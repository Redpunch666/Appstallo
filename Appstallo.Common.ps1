#requires -Version 5.1
<#
.SYNOPSIS
    Gemeinsame Funktionen fuer Appstallo.

.DESCRIPTION
    Diese Datei wird beim Build in den Launcher eingebettet. Sie definiert
    den UpdateScanner-Code als String ($WGT_UpdateScannerCode), damit dieser
    sowohl im Haupt-Scope (per Invoke-Expression) als auch in jedem Runspace
    (per .AddScript($WGT_UpdateScannerCode)) verfuegbar ist.

    AENDERUNGEN AN DEN FILTER-REGELN BITTE NUR HIER VORNEHMEN.

.NOTES
    Wird vom Launcher und allen Modulen genutzt, die Updates scannen
    (Appstallo.ps1 + Software-Aktualisierungen.ps1).
#>

# ─────────────────────────────────────────────────────────────────────────────
# Update-Scanner-Code als String. Wird in jeden Runspace injiziert.
# ─────────────────────────────────────────────────────────────────────────────
$global:WGT_UpdateScannerCode = @'
function Get-WingetUpdates {
    <#
    .SYNOPSIS
        Liefert die aktuell von winget angebotenen Updates als gefilterte Liste.

    .PARAMETER IncludeAll
        Wenn gesetzt: auch PWAs, Unknown-Versionen und sonst gefilterte
        Eintraege zurueckgeben. Jeder Eintrag traegt dann IsPwa/IsUnknown.

    .OUTPUTS
        System.Collections.Generic.List[hashtable]
        Felder pro Eintrag: Name, Id, Current, Available, IsPwa, IsUnknown
    #>
    [CmdletBinding()]
    param([switch]$IncludeAll)

    $result = New-Object 'System.Collections.Generic.List[hashtable]'

    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

    # winget aufrufen, UTF-8 erzwingen
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = "winget"
    $psi.Arguments              = "upgrade --include-unknown --accept-source-agreements"
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()
    $raw = $stdout -split "[\r\n]+"

    # Header finden (enthaelt "Name" UND "Version")
    $headerIdx = -1
    for ($i = 0; $i -lt $raw.Count; $i++) {
        if ($raw[$i] -match "(?i)\bName\b" -and $raw[$i] -match "(?i)\bVersion\b") {
            $headerIdx = $i
            break
        }
    }
    if ($headerIdx -lt 0) { return $result }

    # Dash-Zeile direkt danach
    $dashIdx = -1
    if (($headerIdx + 1) -lt $raw.Count -and $raw[$headerIdx + 1] -match "^-{20,}") {
        $dashIdx = $headerIdx + 1
    }
    if ($dashIdx -lt 0) { return $result }

    # Spalten-Indizes
    $header = $raw[$headerIdx]
    $hdrLow = $header.ToLower()

    $idStart = -1
    $m = [regex]::Match($hdrLow, "\bid\b")
    if ($m.Success) { $idStart = $m.Index }
    if ($idStart -lt 0) { $idStart = 30 }

    $verStart = $hdrLow.IndexOf("version")
    if ($verStart -lt 0) { $verStart = $idStart + 30 }

    $availStart = $hdrLow.IndexOf("available")
    if ($availStart -lt 0) {
        $m2 = [regex]::Match($hdrLow, "verf")
        if ($m2.Success) { $availStart = $m2.Index }
    }
    if ($availStart -lt 0) { $availStart = $verStart + 15 }

    $srcStart = $hdrLow.IndexOf("source")
    if ($srcStart -lt 0) { $srcStart = $hdrLow.IndexOf("quelle") }
    if ($srcStart -lt 0) { $srcStart = $availStart + 15 }

    # Datenzeilen parsen
    for ($i = $dashIdx + 1; $i -lt $raw.Count; $i++) {
        $line = $raw[$i]
        if ($line.Trim() -eq "" -or $line.Trim().Length -lt 10) { continue }
        if ($line -match "(?i)\d+\s+(upgrade|Aktualisierung|available)") { break }
        if ($line.Length -le $idStart) { continue }

        $name = $line.Substring(0, [Math]::Min($idStart, $line.Length)).Trim()

        $idLen = [Math]::Max(0, $verStart - $idStart)
        $id    = if ($line.Length -gt $idStart) {
            $line.Substring($idStart, [Math]::Min($idLen, $line.Length - $idStart)).Trim()
        } else { "" }

        $verLen = [Math]::Max(0, $availStart - $verStart)
        $verCur = if ($line.Length -gt $verStart) {
            $line.Substring($verStart, [Math]::Min($verLen, $line.Length - $verStart)).Trim()
        } else { "" }

        $availLen = [Math]::Max(0, $srcStart - $availStart)
        $verAvail = if ($line.Length -gt $availStart) {
            $line.Substring($availStart, [Math]::Min($availLen, $line.Length - $availStart)).Trim()
        } else { "" }

        # Truncation entfernen
        $id       = $id.TrimEnd(">", [char]0x2026)
        $verCur   = $verCur.TrimEnd(">", [char]0x2026)
        $verAvail = $verAvail.TrimEnd(">", [char]0x2026)

        # Filter-Flags - PWA-Erkennung (umfassend)
        # 1. Bekannte PWA-Praefixe: Firefox-PWA, Edge-PWA
        # 2. ARP-Pfade User/Machine - hier landen praktisch alle Browser-PWAs
        # 3. Bereits markierte Eintraege (z.B. von Hotfix 18 patched)
        # 4. Heuristik: ID enthaelt Browser-Marker und sieht aus wie zufaelliges Token
        $isPwa = $false
        if ($id -match "(?i)(FFPWA|MSEDGE.?PWA)") { $isPwa = $true }
        if (-not $isPwa -and $id -match "(?i)^ARP\\(User|Machine)\\") { $isPwa = $true }
        if (-not $isPwa -and $name -match "\[PWA\]") { $isPwa = $true }
        # Browser-Heuristik: zufaellige 12+ Zeichen + Browser-Marker
        if (-not $isPwa -and $id -match "(?i)(Chrome|Edge|Brave|Vivaldi|Opera|Chromium)" -and $id -match "[A-Z0-9]{12,}") { $isPwa = $true }
        $isUnknown   = ($verCur -match "^(?i)unknown$" -or $verCur -eq "")
        $isInvalidId = (-not ($id -match "^[A-Za-z0-9][A-Za-z0-9._+\-]+$")) -or $id.Length -le 3 -or $id -match "ARP"
        $isBlocked   = ($id -match "(?i)WinStep\.Nexus")

        if (-not $IncludeAll) {
            if ($isPwa -or $isUnknown -or $isInvalidId -or $isBlocked) { continue }
        } else {
            if ($isInvalidId -or $isBlocked) { continue }
        }

        [void]$result.Add(@{
            Name      = $name
            Id        = $id
            Current   = $verCur
            Available = $verAvail
            IsPwa     = $isPwa
            IsUnknown = $isUnknown
        })
    }

    return $result
}
'@

