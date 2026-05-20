# Appstallo

**Appstallo** ist eine kostenlose Open-Source-Desktop-App fuer Windows 10/11,
die den Windows Package Manager (`winget`) mit einer grafischen Oberflaeche,
kuratierten Programm-Katalogen und teilbaren Preset-Dateien (`.json`)
ergaenzt. Damit lassen sich neue PCs in einem Klick einrichten und
bestehende Setups aktuell halten.

- Website: <https://appstallo.net>
- Lizenz: MIT
- Aktuelle Version: **v1.9.1**

## Module

- **Software-Bibliothek** – Kuratierte Programmkataloge inkl. eigener Auswahl
  und Preset-Import/-Export (mit eingebetteten Icons aus der Website).
- **Software-Browser** – Live-Suche im kompletten winget-Repository mit
  Versions-Badges und Direkt-Installation.
- **Software-Aktualisierungen** – Bulk-Updater mit Detailbericht,
  pausierbaren Updates und Update-Historie.
- **Uninstaller** – Saubere Deinstallation inkl. nativer Behandlung von
  MSIX/Store-Apps und Squirrel-Eigenupdatern.

## Voraussetzungen

- Windows 10 ab Version 1809 oder Windows 11
- `winget` (in aktuellen Windows-Versionen vorinstalliert; sonst „App
  Installer" aus dem Microsoft Store)
- PowerShell 5.1+

Eine fertige, signierte `Appstallo.exe` steht auf
<https://appstallo.net> bzw. unter
[Releases](https://github.com/Redpunch666/Appstallo/releases) zum
Download bereit.

## Aus dem Quellcode bauen

```cmd
Build.bat
```

`Build.bat` ruft intern `Build-Executables.ps1` auf, fuegt
`Appstallo.Common.ps1` automatisch in den Launcher ein und kompiliert die
EXE mit PS2EXE inkl. eingebettetem Icon und Assembly-Metadaten.

Signieren mit eigenem Code-Signing-Zertifikat:

```cmd
Sign.bat
```

## Repository-Inhalt

| Datei / Ordner | Zweck |
| --- | --- |
| `Appstallo.ps1` | Launcher / Hauptmodul (Bibliothek + UI-Shell) |
| `Appstallo.Common.ps1` | Geteilte Funktionen (winget-Filter, PWA-Erkennung) |
| `Software-Bibliothek.ps1` | Modul „Software-Bibliothek" als separater Prozess |
| `Software-Browser.ps1` | Modul „Software-Browser" |
| `Software-Aktualisierungen.ps1` | Modul „Software-Aktualisierungen" |
| `Uninstaller.ps1` | Modul „Uninstaller" |
| `Build-Executables.ps1`, `Build.bat` | Build-Skripte (PS2EXE) |
| `Embed-Icons.ps1`, `Build-IconCatalog.ps1` | Icon-Katalog in EXE einbetten |
| `Sign.bat` | Code-Signing-Skript |
| `CHANGELOG.md` | Versionshistorie |
| `GUIDE.md` | Ausfuehrliche Bedienungsanleitung |
| `FAQ.md` | Haeufig gestellte Fragen |
| `Presets/` | Mitgelieferte Beispiel-Presets |
| `icon-catalog/` | Quellbilder fuer den eingebetteten Icon-Cache |
| `branding/` | Logo, Icons, Marketing-Material |

## Weitere Doku

- [`GUIDE.md`](GUIDE.md) – Schritt-fuer-Schritt-Bedienung aller Module
- [`FAQ.md`](FAQ.md) – Haeufige Fragen rund um winget, Presets, Updates
- [`CHANGELOG.md`](CHANGELOG.md) – Vollstaendige Versionshistorie

## Beitragen

Bug-Reports und Pull-Requests sind willkommen. Programm-Vorschlaege fuer
die kuratierten Kataloge bitte ueber das Formular auf
<https://appstallo.net/suggest> einreichen.

## Lizenz

MIT – siehe [`LICENSE`](LICENSE).
