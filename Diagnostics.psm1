# No network calls, shell evaluation, dump collection, registry changes or services.
Set-StrictMode -Version 2
$script:Utf8=New-Object Text.UTF8Encoding($false)
function Assert-TrmpPlainPath([string]$Path) {
    $full=[IO.Path]::GetFullPath($Path)
    $walk=$full
    while($walk){
        if(Test-Path -LiteralPath $walk){
            if((Get-Item -LiteralPath $walk -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Diagnostic path crosses a directory/file link.'}
        }
        $parent=Split-Path $walk -Parent;if($parent -eq $walk){break};$walk=$parent
    }
    return $full
}
function Read-TrmpBounded([string]$Path,[int]$Limit=262144) {
    [void](Assert-TrmpPlainPath $Path)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $null}
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try{
        if($stream.Length -gt $Limit){return $null}
        $bytes=New-Object byte[] ($Limit+1);$count=0
        while($count -le $Limit){$n=$stream.Read($bytes,$count,$bytes.Length-$count);if($n -eq 0){break};$count+=$n}
        if($count -gt $Limit){return $null};return $script:Utf8.GetString($bytes,0,$count)
    }finally{$stream.Dispose()}
}
function Write-TrmpJson([string]$Path,$Value) {
    [void](Assert-TrmpPlainPath $Path)
    $temp=$Path+'.tmp';[void](Assert-TrmpPlainPath $temp)
    [IO.File]::WriteAllText($temp,($Value|ConvertTo-Json -Depth 8),$script:Utf8)
    Move-Item -LiteralPath $temp -Destination $Path -Force
}
function Get-TrmpProperty($Object,[string]$Name) {
    if($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]){return $Object.$Name}
    return $null
}
function Get-TrmpJson([string]$Path,[int]$Limit=16384) {
    try{$text=Read-TrmpBounded $Path $Limit;if($text){return ConvertFrom-Json -InputObject $text -ErrorAction Stop}}catch{return $null}
}
function Test-TrmpInteger($Value,[long]$Min=0,[long]$Max=2147483647) {
    return ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) -and $Value -ge $Min -and $Value -le $Max -and $Value -eq [math]::Truncate($Value)
}
function ConvertTo-TrmpUtc($Value) {
    # PowerShell7 deserializes ISO JSON strings as DateTime; Windows PS5.1
    # keeps strings. Never round-trip dates through the machine's locale.
    if($Value -is [datetime]){return $Value.ToUniversalTime()}
    return [datetime]::Parse([string]$Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
}
function Get-TrmpSafeEvent($Value,[string]$Session) {
    if((Get-TrmpProperty $Value 'session') -cne $Session){return $null}
    $name=Get-TrmpProperty $Value 'event';$utc=Get-TrmpProperty $Value 'utc';$seq=Get-TrmpProperty $Value 'seq'
    if($utc -isnot [string] -or $utc -cnotmatch '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$' -or -not(Test-TrmpInteger $seq 1)){return $null}
    $out=[ordered]@{utc=$utc;seq=$seq;event=$name}
    $flags=@('probe_loaded','mission_takeover','mission_defender_eliminated','scenario_host','first_person_hands','versus_menu_opened','versus_menu_entry_added','steam_initial_game_join','selective_local_begin_play_requested','camera_mouse_capture','travel_requested','HandleNetworkError','HandleTravelError')
    $enums=@{mission_phase=@('active','completed','failed');steam_player_role=@('host','client');combat_mode=@('coop','pvp');world=@('menu','infiltrator','other');game_thread_scheduler_ready=@('menu','infiltrator','other');steam_party_ended=@('owner_left','peer_disconnected','transport_failed','incompatible')}
    if($name -cin $flags){return [pscustomobject]$out}
    if($name -is [string] -and $enums.ContainsKey($name)){
        $v=Get-TrmpProperty $Value 'value';if($v -is [string] -and $v -cin $enums[$name]){$out.value=$v;return [pscustomobject]$out};return $null
    }
    if($name -cin @('session_restart_requested','session_restart_waiting','session_restart_rejoin','session_restart_connected','events_suppressed')){
        $n=Get-TrmpProperty $Value 'n';if(Test-TrmpInteger $n){$out.n=$n;return [pscustomobject]$out};return $null
    }
    if($name -ceq 'mission_native_damage'){
        $a=Get-TrmpProperty $Value 'before';$b=Get-TrmpProperty $Value 'after'
        if(($a -is [double] -or $a -is [int] -or $a -is [long]) -and ($b -is [double] -or $b -is [int] -or $b -is [long]) -and $a -ge 0 -and $b -ge 0 -and $a -le 1000000 -and $b -le 1000000){$out.before=$a;$out.after=$b;return [pscustomobject]$out};return $null
    }
    if($name -cin @('scheduler_error','body_error')){
        $v=Get-TrmpProperty $Value 'value';if($v -cnotin @('nil_access','invalid_object','stack_error','other')){return $null};$out.value=$v
        $site=Get-TrmpProperty $Value 'site';$n=Get-TrmpProperty $Value 'n'
        if($site -cin @('main','scheduler','prototype','bodies','combat','infiltrator_mission','npc_weapon','geometry_sync','scenario_runtime','restart_session','steam_session','versus_menu') -and (Test-TrmpInteger $n 0 100000)){$out.site=$site;$out.n=$n}
        return [pscustomobject]$out
    }
    return $null
}
function Get-TrmpCrash([string]$RoleRoot,$Session,[datetime]$EndUtc) {
    $root=Join-Path $RoleRoot 'profile\Saved\Crashes';[void](Assert-TrmpPlainPath $root)
    if(-not(Test-Path -LiteralPath $root)){return $null}
    $start=ConvertTo-TrmpUtc $Session.startedUtc
    $folders=@(Get-ChildItem -LiteralPath $root -Directory | Where-Object {$_.Name -match '^UE4CC-Windows-[A-Fa-f0-9_]{1,80}$'} | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 64)
    foreach($folder in $folders){
        try{
            $path=Join-Path $folder.FullName 'CrashContext.runtime-xml';[void](Assert-TrmpPlainPath $path)
            if(-not(Test-Path -LiteralPath $path)){continue};$item=Get-Item -LiteralPath $path
            if($item.LastWriteTimeUtc -lt $start -or $item.LastWriteTimeUtc -gt $EndUtc.AddSeconds(10)){continue}
            $text=Read-TrmpBounded $path 2097152;if(-not$text){continue}
            $settings=New-Object Xml.XmlReaderSettings;$settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null;$settings.MaxCharactersInDocument=2097152
            $sr=New-Object IO.StringReader($text);$reader=[Xml.XmlReader]::Create($sr,$settings)
            try{$doc=New-Object Xml.XmlDocument;$doc.XmlResolver=$null;$doc.Load($reader)}finally{$reader.Dispose();$sr.Dispose()}
            $props=$doc.SelectSingleNode('/FGenericCrashContext/RuntimeProperties');if(-not$props){continue}
            $pidNode=$props.SelectSingleNode('ProcessId');if(-not$pidNode -or $pidNode.InnerText -cne [string]$Session.processId){continue}
            $errorNode=$props.SelectSingleNode('ErrorMessage');$message=if($errorNode){$errorNode.InnerText}else{''}
            $class='unknown';$code=$null
            if($message -match 'EXCEPTION_ACCESS_VIOLATION'){$class='access_violation';$code='0xc0000005'}
            elseif($message -match '0x[eE]06[dD]7363'){$class='cpp_exception';$code='0xe06d7363'}
            elseif($message -match 'EXCEPTION_STACK_OVERFLOW'){$class='stack_overflow';$code='0xc00000fd'}
            elseif($message -match '(?i)out of (video )?memory|ran out of memory'){$class='out_of_memory'}
            elseif($message -match '(?i)Assertion failed'){$class='assertion'}
            $frames=@();$stackNode=$props.SelectSingleNode('PCallStack')
            if($stackNode){foreach($line in ($stackNode.InnerText -split '\r?\n' | Select-Object -First 128)){
                if($line -cmatch '^\s*(Terminator-Win64-Shipping|UE4SS|prototype_runtime|prototype_input|steam_lobby|steam_probe|KERNELBASE|KERNEL32|ntdll|VCRUNTIME140|ucrtbase)(?:\.dll|\.exe)?\s+0x[0-9A-Fa-f]{1,16}\s+\+\s+([0-9A-Fa-f]{1,8})\s*$'){$frames+=($Matches[1]+'+0x'+$Matches[2].ToLowerInvariant())}
                if($frames.Count -ge 32){break}
            }}
            $crashType=$props.SelectSingleNode('CrashType');$type=if($crashType -and $crashType.InnerText -cin @('Crash','Assert','Ensure','GPUCrash')){$crashType.InnerText}else{'Unknown'}
            return [pscustomobject]@{type=$type;exceptionClass=$class;exceptionCode=$code;frames=$frames}
        }catch{continue} # Malformed/untrusted XML never prevents a minimal report.
    }
    return $null
}
function New-TrmpReport([string]$RoleRoot,$Session,[Nullable[int]]$ExitCode,[string]$Trigger='manual') {
    $RoleRoot=Assert-TrmpPlainPath $RoleRoot
    if($Session.id -isnot [string] -or $Session.role -isnot [string] -or $Session.id -cnotmatch '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$' -or $Session.role -cnotin @('host','client')){throw 'Invalid diagnostic session.'}
    $started=ConvertTo-TrmpUtc $Session.startedUtc;$ended=[datetime]::UtcNow
    $finished=Get-TrmpProperty $Session 'finishedUtc';if($finished){$ended=ConvertTo-TrmpUtc $finished}
    $events=@();foreach($name in @('diagnostic-events.jsonl.1','diagnostic-events.jsonl')){
        $text=Read-TrmpBounded (Join-Path $RoleRoot $name) 263168
        if($text){foreach($line in ($text -split '\n')){
            if($line.Length -gt 2048){continue}
            try{$e=Get-TrmpSafeEvent (ConvertFrom-Json -InputObject $line -ErrorAction Stop) $Session.id;if($e){$events+=$e}}catch{continue}
        }}
    };$events=@($events | Sort-Object seq | Select-Object -Last 200)
    $crash=Get-TrmpCrash $RoleRoot $Session $ended
    $outcome=if($crash){'engine_crash_record'}elseif($null -ne $ExitCode -and $ExitCode -eq 0){'normal_exit'}elseif($Trigger -eq 'manual' -and $null -eq $ExitCode){'manual_snapshot_or_unknown_exit'}else{'unexpected_exit_or_forced_stop'}
    if($Trigger -eq 'automatic' -and $outcome -eq 'normal_exit'){return $null}
    $version=if($Session.version -is [string] -and $Session.version -cmatch '^[0-9A-Za-z][0-9A-Za-z.-]{0,60}$'){$Session.version}else{'unknown'}
    $transport=if($Session.transport -cin @('loopback','steam','tunnel_test')){$Session.transport}else{'unknown'}
    $mode=if($Session.mode -cin @('coop','pvp')){$Session.mode}else{'unknown'}
    $lobby=$null;$network=$null
    $text=Read-TrmpBounded (Join-Path $RoleRoot 'steam-lobby-state.txt') 160
    if((Test-Path -LiteralPath (Join-Path $RoleRoot 'steam-lobby-state.txt')) -and (Get-Item -LiteralPath (Join-Path $RoleRoot 'steam-lobby-state.txt')).LastWriteTimeUtc -ge $started -and $text -cmatch '^TRMP_LOBBY1\|([a-z_]{1,32})\|(\d{1,5})\|([012])\|\d{1,20}\|([01])\s*$'){
        $state=$Matches[1];if($state -cin @('idle','creating','lobby_ready','steam_unavailable','unsupported_api','overlay_unavailable','create_failed','invitation_pending','joining','join_failed','incompatible','transport_connecting','transport_ready','transport_failed','peer_disconnected','owner_left','local_transport_test')){$lobby=@{state=$state;error=[int]$Matches[2];members=[int]$Matches[3];transportReady=$Matches[4] -eq '1'}}
    }
    $text=Read-TrmpBounded (Join-Path $RoleRoot 'steam-network-state.txt') 160
    if((Test-Path -LiteralPath (Join-Path $RoleRoot 'steam-network-state.txt')) -and (Get-Item -LiteralPath (Join-Path $RoleRoot 'steam-network-state.txt')).LastWriteTimeUtc -ge $started -and $text -cmatch '^TRMP_STEAM1\|(-?\d{1,3})\|(-?\d{1,3})\|([01])\|(-?\d{1,2})\|([01])\|([01])\s*$'){
        $network=@{authentication=[int]$Matches[1];relayAvailability=[int]$Matches[2];listener=$Matches[3] -eq '1';connectionState=[int]$Matches[4];authenticatedRelay=$Matches[5] -eq '1';handshake=$Matches[6] -eq '1'}
    }
    $heartbeat=Get-TrmpJson (Join-Path $RoleRoot 'diagnostic-heartbeat.json')
    $age=$null
    if($heartbeat -and (Get-TrmpProperty $heartbeat 'session') -ceq $Session.id){try{$at=ConvertTo-TrmpUtc (Get-TrmpProperty $heartbeat 'utc');$age=[math]::Max(0,[math]::Round(($ended-$at).TotalSeconds))}catch{}}
    $hashes=[ordered]@{};foreach($name in @('prototype_runtime.dll','prototype_input.dll','steam_probe.dll','steam_lobby.dll')){
        $path=Join-Path $RoleRoot $name;[void](Assert-TrmpPlainPath $path)
        if((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Length -le 8388608){$hashes[$name]=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
    $packageHash=Get-TrmpProperty $Session 'packageHash';if($packageHash -isnot [string] -or $packageHash -cnotmatch '^[a-f0-9]{64}$'){$packageHash=$null}
    $signatureInput=$version+'|'+$packageHash+'|'+$outcome
    if($crash){$signatureInput+='|'+$crash.exceptionClass+'|'+($crash.frames -join '|')}
    else{$lastError=@($events|Where-Object {$_.event -in @('scheduler_error','body_error')}|Select-Object -Last 1);if($lastError.Count){foreach($key in @('event','value','site','n')){$signatureInput+='|'+[string](Get-TrmpProperty $lastError[0] $key)}}}
    $sha=[Security.Cryptography.SHA256]::Create();try{$signature=([BitConverter]::ToString($sha.ComputeHash($script:Utf8.GetBytes($signatureInput)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
    $report=[ordered]@{schema='TRMP_REPORT1';reportId=$Session.id;modVersion=$version;packageManifestSha256=$packageHash;protocol='TRMP1';role=$Session.role;transport=$transport;mode=$mode;windowsVersion=[Environment]::OSVersion.Version.ToString();durationSeconds=[math]::Max(0,[math]::Round(($ended-$started).TotalSeconds));outcome=$outcome;exitCode=$ExitCode;signature=$signature;causeConfirmed=$false;crash=$crash;heartbeatAgeSeconds=$age;helpers=$hashes;lobby=$lobby;network=$network;events=$events}
    $reports=Join-Path $RoleRoot 'reports';[void](Assert-TrmpPlainPath $reports);[void][IO.Directory]::CreateDirectory($reports)
    $path=Join-Path $reports ('TRMP-report-'+$Session.id+'.txt')
    $notice="TRMP DIAGNOSTIC REPORT - REVIEW BEFORE SHARING`r`nNothing has been uploaded. Reports posted to GitHub Issues are PUBLIC.`r`nThis is crash evidence, not a confirmed root-cause diagnosis.`r`nNo dumps, saves, raw logs, account IDs, IPs, paths or free text are included.`r`n`r`n"
    [void](Assert-TrmpPlainPath $path);[IO.File]::WriteAllText($path,$notice+($report|ConvertTo-Json -Depth 8),$script:Utf8)
    foreach($old in @(Get-ChildItem -LiteralPath $reports -File | Where-Object {$_.Name -cmatch '^TRMP-report-[a-f0-9-]{36}\.txt$'} | Sort-Object LastWriteTimeUtc -Descending | Select-Object -Skip 20)){
        [void](Assert-TrmpPlainPath $old.FullName);Remove-Item -LiteralPath $old.FullName
    }
    return $path
}
Export-ModuleMember -Function Assert-TrmpPlainPath,Read-TrmpBounded,Write-TrmpJson,Get-TrmpJson,Get-TrmpProperty,Get-TrmpSafeEvent,Get-TrmpCrash,New-TrmpReport
