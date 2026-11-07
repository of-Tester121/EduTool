# EduUtil - Windows tweak / install / cleanup toolbox
# Run (admin or not, it self-elevates):
#   irm "https://raw.githubusercontent.com/YOURUSER/EduUtil/main/EduUtil.ps1" | iex

$RepoUrl = 'https://raw.githubusercontent.com/YOURUSER/EduUtil/main/EduUtil.ps1'   # <- change this

# ---------- self-elevate ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $cmd = if ($PSCommandPath) { "& '$PSCommandPath'" } else { "irm '$RepoUrl' | iex" }
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command $cmd"
    return
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ---------- helpers ----------
function Set-Reg($Path, $Name, $Value, $Type = 'DWord') {
    if (-not (Test-Path $Path)) { New-Item $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
}

function Pump {
    $window.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background)
}

function Log($msg) {
    $txtLog.AppendText("[$(Get-Date -Format HH:mm:ss)] $msg`r`n")
    $txtLog.ScrollToEnd()
    Pump
}

$script:rpDone = $false
function New-SafeRestorePoint {
    if ($script:rpDone) { return }
    Log 'Creating restore point...'
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
        Checkpoint-Computer -Description 'EduUtil' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Log 'Restore point created.'
    } catch {
        Log "Restore point skipped (Windows only allows one per 24h by default): $($_.Exception.Message)"
    }
    $script:rpDone = $true
}

