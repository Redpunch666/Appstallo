﻿# Appstallo 🛠️

Eine grafische Verwaltungssuite fuer den Windows Package Manager (winget). Durchsuche das winget-Repository nach Programmen, installiere sie direkt und stelle dir individuelle Software-Bibliotheken zusammen, die sich als Presets fuer verschiedene Computer oder Einsatzszenarien exportieren und importieren lassen.

![Version](https://img.shields.io/badge/Version-1.9.0_RC3-orange) ![Windows](https://img.shields.io/badge/Windows-10%2F11-0078d4) ![PowerShell](https://img.shields.io/badge/PowerShell-5.1-blue) ![Signed](https://img.shields.io/badge/Code--Signed-Certum-green)

> ⚠️ **Release Candidate** – diese Version wird als Testversion veroeffentlicht. Feedback zu Fehlern und Auffaelligkeiten ist willkommen, am besten als Issue auf GitHub.

---

## 📦 Module

### 🔍 Software-Browser
Durchsucht das gesamte winget-Repository nach beliebigen Programmen. Ergebnisse koennen direkt installiert oder zur persoenlichen Software-Bibliothek hinzugefuegt werden – inklusive automatischem Laden von Beschreibungen und Herstellerinformationen.

### 📚 Software-Bibliothek
Erkennt beim Start automatisch alle auf dem System installierten Programme (via `winget list`) und sortiert sie in thematische Kategorien ein. Zusaetzlich koennen Programme ueber den Software-Browser hinzugefuegt werden. Unterstuetzt den **Export und Import** der gesamten Bibliothek als JSON-Backup – ideal um Software-Presets fuer verschiedene Rechner oder Einsatzzwecke anzulegen und weiterzugeben.

### 🔄 Software-Aktualisierungen
Sucht automatisch nach verfuegbaren Updates, zeigt sie als anhakbare Liste mit Versionswechseln und ermoeglicht **selektive Installation** – jedes Update kann einzeln aus dem Vorgang ausgenommen oder dauerhaft pausiert werden. Pausierte Updates bleiben bis zur manuellen Reaktivierung von der Pruefung ausgeschlossen. Fuehrt eine Update-Historie mit Datum und Versionsverlauf.

### ➖ Uninstaller
Analysiert alle installierten Programme, kategorisiert sie und ermoeglicht die gezielte Deinstallation – mit automatischer Erkennung von GUI-Uninstallern und bis zu 90 Sekunden Wartezeit fuer externe Deinstallationsprogramme.

---

## 🎨 Programm-Icons

Jedes Programm wird in allen vier Modulen mit einem 24×24-Icon links neben dem Namen dargestellt. Die Icons werden in dieser Reihenfolge bezogen:

1. **Cache-Lookup** – fuer Programme mit Mapping-Eintrag wird ein passendes PNG aus dem eingebetteten Icon-Katalog verwendet
2. **EXE-Extraktion** – fuer installierte Programme ohne Mapping wird das Original-Icon ueber die Win32-API aus der EXE oder den ARP-Registry-Eintraegen extrahiert (Jumbo-Icon-Qualitaet 256x256)
3. **Online-Download** – bei nicht gefundenen Slugs wird einmalig versucht, das Icon vom [dashboard-icons](https://github.com/homarr-labs/dashboard-icons)-CDN nachzuladen
4. **Buchstabenkreis** – als letzter Fallback erscheint der Anfangsbuchstabe des Programms in einem farbigen Kreis

Bei Bedarf koennen eigene PNGs zur Icon-Sammlung beigesteuert werden (siehe [GUIDE.md](GUIDE.md#programm-icons-anpassen)).

---

## ⚙️ Voraussetzungen

- **Windows 10** (Build 1809 oder neuer) oder **Windows 11**
- **winget** (Windows Package Manager) – ab Windows 11 vorinstalliert, fuer Windows 10 ueber den [Microsoft Store (App Installer)](https://apps.microsoft.com/detail/9nblggh4nns1) verfuegbar
- **Administratorrechte** – werden beim Start automatisch angefordert

---

## 🚀 Installation & Verwendung

1. `Appstallo.exe` herunterladen
2. Doppelklick – bei der UAC-Anfrage "Ja" klicken
3. Gewuenschtes Modul auswaehlen

> Die einzelnen `.ps1`-Dateien koennen alternativ direkt mit PowerShell ausgefuehrt werden (Rechtsklick → *Mit PowerShell ausfuehren*).

---

## 📖 Dokumentation

- **[Benutzeranleitung (GUIDE.md)](GUIDE.md)** – Ausfuehrliche Anleitung zu allen Modulen, Taskleisten-Verknuepfung, Bedienung, Programm-Icons und Datenspeicherorten
- **[FAQ (FAQ.md)](FAQ.md)** – Antworten auf haeufig gestellte Fragen zu Installation, Fehlerbehebung, Sicherheit und Darstellung
- **[Changelog (CHANGELOG.md)](CHANGELOG.md)** – Versionshistorie mit allen Aenderungen

---

## 🔨 Selbst kompilieren

Voraussetzungen: PowerShell 5.1, .NET Framework (csc.exe)

```
Build-IconCatalog.ps1    # Optional: Icon-Sammlung herunterladen
Build.bat                # EXE erstellen (ruft Embed-Icons automatisch auf, falls vorhanden)
Sign.bat                 # Code-Signierung (nur lokal, benoetigt Certum-Zertifikat)
```

> Die Icon-Schritte sind optional. Ohne sie startet die EXE schneller (~700 KB statt ~6 MB), zeigt aber nur Icons fuer installierte Programme (per EXE-Extraktion). Mit Embed-Schritt bekommen auch nicht-installierte Programme aus dem winget-Repo passende Icons.

Detaillierte Anleitung zum Icon-Build siehe [GUIDE.md](GUIDE.md#programm-icons-anpassen).

---

## ⚠️ Hinweise

- Die installierten Programme unterliegen jeweils den **eigenen Lizenzbedingungen** der jeweiligen Hersteller.
- Dieses Tool laedt keine Software herunter oder buendelt sie – es ruft ausschliesslich `winget` auf oder oeffnet offizielle Downloadseiten im Browser.
- Dieses Tool wird **ohne Gewaehrleistung** bereitgestellt. Fuer Schaeden, die durch die Installation von Drittanbieter-Software entstehen, wird keine Haftung uebernommen.

---

## 📝 Lizenz

MIT License – siehe [LICENSE](LICENSE)

---

## 👤 Autor

© Sven Kuhlow · 2026
