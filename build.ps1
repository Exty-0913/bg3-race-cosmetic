param(
    [string]$Divine = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Divine) {
    $Divine = Join-Path (Split-Path -Parent $root) 'modtools\Packed\Tools\Divine.exe'
}
$src  = Join-Path $root 'src'
$dist = Join-Path $root 'Dist'
$pak  = Join-Path $dist 'RaceCosmetic.pak'

if (-not (Test-Path $Divine)) { throw "Divine.exe not found: $Divine" }
New-Item -ItemType Directory -Force -Path $dist | Out-Null

# 1) localization: xml -> loca
foreach ($lang in @('Chinese', 'English')) {
    $xml  = Join-Path $src "Localization\$lang\RaceCosmetic.xml"
    $loca = Join-Path $src "Localization\$lang\RaceCosmetic.loca"
    if (-not (Test-Path $xml)) { throw "missing $xml" }
    if (Test-Path $loca) { Remove-Item $loca -Force }
    & $Divine -g bg3 --action convert-loca -s $xml -d $loca | Out-Null
    if (-not (Test-Path $loca)) { throw "loca generation failed for $lang" }
    "loca  $lang  $((Get-Item $loca).Length) bytes"
}

# 2) pack
if (Test-Path $pak) { Remove-Item $pak -Force }
& $Divine -g bg3 --action create-package -s $src -d $pak | Out-Null
if (-not (Test-Path $pak)) { throw "pak creation failed" }

"pak   $pak  $([math]::Round((Get-Item $pak).Length / 1KB, 1)) KB"
""
"--- package contents ---"
& $Divine -g bg3 --action list-package -s $pak