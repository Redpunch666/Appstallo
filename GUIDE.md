# Appstallo – Benutzeranleitung

Appstallo ist eine grafische Verwaltungssuite fuer den Windows Package Manager (winget). Das Programm erkennt automatisch alle installierten Programme, ermoeglicht die Suche im winget-Repository und das Zusammenstellen individueller Software-Bibliotheken. Diese Bibliotheken lassen sich als Presets exportieren und importieren – ideal fuer die Einrichtung verschiedener Computer oder Einsatzszenarien.

## Inhaltsverzeichnis

1. [Installation und erster Start](#installation-und-erster-start)
2. [Taskleisten-Verknuepfung einrichten](#taskleisten-verknuepfung-einrichten)
3. [Der Launcher](#der-launcher)
4. [Software-Browser](#software-browser)
5. [Software-Bibliothek](#software-bibliothek)
6. [Software-Aktualisierungen](#software-aktualisierungen)
7. [Uninstaller](#uninstaller)
8. [Extras-Menue](#extras-menue)
9. [Export und Import](#export-und-import)
10. [Benutzerdefinierte Kategorien](#benutzerdefinierte-kategorien)
11. [Listenausgabe](#listenausgabe)
12. [Programm-Icons anpassen](#programm-icons-anpassen)
13. [Datenspeicherorte](#datenspeicherorte)
14. [Tipps und Hinweise](#tipps-und-hinweise)

---

## Installation und erster Start

### Voraussetzungen

- **Windows 10** (Version 1809 oder neuer) oder **Windows 11**
- **winget** (Windows Package Manager) – ist bei aktuellen Windows-Versionen vorinstalliert. Pruefe dies mit `winget --version` in der Eingabeaufforderung
- **Administratorrechte** – werden beim Start automatisch angefordert

### Programmstart

1. `Appstallo.exe` herunterladen und in einen beliebigen Ordner speichern
2. Doppelklick auf `Appstallo.exe`
3. Bei der UAC-Abfrage (Benutzerkontensteuerung) auf **Ja** klicken
4. Der Launcher oeffnet sich – von hier aus sind alle vier Module erreichbar

### Alternative: Direktstart der PowerShell-Skripte

Die einzelnen `.ps1`-Dateien koennen auch direkt ausgefuehrt werden:

1. Rechtsklick auf die `.ps1`-Datei
2. **Mit PowerShell ausfuehren** waehlen
3. Bei der UAC-Abfrage auf **Ja** klicken

Hinweis: Beim Direktstart ueber PowerShell steht das Appstallo-Icon nicht zur Verfuegung und es wird stattdessen das Standard-PowerShell-Icon angezeigt.

---

## Taskleisten-Verknuepfung einrichten

Seit v1.9.0 funktioniert das Anpinnen direkt aus der laufenden Anwendung:

1. Appstallo ueber die EXE starten
2. Rechtsklick auf das Appstallo-Symbol in der Taskleiste
3. **An Taskleiste anheften** waehlen

Das angepinnte Symbol zeigt das korrekte Appstallo-Icon. Der frueher noetige Umweg ueber das Startmenue entfaellt.

> **Hinweis:** Beim Direktstart einzelner `.ps1`-Dateien ueber PowerShell wird weiterhin das PowerShell-Icon angezeigt, da in diesem Fall keine Appstallo-EXE als Host-Prozess laeuft.

---

## Der Launcher

Der Launcher ist das Hauptfenster und der zentrale Einstiegspunkt. Er zeigt vier Modulkarten:

- **Software-Browser** – winget-Repository durchsuchen und Programme installieren
- **Software-Bibliothek** – kategorisierter Programmkatalog mit Export/Import
- **Software-Aktualisierungen** – Updates suchen und installieren
- **Uninstaller** – Programme deinstallieren

### Automatische Update-Pruefung

Beim Start des Launchers wird im Hintergrund automatisch nach verfuegbaren Updates gesucht. Sind Updates vorhanden, erscheint ein **rotes Badge** auf der Aktualisierungen-Karte mit der Anzahl (z.B. „3"). Nach dem Schliessen eines Moduls wird die Update-Pruefung automatisch erneut durchgefuehrt.

**Pause-Beruecksichtigung:** Pausierte Updates werden weder im Badge noch im Statustext mitgezaehlt. Der Statustext informiert separat ueber pausierte Eintraege:

| Zustand | Statustext auf der Karte |
|---|---|
| Keine Updates, keine pausiert | „Alle Programme sind aktuell" |
| X Updates, keine pausiert | „X Update(s) verfuegbar" |
| Keine Updates, Y pausiert | „Keine aktiven Updates  -  Y pausiert" |
| X Updates, Y pausiert | „X Update(s) verfuegbar  -  Y pausiert" |

### Status-Zeilen

Unter den Karten werden Status-Informationen angezeigt (sofern Daten vorhanden):

- Bei der **Aktualisierungen-Karte**: Datum des letzten durchgefuehrten Updates
- Bei der **Bibliothek-Karte**: Anzahl der Programme im Versionscache

Klicke auf eine Karte, um das jeweilige Modul zu oeffnen. Der Launcher minimiert sich dabei automatisch und erscheint wieder, sobald das Modul geschlossen wird.

Die **Versionsnummer** wird unten rechts im Footer angezeigt.

---

## Software-Browser

### Zweck

Der Software-Browser ermoeglicht den Zugriff auf das gesamte winget-Repository mit ueber 10.000 Programmen. Programme die nicht im vordefinierten Katalog der Bibliothek enthalten sind, koennen hierueber gefunden und installiert werden.

### Suche ausfuehren

1. Einen Suchbegriff in das Suchfeld eingeben (mindestens 2 Zeichen)
2. **Enter** druecken oder auf **Suchen** klicken
3. Die Ergebnisse werden als Liste mit Checkboxen angezeigt

Die Suche durchsucht sowohl Programmnamen als auch Winget-IDs. Je spezifischer der Suchbegriff, desto genauer die Ergebnisse.

### Ergebnisliste

Jedes Ergebnis zeigt:

- **Programmname** (fett)
- **Winget-ID** in Klammern (grau)
- **Versions-Badge** in Orange (falls eine Versionsnummer verfuegbar ist)
- **Info-Button** (i) fuer Details und Winget-ID-Kopierfunktion

### Programme installieren

1. Gewuenschte Programme per Checkbox auswaehlen
2. Unten wird die Anzahl der ausgewaehlten Programme angezeigt
3. Auf **Installieren (X)** klicken
4. Die Installation laeuft automatisch ab mit Fortschrittsanzeige im Log
5. Nach Abschluss kann ueber **Zurueck zur Suche** eine weitere Suche gestartet werden

### Programme zur Bibliothek hinzufuegen

Gefundene Programme koennen dauerhaft in die Software-Bibliothek uebernommen werden:

1. Programme per Checkbox auswaehlen
2. Auf **Zum Katalog (X)** klicken
3. Die Programme werden in einer lokalen Datei gespeichert (`%LOCALAPPDATA%\Appstallo\custom-catalog.json`)
4. Beim naechsten Start der **Software-Bibliothek** erscheinen sie unter der passenden Kategorie

### Tipps

- Fuer Microsoft Office zum Beispiel: „office" oder „Microsoft.Office" eingeben
- Fuer spezifische Programme die Winget-ID verwenden (z.B. „Microsoft.VisualStudioCode")
- Die Suche gibt maximal die von winget zurueckgegebenen Ergebnisse aus – bei sehr allgemeinen Begriffen koennen das viele sein

---

## Software-Bibliothek

### Programmauswahl

Nach dem Oeffnen wird die Liste der installierten Programme erfasst (dauert einige Sekunden). Danach erscheint die kategorisierte Programmliste mit Checkboxen.

### Kategorien

Die Programme werden automatisch in folgende 15 Kategorien einsortiert:

- Audio & Video
- Browser & Internet
- Cloud & Datenspeicher
- E-Mail & Kalender
- Entwicklung
- Gaming & Plattformen
- Grafik & Design
- KI-Tools
- Kommunikation
- Laufzeiten & Frameworks
- Netzwerk & Server
- Office & Produktivitaet
- Sicherheit & Datenschutz
- System & Tools
- Treiber & Hardware

Zusaetzlich gibt es die Kategorie **Direktdownload** fuer Programme die nicht ueber winget verfuegbar sind, sowie beliebig viele **benutzerdefinierte Kategorien** (siehe [Benutzerdefinierte Kategorien](#benutzerdefinierte-kategorien)).

### Programmbeschreibungen

Programmbeschreibungen koennen auf zwei Wegen geladen werden:

- **Info-Button**: Klick auf den Info-Button (i) eines Eintrags laedt die Beschreibung per `winget show` und zeigt sie im Detail-Popup
- **Extras-Menue → Programmbeschreibungen abrufen**: Laedt die Beschreibungen fuer alle Programme auf einmal herunter

Einmal abgerufene Beschreibungen werden in einem lokalen Cache (`descriptions-cache.json`) gespeichert und stehen beim naechsten Start sofort zur Verfuegung.

### Versions-Badges

Neben jedem Programm werden farbige Badges angezeigt:

- **Gruenes Badge „Installiert vX.Y.Z"** – Das Programm ist bereits in der angegebenen Version installiert
- **Oranges Badge „Verfuegbar vX.Y.Z"** – Das Programm ist nicht installiert; die angezeigte Version ist ueber winget verfuegbar

Die verfuegbaren Versionen werden im Hintergrund geladen und erscheinen nach und nach. Ein lokaler Cache speichert die Daten fuer 24 Stunden, damit sie beim naechsten Start sofort angezeigt werden.

### Suchfeld

Ueber dem Programmbereich befindet sich ein **Suchfeld**. Es filtert die Liste live nach Programmname, Winget-ID und Beschreibung. Kategorien ohne Treffer werden automatisch ausgeblendet. Das **X** rechts neben dem Suchfeld loescht den Suchbegriff und zeigt wieder alle Programme.

### Info-Button

Rechts neben jedem Programm befindet sich ein kleiner runder **Info-Button** (i). Ein Klick darauf oeffnet ein Detail-Fenster mit:

- Programmname
- Hersteller (aus der Winget-ID abgeleitet)
- Winget-ID mit **Kopieren-Funktion** (Button „ID kopieren")
- Installierte Version (falls vorhanden)
- Beschreibung (wird bei Bedarf per `winget show` nachgeladen)

### Programme installieren

1. Gewuenschte Programme per Checkbox auswaehlen
2. Der Button **Alle** in jeder Kategorie waehlt alle Programme der Kategorie auf einmal
3. Unten links wird die Anzahl der ausgewaehlten Programme angezeigt
4. Auf **Installieren** klicken
5. Die Installation laeuft automatisch ab – bei Direktdownloads wird die Hersteller-Webseite im Browser geoeffnet

---

## Software-Aktualisierungen

### Automatische Update-Suche

Beim Oeffnen des Moduls wird sofort automatisch nach verfuegbaren Updates gesucht. Nach wenigen Sekunden erscheint eine **Checkbox-Liste** der gefundenen Updates:

```
5 Update(s) verfuegbar - waehle die zu installierenden aus:    Alle abwaehlen
 ☑ Mozilla Firefox (x64 de)                150.0.1  ->  150.0.2     [⏸]
 ☑ calibre 64bit                           8.16.2   ->  9.8.0       [⏸]
 ☑ Visual Studio Code                      1.95.0   ->  1.95.1      [⏸]
```

Jede Zeile zeigt Name, aktuelle Version, verfuegbare Version, eine Checkbox zum Aus-/Abwaehlen und einen Pause-Button (⏸).

### Selektive Updates

- Standardmaessig sind alle gefundenen Updates ausgewaehlt
- Per **Checkbox** koennen einzelne Updates aus dem Vorgang ausgenommen werden
- Der Toggle **Alle abwaehlen** / **Alle auswaehlen** oben rechts wechselt zwischen allen und keinem
- Der **Updates starten (X)**-Button zeigt live die Anzahl der aktuell ausgewaehlten Updates
- Wird kein Update ausgewaehlt, ist der Button deaktiviert

### Updates pausieren

Updates koennen permanent pausiert werden – bis zur manuellen Reaktivierung. Pausierte Updates werden bei jeder Update-Pruefung ignoriert und tauchen weder in der Vorschau oben noch im Launcher-Badge auf.

1. Klick auf den **⏸-Button** rechts neben einem Update
2. Das Update wird sofort in die Sektion **Pausiert** unter der aktiven Liste verschoben
3. Die Selektion und der Counter aktualisieren sich automatisch

```
─────────────────────────────────────────────
Pausiert (1):
  Java JDK          pausiert bei v17.0.11     [▶ Reaktivieren]
```

Die Liste der pausierten Updates wird in `paused-updates.json` dauerhaft gespeichert und bleibt ueber Neustarts hinweg erhalten.

### Updates reaktivieren

- Klick auf **▶ Reaktivieren** neben dem pausierten Eintrag
- Das Update wandert wieder in die aktive Liste (sofern winget es noch als verfuegbar meldet)
- Wurde das Programm zwischenzeitlich manuell aktualisiert oder deinstalliert, erscheint es nach dem Reaktivieren nicht mehr in der Liste

### Updates installieren

1. Die Auswahl pruefen und Updates ggf. ab-/anwaehlen oder pausieren
2. Auf **Updates starten (X)** klicken
3. Die Vorschau wird ausgeblendet, das Log eingeblendet
4. Die ausgewaehlten Updates werden nacheinander installiert
5. Im Log-Bereich wird der Fortschritt pro Paket angezeigt (grafischer Fortschrittsbalken oben sowie Textausgabe im Log)
6. Nach Abschluss zeigt die Zusammenfassung die Anzahl erfolgreicher, fehlgeschlagener und uebersprungener Updates

Nach Abschluss wechselt der **Schliessen-Button** auf Rot – er ist dann die primaere Aktion.

### Problem-Popup

Falls Updates fehlgeschlagen oder uebersprungen sind, erscheint nach Abschluss automatisch ein **Popup mit detaillierten Problemgruenden**. Fuer jeden Eintrag werden angezeigt:

- Programmname und Winget-ID
- Versionswechsel (von → zu)
- Problem-Grund (z.B. Exit-Code, Installationsmodus nicht unterstuetzt)

Neben jedem Eintrag befindet sich ein **Kopieren-Button**, um den Text einzeln in die Zwischenablage zu uebernehmen.

Der Titel des Popups passt sich an: „X Update(s) fehlgeschlagen", „X Update(s) uebersprungen" oder „X Update(s) mit Problemen" (bei gemischten Faellen).

### Update-Historie

Der Button **Update-Historie** oeffnet ein Fenster mit den zuletzt durchgefuehrten Updates (maximal 100 Eintraege). Jeder Eintrag zeigt:

- Datum und Uhrzeit
- Programmname
- Versionswechsel (von → zu)

Ueber **Verlauf loeschen** kann die Historie zurueckgesetzt werden (mit Sicherheitsabfrage).

### Log speichern

Nach abgeschlossenen Updates erscheint der Button **Log speichern**. Damit kann die vollstaendige Konsolen-Ausgabe als `.log`-Datei auf dem Desktop gespeichert werden.

---

## Uninstaller

### Programmanalyse

Beim Oeffnen werden alle installierten Programme analysiert und in dieselben Kategorien wie in der Software-Bibliothek einsortiert. Das Suchfeld und der Info-Button funktionieren identisch zur Software-Bibliothek.

### Programme deinstallieren

1. Programme per Checkbox auswaehlen
2. Auf **Deinstallieren** klicken
3. Eine Sicherheitsabfrage erscheint – mit **Ja** bestaetigen
4. Die Deinstallation laeuft automatisch ab

### Programme mit GUI-Uninstaller

Einige Programme (z.B. Opera) unterstuetzen keine stille Deinstallation. In diesem Fall:

1. winget startet den programmspezifischen Uninstaller
2. Es erscheint das Deinstallationsfenster des Herstellers
3. Die Deinstallation dort manuell bestaetigen
4. Das Modul wartet bis zu **90 Sekunden** und prueft automatisch, ob das Programm entfernt wurde
5. Wurde das Programm erfolgreich entfernt, wird es als **erfolgreich** gewertet – auch wenn winget einen Fehlercode gemeldet hat

---

## Extras-Menue

In der Software-Bibliothek befindet sich unten der Button **Extras ▾**. Er oeffnet ein Kontextmenue mit folgenden Funktionen:

| Menuepunkt | Beschreibung |
|---|---|
| **Exportieren** | Bibliothek als JSON-Backup sichern |
| **Importieren** | Bibliothek aus einem Backup wiederherstellen |
| **Liste ausgeben** | Programmliste als CSV oder HTML-Druckansicht erzeugen |
| **Programmbeschreibungen abrufen** | Beschreibungen aller Programme herunterladen und im Cache speichern |
| **Neue Kategorie anlegen** | Eigene Kategorie erstellen |
| **Bibliothek leeren** | Alle benutzerdefinierten Eintraege entfernen (mit Sicherheitsabfrage und Countdown) |

---

## Export und Import

### Export

1. Im **Extras-Menue** auf **Exportieren** klicken
2. Speicherort und Dateinamen waehlen
3. Die gesamte Bibliothek wird als JSON-Datei gespeichert

Der Export umfasst:

- Alle Programme aus allen Kategorien
- Alle Direktlinks
- Benutzerdefinierte Kategorien (Namen)
- Benutzerdefinierte Kategorie-Zuordnungen (verschobene Programme)

Die Backup-Datei eignet sich als Preset fuer die Einrichtung weiterer Computer oder als Sicherungskopie. Benutzerdefinierte Zuordnungen bleiben nach dem Import erhalten – verschobene Programme landen auf dem Zielrechner wieder in derselben Kategorie.

### Import

1. Im **Extras-Menue** auf **Importieren** klicken und die Backup-Datei auswaehlen
2. Import-Modus waehlen:

| Modus | Beschreibung |
|---|---|
| **Ueberschreiben** | Die aktuelle Bibliothek wird vollstaendig durch das Backup ersetzt |
| **Zusammenfuehren** | Bestehende und importierte Eintraege werden kombiniert. Duplikate werden automatisch uebersprungen |

3. Die Bibliothek wird automatisch neu geladen – kein manuelles Schliessen noetig

### Anwendungsbeispiele

- **Neuer PC einrichten**: Backup vom alten Rechner exportieren, auf dem neuen importieren, alle Programme auf einen Klick installieren
- **Arbeits-PC vs. Privat-PC**: Verschiedene Presets fuer unterschiedliche Einsatzzwecke anlegen
- **Team-Setup**: Ein einheitliches Software-Preset fuer alle Teammitglieder bereitstellen

---

## Benutzerdefinierte Kategorien

Neben den automatisch vergebenen Kategorien koennen eigene Kategorien angelegt werden:

1. Im **Extras-Menue** auf **Neue Kategorie anlegen** klicken
2. Namen eingeben und mit **Anlegen** bestaetigen

### Programme verschieben

Jeder Eintrag in der Bibliothek hat einen Verschieben-Button (Pfeil-Symbol zwischen Info und Loeschen). Ein Klick oeffnet einen Dialog mit allen verfuegbaren Kategorien als Ziel. Die Zuordnung wird dauerhaft in `custom-assignments.json` gespeichert und bleibt auch nach Neustarts und System-Scans erhalten.

### Kategorie loeschen

Leere benutzerdefinierte Kategorien zeigen im Kategorie-Header einen kleinen Loeschbutton (X). Nach einer Sicherheitsabfrage wird die Kategorie entfernt.

---

## Listenausgabe

Im **Extras-Menue** auf **Liste ausgeben** klicken. Es stehen zwei Formate zur Wahl:

### CSV

Speichert die gesamte Programmliste als CSV-Datei (Semikolon-getrennt, UTF-8). Kann mit Excel, LibreOffice oder anderen Tabellenkalkulationen geoeffnet werden.

### HTML / Druckansicht

Erzeugt eine formatierte HTML-Seite mit allen Programmen, Kategorien, Beschreibungen und Installationsstatus und oeffnet sie im Standardbrowser. Von dort aus kann gedruckt werden.

Falls Programmbeschreibungen noch nicht vorliegen, werden sie vor der Ausgabe automatisch heruntergeladen (Fortschrittsanzeige). Bereits gecachte Beschreibungen werden sofort verwendet.

---

## Bibliothek leeren (Reset)

1. Im **Extras-Menue** auf **Bibliothek leeren** klicken
2. Ein Bestaetigungsdialog mit 15-Sekunden-Countdown erscheint
3. Nach Ablauf des Countdowns oder Klick auf den Countdown-Button werden alle benutzerdefinierten Eintraege geloescht
4. Die Bibliothek wird automatisch neu geladen und zeigt nur noch die vom System erkannten Programme

Hinweis: Beim naechsten Start werden die auf dem System installierten Programme automatisch wieder erkannt und angezeigt. Nur manuell ueber den Software-Browser hinzugefuegte Eintraege und Direktlinks gehen verloren.

---


## Programm-Icons anpassen

Appstallo zeigt fuer jedes Programm ein 24×24 Icon links neben dem Namen. Die Icons stammen aus vier Quellen, die in dieser Reihenfolge probiert werden:

1. **Cache-Lookup** – `%LOCALAPPDATA%\Appstallo\icon-cache\` mit dem im Mapping eingetragenen Slug
2. **EXE-Extraktion** – Win32-API extrahiert das Icon aus der installierten EXE
3. **Online-Download** – einmalige Anfrage an dashboard-icons-CDN
4. **Buchstabenkreis** – Anfangsbuchstabe in farbigem Kreis

Die EXE liefert bereits ueber 150 eingebettete Icons. Wer eigene Icons fuer weitere Programme hinzufuegen moechte, kann das so machen:

### Schritt 1 – PNG ablegen

PNG-Datei (transparenter Hintergrund, mind. 64×64 Pixel, ideal 128×128 oder 256×256) im Build-Ordner unter `icon-catalog\` ablegen. Der Dateiname (ohne `.png`) wird zum **Slug** und ist die spaetere Referenz im Mapping. Empfehlung: einfache Kleinschreibung wie `notepadplusplus.png`.

### Schritt 2 – Mapping eintragen

In `Appstallo.ps1` (oder in der entsprechenden Modul-Datei) im `$IconSlugMap`-Hashtable einen Eintrag ergaenzen. Format: `'Winget.Id' = 'slug'`. Beispiel:

```powershell
'Notepad++.Notepad++' = 'notepadplusplus'
```

Die echte Winget-ID eines installierten Programms erfaehrt man mit `winget list` in der PowerShell. Microsoft-Store-Apps haben Produkt-IDs wie `9NLVZBZ2WZ28` (12 Zeichen, alphanumerisch).

### Schritt 3 – Neu bauen

```powershell
Build.bat
```

`Build-Executables.ps1` ruft automatisch `Embed-Icons.ps1` auf, das die neue PNG in den eingebetteten Icon-Block der EXE schreibt. Danach den Icon-Cache leeren, damit beim naechsten Start der frische Embed-Block ausgepackt wird:

```powershell
Remove-Item "$env:LOCALAPPDATA\Appstallo\icon-cache\*" -Force -Recurse -EA SilentlyContinue
```

### Tipps

- **Mapping-Slug muss zum Dateinamen passen** (case-insensitive auf Windows). `'AdGuard.AdGuard' = 'adguard-home'` braucht eine `adguard-home.png` im Katalog.
- **Mehrere IDs auf gleiches Icon mappen** ist OK: `'Affinity.Photo' = 'Affinity'`, `'Affinity.Designer' = 'Affinity'` etc. zeigen alle dasselbe Icon.
- **PowerShell-Hashtables sind case-insensitive** – zwei Eintraege mit gleicher ID (nur unterschiedliche Schreibweise) wuerfen einen Parse-Error.
- **Build-IconCatalog.ps1** versucht NUR Slugs aus dem [dashboard-icons-Repo](https://github.com/homarr-labs/dashboard-icons) zu laden. Eigene PNGs werden nicht ueberschrieben (Skip wenn schon vorhanden).

---


## Architektur (fuer Entwickler)

Appstallo besteht aus mehreren PowerShell-Skripten und einem Build-System,
das diese in eine ausfuehrbare `.exe` packt.

### Module

- **`Appstallo.ps1`** – Launcher mit den 4 Modul-Kacheln. Enthaelt die
  Modul-Code-Heredocs (`$codeUpdater`, `$codeInstaller`, `$codeUninstaller`,
  `$codeSearch`), die bei Klick als separate `powershell.exe`-Prozesse
  gestartet werden.
- **`Software-Bibliothek.ps1`** – Standalone-Variante des Bibliotheks-Moduls.
- **`Software-Browser.ps1`** – Standalone-Variante des Browser-Moduls.
- **`Software-Aktualisierungen.ps1`** – Standalone-Variante des Updater-Moduls.
- **`Uninstaller.ps1`** – Standalone-Variante des Uninstaller-Moduls.

### Gemeinsame Funktionen (`Appstallo.Common.ps1`)

Seit v1.9.0 liegen die zentralen winget-Scanner-Funktionen in einer
gemeinsamen Datei:

- **`Get-WingetUpdates`** – Liefert verfuegbare Updates als gefilterte Liste.
  Wird vom Launcher (Badge) und vom Aktualisierungs-Modul genutzt.
- **`Get-WingetInstalledList`** – Liefert installierte Programme als
  gefilterte Liste. Wird von Bibliothek und Uninstaller genutzt.

Beide Funktionen wenden dieselben Filter-Regeln an:

- PWAs (Firefox/Edge/Chromium-basiert) werden ausgeblendet
- Eintraege mit `Version = Unknown` werden als PWA-Artefakte gefiltert
- ARP-Registry-Pseudo-IDs werden ignoriert
- Duplikate per Winget-ID werden konsolidiert (hoechste Version gewinnt)

**Wartungsvorteil**: Filter-Regeln werden nur an dieser einen Stelle gepflegt.
Alle Module ziehen automatisch nach.

### Build-Pipeline

1. **`Build-IconCatalog.ps1`** (optional) – Laedt Icons aus dem
   [dashboard-icons](https://github.com/homarr-labs/dashboard-icons)-Repository
   in den `icon-catalog\`-Ordner.
2. **`Build.bat`** ruft `Build-Executables.ps1` auf:
   - Falls `Embed-Icons.ps1` und `icon-catalog\` vorhanden: Icons werden
     als Base64 in `Appstallo.ps1` eingebettet
   - `Appstallo.Common.ps1` wird vor `Appstallo.ps1` konkateniert
   - Das Resultat wird als .NET-Resource in eine `Appstallo.exe`
     einkompiliert (csc.exe, .NET Framework SDK)
3. **`Sign.bat`** (optional, nur lokal mit Certum-Zertifikat) – Signiert die
   fertige `.exe`.

### Wie die Module die Common-Funktionen erhalten

Beim Klick auf eine Modul-Kachel wird `$sync.StartTool` aufgerufen:

1. Generiert ein Temp-`.ps1`-File
2. Schreibt darin zuerst die Common-Funktionen (als String-Heredoc + 
   `Invoke-Expression`), dann den Modul-Code
3. Startet `powershell.exe -File <Temp>` als neuen Prozess

Damit haben die Modul-Prozesse Zugriff auf `Get-WingetUpdates` und
`Get-WingetInstalledList`, obwohl sie in eigenen Scopes laufen.

### Standalone-Ausfuehrung

Die einzelnen `.ps1`-Dateien koennen auch direkt aus dem Source-Ordner
gestartet werden. Sie laden die Common-Datei automatisch aus
`$PSScriptRoot`:

```powershell
.\Software-Bibliothek.ps1
```

---

## Datenspeicherorte

Appstallo speichert Cache- und Verlaufsdaten im lokalen Anwendungsverzeichnis:

```
%LOCALAPPDATA%\Appstallo\
```

Folgende Dateien werden dort angelegt:

| Datei | Inhalt | Gueltigkeitsdauer |
|---|---|---|
| `available-versions.json` | Cache der verfuegbaren Programmversionen | 24 Stunden |
| `descriptions-cache.json` | Cache der Programmbeschreibungen | Dauerhaft |
| `update-history.json` | Verlauf der durchgefuehrten Updates (max. 100 Eintraege) | Dauerhaft |
| `paused-updates.json` | Pausierte Updates (Winget-ID + Versions-Snapshot) | Dauerhaft |
| `custom-catalog.json` | Ueber den Software-Browser hinzugefuegte Programme | Dauerhaft |
| `custom-links.json` | Benutzerdefinierte Direktlinks | Dauerhaft |
| `custom-assignments.json` | Benutzerdefinierte Kategorie-Zuordnungen | Dauerhaft |
| `custom-catnames.json` | Namen benutzerdefinierter Kategorien | Dauerhaft |

Die Startmenue-Verknuepfung wird unter folgendem Pfad erstellt:

```
%APPDATA%\Microsoft\Windows\Start Menu\Programs\Appstallo.lnk
```

Alle Daten koennen bedenkenlos geloescht werden – sie werden beim naechsten Start automatisch neu erstellt (Beschreibungen muessen dann allerdings erneut abgerufen werden).

---

## Tipps und Hinweise

### Allgemein

- Das Programm benoetigt eine **aktive Internetverbindung** fuer Updates, Installationen und das Laden verfuegbarer Versionen
- Alle winget-Operationen werden mit dem Flag `--silent --force` ausgefuehrt, um manuelle Eingriffe zu minimieren

### Fehlerbehebung

- Falls der Updater keine Updates findet obwohl welche verfuegbar sind: Programm schliessen und erneut oeffnen
- Falls das Suchfeld nicht reagiert: den Suchbegriff loeschen (X-Button) und erneut eingeben
- Falls die EXE von einer Sicherheitssoftware blockiert wird: Die EXE ist mit einem Certum Open Source Developer Zertifikat signiert. Die Signatur kann ueber Rechtsklick → Eigenschaften → Digitale Signaturen ueberprueft werden