# Im aktuellen Scope (Haupt-Launcher) Funktion sofort verfuegbar machen
Invoke-Expression $global:WGT_UpdateScannerCode

# ─────────────────────────────────────────────────────────────────────────────
# Installed-Scanner-Code als String. Wird in jeden Runspace injiziert.
# ─────────────────────────────────────────────────────────────────────────────
$global:WGT_InstalledScannerCode = @'
function Get-WingetInstalledList {
    <#
    .SYNOPSIS
        Liefert die installierten Programme als gefilterte Liste.

    .PARAMETER IncludeAll
        Wenn gesetzt: auch PWAs und sonst gefilterte Eintraege zurueckgeben.
        Eintraege haben dann das IsPwa-Flag.

    .OUTPUTS
        System.Collections.Generic.List[hashtable]
        Felder pro Eintrag: Name, Id, Version, IsPwa
    #>
    [CmdletBinding()]
    param([switch]$IncludeAll)

    $result = New-Object 'System.Collections.Generic.List[hashtable]'

    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = "winget"
    $psi.Arguments              = "list --accept-source-agreements"
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()
    $raw = $stdout -split "[\r\n]+"

    # Header finden ("Name" UND "Id" UND "Version")
    $headerIdx = -1
    for ($i = 0; $i -lt $raw.Count; $i++) {
        if ($raw[$i] -match "(?i)Name\s+ID?" -and $raw[$i] -match "(?i)Version") {
            $headerIdx = $i
            break
        }
    }
    if ($headerIdx -lt 0) { return $result }

    $header  = $raw[$headerIdx]
    $hdrLow  = $header.ToLower()

    $namePos = $hdrLow.IndexOf("name")
    if ($namePos -lt 0) { $namePos = 0 }

    $idPosInHeader  = $hdrLow.IndexOf(" id", $namePos) + 1
    $verPosInHeader = $hdrLow.IndexOf("version", $namePos)
    if ($idPosInHeader  -lt 1) { $idPosInHeader  = $namePos + 42 }
    if ($verPosInHeader -lt 1) { $verPosInHeader = $namePos + 84 }

    $idStart  = $idPosInHeader  - $namePos
    $verStart = $verPosInHeader - $namePos

    $srcIdx = $hdrLow.IndexOf("quelle", $namePos)
    if ($srcIdx -lt 0) { $srcIdx = $hdrLow.IndexOf("source", $namePos) }
    $srcStart = if ($srcIdx -ge 0) { $srcIdx - $namePos } else { 110 }

    for ($i = $headerIdx + 2; $i -lt $raw.Count; $i++) {
        $line = $raw[$i]
        if ($line.Trim() -eq "" -or $line.Length -le $idStart) { continue }

        $nameRaw = $line.Substring(0, [Math]::Min($idStart, $line.Length)).Trim()
        $end1    = [Math]::Max(0, $verStart - $idStart)
        $idRaw   = if ($line.Length -gt $idStart) {
            $line.Substring($idStart, [Math]::Min($end1, $line.Length - $idStart)).Trim()
        } else { "" }

        $verTok = ""
        if ($line.Length -gt $verStart) {
            $end2  = [Math]::Max(0, $srcStart - $verStart)
            $verTok = $line.Substring($verStart, [Math]::Min($end2, $line.Length - $verStart)).Trim()
            $verTok = ($verTok -split "\s+")[0]
        }
        # Truncation-Fallback: aus der ganzen Zeile eine Versionsnummer extrahieren
        if (-not $verTok -or $verTok -eq "" -or $verTok -eq "Unknown" -or $verTok -match "^[<>]+$" -or $verTok.Length -lt 2) {
            $verMatches = [regex]::Matches($line, "(?:\d+\.){1,4}\d+(?:[\.\-][A-Za-z0-9]+)*")
            if ($verMatches.Count -gt 0) {
                $verTok = $verMatches[$verMatches.Count - 1].Value
            }
        }

        # Filter-Flags
        $isPwa = $false
        if ($idRaw -match "(?i)(FFPWA|MSEDGE.?PWA)") { $isPwa = $true }
        if (-not $isPwa -and $idRaw -match "(?i)^ARP\\(User|Machine)\\") { $isPwa = $true }
        if (-not $isPwa -and $nameRaw -match "\[PWA\]") { $isPwa = $true }
        # Browser-Heuristik: zufaellige 12+ Zeichen + Browser-Marker
        if (-not $isPwa -and $idRaw -match "(?i)(Chrome|Edge|Brave|Vivaldi|Opera|Chromium)" -and $idRaw -match "[A-Z0-9]{12,}") { $isPwa = $true }
        # Hotfix 25: Version=Unknown ist starker PWA-Indikator (z.B. Anthropic.Claude PWA)
        # winget setzt Unknown wenn der ARP-Eintrag keine Version-Info enthaelt - das
        # passiert praktisch nur bei PWA/Squirrel/anderen Eigenupdater-Konstrukten.
        $isUnknownVersion = ($verTok -match "^(?i)unknown$" -or $verTok -eq "")
        if (-not $isPwa -and $isUnknownVersion) { $isPwa = $true }
        $isValidId = ($idRaw -match "^[A-Za-z0-9][A-Za-z0-9._+\-]+$") -and ($idRaw -notmatch "ARP")

        if (-not $IncludeAll) {
            if ($isPwa -or -not $isValidId) { continue }
        } else {
            if (-not $isValidId -and -not $isPwa) { continue }
        }

        [void]$result.Add(@{
            Name    = $nameRaw
            Id      = $idRaw
            Version = $verTok
            IsPwa   = $isPwa
        })
    }

    # Hotfix 25: Duplikate per ID konsolidieren (hoechste Version gewinnt)
    # Mehrere winget-list-Eintraege mit gleicher ID (z.B. WindowsAppRuntime.1.8 in vielen Versionen,
    # oder ImageGlass nach Update) sollen nicht doppelt erscheinen.
    if (-not $IncludeAll -and $result.Count -gt 1) {
        $deduped = New-Object 'System.Collections.Generic.Dictionary[string,hashtable]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $result) {
            $key = $entry.Id
            if (-not $deduped.ContainsKey($key)) {
                $deduped[$key] = $entry
            } else {
                # Version-Vergleich (System.Version wenn moeglich, sonst lexikalisch)
                $existing = $deduped[$key]
                $vNew = $null; $vOld = $null
                try { $vNew = [System.Version]::Parse($entry.Version) } catch {}
                try { $vOld = [System.Version]::Parse($existing.Version) } catch {}
                if ($vNew -and $vOld) {
                    if ($vNew -gt $vOld) { $deduped[$key] = $entry }
                } else {
                    # Fallback: lexikalisch (neuer Eintrag gewinnt nur wenn Versionsstring "groesser")
                    if ($entry.Version -gt $existing.Version) { $deduped[$key] = $entry }
                }
            }
        }
        $result = New-Object 'System.Collections.Generic.List[hashtable]'
        foreach ($v in $deduped.Values) { [void]$result.Add($v) }
    }

    return $result
}
'@

