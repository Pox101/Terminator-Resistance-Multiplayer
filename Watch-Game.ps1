param([Parameter(Mandatory)][ValidateSet('host','client')][string]$Role,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9-]{36}$')][string]$SessionId,
    [switch]$ShowNotice)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Diagnostics.psm1') -Force
$root=Join-Path $PSScriptRoot "runtime\$Role"
try {
    $session=Get-TrmpJson (Join-Path $root 'diagnostic-session.json')
    if(-not$session -or $session.id -cne $SessionId -or $session.role -cne $Role){return}
    $exe=Join-Path $root 'Terminator\Binaries\Win64\Terminator-Win64-Shipping.exe'
    $exitCode=$null;$finishedUtc=[datetime]::UtcNow
    try{$process=[Diagnostics.Process]::GetProcessById([int]$session.processId)}catch{$process=$null}
    if($process){
        # A reused PID must never attach this watcher to an unrelated process.
        if($process.Path -ine $exe -or $process.StartTime.ToUniversalTime().Ticks -ne [long]$session.startTicks){return}
        $null=$process.Handle
        while(-not$process.WaitForExit(2000)){}
        $exitCode=$process.ExitCode;$finishedUtc=$process.ExitTime.ToUniversalTime();$process.Dispose()
    }
    # UE crash context may finish flushing just after the game process exits.
    Start-Sleep -Milliseconds 1500
    $session|Add-Member -NotePropertyName finishedUtc -NotePropertyValue ($finishedUtc.ToString('o')) -Force
    $session|Add-Member -NotePropertyName exitCode -NotePropertyValue $exitCode -Force
    $path=New-TrmpReport $root $session $exitCode 'automatic'
    $current=Get-TrmpJson (Join-Path $root 'diagnostic-session.json')
    if($current -and $current.id -ceq $SessionId){Write-TrmpJson (Join-Path $root 'diagnostic-session.json') $session}
    if($path -and $ShowNotice){
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show("A diagnostic report was prepared locally for this game session.`r`nNothing was uploaded.`r`n`r`nOpen 'Diagnostic reports' in the TRMP launcher to review it before sharing.",'TRMP - local diagnostic report')
    }
}catch{
    # No arbitrary exception text/path/credentials are copied to a shareable file.
    [Console]::Error.WriteLine('TRMP diagnostic watcher could not finish. Use Diagnostic reports in the launcher.')
}
