# Refactor: Common-Funktionen laden (falls nicht bereits embedded)
if (-not (Test-Path Variable:WGT_UpdateScannerCode)) {
    $commonPath = Join-Path $PSScriptRoot "Appstallo.Common.ps1"
    if (Test-Path $commonPath) {
        . $commonPath
    }
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    # Eindeutige AppUserModelID setzen, damit Windows Taskleiste unser Icon zeigt
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class TaskbarHelper {
    [DllImport("shell32.dll", SetLastError = true)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(
        [MarshalAs(UnmanagedType.LPWStr)] string AppID);
}
"@ -ErrorAction SilentlyContinue
        [TaskbarHelper]::SetCurrentProcessExplicitAppUserModelID("Appstallo.Suite") | Out-Null
    } catch {}


    # --- Taskleisten-Pin-Fix: Property Store am Window-HWND ---
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential, Pack = 4)]
public struct AppstalloPropertyKey {
    public Guid fmtid;
    public uint pid;
    public AppstalloPropertyKey(Guid f, uint p) { fmtid = f; pid = p; }
}

[StructLayout(LayoutKind.Explicit)]
public struct AppstalloPropVariant {
    [FieldOffset(0)] public ushort vt;
    [FieldOffset(2)] public ushort wReserved1;
    [FieldOffset(4)] public ushort wReserved2;
    [FieldOffset(6)] public ushort wReserved3;
    [FieldOffset(8)] public IntPtr pwszVal;
    [FieldOffset(16)] public IntPtr padding;
}

[ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAppstalloPropertyStore {
    int GetCount(out uint cProps);
    int GetAt(uint iProp, out AppstalloPropertyKey pkey);
    int GetValue(ref AppstalloPropertyKey key, out AppstalloPropVariant pv);
    int SetValue(ref AppstalloPropertyKey key, ref AppstalloPropVariant pv);
    int Commit();
}

public static class AppstalloWindowPropStore {
    [DllImport("shell32.dll")]
    public static extern int SHGetPropertyStoreForWindow(
        IntPtr hwnd, ref Guid riid, out IAppstalloPropertyStore ps);

    private static readonly Guid IID_IPS =
        new Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99");

    public static void SetString(IntPtr hwnd, Guid fmtid, uint pid, string value) {
        IAppstalloPropertyStore ps = null;
        IntPtr strPtr = IntPtr.Zero;
        Guid iid = IID_IPS;
        try {
            int hr = SHGetPropertyStoreForWindow(hwnd, ref iid, out ps);
            if (hr != 0 || ps == null) return;
            var pk = new AppstalloPropertyKey(fmtid, pid);
            strPtr = Marshal.StringToCoTaskMemUni(value);
            var pv = new AppstalloPropVariant();
            pv.vt = 31; // VT_LPWSTR
            pv.pwszVal = strPtr;
            ps.SetValue(ref pk, ref pv);
            ps.Commit();
        } catch { }
        finally {
            if (strPtr != IntPtr.Zero) Marshal.FreeCoTaskMem(strPtr);
            if (ps != null) Marshal.ReleaseComObject(ps);
        }
    }
}
"@ -ErrorAction SilentlyContinue
    } catch {}

    function Set-AppstalloRelaunchProperties {
        param(
            [Parameter(Mandatory)] [IntPtr] $Hwnd,
            [string] $Module = ""
        )
        if ($Hwnd -eq [IntPtr]::Zero) { return }
        try {
            # Pfad zur Appstallo.exe ermitteln (im EXE-Modus via Env, sonst Skript-Pfad)
            $exePath = $env:APPSTALLO_EXE
            if (-not $exePath -or -not (Test-Path $exePath)) {
                # Fallback: kein Pin-Fix moeglich (PS1-Direktstart)
                return
            }
            # FMTID_AppUserModel = {9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}
            $fmt = [Guid]"9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"
            $relCmd = '"' + $exePath + '"'
            if ($Module) { $relCmd += ' ' + $Module }
            $iconRes = $exePath + ',0'
            # pid 5 = ID, 2 = RelaunchCommand, 3 = RelaunchDisplayNameResource, 4 = RelaunchIconResource
            [AppstalloWindowPropStore]::SetString($Hwnd, $fmt, [uint32]5, "Appstallo.Suite")
            [AppstalloWindowPropStore]::SetString($Hwnd, $fmt, [uint32]2, $relCmd)
            [AppstalloWindowPropStore]::SetString($Hwnd, $fmt, [uint32]3, "Appstallo")
            [AppstalloWindowPropStore]::SetString($Hwnd, $fmt, [uint32]4, $iconRes)
        } catch {}
    }
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$logPath = [System.IO.Path]::Combine($env:USERPROFILE, "WingetUninstaller-debug.log")

