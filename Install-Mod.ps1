param(
    [string]$GameRoot,
    [string]$DestinationRoot = (Join-Path $env:LOCALAPPDATA 'TRMP-LocalPreview'),
    [string]$DependencyArchive,
    [switch]$NoSaveImport,
    [switch]$OpenFolder
)
$ErrorActionPreference='Stop'
$expectedGameHash='5A01BBEE102990B1B1108C8656994ED19D46A9B2735C3B3A11EB9C7921CAFDB4'
$loaderHash='4B47D4BCEDDD2F561A4E395BFA00924CCFC945AF576A2D0C613E6537846C57EC'
$loaderUrl='https://github.com/UE4SS-RE/RE-UE4SS/releases/download/v3.0.1/UE4SS_v3.0.1.zip'
function FullPath([string]$Path) { [IO.Path]::GetFullPath($Path).TrimEnd('\') }
function Inside([string]$Path,[string]$Root) {
    $Path.Equals($Root,[StringComparison]::OrdinalIgnoreCase) -or $Path.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase)
}
function PlainDirectory([string]$Path) {
    if(Test-Path -LiteralPath $Path) {
        if((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {throw "Managed directory cannot be a link: $Path"}
    } else {New-Item -ItemType Directory -Path $Path -Force | Out-Null}
}
if(-not $GameRoot) {
    $steam=(Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    $libraries=@($steam)
    if($steam -and (Test-Path -LiteralPath (Join-Path $steam 'steamapps\libraryfolders.vdf'))) {
        $vdf=Get-Content -LiteralPath (Join-Path $steam 'steamapps\libraryfolders.vdf') -Raw
        foreach($match in [regex]::Matches($vdf,'"path"\s+"([^"]+)"')) {$libraries+=$match.Groups[1].Value.Replace('\\','\')}
    }
    foreach($library in $libraries) {
        if(-not $library){continue}
        $candidate=Join-Path $library 'steamapps\common\Terminator Resistance'
        if(Test-Path -LiteralPath (Join-Path $candidate 'Terminator\Binaries\Win64\Terminator-Win64-Shipping.exe')) {$GameRoot=$candidate;break}
    }
}
if(-not $GameRoot) {throw 'Game not found. Run Install-Mod.ps1 -GameRoot with your Terminator Resistance folder.'}
$GameRoot=FullPath $GameRoot
$DestinationRoot=FullPath $DestinationRoot
$ancestor=$DestinationRoot
while($ancestor) {
    if((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'Installation path must not pass through a directory link.'}
    $parent=Split-Path $ancestor -Parent
    if($parent -eq $ancestor){break};$ancestor=$parent
}
$originalSaves=FullPath (Join-Path $env:LOCALAPPDATA 'Terminator\Saved')
if((Inside $DestinationRoot $GameRoot) -or (Inside $GameRoot $DestinationRoot) -or
   (Inside $DestinationRoot $originalSaves) -or (Inside $originalSaves $DestinationRoot)) {throw 'Choose a separate installation folder outside the game and original saves.'}
$exe=Join-Path $GameRoot 'Terminator\Binaries\Win64\Terminator-Win64-Shipping.exe'
if(-not (Test-Path -LiteralPath $exe) -or (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne $expectedGameHash) {throw 'Unsupported game build. Nothing was installed.'}
$manifestFile=Join-Path $PSScriptRoot 'payload-manifest.json'
if(-not (Test-Path -LiteralPath $manifestFile)) {throw 'Use an extracted release archive. Source developers must build/package the release first.'}
$manifest=Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json
foreach($entry in $manifest.files) {
    $source=FullPath (Join-Path $PSScriptRoot $entry.path)
    if(-not (Inside $source (FullPath $PSScriptRoot)) -or $entry.path -match '(^|[/\\])\.\.([/\\]|$)') {throw 'Invalid release path.'}
    if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $entry.sha256) {throw "Release integrity check failed: $($entry.path)"}
}
if(Test-Path -LiteralPath $DestinationRoot) {
    $marker=Join-Path $DestinationRoot 'installation.json'
    if(-not (Test-Path -LiteralPath $marker) -and (Test-Path -LiteralPath (Join-Path $DestinationRoot 'pending-install.json'))) {$marker=Join-Path $DestinationRoot 'pending-install.json'}
    if(-not (Test-Path -LiteralPath $marker) -and @(Get-ChildItem -LiteralPath $DestinationRoot -Force).Count) {throw 'Destination is not an empty folder or an existing TRMP installation.'}
    if(Test-Path -LiteralPath $marker) {
        $old=Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
        if($old.product -ne 'TRMP-LocalPreview' -or $old.gameRoot -ne $GameRoot) {throw 'Installation marker does not match this game.'}
    }
}
$running=@(Get-Process -Name 'Terminator-Win64-Shipping' -ErrorAction SilentlyContinue | Where-Object { $_.Path -and (Inside $_.Path $DestinationRoot) })
if($running.Count){throw 'Close the preview game copies before installing/updating.'}
PlainDirectory $DestinationRoot
[pscustomobject]@{product='TRMP-LocalPreview';gameRoot=$GameRoot;phase='installing'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $DestinationRoot 'pending-install.json') -Encoding utf8
foreach($part in 'cache','native','mod','runtime','licenses'){PlainDirectory (Join-Path $DestinationRoot $part)}
PlainDirectory (Join-Path $DestinationRoot 'mod\Scripts')
if(-not $DependencyArchive) {
    $DependencyArchive=Join-Path $DestinationRoot 'cache\UE4SS_v3.0.1.zip'
    if(-not (Test-Path -LiteralPath $DependencyArchive)) {
        [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $loaderUrl -OutFile $DependencyArchive -UseBasicParsing
    }
}
if((Get-FileHash -LiteralPath $DependencyArchive -Algorithm SHA256).Hash -ne $loaderHash) {throw 'UE4SS archive checksum mismatch. Installation stopped.'}
# Copy only the declared release payload. No working-folder recursion.
foreach($entry in $manifest.files) {
    $destination=FullPath (Join-Path $DestinationRoot $entry.path)
    if(-not (Inside $destination $DestinationRoot)){throw 'Invalid destination.'}
    PlainDirectory (Split-Path $destination)
    if((Test-Path -LiteralPath $destination) -and ((Get-Item -LiteralPath $destination -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'Refusing to overwrite a linked file.'}
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $entry.path) -Destination $destination -Force
}
Copy-Item -LiteralPath $manifestFile -Destination (Join-Path $DestinationRoot 'payload-manifest.json') -Force
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead((FullPath $DependencyArchive))
try {
    foreach($role in 'host','client') {
        $root=Join-Path $DestinationRoot "runtime\$role"
        foreach($relative in @('','Terminator','Terminator\Binaries','Terminator\Binaries\Win64','Terminator\Binaries\Win64\Mods','Terminator\Binaries\Win64\Mods\TRMPProbe','Terminator\Binaries\Win64\Mods\TRMPProbe\Scripts','profile','profile\Saved')) {
            PlainDirectory (Join-Path $root $relative)
        }
        $bin=Join-Path $root 'Terminator\Binaries\Win64'
        foreach($entry in $zip.Entries) {
            $relative=$entry.FullName.Replace('/','\')
            if($relative.EndsWith('\')){continue}
            if($relative -notin @('UE4SS.dll','dwmapi.dll','UE4SS-settings.ini') -and -not $relative.StartsWith('Mods\shared\',[StringComparison]::Ordinal)) {continue}
            $target=FullPath (Join-Path $bin $relative)
            if(-not (Inside $target $bin)){throw 'Invalid dependency entry.'}
            # Every parent beneath the managed binary directory must be plain.
            $parts=(Split-Path $relative).Split('\',[StringSplitOptions]::RemoveEmptyEntries)
            $parent=$bin
            foreach($part in $parts){$parent=Join-Path $parent $part;PlainDirectory $parent}
            if((Test-Path -LiteralPath $target) -and ((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Linked dependency destination.'}
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$true)
        }
        Copy-Item -LiteralPath $exe -Destination $bin -Force
        foreach($link in @(@('Engine','Engine'),@('Terminator\Content','Terminator\Content'))) {
            $path=Join-Path $root $link[0];$target=Join-Path $GameRoot $link[1]
            if(Test-Path -LiteralPath $path) {
                $item=Get-Item -LiteralPath $path -Force
                if(-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (FullPath @($item.Target)[0]) -ne (FullPath $target)) {throw 'Existing content link does not match the game.'}
            } else {New-Item -ItemType Junction -Path $path -Target $target | Out-Null}
        }
        foreach($name in 'prototype_runtime.dll','prototype_input.dll','steam_probe.dll','steam_lobby.dll') {
            Copy-Item -LiteralPath (Join-Path $DestinationRoot "native\$name") -Destination $root -Force
        }
        Copy-Item -Path (Join-Path $DestinationRoot 'mod\Scripts\*.lua') -Destination (Join-Path $bin 'Mods\TRMPProbe\Scripts') -Force
        $luaPath=$root.Replace('\','/').Replace("'","\'")
        "return {role='$role',directory='$luaPath',prototypePawn=true,nativeHudGuard=false,fullBodies=true,combatEnabled=true,mode='coop'}" | Set-Content -LiteralPath (Join-Path $bin 'Mods\TRMPProbe\Scripts\config.lua') -Encoding utf8
        'TRMPProbe : 1' | Set-Content -LiteralPath (Join-Path $bin 'Mods\mods.txt') -Encoding ascii
        '954740' | Set-Content -LiteralPath (Join-Path $bin 'steam_appid.txt') -Encoding ascii
        $settings=Join-Path $bin 'UE4SS-settings.ini'
        $text=Get-Content -LiteralPath $settings -Raw
        $text=$text -replace '(?m)^EnableHotReloadSystem\s*=.*','EnableHotReloadSystem = 0'
        $text=$text -replace '(?m)^ConsoleEnabled\s*=.*','ConsoleEnabled = 0'
        $text=$text -replace '(?m)^GuiConsoleEnabled\s*=.*','GuiConsoleEnabled = 0'
        [IO.File]::WriteAllText($settings,$text)
        $saveSource=Join-Path $originalSaves 'SaveGames'
        $videoSource=Join-Path $originalSaves 'Config\WindowsNoEditor\GameUserSettings.ini'
        $videoTarget=Join-Path $root 'TestGameUserSettings.ini'
        if((Test-Path -LiteralPath $videoSource) -and -not (Test-Path -LiteralPath $videoTarget)) {
            $video=Get-Content -LiteralPath $videoSource -Raw
            $video=$video -replace '(?m)^bUseVSync=.*','bUseVSync=False' -replace '(?m)^FullscreenMode=.*','FullscreenMode=2' -replace '(?m)^PreferredFullscreenMode=.*','PreferredFullscreenMode=2' -replace '(?m)^ResolutionSizeX=.*','ResolutionSizeX=800' -replace '(?m)^ResolutionSizeY=.*','ResolutionSizeY=450'
            [IO.File]::WriteAllText($videoTarget,$video)
        }
        $saveTarget=Join-Path $root 'profile\Saved\SaveGames'
        if(-not $NoSaveImport -and (Test-Path -LiteralPath $saveSource) -and -not (Test-Path -LiteralPath $saveTarget)) {
            Copy-Item -LiteralPath $saveSource -Destination (Join-Path $root 'profile\Saved') -Recurse
            foreach($file in Get-ChildItem -LiteralPath $saveSource -Recurse -File) {
                $relative=$file.FullName.Substring($saveSource.Length+1)
                if((Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath (Join-Path $saveTarget $relative)).Hash) {throw 'Copied save verification failed.'}
            }
        }
        Write-Output "$role prepared. Original saves were only read."
    }
} finally {$zip.Dispose()}
[pscustomobject]@{product='TRMP-LocalPreview';version=$manifest.version;gameRoot=$GameRoot;transport='loopback';installedUtc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $DestinationRoot 'installation.json') -Encoding utf8
Write-Output "Installed to $DestinationRoot"
Write-Output 'Open Launch-Mod.cmd there to start the preview.'
if($OpenFolder){Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList @('"'+$DestinationRoot+'"')}
