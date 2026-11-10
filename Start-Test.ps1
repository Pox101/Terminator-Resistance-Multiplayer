param([ValidateSet('host','client')][string]$Role = 'host', [string]$Map)
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
# These are interactive test windows so the tester can switch keyboard control.
$process = Start-Process -FilePath $exe -ArgumentList $gameArgs -WorkingDirectory (Split-Path $exe) -WindowStyle Normal -PassThru
$process.Id | Set-Content -LiteralPath (Join-Path $root 'process-id.txt')
Write-Output "$Role started with PID $($process.Id)."
