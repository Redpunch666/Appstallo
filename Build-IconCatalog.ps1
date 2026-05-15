# Build-IconCatalog.ps1 - Laedt PNGs aus dem dashboard-icons CDN
[CmdletBinding()]
param(
    [string]$LauncherPath,
    [string]$CatalogDir,
    [switch]$Extended,
    [switch]$All
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

$scriptDir = $PSScriptRoot
if (-not $scriptDir) {
    try { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path -EA Stop } catch {}
}
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

if (-not $LauncherPath) { $LauncherPath = Join-Path $scriptDir 'Appstallo.ps1' }
if (-not $CatalogDir)   { $CatalogDir   = Join-Path $scriptDir 'icon-catalog' }

$logFile = Join-Path $scriptDir 'Build-IconCatalog.log'
function Write-Log {
    param([string]$msg, [string]$color = 'Gray')
    Write-Host $msg -ForegroundColor $color
    try { "$(Get-Date -Format 'HH:mm:ss') $msg" | Add-Content -Path $logFile -Encoding UTF8 -EA SilentlyContinue } catch {}
}

try { "===== Build-IconCatalog $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') =====" | Set-Content -Path $logFile -Encoding UTF8 } catch {}

Write-Host ""
Write-Host "  Build-IconCatalog" -ForegroundColor Cyan
Write-Host "  Dashboard-Icons fuer Appstallo Suite" -ForegroundColor Cyan
Write-Host ""

$mode = if ($All) { "All (~2800 Slugs)" } elseif ($Extended) { "Extended (gefiltert)" } else { "Standard (Mapping-Slugs)" }
Write-Log "Lade tree.json ($mode)..."

$treeUrl = 'https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons@main/tree.json'
try {
    $json = Invoke-WebRequest -Uri $treeUrl -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
    $tree = $json.Content | ConvertFrom-Json
} catch {
    Write-Log "FEHLER beim Laden von tree.json: $($_.Exception.Message)" "Red"
    Read-Host "Druecke ENTER"; exit 1
}

# Slugs aus tree.json extrahieren - garantiert als String-Array
# WICHTIG: tree.json enthaelt Dateinamen mit .png-Endung -> entfernen
function Strip-PngExt {
    param([string]$s)
    if ($s -match '\.png$') { return $s.Substring(0, $s.Length - 4) }
    return $s
}
$allSlugs = New-Object 'System.Collections.Generic.List[string]'
if ($tree -is [System.Collections.IList]) {
    foreach ($s in $tree) { [void]$allSlugs.Add((Strip-PngExt ([string]$s))) }
} elseif ($tree.png) {
    foreach ($s in $tree.png) { [void]$allSlugs.Add((Strip-PngExt ([string]$s))) }
} else {
    # PSCustomObject - alle Property-Werte sammeln
    foreach ($prop in $tree.PSObject.Properties) {
        if ($prop.Value -is [System.Collections.IList]) {
            foreach ($s in $prop.Value) { [void]$allSlugs.Add((Strip-PngExt ([string]$s))) }
        }
    }
}
Write-Log "  $($allSlugs.Count) Slugs gesamt"
if ($allSlugs.Count -gt 0) {
    Write-Log "  Beispiele: $($allSlugs[0]), $($allSlugs[1]), $($allSlugs[2])" "DarkGray"
}

# Filtern je nach Modus
$slugsToDownload = New-Object 'System.Collections.Generic.List[string]'
if ($All) {
    foreach ($s in $allSlugs) { [void]$slugsToDownload.Add($s) }
} elseif ($Extended) {
    foreach ($s in $allSlugs) {
        if (($s.Length -le 25) -and
            (([regex]::Matches($s, '-').Count) -le 2) -and
            ($s -notmatch '-(arr|server|stack|api|bot|sync|pi)$') -and
            ($s -notmatch '-(light|dark|alt|old|canary)$') -and
            ($s -notmatch '^(kubernetes|docker|helm)-')) {
            [void]$slugsToDownload.Add($s)
        }
    }
    Write-Log "  $($slugsToDownload.Count) nach Filter"
} else {
    # Standard: Mapping-Slugs aus Appstallo.ps1
    if (-not (Test-Path $LauncherPath)) {
        Write-Log "FEHLER: Appstallo.ps1 nicht gefunden." "Red"
        Read-Host "Druecke ENTER"; exit 1
    }
    $launcherContent = Get-Content -Path $LauncherPath -Raw -Encoding UTF8
    $patternMap = '\$IconSlugMap\s*=\s*@\{([^}]+)\}'
    $m = [regex]::Match($launcherContent, $patternMap, 'Singleline')
    if (-not $m.Success) {
        Write-Log "FEHLER: \$IconSlugMap-Block nicht gefunden." "Red"
        Read-Host "Druecke ENTER"; exit 1
    }
    $mapBlock = $m.Groups[1].Value
    $slugMatches = [regex]::Matches($mapBlock, "'[^']+'\s*=\s*'([a-zA-Z0-9\-]+)'")
    # Mapping-Slugs als HashSet[string] -> Lookup ist string-basiert und case-insensitive
    $mappingSlugs = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($sm in $slugMatches) { [void]$mappingSlugs.Add($sm.Groups[1].Value) }
    Write-Log "  Mapping enthaelt $($mappingSlugs.Count) eindeutige Slugs"
    # Beispiele zur Verifikation
    $firstSample = $null
    foreach ($s in $mappingSlugs) { $firstSample = $s; break }
    Write-Log "  Mapping-Sample: $firstSample" "DarkGray"
    foreach ($s in $allSlugs) {
        if ($mappingSlugs.Contains([string]$s)) {
            [void]$slugsToDownload.Add([string]$s)
        }
    }
    Write-Log "  $($slugsToDownload.Count) davon im dashboard-icons-Index verfuegbar"
}

if ($slugsToDownload.Count -eq 0) {
    Write-Log "FEHLER: Keine Slugs zu laden." "Red"
    Read-Host "Druecke ENTER"; exit 1
}

if (-not (Test-Path $CatalogDir)) {
    New-Item -ItemType Directory -Path $CatalogDir -Force | Out-Null
}
Write-Log "Ziel: $CatalogDir"
Write-Log "Zu laden: $($slugsToDownload.Count) Icons"

$downloaded = 0; $skipped = 0; $failed = New-Object 'System.Collections.Generic.List[string]'
$start = Get-Date
$i = 0
foreach ($slug in $slugsToDownload) {
    $i++
    $cachePath = Join-Path $CatalogDir "$slug.png"
    if (Test-Path $cachePath) {
        $skipped++
        if ($i % 50 -eq 0) {
            Write-Progress -Activity "Lade Icons" -Status "[$i/$($slugsToDownload.Count)] $slug" -PercentComplete ($i * 100 / $slugsToDownload.Count)
        }
        continue
    }
    $url = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons@main/png/$slug.png"
    try {
        $bytes = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop).Content
        if ($bytes -is [byte[]] -and $bytes.Length -gt 200) {
            [System.IO.File]::WriteAllBytes($cachePath, $bytes)
            $downloaded++
        } else { [void]$failed.Add("$slug (leer)") }
    } catch { [void]$failed.Add("$slug ($($_.Exception.Message))") }
    Write-Progress -Activity "Lade Icons" -Status "[$i/$($slugsToDownload.Count)] $slug" -PercentComplete ($i * 100 / $slugsToDownload.Count)
}
Write-Progress -Activity "Lade Icons" -Completed
$elapsed = (Get-Date) - $start

$folderSize = (Get-ChildItem $CatalogDir -Filter *.png -EA SilentlyContinue | Measure-Object Length -Sum).Sum
Write-Host ""
Write-Host "  Fertig in $([math]::Round($elapsed.TotalSeconds, 1)) Sek." -ForegroundColor Cyan
Write-Log "  Heruntergeladen:    $downloaded" "Green"
Write-Log "  Bereits vorhanden:  $skipped"
if ($failed.Count -gt 0) {
    Write-Log "  Fehlgeschlagen:     $($failed.Count)" "Yellow"
}
Write-Log "  Groesse: $([math]::Round($folderSize / 1MB, 2)) MB"
Write-Host ""
Read-Host "Druecke ENTER"
