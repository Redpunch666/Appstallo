# Appstallo – Haeufig gestellte Fragen (FAQ)

## Inhaltsverzeichnis

1. [Allgemein](#allgemein)
2. [Installation und Start](#installation-und-start)
3. [Software-Aktualisierungen](#software-aktualisierungen)
4. [Software-Bibliothek](#software-bibliothek)
5. [Uninstaller](#uninstaller)
6. [Software-Browser](#software-browser)
7. [Export und Import](#export-und-import)
8. [Sicherheit und Datenschutz](#sicherheit-und-datenschutz)
9. [Darstellung und Oberflaeche](#darstellung-und-oberflaeche)
10. [Fehlerbehebung](#fehlerbehebung)

---

## Allgemein

### Was ist Appstallo?

Appstallo ist eine grafische Verwaltungssuite fuer den Windows Package Manager (winget). Das Programm ermoeglicht es, das winget-Repository nach Software zu durchsuchen, Programme direkt zu installieren und individuelle Software-Bibliotheken zusammenzustellen. Diese Bibliotheken lassen sich als Presets exportieren und importieren – ideal fuer die Einrichtung verschiedener Computer oder Einsatzszenarien. Appstallo ist kostenlos, quelloffen (MIT-Lizenz) und auf GitHub verfuegbar.

### Was ist winget?

winget ist der offizielle Paketmanager von Microsoft fuer Windows. Er ermoeglicht das Installieren und Aktualisieren von Programmen ueber die Kommandozeile. Appstallo baut auf winget auf und bietet eine benutzerfreundliche grafische Oberflaeche dafuer.

### Welche Windows-Version wird benoetigt?

Windows 10 ab Version 1809 (Oktober 2018 Update) oder Windows 11. Aeltere Windows-Versionen werden nicht unterstuetzt, da winget dort nicht verfuegbar ist.

### Muss winget separat installiert werden?

Bei aktuellen Windows 10/11 Installationen ist winget bereits vorinstalliert. Um das zu pruefen, oeffne die Eingabeaufforderung (cmd) und tippe `winget --version`. Wenn eine Versionsnummer angezeigt wird, ist winget vorhanden. Andernfalls kann der „App-Installer" aus dem Microsoft Store installiert werden.

### Warum werden Administratorrechte benoetigt?

winget benoetigt fuer die meisten Installationen und Deinstallationen Administratorrechte, da Programme systemweit installiert werden. Appstallo fordert diese Rechte beim Start automatisch an.

### Kann ich das Programm auch ohne EXE nutzen?

Ja. Die einzelnen PowerShell-Skripte (`.ps1`-Dateien) koennen direkt ausgefuehrt werden: Rechtsklick → „Mit PowerShell ausfuehren". Die EXE ist lediglich ein Wrapper der den Start vereinfacht und das eigene Icon bereitstellt.

---

## Installation und Start

### Muss das Programm installiert werden?

Nein. Appstallo ist eine portable Anwendung. Die EXE kann in einen beliebigen Ordner gelegt und von dort direkt gestartet werden. Es werden keine Registry-Eintraege oder Systemdateien veraendert.

### Beim Start erscheint eine SmartScreen-Warnung. Ist die Datei sicher?

Die EXE ist mit einem Certum Open Source Developer Zertifikat signiert. Die Signatur kann ueber **Rechtsklick → Eigenschaften → Digitale Signaturen** ueberprueft werden. SmartScreen-Warnungen treten bei neuen Programmen auf, weil Microsoft erst eine Reputationsdatenbank aufbauen muss. Mit der Zeit verschwindet die Warnung automatisch.

### ESET oder ein anderer Virenscanner blockiert die EXE. Was tun?

Einige Virenscanner melden PowerShell-basierte EXEs als potenziell unerwuenscht. Das ist ein Fehlalarm. Die EXE enthaelt lediglich ein PowerShell-Skript das winget-Befehle ausfuehrt. Moegliche Loesungen:

- Die EXE als Ausnahme im Virenscanner hinterlegen
- Die digitale Signatur pruefen (Rechtsklick → Eigenschaften → Digitale Signaturen)
- Alternativ die `.ps1`-Dateien direkt mit PowerShell ausfuehren

### Wie hefte ich das Programm an die Taskleiste an?

Appstallo bei laufendem Programm einfach per Rechtsklick auf das Taskleisten-Symbol → **An Taskleiste anheften** auswaehlen. Seit v1.9.0 RC3 wird dabei zuverlaessig das Appstallo-Icon (statt PowerShell- oder Platzhalter-Icon) verwendet.

### Wo werden Daten gespeichert?

Alle Daten liegen unter `%LOCALAPPDATA%\Appstallo\`:

- `available-versions.json` – Cache fuer verfuegbare Programmversionen (wird nach 24 Stunden erneuert)
- `descriptions-cache.json` – Cache fuer Programmbeschreibungen
- `update-history.json` – Protokoll der durchgefuehrten Updates (max. 100 Eintraege)
- `paused-updates.json` – Pausierte Updates (Winget-ID + Versions-Snapshot)
- `custom-catalog.json` – Ueber den Software-Browser hinzugefuegte Programme
- `custom-links.json` – Benutzerdefinierte Direktlinks
- `custom-assignments.json` – Benutzerdefinierte Kategorie-Zuordnungen
- `custom-catnames.json` – Namen benutzerdefinierter Kategorien

Diese Dateien koennen bedenkenlos geloescht werden.

---

## Software-Aktualisierungen

### Der Updater findet keine Updates, obwohl welche vorhanden sind.

Moegliche Ursachen:

- **winget-Quellen muessen aktualisiert werden**: Oeffne eine Eingabeaufforderung und fuehre `winget source update` aus
- **Programm neu starten**: Den Updater schliessen und erneut oeffnen – der Pre-Scan startet dann erneut

### Was bedeuten die Zahlen in der Zusammenfassung?

- **Erfolgreich**: Update wurde heruntergeladen und installiert
- **Fehlgeschlagen**: winget konnte das Update nicht installieren (z.B. weil das Programm gerade laeuft oder der Installer-Typ nicht unterstuetzt wird)
- **Uebersprungen**: winget konnte das Ergebnis nicht eindeutig bestimmen (z.B. bei Programmen mit interaktivem Installer)

### Was zeigt das Problem-Popup nach den Updates?

Falls Updates fehlgeschlagen oder uebersprungen wurden, erscheint automatisch ein Popup mit detaillierten Problemgruenden. Fuer jedes Programm werden Name, Versionswechsel und Grund angezeigt. Neben jedem Eintrag gibt es einen Kopieren-Button, um den Text einzeln in die Zwischenablage zu uebernehmen. Der Titel passt sich an die Art des Problems an („fehlgeschlagen", „uebersprungen" oder „mit Problemen" bei gemischten Faellen).

### Kann ich einzelne Updates ueberspringen?

Ja. Die Update-Vorschau zeigt eine Checkbox-Liste – standardmaessig sind alle Updates ausgewaehlt. Per Klick auf die Checkbox eines Updates wird es vom aktuellen Vorgang ausgenommen. Der Toggle **Alle abwaehlen** / **Alle auswaehlen** oben rechts hilft bei groesseren Listen.

### Wie unterscheidet sich „abwaehlen" von „pausieren"?

- **Abwaehlen (Checkbox)**: Das Update wird nur fuer diesen Vorgang uebersprungen. Beim naechsten Modul-Start ist es wieder ausgewaehlt
- **Pausieren (⏸-Button)**: Das Update wird permanent aus der Liste entfernt. Es taucht weder im Updater noch im Launcher-Badge auf, bis es manuell reaktiviert wird

### Wie pausiere ich ein Update?

Rechts neben jedem Update gibt es einen Pause-Button (⏸). Ein Klick darauf verschiebt das Update in die Sektion **Pausiert** unter der aktiven Liste. Die Pausierung wird in `paused-updates.json` dauerhaft gespeichert.

### Wie reaktiviere ich ein pausiertes Update?

In der Sektion **Pausiert** befindet sich neben jedem Eintrag ein **▶ Reaktivieren**-Button. Ein Klick darauf entfernt die Pausierung. Wenn winget das Update weiterhin als verfuegbar meldet, erscheint es wieder in der aktiven Liste.

### Werden pausierte Updates im Launcher-Badge mitgezaehlt?

Nein. Das Badge auf der Aktualisierungen-Karte zeigt nur die Anzahl tatsaechlich verfuegbarer, nicht pausierter Updates. Pausierte Eintraege werden im Statustext separat ausgewiesen, z.B. „3 Update(s) verfuegbar  -  2 pausiert".

### Was passiert, wenn ich ein pausiertes Programm manuell aktualisiere?

Nichts Besonderes. Wenn die neue Version installiert ist, meldet winget keinen Update mehr fuer dieses Programm, und es verschwindet automatisch aus der pausierten Liste. Die Pausierung wirkt sich nur auf die Anzeige aus, nicht auf das Programm selbst.

### Was passiert wenn ich waehrend eines Updates den PC herunterfahre?

Das laufende Update wird abgebrochen. Beim naechsten Start des Updaters wird das abgebrochene Programm erneut als Update angeboten.

### Wo finde ich die Update-Historie?

Im Updater unten links auf **Update-Historie** klicken. Das Fenster zeigt die letzten Updates (maximal 100 Eintraege) mit Datum, Programmname und Versionswechsel.

---

## Software-Bibliothek

### Was bedeuten die farbigen Badges neben den Programmnamen?

- **Gruenes Badge „Installiert vX.Y.Z"**: Das Programm ist bereits installiert und zeigt die erkannte Version
- **Oranges Badge „Verfuegbar vX.Y.Z"**: Das Programm ist nicht installiert; die angezeigte Version ist die aktuell ueber winget verfuegbare Version

### Die Versions-Badges erscheinen nicht sofort. Warum?

Die verfuegbaren Versionen werden im Hintergrund geladen, da fuer jedes nicht installierte Programm eine separate Abfrage bei winget noetig ist. Beim ersten Start kann das 1-2 Minuten dauern. Die Daten werden anschliessend fuer 24 Stunden lokal gecacht, sodass sie beim naechsten Start sofort verfuegbar sind.

### Wie lade ich Programmbeschreibungen?

Zwei Wege: Einzeln per **Info-Button** (i) neben jedem Programm, oder fuer alle Programme auf einmal ueber **Extras → Programmbeschreibungen abrufen**. Die Beschreibungen werden im Cache gespeichert und stehen beim naechsten Start sofort zur Verfuegung.

### Was ist der Unterschied zwischen winget-Programmen und Direktdownloads?

- **winget-Programme** werden automatisch ueber den Windows Package Manager heruntergeladen und installiert
- **Direktdownloads** sind Programme die nicht im winget-Katalog verfuegbar sind. Bei diesen wird die offizielle Hersteller-Webseite im Browser geoeffnet, und der Download muss manuell durchgefuehrt werden

### Wie finde ich die Winget-ID eines Programms?

Klicke auf den **Info-Button** (i) rechts neben dem Programmnamen. Im Detail-Fenster wird die Winget-ID angezeigt. Ueber den Button **ID kopieren** kann die ID direkt in die Zwischenablage kopiert werden.

### Wie kann ich Eintraege aus der Bibliothek entfernen?

Klicke auf den Loeschen-Button (Papierkorb-Symbol) rechts neben dem Programm. Nach einer Sicherheitsabfrage wird der Eintrag aus der Bibliothek entfernt.

### Kann ich eigene Programme zur Bibliothek hinzufuegen?

Ja, ueber zwei Wege:

1. **Software-Browser**: Programm suchen, per Checkbox auswaehlen und auf **Zum Katalog** klicken – das Programm wird dauerhaft in `custom-catalog.json` gespeichert
2. **Manuell**: Die Datei `%LOCALAPPDATA%\Appstallo\custom-catalog.json` bearbeiten oder den Quellcode (`Software-Bibliothek.ps1`) anpassen

### In welche Kategorien werden Programme einsortiert?

Es gibt 15 vordefinierte Kategorien: Audio & Video, Browser & Internet, Cloud & Datenspeicher, E-Mail & Kalender, Entwicklung, Gaming & Plattformen, Grafik & Design, KI-Tools, Kommunikation, Laufzeiten & Frameworks, Netzwerk & Server, Office & Produktivitaet, Sicherheit & Datenschutz, System & Tools, Treiber & Hardware. Zusaetzlich koennen ueber das Extras-Menue beliebig viele eigene Kategorien angelegt werden.

---

## Uninstaller

### Ein Programm kann nicht deinstalliert werden. Was tun?

Moegliche Ursachen:

- **Das Programm laeuft noch**: Programm vorher vollstaendig beenden (auch Hintergrundprozesse im Task-Manager pruefen)
- **Der Uninstaller ist interaktiv**: Einige Programme (z.B. Opera) oeffnen ein eigenes Deinstallationsfenster. Dieses muss manuell bestaetigt werden – das Modul wartet bis zu 90 Sekunden darauf
- **Fehlende Rechte**: In seltenen Faellen benoetigt die Deinstallation SYSTEM-Rechte, die auch als Administrator nicht verfuegbar sind

### Was passiert wenn der Uninstaller „Fehlgeschlagen" meldet, das Programm aber trotzdem weg ist?

Das kann bei Programmen mit externem GUI-Uninstaller passieren. winget meldet einen Fehler, aber das Programm wurde tatsaechlich entfernt. Das Modul prueft automatisch bis zu 90 Sekunden lang, ob das Programm noch installiert ist. Wenn nicht, wird die Deinstallation als erfolgreich gewertet.

### Werden bei der Deinstallation auch Benutzerdaten geloescht?

Das haengt vom jeweiligen Programm ab. Appstallo fuehrt lediglich den winget-Befehl `winget uninstall` aus. Ob dabei Benutzerdaten, Einstellungen oder App-Daten entfernt werden, entscheidet der Uninstaller des jeweiligen Programms. In der Regel bleiben Benutzerdaten erhalten.

---

## Software-Browser

### Wozu brauche ich den Software-Browser wenn es schon die Bibliothek gibt?

Die Bibliothek enthaelt die auf dem System installierten Programme und manuell hinzugefuegte Eintraege. Der Software-Browser durchsucht dagegen das gesamte winget-Repository mit ueber 10.000 Programmen. Wenn ein Programm nicht in der Bibliothek enthalten ist, kann es ueber den Software-Browser gefunden und installiert werden.

### Wie finde ich ein bestimmtes Programm?

Gib den Programmnamen oder einen Teil davon in das Suchfeld ein. Fuer genauere Ergebnisse kann auch die Winget-ID verwendet werden (z.B. „Microsoft.VisualStudioCode" statt „Visual Studio Code"). Die Suche benoetigt mindestens 2 Zeichen.

### Die Suche liefert sehr viele Ergebnisse. Wie kann ich filtern?

Verwende einen moeglichst spezifischen Suchbegriff. Statt „microsoft" besser „microsoft office" oder die genaue Winget-ID eingeben. winget liefert standardmaessig alle Treffer zurueck.

### Kann ich Programme aus dem Software-Browser dauerhaft in die Bibliothek uebernehmen?

Ja. Waehle die gewuenschten Programme per Checkbox aus und klicke auf **Zum Katalog**. Die Programme werden lokal gespeichert und erscheinen beim naechsten Start der Bibliothek unter der passenden Kategorie. Die Datei liegt unter `%LOCALAPPDATA%\Appstallo\custom-catalog.json` und kann bei Bedarf manuell bearbeitet oder geloescht werden.

### Kann ich ueber den Software-Browser auch Programme aktualisieren oder deinstallieren?

Nein, der Software-Browser ist ausschliesslich fuer die Suche und Installation gedacht. Fuer Updates das Modul Software-Aktualisierungen verwenden, fuer Deinstallationen den Uninstaller.

---

## Export und Import

### Wie exportiere ich meine Bibliothek?

In der Software-Bibliothek im **Extras-Menue** auf **Exportieren** klicken, Speicherort waehlen – fertig. Die JSON-Datei enthaelt alle Programme, Direktlinks sowie benutzerdefinierte Kategorien und Zuordnungen.

### Kann ich ein Backup auf einem anderen Computer importieren?

Ja, genau dafuer ist die Funktion gedacht. Die Backup-Datei auf den Zielrechner kopieren, dort in der Software-Bibliothek im **Extras-Menue** auf **Importieren** klicken und die Datei auswaehlen.

### Was bedeutet „Benutzerdefinierte Zuordnungen werden mitgesichert"?

Wenn du Programme manuell in andere Kategorien verschoben hast (per Verschieben-Button in der Bibliothek), werden diese Zuordnungen im Export gespeichert. Beim Import auf einem anderen Rechner landen die Programme automatisch wieder in denselben Kategorien – ohne dass die Verschiebungen erneut vorgenommen werden muessen.

### Was ist der Unterschied zwischen Ueberschreiben und Zusammenfuehren?

**Ueberschreiben** ersetzt die komplette aktuelle Bibliothek durch das Backup. **Zusammenfuehren** kombiniert beide – bestehende Eintraege bleiben erhalten, neue aus dem Backup werden hinzugefuegt. Duplikate (gleiche Winget-ID) werden automatisch uebersprungen.

### Kann ich verschiedene Presets fuer verschiedene Rechner anlegen?

Ja. Exportiere fuer jedes Szenario eine eigene Backup-Datei (z.B. „Arbeits-PC.json", „Gaming-PC.json", „Medienbearbeitung.json"). Beim Einrichten eines neuen Rechners importierst du einfach das passende Preset.

---

## Sicherheit und Datenschutz

### Ist Appstallo sicher?

Ja. Das Programm ist vollstaendig quelloffen – der gesamte Quellcode ist auf GitHub einsehbar. Die EXE ist ein kompilierter Wrapper um die PowerShell-Skripte und enthaelt keinen schaedlichen Code. Die EXE ist mit einem Certum Open Source Developer Zertifikat digital signiert.

### Werden Daten an Dritte uebertragen?

Nein. Appstallo kommuniziert ausschliesslich mit den winget-Quellen (standardmaessig der Microsoft winget-Katalog) und den offiziellen Hersteller-Servern fuer Downloads. Es werden keine Nutzungsdaten, Telemetriedaten oder persoenlichen Informationen erhoben oder uebertragen.

### Warum liest das Programm installierte Software aus?

Um die Versions-Badges und die Kategorisierung korrekt anzuzeigen, muss das Programm die Liste der installierten Software abfragen. Dies geschieht ueber den winget-Befehl `winget list`, der nur lokal ausfuehrbar ist und keine Daten nach aussen sendet.

### Kann ich den Quellcode selbst pruefen und kompilieren?

Ja. Alle Quelldateien sind auf GitHub verfuegbar. Die `Build.bat` erstellt die EXE-Datei aus den PowerShell-Skripten. Dafuer wird lediglich das auf jedem Windows vorinstallierte .NET Framework benoetigt.

---

## Darstellung und Oberflaeche

### Die Titelleiste ist hell statt dunkel. Woran liegt das?

Die dunkle Titelleiste wird ueber die Windows DWM-API aktiviert und erfordert Windows 10 ab Version 1809 oder Windows 11. Bei aelteren Windows-Versionen bleibt die Titelleiste im Standard-Design.

### Die Schrift ist schwer lesbar auf meinem Monitor.

Die Schriftfarben wurden fuer dunkle Hintergruende optimiert. Falls die Lesbarkeit trotzdem nicht ausreicht, kann die Windows-Anzeigeskalierung erhoeht werden (Einstellungen → Anzeige → Skalierung).

### Wird in der Taskleiste das richtige Icon angezeigt?

Ja. Seit v1.9.0 RC3 setzt Appstallo eine eigene AppUserModelID und ein konsistentes Fenster-Icon, sodass Windows beim Anpinnen das Appstallo-Icon verwendet – nicht mehr das PowerShell-Symbol oder einen weissen Platzhalter. Falls noch ein altes, falsch gepinntes Icon existiert: einfach von der Taskleiste loesen und neu anheften.

---


## Programm-Icons

### Warum zeigt mein Programm nur einen Buchstabenkreis statt eines Icons?

Appstallo probiert vier Quellen fuer Icons in dieser Reihenfolge: Cache (kuratierte PNGs), EXE-Extraktion (bei installierten Programmen), Online-Download und schliesslich der Buchstabenkreis als Fallback. Wenn keine dieser Quellen funktioniert, erscheint der Anfangsbuchstabe. Haeufige Gruende:

- Das Programm ist nicht installiert (Stufe 2 entfaellt) und nicht im Slug-Mapping vorhanden (Stufe 1 entfaellt)
- Die installierte EXE hat kein gutes Icon und der CDN-Server ist nicht erreichbar
- Das Programm verwendet eine Microsoft-Store-ID (12-stellig alphanumerisch), die nicht im Mapping vorhanden ist

### Kann ich eigene Icons fuer Programme hinzufuegen?

Ja. Lege eine PNG-Datei (transparent, idealerweise 128x128) in `icon-catalog\` ab und ergaenze einen Eintrag in `$IconSlugMap` in `Appstallo.ps1`. Dann `Build.bat` neu starten. Detaillierte Anleitung siehe [GUIDE.md](GUIDE.md#programm-icons-anpassen).

### Warum erscheint bei einigen Programmen ein falsches oder generisches Icon?

Bei installierten Programmen ohne Mapping-Eintrag wird das Icon direkt aus der EXE-Datei extrahiert. Manche Programme haben keine echten Icons in ihrer Haupt-EXE eingebettet (z.B. .NET-Anwendungen ohne Resource-Block) oder ihre Helper-EXE liefert ein nichtssagendes Standard-Icon. Loesung: einen Mapping-Eintrag fuer die Winget-ID anlegen und eine bessere PNG hinzufuegen.

### Werden Icons online nachgeladen, wenn ich offline bin?

Nein, der Online-Download (Stufe 3) wird einfach uebersprungen. Es greifen dann ausschliesslich die im Cache vorhandenen PNGs und die EXE-Extraktion. Der Buchstabenkreis erscheint als letzter Fallback.

### Wie viele Icons sind in der EXE eingebettet?

In der Standard-Konfiguration ca. 130 kuratierte Icons aus dem [dashboard-icons](https://github.com/homarr-labs/dashboard-icons)-Repository. Das fuehrt zu einer EXE-Groesse von ca. 6 MB. Wer auf Icons komplett verzichten moechte, kann den Embed-Schritt ueberspringen – die EXE bleibt dann bei ca. 700 KB.

### Wo werden die ausgepackten Icons gespeichert?

`%LOCALAPPDATA%\Appstallo\icon-cache\`. Beim ersten EXE-Start werden alle eingebetteten Icons hierhin entpackt (idempotent, nur einmalig). Beim Loeschen des Ordners wird er beim naechsten Start wieder neu befuellt. Dort landen auch online nachgeladene Icons (Stufe 3).

---


## Installer-Typen und Update-Verhalten

### Warum erscheint meine Progressive Web App (PWA) nicht in Appstallo?

Seit v1.9.0 RC3 werden PWAs (Progressive Web Apps) in allen Modulen
ausgeblendet. Der Grund: PWAs sind im Wesentlichen Browser-Verknuepfungen
und lassen sich nicht ueber `winget` aktualisieren oder zuverlaessig
deinstallieren. Eine ueber den Browser installierte PWA aktualisiert sich
zusammen mit dem Browser; die Deinstallation erfolgt ueber den Browser
("App entfernen") oder ueber die Windows-Einstellungen unter "Apps".

Falls eine echte App faelschlicherweise als PWA erkannt wird, kann das ein
Hinweis sein, dass:

- die installierte Version `Unknown` ist (z.B. bei Eigen-Updater-Apps wie
  Discord, Slack)
- die Winget-ID ein typisches PWA-Muster enthaelt (z.B. `FFPWA-...`,
  `MSEDGE-PWA-...` oder einen Chromium-Hash)

In so einem Fall bitte ein GitHub-Issue mit der Ausgabe von `winget list`
fuer die betroffene App eroeffnen.

### Mein Microsoft-Store-Programm (Claude, iLovePDF, WhatsApp ...) liess sich nicht aktualisieren

MSIX/Store-Apps werden vom Microsoft Store automatisch im Hintergrund
aktualisiert. `winget upgrade --silent` funktioniert dort nicht
zuverlaessig. Appstallo erkennt das jetzt automatisch und zeigt
stattdessen einen Skip-Hinweis im Abschluss-Popup: *"Bitte ueber den
Microsoft Store aktualisieren (Store > Bibliothek > Updates abrufen)"*.

### Mein Discord/Slack/GitHub-Desktop-Update geht nicht durch

Solche Programme verwenden einen eigenen Updater (Squirrel/Electron), der
parallel zu `winget` laeuft. Falls `winget upgrade` mit typischen
Squirrel-Fehlern (Exit Code 4294967295, "hash does not match" usw.)
abbricht, zeigt Appstallo jetzt automatisch einen Hinweis im
Abschluss-Popup: *"App mit eigenem Updater - bitte App neu starten, sie
aktualisiert sich automatisch. Falls nicht: deinstallieren und neu
installieren."*

### Warum sieht das Aktualisierungs-Modul manchmal andere Updates als das Launcher-Badge?

Seit v1.9.0 RC3 nicht mehr - beide nutzen jetzt dieselbe zentrale
Erkennungs-Routine (`Get-WingetUpdates`). Falls dir trotzdem eine
Diskrepanz auffaellt, bitte ein GitHub-Issue eroeffnen.

### Warum wird mein Programm mit "Unknown" als installierte Version angezeigt?

`Unknown` bedeutet, dass winget die installierte Version nicht aus der
Windows-Registry auslesen konnte. Das passiert bei:

- PWAs (Progressive Web Apps) - dort sind Versions-Infos nicht hinterlegt
- Einigen Squirrel-/Electron-Apps - die tragen die Version nicht in den
  ARP-Eintrag ein
- Sehr alten oder kaputten Installationen

Seit v1.9.0 RC3 werden solche Eintraege automatisch in den Filtern beruecksichtigt.

---

## Fehlerbehebung

### Das Programm startet nicht oder zeigt einen Fehler.

- **winget ist nicht installiert**: In der Eingabeaufforderung `winget --version` pruefen. Falls nicht vorhanden: „App-Installer" aus dem Microsoft Store installieren
- **PowerShell-Ausfuehrungsrichtlinie**: Falls die PS1-Dateien direkt gestartet werden, muss ggf. die Ausfuehrungsrichtlinie angepasst werden: `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`
- **Antivirus blockiert**: Die EXE als Ausnahme hinzufuegen oder die PS1-Dateien direkt verwenden

### winget meldet „Keine Quellen verfuegbar" oder „Failed to update sources".

In der Eingabeaufforderung (als Administrator) ausfuehren:

```
winget source reset --force
winget source update
```

### Das Programm bleibt beim Scan haengen.

Der Scan kann je nach Anzahl der installierten Programme 10-30 Sekunden dauern. Falls es deutlich laenger dauert:

- Internetverbindung pruefen
- winget manuell testen: `winget list` in der Eingabeaufforderung ausfuehren
- Programm schliessen und erneut starten

### Ein Programm wird nach dem Update/der Installation nicht erkannt.

Einige Programme registrieren sich erst nach einem Windows-Neustart korrekt bei winget. Den PC neustarten und den Scan erneut durchfuehren.

### Wo kann ich Fehler melden oder Verbesserungen vorschlagen?

Auf der GitHub-Projektseite unter **Issues**: https://github.com/Redpunch666/winget-tools/issues
