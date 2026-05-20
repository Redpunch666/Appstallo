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

$logPath = [System.IO.Path]::Combine($env:USERPROFILE, "WingetInstaller-debug.log")
try {

$allCategories = @(
    @{ Name = "Direktdownload"; Items = @() }
)

$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Software-Bibliothek"
    Width="1050" Height="700"
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

        <!-- MenuItem Style: Gutter entfernen, 3px roter Akzent links -->
        <Style TargetType="MenuItem">
            <Setter Property="OverridesDefaultStyle" Value="True"/>
            <Setter Property="Background" Value="#1e1e1e"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="MenuItem">
                        <Border x:Name="Bd" BorderThickness="3,0,0,0" BorderBrush="#a93226" Margin="-1,0,0,0"
                                Background="{TemplateBinding Background}" Padding="10,7,22,7">
                            <ContentPresenter ContentSource="Header" RecognizesAccessKey="True"
                                              VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#a93226"/>
                                <Setter TargetName="Bd" Property="BorderBrush" Value="#a93226"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
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
            <Grid Margin="22,0,20,0">
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center" HorizontalAlignment="Left">
                    <Border Width="4" Height="30" Background="#a93226" Margin="0,0,12,0"/>
                    <StackPanel>
                        <TextBlock Text="SOFTWARE-BIBLIOTHEK" Foreground="White" FontSize="15" FontWeight="Bold"/>
                        <TextBlock x:Name="StatusText" Foreground="#888888" FontSize="11" Margin="0,3,0,0"
                                   Text="Installierte Software wird geprueft..."/>
                    </StackPanel>
                </StackPanel>
                <Border x:Name="PresetBadge" CornerRadius="4"
                        Padding="14,7" VerticalAlignment="Center" HorizontalAlignment="Right"
                        Cursor="Hand">
                    <Border.Background>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                            <GradientStop Color="#F1C40F" Offset="0"/>
                            <GradientStop Color="#C0392B" Offset="1"/>
                        </LinearGradientBrush>
                    </Border.Background>
                    <TextBlock Foreground="#000000" FontSize="13" FontWeight="ExtraBold"
                               Text="Gratis Presets zum Import über Extras ▾  |  APPSTALLO.NET &#x2197;"/>
                </Border>
            </Grid>
        </Border>

        <!-- SCAN PANEL -->
        <Border x:Name="ScanPanel" Grid.Row="1" Background="#0d0d0d">
            <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                <ProgressBar Width="320" Height="3" IsIndeterminate="True"
                             Foreground="#a93226" Background="#252525"
                             BorderThickness="0" Margin="0,0,0,20"/>
                <TextBlock Foreground="#777777" FontSize="13" HorizontalAlignment="Center"
                           Text="Installierte Software wird geprueft..."/>
                <TextBlock x:Name="ScanSubText" Text="" Foreground="#777777"
                           FontSize="11" HorizontalAlignment="Center" Margin="0,8,0,0"/>
            </StackPanel>
        </Border>

        <!-- SELECTION PANEL -->
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

        <!-- LOG PANEL -->
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

        <!-- FOOTER -->
        <Border Grid.Row="2" Background="#0e0e0e" Margin="0,10,0,0">
            <Grid Margin="20,0">
                <TextBlock x:Name="CountText"
                           Text="Keine Programme ausgewaehlt"
                           Foreground="#888888" FontSize="12"
                           VerticalAlignment="Center" HorizontalAlignment="Left"/>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <Button x:Name="ExtrasButton" Content="Extras ▾"
                            Background="#2a2a2a" Foreground="#aaaaaa"
                            BorderThickness="0" Padding="14,8" FontSize="11"
                            Margin="0,0,12,0" Cursor="Hand"/>
                    <Button x:Name="SelectAllButton" Content="Alle auswaehlen"
                            Background="#2a2a2a" Foreground="#aaaaaa"
                            BorderThickness="0" Padding="14,8" FontSize="12"
                            Margin="0,0,8,0" Cursor="Hand" Visibility="Collapsed"/>
                    <Button x:Name="BackButton" Content="Zurueck zur Auswahl"
                            Background="#2a2a2a" Foreground="#aaaaaa"
                            BorderThickness="0" Padding="14,8" FontSize="12"
                            Margin="0,0,8,0" Cursor="Hand" Visibility="Collapsed"/>
                    <Button x:Name="InstallButton" Content="Installieren"
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
    if ($null -eq $window) {
        throw "XAML-Fenster konnte nicht erstellt werden (window ist null)."
    }

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
            try {
                $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
                [WinIconHelper]::SendMessage($hwnd, [WinIconHelper]::WM_SETICON, [WinIconHelper]::ICON_BIG,   $hIcon) | Out-Null
                [WinIconHelper]::SendMessage($hwnd, [WinIconHelper]::WM_SETICON, [WinIconHelper]::ICON_SMALL, $hIcon) | Out-Null
            try { Set-AppstalloRelaunchProperties -Hwnd $hwnd -Module ([string]$env:APPSTALLO_MODULE) } catch {}
                # Dunkle Titelleiste erzwingen (Windows 10 1809+ / Windows 11)
                $val = [int]1
                [DwmHelper]::DwmSetWindowAttribute($hwnd, [DwmHelper]::DWMWA_USE_IMMERSIVE_DARK_MODE, [ref]$val, 4)
            } catch {}
        }.GetNewClosure())
    } catch {}

    $sync = [hashtable]::Synchronized(@{
        Window          = $window
        StatusText        = $window.FindName("StatusText")
        SearchBox         = $window.FindName("SearchBox")
        SearchClearButton = $window.FindName("SearchClearButton")
        AllProgramItems   = [System.Collections.Generic.List[object]]::new()
        CustomCatalogPath   = "$env:LOCALAPPDATA\Appstallo\custom-catalog.json"
        CustomAssignPath    = "$env:LOCALAPPDATA\Appstallo\custom-assignments.json"
        CustomCatNamesPath  = "$env:LOCALAPPDATA\Appstallo\custom-catnames.json"
        CustomAssignments   = [System.Collections.Generic.Dictionary[string,string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        CustomCatNames      = [System.Collections.Generic.List[string]]::new()
        ScanSubText     = $window.FindName("ScanSubText")
        ScanPanel       = $window.FindName("ScanPanel")
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
        ExtrasButton    = $window.FindName("ExtrasButton")
        BackButton      = $window.FindName("BackButton")
        InstallButton   = $window.FindName("InstallButton")
        CloseButton     = $window.FindName("CloseButton")
        # Kategoriedaten
        AllCategories   = $allCategories
        # Tracking
        InstalledIds      = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        InstalledVersions = [System.Collections.Generic.Dictionary[string,string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        InstalledNames    = [System.Collections.Generic.Dictionary[string,string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        AvailableVersions = [System.Collections.Generic.Dictionary[string,string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        AvailVersionsCache = "$env:LOCALAPPDATA\Appstallo\available-versions.json"
        DescCachePath      = "$env:LOCALAPPDATA\Appstallo\descriptions-cache.json"
        DescCache          = [System.Collections.Generic.Dictionary[string,string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        AvailVersionsRefreshed = $false
        SelectedIds     = [System.Collections.Generic.HashSet[string]]::new()
        AllEntries      = [System.Collections.Generic.List[hashtable]]::new()
        # Farben
        ClrWhite        = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#e0e0e0"))
        ClrGray         = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#888888"))
        ClrRed          = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#a93226"))
        ClrGreen        = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#4ade80"))
        ClrGreenDim     = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#2a5a2a"))
        ClrSep          = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#222222"))
        ClrHover        = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#1c1c1c"))
        ClrTransp       = [System.Windows.Media.Brushes]::Transparent
        ClrDark         = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#232323"))
        ClrMuted        = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#888888"))
        # Zustand
        ScanDone        = $false
        Done            = $false
        Successful      = 0
        BiboInstallDone = $false
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


    # ── UpdateCount ───────────────────────────────────────────────────────────
    $sync.UpdateCount = {
        $count = $sync.SelectedIds.Count
        if ($count -eq 0) {
            $sync.CountText.Text = "Keine Programme ausgewaehlt"
            $sync.InstallButton.IsEnabled = $false
        } else {
            $sync.CountText.Text = "$count Programm(e) ausgewaehlt"
            $sync.InstallButton.IsEnabled = $true
        }
    }


    # ── Beschreibungs-Cache laden ──────────────────────────────────────────
    $sync.LoadDescCache = {
        try {
            if (Test-Path $sync.DescCachePath) {
                $json = Get-Content $sync.DescCachePath -Raw -Encoding UTF8 | ConvertFrom-Json
                foreach ($prop in $json.PSObject.Properties) {
                    $sync.DescCache[$prop.Name] = $prop.Value
                }
            }
        } catch {}
    }

    # ── Beschreibungs-Cache speichern ─────────────────────────────────────
    $sync.SaveDescCache = {
        try {
            foreach ($cat in $sync.AllCategories) {
                foreach ($item in $cat.Items) {
                    if ($item.Id -and $item.Id -notlike "URL:*" -and $item.Desc -and
                        $item.Desc -ne "Auf diesem System installiert" -and
                        $item.Desc -ne "Verschoben vom Benutzer" -and
                        $item.Desc -ne $item.Name) {
                        $sync.DescCache[$item.Id] = $item.Desc
                    }
                }
            }
            $dir = Split-Path $sync.DescCachePath -Parent
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $ht = @{}
            foreach ($key in $sync.DescCache.Keys) { $ht[$key] = $sync.DescCache[$key] }
            $ht | ConvertTo-Json -Depth 1 | Set-Content -Path $sync.DescCachePath -Encoding UTF8
        } catch {}
    }

    & $sync.LoadDescCache

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

    '9N1B9JWB3M35' = 'wispr'
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


    # Installierte Programme automatisch in Kategorien einsortieren
    $sync.AddInstalledToLibrary = {
        $existingIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($cat in $sync.AllCategories) {
            foreach ($item in $cat.Items) { [void]$existingIds.Add($item.Id) }
        }

        # Kategorien & Keyword-Mapping werden ZENTRAL in Appstallo.Common.ps1
        # gepflegt (Get-AppstalloCategoryMap / Get-AppstalloCategoryFor).
        # So koennen Bibliothek und Uninstaller nicht auseinanderlaufen.

        foreach ($instId in $sync.InstalledIds) {
            if ($existingIds.Contains($instId)) { continue }
            if ($instId -match 'ARP\\') { continue }
            $instName = if ($sync.InstalledNames.ContainsKey($instId)) { $sync.InstalledNames[$instId] } else { ($instId -split '\.')[-1] }
            $instVer  = if ($sync.InstalledVersions.ContainsKey($instId)) { $sync.InstalledVersions[$instId] } else { "" }
            # Hotfix 18: PWA-Kennzeichnung im Display-Name
            if ($instId -match "(?i)(FFPWA|MSEDGE.?PWA|^ARP\\.*PWA)" -and $instName -notmatch "\[PWA\]") {
                $instName = "$instName [PWA]"
            }
            $cachedDesc = if ($sync.DescCache.ContainsKey($instId)) { $sync.DescCache[$instId] } else { "Auf diesem System installiert" }
            $itemEntry = @{ Name = $instName; Id = $instId; Desc = $cachedDesc }

            # 1. Benutzerdefinierte Zuordnung pruefen (hat Vorrang)
            $assignedCat = $null
            if ($sync.CustomAssignments.ContainsKey($instId)) {
                $assignedCat = $sync.CustomAssignments[$instId]
            }

            # 2. Zentrale Keyword-Kategorisierung als Fallback
            if (-not $assignedCat) {
                $assignedCat = Get-AppstalloCategoryFor -Name $instName -Id $instId
            }

            $targetCat = $sync.AllCategories | Where-Object { $_.Name -eq $assignedCat }
            if ($targetCat) {
                $targetCat.Items += $itemEntry
            } else {
                $sync.AllCategories += @{ Name = $assignedCat; Items = @($itemEntry) }
            }
        }

        # Alphabetisch sortieren innerhalb jeder Kategorie
        foreach ($cat in $sync.AllCategories) {
            $cat.Items = @($cat.Items | Sort-Object { $_.Name })
        }

        # Kategorien alphabetisch sortieren, "Sonstige Programme" und "Direktdownload" ans Ende
        $normalCats   = @($sync.AllCategories | Where-Object { $_.Name -ne "Direktdownload" -and $_.Name -ne "Sonstige Programme" } | Sort-Object { $_.Name })
        $sonstigeCat  = @($sync.AllCategories | Where-Object { $_.Name -eq "Sonstige Programme" })
        $dlCat        = @($sync.AllCategories | Where-Object { $_.Name -eq "Direktdownload" })
        $sync.AllCategories = @($normalCats) + @($sonstigeCat) + @($dlCat)
    }

        # ── BuildUI – baut Programmliste mit Installiert-Kennzeichnung ────────────
    # Benutzerdefinierte Eintraege laden
    # Benutzerdefinierte Direktlinks laden
    $customLinksPath = "$env:LOCALAPPDATA\Appstallo\custom-links.json"
    $sync.CustomLinksPath = $customLinksPath
    try {
        if (Test-Path $customLinksPath) {
            $linksRaw = Get-Content $customLinksPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($linksRaw) {
                $dlCat = $sync.AllCategories | Where-Object { $_.Name -eq "Direktdownload" }
                if ($dlCat) {
                    foreach ($lnk in $linksRaw) {
                        if ($true) {
                            $dlCat.Items += @{ Name = $lnk.Name; Id = $lnk.Id; Desc = $lnk.Desc }
                        }
                    }
                }
            }
        }
    } catch {}

    # ── Hilfsfunktion: CustomAssignments robust einlesen ─────────────────────
    # Unterstuetzt sowohl PSCustomObject (Properties) als auch Array von {Key,Value}
    $sync.MergeAssignFromImport = {
        param($imp)
        if (-not $imp) { return }
        # Variante 1: PSCustomObject mit benannten Properties
        $props = $null
        try { $props = $imp.PSObject.Properties } catch {}
        if ($props -and ($props | Where-Object { $_.Name -and $_.Name -ne "Count" -and $_.Name -ne "Length" })) {
            foreach ($p in $props) {
                if ($p.Name -ne "Count" -and $p.Name -ne "Length" -and $p.Value -is [string]) {
                    $sync.CustomAssignments[$p.Name] = $p.Value
                }
            }
        }
        # Variante 2: Array von {Key, Value}-Paaren (von Dictionary-Serialisierung)
        if ($imp -is [System.Collections.IEnumerable] -and -not ($imp -is [string])) {
            foreach ($entry in $imp) {
                if ($entry -and $entry.PSObject.Properties.Name -contains "Key" -and $entry.PSObject.Properties.Name -contains "Value") {
                    $sync.CustomAssignments[[string]$entry.Key] = [string]$entry.Value
                }
            }
        }
    }

        # Benutzerdefinierte Zuordnungen laden (verschobene Eintraege)
    try {
        if (Test-Path $sync.CustomAssignPath) {
            $aRaw = Get-Content $sync.CustomAssignPath -Raw -Encoding UTF8 | ConvertFrom-Json
            & $sync.MergeAssignFromImport $aRaw
        }
    } catch {}

    # Benutzerdefinierten Katalog laden
    $customCatalogPath = "$env:LOCALAPPDATA\Appstallo\custom-catalog.json"
    $customPrograms = @()
    try {
        if (Test-Path $customCatalogPath) {
            $customRaw = Get-Content $customCatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($customRaw) { $customPrograms = @($customRaw) }
        }
    } catch {}
    if ($customPrograms.Count -gt 0) {
        # Kategorien & Keyword-Mapping zentral aus Appstallo.Common.ps1.
        foreach ($cp in $customPrograms) {
            $itemEntry = @{ Name = $cp.Name; Id = $cp.Id; Desc = if ($cp.Desc) { $cp.Desc } else { $cp.Name } }
            # Benutzerdefinierte Zuordnung hat Vorrang
            $assignedCat = $null
            if ($sync.CustomAssignments.ContainsKey($cp.Id)) {
                $assignedCat = $sync.CustomAssignments[$cp.Id]
            }
            if (-not $assignedCat) {
                $assignedCat = Get-AppstalloCategoryFor -Name $cp.Name -Id $cp.Id
            }

            $targetCat = $sync.AllCategories | Where-Object { $_.Name -eq $assignedCat }
            if ($targetCat) {
                $existingIds = @($targetCat.Items | ForEach-Object { $_.Id })
                if ($cp.Id -notin $existingIds) { $targetCat.Items += $itemEntry }
            } else {
                $sync.AllCategories += @{ Name = $assignedCat; Items = @($itemEntry) }
            }
        }

        # Innerhalb jeder Kategorie alphabetisch sortieren
        foreach ($cat in $sync.AllCategories) {
            $cat.Items = @($cat.Items | Sort-Object { $_.Name })
        }
        # Kategorien alphabetisch, "Sonstige Programme" vorletzte, "Direktdownload" letzte
        $normalCats  = @($sync.AllCategories | Where-Object { $_.Name -ne "Direktdownload" -and $_.Name -ne "Sonstige Programme" } | Sort-Object { $_.Name })
        $sonstigeCat = @($sync.AllCategories | Where-Object { $_.Name -eq "Sonstige Programme" })
        $dlCat       = @($sync.AllCategories | Where-Object { $_.Name -eq "Direktdownload" })
        $sync.AllCategories = @($normalCats) + @($sonstigeCat) + @($dlCat)
    }

    # Benutzerdefinierte Kategorienamen laden
    try {
        if (Test-Path $sync.CustomCatNamesPath) {
            $cnRaw = Get-Content $sync.CustomCatNamesPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cnRaw) { foreach ($cn in $cnRaw) { [void]$sync.CustomCatNames.Add($cn) } }
        }
    } catch {}

    # Benutzerdefinierte Kategorien als leere Kategorien anlegen (falls noch nicht vorhanden)
    foreach ($ucn in $sync.CustomCatNames) {
        $existing = $sync.AllCategories | Where-Object { $_.Name -eq $ucn }
        if (-not $existing) {
            $sync.AllCategories += @{ Name = $ucn; Items = @() }
        }
    }

    $sync.BuildUI = {
        # Sortierung: Programme alphabetisch, Kategorien alphabetisch, Sonstige+Direktdownload ans Ende
        foreach ($cat in $sync.AllCategories) {
            $cat.Items = @($cat.Items | Sort-Object { $_.Name })
        }
        $normalCats  = @($sync.AllCategories | Where-Object { $_.Name -ne "Direktdownload" -and $_.Name -ne "Sonstige Programme" } | Sort-Object { $_.Name })
        $sonstigeCat = @($sync.AllCategories | Where-Object { $_.Name -eq "Sonstige Programme" })
        $dlCat       = @($sync.AllCategories | Where-Object { $_.Name -eq "Direktdownload" })
        $sync.AllCategories = @($normalCats) + @($sonstigeCat) + @($dlCat)

        $sync.ProgramList.Children.Clear()
        $sync.AllEntries.Clear()
        $sync.AllProgramItems.Clear()
        $sync.SelectedIds.Clear()
        $sync.AllSelected = $false
        $sync.SelectAllButton.Content = "Alle auswaehlen"

        foreach ($cat in $sync.AllCategories) {
            # Leere Kategorien nicht rendern – außer Direktdownload (zeigt immer den "+ Link" Button)
            $isCustomCat = $sync.CustomCatNames.Contains($cat.Name)
            if ($cat.Items.Count -eq 0 -and $cat.Name -ne "Direktdownload" -and -not $isCustomCat) { continue }

            $catPanel = New-Object System.Windows.Controls.StackPanel
            $catPanel.Margin = [System.Windows.Thickness]::new(0,12,0,4)

            $hdrGrid = New-Object System.Windows.Controls.Grid
            $hdrGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
            $hdrGrid.ColumnDefinitions[0].Width = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
            $hdrGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
            $hdrGrid.ColumnDefinitions[1].Width = [System.Windows.GridLength]::Auto

            $hdrText = New-Object System.Windows.Controls.TextBlock
            $hdrText.Text = $cat.Name; $hdrText.Foreground = $sync.ClrRed
            $hdrText.FontSize = 12; $hdrText.FontWeight = [System.Windows.FontWeights]::Bold
            $hdrText.VerticalAlignment = "Center"
            [System.Windows.Controls.Grid]::SetColumn($hdrText, 0)
            [void]$hdrGrid.Children.Add($hdrText)

            $toggleBtn = New-Object System.Windows.Controls.Button
            $toggleBtn.Content = "Alle"; $toggleBtn.Background = $sync.ClrDark
            $toggleBtn.Foreground = $sync.ClrMuted
            $toggleBtn.BorderThickness = [System.Windows.Thickness]::new(0)
            $toggleBtn.Padding = [System.Windows.Thickness]::new(10,3,10,3)
            $toggleBtn.FontSize = 11; $toggleBtn.Cursor = [System.Windows.Input.Cursors]::Hand
            [System.Windows.Controls.Grid]::SetColumn($toggleBtn, 1)
            [void]$hdrGrid.Children.Add($toggleBtn)

            # Lösch-Button für leere benutzerdefinierte Kategorien
            if ($cat.Items.Count -eq 0 -and $sync.CustomCatNames.Contains($cat.Name)) {
                $hdrGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
                $hdrGrid.ColumnDefinitions[2].Width = [System.Windows.GridLength]::Auto

                $catDelBtn = New-Object System.Windows.Controls.Button
                $catDelBtn.Content = [char]0xE74D
                $catDelBtn.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe MDL2 Assets")
                $catDelBtn.FontSize = 10
                $catDelBtn.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#2a2a2a"))
                $catDelBtn.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#888888"))
                $catDelBtn.BorderThickness = [System.Windows.Thickness]::new(0)
                $catDelBtn.Padding = [System.Windows.Thickness]::new(6,2,6,2)
                $catDelBtn.Margin = [System.Windows.Thickness]::new(4,0,0,0)
                $catDelBtn.Cursor = [System.Windows.Input.Cursors]::Hand
                $catDelBtn.ToolTip = "Kategorie loeschen"
                $catDelBtn.Tag = $cat.Name
                $catDelBtn.Add_Click({
                    param($sender,$ea)
                    $catToDelete = $sender.Tag
                    $result = [System.Windows.MessageBox]::Show(
                        "Kategorie `"$catToDelete`" wirklich loeschen?",
                        "Kategorie loeschen", "YesNo", "Question")
                    if ($result -eq "Yes") {
                        [void]$sync.CustomCatNames.Remove($catToDelete)
                        try {
                            $dir = Split-Path $sync.CustomCatNamesPath -Parent
                            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                            if ($sync.CustomCatNames.Count -gt 0) {
                                @($sync.CustomCatNames) | ConvertTo-Json | Set-Content -Path $sync.CustomCatNamesPath -Encoding UTF8
                            } elseif (Test-Path $sync.CustomCatNamesPath) {
                                Remove-Item $sync.CustomCatNamesPath -Force
                            }
                        } catch {}
                        $sync.AllCategories = @($sync.AllCategories | Where-Object { $_.Name -ne $catToDelete })
                        # Zuordnungen zu dieser Kategorie entfernen
                        $keysToRemove = @($sync.CustomAssignments.Keys | Where-Object { $sync.CustomAssignments[$_] -eq $catToDelete })
                        foreach ($k in $keysToRemove) { [void]$sync.CustomAssignments.Remove($k) }
                        if ($keysToRemove.Count -gt 0) {
                            try {
                                $obj = [PSCustomObject]@{}
                                foreach ($k in $sync.CustomAssignments.Keys) { $obj | Add-Member -NotePropertyName $k -NotePropertyValue $sync.CustomAssignments[$k] }
                                $obj | ConvertTo-Json -Depth 5 | Set-Content -Path $sync.CustomAssignPath -Encoding UTF8
                            } catch {}
                        }
                        & $sync.BuildUI
                        & $sync.UpdateCount
                    }
                })
                [System.Windows.Controls.Grid]::SetColumn($catDelBtn, 2)
                [void]$hdrGrid.Children.Add($catDelBtn)
            }

            [void]$catPanel.Children.Add($hdrGrid)

            $sep = New-Object System.Windows.Controls.Separator
            $sep.Background = $sync.ClrSep
            $sep.Margin = [System.Windows.Thickness]::new(0,5,0,2)
            [void]$catPanel.Children.Add($sep)

            $catBoxes = [System.Collections.Generic.List[System.Windows.Controls.CheckBox]]::new()

            foreach ($item in $cat.Items) {
                $idCopy      = $item.Id
                $nameCopy    = $item.Name
                $isInstalled = ($idCopy -notlike "URL:*") -and $sync.InstalledIds.Contains($idCopy)

                $itemBorder = New-Object System.Windows.Controls.Border
                $itemBorder.Background = $sync.ClrTransp
                $itemBorder.Padding = [System.Windows.Thickness]::new(4,5,4,5)
                $itemBorder.Margin  = [System.Windows.Thickness]::new(0,1,0,0)

                # Spalten: [CB] | [Name+Badge] | [Desc]
                $itemGrid = New-Object System.Windows.Controls.Grid
                $itemGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
                $itemGrid.ColumnDefinitions[0].Width = [System.Windows.GridLength]::Auto
                $itemGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
                $itemGrid.ColumnDefinitions[1].Width = [System.Windows.GridLength]::new(280)
                $itemGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
                $itemGrid.ColumnDefinitions[2].Width = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
                $itemGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
                $itemGrid.ColumnDefinitions[3].Width = [System.Windows.GridLength]::Auto
                $itemGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
                $itemGrid.ColumnDefinitions[4].Width = [System.Windows.GridLength]::Auto
                $itemGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
                $itemGrid.ColumnDefinitions[5].Width = [System.Windows.GridLength]::Auto

                $cb = New-Object System.Windows.Controls.CheckBox
                $cb.VerticalAlignment = "Center"
                $cb.Margin = [System.Windows.Thickness]::new(2,0,10,0)
                [System.Windows.Controls.Grid]::SetColumn($cb, 0); [void]$itemGrid.Children.Add($cb)

                # Name + Icon + optionaler "Installiert"-Badge in einer horizontalen StackPanel
                $namePanel = New-Object System.Windows.Controls.StackPanel
                $namePanel.Orientation = "Horizontal"
                $namePanel.VerticalAlignment = "Center"

                $iconImg = New-Object System.Windows.Controls.Image
                $iconImg.Width = 24; $iconImg.Height = 24
                $iconImg.VerticalAlignment = "Center"
                $iconImg.Margin = [System.Windows.Thickness]::new(0,0,8,0)
                $iconImg.SnapsToDevicePixels = $true
                [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($iconImg, [System.Windows.Media.BitmapScalingMode]::HighQuality)
                if ($item.Id -like "URL:*") {
                    $iconImg.Source = (& $sync.MakeInitialIcon $item.Name)
                } else {
                    & $sync.RequestIcon $item.Id $item.Name $iconImg
                }
                [void]$namePanel.Children.Add($iconImg)

                $nameBlk = New-Object System.Windows.Controls.TextBlock
                $nameBlk.Text = $item.Name
                $nameBlk.Foreground = if ($isInstalled) { $sync.ClrGray } else { $sync.ClrWhite }
                $nameBlk.FontSize = 13
                $nameBlk.VerticalAlignment = "Center"
                [void]$namePanel.Children.Add($nameBlk)

                $availBadge = $null
                if ($isInstalled) {
                    $badge = New-Object System.Windows.Controls.Border
                    $badge.Background   = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#0d2a0d"))
                    $badge.BorderBrush  = $sync.ClrGreenDim
                    $badge.BorderThickness = [System.Windows.Thickness]::new(1)
                    $badge.CornerRadius = [System.Windows.CornerRadius]::new(3)
                    $badge.Padding      = [System.Windows.Thickness]::new(5,1,5,1)
                    $badge.Margin       = [System.Windows.Thickness]::new(7,0,0,0)
                    $badge.VerticalAlignment = "Center"
                    $badgeText = New-Object System.Windows.Controls.TextBlock
                    # Version aus InstalledVersions auslesen wenn vorhanden
                    $instVer = $null
                    if ($sync.InstalledVersions.ContainsKey($item.Id)) { $instVer = $sync.InstalledVersions[$item.Id] }
                    if ($instVer) {
                        $badgeText.Text   = "Installiert v$instVer"
                    } else {
                        $badgeText.Text   = "Installiert"
                    }
                    $badgeText.Foreground = $sync.ClrGreen
                    $badgeText.FontSize   = 10
                    $badge.Child = $badgeText
                    [void]$namePanel.Children.Add($badge)
                } elseif ($idCopy -notlike "URL:*") {
                    # Nicht installiert: Platzhalter-Badge fuer "Verfuegbar v..."
                    # wird vom Hintergrund-Loader spaeter befuellt, sonst bleibt es unsichtbar
                    $availBadge = New-Object System.Windows.Controls.Border
                    $availBadge.Background   = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#2a1a08"))
                    $availBadge.BorderBrush  = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#5a3a1a"))
                    $availBadge.BorderThickness = [System.Windows.Thickness]::new(1)
                    $availBadge.CornerRadius = [System.Windows.CornerRadius]::new(3)
                    $availBadge.Padding      = [System.Windows.Thickness]::new(5,1,5,1)
                    $availBadge.Margin       = [System.Windows.Thickness]::new(7,0,0,0)
                    $availBadge.VerticalAlignment = "Center"
                    $availBadge.Visibility   = "Collapsed"
                    $availBadgeText = New-Object System.Windows.Controls.TextBlock
                    $availBadgeText.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#e89043"))
                    $availBadgeText.FontSize   = 10
                    $availBadge.Child = $availBadgeText
                    [void]$namePanel.Children.Add($availBadge)

                    # Wenn Version bereits im Cache, sofort anzeigen
                    if ($sync.AvailableVersions.ContainsKey($idCopy)) {
                        $availBadgeText.Text = "Verfuegbar v" + $sync.AvailableVersions[$idCopy]
                        $availBadge.Visibility = "Visible"
                    }
                }

                [System.Windows.Controls.Grid]::SetColumn($namePanel, 1)
                [void]$itemGrid.Children.Add($namePanel)

                $descBlk = New-Object System.Windows.Controls.TextBlock
                $descBlk.Text = ($item.Desc -replace '\r?\n', ' ')
                $descBlk.Foreground = $sync.ClrGray
                $descBlk.FontSize = 11; $descBlk.VerticalAlignment = "Center"
                $descBlk.TextTrimming = "CharacterEllipsis"
                $descBlk.Margin = [System.Windows.Thickness]::new(8,0,0,0)
                [System.Windows.Controls.Grid]::SetColumn($descBlk, 2)
                [void]$itemGrid.Children.Add($descBlk)

                $itemBorder.Child = $itemGrid

                $bRef = $itemBorder
                $hov  = $sync.ClrHover
                $trp  = $sync.ClrTransp
                $itemBorder.Add_MouseEnter({ $bRef.Background = $hov }.GetNewClosure())
                $itemBorder.Add_MouseLeave({ $bRef.Background = $trp }.GetNewClosure())

                $cbRef = $cb
                $itemBorder.Add_MouseLeftButtonDown({
                    param($s,$e)
                    if ($e.OriginalSource -isnot [System.Windows.Controls.CheckBox] -and
                        $e.OriginalSource -isnot [System.Windows.Controls.Primitives.ToggleButton]) {
                        $cbRef.IsChecked = -not $cbRef.IsChecked; $e.Handled = $true
                    }
                }.GetNewClosure())

                $cb.Add_Checked({
                    [void]$sync.SelectedIds.Add($idCopy); & $sync.UpdateCount
                }.GetNewClosure())
                $cb.Add_Unchecked({
                    [void]$sync.SelectedIds.Remove($idCopy); & $sync.UpdateCount
                }.GetNewClosure())

                [void]$catBoxes.Add($cb)
                [void]$sync.AllEntries.Add(@{ CB = $cb; Id = $idCopy; Name = $nameCopy })
                # Item fuer Suchfilter und Detail-Popup registrieren
                [void]$sync.AllProgramItems.Add(@{
                    Border        = $itemBorder
                    CatPanel      = $catPanel
                    Name          = $item.Name
                    Id            = $item.Id
                    Desc          = $item.Desc
                    AvailBadge    = $availBadge
                    IsInstalled   = $isInstalled
                })

                # Detail-Popup bei Doppelklick auf Item
                $popupName = $item.Name
                $popupId   = $item.Id
                $popupDesc = $item.Desc
                $popupVer  = if ($sync.InstalledVersions.ContainsKey($item.Id)) { $sync.InstalledVersions[$item.Id] } else { $null }
                $popupItemRef = $item

                # Info-Button ("i") am rechten Rand
                $infoBtn = New-Object System.Windows.Controls.Border
                $infoBtn.Width  = 22; $infoBtn.Height = 22
                $infoBtn.CornerRadius    = [System.Windows.CornerRadius]::new(11)
                $infoBtn.Background      = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#2a2a2a"))
                $infoBtn.BorderBrush     = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#444444"))
                $infoBtn.BorderThickness = [System.Windows.Thickness]::new(1)
                $infoBtn.Cursor = [System.Windows.Input.Cursors]::Hand
                $infoBtn.ToolTip = "Details anzeigen"
                $infoBtn.VerticalAlignment   = "Center"
                $infoBtn.HorizontalAlignment = "Center"
                $infoBtn.Margin = [System.Windows.Thickness]::new(6,0,4,0)
                $infoTxt = New-Object System.Windows.Controls.TextBlock
                $infoTxt.Text = "i"
                $infoTxt.FontSize   = 12; $infoTxt.FontStyle = "Italic"; $infoTxt.FontWeight = "Bold"
                $infoTxt.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#888888"))
                $infoTxt.HorizontalAlignment = "Center"; $infoTxt.VerticalAlignment = "Center"
                $infoBtn.Child = $infoTxt
                [System.Windows.Controls.Grid]::SetColumn($infoBtn, 3)
                [void]$itemGrid.Children.Add($infoBtn)

                # Detail-Popup programmatisch (kein XAML-Template, keine Sonderzeichen-Probleme)
                $infoBtn.Add_MouseLeftButtonDown({
                    param($s,$e)
                    # Aktuellen Desc-Wert lesen (koennte durch Listenausgabe aktualisiert worden sein)
                    $popupDesc = $popupItemRef.Desc
                    # Beschreibung per winget show nachladen falls nur Platzhalter
                    if ($popupId -notlike "URL:*" -and ($popupDesc -eq "Auf diesem System installiert" -or $popupDesc -eq "Verschoben vom Benutzer" -or $popupDesc -eq $popupName -or -not $popupDesc)) {
                        try {
                            $showOut = & winget show --id $popupId --accept-source-agreements 2>&1 | Out-String
                            $descMatch = [regex]::Match($showOut, '(?:Beschreibung|Description)\s*:\s*(.+?)(?:\r?\n\S|\r?\n\r?\n)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
                            if ($descMatch.Success) {
                                $fetchedDesc = $descMatch.Groups[1].Value.Trim()
                                if ($fetchedDesc.Length -gt 200) { $fetchedDesc = $fetchedDesc.Substring(0, 200) + "..." }
                                $popupDesc = $fetchedDesc
                                $popupItemRef.Desc = $fetchedDesc
                                $sync.DescCache[$popupId] = $fetchedDesc
                            } else {
                                $monikerMatch = [regex]::Match($showOut, '(?:Moniker|Kurzname)\s*:\s*(.+)')
                                if ($monikerMatch.Success) {
                                    $popupDesc = $monikerMatch.Groups[1].Value.Trim()
                                    $popupItemRef.Desc = $popupDesc
                                    $sync.DescCache[$popupId] = $popupDesc
                                }
                            }
                        } catch {}
                        & $sync.SaveDescCache
                    }
                    $publisher = if ($popupId -like "URL:*") { "Direkt-Download" } elseif ($popupId -match "^([^\.]+)\.") { $Matches[1] } else { "Unbekannt" }

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

                    # Titel
                    $t = New-Object System.Windows.Controls.TextBlock
                    $t.Text = $popupName; $t.FontSize = 16; $t.FontWeight = "Bold"
                    $t.Foreground = [System.Windows.Media.Brushes]::White
                    $t.Margin = [System.Windows.Thickness]::new(0,0,0,14)
                    [void]$stack.Children.Add($t)

                    # Helper-Funktion fuer Label + Wert
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
                    if ($popupId -like "URL:*") {
                        & $addField "URL" ($popupId.Substring(4)) "#e0e0e0"
                    } else {
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
                    }
                    if ($popupVer) { & $addField "Installierte Version" $popupVer "#4ade80" }
                    & $addField "Beschreibung" $popupDesc "#cccccc"

                    # Schliessen-Button
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

                # Verschieben-Button (Pfeil) – verschiebt Eintrag in andere Kategorie
                $moveBtn = New-Object System.Windows.Controls.Border
                $moveBtn.Width  = 22; $moveBtn.Height = 22
                $moveBtn.CornerRadius    = [System.Windows.CornerRadius]::new(11)
                $moveBtn.Background      = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#2a2a2a"))
                $moveBtn.BorderBrush     = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#333333"))
                $moveBtn.BorderThickness = [System.Windows.Thickness]::new(1)
                $moveBtn.Cursor = [System.Windows.Input.Cursors]::Hand
                $moveBtn.ToolTip = "In andere Kategorie verschieben"
                $moveBtn.VerticalAlignment   = "Center"
                $moveBtn.HorizontalAlignment = "Center"
                $moveBtn.Margin = [System.Windows.Thickness]::new(2,0,2,0)
                $moveTxt = New-Object System.Windows.Controls.TextBlock
                $moveTxt.Text = [char]0xE8AB
                $moveTxt.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe MDL2 Assets")
                $moveTxt.FontSize   = 10
                $moveTxt.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#888888"))
                $moveTxt.HorizontalAlignment = "Center"; $moveTxt.VerticalAlignment = "Center"
                $moveBtn.Child = $moveTxt
                [System.Windows.Controls.Grid]::SetColumn($moveBtn, 4)
                [void]$itemGrid.Children.Add($moveBtn)

                $moveBtn.Tag = @{ Id = $item.Id; Name = $item.Name; Cat = $cat.Name }
                $moveBtn.Add_MouseLeftButtonDown({
                    param($s,$e)
                    $mInfo = $s.Tag
                    $mId   = $mInfo.Id
                    $mName = $mInfo.Name
                    $mCat  = $mInfo.Cat

                    $mvWin = New-Object System.Windows.Window
                    $mvWin.Title = "Verschieben nach..."
                    $mvWin.Width = 360; $mvWin.SizeToContent = "Height"
                    $mvWin.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#161616"))
                    $mvWin.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
                    $mvWin.WindowStartupLocation = "CenterOwner"; $mvWin.ResizeMode = "NoResize"
                    $mvWin.Owner = $sync.Window
                    if ($sync.AppIcon) { $mvWin.Icon = $sync.AppIcon }
                    try {
                        $mvH = (New-Object System.Windows.Interop.WindowInteropHelper($mvWin)).EnsureHandle()
                        $mvD = [int]1
                        [DwmHelper]::DwmSetWindowAttribute($mvH, [DwmHelper]::DWMWA_USE_IMMERSIVE_DARK_MODE, [ref]$mvD, 4)
                    } catch {}

                    $mvSt = New-Object System.Windows.Controls.StackPanel
                    $mvSt.Margin = [System.Windows.Thickness]::new(20,16,20,16)

                    $mvTitle = New-Object System.Windows.Controls.TextBlock
                    $mvTitle.Text = [string]::Format('"{0}" verschieben nach:', $mName)
                    $mvTitle.FontSize = 13; $mvTitle.FontWeight = "Bold"
                    $mvTitle.Foreground = [System.Windows.Media.Brushes]::White
                    $mvTitle.TextWrapping = "Wrap"
                    $mvTitle.Margin = [System.Windows.Thickness]::new(0,0,0,12)
                    [void]$mvSt.Children.Add($mvTitle)

                    $mvScroll = New-Object System.Windows.Controls.ScrollViewer
                    $mvScroll.MaxHeight = 400
                    $mvScroll.VerticalScrollBarVisibility = "Auto"
                    $mvList = New-Object System.Windows.Controls.StackPanel

                    foreach ($targetCat in $sync.AllCategories) {
                        if ($targetCat.Name -eq $mCat) { continue }
                        $catBtn = New-Object System.Windows.Controls.Button
                        $catBtn.Content = $targetCat.Name
                        $catBtn.Tag = @{ NewCat = $targetCat.Name; ItemId = $mId; ItemName = $mName; Win = $mvWin }
                        $catBtn.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#2a2a2a"))
                        $catBtn.Foreground = [System.Windows.Media.Brushes]::White
                        $catBtn.BorderThickness = [System.Windows.Thickness]::new(0)
                        $catBtn.Padding = [System.Windows.Thickness]::new(12,8,12,8)
                        $catBtn.Margin = [System.Windows.Thickness]::new(0,0,0,4)
                        $catBtn.HorizontalContentAlignment = "Left"
                        $catBtn.FontSize = 12; $catBtn.Cursor = [System.Windows.Input.Cursors]::Hand
                        $catBtn.Add_Click({
                            param($sender,$ea)
                            $t = $sender.Tag
                            # Zuordnung speichern
                            $sync.CustomAssignments[$t.ItemId] = $t.NewCat
                            try {
                                $dir = Split-Path $sync.CustomAssignPath -Parent
                                if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                                $obj = [PSCustomObject]@{}
                                foreach ($k in $sync.CustomAssignments.Keys) { $obj | Add-Member -NotePropertyName $k -NotePropertyValue $sync.CustomAssignments[$k] }
                                $obj | ConvertTo-Json -Depth 5 | Set-Content -Path $sync.CustomAssignPath -Encoding UTF8
                            } catch {}
                            # Eintrag verschieben
                            foreach ($c in $sync.AllCategories) {
                                $c.Items = @($c.Items | Where-Object { $_.Id -ne $t.ItemId })
                            }
                            $target = $sync.AllCategories | Where-Object { $_.Name -eq $t.NewCat }
                            if ($target) {
                                $mvDesc = if ($sync.DescCache.ContainsKey($t.ItemId)) { $sync.DescCache[$t.ItemId] } else { "Verschoben vom Benutzer" }
                $target.Items += @{ Name = $t.ItemName; Id = $t.ItemId; Desc = $mvDesc }
                            }
                            $t.Win.Close()
                            & $sync.BuildUI
                            & $sync.UpdateCount
                        })
                        [void]$mvList.Children.Add($catBtn)
                    }
                    $mvScroll.Content = $mvList
                    [void]$mvSt.Children.Add($mvScroll)

                    $mvCancel = New-Object System.Windows.Controls.Button
                    $mvCancel.Content = "Abbrechen"
                    $mvCancel.Padding = [System.Windows.Thickness]::new(16,8,16,8)
                    $mvCancel.HorizontalAlignment = "Right"
                    $mvCancel.Margin = [System.Windows.Thickness]::new(0,12,0,0)
                    $mvCancel.Tag = $mvWin
                    $mvCancel.Add_Click({ param($sender,$ea); $sender.Tag.Close() })
                    [void]$mvSt.Children.Add($mvCancel)

                    $mvWin.Content = $mvSt
                    & $sync.ApplyGoldStyle $mvWin
                    [void]$mvWin.ShowDialog()
                    $e.Handled = $true
                })

                # Loeschen-Button (X) rechts neben Info
                $delBtn = New-Object System.Windows.Controls.Border
                $delBtn.Width  = 22; $delBtn.Height = 22
                $delBtn.CornerRadius    = [System.Windows.CornerRadius]::new(11)
                $delBtn.Background      = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#2a2a2a"))
                $delBtn.BorderBrush     = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#444444"))
                $delBtn.BorderThickness = [System.Windows.Thickness]::new(1)
                $delBtn.Cursor = [System.Windows.Input.Cursors]::Hand
                $delBtn.ToolTip = "Aus Bibliothek entfernen"
                $delBtn.VerticalAlignment   = "Center"
                $delBtn.HorizontalAlignment = "Center"
                $delBtn.Margin = [System.Windows.Thickness]::new(2,0,4,0)
                $delTxt = New-Object System.Windows.Controls.TextBlock
                $delTxt.Text = [char]0xE74D
                $delTxt.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe MDL2 Assets")
                $delTxt.FontSize   = 11
                $delTxt.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#666666"))
                $delTxt.HorizontalAlignment = "Center"; $delTxt.VerticalAlignment = "Center"
                $delBtn.Child = $delTxt
                [System.Windows.Controls.Grid]::SetColumn($delBtn, 5)
                [void]$itemGrid.Children.Add($delBtn)

                $delItemId   = $item.Id
                $delItemName = $item.Name
                $delBorderRef = $itemBorder
                $delCatPanelRef = $catPanel
                $delBtn.Add_MouseLeftButtonDown({
                    param($s,$e)
                    # Bestaetigungs-Dialog
                    $cdWin = New-Object System.Windows.Window
                    $cdWin.Title = "Eintrag entfernen"
                    $cdWin.Width = 440; $cdWin.SizeToContent = "Height"
                    $cdWin.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#161616"))
                    $cdWin.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
                    $cdWin.WindowStartupLocation = "CenterOwner"; $cdWin.ResizeMode = "NoResize"
                    $cdWin.Owner = $sync.Window
                    if ($sync.AppIcon) { $cdWin.Icon = $sync.AppIcon }
                    try {
                        $cdH = (New-Object System.Windows.Interop.WindowInteropHelper($cdWin)).EnsureHandle()
                        $cdD = [int]1
                        [DwmHelper]::DwmSetWindowAttribute($cdH, [DwmHelper]::DWMWA_USE_IMMERSIVE_DARK_MODE, [ref]$cdD, 4)
                    } catch {}
                    $cdSt = New-Object System.Windows.Controls.StackPanel
                    $cdSt.Margin = [System.Windows.Thickness]::new(24,24,24,24)
                    $cdTx = New-Object System.Windows.Controls.TextBlock
                    $cdTx.Text = "`"$delItemName`" aus dem Katalog entfernen?`n`nDer Eintrag kann ueber den Programm-Browser jederzeit wieder hinzugefuegt werden."
                    $cdTx.FontSize = 13; $cdTx.TextWrapping = "Wrap"
                    $cdTx.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#e0e0e0"))
                    $cdTx.Margin = [System.Windows.Thickness]::new(0,0,0,20)
                    [void]$cdSt.Children.Add($cdTx)
                    $cdBp = New-Object System.Windows.Controls.StackPanel
                    $cdBp.Orientation = "Horizontal"; $cdBp.HorizontalAlignment = "Right"
                    $cdYes = New-Object System.Windows.Controls.Button
                    $cdYes.Content = "Entfernen"; $cdYes.Padding = [System.Windows.Thickness]::new(20,8,20,8)
                    $cdYes.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#a93226"))
                    $cdYes.Foreground = [System.Windows.Media.Brushes]::White
                    $cdYes.BorderThickness = [System.Windows.Thickness]::new(0)
                    $cdYes.FontSize = 12; $cdYes.Cursor = [System.Windows.Input.Cursors]::Hand
                    $cdYes.Margin = [System.Windows.Thickness]::new(0,0,8,0)
                    $cdNo = New-Object System.Windows.Controls.Button
                    $cdNo.Content = "Abbrechen"; $cdNo.Padding = [System.Windows.Thickness]::new(20,8,20,8)
                    $cdNo.FontSize = 12; $cdNo.Cursor = [System.Windows.Input.Cursors]::Hand
                    # Referenzen ueber Tag-Property uebergeben (vermeidet nested-closure-Problem in PS5)
                    $cdYes.Tag = @{ Id = $delItemId; Border = $delBorderRef }
                    $cdYes.Add_Click({
                        param($sender,$ea)
                        $info = $sender.Tag
                        $deleteId = $info.Id
                        $deleteBorder = $info.Border
                        # 1. Aus custom-catalog.json entfernen
                        try {
                            if (Test-Path $sync.CustomCatalogPath) {
                                $cc = Get-Content $sync.CustomCatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
                                $cc = @($cc | Where-Object { $_.Id -ne $deleteId })
                                if ($cc.Count -gt 0) {
                                    ConvertTo-Json -InputObject $cc -Depth 5 | Set-Content -Path $sync.CustomCatalogPath -Encoding UTF8
                                } else {
                                    Remove-Item $sync.CustomCatalogPath -Force
                                }
                            }
                        } catch {}
                        # 2. Aus custom-links.json entfernen (falls dort)
                        try {
                            if (Test-Path $sync.CustomLinksPath) {
                                $cl = Get-Content $sync.CustomLinksPath -Raw -Encoding UTF8 | ConvertFrom-Json
                                $cl = @($cl | Where-Object { $_.Id -ne $deleteId })
                                if ($cl.Count -gt 0) {
                                    ConvertTo-Json -InputObject $cl -Depth 5 | Set-Content -Path $sync.CustomLinksPath -Encoding UTF8
                                } else {
                                    Remove-Item $sync.CustomLinksPath -Force
                                }
                            }
                        } catch {}
                        # 3. UI: Eintrag dauerhaft entfernen (nicht nur ausblenden)
                        $parentPanel = [System.Windows.Media.VisualTreeHelper]::GetParent($deleteBorder)
                        if ($parentPanel -and $parentPanel -is [System.Windows.Controls.Panel]) {
                            $parentPanel.Children.Remove($deleteBorder)
                        } else {
                            $deleteBorder.Visibility = [System.Windows.Visibility]::Collapsed
                        }
                        # Aus AllProgramItems entfernen (damit Suchfilter den Eintrag nicht mehr findet)
                        $toRemove = $sync.AllProgramItems | Where-Object { $_.Id -eq $deleteId }
                        if ($toRemove) { [void]$sync.AllProgramItems.Remove($toRemove) }
                        # Aus AllEntries entfernen
                        $entryToRemove = $sync.AllEntries | Where-Object { $_.Id -eq $deleteId }
                        if ($entryToRemove) { [void]$sync.AllEntries.Remove($entryToRemove) }
                        $cdWin.Close()
                    })
                    $cdNo.Add_Click({ $cdWin.Close() })
                    [void]$cdBp.Children.Add($cdYes); [void]$cdBp.Children.Add($cdNo)
                    [void]$cdSt.Children.Add($cdBp)
                    $cdWin.Content = $cdSt
                    & $sync.ApplyGoldStyle $cdWin
                    [void]$cdWin.ShowDialog()
                    $e.Handled = $true
                }.GetNewClosure())

                [void]$catPanel.Children.Add($itemBorder)
            }

            $catBoxesCopy = $catBoxes
            $toggleBtn.Add_Click({
                $allChecked = ($catBoxesCopy | Where-Object { -not $_.IsChecked }).Count -eq 0
                foreach ($c in $catBoxesCopy) { $c.IsChecked = -not $allChecked }
                & $sync.UpdateCount
            }.GetNewClosure())

            # "Link hinzufuegen" Button fuer Direktdownload-Kategorie
            if ($cat.Name -eq "Direktdownload") {
                $addLinkBtn = New-Object System.Windows.Controls.Border
                $addLinkBtn.Background      = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#1a1a1a"))
                $addLinkBtn.BorderBrush     = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#333333"))
                $addLinkBtn.BorderThickness = [System.Windows.Thickness]::new(1)
                $addLinkBtn.CornerRadius    = [System.Windows.CornerRadius]::new(3)
                $addLinkBtn.Padding         = [System.Windows.Thickness]::new(12,6,12,6)
                $addLinkBtn.Margin          = [System.Windows.Thickness]::new(30,6,0,4)
                $addLinkBtn.Cursor          = [System.Windows.Input.Cursors]::Hand
                $addLinkBtn.HorizontalAlignment = "Left"
                $addLinkSp = New-Object System.Windows.Controls.StackPanel
                $addLinkSp.Orientation = "Horizontal"
                $addLinkPlus = New-Object System.Windows.Controls.TextBlock
                $addLinkPlus.Text = "+"; $addLinkPlus.FontSize = 14; $addLinkPlus.FontWeight = "Bold"
                $addLinkPlus.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#a93226"))
                $addLinkPlus.Margin = [System.Windows.Thickness]::new(0,0,6,0)
                $addLinkLabel = New-Object System.Windows.Controls.TextBlock
                $addLinkLabel.Text = "Eigenen Link hinzufuegen"
                $addLinkLabel.FontSize = 11
                $addLinkLabel.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#888888"))
                $addLinkLabel.VerticalAlignment = "Center"
                [void]$addLinkSp.Children.Add($addLinkPlus)
                [void]$addLinkSp.Children.Add($addLinkLabel)
                $addLinkBtn.Child = $addLinkSp

                $addLinkBtn.Add_MouseLeftButtonDown({
                    param($s,$e)
                    # Dialog: Name + URL + Beschreibung
                    $dlgWin = New-Object System.Windows.Window
                    $dlgWin.Title = "Direktlink hinzufuegen"
                    $dlgWin.Width = 480; $dlgWin.SizeToContent = "Height"
                    $dlgWin.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#161616"))
                    $dlgWin.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
                    $dlgWin.WindowStartupLocation = "CenterOwner"; $dlgWin.ResizeMode = "NoResize"
                    $dlgWin.Owner = $sync.Window
                    if ($sync.AppIcon) { $dlgWin.Icon = $sync.AppIcon }
                    try {
                        $dlgH = (New-Object System.Windows.Interop.WindowInteropHelper($dlgWin)).EnsureHandle()
                        $dlgD = [int]1
                        [DwmHelper]::DwmSetWindowAttribute($dlgH, [DwmHelper]::DWMWA_USE_IMMERSIVE_DARK_MODE, [ref]$dlgD, 4)
                    } catch {}

                    $dlgSt = New-Object System.Windows.Controls.StackPanel
                    $dlgSt.Margin = [System.Windows.Thickness]::new(24,20,24,20)

                    # Name
                    $lbName = New-Object System.Windows.Controls.TextBlock
                    $lbName.Text = "Programmname"; $lbName.FontSize = 11
                    $lbName.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#888888"))
                    $lbName.Margin = [System.Windows.Thickness]::new(0,0,0,4)
                    [void]$dlgSt.Children.Add($lbName)
                    $tbName = New-Object System.Windows.Controls.TextBox
                    $tbName.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#1a1a1a"))
                    $tbName.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#e0e0e0"))
                    $tbName.BorderBrush = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#333333"))
                    $tbName.Padding = [System.Windows.Thickness]::new(8,6,8,6); $tbName.FontSize = 13
                    $tbName.Margin = [System.Windows.Thickness]::new(0,0,0,12)
                    [void]$dlgSt.Children.Add($tbName)

                    # URL
                    $lbUrl = New-Object System.Windows.Controls.TextBlock
                    $lbUrl.Text = "Download-URL"; $lbUrl.FontSize = 11
                    $lbUrl.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#888888"))
                    $lbUrl.Margin = [System.Windows.Thickness]::new(0,0,0,4)
                    [void]$dlgSt.Children.Add($lbUrl)
                    $tbUrl = New-Object System.Windows.Controls.TextBox
                    $tbUrl.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#1a1a1a"))
                    $tbUrl.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#e0e0e0"))
                    $tbUrl.BorderBrush = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#333333"))
                    $tbUrl.Padding = [System.Windows.Thickness]::new(8,6,8,6); $tbUrl.FontSize = 13
                    $tbUrl.Margin = [System.Windows.Thickness]::new(0,0,0,12)
                    [void]$dlgSt.Children.Add($tbUrl)

                    # Beschreibung
                    $lbDesc = New-Object System.Windows.Controls.TextBlock
                    $lbDesc.Text = "Beschreibung (optional)"; $lbDesc.FontSize = 11
                    $lbDesc.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#888888"))
                    $lbDesc.Margin = [System.Windows.Thickness]::new(0,0,0,4)
                    [void]$dlgSt.Children.Add($lbDesc)
                    $tbDesc = New-Object System.Windows.Controls.TextBox
                    $tbDesc.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#1a1a1a"))
                    $tbDesc.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#e0e0e0"))
                    $tbDesc.BorderBrush = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#333333"))
                    $tbDesc.Padding = [System.Windows.Thickness]::new(8,6,8,6); $tbDesc.FontSize = 13
                    $tbDesc.Margin = [System.Windows.Thickness]::new(0,0,0,18)
                    [void]$dlgSt.Children.Add($tbDesc)

                    # Buttons
                    $dlgBp = New-Object System.Windows.Controls.StackPanel
                    $dlgBp.Orientation = "Horizontal"; $dlgBp.HorizontalAlignment = "Right"
                    $dlgSave = New-Object System.Windows.Controls.Button
                    $dlgSave.Content = "Hinzufuegen"; $dlgSave.Padding = [System.Windows.Thickness]::new(20,8,20,8)
                    $dlgSave.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#a93226"))
                    $dlgSave.Foreground = [System.Windows.Media.Brushes]::White
                    $dlgSave.BorderThickness = [System.Windows.Thickness]::new(0)
                    $dlgSave.FontSize = 12; $dlgSave.Cursor = [System.Windows.Input.Cursors]::Hand
                    $dlgSave.Margin = [System.Windows.Thickness]::new(0,0,8,0)
                    $dlgCancel = New-Object System.Windows.Controls.Button
                    $dlgCancel.Content = "Abbrechen"; $dlgCancel.Padding = [System.Windows.Thickness]::new(20,8,20,8)
                    $dlgCancel.FontSize = 12; $dlgCancel.Cursor = [System.Windows.Input.Cursors]::Hand
                    $dlgSave.Add_Click({
                        $n = $tbName.Text.Trim()
                        $u = $tbUrl.Text.Trim()
                        if ($n -eq "" -or $u -eq "") { return }
                        if (-not $u.StartsWith("http")) { $u = "https://$u" }
                        $d = $tbDesc.Text.Trim()
                        if ($d -eq "") { $d = "Benutzerdefinierter Direktlink" }
                        $linkId = "URL:$u"

                        # In custom-links.json speichern
                        $links = @()
                        try {
                            if (Test-Path $sync.CustomLinksPath) {
                                $existing = Get-Content $sync.CustomLinksPath -Raw -Encoding UTF8 | ConvertFrom-Json
                                if ($existing) { $links = @($existing) }
                            }
                        } catch {}
                        $links += [PSCustomObject]@{ Name = $n; Id = $linkId; Desc = $d }
                        try {
                            $dir = Split-Path $sync.CustomLinksPath -Parent
                            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                            $links | ConvertTo-Json -Depth 5 | Set-Content -Path $sync.CustomLinksPath -Encoding UTF8
                        } catch {}

                        $dlgWin.Close()

                        # Hinweis: Beim naechsten Oeffnen des Katalogs wird der Link angezeigt
                        $msgWin = New-Object System.Windows.Window
                        $msgWin.Title = "Link hinzugefuegt"; $msgWin.Width = 400; $msgWin.SizeToContent = "Height"
                        $msgWin.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#161616"))
                        $msgWin.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
                        $msgWin.WindowStartupLocation = "CenterOwner"; $msgWin.ResizeMode = "NoResize"
                        $msgWin.Owner = $sync.Window
                        if ($sync.AppIcon) { $msgWin.Icon = $sync.AppIcon }
                        try {
                            $mH = (New-Object System.Windows.Interop.WindowInteropHelper($msgWin)).EnsureHandle()
                            $mD = [int]1
                            [DwmHelper]::DwmSetWindowAttribute($mH, [DwmHelper]::DWMWA_USE_IMMERSIVE_DARK_MODE, [ref]$mD, 4)
                        } catch {}
                        $mSt = New-Object System.Windows.Controls.StackPanel
                        $mSt.Margin = [System.Windows.Thickness]::new(24,24,24,24)
                        $mTx = New-Object System.Windows.Controls.TextBlock
                        $mTx.Text = "`"$n`" wurde als Direktlink gespeichert.`n`nDer Link erscheint beim naechsten Oeffnen des Software-Bibliotheks unter `"Direktdownload`"."
                        $mTx.FontSize = 13; $mTx.TextWrapping = "Wrap"
                        $mTx.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#cccccc"))
                        $mTx.Margin = [System.Windows.Thickness]::new(0,0,0,18)
                        [void]$mSt.Children.Add($mTx)
                        $mBtn = New-Object System.Windows.Controls.Button
                        $mBtn.Content = "OK"; $mBtn.HorizontalAlignment = "Right"
                        $mBtn.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#a93226"))
                        $mBtn.Foreground = [System.Windows.Media.Brushes]::White
                        $mBtn.BorderThickness = [System.Windows.Thickness]::new(0)
                        $mBtn.Padding = [System.Windows.Thickness]::new(24,8,24,8)
                        $mBtn.FontSize = 12; $mBtn.Cursor = [System.Windows.Input.Cursors]::Hand
                        $mBtn.Add_Click({ $msgWin.Close() })
                        [void]$mSt.Children.Add($mBtn)
                        $msgWin.Content = $mSt
                        & $sync.ApplyGoldStyle $msgWin
                        [void]$msgWin.ShowDialog()
                    }.GetNewClosure())
                    $dlgCancel.Add_Click({ $dlgWin.Close() })
                    [void]$dlgBp.Children.Add($dlgSave); [void]$dlgBp.Children.Add($dlgCancel)
                    [void]$dlgSt.Children.Add($dlgBp)
                    $dlgWin.Content = $dlgSt
                    & $sync.ApplyGoldStyle $dlgWin
                    [void]$dlgWin.ShowDialog()
                    $e.Handled = $true
                }.GetNewClosure())

                [void]$catPanel.Children.Add($addLinkBtn)
            }

            [void]$sync.ProgramList.Children.Add($catPanel)
        }

    }

    # ── StartScan: prueft installierte Programme per winget list ──────────────
    $sync.StartScan = {
        $sync.ScanDone = $false
        $sync.InstalledIds.Clear()
        $sync.InstalledVersions.Clear()
        $sync.InstalledNames.Clear()

        # AvailableVersions Cache laden (max. 7 Tage alt)
        try {
            if (Test-Path $sync.AvailVersionsCache) {
                $cacheAge = (Get-Date) - (Get-Item $sync.AvailVersionsCache).LastWriteTime
                if ($cacheAge.TotalDays -lt 1) {
                    $cached = Get-Content $sync.AvailVersionsCache -Raw -Encoding UTF8 | ConvertFrom-Json
                    foreach ($prop in $cached.PSObject.Properties) {
                        $sync.AvailableVersions[$prop.Name] = $prop.Value
                    }
                }
            }
        } catch {}

        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $rs.ApartmentState = "STA"; $rs.ThreadOptions = "ReuseThread"; $rs.Open()
        $rs.SessionStateProxy.SetVariable("sync", $sync)

        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.Runspace = $rs
        # Refactor: Get-WingetInstalledList in Runspace injizieren
        [void]$ps.AddScript($WGT_InstalledScannerCode)
        [void]$ps.AddScript({
            try {
                try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
                $debugLog = "$env:USERPROFILE\Appstallo-ScanDebug.log"

                # === Refactor: zentrale Get-WingetInstalledList ===
                # Funktion via $WGT_InstalledScannerCode in Runspace injiziert.
                # Filter (PWA/ARP) zentral in Appstallo.Common.ps1.
                $debugLog = "$env:USERPROFILE\Appstallo-ScanDebug.log"
                "=== Appstallo Scan Debug $(Get-Date) ===" | Out-File $debugLog -Encoding UTF8

                $installed = Get-WingetInstalledList
                "IDs gefunden: $($installed.Count)" | Out-File $debugLog -Encoding UTF8 -Append
                foreach ($p in $installed) {
                    [void]$sync.InstalledIds.Add($p.Id)
                    if ($p.Name) { $sync.InstalledNames[$p.Id] = $p.Name }
                    if ($p.Version) { $sync.InstalledVersions[$p.Id] = $p.Version }
                    "$($p.Id) | $($p.Name) | $($p.Version)" | Out-File $debugLog -Encoding UTF8 -Append
                }
            } catch {
                "FEHLER: $_" | Out-File "$env:USERPROFILE\Appstallo-ScanDebug.log" -Encoding UTF8 -Append
            }
            finally { $sync.ScanDone = $true }
        })
        [void]$ps.BeginInvoke()
        $sync.ScanTimer.Start()
    }

    # ── Scan-Timer ────────────────────────────────────────────────────────────
    $scanTimer = New-Object System.Windows.Threading.DispatcherTimer
    $scanTimer.Interval = [TimeSpan]::FromMilliseconds(300)
    $sync.ScanTimer = $scanTimer

    $scanTimer.Add_Tick({
        try {
            if (-not $sync.ScanDone) { return }
            $sync.ScanTimer.Stop()

            & $sync.AddInstalledToLibrary
            & $sync.BuildUI

            $instCount  = ($sync.AllCategories | ForEach-Object { $_.Items } | Where-Object { $sync.InstalledIds.Contains($_.Id) } | Measure-Object).Count
            $totalCount = ($sync.AllCategories | ForEach-Object { $_.Items } | Where-Object { $_.Id -notlike "URL:*" } | Measure-Object).Count
        $urlCount   = ($sync.AllCategories | ForEach-Object { $_.Items } | Where-Object { $_.Id -like "URL:*" } | Measure-Object).Count

            $sync.ScanPanel.Visibility       = "Collapsed"
            $sync.SelectionPanel.Visibility  = "Visible"
            $sync.SelectAllButton.Visibility = "Visible"
            $sync.InstallButton.Visibility   = "Visible"
            $sync.InstallButton.IsEnabled    = $false
            $sync.CountText.Text             = "Keine Programme ausgewaehlt"
            $sync.StatusText.Text            = "$totalCount Programme ueber winget verfuegbar ($urlCount zusaetzliche Direktdownloads) | $instCount bereits installiert"

            # Hintergrund-Loader starten: laedt fehlende verfuegbare Versionen
            & $sync.StartAvailVersionsLoader
            $sync.AvailRefreshTimer.Start()
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
                $pct = [int](($sync.CurrentPkg / $sync.TotalPkgs) * 90)
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
                $sync.InstallButton.IsEnabled = $false
                if ($sync.Failed -gt 0) {
                    $sync.StatusText.Text = "Abgeschlossen - $($sync.Successful) OK, $($sync.Failed) fehlgeschlagen."
                } else {
                    $sync.StatusText.Text = "$($sync.Successful) Programm(e) erfolgreich installiert."
                }
            }
        } catch {
            $sync.InstallTimer.Stop()
            $_ | Out-File $logPath -Encoding UTF8 -Append
        }
    })

    # ── Alle auswaehlen ───────────────────────────────────────────────────────
    $sync.SelectAllButton.Add_Click({
        $sync.AllSelected = -not $sync.AllSelected
        foreach ($e in $sync.AllEntries) { $e.CB.IsChecked = $sync.AllSelected }
        $sync.SelectAllButton.Content = if ($sync.AllSelected) { "Alle abwaehlen" } else { "Alle auswaehlen" }
        & $sync.UpdateCount
    })

    # ── Installieren ──────────────────────────────────────────────────────────
    $sync.InstallButton.Add_Click({
        if ($sync.SelectedIds.Count -eq 0) { return }
        $selected = @($sync.AllEntries | Where-Object { $sync.SelectedIds.Contains($_.Id) })

        $sync.SelectionPanel.Visibility  = "Collapsed"
        $sync.LogPanel.Visibility        = "Visible"
        $sync.SelectAllButton.Visibility = "Collapsed"
        $sync.InstallButton.IsEnabled    = $false
        $sync.BackButton.Visibility      = "Collapsed"
        $sync.SummaryPanel.Visibility    = "Collapsed"
        $sync.ProgressBar.Value          = 0
        $sync.StatusText.Text            = "Installation laeuft..."

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
                    $sync.Lines.Add(">>> [$($sync.CurrentPkg)/$($sync.TotalPkgs)]  $($pkg.Name)")

                    # URL-Item: Browser oeffnen statt winget
                    if ($pkg.Id -like "URL:*") {
                        $url = $pkg.Id.Substring(4)
                        $sync.Lines.Add("       Browser wird geoeffnet: $url")
                        Start-Process $url
                        $sync.Lines.Add("[OK]   Download-Seite wurde im Browser geoeffnet.")
                        $sync.Successful++
                        continue
                    }

                    $ok = $false
                    & winget install --id $pkg.Id --silent `
                        --accept-source-agreements --accept-package-agreements --force 2>&1 |
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
                        if ($str -match "(?i)(Successfully installed|Erfolgreich installiert)") {
                            $ok = $true; $sync.Lines.Add("[OK]   $str")
                        } elseif ($str -match "(?i)(failed|fehlgeschlagen)" -and $str -notmatch "^[\s\-=]") {
                            $sync.Lines.Add("[ERR]  $str")
                        } else {
                            $sync.Lines.Add("       $str")
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
                    if ($ok) {
                        $sync.Successful++
                        $sync.BiboInstallDone = $true
                    } else {
                        $sync.Failed++
                    }
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

    # ── Zurueck ───────────────────────────────────────────────────────────────
    $sync.BackButton.Add_Click({
        $sync.LogPanel.Visibility        = "Collapsed"
        $sync.SelectionPanel.Visibility  = "Visible"
        $sync.SelectAllButton.Visibility = "Visible"
        $sync.InstallButton.Visibility   = "Visible"
        $sync.BackButton.Visibility      = "Collapsed"
        
        # v1.9.0: Wenn aus Bibo installiert wurde, Rescan und UI-Rebuild ausloesen
        # damit die soeben installierten Programme als "installiert" angezeigt werden.
        if ($sync.BiboInstallDone) {
            $sync.BiboInstallDone = $false
            $sync.StatusText.Text = "Bibliothek wird aktualisiert..."
            
            # InstalledIds neu einlesen via zentrale Get-WingetInstalledList
            $sync.InstalledIds.Clear()
            $sync.InstalledVersions.Clear()
            $sync.InstalledNames.Clear()
            
            try {
                $installed = Get-WingetInstalledList
                foreach ($p in $installed) {
                    [void]$sync.InstalledIds.Add($p.Id)
                    if ($p.Name)    { $sync.InstalledNames[$p.Id]    = $p.Name }
                    if ($p.Version) { $sync.InstalledVersions[$p.Id] = $p.Version }
                }
                # UI komplett neu aufbauen damit Installiert-Badges erscheinen
                & $sync.AddInstalledToLibrary
                & $sync.BuildUI
                & $sync.UpdateCount
            } catch {
                # Fallback: weiterhin Status-Zeile anzeigen
            }
        }
        
        $instCount  = ($sync.AllCategories | ForEach-Object { $_.Items } | Where-Object { $sync.InstalledIds.Contains($_.Id) } | Measure-Object).Count
        $totalCount = ($sync.AllCategories | ForEach-Object { $_.Items } | Where-Object { $_.Id -notlike "URL:*" } | Measure-Object).Count
        $urlCount   = ($sync.AllCategories | ForEach-Object { $_.Items } | Where-Object { $_.Id -like "URL:*" } | Measure-Object).Count
        $sync.StatusText.Text = "$totalCount Programme ueber winget verfuegbar ($urlCount zusaetzliche Direktdownloads) | $instCount bereits installiert"
        & $sync.UpdateCount
    })

    # ── AvailVersions Loader: laedt fehlende Versionen im Hintergrund ────────
    $sync.StartAvailVersionsLoader = {
        # Sammle alle nicht installierten IDs ohne Version
        $idsToFetch = [System.Collections.Generic.List[string]]::new()
        foreach ($entry in $sync.AllProgramItems) {
            if (-not $entry.IsInstalled -and ($entry.Id -notlike "URL:*") -and (-not $sync.AvailableVersions.ContainsKey($entry.Id))) {
                [void]$idsToFetch.Add($entry.Id)
            }
        }
        if ($idsToFetch.Count -eq 0) { return }

        $rsLoader = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $rsLoader.ApartmentState = "STA"; $rsLoader.ThreadOptions = "ReuseThread"; $rsLoader.Open()
        $rsLoader.SessionStateProxy.SetVariable("sync", $sync)
        $rsLoader.SessionStateProxy.SetVariable("idsToFetch", $idsToFetch)

        $psLoader = [System.Management.Automation.PowerShell]::Create()
        $psLoader.Runspace = $rsLoader
        [void]$psLoader.AddScript({
            try {
                try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
                foreach ($id in $idsToFetch) {
                    try {
                        $psi3 = New-Object System.Diagnostics.ProcessStartInfo
                        $psi3.FileName  = "winget"
                        $psi3.Arguments = "show --id `"$id`" --exact --accept-source-agreements"
                        $psi3.UseShellExecute        = $false
                        $psi3.RedirectStandardOutput = $true
                        $psi3.RedirectStandardError  = $true
                        $psi3.CreateNoWindow         = $true
                        $psi3.StandardOutputEncoding = [System.Text.Encoding]::UTF8
                        $proc3 = [System.Diagnostics.Process]::Start($psi3)
                        $stdout3 = $proc3.StandardOutput.ReadToEnd()
                        $proc3.WaitForExit()
                        # Parse Version: Zeile beginnt mit "Version:"
                        $verMatch = [regex]::Match($stdout3, "(?im)^\s*Version:\s*(\S+)")
                        if ($verMatch.Success) {
                            $sync.AvailableVersions[$id] = $verMatch.Groups[1].Value
                            $sync.AvailVersionsRefreshed = $true
                        }
                    } catch {}
                }
                # Cache speichern
                try {
                    $cacheDir = Split-Path $sync.AvailVersionsCache -Parent
                    if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
                    $obj = New-Object PSObject
                    foreach ($k in $sync.AvailableVersions.Keys) {
                        $obj | Add-Member -NotePropertyName $k -NotePropertyValue $sync.AvailableVersions[$k]
                    }
                    $obj | ConvertTo-Json | Set-Content -Path $sync.AvailVersionsCache -Encoding UTF8
                } catch {}
            } catch {}
        })
        [void]$psLoader.BeginInvoke()
    }

    # Timer der die UI-Badges nachtraeglich aktualisiert
    $availTimer = New-Object System.Windows.Threading.DispatcherTimer
    $availTimer.Interval = [TimeSpan]::FromMilliseconds(800)
    $sync.AvailRefreshTimer = $availTimer
    $availTimer.Add_Tick({
        if (-not $sync.AvailVersionsRefreshed) { return }
        $sync.AvailVersionsRefreshed = $false
        $stillMissing = $false
        foreach ($entry in $sync.AllProgramItems) {
            if ($null -eq $entry.AvailBadge) { continue }
            if ($entry.AvailBadge.Visibility -eq "Visible") { continue }
            if ($sync.AvailableVersions.ContainsKey($entry.Id)) {
                $textBlk = $entry.AvailBadge.Child
                $textBlk.Text = "Verfuegbar v" + $sync.AvailableVersions[$entry.Id]
                $entry.AvailBadge.Visibility = "Visible"
            } else {
                $stillMissing = $true
            }
        }
        # Stop wenn nichts mehr fehlt
        if (-not $stillMissing) { $sync.AvailRefreshTimer.Stop() }
    })

    # ── Suchfeld: filtert Programme + blendet leere Kategorien aus ────────────
    $sync.ApplySearchFilter = {
        $query = ""
        if ($null -ne $sync.SearchBox) { $query = $sync.SearchBox.Text.Trim().ToLower() }

        foreach ($entry in $sync.AllProgramItems) {
            $hay = ($entry.Name + " " + $entry.Id + " " + $entry.Desc).ToLower()
            $match = ($query -eq "") -or ($hay.Contains($query))
            $entry.Border.Visibility = if ($match) { "Visible" } else { "Collapsed" }
        }

        # Kategorien ausblenden, deren Items alle ausgeblendet sind
        # HashCode-basiert um Object-Referenz-Probleme zu vermeiden
        $catVisibility = @{}
        foreach ($entry in $sync.AllProgramItems) {
            $key = $entry.CatPanel.GetHashCode()
            if (-not $catVisibility.ContainsKey($key)) {
                $catVisibility[$key] = @{ Panel = $entry.CatPanel; AnyVisible = $false }
            }
            if ($entry.Border.Visibility -eq "Visible") {
                $catVisibility[$key].AnyVisible = $true
            }
        }
        foreach ($v in $catVisibility.Values) {
            $v.Panel.Visibility = if ($v.AnyVisible) { "Visible" } else { "Collapsed" }
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

    # ── Preset-Badge ──────────────────────────────────────────────────────────
    $presetBadge = $window.FindName("PresetBadge")
    if ($null -ne $presetBadge) {
        $presetBadge.Add_MouseLeftButtonUp({
            # WICHTIG: URL explizit als URI öffnen und ShellExecute erzwingen.
            # `Start-Process "https://appstallo.net"` (ohne /) wird auf manchen
            # Systemen als Datei "appstallo.net" interpretiert -> falsche
            # Datei-Assoziation greift (z. B. Download statt Browser).
            $url = 'https://appstallo.net/'
            try {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName        = $url
                $psi.UseShellExecute = $true
                [System.Diagnostics.Process]::Start($psi) | Out-Null
            } catch {
                try { Start-Process -FilePath $url -ErrorAction Stop }
                catch { Start-Process 'explorer.exe' $url }
            }
        })
        $presetBadge.Add_MouseEnter({
            param($sender,$ea)
            $sender.Opacity = 0.82
        })
        $presetBadge.Add_MouseLeave({
            param($sender,$ea)
            $sender.Opacity = 1.0
        })
    }

    # ── Export-Handler ────────────────────────────────────────────────────────

    # ── Reset-Handler ─────────────────────────────────────────────────────────
    # ── Beschreibungen nachladen fuer Listenausgabe ─────────────────────────
    $sync.FetchAndOutput = {
        param($outputMode, $savePath)
        # Items sammeln die eine Beschreibung brauchen
        $itemsToFetch = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($cat in $sync.AllCategories) {
            foreach ($item in $cat.Items) {
                if ($item.Id -like "URL:*") { continue }
                $d = $item.Desc
                if (-not $d -or $d -eq "Auf diesem System installiert" -or $d -eq "Verschoben vom Benutzer" -or $d -eq $item.Name) {
                    $itemsToFetch.Add($item)
                }
            }
        }

        if ($itemsToFetch.Count -eq 0) {
            if ($outputMode -eq "csv") { & $sync.GenerateCsv $savePath }
            if ($outputMode -eq "html") { & $sync.GenerateHtml }
            if ($outputMode -eq "none") { $sync.StatusText.Text = "Alle Beschreibungen sind bereits vorhanden." }
            return
        }

        # Progress-Fenster
        $pw = New-Object System.Windows.Window
        $pw.Title = "Programmbeschreibungen laden..."
        $pw.Width = 500; $pw.Height = 200
        $pw.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#161616"))
        $pw.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
        $pw.WindowStartupLocation = "CenterOwner"; $pw.ResizeMode = "NoResize"
        $pw.Owner = $sync.Window
        if ($sync.AppIcon) { $pw.Icon = $sync.AppIcon }
        try {
            $pwH = (New-Object System.Windows.Interop.WindowInteropHelper($pw)).EnsureHandle()
            $pwD = [int]1
            [DwmHelper]::DwmSetWindowAttribute($pwH, [DwmHelper]::DWMWA_USE_IMMERSIVE_DARK_MODE, [ref]$pwD, 4)
        } catch {}

        $pwSt = New-Object System.Windows.Controls.StackPanel
        $pwSt.Margin = [System.Windows.Thickness]::new(24,24,24,24)
        $pwInfo = New-Object System.Windows.Controls.TextBlock
        $pwInfo.Text = "Zusaetzliche Programminformationen werden aus dem Internet geladen.`nDieser Vorgang kann einige Minuten dauern..."
        $pwInfo.FontSize = 12; $pwInfo.TextWrapping = "Wrap"
        $pwInfo.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#cccccc"))
        $pwInfo.Margin = [System.Windows.Thickness]::new(0,0,0,16)
        [void]$pwSt.Children.Add($pwInfo)

        $pwBar = New-Object System.Windows.Controls.ProgressBar
        $pwBar.Height = 18; $pwBar.Minimum = 0; $pwBar.Maximum = $itemsToFetch.Count
        $pwBar.Value = 0
        $pwBar.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#a93226"))
        $pwBar.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#2a2a2a"))
        $pwBar.BorderThickness = [System.Windows.Thickness]::new(0)
        $pwBar.Margin = [System.Windows.Thickness]::new(0,0,0,8)
        [void]$pwSt.Children.Add($pwBar)

        $pwStatus = New-Object System.Windows.Controls.TextBlock
        $pwStatus.Text = "0 / $($itemsToFetch.Count) Programme..."
        $pwStatus.FontSize = 11
        $pwStatus.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#888888"))
        [void]$pwSt.Children.Add($pwStatus)
        $pw.Content = $pwSt

        # Shared state fuer Runspace
        $fetchState = [hashtable]::Synchronized(@{
            Items    = $itemsToFetch
            Current  = 0
            Done     = $false
            CurrentName = ""
        })

        # Background-Runspace
        $rs = [runspacefactory]::CreateRunspace()
        $rs.ApartmentState = "STA"
        $rs.Open()
        $rs.SessionStateProxy.SetVariable("fetchState", $fetchState)
        $ps = [powershell]::Create().AddScript({
            try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
            foreach ($item in $fetchState.Items) {
                $fetchState.CurrentName = $item.Name
                try {
                    $out = & winget show --id $item.Id --accept-source-agreements 2>&1 | Out-String
                    $dm = [regex]::Match($out, '(?:Beschreibung|Description)\s*:\s*(.+?)(?:\r?\n\S|\r?\n\r?\n)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
                    if ($dm.Success) {
                        $fd = $dm.Groups[1].Value.Trim()
                        if ($fd.Length -gt 200) { $fd = $fd.Substring(0, 200) + "..." }
                        $item.Desc = $fd
                    }
                } catch {}
                $fetchState.Current++
            }
            $fetchState.Done = $true
        })
        $ps.Runspace = $rs
        $ps.BeginInvoke() | Out-Null

        # Poll-Timer
        $fetchTimer = New-Object System.Windows.Threading.DispatcherTimer
        $fetchTimer.Interval = [TimeSpan]::FromMilliseconds(300)
        $fetchTimer.Tag = @{ Bar = $pwBar; Status = $pwStatus; State = $fetchState; Win = $pw; PS = $ps; RS = $rs }
        $fetchTimer.Add_Tick({
            param($sender,$ea)
            $tag = $sender.Tag
            $tag.Bar.Value = $tag.State.Current
            $tag.Status.Text = "$($tag.State.Current) / $($tag.State.Items.Count) Programme... $($tag.State.CurrentName)"
            if ($tag.State.Done) {
                $sender.Stop()
                try { $tag.PS.Dispose() } catch {}
                try { $tag.RS.Close() } catch {}
                $tag.Win.Close()
            }
        })
        $fetchTimer.Start()
        [void]$pw.ShowDialog()

        # UI aktualisieren (Beschreibungen in der Bibliothek anzeigen)
        & $sync.BuildUI
        & $sync.UpdateCount

        # Ausgabe erzeugen (NACH dem Progress-Fenster)
        if ($outputMode -eq "csv") { & $sync.GenerateCsv $savePath }
        if ($outputMode -eq "html") { & $sync.GenerateHtml }
        if ($outputMode -eq "none") { $sync.StatusText.Text = "$($itemsToFetch.Count) Beschreibung(en) erfolgreich abgerufen." }

        # Cache erst NACH der Ausgabe speichern
        & $sync.SaveDescCache
    }

        # ── CSV-Generator ─────────────────────────────────────────────────────────
    $sync.GenerateCsv = {
        param($savePath)
        $csvLines = [System.Collections.Generic.List[string]]::new()
        $csvLines.Add("Kategorie;Name;ID;Beschreibung;Status;Version")
        foreach ($cat in $sync.AllCategories) {
            foreach ($item in $cat.Items) {
                $status = "Nicht installiert"; $ver = ""
                if ($item.Id -like "URL:*") { $status = "Direktlink" }
                elseif ($sync.InstalledIds.Contains($item.Id)) {
                    $status = "Installiert"
                    if ($sync.InstalledVersions.ContainsKey($item.Id)) { $ver = $sync.InstalledVersions[$item.Id] }
                }
                $nm = $item.Name -replace '"', '""'
                $cn = $cat.Name -replace '"', '""'
                $rd = if ($item.Desc -and $item.Desc -ne "Auf diesem System installiert" -and $item.Desc -ne "Verschoben vom Benutzer" -and $item.Desc -ne $item.Name) { $item.Desc } else { "" }
                $dw = ($rd -split '\s+') | Select-Object -First 10
                $sd = ($dw -join ' ') -replace '"', '""'
                $csvLines.Add("""$cn"";""$nm"";""$($item.Id)"";""$sd"";""$status"";""$ver""")
            }
        }
        try {
            [System.IO.File]::WriteAllLines($savePath, $csvLines, [System.Text.Encoding]::UTF8)
            $sync.StatusText.Text = "CSV-Liste gespeichert: $savePath"
        } catch { $sync.StatusText.Text = "Fehler beim Speichern: $_" }
    }

    # ── HTML-Generator ────────────────────────────────────────────────────────
    $sync.GenerateHtml = {
      try {
        $totalProgs = 0; $totalInstalled = 0
        $html = @"
<!DOCTYPE html>
<html><head><meta charset="utf-8">
<title>Appstallo - Programmliste</title>
<style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 30px; color: #222; }
h1 { font-size: 20px; border-bottom: 2px solid #a93226; padding-bottom: 8px; }
h2 { font-size: 14px; color: #a93226; margin-top: 24px; margin-bottom: 6px; }
table { width: 100%; border-collapse: collapse; margin-bottom: 16px; font-size: 12px; table-layout: fixed; }
th { text-align: left; background: #f0f0f0; padding: 5px 8px; border-bottom: 2px solid #ccc; overflow: hidden; text-overflow: ellipsis; }
td { padding: 4px 8px; border-bottom: 1px solid #eee; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
col.c-name { width: 20%; } col.c-id { width: 22%; } col.c-desc { width: 28%; } col.c-status { width: 14%; } col.c-ver { width: 16%; }
tr:hover { background: #f8f8f8; }
.installed { color: #27ae60; font-weight: bold; }
.notinstalled { color: #888; }
.link { color: #2980b9; }
.footer { margin-top: 30px; font-size: 11px; color: #888; border-top: 1px solid #ddd; padding-top: 8px; }
@media print { body { margin: 15px; } h1 { font-size: 16px; } }
</style></head><body>
<h1>Appstallo - Programmliste</h1>
<p style="font-size:12px;color:#666;">Erstellt am $(Get-Date -Format 'dd.MM.yyyy HH:mm') Uhr</p>
"@
        foreach ($cat in $sync.AllCategories) {
            if ($cat.Items.Count -eq 0) { continue }
            $html += "`n<h2>$($cat.Name) ($($cat.Items.Count))</h2>`n"
            $html += "<table><colgroup><col class='c-name'><col class='c-id'><col class='c-desc'><col class='c-status'><col class='c-ver'></colgroup>`n"
            $html += "<tr><th>Programm</th><th>ID</th><th>Beschreibung</th><th>Status</th><th>Version</th></tr>`n"
            foreach ($item in $cat.Items) {
                $totalProgs++
                $statusCls = "notinstalled"; $statusTxt = "Nicht installiert"; $ver = ""
                if ($item.Id -like "URL:*") {
                    $statusCls = "link"; $statusTxt = "Direktlink"
                    $dispId = ($item.Id -replace '^URL:', '')
                } else {
                    $dispId = $item.Id
                    if ($sync.InstalledIds.Contains($item.Id)) {
                        $statusCls = "installed"; $statusTxt = "Installiert"; $totalInstalled++
                        if ($sync.InstalledVersions.ContainsKey($item.Id)) { $ver = $sync.InstalledVersions[$item.Id] }
                    }
                }
                $rawDesc2 = if ($item.Desc -and $item.Desc -ne "Auf diesem System installiert" -and $item.Desc -ne "Verschoben vom Benutzer" -and $item.Desc -ne $item.Name) { $item.Desc } else { "" }
                $descWords2 = ($rawDesc2 -split '\s+') | Select-Object -First 10
                $shortDesc2 = ($descWords2 -join ' ')
                $html += "<tr><td title=""$([System.Net.WebUtility]::HtmlEncode($item.Name))"">$([System.Net.WebUtility]::HtmlEncode($item.Name))</td>"
                $html += "<td title=""$([System.Net.WebUtility]::HtmlEncode($dispId))"">$([System.Net.WebUtility]::HtmlEncode($dispId))</td>"
                $html += "<td title=""$([System.Net.WebUtility]::HtmlEncode($shortDesc2))"">$([System.Net.WebUtility]::HtmlEncode($shortDesc2))</td>"
                $html += "<td class=""$statusCls"">$statusTxt</td>"
                $html += "<td>$ver</td></tr>`n"
            }
            $html += "</table>`n"
        }
        $html += "<div class='footer'>Gesamt: $totalProgs Programme | $totalInstalled installiert | Appstallo v1.9.1</div>"
        $html += "</body></html>"
        $tmpHtml = [System.IO.Path]::Combine($env:TEMP, "Appstallo-Liste.html")
        [System.IO.File]::WriteAllText($tmpHtml, $html, [System.Text.Encoding]::UTF8)
        Invoke-Item $tmpHtml
        $sync.StatusText.Text = "Druckansicht im Browser geoeffnet."
      } catch {
        [System.Windows.MessageBox]::Show("GenerateHtml Fehler:`n$($_.Exception.Message)`n`nZeile: $($_.InvocationInfo.ScriptLineNumber)`n`nStack:`n$($_.ScriptStackTrace)", "Fehler", "OK", "Error") | Out-Null
      }
    }

        # ── Extras-Menü ──────────────────────────────────────────────────────────
    $extrasMenu = New-Object System.Windows.Controls.ContextMenu
    $extrasMenu.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#1e1e1e"))
    $extrasMenu.BorderThickness = [System.Windows.Thickness]::new(1)
    $extrasMenu.BorderBrush = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#333333"))
    $extrasMenu.Padding = [System.Windows.Thickness]::new(0)
    $extrasMenu.Foreground = [System.Windows.Media.Brushes]::White

    $miExport  = New-Object System.Windows.Controls.MenuItem; $miExport.Header  = "Exportieren";       $miExport.Foreground  = [System.Windows.Media.Brushes]::White
    $miImport  = New-Object System.Windows.Controls.MenuItem; $miImport.Header  = "Importieren";       $miImport.Foreground  = [System.Windows.Media.Brushes]::White
    $miList    = New-Object System.Windows.Controls.MenuItem; $miList.Header    = "Liste ausgeben";     $miList.Foreground    = [System.Windows.Media.Brushes]::White
    $miDescFetch = New-Object System.Windows.Controls.MenuItem; $miDescFetch.Header = "Programmbeschreibungen abrufen"; $miDescFetch.Foreground = [System.Windows.Media.Brushes]::White
    $miNewCat  = New-Object System.Windows.Controls.MenuItem; $miNewCat.Header  = "Neue Kategorie anlegen"; $miNewCat.Foreground  = [System.Windows.Media.Brushes]::White
    $miReset   = New-Object System.Windows.Controls.MenuItem; $miReset.Header   = "Bibliothek leeren"; $miReset.Foreground   = [System.Windows.Media.Brushes]::White

    [void]$extrasMenu.Items.Add($miExport)
    [void]$extrasMenu.Items.Add($miImport)
    [void]$extrasMenu.Items.Add($miList)
    [void]$extrasMenu.Items.Add($miDescFetch)
    [void]$extrasMenu.Items.Add($miNewCat)
    [void]$extrasMenu.Items.Add($miReset)

    $sync.ExtrasButton.ContextMenu = $extrasMenu
    $sync.ExtrasButton.Add_Click({
        $sync.ExtrasButton.ContextMenu.PlacementTarget = $sync.ExtrasButton
        $sync.ExtrasButton.ContextMenu.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Top
        $sync.ExtrasButton.ContextMenu.IsOpen = $true
    })

    # ── Beschreibungen-abrufen-Handler ───────────────────────────────────
    $miDescFetch.Add_Click({
        & $sync.FetchAndOutput "none" $null
    })

    # ── Neue-Kategorie-Handler ───────────────────────────────────────────────
    $miNewCat.Add_Click({
        $dlg = New-Object System.Windows.Window
        $dlg.Title = "Neue Kategorie"
        $dlg.Width = 400; $dlg.SizeToContent = "Height"
        $dlg.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#161616"))
        $dlg.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
        $dlg.WindowStartupLocation = "CenterOwner"; $dlg.ResizeMode = "NoResize"
        $dlg.Owner = $sync.Window
        if ($sync.AppIcon) { $dlg.Icon = $sync.AppIcon }
        try {
            $h = (New-Object System.Windows.Interop.WindowInteropHelper($dlg)).EnsureHandle()
            $d = [int]1
            [DwmHelper]::DwmSetWindowAttribute($h, [DwmHelper]::DWMWA_USE_IMMERSIVE_DARK_MODE, [ref]$d, 4)
        } catch {}
        $st = New-Object System.Windows.Controls.StackPanel
        $st.Margin = [System.Windows.Thickness]::new(24,20,24,20)
        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = "Name der neuen Kategorie:"; $lbl.FontSize = 13
        $lbl.Foreground = [System.Windows.Media.Brushes]::White
        $lbl.Margin = [System.Windows.Thickness]::new(0,0,0,8)
        [void]$st.Children.Add($lbl)
        $tb = New-Object System.Windows.Controls.TextBox
        $tb.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#222222"))
        $tb.Foreground = [System.Windows.Media.Brushes]::White
        $tb.BorderBrush = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#444444"))
        $tb.Padding = [System.Windows.Thickness]::new(8,6,8,6); $tb.FontSize = 13
        $tb.Margin = [System.Windows.Thickness]::new(0,0,0,16)
        [void]$st.Children.Add($tb)
        $bp = New-Object System.Windows.Controls.StackPanel
        $bp.Orientation = "Horizontal"; $bp.HorizontalAlignment = "Right"
        $okBtn = New-Object System.Windows.Controls.Button
        $okBtn.Content = "Anlegen"; $okBtn.Padding = [System.Windows.Thickness]::new(20,8,20,8)
        $okBtn.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#a93226"))
        $okBtn.Foreground = [System.Windows.Media.Brushes]::White
        $okBtn.BorderThickness = [System.Windows.Thickness]::new(0)
        $okBtn.FontSize = 12; $okBtn.Cursor = [System.Windows.Input.Cursors]::Hand
        $okBtn.Margin = [System.Windows.Thickness]::new(0,0,8,0)
        $cancelBtn = New-Object System.Windows.Controls.Button
        $cancelBtn.Content = "Abbrechen"; $cancelBtn.Padding = [System.Windows.Thickness]::new(20,8,20,8)
        $cancelBtn.FontSize = 12; $cancelBtn.Cursor = [System.Windows.Input.Cursors]::Hand
        $okBtn.Add_Click({
            $catName = $tb.Text.Trim()
            if ($catName -eq "") { return }
            $exists = $sync.AllCategories | Where-Object { $_.Name -eq $catName }
            if ($exists) {
                [System.Windows.MessageBox]::Show("Diese Kategorie existiert bereits.", "Hinweis", "OK", "Information") | Out-Null
                return
            }
            [void]$sync.CustomCatNames.Add($catName)
            try {
                $dir = Split-Path $sync.CustomCatNamesPath -Parent
                if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                @($sync.CustomCatNames) | ConvertTo-Json | Set-Content -Path $sync.CustomCatNamesPath -Encoding UTF8
            } catch {}
            $sync.AllCategories += @{ Name = $catName; Items = @() }
            $dlg.Close()
            & $sync.BuildUI
            & $sync.UpdateCount
        }.GetNewClosure())
        $cancelBtn.Add_Click({ $dlg.Close() })
        [void]$bp.Children.Add($okBtn); [void]$bp.Children.Add($cancelBtn)
        [void]$st.Children.Add($bp)
        $dlg.Content = $st
        & $sync.ApplyGoldStyle $dlg
        [void]$dlg.ShowDialog()
    })

    # ── Reset-Handler ─────────────────────────────────────────────────────────
    $miReset.Add_Click({
        $rstWin = New-Object System.Windows.Window
        $rstWin.Title = "Bibliothek leeren"; $rstWin.Width = 480; $rstWin.SizeToContent = "Height"
        $rstWin.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#161616"))
        $rstWin.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
        $rstWin.WindowStartupLocation = "CenterOwner"; $rstWin.ResizeMode = "NoResize"
        $rstWin.Owner = $sync.Window
        if ($sync.AppIcon) { $rstWin.Icon = $sync.AppIcon }
        try {
            $rH = (New-Object System.Windows.Interop.WindowInteropHelper($rstWin)).EnsureHandle()
            $rD = [int]1
            [DwmHelper]::DwmSetWindowAttribute($rH, [DwmHelper]::DWMWA_USE_IMMERSIVE_DARK_MODE, [ref]$rD, 4)
        } catch {}
        & $sync.ApplyGoldStyle $rstWin

        $rstSt = New-Object System.Windows.Controls.StackPanel
        $rstSt.Margin = [System.Windows.Thickness]::new(24,24,24,24)

        $rstTitle = New-Object System.Windows.Controls.TextBlock
        $rstTitle.Text = "Gesamte Bibliothek leeren?"
        $rstTitle.FontSize = 16; $rstTitle.FontWeight = "Bold"
        $rstTitle.Foreground = [System.Windows.Media.Brushes]::White
        $rstTitle.Margin = [System.Windows.Thickness]::new(0,0,0,12)
        [void]$rstSt.Children.Add($rstTitle)

        $rstInfo = New-Object System.Windows.Controls.TextBlock
        $rstInfo.Text = "Alle Programme und Direktlinks werden aus der Bibliothek entfernt.`nDies umfasst auch alle vordefinierten Eintraege.`n`nDie Eintraege lassen sich jederzeit per Import wiederherstellen."
        $rstInfo.FontSize = 13; $rstInfo.TextWrapping = "Wrap"
        $rstInfo.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#cccccc"))
        $rstInfo.Margin = [System.Windows.Thickness]::new(0,0,0,24)
        [void]$rstSt.Children.Add($rstInfo)

        $rstBtnRow = New-Object System.Windows.Controls.Grid
        $rstC1 = New-Object System.Windows.Controls.ColumnDefinition; $rstC1.Width = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
        $rstC2 = New-Object System.Windows.Controls.ColumnDefinition; $rstC2.Width = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
        [void]$rstBtnRow.ColumnDefinitions.Add($rstC1); [void]$rstBtnRow.ColumnDefinitions.Add($rstC2)

        $rstCancel = New-Object System.Windows.Controls.Button
        $rstCancel.Content = "Abbrechen"
        $rstCancel.Padding = [System.Windows.Thickness]::new(16,10,16,10)
        $rstCancel.Margin  = [System.Windows.Thickness]::new(0,0,6,0)
        $rstCancel.Add_Click({ $rstWin.Close() })
        [System.Windows.Controls.Grid]::SetColumn($rstCancel, 0)
        [void]$rstBtnRow.Children.Add($rstCancel)

        $rstYes = New-Object System.Windows.Controls.Button
        $rstYes.Content = "Ja, leeren (15)"
        $rstYes.Padding = [System.Windows.Thickness]::new(16,10,16,10)
        $rstYes.Margin  = [System.Windows.Thickness]::new(6,0,0,0)
        $rstYes.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#a93226"))
        $rstYes.Foreground = [System.Windows.Media.Brushes]::White
        $rstYes.BorderThickness = [System.Windows.Thickness]::new(0)
        $rstYes.IsEnabled = $false
        $rstYes.Add_Click({ $script:doReset = $true; $rstWin.Close() })
        [System.Windows.Controls.Grid]::SetColumn($rstYes, 1)
        [void]$rstBtnRow.Children.Add($rstYes)
        [void]$rstSt.Children.Add($rstBtnRow)
        $rstWin.Content = $rstSt

        $script:doReset = $false
        $cdState = @{ Count = 15; Timer = $null; YesBtn = $rstYes }
        $cdTimer2 = New-Object System.Windows.Threading.DispatcherTimer
        $cdTimer2.Interval = [TimeSpan]::FromSeconds(1)
        $cdState.Timer = $cdTimer2
        $cdTimer2.Add_Tick({
            $cdState.Count--
            if ($cdState.Count -gt 0) {
                $cdState.YesBtn.Content = "Ja, leeren ($($cdState.Count))"
            } else {
                $cdState.Timer.Stop()
                $cdState.YesBtn.Content = "Ja, leeren"
                $cdState.YesBtn.IsEnabled = $true
            }
        }.GetNewClosure())
        $rstWin.Add_Loaded({ $cdTimer2.Start() })
        [void]$rstWin.ShowDialog()
        $cdTimer2.Stop()
        if (-not $script:doReset) { return }

        # Alle benutzerdefinierten Dateien loeschen
        $removedCount = 0
        foreach ($cat in $sync.AllCategories) { $removedCount += $cat.Items.Count }
        if (Test-Path $sync.CustomCatalogPath)  { Remove-Item $sync.CustomCatalogPath  -Force }
        if (Test-Path $sync.CustomAssignPath)   { Remove-Item $sync.CustomAssignPath   -Force }
        if (Test-Path $sync.CustomCatNamesPath) { Remove-Item $sync.CustomCatNamesPath -Force }
        $sync.CustomAssignments.Clear()
        $sync.CustomCatNames.Clear()

        if (Test-Path $sync.CustomLinksPath)   { Remove-Item $sync.CustomLinksPath   -Force }

        # Ergebnis-Fenster mit Stats-Panel
        $doneWin = New-Object System.Windows.Window
        $doneWin.Title = "Bibliothek geleert"; $doneWin.Width = 480; $doneWin.SizeToContent = "Height"
        $doneWin.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#161616"))
        $doneWin.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
        $doneWin.WindowStartupLocation = "CenterOwner"; $doneWin.ResizeMode = "NoResize"
        $doneWin.Owner = $sync.Window
        if ($sync.AppIcon) { $doneWin.Icon = $sync.AppIcon }
        try {
            $dwH = (New-Object System.Windows.Interop.WindowInteropHelper($doneWin)).EnsureHandle()
            $dwD = [int]1
            [DwmHelper]::DwmSetWindowAttribute($dwH, [DwmHelper]::DWMWA_USE_IMMERSIVE_DARK_MODE, [ref]$dwD, 4)
        } catch {}
        & $sync.ApplyGoldStyle $doneWin

        $doneGrid = New-Object System.Windows.Controls.Grid
        for ($ri = 0; $ri -lt 3; $ri++) {
            $dR = New-Object System.Windows.Controls.RowDefinition
            $dR.Height = [System.Windows.GridLength]::Auto
            [void]$doneGrid.RowDefinitions.Add($dR)
        }

        # Stats-Header
        $dHeader = New-Object System.Windows.Controls.Border
        $dHeader.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#1a1a1a"))
        $dHeader.BorderBrush = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#a93226"))
        $dHeader.BorderThickness = [System.Windows.Thickness]::new(0,0,0,2)
        $dHeader.Padding = [System.Windows.Thickness]::new(0,20,0,20)
        [System.Windows.Controls.Grid]::SetRow($dHeader, 0)

        $dStatGrid = New-Object System.Windows.Controls.Grid
        for ($ci = 0; $ci -lt 3; $ci++) {
            $dCol = New-Object System.Windows.Controls.ColumnDefinition
            $dCol.Width = if ($ci -eq 1) { [System.Windows.GridLength]::Auto } else { [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star) }
            [void]$dStatGrid.ColumnDefinitions.Add($dCol)
        }

        # Entfernt (gruen)
        $dOkSp = New-Object System.Windows.Controls.StackPanel; $dOkSp.HorizontalAlignment = "Center"
        [System.Windows.Controls.Grid]::SetColumn($dOkSp, 0)
        $dOkNum = New-Object System.Windows.Controls.TextBlock
        $dOkNum.Text = "$removedCount"; $dOkNum.FontSize = 40; $dOkNum.FontWeight = "Bold"; $dOkNum.HorizontalAlignment = "Center"
        $dOkNum.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#27ae60"))
        $dOkLbl = New-Object System.Windows.Controls.TextBlock
        $dOkLbl.Text = "Entfernt"; $dOkLbl.FontSize = 13; $dOkLbl.HorizontalAlignment = "Center"
        $dOkLbl.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#27ae60"))
        [void]$dOkSp.Children.Add($dOkNum); [void]$dOkSp.Children.Add($dOkLbl)
        [void]$dStatGrid.Children.Add($dOkSp)

        $dSepLine = New-Object System.Windows.Controls.Border
        $dSepLine.Width = 1
        $dSepLine.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#333333"))
        $dSepLine.Margin = [System.Windows.Thickness]::new(0,8,0,8)
        [System.Windows.Controls.Grid]::SetColumn($dSepLine, 1)
        [void]$dStatGrid.Children.Add($dSepLine)

        # Fehler (rot)
        $dErrSp = New-Object System.Windows.Controls.StackPanel; $dErrSp.HorizontalAlignment = "Center"
        [System.Windows.Controls.Grid]::SetColumn($dErrSp, 2)
        $dErrNum = New-Object System.Windows.Controls.TextBlock
        $dErrNum.Text = "0"; $dErrNum.FontSize = 40; $dErrNum.FontWeight = "Bold"; $dErrNum.HorizontalAlignment = "Center"
        $dErrNum.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#e74c3c"))
        $dErrLbl = New-Object System.Windows.Controls.TextBlock
        $dErrLbl.Text = "Fehler"; $dErrLbl.FontSize = 13; $dErrLbl.HorizontalAlignment = "Center"
        $dErrLbl.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#e74c3c"))
        [void]$dErrSp.Children.Add($dErrNum); [void]$dErrSp.Children.Add($dErrLbl)
        [void]$dStatGrid.Children.Add($dErrSp)
        $dHeader.Child = $dStatGrid
        [void]$doneGrid.Children.Add($dHeader)

        $dInfo = New-Object System.Windows.Controls.TextBlock
        $dInfo.Text = "Die Bibliothek wurde vollstaendig geleert.`nSie wird jetzt neu geladen."
        $dInfo.FontSize = 13; $dInfo.TextWrapping = "Wrap"
        $dInfo.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#cccccc"))
        $dInfo.Margin = [System.Windows.Thickness]::new(24,20,24,0)
        [System.Windows.Controls.Grid]::SetRow($dInfo, 1)
        [void]$doneGrid.Children.Add($dInfo)

        $dFooter = New-Object System.Windows.Controls.Border
        $dFooter.Padding = [System.Windows.Thickness]::new(24,16,24,24)
        [System.Windows.Controls.Grid]::SetRow($dFooter, 2)
        $dOkBtn = New-Object System.Windows.Controls.Button
        $dOkBtn.Content = "OK"; $dOkBtn.HorizontalAlignment = "Right"
        $dOkBtn.Padding = [System.Windows.Thickness]::new(32,8,32,8); $dOkBtn.FontSize = 12
        $dOkBtn.Add_Click({ $doneWin.Close() })
        $dFooter.Child = $dOkBtn
        [void]$doneGrid.Children.Add($dFooter)
        $doneWin.Content = $doneGrid
        [void]$doneWin.ShowDialog()

        # Bibliothek neu laden (leer, aber Direktdownload-Kategorie bleibt)
        $sync.ProgramList.Children.Clear()
        $sync.AllProgramItems.Clear()
        $sync.AllEntries.Clear()
        $sync.SelectedIds.Clear()

        # Leere Bibliothek: nur Direktdownload-Kategorie
        $sync.AllCategories = @(
            @{ Name = "Direktdownload"; Items = @() }
        )
        & $sync.BuildUI
        & $sync.UpdateCount
        $sync.StatusText.Text = "Bibliothek wurde geleert. $removedCount Eintraege entfernt."
    })

    $miExport.Add_Click({
        # Auswahl-Dialog: Gesamte Bibliothek oder Auswahl
        $exportMode = $null
        $exWin = New-Object System.Windows.Window
        $exWin.Title = "Export-Modus"; $exWin.Width = 500; $exWin.SizeToContent = "Height"
        $exWin.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#161616"))
        $exWin.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
        $exWin.WindowStartupLocation = "CenterOwner"; $exWin.ResizeMode = "NoResize"
        $exWin.Owner = $sync.Window
        if ($sync.AppIcon) { $exWin.Icon = $sync.AppIcon }
        try {
            $exH = (New-Object System.Windows.Interop.WindowInteropHelper($exWin)).EnsureHandle()
            $exD = [int]1
            [DwmHelper]::DwmSetWindowAttribute($exH, [DwmHelper]::DWMWA_USE_IMMERSIVE_DARK_MODE, [ref]$exD, 4)
        } catch {}
        & $sync.ApplyGoldStyle $exWin

        $exSt = New-Object System.Windows.Controls.StackPanel
        $exSt.Margin = [System.Windows.Thickness]::new(24,24,24,24)

        $exTitle = New-Object System.Windows.Controls.TextBlock
        $exTitle.Text = "Was soll exportiert werden?"
        $exTitle.FontSize = 15; $exTitle.FontWeight = "Bold"
        $exTitle.Foreground = [System.Windows.Media.Brushes]::White
        $exTitle.Margin = [System.Windows.Thickness]::new(0,0,0,20)
        [void]$exSt.Children.Add($exTitle)

        # Anzahl ausgewaehlter Programme
        $selCount = $sync.SelectedIds.Count

        # Button: Gesamte Bibliothek
        $btnAll = New-Object System.Windows.Controls.Button
        $btnAll.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#a93226"))
        $btnAll.Padding = [System.Windows.Thickness]::new(16,10,16,10)
        $btnAll.Margin  = [System.Windows.Thickness]::new(0,0,0,8)
        $btnAll.HorizontalContentAlignment = "Left"
        $allSp = New-Object System.Windows.Controls.StackPanel
        $allSp.HorizontalAlignment = "Stretch"
        $allTitle = New-Object System.Windows.Controls.TextBlock
        $allTitle.Text = "Gesamte Bibliothek exportieren"
        $allTitle.FontWeight = "Bold"; $allTitle.FontSize = 13
        $allTitle.HorizontalAlignment = "Left"
        $allTitle.Foreground = [System.Windows.Media.Brushes]::Black
        $allDesc = New-Object System.Windows.Controls.TextBlock
        $allDesc.Text = "Alle Programme, Direktlinks und Ausschluesse werden gesichert."
        $allDesc.FontSize = 11; $allDesc.TextWrapping = "Wrap"
        $allDesc.HorizontalAlignment = "Left"
        $allDesc.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#1a1a1a"))
        [void]$allSp.Children.Add($allTitle); [void]$allSp.Children.Add($allDesc)
        $btnAll.Content = $allSp
        $btnAll.Add_Click({ $script:exportMode = "all"; $exWin.Close() })
        [void]$exSt.Children.Add($btnAll)

        # Button: Ausgewaehlt
        $btnSel = New-Object System.Windows.Controls.Button
        $btnSel.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#a93226"))
        $btnSel.Padding = [System.Windows.Thickness]::new(16,10,16,10)
        $btnSel.Margin  = [System.Windows.Thickness]::new(0,0,0,8)
        $btnSel.HorizontalContentAlignment = "Left"
        $btnSel.IsEnabled = ($selCount -gt 0)
        $selSp = New-Object System.Windows.Controls.StackPanel
        $selSp.HorizontalAlignment = "Stretch"
        $selTitle = New-Object System.Windows.Controls.TextBlock
        $selTitle.Text = "Nur ausgewaehlte Eintraege exportieren"
        $selTitle.FontWeight = "Bold"; $selTitle.FontSize = 13
        $selTitle.HorizontalAlignment = "Left"
        $selTitle.Foreground = [System.Windows.Media.Brushes]::Black
        $selDesc = New-Object System.Windows.Controls.TextBlock
        $selDesc.Text = if ($selCount -gt 0) {
            "$selCount Programm(e) ausgewaehlt. Nur diese werden in die Backup-Datei geschrieben."
        } else {
            "Keine Programme ausgewaehlt. Bitte zuerst Programme in der Liste markieren."
        }
        $selDesc.FontSize = 11; $selDesc.TextWrapping = "Wrap"
        $selDesc.HorizontalAlignment = "Left"
        $selDesc.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#1a1a1a"))
        [void]$selSp.Children.Add($selTitle); [void]$selSp.Children.Add($selDesc)
        $btnSel.Content = $selSp
        $btnSel.Add_Click({ $script:exportMode = "selected"; $exWin.Close() })
        [void]$exSt.Children.Add($btnSel)

        # Abbrechen
        $btnExCancel = New-Object System.Windows.Controls.Button
        $btnExCancel.Content = "Abbrechen"
        $btnExCancel.Padding = [System.Windows.Thickness]::new(16,8,16,8)
        $btnExCancel.HorizontalAlignment = "Right"
        $btnExCancel.Margin = [System.Windows.Thickness]::new(0,8,0,0)
        $btnExCancel.Add_Click({ $exWin.Close() })
        [void]$exSt.Children.Add($btnExCancel)

        $exWin.Content = $exSt
        $script:exportMode = $null
        [void]$exWin.ShowDialog()
        if (-not $script:exportMode) { return }

        # Speicherdialog
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Title    = "Bibliothek exportieren"
        $dlg.Filter   = "JSON-Backup (*.json)|*.json"
        $dlg.FileName = "Appstallo-Bibliothek-Backup.json"
        if ($dlg.ShowDialog() -ne "OK") { return }

        # Daten zusammenstellen
        if ($script:exportMode -eq "all") {
            # Alle Programme aus allen Kategorien
            $allPrograms = @()
            $allLinks    = @()
            foreach ($cat in $sync.AllCategories) {
                foreach ($item in $cat.Items) {
                    if ($item.Id -like "URL:*") {
                        $allLinks += [PSCustomObject]@{ Name = $item.Name; Id = $item.Id; Desc = $item.Desc; Category = $cat.Name }
                    } else {
                        $allPrograms += [PSCustomObject]@{ Name = $item.Name; Id = $item.Id; Desc = $item.Desc; Category = $cat.Name }
                    }
                }
            }
            # CustomAssignments als PSCustomObject mit benannten Properties exportieren
            $assignObj = [PSCustomObject]@{}
            foreach ($k in $sync.CustomAssignments.Keys) {
                $assignObj | Add-Member -NotePropertyName $k -NotePropertyValue $sync.CustomAssignments[$k]
            }
            $backup = [PSCustomObject]@{
                Version     = "1.9.1"
                ExportDate  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                ExportMode  = "full"
                Programs          = $allPrograms
                DirectLinks       = $allLinks
                CustomCategories  = @($sync.CustomCatNames)
                CustomAssignments = $assignObj
            }
            $exportCount = "$($allPrograms.Count) Programm(e), $($allLinks.Count) Direktlink(s), $($excluded.Count) Ausschluss(e)"
        } else {
            # Nur ausgewaehlte Programme
            $selPrograms = @()
            foreach ($cat in $sync.AllCategories) {
                foreach ($item in $cat.Items) {
                    if ($sync.SelectedIds.Contains($item.Id)) {
                        if ($item.Id -like "URL:*") {
                            $selPrograms += [PSCustomObject]@{ Name = $item.Name; Id = $item.Id; Desc = $item.Desc; Category = $cat.Name }
                        } else {
                            $selPrograms += [PSCustomObject]@{ Name = $item.Name; Id = $item.Id; Desc = $item.Desc; Category = $cat.Name }
                        }
                    }
                }
            }
            # CustomAssignments nur fuer die ausgewaehlten IDs uebernehmen
            $selIds = @($selPrograms | ForEach-Object { $_.Id })
            $assignObj = [PSCustomObject]@{}
            foreach ($k in $sync.CustomAssignments.Keys) {
                if ($selIds -contains $k) {
                    $assignObj | Add-Member -NotePropertyName $k -NotePropertyValue $sync.CustomAssignments[$k]
                }
            }
            $backup = [PSCustomObject]@{
                Version     = "1.9.1"
                ExportDate  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                ExportMode  = "selection"
                Programs          = @($selPrograms | Where-Object { $_.Id -notlike "URL:*" })
                DirectLinks       = @($selPrograms | Where-Object { $_.Id -like "URL:*" })
                CustomCategories  = @($sync.CustomCatNames)
                CustomAssignments = $assignObj
            }
            $exportCount = "$($selPrograms.Count) Programm(e) (Auswahl)"
        }

        try {
            $backup | ConvertTo-Json -Depth 10 | Set-Content -Path $dlg.FileName -Encoding UTF8
        } catch {
            $sync.StatusText.Text = "Export fehlgeschlagen: $_"
            return
        }

        # Bestaetigung
        $msgWin = New-Object System.Windows.Window
        $msgWin.Title = "Export erfolgreich"; $msgWin.Width = 440; $msgWin.SizeToContent = "Height"
        $msgWin.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#161616"))
        $msgWin.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
        $msgWin.WindowStartupLocation = "CenterOwner"; $msgWin.ResizeMode = "NoResize"
        $msgWin.Owner = $sync.Window
        if ($sync.AppIcon) { $msgWin.Icon = $sync.AppIcon }
        try {
            $mH = (New-Object System.Windows.Interop.WindowInteropHelper($msgWin)).EnsureHandle()
            $mD = [int]1
            [DwmHelper]::DwmSetWindowAttribute($mH, [DwmHelper]::DWMWA_USE_IMMERSIVE_DARK_MODE, [ref]$mD, 4)
        } catch {}
        $mSt = New-Object System.Windows.Controls.StackPanel
        $mSt.Margin = [System.Windows.Thickness]::new(24,24,24,24)
        $mTx = New-Object System.Windows.Controls.TextBlock
        $mTx.Text = "Bibliothek erfolgreich exportiert.`n`n$exportCount.`n`nGespeichert unter:`n$($dlg.FileName)"
        $mTx.FontSize = 13; $mTx.TextWrapping = "Wrap"
        $mTx.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#cccccc"))
        $mTx.Margin = [System.Windows.Thickness]::new(0,0,0,18)
        [void]$mSt.Children.Add($mTx)
        $mBtn = New-Object System.Windows.Controls.Button
        $mBtn.Content = "OK"; $mBtn.HorizontalAlignment = "Right"
        $mBtn.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#2a2a2a"))
        $mBtn.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#aaaaaa"))
        $mBtn.BorderThickness = [System.Windows.Thickness]::new(0)
        $mBtn.Padding = [System.Windows.Thickness]::new(24,8,24,8)
        $mBtn.FontSize = 12; $mBtn.Cursor = [System.Windows.Input.Cursors]::Hand
        $mBtn.Add_Click({ $msgWin.Close() })
        [void]$mSt.Children.Add($mBtn)
        $msgWin.Content = $mSt
        & $sync.ApplyGoldStyle $msgWin
        [void]$msgWin.ShowDialog()
    })


    # ── Import-Handler ────────────────────────────────────────────────────────
    $miImport.Add_Click({
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title  = "Bibliothek importieren"
        $dlg.Filter = "JSON-Backup (*.json)|*.json|Alle Dateien (*.*)|*.*"
        if ($dlg.ShowDialog() -ne "OK") { return }

        # Backup laden
        $backup = $null
        try {
            $raw = Get-Content $dlg.FileName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($raw.Programs -or $raw.DirectLinks -or $raw.CustomCatalog -or $raw.CustomLinks) { $backup = $raw }
        } catch {}
        if (-not $backup) {
            $sync.StatusText.Text = "Ungueltige Backup-Datei."
            return
        }

        # Neues und altes Format unterstuetzen
        $impPrograms = if ($backup.Programs)      { @($backup.Programs) }
                  elseif ($backup.CustomCatalog)   { @($backup.CustomCatalog) }
                  else { @() }
        $impLinks    = if ($backup.DirectLinks)    { @($backup.DirectLinks) }
                  elseif ($backup.CustomLinks)     { @($backup.CustomLinks) }
                  else { @() }

        $impDate     = if ($backup.ExportDate)     { $backup.ExportDate }        else { "unbekannt" }
        $impCatNames = if ($backup.CustomCategories)  { @($backup.CustomCategories) }  else { @() }
        $impAssign   = if ($backup.CustomAssignments) { $backup.CustomAssignments }     else { $null }

        # Auswahl-Dialog: Ueberschreiben oder Zusammenfuehren
        $importMode = $null
        $choiceWin = New-Object System.Windows.Window
        $choiceWin.Title = "Import-Modus"; $choiceWin.Width = 500; $choiceWin.SizeToContent = "Height"
        $choiceWin.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#161616"))
        $choiceWin.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
        $choiceWin.WindowStartupLocation = "CenterOwner"; $choiceWin.ResizeMode = "NoResize"
        $choiceWin.Owner = $sync.Window
        if ($sync.AppIcon) { $choiceWin.Icon = $sync.AppIcon }
        try {
            $cH = (New-Object System.Windows.Interop.WindowInteropHelper($choiceWin)).EnsureHandle()
            $cD = [int]1
            [DwmHelper]::DwmSetWindowAttribute($cH, [DwmHelper]::DWMWA_USE_IMMERSIVE_DARK_MODE, [ref]$cD, 4)
        } catch {}

        $cSt = New-Object System.Windows.Controls.StackPanel
        $cSt.Margin = [System.Windows.Thickness]::new(24,24,24,24)

        $cTitle = New-Object System.Windows.Controls.TextBlock
        $cTitle.Text = "Backup vom $impDate"
        $cTitle.FontSize = 15; $cTitle.FontWeight = "Bold"
        $cTitle.Foreground = [System.Windows.Media.Brushes]::White
        $cTitle.Margin = [System.Windows.Thickness]::new(0,0,0,8)
        [void]$cSt.Children.Add($cTitle)

        $cInfo = New-Object System.Windows.Controls.TextBlock
        $cInfo.Text = "Inhalt: $($impPrograms.Count) Programm(e), $($impLinks.Count) Direktlink(s), 0 Ausschluss(e).`n`nWie soll importiert werden?"
        $cInfo.FontSize = 13; $cInfo.TextWrapping = "Wrap"
        $cInfo.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#cccccc"))
        $cInfo.Margin = [System.Windows.Thickness]::new(0,0,0,20)
        [void]$cSt.Children.Add($cInfo)

        # Button: Ueberschreiben
        $btnOverwrite = New-Object System.Windows.Controls.Button
        $btnOverwrite.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#a93226"))
        $btnOverwrite.Padding = [System.Windows.Thickness]::new(16,10,16,10)
        $btnOverwrite.Margin  = [System.Windows.Thickness]::new(0,0,0,8)
        $btnOverwrite.HorizontalContentAlignment = "Left"
        $owSp = New-Object System.Windows.Controls.StackPanel
        $owSp.HorizontalAlignment = "Stretch"
        $owTitle = New-Object System.Windows.Controls.TextBlock
        $owTitle.Text = "Ueberschreiben"; $owTitle.FontWeight = "Bold"; $owTitle.FontSize = 13
        $owTitle.HorizontalAlignment = "Left"
        $owTitle.Foreground = [System.Windows.Media.Brushes]::Black
        $owDesc = New-Object System.Windows.Controls.TextBlock
        $owDesc.Text = "Aktuelle Bibliothek wird durch das Backup ersetzt."
        $owDesc.FontSize = 11
        $owDesc.HorizontalAlignment = "Left"
        $owDesc.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#1a1a1a"))
        [void]$owSp.Children.Add($owTitle); [void]$owSp.Children.Add($owDesc)
        $btnOverwrite.Content = $owSp
        $btnOverwrite.Add_Click({ $script:importMode = "overwrite"; $choiceWin.Close() })
        [void]$cSt.Children.Add($btnOverwrite)

        # Button: Zusammenfuehren
        $btnMerge = New-Object System.Windows.Controls.Button
        $btnMerge.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#a93226"))
        $btnMerge.Padding = [System.Windows.Thickness]::new(16,10,16,10)
        $btnMerge.Margin  = [System.Windows.Thickness]::new(0,0,0,8)
        $btnMerge.HorizontalContentAlignment = "Left"
        $mgSp = New-Object System.Windows.Controls.StackPanel
        $mgSp.HorizontalAlignment = "Stretch"
        $mgTitle = New-Object System.Windows.Controls.TextBlock
        $mgTitle.Text = "Zusammenfuehren"; $mgTitle.FontWeight = "Bold"; $mgTitle.FontSize = 13
        $mgTitle.HorizontalAlignment = "Left"
        $mgTitle.Foreground = [System.Windows.Media.Brushes]::Black
        $mgDesc = New-Object System.Windows.Controls.TextBlock
        $mgDesc.Text = "Bestehende und importierte Eintraege werden kombiniert. Duplikate werden uebersprungen."
        $mgDesc.FontSize = 11; $mgDesc.TextWrapping = "Wrap"
        $mgDesc.HorizontalAlignment = "Left"
        $mgDesc.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#1a1a1a"))
        [void]$mgSp.Children.Add($mgTitle); [void]$mgSp.Children.Add($mgDesc)
        $btnMerge.Content = $mgSp
        $btnMerge.Add_Click({ $script:importMode = "merge"; $choiceWin.Close() })
        [void]$cSt.Children.Add($btnMerge)

        # Button: Direkt installieren
        $btnInstall = New-Object System.Windows.Controls.Button
        $btnInstall.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#a93226"))
        $btnInstall.Padding = [System.Windows.Thickness]::new(16,10,16,10)
        $btnInstall.Margin  = [System.Windows.Thickness]::new(0,0,0,8)
        $btnInstall.HorizontalContentAlignment = "Left"
        $instSp = New-Object System.Windows.Controls.StackPanel
        $instSp.HorizontalAlignment = "Stretch"
        $instTitle = New-Object System.Windows.Controls.TextBlock
        $instTitle.Text = "Direkt installieren"; $instTitle.FontWeight = "Bold"; $instTitle.FontSize = 13
        $instTitle.HorizontalAlignment = "Left"
        $instTitle.Foreground = [System.Windows.Media.Brushes]::Black
        $instDesc = New-Object System.Windows.Controls.TextBlock
        $instDesc.Text = "Die Programme aus dem Backup werden sofort installiert. Du kannst waehlen, ob sie zusaetzlich zur Bibliothek hinzugefuegt werden sollen."
        $instDesc.FontSize = 11; $instDesc.TextWrapping = "Wrap"
        $instDesc.HorizontalAlignment = "Left"
        $instDesc.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#1a1a1a"))
        [void]$instSp.Children.Add($instTitle); [void]$instSp.Children.Add($instDesc)
        $btnInstall.Content = $instSp
        $btnInstall.Add_Click({ $script:importMode = "install"; $choiceWin.Close() })
        [void]$cSt.Children.Add($btnInstall)

        # Button: Abbrechen
        $btnCancel = New-Object System.Windows.Controls.Button
        $btnCancel.Content = "Abbrechen"
        $btnCancel.Padding = [System.Windows.Thickness]::new(16,8,16,8)
        $btnCancel.HorizontalAlignment = "Right"
        $btnCancel.Margin = [System.Windows.Thickness]::new(0,8,0,0)
        $btnCancel.Add_Click({ $choiceWin.Close() })
        [void]$cSt.Children.Add($btnCancel)

        $choiceWin.Content = $cSt
        $script:importMode = $null
        & $sync.ApplyGoldStyle $choiceWin
        [void]$choiceWin.ShowDialog()

        if (-not $script:importMode) { return }

        

        # Modus: Direkt installieren
        if ($script:importMode -eq "install") {
            # Unter-Dialog: Nur installieren oder installieren + zur Bibliothek hinzufuegen
            $instMode = $null
            $subWin = New-Object System.Windows.Window
            $subWin.Title = "Installations-Optionen"; $subWin.Width = 500; $subWin.SizeToContent = "Height"
            $subWin.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#161616"))
            $subWin.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
            $subWin.WindowStartupLocation = "CenterOwner"; $subWin.ResizeMode = "NoResize"
            $subWin.Owner = $sync.Window
            if ($sync.AppIcon) { $subWin.Icon = $sync.AppIcon }
            try {
                $sbH = (New-Object System.Windows.Interop.WindowInteropHelper($subWin)).EnsureHandle()
                $sbD = [int]1
                [DwmHelper]::DwmSetWindowAttribute($sbH, [DwmHelper]::DWMWA_USE_IMMERSIVE_DARK_MODE, [ref]$sbD, 4)
            } catch {}
            & $sync.ApplyGoldStyle $subWin

            $subSt = New-Object System.Windows.Controls.StackPanel
            $subSt.Margin = [System.Windows.Thickness]::new(24,24,24,24)

            $subTitle = New-Object System.Windows.Controls.TextBlock
            $subTitle.Text = "$($impPrograms.Count) Programm(e) werden installiert."
            $subTitle.FontSize = 15; $subTitle.FontWeight = "Bold"
            $subTitle.Foreground = [System.Windows.Media.Brushes]::White
            $subTitle.Margin = [System.Windows.Thickness]::new(0,0,0,8)
            [void]$subSt.Children.Add($subTitle)
            $subInfo = New-Object System.Windows.Controls.TextBlock
            $subInfo.Text = "Sollen die Programme auch zur Bibliothek hinzugefuegt werden?"
            $subInfo.FontSize = 13; $subInfo.TextWrapping = "Wrap"
            $subInfo.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#cccccc"))
            $subInfo.Margin = [System.Windows.Thickness]::new(0,0,0,20)
            [void]$subSt.Children.Add($subInfo)

            # Nur installieren
            $btnJustInst = New-Object System.Windows.Controls.Button
            $btnJustInst.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#a93226"))
            $btnJustInst.Padding = [System.Windows.Thickness]::new(16,10,16,10)
            $btnJustInst.Margin  = [System.Windows.Thickness]::new(0,0,0,8)
            $btnJustInst.HorizontalContentAlignment = "Left"
            $jiSp = New-Object System.Windows.Controls.StackPanel
        $jiSp.HorizontalAlignment = "Stretch"
            $jiTitle = New-Object System.Windows.Controls.TextBlock
            $jiTitle.Text = "Nur installieren"; $jiTitle.FontWeight = "Bold"; $jiTitle.FontSize = 13
            $jiTitle.HorizontalAlignment = "Left"
        $jiTitle.Foreground = [System.Windows.Media.Brushes]::Black
            $jiDesc = New-Object System.Windows.Controls.TextBlock
            $jiDesc.Text = "Programme werden installiert. Die Bibliothek bleibt unveraendert."
            $jiDesc.FontSize = 11; $jiDesc.TextWrapping = "Wrap"
            $jiDesc.HorizontalAlignment = "Left"
        $jiDesc.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#1a1a1a"))
            [void]$jiSp.Children.Add($jiTitle); [void]$jiSp.Children.Add($jiDesc)
            $btnJustInst.Content = $jiSp
            $btnJustInst.Add_Click({ $script:instMode = "install_only"; $subWin.Close() })
            [void]$subSt.Children.Add($btnJustInst)

            # Installieren + zur Bibliothek
            $btnInstAndLib = New-Object System.Windows.Controls.Button
            $btnInstAndLib.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#a93226"))
            $btnInstAndLib.Padding = [System.Windows.Thickness]::new(16,10,16,10)
            $btnInstAndLib.Margin  = [System.Windows.Thickness]::new(0,0,0,8)
            $btnInstAndLib.HorizontalContentAlignment = "Left"
            $ilSp = New-Object System.Windows.Controls.StackPanel
        $ilSp.HorizontalAlignment = "Stretch"
            $ilTitle = New-Object System.Windows.Controls.TextBlock
            $ilTitle.Text = "Installieren und zur Bibliothek hinzufuegen"; $ilTitle.FontWeight = "Bold"; $ilTitle.FontSize = 13
            $ilTitle.HorizontalAlignment = "Left"
        $ilTitle.Foreground = [System.Windows.Media.Brushes]::Black
            $ilDesc = New-Object System.Windows.Controls.TextBlock
            $ilDesc.Text = "Programme werden installiert und zusaetzlich in die Bibliothek aufgenommen (Zusammenfuehren)."
            $ilDesc.FontSize = 11; $ilDesc.TextWrapping = "Wrap"
            $ilDesc.HorizontalAlignment = "Left"
        $ilDesc.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#1a1a1a"))
            [void]$ilSp.Children.Add($ilTitle); [void]$ilSp.Children.Add($ilDesc)
            $btnInstAndLib.Content = $ilSp
            $btnInstAndLib.Add_Click({ $script:instMode = "install_and_lib"; $subWin.Close() })
            [void]$subSt.Children.Add($btnInstAndLib)

            $btnSubCancel = New-Object System.Windows.Controls.Button
            $btnSubCancel.Content = "Abbrechen"
            $btnSubCancel.Padding = [System.Windows.Thickness]::new(16,8,16,8)
            $btnSubCancel.HorizontalAlignment = "Right"
            $btnSubCancel.Margin = [System.Windows.Thickness]::new(0,8,0,0)
            $btnSubCancel.Add_Click({ $subWin.Close() })
            [void]$subSt.Children.Add($btnSubCancel)
            $subWin.Content = $subSt
            $script:instMode = $null
            [void]$subWin.ShowDialog()
            if (-not $script:instMode) { return }

            # Programme installieren
            $toInstall = @($impPrograms | Where-Object { $_.Id -and $_.Id -notlike "URL:*" })
            if ($toInstall.Count -eq 0) {
                $sync.StatusText.Text = "Keine installierbaren Programme im Backup gefunden."
                return
            }

            # Installations-Fortschritts-Fenster (Design wie regulaerer Installer)
            $instWin = New-Object System.Windows.Window
            $instWin.Title = "Installation laeuft..."; $instWin.Width = 900; $instWin.Height = 600
            $instWin.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#161616"))
            $instWin.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
            $instWin.WindowStartupLocation = "CenterOwner"; $instWin.ResizeMode = "CanResize"
            $instWin.Owner = $sync.Window
            if ($sync.AppIcon) { $instWin.Icon = $sync.AppIcon }
            try {
                $iwH = (New-Object System.Windows.Interop.WindowInteropHelper($instWin)).EnsureHandle()
                $iwD = [int]1
                [DwmHelper]::DwmSetWindowAttribute($iwH, [DwmHelper]::DWMWA_USE_IMMERSIVE_DARK_MODE, [ref]$iwD, 4)
            } catch {}

            # Haupt-Grid: Header | Log | Footer
            $iwGrid = New-Object System.Windows.Controls.Grid
            $iwR0 = New-Object System.Windows.Controls.RowDefinition; $iwR0.Height = [System.Windows.GridLength]::Auto
            $iwR1 = New-Object System.Windows.Controls.RowDefinition; $iwR1.Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $iwR2 = New-Object System.Windows.Controls.RowDefinition; $iwR2.Height = [System.Windows.GridLength]::Auto
            [void]$iwGrid.RowDefinitions.Add($iwR0)
            [void]$iwGrid.RowDefinitions.Add($iwR1)
            [void]$iwGrid.RowDefinitions.Add($iwR2)

            # Statistik-Header
            $iwHeader = New-Object System.Windows.Controls.Border
            $iwHeader.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#1a1a1a"))
            $iwHeader.BorderBrush = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#a93226"))
            $iwHeader.BorderThickness = [System.Windows.Thickness]::new(0,0,0,2)
            $iwHeader.Padding = [System.Windows.Thickness]::new(0,16,0,16)
            [System.Windows.Controls.Grid]::SetRow($iwHeader, 0)

            $iwStatGrid = New-Object System.Windows.Controls.Grid
            $iwSC1 = New-Object System.Windows.Controls.ColumnDefinition; $iwSC1.Width = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
            $iwSep = New-Object System.Windows.Controls.ColumnDefinition; $iwSep.Width = [System.Windows.GridLength]::Auto
            $iwSC2 = New-Object System.Windows.Controls.ColumnDefinition; $iwSC2.Width = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
            [void]$iwStatGrid.ColumnDefinitions.Add($iwSC1)
            [void]$iwStatGrid.ColumnDefinitions.Add($iwSep)
            [void]$iwStatGrid.ColumnDefinitions.Add($iwSC2)

            # Erfolgreich
            $iwOkPanel = New-Object System.Windows.Controls.StackPanel
            $iwOkPanel.HorizontalAlignment = "Center"
            [System.Windows.Controls.Grid]::SetColumn($iwOkPanel, 0)
            $iwOkNum = New-Object System.Windows.Controls.TextBlock
            $iwOkNum.Text = "0"; $iwOkNum.FontSize = 40; $iwOkNum.FontWeight = "Bold"
            $iwOkNum.HorizontalAlignment = "Center"
            $iwOkNum.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#27ae60"))
            $iwOkLbl = New-Object System.Windows.Controls.TextBlock
            $iwOkLbl.Text = "Erfolgreich"; $iwOkLbl.FontSize = 13; $iwOkLbl.HorizontalAlignment = "Center"
            $iwOkLbl.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#27ae60"))
            [void]$iwOkPanel.Children.Add($iwOkNum); [void]$iwOkPanel.Children.Add($iwOkLbl)
            [void]$iwStatGrid.Children.Add($iwOkPanel)

            # Trennlinie
            $iwSepLine = New-Object System.Windows.Controls.Border
            $iwSepLine.Width = 1; $iwSepLine.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#333333"))
            $iwSepLine.Margin = [System.Windows.Thickness]::new(0,8,0,8)
            [System.Windows.Controls.Grid]::SetColumn($iwSepLine, 1)
            [void]$iwStatGrid.Children.Add($iwSepLine)

            # Fehlgeschlagen
            $iwErrPanel = New-Object System.Windows.Controls.StackPanel
            $iwErrPanel.HorizontalAlignment = "Center"
            [System.Windows.Controls.Grid]::SetColumn($iwErrPanel, 2)
            $iwErrNum = New-Object System.Windows.Controls.TextBlock
            $iwErrNum.Text = "0"; $iwErrNum.FontSize = 40; $iwErrNum.FontWeight = "Bold"
            $iwErrNum.HorizontalAlignment = "Center"
            $iwErrNum.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#e74c3c"))
            $iwErrLbl = New-Object System.Windows.Controls.TextBlock
            $iwErrLbl.Text = "Fehlgeschlagen"; $iwErrLbl.FontSize = 13; $iwErrLbl.HorizontalAlignment = "Center"
            $iwErrLbl.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#e74c3c"))
            [void]$iwErrPanel.Children.Add($iwErrNum); [void]$iwErrPanel.Children.Add($iwErrLbl)
            [void]$iwStatGrid.Children.Add($iwErrPanel)

            $iwHeader.Child = $iwStatGrid
            [void]$iwGrid.Children.Add($iwHeader)

            # Fortschrittsbalken
            $iwBar = New-Object System.Windows.Controls.ProgressBar
            $iwBar.Height = 18; $iwBar.Minimum = 0; $iwBar.Maximum = 100; $iwBar.Value = 0
            $iwBar.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#a93226"))
            $iwBar.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#2a2a2a"))
            $iwBar.BorderThickness = [System.Windows.Thickness]::new(0)
            $iwBar.Margin = [System.Windows.Thickness]::new(16,8,16,4)
            [System.Windows.Controls.Grid]::SetRow($iwBar, 1)
            [void]$iwGrid.Children.Add($iwBar)

            # Log-Bereich
            $iwLogBorder = New-Object System.Windows.Controls.Border
            $iwLogBorder.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#0d0d0d"))
            [System.Windows.Controls.Grid]::SetRow($iwLogBorder, 2)
            $iwScroll = New-Object System.Windows.Controls.ScrollViewer
            $iwScroll.VerticalScrollBarVisibility = "Auto"
            $iwLog = New-Object System.Windows.Controls.TextBlock
            $iwLog.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#cccccc"))
            $iwLog.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
            $iwLog.FontSize = 12; $iwLog.TextWrapping = "Wrap"; $iwLog.Margin = [System.Windows.Thickness]::new(16,12,16,12)
            $iwScroll.Content = $iwLog
            $iwLogBorder.Child = $iwScroll
            [void]$iwGrid.Children.Add($iwLogBorder)

            # Footer
            $iwFooter = New-Object System.Windows.Controls.Border
            $iwFooter.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#0e0e0e"))
            $iwFooter.Padding = [System.Windows.Thickness]::new(16,10,16,10)
            [System.Windows.Controls.Grid]::SetRow($iwFooter, 3)
            $iwCloseBtn = New-Object System.Windows.Controls.Button
            $iwCloseBtn.Content = "Schliessen"; $iwCloseBtn.IsEnabled = $false
            $iwCloseBtn.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#2a2a2a"))
            $iwCloseBtn.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#aaaaaa"))
            $iwCloseBtn.BorderThickness = [System.Windows.Thickness]::new(0)
            $iwCloseBtn.Padding = [System.Windows.Thickness]::new(24,8,24,8)
            $iwCloseBtn.HorizontalAlignment = "Right"; $iwCloseBtn.FontSize = 12; $iwCloseBtn.Cursor = [System.Windows.Input.Cursors]::Hand
            $iwCloseBtn.Add_Click({ $instWin.Close() })
            $iwFooter.Child = $iwCloseBtn
            [void]$iwGrid.Children.Add($iwFooter)
            $instWin.Content = $iwGrid
            & $sync.ApplyGoldStyle $instWin
            $iSync = [hashtable]::Synchronized(@{
                Lines      = [System.Collections.Generic.List[string]]::new()
                Done       = $false
                Successful = 0
                Failed     = 0
                Total      = $toInstall.Count
                CurrentPct = 0
                Log        = $iwLog
                Scroller   = $iwScroll
                CloseBtn   = $iwCloseBtn
                OkNum      = $iwOkNum
                ErrNum     = $iwErrNum
                Bar        = $iwBar
            })

            # Timer
            $iTimer = New-Object System.Windows.Threading.DispatcherTimer
            $iTimer.Interval = [TimeSpan]::FromMilliseconds(200)
            $iTimer.Add_Tick({
                if ($iSync.Lines.Count -gt 0) {
                    $iSync.Log.Text = ($iSync.Lines -join "`n")
                    $iSync.Scroller.ScrollToEnd()
                }
                $iSync.OkNum.Text  = "$($iSync.Successful)"
                $iSync.ErrNum.Text = "$($iSync.Failed)"
                if ($iSync.Total -gt 0) {
                    $doneCount = $iSync.Successful + $iSync.Failed
                    $basePct = ($doneCount / $iSync.Total) * 100
                    $withinPct = ($iSync.CurrentPct / 100) * (100 / $iSync.Total)
                    $iSync.Bar.Value = [Math]::Min(100, $basePct + $withinPct)
                }
                if ($iSync.Done) {
                    $iTimer.Stop()
                    $iSync.Bar.Value = 100
                    $iSync.CloseBtn.IsEnabled = $true
                    $iSync.CloseBtn.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#a93226"))
                    $iSync.CloseBtn.Foreground = [System.Windows.Media.Brushes]::White
                }
            })

            $instWin.Add_Loaded({
                $iTimer.Start()
                $pkgList = $toInstall
                $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
                $rs.ApartmentState = "STA"; $rs.ThreadOptions = "ReuseThread"; $rs.Open()
                $rs.SessionStateProxy.SetVariable("iSync", $iSync)
                $rs.SessionStateProxy.SetVariable("pkgList", $pkgList)
                $ps = [System.Management.Automation.PowerShell]::Create()
                $ps.Runspace = $rs
                [void]$ps.AddScript({
                    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
                    $total = $pkgList.Count
                    $iSync.Lines.Add("Starte Installation von $total Programm(en)...")
                    $iSync.Lines.Add("")
                    $num = 0
                    foreach ($pkg in $pkgList) {
                        $num++
                        $id = $pkg.Id
                        $iSync.Lines.Add(">>> [$num/$total] $id")
                        $pliIdx = $iSync.Lines.Count
                        $iSync.Lines.Add("       [....................] 0%")
                        $iSync.CurrentPct = 0
                        $synthTick = 0
                        & winget install --id $id --exact --silent --force --accept-source-agreements --accept-package-agreements 2>&1 | ForEach-Object {
                            $str = $_.ToString().Trim()
                            $str = $str -replace 'Ã¼','ue' -replace 'Ã¶','oe' -replace 'Ã¤','ae' -replace 'ÃŸ','ss' -replace 'Ãœ','Ue' -replace 'Ã–','Oe' -replace 'Ã„','Ae'
                            if ($str -eq "" -or ($str.Length -le 2 -and ($str -eq '-' -or $str -eq '\' -or $str -eq '|' -or $str -eq '/'))) { return }
                            if ($str -match "^(\d+)%$") {
                                $pct = [int]$Matches[1]
                                $bar = ('#' * [int]($pct / 5)).PadRight(20, '.')
                                $iSync.Lines[$pliIdx - 1] = "       [$bar] $pct%"
                                $iSync.CurrentPct = $pct
                                return
                            }
                            if ($str -match "[\u2580-\u259F\u2588]" -or $str -match "\u00E2[\u2010-\u203A\u02C6-\u02DC\u0161\u017E\u0192\u2122]") {
                                if ($str -match "(\d+)%") {
                                    $pct = [int]$Matches[1]
                                    $bar = ('#' * [int]($pct / 5)).PadRight(20, '.')
                                    $iSync.Lines[$pliIdx - 1] = "       [$bar] $pct%"
                                    $iSync.CurrentPct = $pct
                                }
                                return
                            }
                            $iSync.Lines.Add("        $str")
                        }
                        if ($LASTEXITCODE -eq 0) {
                            $iSync.Successful++
                            $iSync.Lines[$pliIdx - 1] = "       [####################] 100%"
                            $iSync.Lines.Add("[OK]   $id erfolgreich installiert")
                        } else {
                            $iSync.Failed++
                            $iSync.Lines[$pliIdx - 1] = "       [--------------------]"
                            $iSync.Lines.Add("[ERR]  $id – Installation fehlgeschlagen")
                        }
                        $iSync.Lines.Add("")
                    }
                    $iSync.Lines.Add("Abgeschlossen: $($iSync.Successful) erfolgreich, $($iSync.Failed) fehlgeschlagen.")
                    $iSync.Done = $true
                })
                [void]$ps.BeginInvoke()
            }.GetNewClosure())

            [void]$instWin.ShowDialog()

            # Bibliothek neu laden (unabhaengig vom Modus)
            $sync.ProgramList.Children.Clear()
            $sync.AllProgramItems.Clear()
            $sync.AllEntries.Clear()
            $sync.SelectedIds.Clear()
            $sync.AllCategories = @($sync.AllCategories | ForEach-Object {
                @{ Name = $_.Name; Items = @($_.Items | ForEach-Object { @{ Name = $_.Name; Id = $_.Id; Desc = $_.Desc } }) }
            })

            try {
                if (Test-Path $sync.CustomCatalogPath) {
                    $ccRaw = Get-Content $sync.CustomCatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($ccRaw) {
                        foreach ($cp in $ccRaw) {

                            $itm = @{ Name = $cp.Name; Id = $cp.Id; Desc = if ($cp.Desc) { $cp.Desc } else { $cp.Name } }
                            $ac = $null
                            if ($sync.CustomAssignments.ContainsKey($cp.Id)) {
                                $ac = $sync.CustomAssignments[$cp.Id]
                            }
                            if (-not $ac) { $ac = Get-AppstalloCategoryFor -Name $cp.Name -Id $cp.Id }
                            $tc = $sync.AllCategories | Where-Object { $_.Name -eq $ac }
                            if ($tc) { $tc.Items += $itm } else { $sync.AllCategories += @{ Name = $ac; Items = @($itm) } }
                        }
                        foreach ($cat in $sync.AllCategories) { $cat.Items = @($cat.Items | Sort-Object { $_.Name }) }
                        $dlCat = $sync.AllCategories | Where-Object { $_.Name -eq "Direktdownload" }
                        if ($dlCat) { $sync.AllCategories = @($sync.AllCategories | Where-Object { $_.Name -ne "Direktdownload" }) + @($dlCat) }
                    }
                }
            } catch {}
            try {
                if (Test-Path $sync.CustomLinksPath) {
                    $lnkRaw = Get-Content $sync.CustomLinksPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($lnkRaw) {
                        $dlc = $sync.AllCategories | Where-Object { $_.Name -eq "Direktdownload" }
                        if ($dlc) {
                            foreach ($lnk in $lnkRaw) {
                                if ($true) { $dlc.Items += @{ Name = $lnk.Name; Id = $lnk.Id; Desc = $lnk.Desc } }
                            }
                        }
                    }
                }
            } catch {}
            $sync.StatusText.Text = "$($iSync.Successful) Programm(e) installiert, $($iSync.Failed) fehlgeschlagen. Bibliothek wird aktualisiert..."

            # InstalledIds per winget list neu einlesen, dann UI neu aufbauen
            $sync.InstalledIds.Clear()
            $sync.InstalledVersions.Clear()
            $sync.InstalledNames.Clear()
            $rsScan = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
            $rsScan.ApartmentState = "STA"; $rsScan.ThreadOptions = "ReuseThread"; $rsScan.Open()
            $rsScan.SessionStateProxy.SetVariable("sync", $sync)
            $psScan = [System.Management.Automation.PowerShell]::Create()
            $psScan.Runspace = $rsScan
            [void]$psScan.AddScript({
                try {
                    $psi2 = New-Object System.Diagnostics.ProcessStartInfo
                    $psi2.FileName = "winget"; $psi2.Arguments = "list --accept-source-agreements"
                    $psi2.UseShellExecute = $false; $psi2.RedirectStandardOutput = $true
                    $psi2.RedirectStandardError = $true; $psi2.CreateNoWindow = $true
                    $psi2.StandardOutputEncoding = [System.Text.Encoding]::UTF8
                    $proc2 = [System.Diagnostics.Process]::Start($psi2)
                    $stdout2 = $proc2.StandardOutput.ReadToEnd(); $proc2.WaitForExit()
                    $raw2 = $stdout2 -split "`r?`n"
                    $hIdx = -1
                    for ($i = 0; $i -lt $raw2.Count; $i++) {
                        if ($raw2[$i] -match "(?i)Name\s+ID?" -and $raw2[$i] -match "(?i)Version") { $hIdx = $i; break }
                    }
                    if ($hIdx -ge 0) {
                        $hdr = $raw2[$hIdx]
                        $nPos = $hdr.ToLower().IndexOf("name"); if ($nPos -lt 0) { $nPos = 0 }
                        $iPos = $hdr.ToLower().IndexOf(" id", $nPos) + 1; if ($iPos -lt 1) { $iPos = $nPos + 42 }
                        $vPos = $hdr.ToLower().IndexOf("version", $nPos); if ($vPos -lt 1) { $vPos = $nPos + 84 }
                        $idSt = $iPos - $nPos; $vSt = $vPos - $nPos
                        for ($i = $hIdx + 2; $i -lt $raw2.Count; $i++) {
                            $ln = $raw2[$i]
                            if ($ln.Trim() -eq "" -or $ln.Length -le $idSt) { continue }
                            $idR = $ln.Substring($idSt, [Math]::Min($vSt - $idSt, $ln.Length - $idSt)).Trim()
                            if ($idR -match '^[A-Za-z0-9][A-Za-z0-9._+\-]+$') {
                                [void]$sync.InstalledIds.Add($idR)
                                $nmR = $ln.Substring(0, [Math]::Min($idSt, $ln.Length)).Trim()
                                if ($nmR) { $sync.InstalledNames[$idR] = $nmR }
                                if ($ln.Length -gt $vSt) {
                                    $vTok = ($ln.Substring($vSt).Trim() -split '\s+')[0]
                                    if ($vTok -and $vTok.Length -gt 1) { $sync.InstalledVersions[$idR] = $vTok }
                                }
                            }
                        }
                    }
                } catch {} finally { $sync.RescanDone = $true }
            })
            $sync.RescanDone = $false
            [void]$psScan.BeginInvoke()

            # Poll-Timer: wartet auf Scan-Ende, baut dann UI neu
            $rTimer = New-Object System.Windows.Threading.DispatcherTimer
            $rTimer.Interval = [TimeSpan]::FromMilliseconds(400)
            $rTimer.Add_Tick({
                if (-not $sync.RescanDone) { return }
                $rTimer.Stop()
                & $sync.AddInstalledToLibrary
                & $sync.BuildUI
                & $sync.UpdateCount
                $instC = ($sync.AllCategories | ForEach-Object { $_.Items } | Where-Object { $sync.InstalledIds.Contains($_.Id) } | Measure-Object).Count
                $totC  = ($sync.AllCategories | ForEach-Object { $_.Items } | Where-Object { $_.Id -notlike "URL:*" } | Measure-Object).Count
                $urlC  = ($sync.AllCategories | ForEach-Object { $_.Items } | Where-Object { $_.Id -like "URL:*"  } | Measure-Object).Count
                $sync.StatusText.Text = "$totC Programme ueber winget verfuegbar ($urlC zusaetzliche Direktdownloads) | $instC bereits installiert"
            }.GetNewClosure())
            $rTimer.Start()

            # Falls "Installieren und zur Bibliothek" gewählt: Merge durchfuehren
            if ($script:instMode -eq "install_and_lib") {
                $script:importMode = "merge"
                # Weiter mit normalem Merge-Code unten
            } else {
                # Nur installiert, fertig
                $sync.StatusText.Text = "$($iSync.Successful) Programm(e) installiert, $($iSync.Failed) fehlgeschlagen."
                return
            }
        }

        $dir = Split-Path $sync.CustomCatalogPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        # URL-Eintraege aus Programs nach Links verschieben (Fallback fuer alte Backups)
        $urlFromProgs = @($impPrograms | Where-Object { $_.Id -like "URL:*" })
        $impPrograms  = @($impPrograms | Where-Object { $_.Id -notlike "URL:*" })
        $impLinks     = @($impLinks) + $urlFromProgs

        # Alle importierten Programme und Links als Custom speichern
        $customProgs = @($impPrograms)
        $customLnks  = @($impLinks)

        if ($script:importMode -eq "overwrite") {
            if ($customProgs.Count -gt 0) {
                $customProgs | ConvertTo-Json -Depth 10 | Set-Content -Path $sync.CustomCatalogPath -Encoding UTF8
            } elseif (Test-Path $sync.CustomCatalogPath) { Remove-Item $sync.CustomCatalogPath -Force }

            if ($customLnks.Count -gt 0) {
                $customLnks | ConvertTo-Json -Depth 10 | Set-Content -Path $sync.CustomLinksPath -Encoding UTF8
            } elseif (Test-Path $sync.CustomLinksPath) { Remove-Item $sync.CustomLinksPath -Force }

            # Benutzerdefinierte Kategorien und Zuordnungen ueberschreiben
            $sync.CustomCatNames.Clear()
            foreach ($cn in $impCatNames) { [void]$sync.CustomCatNames.Add($cn) }
            if ($impCatNames.Count -gt 0) {
                $impCatNames | ConvertTo-Json | Set-Content -Path $sync.CustomCatNamesPath -Encoding UTF8
            } elseif (Test-Path $sync.CustomCatNamesPath) { Remove-Item $sync.CustomCatNamesPath -Force }

            $sync.CustomAssignments.Clear()
            if ($impAssign) {
                & $sync.MergeAssignFromImport $impAssign
                # Als PSCustomObject mit benannten Properties speichern
                $assignSave = [PSCustomObject]@{}
                foreach ($k in $sync.CustomAssignments.Keys) {
                    $assignSave | Add-Member -NotePropertyName $k -NotePropertyValue $sync.CustomAssignments[$k]
                }
                $assignSave | ConvertTo-Json -Depth 5 | Set-Content -Path $sync.CustomAssignPath -Encoding UTF8
            } elseif (Test-Path $sync.CustomAssignPath) { Remove-Item $sync.CustomAssignPath -Force }

        } else {
            # Merge: bereinigte Ausschlussliste speichern (importierte IDs entfernt)
            # Zusammenfuehren (Merge)
            # Custom Catalog
            $existCat = @()
            try {
                if (Test-Path $sync.CustomCatalogPath) {
                    $r = Get-Content $sync.CustomCatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($r) { $existCat = @($r) }
                }
            } catch {}
            $existIds = @{}; foreach ($e in $existCat) { $existIds[$e.Id] = $true }
            foreach ($imp in $customProgs) {
                if (-not $existIds.ContainsKey($imp.Id)) {
                    $existCat += $imp; $existIds[$imp.Id] = $true
                }
            }
            if ($existCat.Count -gt 0) {
                $existCat | ConvertTo-Json -Depth 10 | Set-Content -Path $sync.CustomCatalogPath -Encoding UTF8
            }

            # Custom Links
            $existLinks = @()
            try {
                if (Test-Path $sync.CustomLinksPath) {
                    $r = Get-Content $sync.CustomLinksPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($r) { $existLinks = @($r) }
                }
            } catch {}
            $existLinkIds = @{}; foreach ($e in $existLinks) { $existLinkIds[$e.Id] = $true }
            foreach ($imp in $customLnks) {
                if (-not $existLinkIds.ContainsKey($imp.Id)) {
                    $existLinks += $imp; $existLinkIds[$imp.Id] = $true
                }
            }
            if ($existLinks.Count -gt 0) {
                $existLinks | ConvertTo-Json -Depth 10 | Set-Content -Path $sync.CustomLinksPath -Encoding UTF8

            # Benutzerdefinierte Kategorien zusammenfuehren
            foreach ($cn in $impCatNames) {
                if (-not $sync.CustomCatNames.Contains($cn)) { [void]$sync.CustomCatNames.Add($cn) }
            }
            if ($sync.CustomCatNames.Count -gt 0) {
                @($sync.CustomCatNames) | ConvertTo-Json | Set-Content -Path $sync.CustomCatNamesPath -Encoding UTF8
            }

            # Zuordnungen zusammenfuehren (importierte ueberschreiben bestehende bei Konflikten)
            if ($impAssign) {
                & $sync.MergeAssignFromImport $impAssign
                $obj = [PSCustomObject]@{}
                foreach ($k in $sync.CustomAssignments.Keys) { $obj | Add-Member -NotePropertyName $k -NotePropertyValue $sync.CustomAssignments[$k] }
                $obj | ConvertTo-Json -Depth 5 | Set-Content -Path $sync.CustomAssignPath -Encoding UTF8
            }
            }


        }

        # Bestaetigungs-Fenster mit Neustart-Hinweis
        $doneWin = New-Object System.Windows.Window
        $doneWin.Title = "Import erfolgreich"; $doneWin.Width = 440; $doneWin.SizeToContent = "Height"
        $doneWin.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#161616"))
        $doneWin.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
        $doneWin.WindowStartupLocation = "CenterOwner"; $doneWin.ResizeMode = "NoResize"
        $doneWin.Owner = $sync.Window
        if ($sync.AppIcon) { $doneWin.Icon = $sync.AppIcon }
        try {
            $dH = (New-Object System.Windows.Interop.WindowInteropHelper($doneWin)).EnsureHandle()
            $dD = [int]1
            [DwmHelper]::DwmSetWindowAttribute($dH, [DwmHelper]::DWMWA_USE_IMMERSIVE_DARK_MODE, [ref]$dD, 4)
        } catch {}
        $dSt = New-Object System.Windows.Controls.StackPanel
        $dSt.Margin = [System.Windows.Thickness]::new(24,24,24,24)
        $modeText = if ($script:importMode -eq "overwrite") { "ueberschrieben" } else { "zusammengefuehrt" }
        $dTx = New-Object System.Windows.Controls.TextBlock
        $dTx.Text = "Import erfolgreich – Bibliothek wurde $modeText.`n`nDie Bibliothek wird jetzt neu geladen."
        $dTx.FontSize = 13; $dTx.TextWrapping = "Wrap"
        $dTx.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#cccccc"))
        $dTx.Margin = [System.Windows.Thickness]::new(0,0,0,18)
        [void]$dSt.Children.Add($dTx)
        $dBtn = New-Object System.Windows.Controls.Button
        $dBtn.Content = "OK"; $dBtn.HorizontalAlignment = "Right"
        $dBtn.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#a93226"))
        $dBtn.Foreground = [System.Windows.Media.Brushes]::White
        $dBtn.BorderThickness = [System.Windows.Thickness]::new(0)
        $dBtn.Padding = [System.Windows.Thickness]::new(24,8,24,8)
        $dBtn.FontSize = 12; $dBtn.Cursor = [System.Windows.Input.Cursors]::Hand
        $dBtn.Add_Click({ $doneWin.Close() })
        [void]$dSt.Children.Add($dBtn)
        $doneWin.Content = $dSt
        & $sync.ApplyGoldStyle $doneWin
        [void]$doneWin.ShowDialog()

        # Bibliothek neu laden: Kategorien zuruecksetzen
        $sync.ProgramList.Children.Clear()
        $sync.AllProgramItems.Clear()
        $sync.AllEntries.Clear()
        $sync.SelectedIds.Clear()

        # Leere Bibliothek + benutzerdefinierte Kategorien
        $sync.AllCategories = @(
            @{ Name = "Direktdownload"; Items = @() }
        )
        foreach ($ucn in $sync.CustomCatNames) {
            $existing = $sync.AllCategories | Where-Object { $_.Name -eq $ucn }
            if (-not $existing) {
                $sync.AllCategories += @{ Name = $ucn; Items = @() }
            }
        }

        # Installierte Programme einsortieren (beachtet CustomAssignments)
        & $sync.AddInstalledToLibrary


        # Custom-Katalog neu laden
        $customPrograms = @()
        try {
            if (Test-Path $sync.CustomCatalogPath) {
                $customRaw = Get-Content $sync.CustomCatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($customRaw) { $customPrograms = @($customRaw) }
            }
        } catch {}
        if ($customPrograms.Count -gt 0) {
            foreach ($cp in $customPrograms) {
                $itemEntry = @{ Name = $cp.Name; Id = $cp.Id; Desc = if ($cp.Desc) { $cp.Desc } else { $cp.Name } }
                # Benutzerdefinierte Zuordnung hat Vorrang
                $assignedCat = $null
                if ($sync.CustomAssignments.ContainsKey($cp.Id)) {
                    $assignedCat = $sync.CustomAssignments[$cp.Id]
                }
                if (-not $assignedCat) {
                    $assignedCat = Get-AppstalloCategoryFor -Name $cp.Name -Id $cp.Id
                }
                $targetCat = $sync.AllCategories | Where-Object { $_.Name -eq $assignedCat }
                if ($targetCat) {
                    $existingIds = @($targetCat.Items | ForEach-Object { $_.Id })
                    if ($cp.Id -notin $existingIds) { $targetCat.Items += $itemEntry }
                } else {
                    $sync.AllCategories += @{ Name = $assignedCat; Items = @($itemEntry) }
                }
            }
            foreach ($cat in $sync.AllCategories) {
                $cat.Items = @($cat.Items | Sort-Object { $_.Name })
            }
            $normalCats  = @($sync.AllCategories | Where-Object { $_.Name -ne "Direktdownload" -and $_.Name -ne "Sonstige Programme" } | Sort-Object { $_.Name })
            $sonstigeCat = @($sync.AllCategories | Where-Object { $_.Name -eq "Sonstige Programme" })
            $dlCat       = @($sync.AllCategories | Where-Object { $_.Name -eq "Direktdownload" })
            $sync.AllCategories = @($normalCats) + @($sonstigeCat) + @($dlCat)
        }

        # Custom-Links neu laden
        try {
            if (Test-Path $sync.CustomLinksPath) {
                $linksRaw = Get-Content $sync.CustomLinksPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($linksRaw) {
                    $dlCat2 = $sync.AllCategories | Where-Object { $_.Name -eq "Direktdownload" }
                    if ($dlCat2) {
                        foreach ($lnk in $linksRaw) {
                            if ($true) {
                                $existingIds2 = @($dlCat2.Items | ForEach-Object { $_.Id })
                                if ($lnk.Id -notin $existingIds2) {
                                    $dlCat2.Items += @{ Name = $lnk.Name; Id = $lnk.Id; Desc = $lnk.Desc }
                                }
                            }
                        }
                    }
                }
            }
        } catch {}

        # UI neu aufbauen
        & $sync.BuildUI
        & $sync.UpdateCount
        $sync.StatusText.Text = "Bibliothek wurde neu geladen."
    })

    # ── Liste ausgeben Handler ────────────────────────────────────────────────
    $miList.Add_Click({
        $loWin = New-Object System.Windows.Window
        $loWin.Title = "Liste ausgeben"
        $loWin.Width = 420; $loWin.SizeToContent = "Height"
        $loWin.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#161616"))
        $loWin.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
        $loWin.WindowStartupLocation = "CenterOwner"; $loWin.ResizeMode = "NoResize"
        $loWin.Owner = $sync.Window
        if ($sync.AppIcon) { $loWin.Icon = $sync.AppIcon }
        try {
            $loH = (New-Object System.Windows.Interop.WindowInteropHelper($loWin)).EnsureHandle()
            $loD = [int]1
            [DwmHelper]::DwmSetWindowAttribute($loH, [DwmHelper]::DWMWA_USE_IMMERSIVE_DARK_MODE, [ref]$loD, 4)
        } catch {}

        $loSt = New-Object System.Windows.Controls.StackPanel
        $loSt.Margin = [System.Windows.Thickness]::new(24,24,24,24)
        $loTitle = New-Object System.Windows.Controls.TextBlock
        $loTitle.Text = "In welchem Format soll die Liste ausgegeben werden?"
        $loTitle.FontSize = 14; $loTitle.FontWeight = "Bold"
        $loTitle.Foreground = [System.Windows.Media.Brushes]::White
        $loTitle.Margin = [System.Windows.Thickness]::new(0,0,0,20)
        $loTitle.TextWrapping = "Wrap"
        [void]$loSt.Children.Add($loTitle)

        # CSV Button
        $btnCsv = New-Object System.Windows.Controls.Button
        $btnCsv.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#a93226"))
        $btnCsv.Padding = [System.Windows.Thickness]::new(16,10,16,10)
        $btnCsv.Margin = [System.Windows.Thickness]::new(0,0,0,8)
        $btnCsv.HorizontalContentAlignment = "Left"
        $csvSp = New-Object System.Windows.Controls.StackPanel
        $csvSp.HorizontalAlignment = "Stretch"
        $csvTitle = New-Object System.Windows.Controls.TextBlock
        $csvTitle.Text = "Als CSV exportieren"; $csvTitle.FontWeight = "Bold"; $csvTitle.FontSize = 13
        $csvTitle.HorizontalAlignment = "Left"
        $csvTitle.Foreground = [System.Windows.Media.Brushes]::Black
        $csvDesc = New-Object System.Windows.Controls.TextBlock
        $csvDesc.Text = "Speichert die gesamte Programmliste als CSV-Datei (oeffenbar mit Excel, LibreOffice etc.)."
        $csvDesc.FontSize = 11; $csvDesc.TextWrapping = "Wrap"
        $csvDesc.HorizontalAlignment = "Left"
        $csvDesc.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#1a1a1a"))
        [void]$csvSp.Children.Add($csvTitle); [void]$csvSp.Children.Add($csvDesc)
        $btnCsv.Content = $csvSp
        $btnCsv.Add_Click({
            $loWin.Close()
            Add-Type -AssemblyName System.Windows.Forms
            $dlg = New-Object System.Windows.Forms.SaveFileDialog
            $dlg.Title = "Liste als CSV speichern"
            $dlg.Filter = "CSV-Datei (*.csv)|*.csv"
            $dlg.FileName = "Appstallo-Programmliste.csv"
            if ($dlg.ShowDialog() -ne "OK") { return }
            & $sync.FetchAndOutput "csv" $dlg.FileName
        })
        [void]$loSt.Children.Add($btnCsv)

        # Drucken Button
        $btnPrint = New-Object System.Windows.Controls.Button
        $btnPrint.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#a93226"))
        $btnPrint.Padding = [System.Windows.Thickness]::new(16,10,16,10)
        $btnPrint.Margin = [System.Windows.Thickness]::new(0,0,0,8)
        $btnPrint.HorizontalContentAlignment = "Left"
        $prtSp = New-Object System.Windows.Controls.StackPanel
        $prtSp.HorizontalAlignment = "Stretch"
        $prtTitle = New-Object System.Windows.Controls.TextBlock
        $prtTitle.Text = "Druckansicht oeffnen"; $prtTitle.FontWeight = "Bold"; $prtTitle.FontSize = 13
        $prtTitle.HorizontalAlignment = "Left"
        $prtTitle.Foreground = [System.Windows.Media.Brushes]::Black
        $prtDesc = New-Object System.Windows.Controls.TextBlock
        $prtDesc.Text = "Erzeugt eine formatierte HTML-Seite und oeffnet sie im Browser zum Drucken."
        $prtDesc.FontSize = 11; $prtDesc.TextWrapping = "Wrap"
        $prtDesc.HorizontalAlignment = "Left"
        $prtDesc.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString("#1a1a1a"))
        [void]$prtSp.Children.Add($prtTitle); [void]$prtSp.Children.Add($prtDesc)
        $btnPrint.Content = $prtSp
        $btnPrint.Add_Click({
            $loWin.Close()
            & $sync.FetchAndOutput "html" $null
        })
        [void]$loSt.Children.Add($btnPrint)

        # Abbrechen
        $loCancel = New-Object System.Windows.Controls.Button
        $loCancel.Content = "Abbrechen"
        $loCancel.Padding = [System.Windows.Thickness]::new(16,8,16,8)
        $loCancel.HorizontalAlignment = "Right"
        $loCancel.Margin = [System.Windows.Thickness]::new(0,8,0,0)
        $loCancel.Add_Click({ $loWin.Close() })
        [void]$loSt.Children.Add($loCancel)

        $loWin.Content = $loSt
        & $sync.ApplyGoldStyle $loWin
        [void]$loWin.ShowDialog()
    })

    # ── Startup-Timer ─────────────────────────────────────────────────────────
    $startupTimer = New-Object System.Windows.Threading.DispatcherTimer
    $startupTimer.Interval = [TimeSpan]::FromMilliseconds(100)
    $sync.StartupTimer = $startupTimer
    $startupTimer.Add_Tick({
        try {
            $sync.StartupTimer.Stop()
            & $sync.StartScan
        } catch {
            $sync.StartupTimer.Stop()
            "STARTUP-TIMER ERROR: $_" | Out-File $logPath -Encoding UTF8 -Append
        }
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
    $_ | Out-File -FilePath $logPath -Encoding UTF8 -Append
    [System.Windows.MessageBox]::Show(
        "Unerwarteter Fehler:`n`n$_`n`nDetails in:`n$logPath",
        "WingetInstaller - Fehler", "OK", "Error") | Out-Null
}
