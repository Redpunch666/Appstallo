# Embed-Icons.ps1 - Bettet PNGs aus icon-catalog\ als Base64 in Appstallo.ps1 ein
[CmdletBinding()]
param(
    [string]$LauncherPath,
    [string]$CatalogDir,
    [switch]$All,
    [switch]$NoPause   # Verhindert Read-Host am Ende (fuer Build-Skripte)
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

function Pause-IfInteractive {
    param([string]$msg = "Druecke ENTER...")
    if ($NoPause) { return }
    # Mehrere Sicherheitspruefungen gegen blockierendes Read-Host
    try {
        if (-not [Environment]::UserInteractive) { return }
        if ([Console]::IsInputRedirected) { return }
        Write-Host $msg -ForegroundColor Yellow
        [void](Read-Host)
    } catch {}
}

$scriptDir = $PSScriptRoot
if (-not $scriptDir) {
    try { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path -EA Stop } catch {}
}
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

if (-not $LauncherPath) { $LauncherPath = Join-Path $scriptDir 'Appstallo.ps1' }
if (-not $CatalogDir)   { $CatalogDir   = Join-Path $scriptDir 'icon-catalog' }

$logFile = Join-Path $scriptDir 'Embed-Icons.log'
function Write-Log {
    param([string]$msg, [string]$color = 'Gray')
    Write-Host $msg -ForegroundColor $color
    try { "$(Get-Date -Format 'HH:mm:ss') $msg" | Add-Content -Path $logFile -Encoding UTF8 -EA SilentlyContinue } catch {}
}

try { "===== Embed-Icons $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') =====" | Set-Content -Path $logFile -Encoding UTF8 } catch {}

Write-Host ""
Write-Host "  Embed-Icons" -ForegroundColor Cyan
if ($All) {
    Write-Host "  Modus: -All (alle PNGs aus icon-catalog\)" -ForegroundColor Cyan
} else {
    Write-Host "  Modus: Standard (nur Mapping-Slugs, schlank)" -ForegroundColor Cyan
}
Write-Host ""

Write-Log "Launcher: $LauncherPath"
Write-Log "Katalog : $CatalogDir"
Write-Host ""

if (-not (Test-Path $LauncherPath)) {
    Write-Log "FEHLER: Appstallo.ps1 nicht gefunden: $LauncherPath" "Red"
    Pause-IfInteractive
    exit 1
}
if (-not (Test-Path $CatalogDir)) {
    Write-Log "FEHLER: Katalog-Ordner nicht gefunden: $CatalogDir" "Red"
    Write-Log "→ Erst 'Build-IconCatalog.ps1' ausfuehren!" "Yellow"
    Pause-IfInteractive
    exit 1
}

$launcherContent = Get-Content -Path $LauncherPath -Raw -Encoding UTF8
$startMarker = '# === EMBEDDED ICONS START ==='
$endMarker   = '# === EMBEDDED ICONS END ==='

if ($launcherContent -notmatch [regex]::Escape($startMarker)) {
    Write-Log "FEHLER: Marker '$startMarker' nicht in Appstallo.ps1." "Red"
    Pause-IfInteractive
    exit 1
}

$allowedSlugs = $null
if (-not $All) {
    Write-Log "Lese Slug-Mapping aus Appstallo.ps1..."
    $patternMap = '\$IconSlugMap\s*=\s*@\{([^}]+)\}'
    $m = [regex]::Match($launcherContent, $patternMap, 'Singleline')
    if (-not $m.Success) {
        Write-Log "FEHLER: \$IconSlugMap-Block nicht gefunden." "Red"
        Pause-IfInteractive
        exit 1
    }
    $mapBlock = $m.Groups[1].Value
    $slugMatches = [regex]::Matches($mapBlock, "'[^']+'\s*=\s*'([a-zA-Z0-9\-]+)'")
    $allowedSlugs = @{}
    foreach ($sm in $slugMatches) { $allowedSlugs[$sm.Groups[1].Value] = $true }
    Write-Log "Mapping enthaelt $($allowedSlugs.Count) eindeutige Slugs" "Green"
}

$pngs = Get-ChildItem -Path $CatalogDir -Filter "*.png" -ErrorAction SilentlyContinue
if (-not $pngs -or $pngs.Count -eq 0) {
    Write-Log "FEHLER: Keine PNG-Dateien in $CatalogDir." "Red"
    Pause-IfInteractive
    exit 1
}
Write-Log "Im Katalog: $($pngs.Count) PNG-Dateien"

if ($allowedSlugs) {
    $pngsToEmbed = @($pngs | Where-Object {
        $slug = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        $allowedSlugs.ContainsKey($slug)
    })
    Write-Log "Nach Filter (nur Mapping-Slugs): $($pngsToEmbed.Count) PNG-Dateien" "Green"
} else {
    $pngsToEmbed = $pngs
    Write-Log "Embed alle: $($pngsToEmbed.Count) PNG-Dateien (-All Modus)" "Green"
}

if ($pngsToEmbed.Count -eq 0) {
    Write-Log "FEHLER: Keine passenden Icons gefunden." "Red"
    Pause-IfInteractive
    exit 1
}

$totalBytes = 0
$builder = New-Object System.Text.StringBuilder
[void]$builder.AppendLine($startMarker)
[void]$builder.AppendLine('$EmbeddedIcons = @{')

$i = 0
foreach ($f in $pngsToEmbed) {
    $i++
    $slug = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    $slugEscaped = $slug -replace "'", "''"
    try {
        $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
        $b64   = [Convert]::ToBase64String($bytes)
        [void]$builder.Append("    '")
        [void]$builder.Append($slugEscaped)
        [void]$builder.Append("' = '")
        [void]$builder.Append($b64)
        [void]$builder.AppendLine("'")
        $totalBytes += $bytes.Length
    } catch {
        Write-Log "WARNUNG: $($f.Name): $($_.Exception.Message)" "Yellow"
    }
    if ($i % 50 -eq 0) {
        Write-Progress -Activity "Icons einbetten" -Status "[$i/$($pngsToEmbed.Count)] $slug" -PercentComplete ($i * 100 / $pngsToEmbed.Count)
    }
}
Write-Progress -Activity "Icons einbetten" -Completed

[void]$builder.AppendLine('}')
[void]$builder.AppendLine($endMarker)
$embedBlock = $builder.ToString()

Write-Log "Generiert: $($pngsToEmbed.Count) Eintraege, $([math]::Round($totalBytes / 1MB, 2)) MB Roh-Daten" "Green"

$startIdx = $launcherContent.IndexOf($startMarker)
$endIdx   = $launcherContent.IndexOf($endMarker, $startIdx) + $endMarker.Length
$newContent = $launcherContent.Substring(0, $startIdx) + $embedBlock.TrimEnd("`r","`n") + $launcherContent.Substring($endIdx)

$backupPath = "$LauncherPath.bak"
try { Copy-Item -Path $LauncherPath -Destination $backupPath -Force -EA Stop } catch {}

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($LauncherPath, $newContent, $utf8Bom)

$newSize = (Get-Item $LauncherPath).Length
Write-Log "Appstallo.ps1 aktualisiert: $([math]::Round($newSize / 1MB, 2)) MB" "Green"
Write-Host ""
Write-Host "  Fertig! Eingebettet: $($pngsToEmbed.Count) Icons" -ForegroundColor Green
Write-Host ""
Pause-IfInteractive
