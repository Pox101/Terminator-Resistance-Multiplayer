param([ValidateSet('host','client')][string]$Role,[ValidateSet('coop','pvp')][string]$Mode='coop',[ValidateSet('arena','infiltrator_hunt')][string]$Scenario='arena',[ValidateSet('loopback','steam','tunnel_test')][string]$Transport='loopback',[ValidatePattern('^[0-9]{1,20}$')][string]$LobbyId)
$ErrorActionPreference='Stop'
function Start-Role([string]$Target,[string]$GameMode,[string]$ScenarioName='arena',[string]$Network='loopback') {
    if($Network -ne 'loopback'){$GameMode='pvp';$ScenarioName='infiltrator_hunt'}
    $config=Join-Path $PSScriptRoot "runtime\$Target\Terminator\Binaries\Win64\Mods\TRMPProbe\Scripts\config.lua"
    if(-not (Test-Path -LiteralPath $config)){throw 'Run Install-Mod.cmd first.'}
    $text=Get-Content -LiteralPath $config -Raw
    $text=$text -replace "mode='(coop|pvp)'","mode='$GameMode'"
    if($text -match "scenario='[^']*'") {$text=$text -replace "scenario='[^']*'","scenario='$ScenarioName'"}
    else {$text=$text -replace '}\s*$',",scenario='$ScenarioName'}"}
    if($text -match "transport='[^']*'"){$text=$text -replace "transport='[^']*'","transport='$Network'"}
    else{$text=$text -replace '}\s*$',",transport='$Network'}"}
    [IO.File]::WriteAllText($config,$text)
    $launchParameters=@{Role=$Target}
    if($LobbyId){$launchParameters.LobbyId=$LobbyId}
    & (Join-Path $PSScriptRoot 'Start-Test.ps1') @launchParameters
}
if($Role){Start-Role $Role $Mode $Scenario $Transport;return}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$form=New-Object Windows.Forms.Form
$form.Text='Resistance Multiplayer - Local Preview'
$form.Size=New-Object Drawing.Size(540,485)
$form.StartPosition='CenterScreen';$form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false
$label=New-Object Windows.Forms.Label
$label.Text="Local preview: both games run on this PC.`r`n1. Start a host, then Play > Continue in the game.`r`n2. Click 'Host loaded save' and finish its loading screen.`r`n3. Start player two, click Join, then finish its loading screen.`r`nPvP is first person. Co-op also allows third person (F5)."
$label.SetBounds(20,15,490,105);$form.Controls.Add($label)
$status=New-Object Windows.Forms.Label;$status.SetBounds(20,370,490,60);$status.Text='Infiltrator: Play > New Infiltrator Mode. Steam Versus is an experimental relay test requiring a separate authenticated peer.';$form.Controls.Add($status)
function Add-Button([string]$Text,[int]$X,[int]$Y,[scriptblock]$Action) {
    $button=New-Object Windows.Forms.Button;$button.Text=$Text;$button.SetBounds($X,$Y,235,38)
    $handler={try{& $Action;$status.Text='Done. Continue in the selected game window.'}catch{$status.Text=$_.Exception.Message}}.GetNewClosure()
    $button.Add_Click($handler);$form.Controls.Add($button)
}
Add-Button 'Start co-op host' 20 125 {Start-Role 'host' 'coop'}
Add-Button 'Start PvP host' 265 125 {Start-Role 'host' 'pvp'}
Add-Button 'Host loaded save' 20 170 {& (Join-Path $PSScriptRoot 'Send-TestCommand.ps1') host host}
Add-Button 'Start player two' 265 170 {Start-Role 'client' 'coop'}
Add-Button 'Join player two' 20 215 {& (Join-Path $PSScriptRoot 'Send-TestCommand.ps1') client join}
Add-Button 'Start Infiltrator mission host' 20 265 {Start-Role 'host' 'pvp' 'infiltrator_hunt'}
Add-Button 'Play a Resistance NPC' 265 265 {Start-Role 'client' 'pvp' 'infiltrator_hunt'}
Add-Button 'Steam Versus (experimental)' 20 310 {Start-Role 'host' 'pvp' 'infiltrator_hunt' 'steam'}
Add-Button 'Close both game copies' 265 215 {
    foreach($target in 'client','host') {
        $exe=Join-Path $PSScriptRoot "runtime\$target\Terminator\Binaries\Win64\Terminator-Win64-Shipping.exe"
        if(Get-Process -Name Terminator-Win64-Shipping -ErrorAction SilentlyContinue | Where-Object Path -EQ $exe){& (Join-Path $PSScriptRoot 'Send-TestCommand.ps1') $target quit}
    }
}
[void]$form.ShowDialog()
