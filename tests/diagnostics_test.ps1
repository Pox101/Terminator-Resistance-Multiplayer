$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'Diagnostics.psm1') -Force
$fixture=Join-Path $root ('runtime\diagnostics-tests\'+[guid]::NewGuid().ToString())
[void][IO.Directory]::CreateDirectory($fixture)
$script:checks=0
function Check($Condition,[string]$Label){if(-not$Condition){throw "FAIL: $Label"};$script:checks++}
function Put([string]$Name,[string]$Text){$p=Join-Path $fixture $Name;[void][IO.Directory]::CreateDirectory((Split-Path $p -Parent));[IO.File]::WriteAllText($p,$Text)}
$id=[guid]::NewGuid().ToString();$session=[pscustomobject]@{id=$id;role='host';processId=12345;version='0.6.0-steam-dev';transport='steam';mode='pvp';startedUtc=[datetime]::UtcNow.AddMinutes(-5).ToString('o')}
$secret='SECRET_SENTINEL';$stamp=[datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
$event=[pscustomobject]@{session=$id;utc=$stamp;seq=1;event='mission_phase';value='failed';secret=$secret}
Check ($null-ne(Get-TrmpSafeEvent $event $id)) 'valid projected event'
$event.value=$secret;Check ($null-eq(Get-TrmpSafeEvent $event $id)) 'freeform value rejected';$event.value='failed'
Check ($null-eq(Get-TrmpSafeEvent $event ([guid]::NewGuid().ToString()))) 'other session excluded'
Put 'diagnostic-events.jsonl' (($event|ConvertTo-Json -Compress)+"`n"+('{"session":"'+$id+'","utc":"'+$stamp+'","seq":2,"event":"account","value":"'+$secret+'"}'))
Put 'steam-lobby-state.txt' 'TRMP_LOBBY1|lobby_ready|0|2|109775244129945387|1'
Put 'steam-network-state.txt' 'TRMP_STEAM1|100|100|1|3|1|1'
$xml=@"
<FGenericCrashContext><RuntimeProperties><ProcessId>12345</ProcessId><CrashType>Crash</CrashType><ErrorMessage>Unhandled Exception: EXCEPTION_ACCESS_VIOLATION writing address 0x12345678 $secret</ErrorMessage><UserName>$secret</UserName><LoginId>$secret</LoginId><CommandLine>C:/Users/$secret -token $secret</CommandLine><PCallStack>
UE4SS 0x00007fff12340000 + 123abc
Terminator-Win64-Shipping 0x00007fff45670000 + 2089ed0
PRIVATE_MODULE_$secret 0x00007fff12340000 + 123
</PCallStack></RuntimeProperties></FGenericCrashContext>
"@
$crashName='profile\Saved\Crashes\UE4CC-Windows-ABCDEF_0000\CrashContext.runtime-xml';Put $crashName $xml
$crash=Get-TrmpCrash $fixture $session ([datetime]::UtcNow)
Check ($crash.exceptionClass-eq'access_violation') 'crash exception classified'
Check ($crash.frames.Count-eq2-and$crash.frames[0]-eq'UE4SS+0x123abc') 'module relative stack only'
$report=New-TrmpReport $fixture $session -1073741819 'automatic';$content=Read-TrmpBounded $report
Check ($content -notmatch "$secret|109775244129945387|0x00007fff|0x12345678|UserName|CommandLine") 'no identifiers/path/absolute addresses/free text exported'
$data=($content.Substring($content.IndexOf('{'))|ConvertFrom-Json)
Check ($data.durationSeconds-ge299-and$data.durationSeconds-le330) 'timestamps parsed independently of locale/PS JSON date conversion'
Check ($data.events.Count-eq1-and$data.crash.frames.Count-eq2-and$data.causeConfirmed-eq$false) 'minimal evidence report, no invented cause'
Check ($data.lobby.members-eq2-and$data.network.authenticatedRelay) 'network status preserved without lobby identity'
$signature=$data.signature
$session.startedUtc=[datetime]::Parse($session.startedUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)
$path=New-TrmpReport $fixture $session -1073741819 'automatic';$asDate=Read-TrmpBounded $path;$asDateData=$asDate.Substring($asDate.IndexOf('{'))|ConvertFrom-Json
Check ($asDateData.durationSeconds-ge299-and$asDateData.durationSeconds-le330) 'DateTime input uses UTC without locale string round-trip'
$event.utc='2026-01-01T00:00:00Z';Put 'diagnostic-events.jsonl' ($event|ConvertTo-Json -Compress)
$path=New-TrmpReport $fixture $session -1073741819 'automatic';$next=Read-TrmpBounded $path;$nextData=$next.Substring($next.IndexOf('{'))|ConvertFrom-Json
Check ($nextData.signature-eq$signature) 'crash grouping excludes timestamps/addresses'
Put $crashName ($xml.Replace('<ProcessId>12345</ProcessId>','<ProcessId>99999</ProcessId>'))
Check ($null-eq(Get-TrmpCrash $fixture $session ([datetime]::UtcNow))) 'unrelated process crash excluded'
Check ($null-eq(New-TrmpReport $fixture $session 0 'automatic')) 'normal exit produces no automatic report'
$path=New-TrmpReport $fixture $session 7 'automatic';Check ((Read-TrmpBounded $path)-match'unexpected_exit_or_forced_stop') 'forced stop not falsely called proven crash'
Put $crashName '<!DOCTYPE x [<!ENTITY leak SYSTEM "file:///C:/sensitive">]><FGenericCrashContext>&leak;</FGenericCrashContext>'
Check ($null-eq(Get-TrmpCrash $fixture $session ([datetime]::UtcNow))) 'XML external entities prohibited'
Put 'too-large.txt' ('x'*1001);Check ($null-eq(Read-TrmpBounded (Join-Path $fixture 'too-large.txt') 1000)) 'bounded input reads'
Put 'outside\private.txt' $secret
New-Item -ItemType Junction -Path (Join-Path $fixture 'linked') -Target (Join-Path $fixture 'outside')|Out-Null
$blocked=$false;try{Read-TrmpBounded (Join-Path $fixture 'linked\private.txt')|Out-Null}catch{$blocked=$true}
Check $blocked 'linked input rejected without reading target'
Put 'engine.log' $secret;Put 'prototype-runtime.log' $secret;Put 'profile\Saved\Crashes\UE4CC-Windows-ABCDEF_0000\UE4Minidump.dmp' $secret
$session.version=@('0.6.0','SECRET_SENTINEL');$path=New-TrmpReport $fixture $session 7 'automatic';Check ((Read-TrmpBounded $path)-notmatch$secret) 'poisoned version arrays excluded';$session.version='0.6.0-steam-dev'
foreach($i in 1..23){$session.id=[guid]::NewGuid().ToString();[void](New-TrmpReport $fixture $session 7 'automatic')}
Check (@(Get-ChildItem (Join-Path $fixture 'reports') -File).Count-eq20) 'report retention bounded'
Check ((Get-ChildItem -LiteralPath (Join-Path $fixture 'reports') -File | Sort-Object Length -Descending | Select-Object -First 1).Length -lt 262144) 'shareable report remains bounded'

# Run the real watcher against a harmless, purpose-built child process. No
# game crash is induced and no user process is killed/inspected.
$watchRoot=Join-Path $fixture 'watcher'
$bin=Join-Path $watchRoot 'runtime\host\Terminator\Binaries\Win64'
[void][IO.Directory]::CreateDirectory($bin)
Copy-Item -LiteralPath (Join-Path $root 'Watch-Game.ps1'),(Join-Path $root 'Diagnostics.psm1') -Destination $watchRoot
$childExe=Join-Path $bin 'Terminator-Win64-Shipping.exe'
Add-Type -TypeDefinition 'public class TRMPDiagnosticChild { public static int Main(string[] args) { System.Threading.Thread.Sleep(2000); return int.Parse(args[0]); } }' -OutputAssembly $childExe -OutputType ConsoleApplication
foreach($code in @(0,7)){
    $child=Start-Process -FilePath $childExe -ArgumentList @([string]$code) -PassThru -WindowStyle Hidden
    $watchSession=[pscustomobject]@{id=[guid]::NewGuid().ToString();role='host';processId=$child.Id;startTicks=$child.StartTime.ToUniversalTime().Ticks;startedUtc=$child.StartTime.ToUniversalTime().ToString('o');version='0.6.0-steam-dev';mode='pvp';transport='loopback'}
    Write-TrmpJson (Join-Path $watchRoot 'runtime\host\diagnostic-session.json') $watchSession
    & (Join-Path $watchRoot 'Watch-Game.ps1') -Role host -SessionId $watchSession.id
    $reportPath=Join-Path $watchRoot ('runtime\host\reports\TRMP-report-'+$watchSession.id+'.txt')
    Check ((Test-Path -LiteralPath $reportPath)-eq($code-ne0)) "watcher normal/abnormal exit $code"
    $finished=Get-TrmpJson (Join-Path $watchRoot 'runtime\host\diagnostic-session.json')
    Check ($finished.exitCode-eq$code-and$null-ne$finished.finishedUtc) 'watcher stores actual exit status then exits'
}
$watchSession.id=[guid]::NewGuid().ToString();$watchSession.processId=$PID;$watchSession.startTicks=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks
Write-TrmpJson (Join-Path $watchRoot 'runtime\host\diagnostic-session.json') $watchSession
& (Join-Path $watchRoot 'Watch-Game.ps1') -Role host -SessionId $watchSession.id
Check (-not(Test-Path -LiteralPath (Join-Path $watchRoot ('runtime\host\reports\TRMP-report-'+$watchSession.id+'.txt')))) 'watcher refuses unrelated process identity'
Write-Output "PASS: $script:checks diagnostic privacy/parser/crash-isolation/retention checks"
