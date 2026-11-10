param([Parameter(Mandatory)][ValidateSet('host','client')][string]$Role, [Parameter(Mandatory)][string]$Command)
$ErrorActionPreference = 'Stop'
if ($Command -notmatch '^(host|host-menu|experiment|join|status|move|view|vision|quit|fire|reload|combat-status|mode (coop|pvp)|map /Game/[A-Za-z0-9_/]+)$') { throw 'Supported: host, host-menu, experiment, join, status, move, view, vision, quit, fire, reload, combat-status, mode coop/pvp, map /Game/path' }
$root = Join-Path $PSScriptRoot "runtime\$Role"
if (Test-Path -LiteralPath (Join-Path $root 'command.txt')) { throw 'Previous command has not been consumed yet.' }
$temp = Join-Path $root 'command.tmp'
[IO.File]::WriteAllText($temp, $Command)
Move-Item -LiteralPath $temp -Destination (Join-Path $root 'command.txt')