# Im aktuellen Scope (Haupt-Launcher) Funktion sofort verfuegbar machen
Invoke-Expression $global:WGT_InstalledScannerCode


# =====================================================================
# Zentrale Kategorie-Definition (gilt fuer Bibliothek, Uninstaller, ...)
# =====================================================================
# Damit es zwischen den Modulen keine Differenzen gibt, sind Kategorien
# und Keyword-Mapping AUSSCHLIESSLICH hier gepflegt. Module rufen
# Get-AppstalloCategoryMap / Get-AppstalloCategoryFor / Get-AppstalloCategoryOrder.

function Get-AppstalloCategoryMap {
    return @{
        "Browser & Internet"        = @("browser","firefox","chrome","chromium","opera","brave","vivaldi","edge","wget","curl","ftp","download","torrent","qbittorrent","internet","web browser","selenium")
        "Kommunikation"             = @("discord","jabra","slack","teams","zoom","chat","messenger","signal","telegram","skype","webex","mumble","teamspeak","viber","whatsapp","element","matrix")
        "KI-Tools"                  = @("chatgpt","claude","copilot","openai","anthropic","ollama","lmstudio","lm studio","gpt4all","koboldcpp","localai","stable diffusion","comfyui","automatic1111","midjourney","dall-e","whisper","huggingface","transformers","pytorch","tensorflow","onnx","artificial intelligence","machine learning","llm","gguf","llamacpp")
        "Office & Produktivitaet"   = @("office","libreoffice","onlyoffice","notepad","calibre","joplin","deepl","1password","asana","editor","note","pdf","document","word","excel","typora","languagetool","wispr","xyplorer","todo","task","planner","evernote","notion","obsidian","keepass","onenote","acrobat","foxit","sumatrapdf","writer","calc","impress","powerpoint","okular")
        "E-Mail & Kalender"         = @("thunderbird","emclient","outlook","mailbird","postbox","mail","email","e-mail","calendar","kalender")
        "Grafik & Design"           = @("gimp","pinta","snagit","image","photo","graphic","paint","draw","inkscape","krita","figma","canva","lightroom","photoshop","illustrator","corel","greenshot","sharex","screenshot","irfanview","xnview","darktable","rawtherapee")
        "Audio & Video"             = @("vlc","video","media","audio","music","player","obs","ffmpeg","handbrake","blender","audacity","foobar","spotify","winamp","mpv","mpc","plex","jellyfin","kodi","davinci","premiere","kdenlive","shotcut","openshot","lossless","codec","subtitle","makemkv","screen","capture","voicemeeter","equalizer","soundboard")
        "Gaming & Plattformen"      = @("steam","epic","gog","blizzard","battle.net","ea desktop","ubisoft","playnite","vortex","game","gaming","xbox","lutris","retroarch","emulator","reshade","msi afterburner")
        "Sicherheit & Datenschutz"  = @("adguard","cryptomator","malwarebytes","eset","security","antivirus","firewall","encrypt","vpn","password","bitwarden","privacy","kaspersky","norton","avast","avira","defender","veracrypt","wireguard","openvpn","proton","nordvpn","bitdefender","cert")
        "System & Tools"            = @("7-zip","winrar","powertoys","hwinfo","everything","treesize","tool","utility","ccleaner","revo","iobit","winaero","aquasnap","fences","remote","ssh","terminal","putty","winscp","filezilla","backup","hash","monitor","disk","partition","defrag","registry","uninstall","cleaner","benchmark","speedtest","cpu-z","gpu-z","speccy","cinebench","crystal","autoruns","process","sysinternals","recuva","rufus","etcher","ventoy","ditto","clipboard","autohotkey","macro")
        "Treiber & Hardware"        = @("nvidia","geforce","radeon","amd","intel","realtek","logitech","corsair","razer","steelseries","driver","hardware","chipset","firmware","bios","wacom","elgato","brother","canon","epson","hp ","samsung","displaylink")
        "Cloud & Datenspeicher"     = @("onedrive","dropbox","google drive","icloud","nextcloud","mega","cloud","storage","owncloud","syncthing","resilio","rclone","boxcryptor","tresorit")
        "Laufzeiten & Frameworks"   = @("runtime","redistributable","vcredist","directx","framework",".net","dotnet","webview","msedgewebview","vulkan","openal","openjdk","temurin","corretto","liberica","zulu")
        "Entwicklung"               = @("git","github","node","python","java","dotnet","visual studio","vscode","code","sdk","docker","npm","cmake","rust","go","ruby","php","jetbrains","rider","intellij","pycharm","webstorm","compiler","debug","mingw","gcc","clang","perl","lua","swift","kotlin","gradle","maven","vagrant","terraform","ansible","kubectl","kubernetes","postgres","mysql","mariadb","mongodb","redis","sqlite","dbeaver","datagrip","postman","insomnia","wireshark","fiddler","fork","gitkraken","sourcetree","sublimetext","atom","neovim","vim","emacs","wsl","cygwin","msys","powershell")
        "Netzwerk & Server"         = @("filezilla server","apache","nginx","iis","dns","dhcp","proxy","network","netzwerk","traceroute","ping","nmap","netcat","mremoteng","rdp","vnc","anydesk","teamviewer","parsec","tailscale","zerotier","opnsense","pfsense","pihole","adguard home","unifi","ubiquiti")
    }
}

# Reihenfolge der Kategorien fuer die Anzeige.
# Standard: alphabetisch + "Sonstige Programme" am Ende.
# IncludeDirectDownload = $true haengt zusaetzlich "Direktdownload" als
# allerletzte Kategorie an (nur fuer die Bibliothek relevant).
function Get-AppstalloCategoryOrder {
    param([switch]$IncludeDirectDownload)
    $map = Get-AppstalloCategoryMap
    $order = @(@($map.Keys) | Sort-Object) + @("Sonstige Programme")
    if ($IncludeDirectDownload) { $order += "Direktdownload" }
    return ,$order
}

# Liefert die Kategorie fuer ein Programm anhand Name + Id.
# Gleiche Logik wie bisher in Bibliothek/Uninstaller; Fallback "Sonstige Programme".
function Get-AppstalloCategoryFor {
    param(
        [string]$Name,
        [string]$Id
    )
    $map = Get-AppstalloCategoryMap
    $matchText = (("$Name $Id")).ToLower()
    foreach ($catName in $map.Keys) {
        foreach ($kw in $map[$catName]) {
            if ($matchText.Contains($kw)) { return $catName }
        }
    }
    return "Sonstige Programme"
}
