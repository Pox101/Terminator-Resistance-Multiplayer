param([ValidateSet('host','client')][string]$Role = 'host', [string]$Map,[ValidatePattern('^[0-9]{1,20}$')][string]$LobbyId,[switch]$NoDiagnostics)
$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot "runtime\$Role"
$exe = Join-Path $root 'Terminator\Binaries\Win64\Terminator-Win64-Shipping.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw 'Run Prepare-Test.ps1 first.' }
$expectedHash = '5A01BBEE102990B1B1108C8656994ED19D46A9B2735C3B3A11EB9C7921CAFDB4'
if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne $expectedHash) {
    throw 'Unsupported game build: the prototype initialization helper requires the verified executable.'
}
if (-not (Test-Path -LiteralPath (Join-Path $root 'prototype_runtime.dll'))) { throw 'Run Build-Native.cmd and Prepare-Test.ps1 first.' }
if (-not (Test-Path -LiteralPath (Join-Path $root 'prototype_input.dll'))) { throw 'Run Build-Native.cmd and Prepare-Test.ps1 first.' }
$existing = Get-Process -Name 'Terminator-Win64-Shipping' -ErrorAction SilentlyContinue | Where-Object Path -EQ $exe
if ($existing) { throw "$Role is already running." }
$config=Get-Content -LiteralPath (Join-Path $root 'Terminator\Binaries\Win64\Mods\TRMPProbe\Scripts\config.lua') -Raw
$transport='loopback'
if($config -match "transport='(steam|tunnel_test)'"){$transport=$Matches[1]}
[IO.File]::WriteAllText((Join-Path $root 'network-mode.txt'),$transport)
if($transport -ne 'loopback') {
    $pakRoot=Join-Path $root 'Terminator\Content\Paks'
    [string[]]$pakEntries=@(Get-ChildItem -LiteralPath $pakRoot -File -Recurse -Filter '*.pak' | ForEach-Object {
        $_.FullName.Substring($pakRoot.Length+1).Replace('\','/').ToLowerInvariant()+':'+$_.Length
    })
    if(-not $pakEntries.Count){throw 'Installed game content was not found.'}
    [Array]::Sort($pakEntries,[StringComparer]::Ordinal)
    $scriptRoot=Join-Path $root 'Terminator\Binaries\Win64\Mods\TRMPProbe\Scripts'
    [string[]]$modEntries=@(Get-ChildItem -LiteralPath $scriptRoot -File -Filter '*.lua' | Where-Object Name -NE 'config.lua' | ForEach-Object {
        $_.Name.ToLowerInvariant()+':'+(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    })
    foreach($name in 'prototype_runtime.dll','prototype_input.dll','steam_lobby.dll','steam_probe.dll'){
        $modEntries+=$name+':'+(Get-FileHash -LiteralPath (Join-Path $root $name) -Algorithm SHA256).Hash
    }
    [Array]::Sort($modEntries,[StringComparer]::Ordinal)
    $bytes=[Text.Encoding]::UTF8.GetBytes($expectedHash+"`n"+($pakEntries -join "`n")+"`n"+($modEntries -join "`n"))
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$fingerprint=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
    [IO.File]::WriteAllText((Join-Path $root 'content-fingerprint.txt'),$fingerprint)
}
$inviteFile=Join-Path $root 'steam-invite.txt'
if($LobbyId){[IO.File]::WriteAllText($inviteFile,$LobbyId)}elseif(Test-Path -LiteralPath $inviteFile){Remove-Item -LiteralPath $inviteFile}
if (Test-Path -LiteralPath (Join-Path $root 'command.txt')) {
    Move-Item -LiteralPath (Join-Path $root 'command.txt') -Destination (Join-Path $root ('stale-command-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.txt'))
}
$x = if ($Role -eq 'host') { 20 } else { 840 }
$gameArgs = @('-windowed','-ResX=800','-ResY=450',"-WinX=$x",'-WinY=60','-nosplash','-nosteam','-NoVSync', ('-UserDir="' + (Join-Path $root 'profile') + '"'), ('-abslog="' + (Join-Path $root 'engine.log') + '"'))
# Selecting IpNetDriver alone does not stop Steam from becoming the default
# socket subsystem. Apply this before the online subsystem initializes.
$engineConfig = Join-Path $root 'profile\Saved\Config\WindowsNoEditor\Engine.ini'
New-Item -ItemType Directory -Path (Split-Path $engineConfig) -Force | Out-Null
@'
[OnlineSubsystemSteam]
bUseSteamNetworking=false

[/Script/Engine.GameEngine]
!NetDriverDefinitions=ClearArray
+NetDriverDefinitions=(DefName="GameNetDriver",DriverClassName="/Script/OnlineSubsystemUtils.IpNetDriver",DriverClassNameFallback="/Script/OnlineSubsystemUtils.IpNetDriver")
'@ | Set-Content -LiteralPath $engineConfig -Encoding ascii
$gameArgs += '-ENGINEINI="' + $engineConfig + '"'
$gameArgs += '-MULTIHOME=127.0.0.1'
if (Test-Path -LiteralPath (Join-Path $root 'TestGameUserSettings.ini')) {
    $gameArgs += '-GAMEUSERSETTINGSINI="' + (Join-Path $root 'TestGameUserSettings.ini') + '"'
}
if ($Map) { $gameArgs = @($Map) + $gameArgs }
Import-Module (Join-Path $PSScriptRoot 'Diagnostics.psm1') -Force
[void](Assert-TrmpPlainPath $root)
foreach($name in @('diagnostic-session-id.txt','diagnostic-events.jsonl','diagnostic-events.jsonl.1','diagnostic-heartbeat.json','probe.log','probe.log.1')){[void](Assert-TrmpPlainPath (Join-Path $root $name))}
$previous=Get-TrmpJson (Join-Path $root 'diagnostic-session.json')
if(-not$NoDiagnostics -and $previous -and -not(Get-TrmpProperty $previous 'finishedUtc')){
    try{[void](New-TrmpReport $root $previous $null 'recovery')}catch{Write-Warning 'Previous local report could not be recovered.'}
}
$sessionId=[guid]::NewGuid().ToString()
$sessionIdPath=Join-Path $root 'diagnostic-session-id.txt'
if($NoDiagnostics){if(Test-Path -LiteralPath $sessionIdPath){Remove-Item -LiteralPath $sessionIdPath}}
else{[IO.File]::WriteAllText($sessionIdPath,$sessionId)}
$sessionVersion='unknown';$manifestPath=Join-Path $PSScriptRoot 'payload-manifest.json'
if(Test-Path -LiteralPath $manifestPath){$sessionVersion=(Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json).version}
$sessionMode='unknown';if($config -match "mode='(coop|pvp)'"){$sessionMode=$Matches[1]}
# These are interactive test windows so the tester can switch keyboard control.
$process = Start-Process -FilePath $exe -ArgumentList $gameArgs -WorkingDirectory (Split-Path $exe) -WindowStyle Normal -PassThru
$process.Id | Set-Content -LiteralPath (Join-Path $root 'process-id.txt')
$packageHash=$null;if(Test-Path -LiteralPath $manifestPath){$packageHash=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()}
$session=[pscustomobject]@{id=$sessionId;role=$Role;processId=$process.Id;startTicks=$process.StartTime.ToUniversalTime().Ticks;startedUtc=$process.StartTime.ToUniversalTime().ToString('o');version=$sessionVersion;transport=$transport;mode=$sessionMode;packageHash=$packageHash}
if(-not$NoDiagnostics){
Write-TrmpJson (Join-Path $root 'diagnostic-session.json') $session
$watcher=Join-Path $PSScriptRoot 'Watch-Game.ps1'
try{
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList @('-NoProfile','-File',('"'+$watcher+'"'),'-Role',$Role,'-SessionId',$sessionId,'-ShowNotice') -WindowStyle Hidden | Out-Null
}catch{Write-Warning 'Local crash watcher did not start. Diagnostic reports can still be prepared manually.'}
Write-Output 'Local diagnostics enabled. Nothing is uploaded; review reports in the launcher before sharing.'
}else{Write-Output 'Automatic diagnostic reports disabled for this launch. Existing private game/mod logs still apply.'}
Write-Output "$Role started with PID $($process.Id)."
