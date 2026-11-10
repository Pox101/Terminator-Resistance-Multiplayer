param([string]$Version='0.3.0-steam-menu-preview')
$ErrorActionPreference='Stop'
if($Version -notmatch '^[0-9A-Za-z][0-9A-Za-z.-]{0,60}$'){throw 'Invalid version.'}
$dist=Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$stage=Join-Path $dist ('stage-'+$Version+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $stage | Out-Null
$files=@('Install-Mod.ps1','Install-Mod.cmd','Launch-Mod.ps1','Launch-Mod.cmd','Start-Test.ps1','Send-TestCommand.ps1','README.md','LICENSE','THIRD-PARTY-NOTICES.txt',
    'mod/Scripts/main.lua','mod/Scripts/prototype.lua','mod/Scripts/bodies.lua','mod/Scripts/combat.lua','mod/Scripts/combat_rules.lua','mod/Scripts/scenario_rules.lua','mod/Scripts/scenario_runtime.lua','mod/Scripts/mission_rules.lua','mod/Scripts/infiltrator_mission.lua','mod/Scripts/geometry_sync.lua','mod/Scripts/npc_weapon.lua','mod/Scripts/scheduler.lua','mod/Scripts/lobby_state.lua','mod/Scripts/versus_menu.lua',
    'native/prototype_runtime.dll','native/prototype_input.dll','native/steam_probe.dll','native/steam_lobby.dll')
$manifest=@(foreach($relative in $files) {
    $source=Join-Path $PSScriptRoot $relative
    if(-not (Test-Path -LiteralPath $source)){throw "Missing release file: $relative"}
    $target=Join-Path $stage $relative
    New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target
    [pscustomobject]@{path=$relative;sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash}
})
New-Item -ItemType Directory -Path (Join-Path $stage 'licenses') | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'third_party/gamenetworkingsockets/LICENSE') -Destination (Join-Path $stage 'licenses/GameNetworkingSockets-LICENSE.txt')
$manifest+=[pscustomobject]@{path='licenses/GameNetworkingSockets-LICENSE.txt';sha256=(Get-FileHash -LiteralPath (Join-Path $stage 'licenses/GameNetworkingSockets-LICENSE.txt')).Hash}
[pscustomobject]@{product='TRMP-LocalPreview';version=$Version;transport='loopback';protocol='TRMP1';files=$manifest} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stage 'payload-manifest.json') -Encoding utf8
$forbidden=@(Get-ChildItem -LiteralPath $stage -Recurse -File | Where-Object {$_.Extension -in '.sav','.pak','.exe','.dmp','.log' -or $_.FullName -match '[\\/](profile|backups|screenshots|\.codex-attachments)[\\/]'})
if($forbidden.Count){throw 'Release contains forbidden data.'}
$archive=Join-Path $dist "TRMP-$Version.zip"
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $archive -Force
$hash=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
"$hash  $([IO.Path]::GetFileName($archive))" | Set-Content -LiteralPath (Join-Path $dist 'SHA256SUMS.txt') -Encoding ascii
Write-Output $archive
Write-Output "SHA256 $hash"