# ---------- tweaks ----------
$Tweaks = @(
    @{ Name = 'Disable telemetry'
       Desc = 'Turns off diagnostic data collection and the DiagTrack service.'
       Apply = {
           Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
           Set-Service DiagTrack -StartupType Disabled -ErrorAction SilentlyContinue
           Stop-Service DiagTrack -Force -ErrorAction SilentlyContinue
       }
       Undo = {
           Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' -ErrorAction SilentlyContinue
           Set-Service DiagTrack -StartupType Automatic -ErrorAction SilentlyContinue
           Start-Service DiagTrack -ErrorAction SilentlyContinue
       } },

    @{ Name = 'Disable activity history'
       Desc = 'Stops Windows logging and uploading your activity timeline.'
       Apply = {
           $p = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
           Set-Reg $p 'EnableActivityFeed' 0; Set-Reg $p 'PublishUserActivities' 0; Set-Reg $p 'UploadUserActivities' 0
       }
       Undo = {
           $p = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
           'EnableActivityFeed','PublishUserActivities','UploadUserActivities' | ForEach-Object { Remove-ItemProperty $p $_ -ErrorAction SilentlyContinue }
       } },

    @{ Name = 'Disable consumer features / suggested apps'
       Desc = 'Stops Windows auto-installing promoted apps (Candy Crush etc).'
       Apply = { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1 }
       Undo  = { Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' -ErrorAction SilentlyContinue } },

    @{ Name = 'Disable Bing web results in Start search'
       Desc = 'Start menu search only searches your PC.'
       Apply = {
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
           Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
       }
       Undo = {
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 1
           Remove-ItemProperty 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' -ErrorAction SilentlyContinue
       } },

    @{ Name = 'Disable Copilot'
       Desc = 'Turns off Windows Copilot via policy.'
       Apply = { Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1 }
       Undo  = { Remove-ItemProperty 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' -ErrorAction SilentlyContinue } },

    @{ Name = 'Ultimate Performance power plan'
       Desc = 'Adds and activates the hidden Ultimate Performance plan. Undo switches back to Balanced.'
       Apply = {
           $out = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61
           if ("$out" -match '([0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12})') { powercfg -setactive $Matches[1] }
       }
       Undo = { powercfg -setactive 381b4222-f694-41f0-9685-ff5bb260df2e } },

    @{ Name = 'Disable Game DVR / Xbox Game Bar capture'
       Desc = 'Removes background recording overhead in games.'
       Apply = {
           Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
       }
       Undo = {
           Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 1
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 1
       } },

    @{ Name = 'Disable mouse acceleration'
       Desc = 'Flat 1:1 mouse movement. Needs sign-out to fully apply.'
       Apply = {
           $p = 'HKCU:\Control Panel\Mouse'
           Set-Reg $p 'MouseSpeed' '0' 'String'; Set-Reg $p 'MouseThreshold1' '0' 'String'; Set-Reg $p 'MouseThreshold2' '0' 'String'
       }
       Undo = {
           $p = 'HKCU:\Control Panel\Mouse'
           Set-Reg $p 'MouseSpeed' '1' 'String'; Set-Reg $p 'MouseThreshold1' '6' 'String'; Set-Reg $p 'MouseThreshold2' '10' 'String'
       } },

    @{ Name = 'Show file extensions and hidden files'
       Desc = 'Explorer shows .exe/.txt etc and hidden files.'
       Apply = {
           $p = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
           Set-Reg $p 'HideFileExt' 0; Set-Reg $p 'Hidden' 1
       }
       Undo = {
           $p = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
           Set-Reg $p 'HideFileExt' 1; Set-Reg $p 'Hidden' 2
       } },

    @{ Name = 'Classic right-click menu (Windows 11)'
       Desc = 'Brings back the full context menu without "Show more options".'
       Apply = { reg add 'HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' /f /ve | Out-Null }
       Undo  = { reg delete 'HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}' /f | Out-Null } },

    @{ Name = 'Remove startup delay'
       Desc = 'Startup apps launch immediately after login instead of waiting.'
       Apply = { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 0 }
       Undo  = { Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' -ErrorAction SilentlyContinue } },

    @{ Name = 'Disable transparency effects'
       Desc = 'Slightly lighter on the GPU.'
       Apply = { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0 }
       Undo  = { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 1 } },

    @{ Name = 'Disable hibernation'
       Desc = 'Frees disk space (size of your RAM) and disables Fast Startup.'
       Apply = { powercfg -h off }
       Undo  = { powercfg -h on } }
)

# ---------- apps (winget IDs) ----------
$Apps = [ordered]@{
    'Brave'            = 'Brave.Brave'
    'Firefox'          = 'Mozilla.Firefox'
    'Google Chrome'    = 'Google.Chrome'
    '7-Zip'            = '7zip.7zip'
    'VLC'              = 'VideoLAN.VLC'
    'Discord'          = 'Discord.Discord'
    'Steam'            = 'Valve.Steam'
    'Spotify'          = 'Spotify.Spotify'
    'OBS Studio'       = 'OBSProject.OBSStudio'
    'VS Code'          = 'Microsoft.VisualStudioCode'
    'Git'              = 'Git.Git'
    'Python 3'         = 'Python.Python.3.12'
    'Notepad++'        = 'Notepad++.Notepad++'
    'PowerToys'        = 'Microsoft.PowerToys'
    'Everything'       = 'voidtools.Everything'
    'HWiNFO'           = 'REALiX.HWiNFO'
}

# ---------- GUI ----------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="EduUtil" Width="920" Height="660" WindowStartupLocation="CenterScreen"
        Background="#14161B" FontFamily="Segoe UI" Foreground="#E6E6E6">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Background" Value="#2B6BFF"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="14,8"/>
      <Setter Property="Margin" Value="0,0,8,0"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#E6E6E6"/>
      <Setter Property="Margin" Value="0,5"/>
      <Setter Property="FontSize" Value="14"/>
    </Style>
  </Window.Resources>
  <Grid Margin="12">
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="160"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>

    <StackPanel Grid.Column="0" Margin="0,0,12,0">
      <TextBlock Text="EduUtil" FontSize="26" FontWeight="Bold" Margin="0,0,0,18"/>
      <Button Name="navTweaks"  Content="Tweaks"  Margin="0,0,0,8" HorizontalContentAlignment="Left"/>
      <Button Name="navInstall" Content="Install"  Margin="0,0,0,8" HorizontalContentAlignment="Left"/>
      <Button Name="navClean"   Content="Cleanup" Margin="0,0,0,8" HorizontalContentAlignment="Left"/>
    </StackPanel>

    <Grid Grid.Column="1">
      <Grid.RowDefinitions>
        <RowDefinition Height="*"/>
        <RowDefinition Height="160"/>
      </Grid.RowDefinitions>

      <Grid Grid.Row="0">
        <DockPanel Name="pgTweaks">
          <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,8,0,8">
            <Button Name="btnApply" Content="Apply selected"/>
            <Button Name="btnUndo"  Content="Undo selected" Background="#444A55"/>
            <Button Name="btnRP"    Content="Make restore point" Background="#444A55"/>
          </StackPanel>
          <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Name="tweakList"/></ScrollViewer>
        </DockPanel>

        <DockPanel Name="pgInstall" Visibility="Collapsed">
          <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,8,0,8">
            <Button Name="btnInstall" Content="Install selected"/>
          </StackPanel>
          <ScrollViewer VerticalScrollBarVisibility="Auto"><WrapPanel Name="appList"/></ScrollViewer>
        </DockPanel>

        <StackPanel Name="pgClean" Visibility="Collapsed">
          <Button Name="btnTemp"  Content="Clean temp files"          Margin="0,0,0,10" HorizontalAlignment="Left"/>
          <Button Name="btnBin"   Content="Empty Recycle Bin"         Margin="0,0,0,10" HorizontalAlignment="Left"/>
          <Button Name="btnDns"   Content="Flush DNS cache"           Margin="0,0,0,10" HorizontalAlignment="Left"/>
          <Button Name="btnSfc"   Content="Repair Windows (SFC + DISM)" Margin="0,0,0,10" HorizontalAlignment="Left"/>
        </StackPanel>
      </Grid>

      <TextBox Name="txtLog" Grid.Row="1" IsReadOnly="True" Background="#0D0F13" Foreground="#9BE59B"
               FontFamily="Consolas" FontSize="12" BorderThickness="0" Padding="8"
               VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"/>
    </Grid>
  </Grid>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Parse($xaml)
foreach ($n in 'navTweaks','navInstall','navClean','pgTweaks','pgInstall','pgClean','tweakList','appList',
               'btnApply','btnUndo','btnRP','btnInstall','btnTemp','btnBin','btnDns','btnSfc','txtLog') {
    Set-Variable -Name $n -Value $window.FindName($n)
}

# fill tweak + app lists
foreach ($t in $Tweaks) {
    $cb = New-Object Windows.Controls.CheckBox
    $cb.Content = $t.Name; $cb.ToolTip = $t.Desc; $cb.Tag = $t
    [void]$tweakList.Children.Add($cb)
    $desc = New-Object Windows.Controls.TextBlock
    $desc.Text = $t.Desc; $desc.Foreground = '#8A90A0'; $desc.FontSize = 11
    $desc.Margin = '24,-2,0,4'; $desc.TextWrapping = 'Wrap'
    [void]$tweakList.Children.Add($desc)
}
foreach ($k in $Apps.Keys) {
    $cb = New-Object Windows.Controls.CheckBox
    $cb.Content = $k; $cb.Tag = $Apps[$k]; $cb.Width = 200
    [void]$appList.Children.Add($cb)
}

function Show-Page($name) {
    foreach ($p in 'pgTweaks','pgInstall','pgClean') {
        (Get-Variable $p).Value.Visibility = if ($p -eq $name) { 'Visible' } else { 'Collapsed' }
    }
}
$navTweaks.Add_Click({ Show-Page 'pgTweaks' })
$navInstall.Add_Click({ Show-Page 'pgInstall' })
$navClean.Add_Click({ Show-Page 'pgClean' })

function Run-Tweaks($mode) {
    $picked = $tweakList.Children | Where-Object { $_ -is [Windows.Controls.CheckBox] -and $_.IsChecked }
    if (-not $picked) { Log 'Nothing selected.'; return }
    if ($mode -eq 'Apply') { New-SafeRestorePoint }
    foreach ($cb in $picked) {
        try {
            Log "$mode : $($cb.Content)"
            & $cb.Tag.$mode
        } catch { Log "  failed: $($_.Exception.Message)" }
    }
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue   # restarts automatically
    Log 'Done. Some tweaks need a reboot or sign-out.'
}
$btnApply.Add_Click({ Run-Tweaks 'Apply' })
$btnUndo.Add_Click({ Run-Tweaks 'Undo' })
$btnRP.Add_Click({ $script:rpDone = $false; New-SafeRestorePoint })

$btnInstall.Add_Click({
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Log 'winget not found. Install "App Installer" from the Microsoft Store.'; return }
    $picked = $appList.Children | Where-Object IsChecked
    if (-not $picked) { Log 'Nothing selected.'; return }
    foreach ($cb in $picked) {
        Log "Installing $($cb.Content)..."
        $p = Start-Process winget.exe -ArgumentList "install --id $($cb.Tag) -e --silent --accept-package-agreements --accept-source-agreements" -WindowStyle Hidden -PassThru
        $null = $p.Handle
        while (-not $p.HasExited) { Pump; Start-Sleep -Milliseconds 150 }
        if ($p.ExitCode -eq 0) { Log "  $($cb.Content) installed." } else { Log "  $($cb.Content) finished with code $($p.ExitCode) (may already be installed)." }
    }
    Log 'Install queue finished.'
})

$btnTemp.Add_Click({
    Log 'Cleaning temp files...'
    Remove-Item "$env:TEMP\*", "$env:WINDIR\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    Log 'Temp files cleaned (files in use were skipped).'
})
$btnBin.Add_Click({ Clear-RecycleBin -Force -ErrorAction SilentlyContinue; Log 'Recycle Bin emptied.' })
$btnDns.Add_Click({ ipconfig /flushdns | Out-Null; Log 'DNS cache flushed.' })
$btnSfc.Add_Click({
    Start-Process cmd -ArgumentList '/k sfc /scannow & DISM /Online /Cleanup-Image /RestoreHealth'
    Log 'Opened SFC + DISM in a new window.'
})

Log 'EduUtil ready. Tick what you want, hit Apply. A restore point is made before the first apply.'
[void]$window.ShowDialog()