try {

$knownDb = @{
    # Gaming & Plattformen
    "ElectronicArts.EADesktop"                    = @{ Cat = "Gaming & Plattformen"; Desc = "EA-Spieleplattform (ehemals Origin)" }
    "EpicGames.EpicGamesLauncher"                 = @{ Cat = "Gaming & Plattformen"; Desc = "Epic Games Store und Launcher" }
    "GOG.Galaxy"                                  = @{ Cat = "Gaming & Plattformen"; Desc = "Spieleplattform fuer DRM-freie Spiele" }
    "NexusMods.Vortex"                            = @{ Cat = "Gaming & Plattformen"; Desc = "Mod-Manager fuer hunderte PC-Spiele" }
    "Playnite.Playnite"                           = @{ Cat = "Gaming & Plattformen"; Desc = "Universelle Spielebibliothek fuer alle Plattformen" }
    "Ubisoft.Connect"                             = @{ Cat = "Gaming & Plattformen"; Desc = "Ubisofts Spieleplattform und Launcher" }
    "Valve.Steam"                                 = @{ Cat = "Gaming & Plattformen"; Desc = "Groesste PC-Spieleplattform von Valve" }

    # Browser & Internet
    "Brave.Brave"                                 = @{ Cat = "Browser & Internet"; Desc = "Datenschutzorientierter Chromium-Browser" }
    "filips.FirefoxPWA"                           = @{ Cat = "Browser & Internet"; Desc = "Progressive Web Apps fuer Firefox installieren" }
    "Google.Chrome"                               = @{ Cat = "Browser & Internet"; Desc = "Googles weit verbreiteter Webbrowser" }
    "Google.Chrome.EXE"                           = @{ Cat = "Browser & Internet"; Desc = "Googles weit verbreiteter Webbrowser" }
    "Mozilla.Firefox"                             = @{ Cat = "Browser & Internet"; Desc = "Freier Open-Source-Browser von Mozilla" }
    "Mozilla.Firefox.de"                          = @{ Cat = "Browser & Internet"; Desc = "Freier Open-Source-Browser von Mozilla (DE)" }
    "Mozilla.Thunderbird"                         = @{ Cat = "E-Mail & Kalender"; Desc = "E-Mail- und Kalender-Client von Mozilla" }
    "Mozilla.Thunderbird.de"                      = @{ Cat = "E-Mail & Kalender"; Desc = "E-Mail- und Kalender-Client von Mozilla (DE)" }
    "Opera.Opera"                                 = @{ Cat = "Browser & Internet"; Desc = "Browser mit integriertem VPN und Werbeblocker" }
    "Vivaldi.Vivaldi"                             = @{ Cat = "Browser & Internet"; Desc = "Hochgradig anpassbarer Browser" }

    # Office & Produktivitaet
    "AgileBits.1Password"                         = @{ Cat = "Office & Produktivitaet"; Desc = "Passwort-Manager fuer alle Geraete" }
    "appmakes.Typora"                             = @{ Cat = "Office & Produktivitaet"; Desc = "Minimalistischer WYSIWYG-Markdown-Editor" }
    "calibre.calibre"                             = @{ Cat = "Office & Produktivitaet"; Desc = "E-Book-Verwaltung und Konvertierung" }
    "CologneCodeCompany.XYplorer"                 = @{ Cat = "Office & Produktivitaet"; Desc = "Leistungsstarker Datei-Manager mit Tabs" }
    "eMClient.eMClient"                           = @{ Cat = "E-Mail & Kalender"; Desc = "E-Mail-, Kalender- und Kontaktverwaltung" }
    "Joplin.Joplin"                               = @{ Cat = "Office & Produktivitaet"; Desc = "Open-Source-Notizverwaltung mit Markdown" }
    "Learneo.LanguageTool"                        = @{ Cat = "Office & Produktivitaet"; Desc = "KI-Grammatik- und Rechtschreibpruefung" }
    "Notepad++.Notepad++"                         = @{ Cat = "Office & Produktivitaet"; Desc = "Erweiterter Texteditor fuer Entwickler" }
    "Obsidian.Obsidian"                           = @{ Cat = "Office & Produktivitaet"; Desc = "Vernetztes Notizsystem mit Markdown" }
    "ONLYOFFICE.DesktopEditors"                   = @{ Cat = "Office & Produktivitaet"; Desc = "Office-Suite kompatibel mit Word, Excel, PowerPoint" }

    # Grafik & Design
    "BandicamCompany.Bandicam"                    = @{ Cat = "Audio & Video"; Desc = "Bildschirm- und Spielaufzeichnung" }
    "Canva.Affinity"                              = @{ Cat = "Grafik & Design"; Desc = "Professionelle Grafiksuite (Photo, Designer, Publisher)" }
    "Canva.Canva"                                 = @{ Cat = "Grafik & Design"; Desc = "Online-Designtool fuer Grafiken und Praesentationen" }
    "DuongDieuPhap.ImageGlass"                    = @{ Cat = "Grafik & Design"; Desc = "Schneller, schlanker Bildbetrachter" }
    "ente-io.photos-desktop"                      = @{ Cat = "Grafik & Design"; Desc = "Ende-zu-Ende-verschluesselte Fotoverwaltung" }
    "GIMP.GIMP"                                   = @{ Cat = "Grafik & Design"; Desc = "Professionelles Open-Source-Bildbearbeitungsprogramm" }
    "iLovePDF.iLovePDFDesktop"                    = @{ Cat = "Grafik & Design"; Desc = "PDF bearbeiten, konvertieren und zusammenfuehren" }
    "mpv.net"                                     = @{ Cat = "Audio & Video"; Desc = "Leichtgewichtiger Mediaplayer fuer alle Formate" }
    "OBSProject.OBSStudio"                        = @{ Cat = "Audio & Video"; Desc = "Open-Source Streaming- und Aufzeichnungssoftware" }
    "Pinta.Pinta"                                 = @{ Cat = "Grafik & Design"; Desc = "Einfaches Bildbearbeitungsprogramm" }
    "SplitCam.SplitCam"                           = @{ Cat = "Audio & Video"; Desc = "Virtuelle Webcam und Video-Streaming-Tool" }
    "SplitmediaLabs.XSplitVCam"                   = @{ Cat = "Audio & Video"; Desc = "KI-Hintergrundentfernung fuer Webcam" }
    "TechSmith.Snagit.2025"                       = @{ Cat = "Grafik & Design"; Desc = "Professionelles Screenshot- und Screencasting-Tool" }
    "TechSmith.Snagit.2026"                       = @{ Cat = "Grafik & Design"; Desc = "Professionelles Screenshot- und Screencasting-Tool" }
    "VideoLAN.VLC"                                = @{ Cat = "Audio & Video"; Desc = "Universeller Open-Source-Mediaplayer" }

    # Sicherheit & Datenschutz
    "Bitdefender.Bitdefender"                     = @{ Cat = "Sicherheit & Datenschutz"; Desc = "Antivirus und umfassende Sicherheitssuite" }
    "ESET.Nod32"                                  = @{ Cat = "Sicherheit & Datenschutz"; Desc = "Antivirus und Internet Security Suite" }
    "Malwarebytes.Malwarebytes"                   = @{ Cat = "Sicherheit & Datenschutz"; Desc = "Anti-Malware und Sicherheits-Scanner" }
    "NordSecurity.NordVPN"                        = @{ Cat = "Sicherheit & Datenschutz"; Desc = "VPN-Dienst fuer Datenschutz und Sicherheit" }
    "SparkLabs.Viscosity"                         = @{ Cat = "Sicherheit & Datenschutz"; Desc = "OpenVPN-Client mit uebersichtlicher Oberflaeche" }

    # Kommunikation
    "Discord.Discord"                             = @{ Cat = "Kommunikation"; Desc = "Chat- und Community-Plattform fuer Gamer" }
    "SlackTechnologies.Slack"                     = @{ Cat = "Kommunikation"; Desc = "Team-Kommunikations- und Kollaborationsplattform" }
    "Telegram.TelegramDesktop"                    = @{ Cat = "Kommunikation"; Desc = "Sicherer Messenger mit Cloud-Synchronisation" }
    "Zoom.Zoom"                                   = @{ Cat = "Kommunikation"; Desc = "Videokonferenz- und Collaboration-Plattform" }

    # Entwicklung
    "Git.Git"                                     = @{ Cat = "Entwicklung"; Desc = "Versionskontrollsystem fuer Softwareprojekte" }
    "Microsoft.PowerShell"                        = @{ Cat = "Entwicklung"; Desc = "Moderne PowerShell-Version (Cross-Platform)" }
    "Microsoft.VisualStudioCode"                  = @{ Cat = "Entwicklung"; Desc = "Leistungsstarker Quellcode-Editor von Microsoft" }

    # System & Tools
    "7zip.7zip"                                   = @{ Cat = "System & Tools"; Desc = "Kostenloser Datei-Archiver (ZIP, RAR, 7z u.v.m.)" }
    "Anthropic.Claude"                            = @{ Cat = "KI-Tools"; Desc = "KI-Assistent von Anthropic als Desktop-App" }
    "Corsair.iCUE.5"                              = @{ Cat = "System & Tools"; Desc = "RGB-Steuerung und Hardware-Ueberwachung" }
    "FinalWire.AIDA64.Extreme"                    = @{ Cat = "System & Tools"; Desc = "System-Diagnose, Benchmark und Hardware-Info" }
    "Gainward.EXPERTool"                          = @{ Cat = "System & Tools"; Desc = "GPU-Uebertaktung fuer Gainward-Grafikkarten" }
    "GIGABYTE.RGBFusion"                          = @{ Cat = "System & Tools"; Desc = "RGB-Steuerung fuer GIGABYTE-Hardware" }
    "HelmutBuhler.8GadgetPack"                    = @{ Cat = "System & Tools"; Desc = "Desktop-Gadgets fuer Windows 10 und 11" }
    "JAMSoftware.TreeSize.Free"                   = @{ Cat = "System & Tools"; Desc = "Festplattennutzung visualisieren und analysieren" }
    "JAMSoftware.TreeSize.Personal"               = @{ Cat = "System & Tools"; Desc = "Festplattennutzung visualisieren und analysieren" }
    "Microsoft.WindowsTerminal"                   = @{ Cat = "System & Tools"; Desc = "Modernes Terminal mit Tabs und Themes" }
    "Nvidia.PhysX"                                = @{ Cat = "System & Tools"; Desc = "Physik-Engine-Bibliothek fuer Spiele" }
    "RamenSoftware.Windhawk"                      = @{ Cat = "System & Tools"; Desc = "Framework fuer Windows-UI-Anpassungen" }
    "RARLab.WinRAR"                               = @{ Cat = "System & Tools"; Desc = "RAR- und ZIP-Archivierungsprogramm" }
    "Stardock.Start11.v2"                         = @{ Cat = "System & Tools"; Desc = "Klassisches Startmenue fuer Windows 11" }
    "StardockSystems.Fences6"                     = @{ Cat = "System & Tools"; Desc = "Desktop-Organizer fuer Programm-Icons" }
    "TeamViewer.TeamViewer"                       = @{ Cat = "System & Tools"; Desc = "Fernzugriff und Remote-Support" }
    "voidtools.Everything"                        = @{ Cat = "System & Tools"; Desc = "Blitzschnelle Dateisuche fuer Windows" }
    "voidtools.Everything.Alpha"                  = @{ Cat = "System & Tools"; Desc = "Blitzschnelle Dateisuche (Alpha-Version)" }

    # Laufzeiten & Frameworks
    "Microsoft.AppInstaller"                      = @{ Cat = "Laufzeiten & Frameworks"; Desc = "Windows Package Manager App Installer" }
    "Microsoft.DirectX"                           = @{ Cat = "Laufzeiten & Frameworks"; Desc = "DirectX-Laufzeitbibliotheken fuer Spiele" }
    "Microsoft.DotNet.DesktopRuntime.10"          = @{ Cat = "Laufzeiten & Frameworks"; Desc = ".NET 10 Desktop-Laufzeitumgebung" }
    "Microsoft.DotNet.DesktopRuntime.6"           = @{ Cat = "Laufzeiten & Frameworks"; Desc = ".NET 6 Desktop-Laufzeitumgebung" }
    "Microsoft.DotNet.DesktopRuntime.8"           = @{ Cat = "Laufzeiten & Frameworks"; Desc = ".NET 8 Desktop-Laufzeitumgebung" }
    "Microsoft.DotNet.DesktopRuntime.9"           = @{ Cat = "Laufzeiten & Frameworks"; Desc = ".NET 9 Desktop-Laufzeitumgebung" }
    "Microsoft.UI.Xaml.2.8"                       = @{ Cat = "Laufzeiten & Frameworks"; Desc = "WinUI 2.8 XAML-Framework" }
    "Microsoft.VCLibs.Desktop.14"                 = @{ Cat = "Laufzeiten & Frameworks"; Desc = "Visual C++ UWP Runtime 2015" }
    "Microsoft.VCRedist.2008.x86"                 = @{ Cat = "Laufzeiten & Frameworks"; Desc = "Microsoft Visual C++ 2008 Runtime (32-bit)" }
    "Microsoft.VCRedist.2010.x64"                 = @{ Cat = "Laufzeiten & Frameworks"; Desc = "Microsoft Visual C++ 2010 Runtime (64-bit)" }
    "Microsoft.VCRedist.2010.x86"                 = @{ Cat = "Laufzeiten & Frameworks"; Desc = "Microsoft Visual C++ 2010 Runtime (32-bit)" }
    "Microsoft.VCRedist.2012.x64"                 = @{ Cat = "Laufzeiten & Frameworks"; Desc = "Microsoft Visual C++ 2012 Runtime (64-bit)" }
    "Microsoft.VCRedist.2012.x86"                 = @{ Cat = "Laufzeiten & Frameworks"; Desc = "Microsoft Visual C++ 2012 Runtime (32-bit)" }
    "Microsoft.VCRedist.2013.x64"                 = @{ Cat = "Laufzeiten & Frameworks"; Desc = "Microsoft Visual C++ 2013 Runtime (64-bit)" }
    "Microsoft.VCRedist.2013.x86"                 = @{ Cat = "Laufzeiten & Frameworks"; Desc = "Microsoft Visual C++ 2013 Runtime (32-bit)" }
    "Microsoft.VCRedist.2015+.x64"                = @{ Cat = "Laufzeiten & Frameworks"; Desc = "Microsoft Visual C++ 2015-2022 Runtime (64-bit)" }
    "Microsoft.VCRedist.2015+.x86"                = @{ Cat = "Laufzeiten & Frameworks"; Desc = "Microsoft Visual C++ 2015-2022 Runtime (32-bit)" }
    "Microsoft.WindowsAppRuntime.1.5"             = @{ Cat = "Laufzeiten & Frameworks"; Desc = "Windows App Runtime 1.5" }
    "Microsoft.WindowsAppRuntime.1.6"             = @{ Cat = "Laufzeiten & Frameworks"; Desc = "Windows App Runtime 1.6" }
    "Microsoft.WindowsAppRuntime.1.7"             = @{ Cat = "Laufzeiten & Frameworks"; Desc = "Windows App Runtime 1.7" }
    "Microsoft.WindowsAppRuntime.1.8"             = @{ Cat = "Laufzeiten & Frameworks"; Desc = "Windows App Runtime 1.8" }
}

# Kategorien & Keyword-Mapping werden ZENTRAL in Appstallo.Common.ps1
# gepflegt (Get-AppstalloCategoryMap / Get-AppstalloCategoryOrder /
# Get-AppstalloCategoryFor). So koennen Bibliothek und Uninstaller nicht
# auseinanderlaufen.
$categoryMap = Get-AppstalloCategoryMap
$catOrder    = Get-AppstalloCategoryOrder

$xaml = @"

<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Uninstaller"
    Width="860" Height="640"
    MinWidth="700" MinHeight="500"
    WindowStartupLocation="CenterScreen"
    Background="#161616"
    FontFamily="Segoe UI">
    <Window.Resources>

        <!-- Dark Scrollbar Style -->
        <Style x:Key="DarkThumb" TargetType="Thumb">
            <Setter Property="OverridesDefaultStyle" Value="True"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Thumb">
                        <Border Background="#3a3a3a" CornerRadius="4" Margin="1"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="ScrollBar">
            <Setter Property="OverridesDefaultStyle" Value="True"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Grid Background="#0d0d0d" Width="10">
                            <Track x:Name="PART_Track" IsDirectionReversed="True">
                                <Track.Thumb>
                                    <Thumb Style="{StaticResource DarkThumb}"/>
                                </Track.Thumb>
                            </Track>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="Orientation" Value="Horizontal">
                                <Setter Property="Height" Value="10"/>
                                <Setter TargetName="PART_Track" Property="IsDirectionReversed" Value="False"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#e0e0e0"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>

        <!-- Dark Button Style mit rotem Hover -->
        <Style TargetType="Button">
            <Setter Property="Background" Value="#2a2a2a"/>
            <Setter Property="Foreground" Value="#aaaaaa"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="16,8"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="BtnBorder"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                Padding="{TemplateBinding Padding}"
                                CornerRadius="0">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="BtnBorder" Property="Background" Value="#a93226"/>
                                <Setter Property="Foreground" Value="White"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="BtnBorder" Property="Background" Value="#8c231c"/>
                                <Setter Property="Foreground" Value="White"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="BtnBorder" Property="Background" Value="#1a1a1a"/>
                                <Setter Property="Foreground" Value="#666666"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- TextBox Style mit rotem Fokus-Rahmen -->
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#1a1a1a"/>
            <Setter Property="Foreground" Value="#e0e0e0"/>
            <Setter Property="BorderBrush" Value="#2a2a2a"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,4,8,4"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="CaretBrush" Value="#e0e0e0"/>
            <Setter Property="SelectionBrush" Value="#a93226"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border x:Name="TxBorder"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                Padding="{TemplateBinding Padding}">
                            <ScrollViewer x:Name="PART_ContentHost"
                                          Focusable="False"
                                          HorizontalScrollBarVisibility="Hidden"
                                          VerticalScrollBarVisibility="Hidden"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="TxBorder" Property="BorderBrush" Value="#a93226"/>
                            </Trigger>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter TargetName="TxBorder" Property="BorderBrush" Value="#a93226"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="64"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="56"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="#0e0e0e">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="22,0,0,0">
                <Border Width="4" Height="30" Background="#a93226" Margin="0,0,12,0"/>
                <StackPanel>
                    <TextBlock Text="UNINSTALLER" Foreground="White" FontSize="15" FontWeight="Bold"/>
                    <TextBlock x:Name="StatusText" Foreground="#888888" FontSize="11" Margin="0,3,0,0"
                               Text="Installierte Software wird analysiert..."/>
                </StackPanel>
            </StackPanel>
        </Border>

        <Border x:Name="ScanPanel" Grid.Row="1" Background="#0d0d0d">
            <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                <ProgressBar Width="320" Height="3" IsIndeterminate="True"
                             Foreground="#a93226" Background="#252525"
                             BorderThickness="0" Margin="0,0,0,20"/>
                <TextBlock x:Name="ScanText" Foreground="#777777" FontSize="13"
                           HorizontalAlignment="Center"
                           Text="Installierte Software wird analysiert..."/>
                <TextBlock x:Name="ScanSubText" Text="" Foreground="#777777"
                           FontSize="11" HorizontalAlignment="Center" Margin="0,8,0,0"/>
            </StackPanel>
        </Border>

        <Border x:Name="SelectionPanel" Grid.Row="1" Background="#0d0d0d" Visibility="Collapsed">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <Border Grid.Row="0" Background="#0d0d0d" BorderBrush="#1e1e1e" BorderThickness="0,0,0,1">
                    <Grid Margin="20,10,20,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Grid.Column="0" Text="Suche:" Foreground="#888888" FontSize="11"
                                   VerticalAlignment="Center" Margin="0,0,8,0"/>
                        <TextBox x:Name="SearchBox" Grid.Column="1"
                                 Background="#1a1a1a" Foreground="#e0e0e0"
                                 BorderBrush="#2a2a2a" BorderThickness="1"
                                 Padding="8,4,8,4" FontSize="12"
                                 VerticalContentAlignment="Center"/>
                        <Button x:Name="SearchClearButton" Grid.Column="2"
                                Content="X" Width="28" Height="28" Margin="6,0,0,0"
                                Background="#2a2a2a" Foreground="#cccccc"
                                BorderBrush="#444444" BorderThickness="1"
                                Padding="0" Cursor="Hand" FontSize="11" FontWeight="Bold"/>
                    </Grid>
                </Border>
                <ScrollViewer x:Name="ProgramScroller" Grid.Row="1"
                              VerticalScrollBarVisibility="Auto"
                              HorizontalScrollBarVisibility="Disabled">
                    <StackPanel x:Name="ProgramList" Margin="20,8,20,16"/>
                </ScrollViewer>
            </Grid>
        </Border>

        <Grid x:Name="LogPanel" Grid.Row="1" Visibility="Collapsed">
            <Grid.RowDefinitions>
                <RowDefinition Height="4"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <ProgressBar x:Name="ProgressBar" Grid.Row="0"
                         Background="#252525" Foreground="#a93226"
                         BorderThickness="0" Value="0" IsIndeterminate="False"/>
            <Border x:Name="SummaryPanel" Grid.Row="1"
                    Background="#0e0e0e" Margin="20,10,20,0"
                    Padding="20,12" Visibility="Collapsed"
                    BorderBrush="#1f1f1f" BorderThickness="1">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="1"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Rectangle Grid.Column="1" Fill="#252525"/>
                    <StackPanel Grid.Column="0" HorizontalAlignment="Center">
                        <TextBlock x:Name="SuccessCount" Text="0" Foreground="#4ade80"
                                   FontSize="28" FontWeight="Bold" HorizontalAlignment="Center"/>
                        <TextBlock Text="Erfolgreich" Foreground="#4ade80"
                                   FontSize="11" HorizontalAlignment="Center"/>
                    </StackPanel>
                    <StackPanel Grid.Column="2" HorizontalAlignment="Center">
                        <TextBlock x:Name="FailCount" Text="0" Foreground="#f87171"
                                   FontSize="28" FontWeight="Bold" HorizontalAlignment="Center"/>
                        <TextBlock Text="Fehlgeschlagen" Foreground="#f87171"
                                   FontSize="11" HorizontalAlignment="Center"/>
                    </StackPanel>
                </Grid>
            </Border>
            <Border Grid.Row="2" Background="#0a0a0a"
                    BorderBrush="#1e1e1e" BorderThickness="1" Margin="20,8,20,0">
                <ScrollViewer x:Name="LogScroller"
                              VerticalScrollBarVisibility="Auto"
                              HorizontalScrollBarVisibility="Disabled">
                    <TextBlock x:Name="LogOutput"
                               Foreground="#999999" FontFamily="Consolas" FontSize="12"
                               Padding="14,10" TextWrapping="Wrap"/>
                </ScrollViewer>
            </Border>
        </Grid>

        <Border Grid.Row="2" Background="#0e0e0e" Margin="0,10,0,0">
            <Grid Margin="20,0">
                <TextBlock x:Name="CountText" Text=""
                           Foreground="#888888" FontSize="12"
                           VerticalAlignment="Center" HorizontalAlignment="Left"/>
                <StackPanel Orientation="Horizontal"
                            HorizontalAlignment="Right" VerticalAlignment="Center">
                    <Button x:Name="SelectAllButton" Content="Alle auswaehlen"
                            Background="#2a2a2a" Foreground="#aaaaaa"
                            BorderThickness="0" Padding="14,8" FontSize="12"
                            Margin="0,0,8,0" Cursor="Hand" Visibility="Collapsed"/>
                    <Button x:Name="RescanButton" Content="Neu einlesen"
                            Background="#2a2a2a" Foreground="#aaaaaa"
                            BorderThickness="0" Padding="14,8" FontSize="12"
                            Margin="0,0,8,0" Cursor="Hand" Visibility="Collapsed"/>
                    <Button x:Name="BackButton" Content="Zurueck zur Auswahl"
                            Background="#2a2a2a" Foreground="#aaaaaa"
                            BorderThickness="0" Padding="14,8" FontSize="12"
                            Margin="0,0,8,0" Cursor="Hand" Visibility="Collapsed"/>
                    <Button x:Name="UninstallButton" Content="Deinstallieren"
                            Background="#a93226" Foreground="White"
                            BorderThickness="0" Padding="16,8" FontSize="13"
                            FontWeight="SemiBold" Margin="0,0,8,0" Cursor="Hand"
                            IsEnabled="False" Visibility="Collapsed"/>
                    <Button x:Name="CloseButton" Content="Schliessen"
                            Background="#2a2a2a" Foreground="#aaaaaa"
                            BorderThickness="0" Padding="14,8" FontSize="12"
                            Cursor="Hand"/>
                </StackPanel>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]$xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    # Fenster-Icon aus eingebettetem Base64 setzen (funktioniert in PS1 und EXE)
    try {
        $iconB64 = "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"
        $iconBytes  = [Convert]::FromBase64String($iconB64)
        $iconStream = New-Object System.IO.MemoryStream(,$iconBytes)
        # IconBitmapDecoder: liest alle Frames der ICO-Datei
        $decoder = New-Object System.Windows.Media.Imaging.IconBitmapDecoder(
            $iconStream,
            [System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,
            [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
        # Groesstes Frame nehmen (statt erstes/kleinstes)
        $largestFrame = $decoder.Frames | Sort-Object PixelWidth -Descending | Select-Object -First 1
        $window.Icon = $largestFrame
        $script:appIcon = $largestFrame

        # Taskleisten-Icon per Win32 WM_SETICON setzen (WPF Window.Icon reicht bei
        # powershell.exe-Prozessen nicht fuer die Taskleiste)
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class WinIconHelper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    public const uint WM_SETICON = 0x0080;
    public static readonly IntPtr ICON_SMALL = new IntPtr(0);
    public static readonly IntPtr ICON_BIG   = new IntPtr(1);
}
"@ -ErrorAction SilentlyContinue

        # System.Drawing.Icon aus denselben Bytes laden
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        $iconStream2 = New-Object System.IO.MemoryStream(,$iconBytes)
        $drawingIcon = New-Object System.Drawing.Icon($iconStream2)
        $hIcon = $drawingIcon.Handle

        # DWM Dark Mode fuer Titelleiste aktivieren
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class DwmHelper {
    [DllImport("dwmapi.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    public static extern void DwmSetWindowAttribute(IntPtr hwnd, uint attr, ref int value, uint size);
    public const uint DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
}
"@ -ErrorAction SilentlyContinue

        # SourceInitialized: Window-Handle ist dann verfuegbar
        $window.Add_SourceInitialized({
            $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
            [WinIconHelper]::SendMessage($hwnd, [WinIconHelper]::WM_SETICON, [WinIconHelper]::ICON_BIG,   $hIcon) | Out-Null
            [WinIconHelper]::SendMessage($hwnd, [WinIconHelper]::WM_SETICON, [WinIconHelper]::ICON_SMALL, $hIcon) | Out-Null
            try { Set-AppstalloRelaunchProperties -Hwnd $hwnd -Module ([string]$env:APPSTALLO_MODULE) } catch {}
            # Dunkle Titelleiste erzwingen (Windows 10 1809+ / Windows 11)
            try {
                $val = [int]1
                [DwmHelper]::DwmSetWindowAttribute($hwnd, [DwmHelper]::DWMWA_USE_IMMERSIVE_DARK_MODE, [ref]$val, 4)
            } catch {}
        }.GetNewClosure())
    } catch {}

    if ($null -eq $window) {
        "Window null" | Out-File $logPath -Encoding UTF8
        throw "Fenster konnte nicht geladen werden."
    }

$sync = [hashtable]::Synchronized(@{
        Window          = $window
        StatusText        = $window.FindName("StatusText")
        SearchBox         = $window.FindName("SearchBox")
        SearchClearButton = $window.FindName("SearchClearButton")
        AllProgramItems   = [System.Collections.Generic.List[object]]::new()
        ScanPanel       = $window.FindName("ScanPanel")
        ScanText        = $window.FindName("ScanText")
        ScanSubText     = $window.FindName("ScanSubText")
        SelectionPanel  = $window.FindName("SelectionPanel")
        ProgramList     = $window.FindName("ProgramList")
        LogPanel        = $window.FindName("LogPanel")
        ProgressBar     = $window.FindName("ProgressBar")
        SummaryPanel    = $window.FindName("SummaryPanel")
        LogOutput       = $window.FindName("LogOutput")
        LogScroller     = $window.FindName("LogScroller")
        CountText       = $window.FindName("CountText")
        SuccessCount    = $window.FindName("SuccessCount")
        FailCount       = $window.FindName("FailCount")
        SelectAllButton = $window.FindName("SelectAllButton")
        RescanButton    = $window.FindName("RescanButton")
        BackButton      = $window.FindName("BackButton")
        UninstallButton = $window.FindName("UninstallButton")
        CloseButton     = $window.FindName("CloseButton")
        # Daten
        KnownDb         = $knownDb
        CatOrder        = $catOrder
        CategoryMap     = $categoryMap
        FoundPrograms   = $null
        SelectedIds     = [System.Collections.Generic.HashSet[string]]::new()
        AllEntries      = [System.Collections.Generic.List[hashtable]]::new()
        # Farben
        ClrWhite        = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#e0e0e0"))
        ClrGray         = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#888888"))
        ClrRed          = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#a93226"))
        ClrSep          = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#222222"))
        ClrHover        = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#1c1c1c"))
        ClrTransp       = [System.Windows.Media.Brushes]::Transparent
        ClrDark         = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#232323"))
        ClrMuted        = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#888888"))
        # Zustand
        ScanDone        = $false
        Done            = $false
        Successful      = 0
        Failed          = 0
        TotalPkgs       = 0
        CurrentPkg      = 0
        AllSelected     = $false
        Lines           = [System.Collections.Generic.List[string]]::new()
        RawLines        = [System.Collections.Generic.List[string]]::new()
        ScanTimer       = $null
        InstallTimer    = $null
        StartupTimer    = $null
    })
    if ($script:appIcon) { $sync.AppIcon = $script:appIcon }





    # Goldgelber Button-Style fuer Popup-Fenster
    try {
        $goldXaml = "<Style xmlns=`"http://schemas.microsoft.com/winfx/2006/xaml/presentation`" xmlns:x=`"http://schemas.microsoft.com/winfx/2006/xaml`" TargetType=`"Button`"><Setter Property=`"Background`" Value=`"#2a2a2a`"/><Setter Property=`"Foreground`" Value=`"#aaaaaa`"/><Setter Property=`"BorderThickness`" Value=`"0`"/><Setter Property=`"Padding`" Value=`"14,7`"/><Setter Property=`"Cursor`" Value=`"Hand`"/><Setter Property=`"Template`"><Setter.Value><ControlTemplate TargetType=`"Button`"><Border x:Name=`"Bd`" Background=`"{TemplateBinding Background}`" Padding=`"{TemplateBinding Padding}`"><ContentPresenter HorizontalAlignment=`"{TemplateBinding HorizontalContentAlignment}`" VerticalAlignment=`"Center`"/></Border><ControlTemplate.Triggers><Trigger Property=`"IsMouseOver`" Value=`"True`"><Setter TargetName=`"Bd`" Property=`"Background`" Value=`"#a93226`"/><Setter Property=`"Foreground`" Value=`"White`"/></Trigger><Trigger Property=`"IsPressed`" Value=`"True`"><Setter TargetName=`"Bd`" Property=`"Background`" Value=`"#8c231c`"/><Setter Property=`"Foreground`" Value=`"White`"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>"
        $sync.GoldStyle = [System.Windows.Markup.XamlReader]::Parse($goldXaml)
    } catch { $sync.GoldStyle = $null; $sync.GoldError = $_.ToString() }
    $sync.ApplyGoldStyle = {
        param($w)
        if ($sync.GoldStyle) {
            try { $w.Resources.Add([System.Windows.Controls.Button], $sync.GoldStyle) } catch {}
        }
    }







    # ── Hilfsfunktionen als Scriptblocks ──────────────────────────────────────
    $sync.UpdateCount = {
        $n = $sync.SelectedIds.Count
        if ($n -eq 0) {
            $sync.CountText.Text            = "Keine Programme ausgewaehlt"
            $sync.UninstallButton.IsEnabled = $false
        } else {
            $sync.CountText.Text            = "$n Programm(e) ausgewaehlt"
            $sync.UninstallButton.IsEnabled = $true
        }
    }

    # ╔══════════════════════════════════════════════════════════════════════╗
    # ║ ICON MANAGER – EXE-Extraktion (primaer) + dashboard-icons CDN (Fallback) ║
    # ╚══════════════════════════════════════════════════════════════════════╝
    $sync.IconCacheDir = "$env:LOCALAPPDATA\Appstallo\icon-cache"
    if (-not (Test-Path $sync.IconCacheDir)) {
        try { New-Item -ItemType Directory -Path $sync.IconCacheDir -Force | Out-Null } catch {}
    }
    $sync.IconIndexPath = Join-Path $sync.IconCacheDir "_index.json"

    # Optionaler externer Icon-Katalog (Override per ENV-Variable, fuer Power-User)
    # Standard: Icons sind eingebettet und wurden vom Launcher in $IconCacheDir entpackt
    $sync.IconCatalogDir = $null
    if ($env:APPSTALLO_HOME) {
        $catalogPath = Join-Path $env:APPSTALLO_HOME "icon-catalog"
        if (Test-Path $catalogPath) { $sync.IconCatalogDir = $catalogPath }
    }

    # Win32-Interop fuer Icon-Extraktion aus EXE/DLL/ICO via SHGetFileInfo + IImageList(SHIL_JUMBO)
    if (-not ("WT.IconExtractor" -as [type])) {
        try {
            Add-Type -ErrorAction Stop -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

namespace WT {

[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
public struct SHFILEINFO {
    public IntPtr hIcon;
    public int iIcon;
    public uint dwAttributes;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)]
    public string szDisplayName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=80)]
    public string szTypeName;
}

[ComImport]
[Guid("46EB5926-582E-4017-9FDF-E8998DAA0950")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IImageList {
    [PreserveSig] int Add(IntPtr hbmImage, IntPtr hbmMask, ref int pi);
    [PreserveSig] int ReplaceIcon(int i, IntPtr hicon, ref int pi);
    [PreserveSig] int SetOverlayImage(int iImage, int iOverlay);
    [PreserveSig] int Replace(int i, IntPtr hbmImage, IntPtr hbmMask);
    [PreserveSig] int AddMasked(IntPtr hbmImage, int crMask, ref int pi);
    [PreserveSig] int Draw(IntPtr pimldp);
    [PreserveSig] int Remove(int i);
    [PreserveSig] int GetIcon(int i, int flags, ref IntPtr picon);
}

public static class IconExtractor {
    const uint SHGFI_SYSICONINDEX     = 0x4000;
    const uint SHGFI_USEFILEATTRIBUTES = 0x10;
    const uint FILE_ATTRIBUTE_NORMAL  = 0x80;
    const int  SHIL_LARGE             = 0;
    const int  SHIL_EXTRALARGE        = 2;
    const int  SHIL_JUMBO             = 4;
    const int  ILD_TRANSPARENT        = 1;

    [DllImport("shell32.dll", CharSet=CharSet.Unicode)]
    static extern IntPtr SHGetFileInfo(string pszPath, uint dwFileAttributes,
        ref SHFILEINFO psfi, uint cbFileInfo, uint uFlags);

    [DllImport("shell32.dll", EntryPoint="#727")]
    static extern int SHGetImageList(int iImageList, ref Guid riid, out IImageList ppv);

    [DllImport("user32.dll")]
    static extern bool DestroyIcon(IntPtr hIcon);

    static readonly Guid IID_IImageList = new Guid("46EB5926-582E-4017-9FDF-E8998DAA0950");

    public static byte[] ExtractIconPng(string filePath) {
        if (string.IsNullOrEmpty(filePath) || !File.Exists(filePath)) return null;

        // .ico-Dateien direkt laden (System.Drawing.Icon)
        string ext = System.IO.Path.GetExtension(filePath).ToLowerInvariant();
        if (ext == ".ico") {
            try {
                using (Icon ic = new Icon(filePath, new System.Drawing.Size(256, 256)))
                using (Bitmap bmp = ic.ToBitmap())
                using (MemoryStream ms = new MemoryStream()) {
                    if (bmp.Width >= 16 && bmp.Height >= 16) {
                        bmp.Save(ms, ImageFormat.Png);
                        return ms.ToArray();
                    }
                }
            } catch { }
            return null;  // .ico aber Laden fehlgeschlagen: kein Fallback auf SHGetFileInfo
        }

        SHFILEINFO shfi = new SHFILEINFO();
        IntPtr ret = SHGetFileInfo(filePath, FILE_ATTRIBUTE_NORMAL, ref shfi,
            (uint)Marshal.SizeOf(shfi),
            SHGFI_SYSICONINDEX | SHGFI_USEFILEATTRIBUTES);
        if (ret == IntPtr.Zero) return null;
        int iconIdx = shfi.iIcon;

        // Reihenfolge: JUMBO (256), EXTRALARGE (48), LARGE (32)
        int[] sizes = new int[] { SHIL_JUMBO, SHIL_EXTRALARGE, SHIL_LARGE };
        foreach (int sz in sizes) {
            Guid iid = IID_IImageList;
            IImageList imgList = null;
            int hr = SHGetImageList(sz, ref iid, out imgList);
            if (hr != 0 || imgList == null) continue;

            IntPtr hIcon = IntPtr.Zero;
            try {
                imgList.GetIcon(iconIdx, ILD_TRANSPARENT, ref hIcon);
            } catch { hIcon = IntPtr.Zero; }
            if (hIcon == IntPtr.Zero) continue;

            try {
                using (Icon ic = (Icon)Icon.FromHandle(hIcon).Clone())
                using (Bitmap bmp = ic.ToBitmap())
                using (MemoryStream ms = new MemoryStream()) {
                    // Prefer larger size: nur akzeptieren wenn mindestens 32x32
                    if (bmp.Width >= 32 && bmp.Height >= 32) {
                        bmp.Save(ms, ImageFormat.Png);
                        return ms.ToArray();
                    }
                }
            } catch { }
            finally { DestroyIcon(hIcon); }
        }
        return null;
    }
}

}
"@
        } catch {
            # Add-Type fehlgeschlagen - EXE-Extraktion deaktiviert, nur CDN+Buchstaben verfuegbar
        }
    }

    $IconSlugMap = @{
        '7zip.7zip' = '7zip'
        'AdGuard.AdGuardHome' = 'adguard-home'
        'Adobe.Acrobat' = 'adobe'
        'Adobe.Acrobat.Reader.64-bit' = 'adobe'
        'Adobe.Illustrator' = 'adobe'
        'Adobe.InDesign' = 'adobe'
        'Adobe.Lightroom' = 'adobe'
        'Adobe.Photoshop' = 'adobe'
        'AdvancedMicroDevicesInc.AMDSoftwareAdrenalin' = 'amd'
        'AgileBits.1Password' = '1password'
        'Anthropic.Claude' = 'claude-ai'
        'Apache.ApacheHTTPServer' = 'apache'
        'Apple.iCloud' = 'icloud'
        'Arduino.ArduinoIDE' = 'arduino'
        'Arduino.IDE' = 'arduino'
        'Asana.Asana' = 'asana'
        'Audacity.Audacity' = 'audacity'
        'Balena.Etcher' = 'balena-etcher'
        'Bitwarden.Bitwarden' = 'bitwarden'
        'Bitwarden.CLI' = 'bitwarden'
        'BlenderFoundation.Blender' = 'blender'
        'Brave.Brave' = 'brave'
        'BraveSoftware.BraveBrowser' = 'brave'
        'Canonical.Ubuntu' = 'ubuntu-linux'
        'Canonical.Ubuntu.2004' = 'ubuntu-linux'
        'Canonical.Ubuntu.2204' = 'ubuntu-linux'
        'Canonical.Ubuntu.2404' = 'ubuntu-linux'
        'Cisco.WebexTeams' = 'webex'
        'ClickUp.ClickUp' = 'clickup'
        'Cryptomator.Cryptomator' = 'cryptomator'
        'Debian.Debian' = 'debian-linux'
        'DeepL.DeepL' = 'deepl'
        'Deluge.Deluge' = 'deluge'
        'Discord.Discord' = 'discord'
        'Docker.DockerDesktop' = 'docker'
        'Dropbox.Dropbox' = 'dropbox'
        'Element.Element' = 'element'
        'EpicGames.EpicGamesLauncher' = 'epic-games'
        'Evernote.Evernote' = 'evernote'
        'Figma.Figma' = 'figma'
        'FilezillaProject.Filezilla' = 'filezilla'
        'GIMP.GIMP' = 'gimp'
        'GIMP.GIMP.2' = 'gimp'
        'GIMP.GIMP.3' = 'gimp'
        'Git.Git' = 'git'
        'GoLang.Go' = 'go'
        'Google.Chrome' = 'google-chrome'
        'Google.Chrome.EXE' = 'google-chrome'
        'Google.GoogleDrive' = 'google-drive'
        'HandBrake.HandBrake' = 'handbrake'
        'Hashicorp.Terraform' = 'terraform'
        'Helm.Helm' = 'helm'
        'JDownloader.JDownloader2' = 'jdownloader'
        'Jellyfin.JellyfinMediaPlayer' = 'jellyfin'
        'Jellyfin.Server' = 'jellyfin'
        'JetBrains.IntelliJIDEA.Community' = 'intellij'
        'JetBrains.IntelliJIDEA.Ultimate' = 'intellij'
        'JetBrains.Toolbox' = 'jetbrains-toolbox'
        'Joplin.Joplin' = 'joplin'
        'JoplinApp.Joplin' = 'joplin'
        'KeePassXCTeam.KeePassXC' = 'keepassxc'
        'Kubernetes.kubectl' = 'kubernetes'
        'Kubernetes.minikube' = 'kubernetes'
        'LibreWolf.LibreWolf' = 'librewolf'
        'Logitech.GHUB' = 'logitech'
        'Logitech.OptionsPlus' = 'logitech'
        'MEGA.MEGASync' = 'mega-nz'
        'MariaDB.Server' = 'mariadb'
        'Microsoft.Copilot' = 'microsoft-copilot'
        'Microsoft.Edge' = 'microsoft-edge'
        'Microsoft.Excel' = 'microsoft-excel'
        'Microsoft.GamingApp' = 'xbox'
        'Microsoft.Office' = 'microsoft-office'
        'Microsoft.Office.365' = 'microsoft-365'
        'Microsoft.OneDrive' = 'microsoft-onedrive'
        'Microsoft.OneNote' = 'microsoft-onenote'
        'Microsoft.Outlook' = 'microsoft-outlook'
        'Microsoft.PowerPoint' = 'microsoft-powerpoint'
        'Microsoft.Skype' = 'skype'
        'Microsoft.Teams' = 'microsoft-teams'
        'Microsoft.VisualStudioCode' = 'vscode'
        'Microsoft.VisualStudioCode.Insiders' = 'vscode'
        'Microsoft.Word' = 'microsoft-word'
        'Microsoft.XboxApp' = 'xbox'
        'Mintty.WSLtty' = 'ubuntu-linux'
        'MongoDB.Server' = 'mongodb'
        'Mozilla.Firefox' = 'firefox'
        'Mozilla.Firefox.ESR' = 'firefox'
        'Mozilla.Firefox.de' = 'firefox'
        'Mozilla.Thunderbird' = 'thunderbird'
        'Mozilla.Thunderbird.de' = 'thunderbird'
        'Mullvad.MullvadBrowser' = 'mullvad-browser'
        'Mullvad.MullvadVPN' = 'mullvad-vpn'
        'Mullvad.VPN' = 'mullvad-vpn'
        'Mumble.Mumble' = 'mumble'
        'Netgate.pfSense' = 'pfsense'
        'Nextcloud.NextcloudDesktop' = 'nextcloud'
        'Nginx.Nginx' = 'nginx'
        'NordSecurity.NordVPN' = 'nordvpn'
        'NordVPN.NordVPN' = 'nordvpn'
        'Notion.Notion' = 'notion'
        'Nvidia.GeForceExperience' = 'nvidia'
        'ONLYOFFICE.DesktopEditors' = 'onlyoffice'
        'OPNsense.OPNsense' = 'opnsense'
        'Obsidian.Obsidian' = 'obsidian'
        'Ollama.Ollama' = 'ollama'
        'OpenAI.ChatGPT' = 'chatgpt'
        'OpenJS.NodeJS' = 'nodejs'
        'OpenJS.NodeJS.LTS' = 'nodejs'
        'OpenVPNTechnologies.OpenVPN' = 'openvpn'
        'OpenVPNTechnologies.OpenVPNConnect' = 'openvpn'
        'OpenWhisperSystems.Signal' = 'signal'
        'Opera.Opera' = 'opera'
        'Opera.OperaGX' = 'opera'
        'Oracle.MySQL' = 'mysql'
        'OwnCloud.Client' = 'owncloud'
        'PHP.PHP' = 'php'
        'Pi-hole.Pi-hole' = 'pi-hole'
        'Plex.Plex' = 'plex'
        'Plex.PlexDesktop' = 'plex'
        'PostgreSQL.PostgreSQL' = 'postgres'
        'Proton.ProtonDrive' = 'proton-drive'
        'Proton.ProtonMail' = 'proton-mail'
        'Proton.ProtonPass' = 'proton-pass'
        'Proton.ProtonVPN' = 'proton-vpn'
        'ProtonTechnologies.ProtonVPN' = 'proton-vpn'
        'PuTTY.PuTTY' = 'putty'
        'Python.Python.3.11' = 'python'
        'Python.Python.3.12' = 'python'
        'Python.Python.3.13' = 'python'
        'Rclone.Rclone' = 'rclone'
        'RedHat.Ansible' = 'ansible'
        'Redis.Redis' = 'redis'
        'Resilio.Sync' = 'resiliosync'
        'RubyInstallerTeam.Ruby.3.3' = 'ruby'
        'RustDesk.RustDesk' = 'rustdesk'
        'Rustlang.Rust.MSVC' = 'rust'
        'Rustlang.Rustup' = 'rust'
        'SlackTechnologies.Slack' = 'slack'
        'Spotify.Spotify' = 'spotify'
        'Stremio.Stremio' = 'stremio'
        'Syncthing.Syncthing' = 'syncthing'
        'TIDAL.TIDAL' = 'tidal'
        'Tailscale.Tailscale' = 'tailscale'
        'TeamSpeakSystems.TeamSpeak.Client' = 'teamspeak'
        'TeamSpeakSystems.TeamSpeakClient' = 'teamspeak'
        'Telegram.TelegramDesktop' = 'telegram'
        'TheDocumentFoundation.LibreOffice' = 'libreoffice'
        'TodoistInc.Todoist' = 'todoist'
        'Transmission.Transmission' = 'transmission'
        'Ubiquiti.UniFi' = 'unifi'
        'Valve.Steam' = 'steam'
        'Viber.Viber' = 'viber'
        'Vivaldi.Vivaldi' = 'vivaldi'
        'WhatsApp.WhatsApp' = 'whatsapp'
        'WireGuard.WireGuard' = 'wireguard'
        'WiresharkFoundation.Wireshark' = 'wireshark'
        'XBMCFoundation.Kodi' = 'kodi'
        'ZeroTier.ZeroTierOne' = 'zerotier'
        'Zoom.Zoom' = 'zoom'
        'calibre.calibre' = 'calibre'
        'qBittorrent.qBittorrent' = 'qbittorrent'
    
    # Microsoft Runtimes/Redistributables -> Windows-Logo
    'Microsoft.DotNet.Native.Runtime' = 'microsoft'
    'Microsoft.VCRedist.2008.x86' = 'cpp'
    'Microsoft.VCRedist.2008.x64' = 'cpp'
    'Microsoft.VCRedist.2010.x86' = 'cpp'
    'Microsoft.VCRedist.2010.x64' = 'cpp'
    'Microsoft.VCRedist.2012.x86' = 'cpp'
    'Microsoft.VCRedist.2012.x64' = 'cpp'
    'Microsoft.VCRedist.2013.x86' = 'cpp'
    'Microsoft.VCRedist.2013.x64' = 'cpp'
    'Microsoft.VCRedist.2015+.x86' = 'cpp'
    'Microsoft.VCRedist.2015+.x64' = 'cpp'
    'Microsoft.VCRedist.2017.x86' = 'cpp'
    'Microsoft.VCRedist.2017.x64' = 'cpp'
    'Microsoft.VCLibs.Desktop.14' = 'cpp'
    'Microsoft.WindowsDesktopRuntime.3.1' = 'microsoft'
    'Microsoft.WindowsDesktopRuntime.5' = 'microsoft'
    'Microsoft.WindowsDesktopRuntime.6' = 'microsoft'
    'Microsoft.WindowsDesktopRuntime.7' = 'microsoft'
    'Microsoft.WindowsDesktopRuntime.8' = 'microsoft'
    'Microsoft.WindowsDesktopRuntime.9' = 'microsoft'
    'Microsoft.WindowsDesktopRuntime.10' = 'microsoft'
    'Microsoft.WindowsAppRuntime.1.4' = 'microsoft-windows'
    'Microsoft.WindowsAppRuntime.1.5' = 'microsoft-windows'
    'Microsoft.WindowsAppRuntime.1.6' = 'microsoft-windows'
    'Microsoft.WindowsAppRuntime.1.7' = 'microsoft-windows'
    'Microsoft.WindowsAppRuntime.1.8' = 'microsoft-windows'
    'Microsoft.DirectX' = 'microsoft-windows'
    # Weitere gaengige Programme
    'TeamViewer.TeamViewer' = 'team-viewer'
    'NVIDIA.PhysX' = 'nvidia'

    # === Im dashboard-icons-Index (lädt Build-IconCatalog automatisch) ===
    'ElectronicArts.EADesktop' = 'electronic-arts'
    'Microsoft.WindowsTerminal' = 'terminal'
    # === Custom-Icons (User legt PNG mit diesem Slug-Namen in icon-catalog\ ab) ===
    'VideoLAN.VLC' = 'vlc'
    'SplitmediaLabs.XSplitVCam' = 'xsplit-vcam'
    'Blizzard.BattleNet' = 'battle-net'
    'GOG.Galaxy' = 'gog'
    'Playnite.Playnite' = 'playnite'
    'BlackTreeGaming.Vortex' = 'vortex'
    'Serif.Affinity.Photo' = 'affinity'
    'Serif.Affinity.Designer' = 'affinity'
    'Serif.Affinity.Publisher' = 'affinity'
    'ente.io' = 'ente'
    'ImageGlass.ImageGlass' = 'imageglass'
    'PintaProject.Pinta' = 'pinta'
    'JabraEnterprise.JabraDirect' = 'jabra'
    'Jabra.JabraDirect' = 'jabra'
    'iLovePDF.iLovePDFDesktop' = 'ilovepdf'
    'Malwarebytes.Malwarebytes' = 'malwarebytes'
    'voidtools.Everything' = 'everything'
    'LanguageTool.LanguageTool' = 'languagetool'
    'Microsoft.PowerToys' = 'powertoys'
    'Cofyc.XYplorer' = 'xyplorer'
    'XYplorer.XYplorer' = 'xyplorer'
    'Elgato.ControlCenter' = 'elgato'
    'Elgato.StreamDeck' = 'elgato-stream-deck'
    'Bandicam.Bandicam' = 'bandicam'
    'DYMO.DYMOConnect' = 'dymo'
    'Insta360.Link' = 'insta360'
    'SplitmediaLabs.SplitCam' = 'splitcam'
    'SparkLabs.Viscosity' = 'viscosity'
    'AdGuard.AdGuard' = 'adguard-home'
    'ESET.SmartSecurity' = 'eset'
    'ESET.Endpoint.Antivirus' = 'eset'
    'ESET.NOD32' = 'eset'
    'IObit.IObitUnlocker' = 'iobit'
    'TechSmith.Snagit.2026' = 'snagit'
    'TechSmith.Snagit.2025' = 'snagit'
    'TechSmith.Snagit' = 'snagit'
    'JAMSoftware.TreeSize.Free' = 'treesize'
    'JAMSoftware.TreeSize' = 'treesize'
    'RARLab.WinRAR' = 'winrar'
    'Razer.Synapse' = 'razer'
    'Razer.RazerInstaller' = 'razer'
    'Corsair.iCUE.5' = 'corsair'
    'Corsair.iCUE.4' = 'corsair'
    'Corsair.iCUE' = 'corsair'
    'GIGABYTE.RGBFusion' = 'rgb2-logo'
    'AquaSnap.AquaSnap' = 'aquasnap'

    # === Korrigierte/erweiterte Mappings (echte Winget-IDs aus User-Presets) ===
    # .NET Desktop Runtime (korrekte ID-Schreibweise)
    'Microsoft.DotNet.DesktopRuntime.3.1' = 'microsoft'
    'Microsoft.DotNet.DesktopRuntime.5' = 'microsoft'
    'Microsoft.DotNet.DesktopRuntime.6' = 'microsoft'
    'Microsoft.DotNet.DesktopRuntime.7' = 'microsoft'
    'Microsoft.DotNet.DesktopRuntime.8' = 'microsoft'
    'Microsoft.DotNet.DesktopRuntime.9' = 'microsoft'
    'Microsoft.DotNet.DesktopRuntime.10' = 'microsoft'
    # VCLibs (Schreibweise im Preset)
    'Microsoft.VCLibs.14' = 'cpp'
    # UI.Xaml und AppInstaller
    'Microsoft.UI.Xaml.2.8' = 'microsoft-windows'
    'Microsoft.AppInstaller' = 'microsoft'
    # WhatsApp (Microsoft Store)
    '9NKSQGP7F2NH' = 'whatsapp'
    # Jabra (korrekte ID)
    'Jabra.Direct' = 'jabra'
    # XYplorer (korrekte ID)
    'CologneCodeCompany.XYplorer' = 'xyplorer'
    # Bandicam (korrekte ID)
    'BandicamCompany.Bandicam' = 'bandicam'
    # Insta360 (korrekte ID)
    'Insta360.Link.Controller' = 'insta360'
    # SplitCam (korrekte ID)
    'SplitCam.SplitCam' = 'splitcam'
    # LanguageTool (korrekte ID)
    'Learneo.LanguageTool' = 'languagetool'
    # ImageGlass (korrekte ID)
    'DuongDieuPhap.ImageGlass' = 'imageglass'
    # Pinta (korrekte ID)
    'Pinta.Pinta' = 'pinta'
    # AquaSnap (korrekte ID)
    'NurgoSoftware.AquaSnap' = 'aquasnap'
    # Vortex (korrekte ID)
    'NexusMods.Vortex' = 'vortex'
    # Affinity (korrekte ID - Canva hat Affinity uebernommen)
    'Canva.Affinity' = 'Affinity'
    # Razer (korrekte ID)
    'Razer.RazerSynapse' = 'razer'
    # ente (korrekte ID)
    'ente-io.photos-desktop' = 'ente'

    # Hotfix 9: aus User-Tabelle ergaenzt (Dateinamen wie vom User angegeben)
    'eMClient.eMClient' = 'emclient'
    'Ubisoft.Connect' = 'Ubisoft'
    # Affinity in allen bekannten Varianten -> 'Affinity'
    'Affinity.Photo' = 'Affinity'
    'Affinity.Photo.2' = 'Affinity'
    'Affinity.Designer' = 'Affinity'
    'Affinity.Designer.2' = 'Affinity'
    'Affinity.Publisher' = 'Affinity'
    'Affinity.Publisher.2' = 'Affinity'
    'SerifEurope.Affinity.Photo' = 'Affinity'
    'SerifEurope.Affinity.Designer' = 'Affinity'
    'SerifEurope.Affinity.Publisher' = 'Affinity'
    # 1Password Varianten -> '1password'
    'AgileBits.1Password.CLI' = '1password'
    '1Password.1Password' = '1password'
    '1Password.CLI' = '1password'
    # Bullzip PDF Printer
    'Bullzip.PDFPrinter' = 'BullzipPDFPrinter'

    # Hotfix 11: Microsoft Store Produkt-IDs
    '9NLVZBZ2WZ28' = 'ilovepdf'
}

    $sync.IconSlugMap     = $IconSlugMap
    $sync.IconImageCache  = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    $sync.IconFailedIds   = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $sync.IconPendingImgs = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[System.Windows.Controls.Image]]' ([System.StringComparer]::OrdinalIgnoreCase)
    $sync.IconAvailableSlugs = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    $sync.IconDownloadQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    $sync.IconReadyQueue    = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()
    $sync.IconRunspaceActive = $false

    # Index laden falls vorhanden und noch frisch (max 7 Tage)
    try {
        if (Test-Path $sync.IconIndexPath) {
            $age = (Get-Date) - (Get-Item $sync.IconIndexPath).LastWriteTime
            if ($age.TotalDays -lt 7) {
                $idx = Get-Content $sync.IconIndexPath -Raw -Encoding UTF8 | ConvertFrom-Json
                foreach ($s in $idx) { [void]$sync.IconAvailableSlugs.Add([string]$s) }
            }
        }
    } catch {}

    $sync.IconFallbackColors = @(
        "#5b6c8a","#7a4e7e","#a93226","#1f6f43","#b87333","#475569",
        "#0f766e","#7c3aed","#b45309","#9f1239","#0369a1","#4d7c0f",
        "#6b21a8","#a16207","#0d9488","#be123c","#1d4ed8","#65a30d"
    )

    $sync.IconCachePathFor = {
        param($slug)
        $safe = ($slug -replace '[^a-zA-Z0-9_\-]','_')
        return (Join-Path $sync.IconCacheDir ("$safe.png"))
    }

    # ── ARP-Datenbank: DisplayName -> Liste aller passenden Eintraege ────────
    $sync.LoadARPDatabase = {
        if ($sync.ARPDatabase) { return }
        $sync.ARPDatabase = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[hashtable]]' ([System.StringComparer]::OrdinalIgnoreCase)

        $paths = @(
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
        )
        foreach ($p in $paths) {
            if (-not (Test-Path $p)) { continue }
            try {
                Get-ChildItem $p -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                        if ($props -and $props.DisplayName) {
                            $key = $props.DisplayName.Trim().ToLower()
                            if (-not $key) { return }
                            $entry = @{
                                DisplayName     = $props.DisplayName
                                DisplayIcon     = $props.DisplayIcon
                                InstallLocation = $props.InstallLocation
                                Publisher       = $props.Publisher
                            }
                            if (-not $sync.ARPDatabase.ContainsKey($key)) {
                                $sync.ARPDatabase[$key] = New-Object 'System.Collections.Generic.List[hashtable]'
                            }
                            [void]$sync.ARPDatabase[$key].Add($entry)
                        }
                    } catch {}
                }
            } catch {}
        }
    }

    # ── Pfad-Aufloesung: WingetID -> Icon-Quelle (EXE/DLL/ICO) ───────────────
    $sync.ResolveExeIconPath = {
        param($wingetId, $displayName)
        if (-not $displayName) { return $null }
        if (-not $sync.ARPDatabase) { & $sync.LoadARPDatabase }

        $entries = $null
        $key = $displayName.Trim().ToLower()
        # 1. Exakter Name
        if ($sync.ARPDatabase.ContainsKey($key)) {
            $entries = $sync.ARPDatabase[$key]
        }
        # 2. Starts-With Match (vorsichtig: nur wenn eindeutig)
        if (-not $entries) {
            $matchingKeys = @()
            foreach ($k in $sync.ARPDatabase.Keys) {
                if ($k.StartsWith($key) -or $key.StartsWith($k)) {
                    $matchingKeys += $k
                    if ($matchingKeys.Count -gt 3) { break }
                }
            }
            if ($matchingKeys.Count -eq 1) { $entries = $sync.ARPDatabase[$matchingKeys[0]] }
        }
        if (-not $entries -or $entries.Count -eq 0) { return $null }

        # Bei mehreren Eintraegen: waehle den, dessen Pfad/Publisher zur WingetID passt
        $entry = $null
        if ($entries.Count -eq 1) {
            $entry = $entries[0]
        } else {
            # Publisher aus WingetID extrahieren (erster Teil vor Punkt)
            $publisher = ""
            if ($wingetId -and $wingetId.Contains(".")) {
                $publisher = ($wingetId -split '\.')[0].ToLower()
            }
            if ($publisher) {
                foreach ($e in $entries) {
                    $combined = (("" + $e.DisplayIcon + " " + $e.InstallLocation + " " + $e.Publisher)).ToLower()
                    if ($combined.Contains($publisher)) { $entry = $e; break }
                }
            }
            if (-not $entry) { $entry = $entries[0] }  # Fallback: erster Eintrag
        }
        if (-not $entry) { return $null }

        # DisplayIcon parsen (kann "path,index" sein)
        if ($entry.DisplayIcon) {
            $raw = $entry.DisplayIcon.Trim().Trim('"')
            if ($raw -match '^(.+?),-?\d+$') { $raw = $matches[1].Trim() }
            if ($raw -and (Test-Path -LiteralPath $raw -PathType Leaf -ErrorAction SilentlyContinue)) {
                return $raw
            }
        }

        # Fallback: primaere EXE im InstallLocation suchen
        if ($entry.InstallLocation) {
            $loc = $entry.InstallLocation.Trim().Trim('"')
            if ($loc -and (Test-Path -LiteralPath $loc -PathType Container -ErrorAction SilentlyContinue)) {
                try {
                    $exes = Get-ChildItem -LiteralPath $loc -Filter "*.exe" -ErrorAction SilentlyContinue |
                        Where-Object {
                            $_.Name -notmatch '(?i)(uninst|update|setup|crash|helper|launcher|tray|notification|service)'
                        } | Sort-Object Length -Descending
                    if ($exes) { return $exes[0].FullName }
                } catch {}
            }
        }
        return $null
    }

    # ── Icon aus EXE extrahieren + cachen ────────────────────────────────────
    $sync.ExtractExeIconBitmap = {
        param($exePath, $id)
        if (-not $exePath) { return $null }

        $safe = ($id -replace '[^a-zA-Z0-9_\-\.]', '_')
        $cachePath = Join-Path $sync.IconCacheDir ("exe_" + $safe + ".png")
        if (Test-Path $cachePath) {
            return (& $sync.LoadIconBitmap $cachePath)
        }
        if (-not ("WT.IconExtractor" -as [type])) { return $null }
        try {
            $bytes = [WT.IconExtractor]::ExtractIconPng($exePath)
            if ($bytes -and $bytes.Length -gt 200) {
                [System.IO.File]::WriteAllBytes($cachePath, $bytes)
                return (& $sync.LoadIconBitmap $cachePath)
            }
        } catch {}
        return $null
    }

    # ── Initial-Kreis als 24x24 BitmapSource ─────────────────────────────────
    $sync.MakeInitialIcon = {
        param($name)
        if (-not $name) { $name = "?" }
        $letter = ($name.Substring(0,1)).ToUpper()
        $sum = 0
        foreach ($c in $name.ToCharArray()) { $sum += [int]$c }
        $colorHex = $sync.IconFallbackColors[$sum % $sync.IconFallbackColors.Count]

        $dv = New-Object System.Windows.Media.DrawingVisual
        $dc = $dv.RenderOpen()
        $brush = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString($colorHex))
        $brush.Freeze()
        $dc.DrawEllipse($brush, $null, (New-Object System.Windows.Point(12,12)), 12.0, 12.0)
        $tf = New-Object System.Windows.Media.Typeface("Segoe UI")
        $ft = New-Object System.Windows.Media.FormattedText(
            $letter,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Windows.FlowDirection]::LeftToRight,
            $tf, 13.0,
            [System.Windows.Media.Brushes]::White,
            96.0
        )
        $ft.SetFontWeight([System.Windows.FontWeights]::Bold)
        $pt = New-Object System.Windows.Point((12 - $ft.Width/2),(12 - $ft.Height/2))
        $dc.DrawText($ft, $pt)
        $dc.Close()

        $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap(24,24,96,96,[System.Windows.Media.PixelFormats]::Pbgra32)
        $bmp.Render($dv)
        $bmp.Freeze()
        return $bmp
    }

    $sync.LoadIconBitmap = {
        param($path)
        try {
            $bi = New-Object System.Windows.Media.Imaging.BitmapImage
            $bi.BeginInit()
            $bi.CacheOption       = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bi.CreateOptions     = [System.Windows.Media.Imaging.BitmapCreateOptions]::IgnoreColorProfile
            $bi.DecodePixelHeight = 24
            $bi.UriSource         = [Uri]::new($path)
            $bi.EndInit()
            $bi.Freeze()
            return $bi
        } catch { return $null }
    }

    # ── Icon-Anfrage: EXE -> CDN-Cache -> CDN-Download -> Buchstaben ─────────
    $sync.RequestIcon = {
        param($id, $name, $img)
        if (-not $img) { return }

        # Sofort Initial-Kreis als Platzhalter
        $img.Source = (& $sync.MakeInitialIcon $name)
        if (-not $id) { return }

        # Memory-Cache?
        if ($sync.IconImageCache.ContainsKey($id)) {
            $cached = $sync.IconImageCache[$id]
            if ($cached) { $img.Source = $cached }
            return
        }
        if ($sync.IconFailedIds.Contains($id)) { return }

        # === STUFE 1: Cache-Lookup (Custom-PNG via Mapping) ===================
        $slugs = New-Object System.Collections.Generic.List[string]
        if ($sync.IconSlugMap.ContainsKey($id)) { [void]$slugs.Add($sync.IconSlugMap[$id]) }
        $low = $id.ToLower()
        $h1 = ($low -replace '[._\s]+','-').TrimEnd('-').TrimStart('-')
        if ($h1 -and -not $slugs.Contains($h1)) { [void]$slugs.Add($h1) }
        if ($low.Contains('.')) {
            $h2 = ($low -split '\.')[-1]
            $h2 = ($h2 -replace '[_\s]+','-').TrimEnd('-').TrimStart('-')
            if ($h2 -and -not $slugs.Contains($h2)) { [void]$slugs.Add($h2) }
        }
        foreach ($slug in $slugs) {
            $safe = ($slug -replace '[^a-zA-Z0-9_\-]','_')
            # Erst mitgelieferter Katalog, dann lokaler Cache
            $candidates = @()
            if ($sync.IconCatalogDir) {
                $candidates += (Join-Path $sync.IconCatalogDir "$safe.png")
            }
            $candidates += (Join-Path $sync.IconCacheDir "$safe.png")
            foreach ($cp in $candidates) {
                if (Test-Path $cp) {
                    $bmp = & $sync.LoadIconBitmap $cp
                    if ($bmp) {
                        $sync.IconImageCache[$id] = $bmp
                        $img.Source = $bmp
                        return
                    }
                }
            }
        }

        # === STUFE 2: EXE-Extraktion als Fallback (wenn kein Cache-Treffer) ===
        $displayName = $name
        if ($sync.InstalledNames -and $sync.InstalledNames.ContainsKey($id)) {
            $displayName = $sync.InstalledNames[$id]
        }
        $exePath = & $sync.ResolveExeIconPath $id $displayName
        if ($exePath) {
            $bmp = & $sync.ExtractExeIconBitmap $exePath $id
            if ($bmp) {
                $sync.IconImageCache[$id] = $bmp
                $img.Source = $bmp
                return
            }
        }

        # === STUFE 3: In Download-Queue stellen =============================
        if (-not $sync.IconPendingImgs.ContainsKey($id)) {
            $sync.IconPendingImgs[$id] = New-Object System.Collections.Generic.List[System.Windows.Controls.Image]
            $sync.IconDownloadQueue.Enqueue($id)
        }
        [void]$sync.IconPendingImgs[$id].Add($img)

        if (-not $sync.IconRunspaceActive) {
            & $sync.StartIconRunspace
        }
    }

    # ── Background-Runspace fuer CDN-Downloads (unveraendert ggü v6) ────────
    $sync.StartIconRunspace = {
        if ($sync.IconRunspaceActive) { return }
        $sync.IconRunspaceActive = $true

        $bgScript = {
            param($syncRef)
            try {
                [System.Net.ServicePointManager]::SecurityProtocol = `
                    [System.Net.SecurityProtocolType]::Tls12 -bor `
                    [System.Net.SecurityProtocolType]::Tls11 -bor `
                    [System.Net.SecurityProtocolType]::Tls
            } catch {}

            try { Add-Type -AssemblyName System.Net.Http } catch {}
            $handler = New-Object System.Net.Http.HttpClientHandler
            $handler.AllowAutoRedirect = $true
            $httpClient = New-Object System.Net.Http.HttpClient($handler)
            $httpClient.Timeout = [TimeSpan]::FromSeconds(5)
            $httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("Appstallo/1.9.1") | Out-Null

            $logFile = Join-Path $syncRef.IconCacheDir "_iconworker.log"

            # tree.json laden falls Index leer
            if ($syncRef.IconAvailableSlugs.Count -eq 0) {
                try {
                    $treeUrl = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons@main/tree.json"
                    $t = $httpClient.GetStringAsync($treeUrl)
                    if ($t.Wait(15000)) {
                        $tree = $t.Result | ConvertFrom-Json
                        $count = 0
                        if ($tree.png) {
                            foreach ($fname in $tree.png) {
                                if ($fname -is [string] -and $fname.EndsWith(".png")) {
                                    $slug = $fname.Substring(0, $fname.Length - 4)
                                    [void]$syncRef.IconAvailableSlugs.Add($slug)
                                    $count++
                                }
                            }
                        }
                        try {
                            $arr = @($syncRef.IconAvailableSlugs)
                            $arr | ConvertTo-Json -Compress | Set-Content -Path $syncRef.IconIndexPath -Encoding UTF8
                        } catch {}
                        "$(Get-Date -Format HH:mm:ss) [INDEX] loaded $count slugs from tree.json" | Add-Content -Path $logFile -Encoding UTF8 -ErrorAction SilentlyContinue
                    }
                } catch {
                    "$(Get-Date -Format HH:mm:ss) [INDEX] error: $($_.Exception.GetBaseException().Message)" | Add-Content -Path $logFile -Encoding UTF8 -ErrorAction SilentlyContinue
                }
            }

            $idleCount = 0
            try {
                while ($true) {
                    $id = $null
                    $hasId = $syncRef.IconDownloadQueue.TryDequeue([ref]$id)
                    if (-not $hasId) {
                        $idleCount++
                        if ($idleCount -gt 300) { break }
                        Start-Sleep -Milliseconds 100
                        continue
                    }
                    $idleCount = 0
                    $foundPath = $null

                    try {
                        $slugs = New-Object System.Collections.Generic.List[string]
                        if ($syncRef.IconSlugMap.ContainsKey($id)) {
                            [void]$slugs.Add($syncRef.IconSlugMap[$id])
                        }
                        $low = $id.ToLower()
                        $h1  = ($low -replace '[._\s]+','-').TrimEnd('-').TrimStart('-')
                        if ($h1 -and -not $slugs.Contains($h1)) { [void]$slugs.Add($h1) }
                        if ($low.Contains('.')) {
                            $parts = @($low -split '\.')
                            $last = ($parts[-1] -replace '[_\s]+','-').TrimEnd('-').TrimStart('-')
                            if ($last -and -not $slugs.Contains($last)) { [void]$slugs.Add($last) }
                            if ($parts.Count -ge 2) {
                                $second = ($parts[-2] -replace '[_\s]+','-').TrimEnd('-').TrimStart('-')
                                $combo = "$second-$last"
                                if ($combo -and -not $slugs.Contains($combo)) { [void]$slugs.Add($combo) }
                            }
                        }

                        $cacheDir = $syncRef.IconCacheDir
                        $catalogDir = $syncRef.IconCatalogDir
                        $useIndex = $syncRef.IconAvailableSlugs.Count -gt 0
                        foreach ($slug in $slugs) {
                            $safe = ($slug -replace '[^a-zA-Z0-9_\-]','_')
                            # Mitgelieferter Katalog hat Vorrang
                            if ($catalogDir) {
                                $catalogPath = Join-Path $catalogDir "$safe.png"
                                if (Test-Path $catalogPath) { $foundPath = $catalogPath; break }
                            }
                            $cachePath = Join-Path $cacheDir "$safe.png"
                            if (Test-Path $cachePath) { $foundPath = $cachePath; break }
                            if ($useIndex -and -not $syncRef.IconAvailableSlugs.Contains($slug)) { continue }

                            try {
                                $url = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/$slug.png"
                                $respTask = $httpClient.GetAsync($url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead)
                                if (-not $respTask.Wait(5000)) { continue }
                                $resp = $respTask.Result
                                if (-not $resp.IsSuccessStatusCode) {
                                    try { $resp.Dispose() } catch {}
                                    continue
                                }
                                $bytesTask = $resp.Content.ReadAsByteArrayAsync()
                                if (-not $bytesTask.Wait(5000)) {
                                    try { $resp.Dispose() } catch {}
                                    continue
                                }
                                $bytes = $bytesTask.Result
                                try { $resp.Dispose() } catch {}
                                if ($bytes -and $bytes.Length -gt 200) {
                                    [System.IO.File]::WriteAllBytes($cachePath, $bytes)
                                    "$(Get-Date -Format HH:mm:ss) [$id] downloaded: $slug" | Add-Content -Path $logFile -Encoding UTF8 -ErrorAction SilentlyContinue
                                    $foundPath = $cachePath
                                    break
                                }
                            } catch {}
                        }
                    } catch {}

                    $result = @{ Id = $id; Path = $foundPath }
                    $syncRef.IconReadyQueue.Enqueue($result)
                }
            } catch {} finally {
                try { $httpClient.Dispose() } catch {}
                try { $handler.Dispose() } catch {}
            }
        }

        $sync.IconRS = [runspacefactory]::CreateRunspace()
        $sync.IconRS.ApartmentState = "STA"
        $sync.IconRS.ThreadOptions  = "ReuseThread"
        $sync.IconRS.Open()
        $sync.IconRS.SessionStateProxy.SetVariable("syncRef", $sync)
        $sync.IconRSPS = [powershell]::Create()
        $sync.IconRSPS.Runspace = $sync.IconRS
        [void]$sync.IconRSPS.AddScript($bgScript).AddArgument($sync)
        $sync.IconRSHandle = $sync.IconRSPS.BeginInvoke()

        $sync.IconUITimer = New-Object System.Windows.Threading.DispatcherTimer
        $sync.IconUITimer.Interval = [TimeSpan]::FromMilliseconds(150)
        $sync.IconUITimer.Add_Tick({
            $processed = 0
            $result = $null
            while ($sync.IconReadyQueue.TryDequeue([ref]$result) -and $processed -lt 5) {
                $rid  = $result.Id
                $path = $result.Path
                $bmp  = $null
                if ($path) { $bmp = & $sync.LoadIconBitmap $path }
                if ($bmp) {
                    $sync.IconImageCache[$rid] = $bmp
                    if ($sync.IconPendingImgs.ContainsKey($rid)) {
                        foreach ($img in $sync.IconPendingImgs[$rid]) {
                            try { $img.Source = $bmp } catch {}
                        }
                        $sync.IconPendingImgs.Remove($rid) | Out-Null
                    }
                } else {
                    [void]$sync.IconFailedIds.Add($rid)
                    if ($sync.IconPendingImgs.ContainsKey($rid)) {
                        $sync.IconPendingImgs.Remove($rid) | Out-Null
                    }
                }
                $processed++
            }
            if ($sync.IconRSHandle.IsCompleted -and $sync.IconReadyQueue.Count -eq 0) {
                $sync.IconUITimer.Stop()
                try { $sync.IconRSPS.EndInvoke($sync.IconRSHandle) } catch {}
                try { $sync.IconRSPS.Dispose() } catch {}
                try { $sync.IconRS.Close() } catch {}
                try { $sync.IconRS.Dispose() } catch {}
                $sync.IconRunspaceActive = $false
            }
        })
        $sync.IconUITimer.Start()
    }


    $sync.BuildUI = {
        $sync.ProgramList.Children.Clear()
        $sync.AllEntries.Clear()
        $sync.AllProgramItems.Clear()
        $sync.SelectedIds.Clear()
        $sync.AllSelected = $false

        $grouped = @{}
        foreach ($prog in $sync.FoundPrograms) {
            # Kategoriezuordnung wird ZENTRAL in Appstallo.Common.ps1 gepflegt:
            # 1) bekannte ID aus KnownDb (nur falls Cat in CatOrder gueltig)
            # 2) Get-AppstalloCategoryFor (Keyword-Match, gleiche Logik wie Bibliothek)
            $cat = $null
            $matchKey = $sync.KnownDb.Keys | Where-Object { $_ -ieq $prog.Id } | Select-Object -First 1
            if ($matchKey) {
                $knownCat = $sync.KnownDb[$matchKey].Cat
                if ($sync.CatOrder -contains $knownCat) { $cat = $knownCat }
            }
            if (-not $cat) { $cat = Get-AppstalloCategoryFor -Name $prog.Name -Id $prog.Id }
            if (-not $grouped.ContainsKey($cat)) { $grouped[$cat] = [System.Collections.Generic.List[object]]::new() }
            [void]$grouped[$cat].Add($prog)
        }

        foreach ($catName in $sync.CatOrder) {
            if (-not $grouped.ContainsKey($catName)) { continue }

            # Kategorie-Header
            $hdr = New-Object System.Windows.Controls.TextBlock
            $hdr.Text       = $catName
            $hdr.Foreground = $sync.ClrRed
            $hdr.FontWeight = "Bold"
            $hdr.FontSize   = 13
            $hdr.Margin     = [System.Windows.Thickness]::new(0,14,0,4)
            [void]$sync.ProgramList.Children.Add($hdr)

            foreach ($prog in ($grouped[$catName] | Sort-Object { $_.Name })) {
                $idCopy   = $prog.Id
                $nameCopy = $prog.Name
                # Hotfix 18: PWA-Kennzeichnung
                if ($idCopy -match "(?i)(FFPWA|MSEDGE.?PWA|^ARP\\.*PWA)" -and $nameCopy -notmatch "\[PWA\]") {
                    $nameCopy = "$nameCopy [PWA]"
                }
                $matchKey2 = $sync.KnownDb.Keys | Where-Object { $_ -ieq $prog.Id } | Select-Object -First 1
                $desc = if ($matchKey2) { $sync.KnownDb[$matchKey2].Desc } else { "Version: $($prog.Version)" }

                $row = New-Object System.Windows.Controls.Grid
                $row.Margin = [System.Windows.Thickness]::new(0,2,0,2)
                $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = [System.Windows.GridLength]::Auto
                $col2 = New-Object System.Windows.Controls.ColumnDefinition; $col2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
                $col3 = New-Object System.Windows.Controls.ColumnDefinition; $col3.Width = [System.Windows.GridLength]::Auto
                [void]$row.ColumnDefinitions.Add($col1)
                [void]$row.ColumnDefinitions.Add($col2)
                [void]$row.ColumnDefinitions.Add($col3)

                $cb = New-Object System.Windows.Controls.CheckBox
                $cb.VerticalAlignment = "Center"
                $cb.Margin = [System.Windows.Thickness]::new(0,0,10,0)
                [System.Windows.Controls.Grid]::SetColumn($cb, 0)

                $sp = New-Object System.Windows.Controls.StackPanel
                $sp.Orientation = "Horizontal"
                [System.Windows.Controls.Grid]::SetColumn($sp, 1)

                # Programm-Icon (24x24) vor dem Namen
                $iconImg = New-Object System.Windows.Controls.Image
                $iconImg.Width = 24; $iconImg.Height = 24
                $iconImg.VerticalAlignment = "Center"
                $iconImg.Margin = [System.Windows.Thickness]::new(0,0,8,0)
                $iconImg.SnapsToDevicePixels = $true
                [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($iconImg, [System.Windows.Media.BitmapScalingMode]::HighQuality)
                & $sync.RequestIcon $idCopy $nameCopy $iconImg
                [void]$sp.Children.Add($iconImg)

                $nameBlock = New-Object System.Windows.Controls.TextBlock
                $nameBlock.Text       = $nameCopy
                $nameBlock.Foreground = $sync.ClrWhite
                $nameBlock.FontSize   = 12
                $nameBlock.VerticalAlignment = "Center"

                $descBlock = New-Object System.Windows.Controls.TextBlock
                $descBlock.Text       = "  — $desc"
                $descBlock.Foreground = $sync.ClrGray
                $descBlock.FontSize   = 11
                $descBlock.VerticalAlignment = "Center"

                [void]$sp.Children.Add($nameBlock)
                [void]$sp.Children.Add($descBlock)
                [void]$row.Children.Add($cb)
                [void]$row.Children.Add($sp)

                # Wickle row in einen Border damit wir Hover/Klick haben
                $itemBorder = New-Object System.Windows.Controls.Border
                $itemBorder.Padding = [System.Windows.Thickness]::new(2,2,2,2)
                $itemBorder.Child   = $row

                $cbRef = $cb; $idRef = $idCopy
                $cb.Add_Checked({
                    [void]$sync.SelectedIds.Add($idRef)
                    & $sync.UpdateCount
                }.GetNewClosure())
                $cb.Add_Unchecked({
                    [void]$sync.SelectedIds.Remove($idRef)
                    & $sync.UpdateCount
                }.GetNewClosure())

                # Info-Button ("i") am rechten Rand
                $popupName = $nameCopy
                $popupId   = $idCopy
                $popupVer  = $prog.Version
                $popupDesc = $desc

                $infoBtn = New-Object System.Windows.Controls.Border
                $infoBtn.Width  = 22; $infoBtn.Height = 22
                $infoBtn.CornerRadius    = [System.Windows.CornerRadius]::new(11)
                $infoBtn.Background      = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#2a2a2a"))
                $infoBtn.BorderBrush     = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#444444"))
                $infoBtn.BorderThickness = [System.Windows.Thickness]::new(1)
                $infoBtn.Cursor = [System.Windows.Input.Cursors]::Hand
                $infoBtn.VerticalAlignment   = "Center"
                $infoBtn.HorizontalAlignment = "Center"
                $infoBtn.Margin = [System.Windows.Thickness]::new(6,0,4,0)
                $infoTxt = New-Object System.Windows.Controls.TextBlock
                $infoTxt.Text = "i"
                $infoTxt.FontSize   = 12; $infoTxt.FontStyle = "Italic"; $infoTxt.FontWeight = "Bold"
                $infoTxt.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#888888"))
                $infoTxt.HorizontalAlignment = "Center"; $infoTxt.VerticalAlignment = "Center"
                $infoBtn.Child = $infoTxt
                [System.Windows.Controls.Grid]::SetColumn($infoBtn, 2)
                [void]$row.Children.Add($infoBtn)

                $infoBtn.Add_MouseLeftButtonDown({
                    param($s,$e)
                    $publisher = if ($popupId -match "^([^\.]+)\.") { $Matches[1] } else { "Unbekannt" }

                    $dpWin = New-Object System.Windows.Window
                    $dpWin.Title = "Programm-Details"
                    $dpWin.Width = 480; $dpWin.SizeToContent = "Height"
                    $dpWin.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#161616"))
                    $dpWin.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
                    $dpWin.WindowStartupLocation = "CenterOwner"
                    $dpWin.ResizeMode = "NoResize"
                    $dpWin.Owner = $sync.Window
                    if ($sync.AppIcon) { $dpWin.Icon = $sync.AppIcon }

                    try {
                        $dpHwnd = (New-Object System.Windows.Interop.WindowInteropHelper($dpWin)).EnsureHandle()
                        $dpDarkVal = [int]1
                        [DwmHelper]::DwmSetWindowAttribute($dpHwnd, [DwmHelper]::DWMWA_USE_IMMERSIVE_DARK_MODE, [ref]$dpDarkVal, 4)
                    } catch {}

                    $stack = New-Object System.Windows.Controls.StackPanel
                    $stack.Margin = [System.Windows.Thickness]::new(24,20,24,20)

                    $t = New-Object System.Windows.Controls.TextBlock
                    $t.Text = $popupName; $t.FontSize = 16; $t.FontWeight = "Bold"
                    $t.Foreground = [System.Windows.Media.Brushes]::White
                    $t.Margin = [System.Windows.Thickness]::new(0,0,0,14)
                    [void]$stack.Children.Add($t)

                    $addField = {
                        param($label, $value, $color)
                        $lb = New-Object System.Windows.Controls.TextBlock
                        $lb.Text = $label; $lb.FontSize = 11
                        $lb.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#888888"))
                        $lb.Margin = [System.Windows.Thickness]::new(0,0,0,2)
                        [void]$stack.Children.Add($lb)
                        $vb = New-Object System.Windows.Controls.TextBlock
                        $vb.Text = $value; $vb.FontSize = 13; $vb.TextWrapping = "Wrap"
                        $vb.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString($color))
                        $vb.Margin = [System.Windows.Thickness]::new(0,0,0,10)
                        [void]$stack.Children.Add($vb)
                    }

                    & $addField "Hersteller" $publisher "#e0e0e0"
                    & $addField "Winget-ID" $popupId "#e0e0e0"
                        # Kopieren-Button fuer Winget-ID
                        $copyPanel = New-Object System.Windows.Controls.StackPanel
                        $copyPanel.Orientation = "Horizontal"
                        $copyPanel.Margin = [System.Windows.Thickness]::new(0,-6,0,10)
                        $copyBtn = New-Object System.Windows.Controls.Border
                        $copyBtn.Background      = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#2a2a2a"))
                        $copyBtn.BorderBrush     = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#444444"))
                        $copyBtn.BorderThickness = [System.Windows.Thickness]::new(1)
                        $copyBtn.CornerRadius    = [System.Windows.CornerRadius]::new(3)
                        $copyBtn.Padding         = [System.Windows.Thickness]::new(8,3,8,3)
                        $copyBtn.Cursor          = [System.Windows.Input.Cursors]::Hand
                        $copyTxt = New-Object System.Windows.Controls.TextBlock
                        $copyTxt.Text = "ID kopieren"
                        $copyTxt.FontSize = 10
                        $copyTxt.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#888888"))
                        $copyBtn.Child = $copyTxt
                        $copyIdVal = $popupId
                        $copyBtn.Add_MouseLeftButtonDown({
                            [System.Windows.Clipboard]::SetText($copyIdVal)
                            $copyTxt.Text = "Kopiert!"
                        }.GetNewClosure())
                        [void]$copyPanel.Children.Add($copyBtn)
                        [void]$stack.Children.Add($copyPanel)
                    if ($popupVer) { & $addField "Version" $popupVer "#4ade80" }
                    & $addField "Beschreibung" $popupDesc "#cccccc"

                    $closeBtn = New-Object System.Windows.Controls.Button
                    $closeBtn.Content = "Schliessen"
                    $closeBtn.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#2a2a2a"))
                    $closeBtn.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#aaaaaa"))
                    $closeBtn.BorderThickness = [System.Windows.Thickness]::new(0)
                    $closeBtn.Padding = [System.Windows.Thickness]::new(20,8,20,8)
                    $closeBtn.FontSize = 12; $closeBtn.Cursor = [System.Windows.Input.Cursors]::Hand
                    $closeBtn.HorizontalAlignment = "Right"
                    $closeBtn.Margin = [System.Windows.Thickness]::new(0,8,0,0)
                    $closeBtn.Add_Click({ $dpWin.Close() })
                    [void]$stack.Children.Add($closeBtn)

                    $dpWin.Content = $stack
                    & $sync.ApplyGoldStyle $dpWin
                    [void]$dpWin.ShowDialog()
                    $e.Handled = $true
                }.GetNewClosure())

                # Fuer Suchfilter registrieren
                [void]$sync.AllProgramItems.Add(@{
                    Border    = $itemBorder
                    HeaderRef = $hdr
                    Name      = $nameCopy
                    Id        = $idCopy
                    Desc      = $desc
                })

                [void]$sync.AllEntries.Add(@{ CB = $cb; Id = $idCopy; Name = $nameCopy })
                [void]$sync.ProgramList.Children.Add($itemBorder)
            }
        }
        & $sync.UpdateCount
    }

    $sync.StartScan = {
        $sync.ScanDone    = $false
        $sync.ScanPanel.Visibility       = "Visible"
        $sync.SelectionPanel.Visibility  = "Collapsed"
        $sync.LogPanel.Visibility        = "Collapsed"
        $sync.SelectAllButton.Visibility = "Collapsed"
        $sync.RescanButton.Visibility    = "Collapsed"
        $sync.UninstallButton.Visibility = "Collapsed"
        $sync.BackButton.Visibility      = "Collapsed"
        $sync.CountText.Text             = ""
        $sync.StatusText.Text            = "Installierte Software wird analysiert..."

        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $rs.ApartmentState = "STA"; $rs.ThreadOptions = "ReuseThread"; $rs.Open()
        $rs.SessionStateProxy.SetVariable("sync", $sync)

        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.Runspace = $rs
        # Refactor: Get-WingetInstalledList in Runspace injizieren
        [void]$ps.AddScript($WGT_InstalledScannerCode)
        [void]$ps.AddScript({
            try {
                # === Refactor: zentrale Get-WingetInstalledList ===
                # Filter (PWA/ARP) wird in Appstallo.Common.ps1 gepflegt.
                $installed = Get-WingetInstalledList
                $results = [System.Collections.Generic.List[hashtable]]::new()
                foreach ($p in $installed) {
                    [void]$results.Add(@{ Name = $p.Name; Id = $p.Id; Version = $p.Version })
                }
                $sync.FoundPrograms = $results
            } catch {
                $sync.FoundPrograms = [System.Collections.Generic.List[hashtable]]::new()
            } finally {
                $sync.ScanDone = $true
            }
        })
        [void]$ps.BeginInvoke()
        $sync.ScanTimer.Start()
    }

    $scanTimer = New-Object System.Windows.Threading.DispatcherTimer
    $scanTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $sync.ScanTimer = $scanTimer

    $scanTimer.Add_Tick({
        try {
            if (-not $sync.ScanDone) { return }
            $sync.ScanTimer.Stop()
            & $sync.BuildUI
            $count = if ($null -ne $sync.FoundPrograms) { $sync.FoundPrograms.Count } else { 0 }
            $sync.ScanPanel.Visibility       = "Collapsed"
            $sync.SelectionPanel.Visibility  = "Visible"
            $sync.SelectAllButton.Visibility = "Visible"
            $sync.RescanButton.Visibility    = "Visible"
            $sync.UninstallButton.Visibility = "Visible"
            $sync.StatusText.Text            = "$count Programme gefunden. Programme fuer Deinstallation auswaehlen."
            $sync.CountText.Text             = "Keine Programme ausgewaehlt"
            $sync.UninstallButton.IsEnabled  = $false
        } catch {
            $sync.ScanTimer.Stop()
            $_ | Out-File $logPath -Encoding UTF8 -Append
        }
    })

    # ── Install-Timer ─────────────────────────────────────────────────────────
    $installTimer = New-Object System.Windows.Threading.DispatcherTimer
    $installTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $sync.InstallTimer = $installTimer

    $installTimer.Add_Tick({
        try {
            if ($sync.Lines.Count -gt 0) {
                $sync.LogOutput.Text = $sync.Lines -join "`n"
                $sync.LogScroller.ScrollToBottom()
            }
            if ($sync.TotalPkgs -gt 0 -and $sync.CurrentPkg -gt 0) {
                # Inline-Balken im Log animieren (Fallback wenn winget nicht streamt)
                if ($null -ne $sync.ProgressLineIdx -and
                    $sync.ProgressLineIdx -ge 0 -and
                    $sync.ProgressLineIdx -lt $sync.Lines.Count) {
                    if ($sync.PkgProgress -eq 0) {
                        if ($null -eq $sync.SynthTick) { $sync.SynthTick = 0 }
                        $sync.SynthTick++
                        $pct = [Math]::Min(85, [int]($sync.SynthTick * 2))
                        $bar = ('#' * [int]($pct / 5)).PadRight(20, '.')
                        $sync.Lines[$sync.ProgressLineIdx] = "       [$bar] $pct%"
                    }
                }
                # Live-Progress: immer determinate, mit synthetischer Animation als Fallback
                if ($sync.CurrentPkg -gt 0 -and $sync.TotalPkgs -gt 0) {
                    $sync.ProgressBar.IsIndeterminate = $false
                    $base    = (($sync.CurrentPkg - 1) / $sync.TotalPkgs) * 100
                    $stepPct = 100 / $sync.TotalPkgs
                    if ($sync.PkgProgress -gt 0) {
                        $within = ($sync.PkgProgress / 100) * $stepPct
                        $sync.ProgressBar.Value = [Math]::Min(99, $base + $within)
                    } else {
                        if ($null -eq $sync.TickCounter) { $sync.TickCounter = 0 }
                        $sync.TickCounter++
                        $synth = 30 + (($sync.TickCounter % 50) * 1)
                        if ($synth -gt 80) { $synth = 80 }
                        $within = ($synth / 100) * $stepPct
                        $sync.ProgressBar.Value = [Math]::Min(99, $base + $within)
                    }
                }
            }
            if ($sync.Done) {
                $sync.InstallTimer.Stop()
                $sync.ProgressBar.Value       = 100
                $sync.SummaryPanel.Visibility = "Visible"
                $sync.SuccessCount.Text       = $sync.Successful
                $sync.FailCount.Text          = $sync.Failed
                $sync.BackButton.Visibility   = "Visible"
                $sync.UninstallButton.IsEnabled = $false
                if ($sync.Failed -gt 0) {
                    $sync.StatusText.Text = "Abgeschlossen - $($sync.Successful) OK, $($sync.Failed) fehlgeschlagen."
                } else {
                    $sync.StatusText.Text = "$($sync.Successful) Programm(e) erfolgreich deinstalliert."
                }
            }
        } catch {
            $sync.InstallTimer.Stop()
            $_ | Out-File $logPath -Encoding UTF8 -Append
        }
    })

    # ── Buttons ───────────────────────────────────────────────────────────────
    $sync.SelectAllButton.Add_Click({
        $sync.AllSelected = -not $sync.AllSelected
        foreach ($e in $sync.AllEntries) { $e.CB.IsChecked = $sync.AllSelected }
        $sync.SelectAllButton.Content = if ($sync.AllSelected) { "Alle abwaehlen" } else { "Alle auswaehlen" }
        & $sync.UpdateCount
    })

    $sync.RescanButton.Add_Click({ & $sync.StartScan })

    $sync.UninstallButton.Add_Click({
        if ($sync.SelectedIds.Count -eq 0) { return }
        $selected = @($sync.AllEntries | Where-Object { $sync.SelectedIds.Contains($_.Id) })

        # Dark-Mode Bestaetigungs-Dialog
        $confirmResult = $false
        $cWin = New-Object System.Windows.Window
        $cWin.Title = "Bestaetigung"
        $cWin.Width = 450; $cWin.SizeToContent = "Height"
        $cWin.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#161616"))
        $cWin.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
        $cWin.WindowStartupLocation = "CenterOwner"
        $cWin.ResizeMode = "NoResize"
        $cWin.Owner = $sync.Window
        if ($sync.AppIcon) { $cWin.Icon = $sync.AppIcon }
        try {
            $cHwnd = (New-Object System.Windows.Interop.WindowInteropHelper($cWin)).EnsureHandle()
            $cDark = [int]1
            [DwmHelper]::DwmSetWindowAttribute($cHwnd, [DwmHelper]::DWMWA_USE_IMMERSIVE_DARK_MODE, [ref]$cDark, 4)
        } catch {}
        $cStack = New-Object System.Windows.Controls.StackPanel
        $cStack.Margin = [System.Windows.Thickness]::new(24,24,24,24)
        $cTxt = New-Object System.Windows.Controls.TextBlock
        $cTxt.Text = "$($selected.Count) Programm(e) werden deinstalliert. Fortfahren?"
        $cTxt.FontSize = 14; $cTxt.TextWrapping = "Wrap"
        $cTxt.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#e0e0e0"))
        $cTxt.Margin = [System.Windows.Thickness]::new(0,0,0,20)
        [void]$cStack.Children.Add($cTxt)
        $cBtnPanel = New-Object System.Windows.Controls.StackPanel
        $cBtnPanel.Orientation = "Horizontal"
        $cBtnPanel.HorizontalAlignment = "Right"
        $cYes = New-Object System.Windows.Controls.Button
        $cYes.Content = "Ja"; $cYes.Padding = [System.Windows.Thickness]::new(24,8,24,8)
        $cYes.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#a93226"))
        $cYes.Foreground = [System.Windows.Media.Brushes]::White
        $cYes.BorderThickness = [System.Windows.Thickness]::new(0)
        $cYes.FontSize = 12; $cYes.Cursor = [System.Windows.Input.Cursors]::Hand
        $cYes.Margin = [System.Windows.Thickness]::new(0,0,8,0)
        $cNo = New-Object System.Windows.Controls.Button
        $cNo.Content = "Nein"; $cNo.Padding = [System.Windows.Thickness]::new(24,8,24,8)
        $cNo.FontSize = 12; $cNo.Cursor = [System.Windows.Input.Cursors]::Hand
        $cYes.Add_Click({ $script:confirmResult = $true; $cWin.Close() })
        $cNo.Add_Click({ $cWin.Close() })
        [void]$cBtnPanel.Children.Add($cYes)
        [void]$cBtnPanel.Children.Add($cNo)
        [void]$cStack.Children.Add($cBtnPanel)
        $cWin.Content = $cStack
        $script:confirmResult = $false
        & $sync.ApplyGoldStyle $cWin
        [void]$cWin.ShowDialog()
        if (-not $script:confirmResult) { return }

        $sync.SelectionPanel.Visibility  = "Collapsed"
        $sync.LogPanel.Visibility        = "Visible"
        $sync.SelectAllButton.Visibility = "Collapsed"
        $sync.RescanButton.Visibility    = "Collapsed"
        $sync.UninstallButton.IsEnabled  = $false
        $sync.BackButton.Visibility      = "Collapsed"
        $sync.SummaryPanel.Visibility    = "Collapsed"
        $sync.ProgressBar.Value          = 0
        $sync.StatusText.Text            = "Deinstallation laeuft..."

        $sync.Done       = $false
        $sync.Successful = 0
        $sync.Failed     = 0
        $sync.TotalPkgs  = $selected.Count
        $sync.CurrentPkg = 0
        $sync.Lines.Clear(); $sync.RawLines.Clear()

        $pkgList = @($selected | ForEach-Object { @{ Id = $_.Id; Name = $_.Name } })

        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $rs.ApartmentState = "STA"; $rs.ThreadOptions = "ReuseThread"; $rs.Open()
        $rs.SessionStateProxy.SetVariable("sync",    $sync)
        $rs.SessionStateProxy.SetVariable("pkgList", $pkgList)

        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript({
            try {
                try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
                foreach ($pkg in $pkgList) {
                    $sync.CurrentPkg++
                    $sync.PkgProgress = 0
                    $sync.TickCounter = 0
                    # Inline-Progress-Zeile reservieren
                    $sync.Lines.Add("       [....................] 0%")
                    $sync.ProgressLineIdx = $sync.Lines.Count - 1
                    $sync.SynthTick = 0
                    $sync.Lines.Add("")
                    $sync.Lines.Add(">>> [$($sync.CurrentPkg)/$($sync.TotalPkgs)]  $($pkg.Name)  ($($pkg.Id))")
                    $ok = $false
                    # === Pre-Check: MSIX/AppX-App? Dann nativer Pfad ===
                    $isMsix = $false
                    $msixFullName = $null
                    $msixName = $null
                    try {
                        $shortName = ($pkg.Id -split '\.')[-1]
                        $appx = Get-AppxPackage "*$shortName*" -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($appx) {
                            $isMsix = $true
                            $msixFullName = $appx.PackageFullName
                            $msixName = $appx.Name
                            $sync.Lines.Add("       MSIX-App erkannt: $($appx.Name)")
                            $sync.Lines.Add("       Verwende Remove-AppxPackage")
                        }
                    } catch {}

                    if ($isMsix -and $msixFullName) {
                        try {
                            Remove-AppxPackage -Package $msixFullName -ErrorAction Stop
                            Start-Sleep -Seconds 2
                            $stillThere = Get-AppxPackage -Name $msixName -ErrorAction SilentlyContinue
                            if (-not $stillThere) {
                                $ok = $true
                                $sync.Lines.Add("[OK]   MSIX-App erfolgreich entfernt")
                            } else {
                                $sync.Lines.Add("[ERR]  Remove-AppxPackage lief, aber App noch da")
                            }
                        } catch {
                            $sync.Lines.Add("[ERR]  Remove-AppxPackage fehlgeschlagen: $($_.Exception.Message)")
                        }
                        if ($null -ne $sync.ProgressLineIdx) {
                            if ($ok) {
                                $sync.Lines[$sync.ProgressLineIdx] = "       [####################] 100%"
                            } else {
                                $sync.Lines.RemoveAt($sync.ProgressLineIdx)
                            }
                            $sync.ProgressLineIdx = $null
                        }
                        if ($ok) { $sync.Successful++ } else { $sync.Failed++ }
                        continue
                    }

                    # === Standard-Pfad: winget uninstall ===
                    & winget uninstall --id $pkg.Id --silent --force --accept-source-agreements 2>&1 |
                    ForEach-Object {
                        $str = $_.ToString()
                        $str = $str -replace 'Ã¼','ue' -replace 'Ã¶','oe' -replace 'Ã¤','ae' -replace 'ÃŸ','ss' -replace 'Ãœ','Ue' -replace 'Ã–','Oe' -replace 'Ã„','Ae'
                        # CR-getrennte Progress-Updates ignorieren - nur den letzten Teil nehmen
                        if ($str -match "[`r`n]") { $str = ($str -split "[`r`n]+")[-1] }
                        $str = $str.Trim()
                        if ($str -eq "" -or $str -match "^[-=]{4,}$" -or $str -match "^[-\|/\\]$") { return }
                        # Prozentzeile: Fortschritt extrahieren, nicht loggen
                        if ($str -match "^(\d+)%$") {
                            $pct = [int]$Matches[1]
                            $sync.PkgProgress = $pct
                            if ($null -ne $sync.ProgressLineIdx) {
                                $bar = ('#' * [int]($pct / 5)).PadRight(20, '.')
                                $sync.Lines[$sync.ProgressLineIdx] = "       [$bar] $pct%"
                            }
                            return
                        }
                        # winget Block-Progressbar filtern
                        if ($str -match "[\u2580-\u259F\u2588]" -or $str -match "\u00E2[\u2010-\u203A\u02C6-\u02DC\u0161\u017E\u0192\u2122]") {
                            if ($str -match "(\d+)%") {
                                $pct = [int]$Matches[1]
                                $sync.PkgProgress = $pct
                                if ($null -ne $sync.ProgressLineIdx) {
                                    $bar = ('#' * [int]($pct / 5)).PadRight(20, '.')
                                    $sync.Lines[$sync.ProgressLineIdx] = "       [$bar] $pct%"
                                }
                            }
                            return
                        }
                        if ($str -match "^\d+[\.,]?\d*\s*[KMGkmg]?B\s*/\s*\d+[\.,]?\d*\s*[KMGkmg]?B") { return }
                        if ($str -match "[\x00-\x08\x0B-\x1F]") { return }
                        $sync.RawLines.Add($str)
                        if ($str -match "(?i)(Successfully uninstalled|Erfolgreich deinstalliert|was successfully uninstalled)") {
                            $ok = $true; $sync.Lines.Add("[OK]   $str")
                        } elseif ($str -match "(?i)(failed|fehlgeschlagen|error)" -and $str -notmatch "^[\s\-=]") {
                            $sync.Lines.Add("[ERR]  $str")
                        } else {
                            $sync.Lines.Add("       $str")
                        }
                    }
                    # Wenn nicht eindeutig OK: bis zu 90 Sekunden lang pollen ob das Paket
                    # nicht mehr installiert ist. Bei Programmen wie Opera startet winget einen
                    # GUI-Uninstaller, gibt sofort Exit Code 38 zurueck, der externe Uninstaller
                    # laeuft aber im Hintergrund weiter und wartet auf Benutzer-Bestaetigung.
                    if (-not $ok) {
                        $sync.Lines.Add("       Pruefe ob externer Uninstaller noch laeuft (bis zu 90 Sek.)...")
                        $stillInstalled = $true
                        $shortName = ($pkg.Id -split '\.')[-1]
                        for ($i = 0; $i -lt 45; $i++) {
                            Start-Sleep -Seconds 2
                            try {
                                $foundSomewhere = $false
                                # 1. winget list mit ID-Match
                                $check = & winget list --id $pkg.Id --exact 2>&1
                                $checkStr = ($check | Out-String)
                                if ($checkStr -notmatch "(?i)(No installed package|Keine installierten Pakete|kein installiertes Paket)") {
                                    if ($checkStr -match [regex]::Escape($pkg.Id)) { $foundSomewhere = $true }
                                }
                                # 2. MSIX/AppX-Check
                                if (-not $foundSomewhere -and $shortName) {
                                    $appxCheck = Get-AppxPackage "*$shortName*" -ErrorAction SilentlyContinue
                                    if ($appxCheck) { $foundSomewhere = $true }
                                }
                                # 3. ARP-Registry mit DisplayName
                                if (-not $foundSomewhere -and $pkg.Name) {
                                    $arpPaths = @(
                                        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
                                        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
                                        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
                                    )
                                    foreach ($arpRoot in $arpPaths) {
                                        if (-not (Test-Path $arpRoot)) { continue }
                                        try {
                                            $entries = Get-ChildItem $arpRoot -ErrorAction SilentlyContinue |
                                                Get-ItemProperty -ErrorAction SilentlyContinue |
                                                Where-Object { $_.DisplayName -and $_.DisplayName -ieq $pkg.Name }
                                            if ($entries) { $foundSomewhere = $true; break }
                                        } catch {}
                                    }
                                }
                                if (-not $foundSomewhere) {
                                    $stillInstalled = $false
                                    break
                                }
                            } catch {}
                            $dots = ('.' * (($i % 5) + 1))
                            if ($null -ne $sync.ProgressLineIdx -and $sync.ProgressLineIdx -lt $sync.Lines.Count) {
                                $sync.Lines[$sync.ProgressLineIdx] = "       Warte auf externen Uninstaller$dots"
                            }
                        }
                        if (-not $stillInstalled) {
                            $ok = $true
                            $sync.Lines.Add("[OK]   Paket erfolgreich deinstalliert (per externem Uninstaller)")
                        } else {
                            $sync.Lines.Add("       Paket ist nach 90 Sek. immer noch installiert – als Fehler gewertet")
                        }
                    }

                    # Inline-Balken finalisieren
                    if ($null -ne $sync.ProgressLineIdx) {
                        if ($ok) {
                            $sync.Lines[$sync.ProgressLineIdx] = "       [####################] 100%"
                        } else {
                            $sync.Lines.RemoveAt($sync.ProgressLineIdx)
                        }
                        $sync.ProgressLineIdx = $null
                    }
                    if ($ok) { $sync.Successful++ } else { $sync.Failed++ }
                }
            } catch {
                $sync.Lines.Add("[ERR]  Ausnahme: $_"); $sync.Failed++
            } finally {
                $sync.Done = $true
            }
        })
        [void]$ps.BeginInvoke()
        $sync.InstallTimer.Start()
    })

    $sync.BackButton.Add_Click({
        $sync.LogPanel.Visibility        = "Collapsed"
        $sync.SelectionPanel.Visibility  = "Visible"
        $sync.SelectAllButton.Visibility = "Visible"
        $sync.RescanButton.Visibility    = "Visible"
        $sync.UninstallButton.Visibility = "Visible"
        $sync.BackButton.Visibility      = "Collapsed"
        $sync.StatusText.Text            = "Programme fuer Deinstallation auswaehlen."
        & $sync.UpdateCount
    })

    # ── Suchfeld: filtert Programme + blendet leere Header aus ────────────────
    $sync.ApplySearchFilter = {
        $query = ""
        if ($null -ne $sync.SearchBox) { $query = $sync.SearchBox.Text.Trim().ToLower() }

        # Pro Header die Anzahl sichtbarer Items zaehlen
        $headerVisibility = @{}
        foreach ($entry in $sync.AllProgramItems) {
            $hay = ($entry.Name + " " + $entry.Id + " " + $entry.Desc).ToLower()
            $match = ($query -eq "") -or ($hay.Contains($query))
            $entry.Border.Visibility = if ($match) { "Visible" } else { "Collapsed" }
            $key = $entry.HeaderRef.GetHashCode()
            if (-not $headerVisibility.ContainsKey($key)) { $headerVisibility[$key] = @{ Header = $entry.HeaderRef; AnyVisible = $false } }
            if ($match) { $headerVisibility[$key].AnyVisible = $true }
        }

        # Header ausblenden, deren Items alle ausgeblendet sind
        foreach ($v in $headerVisibility.Values) {
            $v.Header.Visibility = if ($v.AnyVisible) { "Visible" } else { "Collapsed" }
        }
    }

    if ($null -ne $sync.SearchBox) {
        $sync.SearchBox.Add_TextChanged({ & $sync.ApplySearchFilter })
    }
    if ($null -ne $sync.SearchClearButton) {
        $sync.SearchClearButton.Add_Click({
            $sync.SearchBox.Text = ""
            & $sync.ApplySearchFilter
        })
    }

    $sync.CloseButton.Add_Click({ $sync.Window.Close() })

    # ── Startup-Timer startet den Scan sobald das Fenster geladen ist ─────────
    $startupTimer = New-Object System.Windows.Threading.DispatcherTimer
    $startupTimer.Interval = [TimeSpan]::FromMilliseconds(100)
    $sync.StartupTimer = $startupTimer
    $startupTimer.Add_Tick({
        $sync.StartupTimer.Stop()
        & $sync.StartScan
    })
    $startupTimer.Start()

    $window.Add_Closed({
    try { if ($sync.IconUITimer) { $sync.IconUITimer.Stop() } } catch {}
    try { if ($sync.IconRSPS) { $sync.IconRSPS.Stop() } } catch {}
    try { if ($sync.IconRSPS) { $sync.IconRSPS.Dispose() } } catch {}
    try { if ($sync.IconRS) { $sync.IconRS.Close() } } catch {}
    try { if ($sync.IconRS) { $sync.IconRS.Dispose() } } catch {}
})

[void]$window.ShowDialog()

} catch {
    $_ | Out-File -FilePath $logPath -Encoding UTF8
    [System.Windows.MessageBox]::Show(
        "Unerwarteter Fehler:`n`n$_`n`nDetails in:`n$logPath",
        "Uninstaller - Fehler", "OK", "Error") | Out-Null
}
