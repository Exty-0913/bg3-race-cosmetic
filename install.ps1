param(
    [switch]$NoModSettings
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$pak  = Join-Path $root 'Dist\RaceCosmetic.pak'
$mods = Join-Path $env:LOCALAPPDATA "Larian Studios\Baldur's Gate 3\Mods"
$msPath = Join-Path $env:LOCALAPPDATA "Larian Studios\Baldur's Gate 3\PlayerProfiles\Public\modsettings.lsx"

$modUuid  = '7f3c9a12-4d2b-4e8f-9c61-2a5b8e7d4c10'
$modName  = 'RaceCosmetic'
$version64 = '281474976710656'

if (-not (Test-Path $pak)) { throw "pak not found: $pak (run build.ps1 first)" }

$proc = Get-Process -Name 'bg3', 'bg3_dx11' -ErrorAction SilentlyContinue
if ($proc -and -not $NoModSettings) {
    throw "Baldur's Gate 3 is running. Close the game before editing modsettings.lsx (or rerun with -NoModSettings)."
}

# 1) copy the pak
New-Item -ItemType Directory -Force -Path $mods | Out-Null
Copy-Item $pak (Join-Path $mods 'RaceCosmetic.pak') -Force
"installed: $(Join-Path $mods 'RaceCosmetic.pak')"

if ($NoModSettings) {
    "modsettings.lsx untouched (-NoModSettings). Enable 'RaceCosmetic' in BG3 Mod Manager."
    return
}

# 2) register in modsettings.lsx
if (-not (Test-Path $msPath)) { throw "modsettings.lsx not found: $msPath" }

$backup = "$msPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item $msPath $backup -Force
"backup:    $backup"

[xml]$doc = Get-Content -LiteralPath $msPath -Encoding UTF8

$modsNode = $doc.save.region.node.children.node | Where-Object { $_.id -eq 'Mods' }
if (-not $modsNode) { throw "could not locate the Mods node in modsettings.lsx" }

$existing = $modsNode.children.node | Where-Object {
    ($_.attribute | Where-Object { $_.id -eq 'UUID' }).value -eq $modUuid
}

if ($existing) {
    "modsettings.lsx already contains RaceCosmetic, nothing to add."
} else {
    $newNode = $doc.CreateElement('node')
    $newNode.SetAttribute('id', 'ModuleShortDesc')

    $fields = @(
        @{ id = 'Folder';        type = 'LSString'; value = $modName },
        @{ id = 'MD5';           type = 'LSString'; value = '' },
        @{ id = 'Name';          type = 'LSString'; value = $modName },
        @{ id = 'PublishHandle'; type = 'uint64';   value = '0' },
        @{ id = 'UUID';          type = 'guid';     value = $modUuid },
        @{ id = 'Version64';     type = 'int64';    value = $version64 }
    )

    foreach ($f in $fields) {
        $attr = $doc.CreateElement('attribute')
        $attr.SetAttribute('id', $f.id)
        $attr.SetAttribute('type', $f.type)
        $attr.SetAttribute('value', $f.value)
        [void]$newNode.AppendChild($attr)
    }

    [void]$modsNode.children.AppendChild($newNode)

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $settings.Indent = $true

    $writer = [System.Xml.XmlWriter]::Create($msPath, $settings)
    try { $doc.Save($writer) } finally { $writer.Dispose() }

    "modsettings.lsx updated (RaceCosmetic appended at the end of the load order)."
}

""
"Done. If the mod list looks wrong, restore the backup file above."