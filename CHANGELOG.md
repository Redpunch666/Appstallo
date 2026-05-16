# Changelog

Alle wesentlichen Aenderungen an **Appstallo** werden in dieser Datei dokumentiert.

---

## v1.9.0 – 2026-05-16

Minor-Release mit Architektur-Refactor, erweiterter Behandlung verschiedener Installer-Typen (PWAs, MSIX, Squirrel), korrektem Taskleisten-Icon und automatischem Rescan nach Bibliotheks-Installation.

### Architektur-Refactor

- **Zentrale `Appstallo.Common.ps1`** – Funktionen `Get-WingetUpdates` und `Get-WingetInstalledList` werden jetzt einmal an einer Stelle gepflegt statt in mehreren Modulen redundant zu existieren. Die Common-Datei wird beim Build automatisch in den Launcher eingebettet und beim Start eines Moduls vor den Modul-Code injiziert. Damit gibt es **nur noch eine Stelle**, an der Filter-Regeln (PWA-Erkennung, Versions-Heuristik, etc.) gepflegt werden.

### Neue Erkennungs- und Filter-Regeln

- **PWAs werden überall ausgeblendet** – Firefox-PWAs (`FFPWA-...`), Edge-PWAs (`MSEDGE-PWA-...`), ARP-Registry-Einträge unter `^ARP\User\` / `^ARP\Machine\`, sowie Browser-PWAs mit Chromium-Hash-IDs (Chrome/Brave/Vivaldi/Opera mit 12+ alphanumerischen Zeichen) werden in allen Modulen ignoriert. Zusätzlich gilt: Einträge mit `Version = Unknown` werden als PWA-/Eigenupdater-Artefakte behandelt und ebenfalls gefiltert.
- **Squirrel-Apps werden erkannt** – Wenn `winget upgrade` aufgrund eines Squirrel-typischen Fehlers fehlschlägt (Exit Code 4294967295, "hash does not match", "requires explicit targeting"), prüft Appstallo das `%LOCALAPPDATA%\<AppName>\Update.exe`-Layout. Falls Match: kein „Fehler", sondern ein klarer Skip-Hinweis im Abschluss-Popup: *„App mit eigenem Updater – bitte App neu starten, sie aktualisiert sich automatisch"*.
- **MSIX/Store-Apps werden nativ behandelt** – Im Uninstaller wird `Remove-AppxPackage` statt `winget uninstall --silent` verwendet, was die Deinstallation von Apps wie Claude, iLovePDF oder WhatsApp zuverlässig macht. Im Updater erscheint ein klarer Hinweis im Abschluss-Popup mit Verweis auf den Microsoft Store: *„Store > Bibliothek > Updates abrufen"*.
- **Härterer Erfolgs-Check beim Deinstallieren** – Der 90-Sekunden-Poll prüft jetzt nicht nur `winget list`, sondern parallel `Get-AppxPackage` und die ARP-Registry. Damit werden falsch-positive „erfolgreich"-Meldungen vermieden, wenn das Programm in Wirklichkeit noch installiert ist.

### Verbesserungen

- **Korrektes Appstallo-Icon in der Taskleiste** – Die EXE setzt nun beim Start eine eigene **AppUserModelID** (`Appstallo.WingetSuite`) und der PowerShell-Host-Prozess wird konsistent mit dem eingebetteten Appstallo-Icon versehen. Damit zeigt Windows beim Anpinnen direkt aus dem laufenden Programm das Appstallo-Icon an – das frühere PowerShell-Icon und der weisse Platzhalter treten nicht mehr auf. Anpinnen direkt aus der laufenden Anwendung funktioniert jetzt korrekt; der frühere Workaround über das Startmenü ist nicht mehr nötig.
- **Automatischer Rescan nach Bibliotheks-Installation** – Nach erfolgreichem Klick auf den Zurueck-Button werden die installierten IDs neu eingelesen und die Bibliothek-Ansicht wird komplett neu aufgebaut. Damit erscheinen Programme, die gerade aus einem Preset installiert wurden, sofort als „Installiert" markiert (mit grauer Schrift und Installiert-Badge) statt weiterhin als „Verfuegbar".
- **Launcher bleibt im Vordergrund** – Nach Schliessen eines Moduls kommt das Launcher-Fenster wieder zuverlässig nach vorne.
- **Sauberes Beenden** – Beim Schliessen des Launchers wird der Appstallo-Prozess vollständig beendet (kein Hintergrund-Prozess mehr im Task-Manager).
- **Uninstaller-Titel vereinheitlicht** – Titelleiste und Überschrift heißen jetzt schlicht „Uninstaller" statt „Winget Uninstaller".
- **Alphabetische Sortierung im Uninstaller** – Kategorien werden konsistent alphabetisch sortiert angezeigt.

### Behoben

- **Store-Apps und Single-Token-IDs erscheinen in der Bibliothek** – Die alte Filterregel `$instId -notmatch '\.'` schloss alle Winget-IDs ohne Punkt aus (z.B. Microsoft Store IDs wie `9NLVZBZ2WZ28` für iLovePDF). Diese Programme tauchten beim Bibliothek-Scan überhaupt nicht auf. Jetzt werden sie korrekt eingeordnet und mit Installiert-Markierung versehen.
- **Duplikate werden konsolidiert** – Mehrere `winget list`-Einträge mit identischer Winget-ID (z.B. `Microsoft.WindowsAppRuntime.1.8` in mehreren Builds, `Microsoft.DirectX` doppelt) werden zusammengefasst; nur der Eintrag mit der höchsten Version bleibt sichtbar.
- **Launcher-Badge konsistent mit Updater** – Beide nutzen jetzt dieselbe Erkennungs-Routine über `Get-WingetUpdates`. Damit kann das Badge nicht mehr eine andere Anzahl als das Updater-Modul anzeigen.

### Mapping-Erweiterungen

- **Wispr Flow** (`9N1B9JWB3M35` → `wispr`) inklusive neuem Keyword `"wispr"` in der Kategorie *Office & Produktivität*

### Hinweis für Entwickler

Beim Build wird `Appstallo.Common.ps1` automatisch vor `Appstallo.ps1` in die EXE-Resource eingebettet. Bei direkter `.ps1`-Ausführung lädt der Launcher die Common-Datei aus dem gleichen Verzeichnis (`$PSScriptRoot`).

---

## v1.8.5 RC3 – 2026-05-14

> ⚠️ Release Candidate – iterative Verbesserungen am Icon-System und an der Behandlung verschiedener Installer-Typen (MSIX, Squirrel).

### Neu
- **MSIX/Store-Apps werden korrekt deinstalliert** – der Uninstaller erkennt MSIX-Apps automatisch und verwendet `Remove-AppxPackage` statt `winget uninstall --silent`. Damit funktioniert die Deinstallation von Apps wie Claude, iLovePDF oder WhatsApp jetzt zuverlässig.
- **MSIX-Apps im Updater werden korrekt behandelt** – statt fehlerhaft `winget upgrade --silent` zu versuchen, erscheint ein klarer Hinweis im Abschluss-Popup mit Verweis auf den Microsoft Store ("Store > Bibliothek > Updates abrufen") und kopierbaren Details.
- **Squirrel-basierte Apps werden erkannt** (Discord, Slack, GitHub Desktop, Atom etc.) – wenn `winget upgrade` aufgrund eines Squirrel-Konflikts fehlschlägt (typische Exit Codes wie 4294967295, "hash does not match", "requires explicit targeting"), wird im Abschluss-Popup ein passender Hinweis ausgegeben: "App mit eigenem Updater - bitte App neu starten, sie aktualisiert sich automatisch".
- **Härterer Erfolgs-Check beim Deinstallieren** – der 90-Sekunden-Poll prüft jetzt nicht nur `winget list`, sondern auch `Get-AppxPackage` und die ARP-Registry. Damit werden falsch-positive "erfolgreich"-Meldungen vermieden, wenn das Programm in Wirklichkeit noch installiert ist.

### Behoben
- **Store-Apps und Single-Token-IDs erscheinen jetzt in der Bibliothek** – die Filterregel `$instId -notmatch '\.'` schloss alle Winget-IDs ohne Punkt aus (z.B. `9NLVZBZ2WZ28` für Microsoft Store Apps). Diese Programme tauchten beim Bibliothek-Scan überhaupt nicht auf. Jetzt werden sie korrekt eingeordnet und mit Installiert-Markierung versehen.

### Mapping-Erweiterungen
- **Wispr Flow**: `'9N1B9JWB3M35' = 'wispr'`, zusätzlich neues Keyword `"wispr"` in der Office-Kategorie damit das Programm dort automatisch einsortiert wird

---

## v1.8.5 RC2 – 2026-05-13

> ⚠️ Release Candidate – Nachfolger von RC1 mit umfassendem Icon-System in allen vier Modulen.

### Neu
- **Programm-Icons in allen Modulen** – jedes Programm wird mit einem 24×24-Icon links neben dem Namen dargestellt (Software-Bibliothek, Software-Browser, Software-Aktualisierungen, Uninstaller)
- **Vierstufige Icon-Aufloesung mit klarer Priorisierung**:
  1. **Cache-Lookup** mit Mapping-Slug + Heuristik – fuer Programme mit eingetragenem Mapping wird das passende PNG aus dem eingebetteten Icon-Katalog (`%LOCALAPPDATA%\Appstallo\icon-cache\`) verwendet
  2. **EXE-Extraktion** via Win32-API (`SHGetFileInfo` + `IImageList` Jumbo-Icons, 256x256) – als Fallback fuer installierte Programme ohne Mapping
  3. **Online-Download** vom [dashboard-icons](https://github.com/homarr-labs/dashboard-icons)-CDN
  4. **Buchstabenkreis** als finaler Fallback
- **Eingebettete Icon-Sammlung** – ~150 kuratierte Slugs aus dem [homarr-labs/dashboard-icons](https://github.com/homarr-labs/dashboard-icons)-Repository werden direkt in die EXE eingebettet und beim ersten Start in den Cache entpackt (idempotent ueber Embed-Marker)
- **Erweiterbares Slug-Mapping** – ueber 280 Winget-ID-Zuordnungen, inkl. Microsoft Store Produkt-IDs (z.B. `9NLVZBZ2WZ28` fuer iLovePDF) und Microsoft-Komponenten (.NET Runtime → `microsoft`-Logo, VCRedist → `cpp`-Logo, WindowsAppRuntime → `microsoft-windows`-Logo)
- **Eigene Icons hinzufuegen** – beliebige PNGs koennen ins `icon-catalog\` gelegt werden und werden beim naechsten EXE-Build automatisch eingebettet (siehe GUIDE)
- **Build-IconCatalog.ps1** – laedt Icons aus dem dashboard-icons-CDN herunter. Drei Modi: Standard (nur Mapping-Slugs, ~5 MB), `-Extended` (~50 MB), `-All` (~100 MB)
- **Embed-Icons.ps1** – bettet die Icons als Base64-Hashtable in `Appstallo.ps1` ein. Standardmaessig nur die im Mapping referenzierten Slugs, damit die EXE schlank bleibt (~6 MB statt ~70 MB)
- **Build-Executables.ps1 ruft Embed-Icons.ps1 automatisch auf**, wenn `Embed-Icons.ps1` und `icon-catalog\` im selben Ordner liegen

### Geaendert
- **Cache-Lookup hat jetzt Vorrang vor EXE-Extraktion** – bei Programmen mit eingetragenem Slug wird zuerst das hochwertigere kuratierte PNG verwendet, statt dem oft generischen oder fehlerhaften Icon aus der EXE-Datei
- AssemblyVersion bleibt `1.8.5.0`, User-sichtbarer Versionstext: `v1.8.5 RC2`

### Behoben
- ARP-Datenbank speichert mehrere Eintraege pro DisplayName (z.B. bei doppelten "Claude"-Eintraegen wird der Eintrag mit passendem Publisher gewaehlt)
- `.ico`-Dateien werden direkt geladen statt ueber `SHGetFileInfo` (Vermeidung generischer Icons)
- Mapping-Patches verhindern **case-insensitive Duplikate** (PowerShell-Hashtables wuerfen sonst Parse-Errors)
- Embed-Icons.ps1 Regex erweitert auf `[a-zA-Z0-9\-]+` (sonst keine Slugs mit Grossbuchstaben wie `Ubisoft`, `Affinity`, `AquaSnap`, `BullzipPDFPrinter` eingebettet)
- Build-Executables.ps1 ruft Embed-Icons.ps1 direkt auf statt als Subprozess (Verhinderung von Pipe-Buffer-Deadlocks bei `| Out-Null`)
- Embed-Icons.ps1 hat neuen `-NoPause` Switch + dreifache Sicherheitspruefung gegen blockierendes `Read-Host` (NonInteractive, IsInputRedirected, expliziter Switch)
- Build-IconCatalog.ps1 schneidet `.png`-Endung der tree.json-Eintraege korrekt ab (sonst 0 Treffer im Mapping-Vergleich)

---


## v1.8.5 RC1 – 2026-05-13

> ⚠️ Release Candidate – diese Version wird als Testversion veroeffentlicht. Feedback zu Fehlern und Auffaelligkeiten ist willkommen.

### Neu
- **Selektive Updates** – die Update-Vorschau zeigt jetzt eine Checkbox-Liste statt Text. Per Klick koennen einzelne Updates aus dem Vorgang ausgenommen werden. Ein „Alle aus-/abwaehlen"-Toggle oben rechts wechselt schnell zwischen allen und keinem
- **Updates pausieren (bis Widerruf)** – neben jedem Update gibt es einen Pause-Button (⏸). Pausierte Updates werden in einer separaten Sektion unter der aktiven Liste angezeigt und in `paused-updates.json` dauerhaft gespeichert. Reaktivierung jederzeit per ▶-Button moeglich
- **Pause-aware Launcher** – Badge und Statustext auf der Aktualisierungen-Karte beruecksichtigen pausierte Updates. Verfuegbare und pausierte Anzahl werden separat dargestellt (z.B. „3 Update(s) verfuegbar  -  2 pausiert")
- **Erweitertes Problem-Popup im Updater** – nach Abschluss erscheint das Popup jetzt auch bei rein uebersprungenen Updates (nicht mehr nur bei fehlgeschlagenen). Statustext und Titel passen sich dynamisch an (fehlgeschlagen, uebersprungen, beides)
- **Programmbeschreibungen abrufen** – neuer Menuepunkt im Extras-Menue der Bibliothek laedt Beschreibungen aller Programme herunter, ohne eine Liste zu erzeugen
- **Beschreibungs-Cache** – einmal abgerufene Programmbeschreibungen werden in `descriptions-cache.json` gespeichert und beim naechsten Start automatisch geladen

### Geaendert
- „Neue Kategorie anlegen" vom Ende der Programmliste ins Extras-Menue verschoben
- Extras-Menue erhaelt eigenes Dark-Theme-Styling (roter Akzent links, kein weisser Gutter)
- Bibliotheksfenster standardmaessig groesser (1050x700 statt 900x640)
- Beschreibungen in der Bibliothek werden einzeilig angezeigt (Zeilenumbrueche entfernt)
- Name-Spalte in der Bibliothek verbreitert (280px statt 230px)
- Moduldateien umbenannt: `Software-Browser.ps1`, `Software-Bibliothek.ps1`, `Software-Aktualisierungen.ps1`, `Uninstaller.ps1`
- Updater nutzt jetzt die im Pre-Scan ermittelte Update-Liste direkt – keine redundante zweite winget-Abfrage mehr beim Start der Installation

### Behoben
- **Custom-Kategorie-Zuordnungen gingen nach Neustart verloren** – `custom-assignments.json` wurde zu spaet geladen (nach Verarbeitung des Custom-Catalogs). Lade-Reihenfolge umgestellt, sodass verschobene Programme dauerhaft in der gewaehlten Kategorie bleiben
- **Custom-Zuordnungen wurden in Preset-Exporten nicht korrekt mitgesichert** – `Dictionary` wurde als Array von Key/Value-Paaren serialisiert, beim Import wurde aber Property-Iteration erwartet. Export schreibt jetzt `PSCustomObject`, Import-Helper erkennt beide Formate (alte Backups bleiben kompatibel)
- HTML-Listenexport zeigte Programmnamen statt Beschreibungen (Regex im Background-Runspace hatte eingebettete Literal-Newlines statt explizites `\r?\n`)
- HTML-Druckansicht oeffnete sich nicht im Browser (`Start-Process` durch `Invoke-Item` ersetzt – Workaround fuer WPF-Dispatcher-Kontext)

---

## v1.8.3 – 2026-05-11

### Behoben
- **Update-Pruefung beim Launcher-Start** funktioniert jetzt zuverlaessig (Check wird im ContentRendered-Event ausgeloest, identischer Code wie der funktionierende Recheck nach Modul-Schließung)
- HTML-Druckansicht zeigt Programmbeschreibungen korrekt an (Beschreibungen werden nach dem Download in der Bibliotheks-UI aktualisiert)
- Info-Button liest jetzt immer den aktuellen Beschreibungstext (nicht mehr den bei UI-Aufbau eingefrorenen Wert)

---

## v1.8.2 – 2026-05-11

### Neu
- **Bibliothek zeigt echte Beschreibungen** – nach einer Listenausgabe (CSV/HTML) werden die heruntergeladenen Programmbeschreibungen direkt in der Bibliotheks-UI aktualisiert

### Behoben
- HTML-Druckansicht oeffnete sich beim ersten Mal nicht im Browser (Ausgabe wurde innerhalb des Timer-Ticks statt nach ShowDialog aufgerufen)
- Info-Button zeigte weiterhin „Auf diesem System installiert" obwohl die echte Beschreibung bereits per Listenausgabe geladen worden war

---

## v1.8.1 – 2026-05-11

### Neu
- **Update-Recheck nach Modul-Schließung** – nach dem Schließen eines Moduls wird der Update-Status automatisch neu ermittelt und das Badge auf der Aktualisierungen-Kachel aktualisiert (oder ausgeblendet)
- Statustext zeigt „Updates werden geprueft..." waehrend der Neuermittlung

### Behoben
- Update-Badge wurde nach durchgefuehrten Updates nicht aktualisiert (zeigte weiterhin die alte Anzahl)
- Launcher-Crash beim Schließen eines Moduls wenn keine Updates verfuegbar waren (Null-Referenz durch lokale Variablen im Timer-Scope)
- Initialer Update-Timer stoppte nicht wenn 0 Updates gefunden wurden (lief endlos im Hintergrund)
- Chevron-Pfeil auf der Updater-Kachel war groesser als bei den anderen Karten (falsches Unicode-Zeichen und abweichender Margin)

---

## v1.8.0 – 2026-05-11

### Neu
- **Automatische Update-Pruefung** – beim Start des Launchers wird im Hintergrund `winget upgrade` ausgefuehrt. Sind Updates verfuegbar, erscheint ein roter Badge auf der Aktualisierungen-Kachel mit der Anzahl (z.B. „3"), und der Statustext wechselt zu „3 Update(s) verfuegbar"
- **Benutzerdefinierte Kategorien** – in der Bibliothek koennen eigene Kategorien angelegt werden (Button „+ Neue Kategorie anlegen" am Ende der Programmliste)
- **Programme verschieben** – jeder Eintrag hat einen neuen Verschieben-Button, der einen Dialog mit allen verfuegbaren Kategorien oeffnet. Die Zuordnung wird in `custom-assignments.json` dauerhaft gespeichert und ueberlebt Neustarts und Rescans
- **Benutzerdefinierte Kategorien loeschen** – leere benutzerdefinierte Kategorien koennen ueber einen Loeschbutton im Kategorie-Header entfernt werden
- **Tooltips** auf Aktions-Buttons: „Details anzeigen", „In andere Kategorie verschieben", „Aus Bibliothek entfernen"
- **Extras-Menue** – die Footer-Buttons (Exportieren, Importieren, Liste ausgeben, Bibliothek leeren) wurden in ein aufgeraeumtes Dropdown-Menue zusammengefasst
- **Listenausgabe** (CSV und HTML/Druck) mit Programmbeschreibungen, die bei Bedarf per `winget show` nachgeladen werden (mit Fortschrittsanzeige)
- **Programmbeschreibungen on-demand** – beim Klick auf den Info-Button werden fehlende Beschreibungen automatisch per `winget show` nachgeladen

### Geaendert
- **Versionsnummerierung** auf 3-teilig umgestellt (Major.Minor.Patch)
- **Export/Import** sichert und stellt benutzerdefinierte Kategorien und Zuordnungen mit wieder her
- **Suchfeld-Darstellung** in Bibliothek und Uninstaller verbessert (Height Auto statt fixe 46px)
- **Direktlinks-Import** – URL-Eintraege werden beim Import korrekt als Direktlinks erkannt und nicht mehr in thematische Kategorien einsortiert
- **Modulbezeichnungen** in der Dokumentation an die tatsaechlichen Namen im Launcher angepasst (Software-Browser, Software-Bibliothek, Software-Aktualisierungen, Uninstaller)

### Behoben
- Direktlinks wurden beim Auswahl-Export faelschlicherweise im Programs-Feld statt im DirectLinks-Feld gespeichert

---

## v1.7.0.1 – 2026-05-10

### Behoben
- **Direktlinks-Import** – exportierte Direktlinks wurden beim Reimport faelschlicherweise per Keyword-Matching in thematische Kategorien einsortiert statt unter „Direktdownload" zu bleiben
- **Auswahl-Export** – URL-Eintraege (`URL:*`) werden jetzt korrekt in das `DirectLinks`-Feld statt `Programs` exportiert
- **Import-Fallback** – falls aeltere Backups URL-Eintraege im `Programs`-Feld enthalten, werden sie beim Import automatisch als Direktlinks erkannt
- **Suchfeld-Darstellung** – abgeschnittene Buchstaben (g, j, p, q, y) in Bibliothek und Uninstaller behoben (Zeilenhoehe von 46px auf Auto geaendert)

---

## v1.7.0.0 – 2026-05-10

### Neu
- **Automatische Systemerkennung** – beim Start der Bibliothek werden alle auf dem System installierten Programme via `winget list` erkannt, mit Name, ID und Versionsnummer erfasst und automatisch in thematische Kategorien einsortiert
- **15 thematische Kategorien** – Programme werden anhand von Schluesselwoertern automatisch zugeordnet:
  - Audio & Video, Browser & Internet, Cloud & Datenspeicher, E-Mail & Kalender, Entwicklung, Gaming & Plattformen, Grafik & Design, KI-Tools, Kommunikation, Laufzeiten & Frameworks, Netzwerk & Server, Office & Produktivitaet, Sicherheit & Datenschutz, System & Tools, Treiber & Hardware
- **Direkte Installation aus Import** – importierte Bibliotheken koennen direkt installiert werden (nur installieren oder installieren und zur Bibliothek hinzufuegen)
- **Bibliothek leeren** – neuer Button im Footer mit 15-Sekunden-Countdown zur Sicherheitsbestaetigung

### Geaendert
- **Builtin-Katalog entfernt** – die Bibliothek enthaelt keine vordefinierten Programme mehr und startet stattdessen mit einer automatischen Erkennung der installierten Software
- **Versionsnummerierung** – Kataloggroesse wird nicht mehr in der Versionsnummer gefuehrt (neu: v1.7.0.0)
- **Kategorien alphabetisch sortiert** – bei jedem UI-Aufbau; „Sonstige Programme" immer vorletzte, „Direktdownload" immer letzte Position
- **Programme alphabetisch sortiert** – innerhalb jeder Kategorie bei jedem UI-Aufbau
- **Export vereinfacht** – sichert nur noch benutzerdefinierte Programme und Direktlinks (keine Ausschlusslisten mehr)
- **Import vereinfacht** – drei Modi: Ueberschreiben, Zusammenfuehren, Direkt installieren (kein Builtin-Filtering mehr)
- **Loeschen vereinfacht** – entfernt Programme direkt aus `custom-catalog.json`/`custom-links.json` (keine Ausschlussliste mehr)
- **Reset vereinfacht** – loescht nur `custom-catalog.json` und `custom-links.json`

### Entfernt
- Fest eingebauter Programmkatalog (~77 Programme)
- `excluded-catalog.json` und gesamte Ausschlusslistenverwaltung
- `BuiltinCategories`-Logik

### Behoben
- ShowDialog-Crash beim Start der Bibliothek (fehlender catch-Block, ungefangene Fehler in SourceInitialized-Handler)
- Fehlende Initialisierung von `InstalledNames` in der `$sync`-Hashtable
- Import stellte nach Reset die komplette Bibliothek wieder her statt nur die importierten Programme

---

## v1.6.0.77 – 2026-05-10

### Neu
- **Bibliothek Export/Import** – die gesamte Software-Bibliothek kann als JSON-Backup exportiert und auf anderen Rechnern importiert werden
  - Export sichert alle Programme, Direktlinks und Ausschluesse
  - Import bietet zwei Modi: **Ueberschreiben** (Backup ersetzt alles) und **Zusammenfuehren** (bestehende und importierte Eintraege werden kombiniert)
  - Import bereinigt die Ausschlussliste automatisch, sodass zuvor geloeschte Programme nach dem Import wieder erscheinen
  - Bibliothek wird nach dem Import automatisch neu geladen (kein manuelles Schliessen noetig)
- **Katalog-Loeschfunktion** – Papierkorb-Button neben jedem Eintrag zum Entfernen aus der Bibliothek (Ausschlussliste in `excluded-catalog.json`)
- **Benutzerdefinierte Direktlinks** – ueber „+ Eigenen Link hinzufuegen" koennen eigene Download-Links angelegt werden (`custom-links.json`)
- **Software-Browser: Beschreibungen** – Info-Popup laedt vollstaendige Beschreibung und Herstellerinformationen via `winget show`
- **Software-Browser: Zur Bibliothek hinzufuegen** – gefundene Programme koennen mit Beschreibung dauerhaft zur Bibliothek hinzugefuegt werden
- **Keyword-basierte Auto-Kategorisierung** – ueber den Browser hinzugefuegte Programme werden anhand von Schluesselbegriffen automatisch in die passende Kategorie einsortiert
- **Startmenue-Verknuepfung** – wird beim ersten EXE-Start automatisch erstellt (korrektes Icon beim Taskleisten-Pinning)
- **Code-Signing** – EXE signiert mit Certum Open Source Developer Zertifikat (SHA256 + Zeitstempel)

### Geaendert
- **Launcher umstrukturiert** – neue Reihenfolge: Software-Browser → Software-Bibliothek → Software-Aktualisierungen → Uninstaller
- **Module umbenannt:** Programm-Browser → Software-Browser, Programm-Katalog → Software-Bibliothek, Programm-Aktualisierung → Software-Aktualisierungen
- Launcher-Subtitle: „Suchen · Katalog · Aktualisieren · Deinstallieren"
- Rotes SVG-Lupen-Icon fuer den Software-Browser im Launcher
- Schriftfarben in allen Modulen aufgehellt fuer bessere Lesbarkeit
- Suchfeld X-Button: sichtbarer (Padding-Fix, hellerer Hintergrund)
- Updater: Button zeigt nach Abschluss Ergebnis, Schliessen-Button wird rot
- Pre-Scan Parser: robuster durch Header+Trennlinien-Erkennung und `[\r\n]+` Split
- Import-Dialog: rote Auswahl-Cards mit schwarzer Schrift
- Direktdownload-Kategorie bleibt immer als letzte Kategorie
- Alphabetische Sortierung innerhalb aller Kategorien

### Behoben
- Loeschen bei aktiver Suche: Element wird komplett aus UI entfernt (nicht nur Visibility)
- PS5-Kompatibilitaet: Unicode-Regex durch `.TrimEnd()` ersetzt
- Popup-Icons: `$sync.AppIcon` statt `$script:appIcon` (Closure-Scope)
- Spinner-Zeichen (`- \ | /`) im Browser-Installationslog gefiltert
- Build: eindeutiger Temp-Dateiname mit GUID (ESET-Kompatibilitaet)
- Import: Ausschlussliste wird bereinigt damit geloeschte Builtin-Programme wiederhergestellt werden

---

## v1.5.3.77 – 2026-05-10

### Neu
- **Launcher umstrukturiert** – neue Reihenfolge: Software-Browser → Software-Bibliothek → Software-Aktualisierungen → Uninstaller
- **Module umbenannt:**
  - Software-Browser → **Software-Browser**
  - Software-Bibliothek → **Software-Bibliothek**
  - Software-Aktualisierungen → **Software-Aktualisierungen**
- **Rotes Lupen-Icon** im Launcher (SVG statt Emoji)
- **Software-Browser: Beschreibungen** – beim Klick auf den Info-Button wird die vollstaendige Beschreibung aus dem winget-Repository geladen (via `winget show`)
- **Katalog-Loeschfunktion** – jeder Eintrag hat ein X-Button zum Entfernen. Entfernte Eintraege werden in einer Ausschlussliste gespeichert (`excluded-catalog.json`) und koennen ueber den Software-Browser jederzeit wieder hinzugefuegt werden
- **Benutzerdefinierte Direktlinks** – in der Direktdownload-Kategorie kann ueber „+ Eigenen Link hinzufuegen" ein neuer Download-Link mit Name, URL und Beschreibung angelegt werden (gespeichert in `custom-links.json`)

### Datenspeicherorte (neu)
- `excluded-catalog.json` – IDs entfernter Katalogeintraege
- `custom-links.json` – benutzerdefinierte Direktdownload-Links

---

## v1.5.2.77 – 2026-05-09

### Neu
- **Software-Browser** – neues viertes Modul: durchsucht das winget-Repository nach beliebigen Programmen und ermoeglicht deren Installation direkt aus der Oberflaeche
  - Suchfeld mit Enter-Taste und Suchen-Button
  - Ergebnisliste mit Checkboxen, Versions-Badges und Info-Button
  - Winget-ID kopieren im Detail-Popup
  - Installation ausgewaehlter Programme mit Fortschrittsanzeige
  - Zurueck-zur-Suche-Funktion nach abgeschlossener Installation
  - **Zum Katalog hinzufuegen** – gefundene Programme koennen dauerhaft in den Installer-Katalog uebernommen werden (gespeichert in `custom-catalog.json`)
- **Installer: Benutzerdefinierte Kategorie** – liest beim Start die per Software-Browser hinzugefuegten Programme und zeigt sie als eigene Kategorie an
- **Launcher: 4. Modulkarte** (Software-Browser) mit Suchlupen-Icon

### Geaendert
- Launcher-Fensterhoehe angepasst fuer 4 Karten (540px statt 460px)
- Launcher-Subtitle erweitert: „Aktualisieren · Installieren · Deinstallieren · Suchen"

---

## v1.5.1.77 – 2026-05-09

### Neu
- **Startmenue-Verknuepfung** – wird beim ersten Start automatisch erstellt, damit das Programm ueber das Startmenue korrekt an die Taskleiste gepinnt werden kann (mit Appstallo-Icon statt PowerShell-Icon)

### Geaendert
- Alle grauen Schriftzuege in saemtlichen Modulen und Fenstern aufgehellt fuer bessere Lesbarkeit auf verschiedenen Displays (#555→#888, #444→#777, #333→#666, #2a2a2a→#555)

---

## v1.5.0.77 – 2026-05-08

### Neu
- **Code-Signing** – EXE wird mit Certum Open Source Developer Zertifikat signiert (SHA256 + Zeitstempel)
- **Sign.bat** – separates Signierungsskript (nur lokal, nicht auf GitHub)
- **.gitignore** – schliesst Sign.bat, EXEs und Zertifikatsdateien vom Repository aus
- **Launcher aufgehuebscht:**
  - Roter Akzent-Streifen links an jeder Modulkarte beim Hover
  - Status-Zeilen pro Modul (letztes Update-Datum, Cache-Groesse)
  - Versionsnummer im Footer (rechts unten)
- **Dark-Mode komplett:**
  - Alle Bestaetigungs-Dialoge (Deinstallation, Verlauf loeschen) als dunkle WPF-Fenster
  - Update-Historie-Popup mit eigenem Button-Style (roter Hover)
  - Leerer-Verlauf-Meldung als Dark-Fenster
- **Info-Button** (i) statt Rechtsklick fuer Programm-Details – intuitiver bedienbar
- **Winget-ID kopieren** – Button im Detail-Popup kopiert die ID in die Zwischenablage
- **Appstallo-Icon in allen Popup-Fenstern** (Detail, Historie, Bestaetigungen)

### Geaendert
- Suchfeld X-Button: sichtbarer (hellerer Hintergrund, Padding-Fix)
- Updater: Button zeigt nach Abschluss "X Update(s) erfolgreich" statt "Updates starten"
- Updater: Schliessen-Button wird nach Abschluss rot hervorgehoben
- Pre-Scan Parser: robuster durch Header+Trennlinien-Erkennung und `[\r\n]+` Split (winget-Spinner-kompatibel)

### Behoben
- PS5-Kompatibilitaet: `[\x{2026}>]+$` Regex durch `.TrimEnd()` ersetzt
- Icon in Popup-Fenstern: `$script:appIcon` durch `$sync.AppIcon` ersetzt (Closure-Scope-Problem)
- Icon-Block in Modulen: doppelte geschweifte Klammern `try {{` behoben (Python-Escaping-Artefakt)

---

## v1.4.4.77 – 2026-05-08

### Neu
- **Info-Button** (ⓘ) neben jedem Programm im Installer und Uninstaller – oeffnet ein Detail-Popup mit Hersteller, Winget-ID, Version und Beschreibung
- **Winget-ID kopieren** – im Detail-Popup kann die ID per Klick in die Zwischenablage kopiert werden
- **Dunkle Titelleisten** in allen Fenstern und Popups (DWM Dark Mode)
- **Dunkle Scrollbars** passend zum Dark-Theme
- **Button-Hover in Rot** statt Standard-Windows-Blau
- **Appstallo-Icon** in Titelleiste und Taskleiste aller Fenster (eingebettet als Base64)
- **Update-Historie-Popup** mit dunkler Titelleiste und eigenem Icon

### Geaendert
- Detail-Popup als eigenes Dark-Mode-Fenster statt System-MessageBox
- Update-Historie-Button umbenannt von „Verlauf" zu „Update-Historie"

---

## v1.4.2.77 – 2026-05-07

### Neu
- **Updater-Vorschau** – beim Oeffnen wird automatisch nach Updates gesucht und eine formatierte Liste angezeigt (Programmname, aktuelle Version → verfuegbare Version)
- **Update-Historie** – jedes erfolgreiche Update wird in `%LOCALAPPDATA%\Appstallo\update-history.json` geloggt; Button zum Anzeigen der letzten 30 Updates mit Datum und Versionswechsel
- **Verfuegbare Versionen** im Installer – nicht installierte Programme zeigen ein oranges Badge „Verfuegbar vX.Y.Z" an
- **Versions-Cache** fuer verfuegbare Versionen (1 Tag gueltig, Hintergrund-Loader)

### Geaendert
- Versions-Parsing mit Regex-Fallback bei winget-Truncation (z.B. 1Password)
- Pre-Scan Parser nutzt `[\r\n]+` Split (winget-Spinner-Kompatibilitaet)

---

## v1.4.1.77 – 2026-05-07

### Neu
- **Suchfeld** im Installer und Uninstaller – filtert live nach Name, ID und Beschreibung
- **Versionsanzeige** im Installer – gruenes Badge „Installiert vX.Y.Z" mit erkannter Version
- **Groessenanpassbare Fenster** – Launcher mit MinWidth/MinHeight, Module waren bereits resizable
- **Benutzungsanleitung** in der README ergaenzt

### Geaendert
- eM Client von „Office & Produktivitaet" nach „Browser & Internet" verschoben (gleiche Kategorie wie Thunderbird)
- Leere Kategorien werden beim Filtern korrekt ausgeblendet (HashCode-basiert)

---

## v1.4.0.77 – 2026-05-06

### Neu
- **Uninstaller-Verifikation** – bei fehlgeschlagener Deinstallation (z.B. Opera mit GUI-Uninstaller) wird bis zu 90 Sekunden lang geprueft ob das Programm tatsaechlich entfernt wurde
- **Inline-Fortschrittsbalken** im Log-Bereich aller Module mit synthetischer Animation
- **Deterministische Progress-Bar** statt Indeterminate-Animation

### Geaendert
- Fortschrittsbalken-Logik ueberarbeitet: synthetischer Fortschritt wenn winget keine Live-Prozente liefert

---

## v1.3.0.77 – 2026-05-05

### Erster Release
- **Launcher** mit drei Modulkarten (Updater, Installer, Uninstaller)
- **Updater** – sucht und installiert Updates fuer alle winget-verwalteten Programme
- **Installer** – 77 Programme in 9 Kategorien + 14 Direktdownloads, Checkbox-Auswahl
- **Uninstaller** – analysiert installierte Software, kategorisiert und deinstalliert
- **EXE-Build** mit C# Wrapper, Admin-Elevation, eingebettetem PS1-Code
- **Dark Theme** – durchgehendes Rot/Schwarz-Design (#c0392b / #161616)
- **Appstallo.ico** als Anwendungsicon (7 Aufloesungen: 16–256px)
- **MIT-Lizenz**, GitHub-Repository
