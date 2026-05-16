# ============================================================
#  Build-Executables.ps1  -  Build.bat doppelklicken!
#  Version: 2026-05-INPROC-HOST
#
#  Neuer Ansatz gegen das weisse Taskleisten-Icon:
#  Die EXE startet NICHT mehr powershell.exe als Unterprozess,
#  sondern fuehrt das eingebettete Appstallo.ps1 direkt ueber
#  System.Management.Automation im eigenen EXE-Prozess aus.
#  Dadurch bleibt der sichtbare Host-Prozess immer Appstallo.exe.
# ============================================================

$logFile = "$env:USERPROFILE\WingetBuild.log"
function Log($msg, $col = "White") {
    Write-Host "  $msg" -ForegroundColor $col
    "  $msg" | Out-File $logFile -Encoding UTF8 -Append
}
"=== Build gestartet: $(Get-Date) ===" | Out-File $logFile -Encoding UTF8

# Icon wird zur Build-Zeit aus Appstallo.ico gelesen (keine eingebettete Base64 mehr)
try {
    $dir = Split-Path -Parent $MyInvocation.MyCommand.Path
    if (-not $dir -or $dir -eq "") { $dir = $PWD.Path }
    $ps1 = Join-Path $dir "Appstallo.ps1"
    $out = Join-Path $dir "Appstallo.exe"

    Log "Ordner : $dir" "DarkGray"
    Log "" ; Log "APPSTALLO - EXE BUILD (Ressource)" "Red"
    Log "-----------------------------------------" ; Log ""

    # === Optional: Icons einbetten (wenn icon-catalog\ vorhanden) ===
    $embedScript = Join-Path $dir "Embed-Icons.ps1"
    $catalogDir  = Join-Path $dir "icon-catalog"
    if ((Test-Path $embedScript) -and (Test-Path $catalogDir)) {
        Log "[0/3] Icons einbetten..." "Cyan"
        try {
            # Embed-Icons.ps1 direkt aufrufen (kein Subprocess - keine Pipe-Buffer-Probleme)
            & $embedScript -LauncherPath $ps1 -CatalogDir $catalogDir -NoPause *>&1 | Out-Null
            $ps1Size = [math]::Round((Get-Item $ps1).Length/1MB, 2)
            Log "OK - Appstallo.ps1 nach Embed: $ps1Size MB" "Green"
            Log ""
        } catch {
            Log "WARNUNG: Embed-Step fehlgeschlagen: $($_.Exception.Message)" "Yellow"
            Log "Build laeuft ohne Embedded-Icons weiter." "Yellow"
            Log ""
        }
    } else {
        Log "[0/3] Embed-Step uebersprungen (Embed-Icons.ps1 oder icon-catalog\ fehlt)" "DarkGray"
        Log ""
    }

    Log "[1/3] Pruefe Appstallo.ps1..." "Cyan"
    if (-not (Test-Path $ps1)) {
        Log "FEHLER: Appstallo.ps1 nicht gefunden!" "Red"
        Read-Host "`n  Enter zum Beenden"; exit 1
    }
    Log "OK - $([math]::Round((Get-Item $ps1).Length/1KB,1)) KB" "Green"

    Log "" ; Log "[2/3] Bereite Ressourcen vor..." "Cyan"
    # Alte Temp-Dateien aufraeumen
    Get-ChildItem $env:TEMP -Filter "AppstalloEmbed_*.ps1" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    $icoSrc = Join-Path $dir "Appstallo.ico"
    if (-not (Test-Path $icoSrc)) {
        Log "FEHLER: Appstallo.ico nicht gefunden neben Build-Executables.ps1!" "Red"
        Read-Host "`n  Enter zum Beenden"; exit 1
    }
    Get-ChildItem $env:TEMP -Filter "WgtIcon_*.ico" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    $tmpIco = Join-Path $env:TEMP ("WgtIcon_" + [Guid]::NewGuid().ToString("N") + ".ico")
    Copy-Item -LiteralPath $icoSrc -Destination $tmpIco -Force
    Log "Icon-Quelle  : $icoSrc" "DarkGray"
    Log "Icon-Temp    : $tmpIco" "DarkGray"

    $tmpPs1 = Join-Path $env:TEMP ("AppstalloEmbed_" + [Guid]::NewGuid().ToString("N") + ".ps1")
    
    # === Refactor: Common-Datei in den Launcher einbetten ===
    # Appstallo.Common.ps1 enthaelt zentrale Funktionen (Get-WingetUpdates etc.)
    # die der Launcher dot-sourcen wird. Wir kombinieren beide Files zu einem Temp-PS1.
    $commonPs1 = Join-Path $dir "Appstallo.Common.ps1"
    if (Test-Path $commonPs1) {
        $commonContent  = Get-Content -Path $commonPs1 -Raw -Encoding UTF8
        $launcherContent = Get-Content -Path $ps1       -Raw -Encoding UTF8
        # Common-Funktionen zuerst, dann Launcher-Logik
        $combinedContent = $commonContent + "`r`n`r`n" + $launcherContent
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($tmpPs1, $combinedContent, $utf8Bom)
        Log "Common-Datei: $commonPs1 (eingebettet, $([math]::Round((Get-Item $commonPs1).Length/1KB,1)) KB)" "DarkGray"
    } else {
        Copy-Item $ps1 $tmpPs1 -Force
        Log "WARNUNG: Appstallo.Common.ps1 nicht gefunden, EXE ohne gemeinsame Funktionen!" "Yellow"
    }
    Start-Sleep -Milliseconds 500
    Log "PS1-Ressource: $tmpPs1" "DarkGray"

    $csCode = @"
using System;
using System.IO;
using System.Diagnostics;
using System.Windows.Forms;
using System.Security.Principal;
using System.Reflection;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;

[assembly: AssemblyTitle("Appstallo")]
[assembly: AssemblyDescription("Winget Package Manager Suite - Updater, Installer, Uninstaller")]
[assembly: AssemblyCompany("Sven Kuhlow")]
[assembly: AssemblyProduct("Appstallo")]
[assembly: AssemblyCopyright("Copyright (c) 2026 Sven Kuhlow")]
[assembly: AssemblyTrademark("")]
[assembly: AssemblyVersion("1.9.0.0")]
[assembly: AssemblyFileVersion("1.9.0.0")]

class AppstalloApp {

    static bool IsAdmin() {
        var id = WindowsIdentity.GetCurrent();
        return new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator);
    }

    static string ReadEmbeddedScript() {
        var asm = Assembly.GetExecutingAssembly();
        using (var stream = asm.GetManifestResourceStream("AppstalloEmbed.ps1")) {
            if (stream == null) return null;
            using (var reader = new StreamReader(stream, true)) {
                return reader.ReadToEnd();
            }
        }
    }

    [STAThread]
    static void Main(string[] cliArgs) {
        string moduleArg = (cliArgs != null && cliArgs.Length > 0) ? cliArgs[0] : "";

        if (!IsAdmin()) {
            try {
                var self = new ProcessStartInfo(Assembly.GetExecutingAssembly().Location);
                self.Arguments = moduleArg;
                self.Verb = "runas";
                self.UseShellExecute = true;
                Process.Start(self);
            } catch (Exception) { }
            return;
        }

        try {
            string scriptText = ReadEmbeddedScript();
            if (String.IsNullOrEmpty(scriptText)) {
                MessageBox.Show("Interne Ressource nicht gefunden.", "Appstallo",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            string exePath = Assembly.GetExecutingAssembly().Location;
            string exeDir = Path.GetDirectoryName(exePath) ?? Environment.CurrentDirectory;
            Environment.SetEnvironmentVariable("APPSTALLO_EXE", exePath, EnvironmentVariableTarget.Process);
            Environment.SetEnvironmentVariable("APPSTALLO_MODULE", moduleArg ?? "", EnvironmentVariableTarget.Process);
            Environment.CurrentDirectory = exeDir;

            var initial = InitialSessionState.CreateDefault();

            using (var runspace = RunspaceFactory.CreateRunspace(initial)) {
                runspace.ApartmentState = ApartmentState.STA;
                runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
                runspace.Open();
                runspace.SessionStateProxy.SetVariable("PSScriptRoot", exeDir);
                runspace.SessionStateProxy.SetVariable("PSCommandPath", Path.Combine(exeDir, "Appstallo.ps1"));

                using (var ps = PowerShell.Create()) {
                    ps.Runspace = runspace;
                    ps.AddScript(scriptText, false);
                    ps.Invoke();

                    if (ps.HadErrors) {
                        var msg = "";
                        foreach (var err in ps.Streams.Error) {
                            if (!String.IsNullOrWhiteSpace(msg)) msg += "\n\n";
                            msg += err.ToString();
                        }
                        if (String.IsNullOrWhiteSpace(msg)) msg = "Unbekannter PowerShell-Fehler.";
                        MessageBox.Show(msg, "Appstallo", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    }
                }
            }
        }
        catch (Exception ex) {
            MessageBox.Show("Fehler:\n\n" + ex.ToString(), "Appstallo",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
"@

    Log "" ; Log "[3/3] Kompiliere..." "Cyan"
    if (Test-Path $out) { Remove-Item $out -Force }

    Add-Type -AssemblyName Microsoft.CSharp -ErrorAction Stop
    $provider = New-Object Microsoft.CSharp.CSharpCodeProvider
    $params   = New-Object System.CodeDom.Compiler.CompilerParameters
    $params.GenerateExecutable = $true
    $params.OutputAssembly     = $out
    $params.CompilerOptions    = "/target:winexe /platform:x64 /win32icon:`"$tmpIco`" /resource:`"$tmpPs1`",AppstalloEmbed.ps1"
    [void]$params.ReferencedAssemblies.Add("System.dll")
    [void]$params.ReferencedAssemblies.Add("System.Core.dll")
    [void]$params.ReferencedAssemblies.Add("System.Windows.Forms.dll")
    $smaPath = [System.Reflection.Assembly]::GetAssembly([powershell]).Location
    [void]$params.ReferencedAssemblies.Add($smaPath)

    $results = $provider.CompileAssemblyFromSource($params, $csCode)

    Remove-Item $tmpIco -ErrorAction SilentlyContinue
    Remove-Item $tmpPs1 -ErrorAction SilentlyContinue

    if ($results.Errors.HasErrors) {
        Log "" ; Log ">>> COMPILER-FEHLER:" "Red"
        foreach ($err in $results.Errors) { Log "  $($err.ToString())" "Red" }
        throw "Kompilierung fehlgeschlagen."
    }

    Start-Sleep -Milliseconds 800
    if (Test-Path $out) {
        $kb = [math]::Round((Get-Item $out).Length / 1KB, 0)
        Log "" ; Log "-----------------------------------------"
        Log "ERFOLG: Appstallo.exe ($kb KB)" "Green"
        Log "Pfad  : $out" "Gray"
        Log "" ; Log "Metadaten:" "DarkGray"
        Log "  Produkt   : Appstallo 1.9.0" "DarkGray"
        Log "  Entwickler: Sven Kuhlow" "DarkGray"
        Log "  Copyright : (c) 2026 Sven Kuhlow" "DarkGray"
        Log "" ; Log "EXE ist vollstaendig standalone." "DarkGray"
    } else {
        Log "" ; Log ">>> EXE NACH BUILD GELOESCHT (ESET)!" "Yellow"
        Log "Erkennungsausnahme: MSIL/GenKryptik_AGen.CAR" "Yellow"
    }

} catch {
    Log "" ; Log "FEHLER: $($_.Exception.Message)" "Red"
}

Log "" ; Log "Log: $logFile" "DarkGray"
Write-Host "" ; Read-Host "  Enter zum Beenden"
