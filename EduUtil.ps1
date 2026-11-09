<#
.SYNOPSIS
    EduUtil Pro - Ultimate Windows Tweak, Install, Cleanup & Optimization Toolbox
.DESCRIPTION
    Self-elevating WPF-based PowerShell utility for advanced Windows optimization,
    telemetry removal, gaming performance tweaks, deep system cleanup, and software deployment.
#>

$RepoUrl = 'https://raw.githubusercontent.com/of-Tester121/EduTool/main/EduUtil.ps1'

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
        Checkpoint-Computer -Description 'EduUtil Pro' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Log 'Restore point created.'
    } catch {
        Log "Restore point skipped (Windows only allows one per 24h by default): $($_.Exception.Message)"
    }
    $script:rpDone = $true
}

# ---------- standard tweaks ----------
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
       Desc = 'Start menu search only searches your local PC.'
       Apply = {
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
           Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
       }
       Undo = {
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 1
           Remove-ItemProperty 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' -ErrorAction SilentlyContinue
       } },

    @{ Name = 'Disable Copilot & Taskbar button'
       Desc = 'Turns off Windows Copilot and removes the taskbar integration.'
       Apply = {
           Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCopilotButton' 0
       }
       Undo  = {
           Remove-ItemProperty 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' -ErrorAction SilentlyContinue
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCopilotButton' 1
       } },

    @{ Name = 'Ultimate Performance power plan'
       Desc = 'Adds and activates the hidden Ultimate Performance plan.'
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
       Desc = 'Flat 1:1 raw mouse movement for precision.'
       Apply = {
           $p = 'HKCU:\Control Panel\Mouse'
           Set-Reg $p 'MouseSpeed' '0' 'String'; Set-Reg $p 'MouseThreshold1' '0' 'String'; Set-Reg $p 'MouseThreshold2' '0' 'String'
       }
       Undo = {
           $p = 'HKCU:\Control Panel\Mouse'
           Set-Reg $p 'MouseSpeed' '1' 'String'; Set-Reg $p 'MouseThreshold1' '6' 'String'; Set-Reg $p 'MouseThreshold2' '10' 'String'
       } },

    @{ Name = 'Show file extensions and hidden files'
       Desc = 'Explorer shows .exe/.txt etc and hidden system files.'
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
       Desc = 'Slightly lighter on GPU rendering overhead.'
       Apply = { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0 }
       Undo  = { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 1 } },

    @{ Name = 'Disable hibernation'
       Desc = 'Frees disk space equal to your RAM capacity and disables Fast Startup.'
       Apply = { powercfg -h off }
       Undo  = { powercfg -h on } },

    @{ Name = 'Disable Sticky Keys shortcut annoyance'
       Desc = 'Stops Shift x5 popup dialogs during gaming.'
       Apply = { Set-Reg 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' 'String' }
       Undo  = { Set-Reg 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '510' 'String' } }
)

# ---------- extreme helpers ----------
function Set-SvcStart($names, $mode) {
    foreach ($n in $names) {
        if (Get-Service $n -ErrorAction SilentlyContinue) {
            sc.exe config $n start= $mode | Out-Null
            if ($mode -eq 'disabled') { Stop-Service $n -Force -ErrorAction SilentlyContinue }
            elseif ($mode -in 'auto','delayed-auto') { Start-Service $n -ErrorAction SilentlyContinue }
        }
    }
}
function Set-Tasks($tasks, $enable) {
    $flag = if ($enable) { '/enable' } else { '/disable' }
    foreach ($t in $tasks) { schtasks /change /tn $t $flag 2>&1 | Out-Null }
}
function Remove-Prop($path, $names) {
    foreach ($n in $names) { Remove-ItemProperty $path $n -ErrorAction SilentlyContinue }
}

# ---------- EXTREME & ADVANCED OPTIMIZATIONS (Risk: Low / Medium / High) ----------
$Extreme = @(
    @{ Name = 'Disable SysMain (Superfetch)'; Risk = 'Medium'
       Desc = 'Stops background preloading + disk thrash. Great on SSDs.'
       Apply = { Set-SvcStart @('SysMain') 'disabled' }
       Undo  = { Set-SvcStart @('SysMain') 'auto' } },

    @{ Name = 'Disable Windows Search indexer'; Risk = 'Medium'
       Desc = 'Kills constant indexing CPU/disk use. Explorer search gets slower.'
       Apply = { Set-SvcStart @('WSearch') 'disabled' }
       Undo  = { Set-SvcStart @('WSearch') 'delayed-auto' } },

    @{ Name = 'Disable Xbox services'; Risk = 'Medium'
       Desc = 'Breaks Xbox app, Game Pass and Xbox sign-in. Fine for standalone Steam/Epic/GOG/Java.'
       Apply = { Set-SvcStart @('XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc') 'disabled' }
       Undo  = { Set-SvcStart @('XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc') 'demand' } },

    @{ Name = 'Disable Print Spooler + Fax'; Risk = 'Medium'
       Desc = 'No printing while off. Closes PrintNightmare vulnerability surface.'
       Apply = { Set-SvcStart @('Spooler','Fax') 'disabled' }
       Undo  = { Set-SvcStart @('Spooler') 'auto'; Set-SvcStart @('Fax') 'demand' } },

    @{ Name = 'Disable Bluetooth services'; Risk = 'Medium'
       Desc = 'Only use on desktops with no BT controllers, mice or headsets.'
       Apply = { Set-SvcStart @('bthserv','BTAGService','BthAvctpSvc') 'disabled' }
       Undo  = { Set-SvcStart @('bthserv','BTAGService','BthAvctpSvc') 'demand' } },

    @{ Name = 'Disable useless background services'; Risk = 'Medium'
       Desc = 'Maps, retail demo, error reporting, Insider, geolocation, hotspot, remote registry, etc.'
       Apply = { Set-SvcStart @('MapsBroker','RetailDemo','WerSvc','wisvc','lfsvc','icssvc','WMPNetworkSvc','RemoteRegistry','TrkWks','dmwappushservice','PhoneSvc','WalletService','diagnosticshub.standardcollector.service') 'disabled' }
       Undo  = { Set-SvcStart @('MapsBroker','RetailDemo','WerSvc','wisvc','lfsvc','icssvc','WMPNetworkSvc','TrkWks','dmwappushservice','PhoneSvc','WalletService','diagnosticshub.standardcollector.service') 'demand'; Set-SvcStart @('RemoteRegistry') 'disabled' } },

    @{ Name = 'Disable Delivery Optimization (P2P updates)'; Risk = 'Low'
       Desc = 'Stops Windows uploading updates to other PCs using your internet bandwidth.'
       Apply = { Set-SvcStart @('DoSvc') 'disabled'; Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0 }
       Undo  = { Set-SvcStart @('DoSvc') 'delayed-auto'; Remove-Prop 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' @('DODownloadMode') } },

    @{ Name = 'Disable telemetry scheduled tasks'; Risk = 'Low'
       Desc = 'Turns off Compatibility Appraiser, CEIP, USB CEIP and error-reporting scheduled tasks.'
       Apply = { Set-Tasks @('\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser','\Microsoft\Windows\Application Experience\ProgramDataUpdater','\Microsoft\Windows\Customer Experience Improvement Program\Consolidator','\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip','\Microsoft\Windows\Windows Error Reporting\QueueReporting') $false }
       Undo  = { Set-Tasks @('\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser','\Microsoft\Windows\Application Experience\ProgramDataUpdater','\Microsoft\Windows\Customer Experience Improvement Program\Consolidator','\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip','\Microsoft\Windows\Windows Error Reporting\QueueReporting') $true } },

    @{ Name = 'Block background apps'; Risk = 'Low'
       Desc = 'Prevents Store apps from running invisibly in the background.'
       Apply = { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1; Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground' 2 }
       Undo  = { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 0; Remove-Prop 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' @('LetAppsRunInBackground') } },

    @{ Name = 'Disable Widgets / News feed'; Risk = 'Low'
       Desc = 'Removes the heavy Widgets and MSN news background process.'
       Apply = { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0 }
       Undo  = { Remove-Prop 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' @('AllowNewsAndInterests') } },

    @{ Name = 'Disable OneDrive & Sync'; Risk = 'Medium'
       Desc = 'Policy-disables OneDrive and terminates running instances.'
       Apply = { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1; taskkill /f /im OneDrive.exe 2>&1 | Out-Null }
       Undo  = { Remove-Prop 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' @('DisableFileSyncNGSC') } },

    @{ Name = 'Remove preinstalled bloat apps'; Risk = 'Medium'
       Desc = 'Uninstalls News, Weather, Solitaire, Office hub, Feedback Hub, Phone Link, Clipchamp, Teams, etc.'
       Apply = {
           $bloat = 'Microsoft.BingNews','Microsoft.BingWeather','Microsoft.GetHelp','Microsoft.Getstarted','Microsoft.MicrosoftSolitaireCollection','Microsoft.MicrosoftOfficeHub','Microsoft.WindowsFeedbackHub','Microsoft.YourPhone','Microsoft.ZuneMusic','Microsoft.ZuneVideo','Clipchamp.Clipchamp','Microsoft.People','Microsoft.Todos','Microsoft.PowerAutomateDesktop','Microsoft.549981C3F5F10','MicrosoftTeams','Microsoft.WindowsMaps','Microsoft.SkypeApp','Microsoft.MixedReality.Portal','Microsoft.Microsoft3DViewer'
           foreach ($b in $bloat) { Get-AppxPackage -AllUsers -Name $b | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue }
       }
       Undo  = { Log 'Removed apps cannot be auto-restored. Reinstall them from Microsoft Store.' } },

    @{ Name = 'Max-performance visual effects'; Risk = 'Low'
       Desc = 'Turns off non-essential window/taskbar animations for snappy UI responsiveness.'
       Apply = {
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2
           Set-ItemProperty 'HKCU:\Control Panel\Desktop' 'UserPreferencesMask' ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) -Type Binary
           Set-Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 0
       }
       Undo = {
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 0
           Set-ItemProperty 'HKCU:\Control Panel\Desktop' 'UserPreferencesMask' ([byte[]](0x9E,0x3E,0x07,0x80,0x12,0x00,0x00,0x00)) -Type Binary
           Set-Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '1' 'String'
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 1
       } },

    @{ Name = 'Disable CPU power throttling'; Risk = 'Low'
       Desc = 'Stops Windows from throttling background and game launcher processes.'
       Apply = { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1 }
       Undo  = { Remove-Prop 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' @('PowerThrottlingOff') } },

    @{ Name = 'CPU min state 100% + no core parking'; Risk = 'Medium'
       Desc = 'Cores never park or downclock on AC power. Lower latency, higher sustained clocks.'
       Apply = {
           powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100
           powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100
           powercfg -setactive SCHEME_CURRENT
       }
       Undo = {
           powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 10
           powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5
           powercfg -setactive SCHEME_CURRENT
       } },

    @{ Name = 'Disable USB selective suspend + PCIe power saving'; Risk = 'Low'
       Desc = 'Eliminates mouse/headset dropouts and GPU link-state transition stutter.'
       Apply = {
           powercfg -setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
           powercfg -setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0
           powercfg -setactive SCHEME_CURRENT
       }
       Undo = {
           powercfg -setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1
           powercfg -setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 1
           powercfg -setactive SCHEME_CURRENT
       } },

    @{ Name = 'Gaming CPU scheduling priority'; Risk = 'Low'
       Desc = 'Optimizes SystemResponsiveness and Game task scheduling priorities.'
       Apply = {
           $mm = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
           Set-Reg $mm 'SystemResponsiveness' 0
           Set-Reg "$mm\Tasks\Games" 'GPU Priority' 8
           Set-Reg "$mm\Tasks\Games" 'Priority' 6
           Set-Reg "$mm\Tasks\Games" 'Scheduling Category' 'High' 'String'
           Set-Reg "$mm\Tasks\Games" 'SFIO Priority' 'High' 'String'
           Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 38
       }
       Undo = {
           $mm = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
           Set-Reg $mm 'SystemResponsiveness' 20
           Set-Reg "$mm\Tasks\Games" 'Priority' 2
           Set-Reg "$mm\Tasks\Games" 'Scheduling Category' 'Medium' 'String'
           Set-Reg "$mm\Tasks\Games" 'SFIO Priority' 'Normal' 'String'
           Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 2
       } },

    @{ Name = 'Network: no throttling + disable Nagle (TCPNoDelay)'; Risk = 'Low'
       Desc = 'Removes network throttle and TCP delay for lower ping in online games.'
       Apply = {
           reg add 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' /v NetworkThrottlingIndex /t REG_DWORD /d 0xffffffff /f | Out-Null
           Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' | ForEach-Object {
               Set-ItemProperty $_.PSPath 'TcpAckFrequency' 1 -Type DWord
               Set-ItemProperty $_.PSPath 'TCPNoDelay' 1 -Type DWord
           }
       }
       Undo = {
           reg add 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' /v NetworkThrottlingIndex /t REG_DWORD /d 10 /f | Out-Null
           Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' | ForEach-Object {
               Remove-Prop $_.PSPath @('TcpAckFrequency','TCPNoDelay')
           }
       } },

    @{ Name = 'Hardware-accelerated GPU scheduling (HAGS)'; Risk = 'Low'
       Desc = 'Enables HAGS for reduced input latency and improved GPU scheduling. Reboot required.'
       Apply = { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 }
       Undo  = { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 1 } },

    @{ Name = 'Disable Multiplane Overlay (MPO)'; Risk = 'Low'
       Desc = 'Fixes screen flicker, stutter, and black screen issues in games on multi-monitor setups.'
       Apply = { Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\DWM' 'OverlayTestMode' 5 }
       Undo  = { Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\DWM' 'OverlayTestMode' -ErrorAction SilentlyContinue } },

    @{ Name = 'Disable fullscreen optimizations'; Risk = 'Low'
       Desc = 'Enforces true exclusive fullscreen behavior for stutter-free gaming.'
       Apply = {
           $p = 'HKCU:\System\GameConfigStore'
           Set-Reg $p 'GameDVR_FSEBehaviorMode' 2; Set-Reg $p 'GameDVR_HonorUserFSEBehaviorMode' 1; Set-Reg $p 'GameDVR_DXGIHonorFSEWindowsCompatible' 1
       }
       Undo = {
           $p = 'HKCU:\System\GameConfigStore'
           Set-Reg $p 'GameDVR_FSEBehaviorMode' 0; Set-Reg $p 'GameDVR_HonorUserFSEBehaviorMode' 0; Set-Reg $p 'GameDVR_DXGIHonorFSEWindowsCompatible' 0
       } },

    @{ Name = 'Disable memory compression'; Risk = 'Medium'
       Desc = 'Saves CPU cycles. Recommended for systems with 16GB+ RAM. Reboot required.'
       Apply = { Disable-MMAgent -MemoryCompression }
       Undo  = { Enable-MMAgent -MemoryCompression } },

    @{ Name = 'NTFS: disable last-access time + 8.3 names'; Risk = 'Low'
       Desc = 'Reduces unnecessary disk writes when reading files.'
       Apply = { fsutil behavior set disablelastaccess 1 | Out-Null; fsutil behavior set disable8dot3 1 | Out-Null }
       Undo  = { fsutil behavior set disablelastaccess 2 | Out-Null; fsutil behavior set disable8dot3 2 | Out-Null } },

    @{ Name = 'Disable reserved storage'; Risk = 'Low'
       Desc = 'Reclaims ~7GB of disk space reserved by Windows for system updates.'
       Apply = { DISM /Online /Set-ReservedStorageState /State:Disabled | Out-Null }
       Undo  = { DISM /Online /Set-ReservedStorageState /State:Enabled | Out-Null } },

    @{ Name = 'Timer tweaks (disable dynamic tick)'; Risk = 'Medium'
       Desc = 'Increases timer precision for lowest input latency. Slight idle power increase.'
       Apply = { bcdedit /set disabledynamictick yes | Out-Null; bcdedit /deletevalue useplatformclock 2>&1 | Out-Null }
       Undo  = { bcdedit /deletevalue disabledynamictick 2>&1 | Out-Null } },

    @{ Name = 'Windows Update: notify only (no auto reboot)'; Risk = 'Medium'
       Desc = 'Stops automatic updates and forced reboots while working or gaming.'
       Apply = {
           $p = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
           Set-Reg $p 'AUOptions' 2; Set-Reg $p 'NoAutoRebootWithLoggedOnUsers' 1
       }
       Undo = { Remove-Prop 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' @('AUOptions','NoAutoRebootWithLoggedOnUsers') } },

    @{ Name = 'Disable Core Isolation / VBS (Memory Integrity)'; Risk = 'High'
       Desc = 'Significant FPS gain in CPU-bound games. Disables a core virtualization security feature.'
       Apply = {
           Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0
           Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0
       }
       Undo = {
           Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 1
           Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 1
       } },

    @{ Name = 'Disable Spectre/Meltdown mitigations'; Risk = 'High'
       Desc = 'Boosts CPU performance on older processors by removing speculative execution security patches.'
       Apply = {
           $p = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
           Set-Reg $p 'FeatureSettingsOverride' 3; Set-Reg $p 'FeatureSettingsOverrideMask' 3
       }
       Undo = { Remove-Prop 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' @('FeatureSettingsOverride','FeatureSettingsOverrideMask') } }
)

# ---------- apps (winget IDs expanded) ----------
$Apps = [ordered]@{
    'Brave Browser'    = 'Brave.Brave'
    'Firefox'          = 'Mozilla.Firefox'
    'Google Chrome'    = 'Google.Chrome'
    '7-Zip'            = '7zip.7zip'
    'VLC Media Player' = 'VideoLAN.VLC'
    'Discord'          = 'Discord.Discord'
    'Steam'            = 'Valve.Steam'
    'Epic Games'       = 'EpicGames.EpicGamesLauncher'
    'GOG Galaxy'       = 'GOG.Galaxy'
    'Spotify'          = 'Spotify.Spotify'
    'OBS Studio'       = 'OBSProject.OBSStudio'
    'VS Code'          = 'Microsoft.VisualStudioCode'
    'Git'              = 'Git.Git'
    'Python 3.12'      = 'Python.Python.3.12'
    'Notepad++'        = 'Notepad++.Notepad++'
    'PowerToys'        = 'Microsoft.PowerToys'
    'Everything Search'= 'voidtools.Everything'
    'HWiNFO'           = 'REALiX.HWiNFO'
    'WizTree'          = 'AntibodySoftware.WizTree'
    'MSI Afterburner'  = 'URT.MSIAfterburner'
    'Revo Uninstaller' = 'RevoUninstaller.RevoUninstaller'
    'ShareX'           = 'ShareX.ShareX'
    'Bitwarden'        = 'Bitwarden.Bitwarden'
}

# ---------- GUI XAML ----------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="EduUtil Pro - Ultimate Windows Toolbox" Width="980" Height="680" WindowStartupLocation="CenterScreen"
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
      <ColumnDefinition Width="170"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>

    <StackPanel Grid.Column="0" Margin="0,0,12,0">
      <TextBlock Text="EduUtil Pro" FontSize="24" FontWeight="Bold" Margin="0,0,0,18" Foreground="#58A6FF"/>
      <Button Name="navTweaks"  Content="Tweaks"     Margin="0,0,0,8" HorizontalContentAlignment="Left"/>
      <Button Name="navExtreme" Content="Extreme/Game" Margin="0,0,0,8" HorizontalContentAlignment="Left" Background="#C0392B"/>
      <Button Name="navInstall" Content="Install Apps" Margin="0,0,0,8" HorizontalContentAlignment="Left"/>
      <Button Name="navClean"   Content="Cleanup"    Margin="0,0,0,8" HorizontalContentAlignment="Left"/>
      <Button Name="navSysInfo" Content="System Info" Margin="0,0,0,8" HorizontalContentAlignment="Left" Background="#27AE60"/>
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

        <DockPanel Name="pgExtreme" Visibility="Collapsed">
          <TextBlock DockPanel.Dock="Top" TextWrapping="Wrap" Foreground="#FF8A5C" Margin="0,0,0,8"
                     Text="Advanced &amp; Extreme optimizations. Yellow = medium trade-off, red = high security/compat risk. Restore point created automatically."/>
          <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,8,0,8">
            <Button Name="btnXApply" Content="Apply selected" Background="#C0392B"/>
            <Button Name="btnXUndo"  Content="Undo selected" Background="#444A55"/>
          </StackPanel>
          <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Name="extremeList"/></ScrollViewer>
        </DockPanel>

        <DockPanel Name="pgInstall" Visibility="Collapsed">
          <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,8,0,8">
            <Button Name="btnInstall" Content="Install selected apps via Winget"/>
          </StackPanel>
          <ScrollViewer VerticalScrollBarVisibility="Auto"><WrapPanel Name="appList"/></ScrollViewer>
        </DockPanel>

        <StackPanel Name="pgClean" Visibility="Collapsed">
          <TextBlock Text="System Cleanup &amp; Maintenance Tools" FontSize="16" FontWeight="Bold" Margin="0,0,0,12" Foreground="#58A6FF"/>
          <Button Name="btnTemp"    Content="Clean Temp Files &amp; Prefetch"     Margin="0,0,0,10" HorizontalAlignment="Left"/>
          <Button Name="btnBin"     Content="Empty Recycle Bin"                  Margin="0,0,0,10" HorizontalAlignment="Left"/>
          <Button Name="btnDns"     Content="Flush DNS Cache"                    Margin="0,0,0,10" HorizontalAlignment="Left"/>
          <Button Name="btnShader"  Content="Clean DirectX &amp; Browser Caches"   Margin="0,0,0,10" HorizontalAlignment="Left"/>
          <Button Name="btnSfc"     Content="Repair Windows (SFC + DISM)"        Margin="0,0,0,10" HorizontalAlignment="Left"/>
        </StackPanel>

        <DockPanel Name="pgSysInfo" Visibility="Collapsed">
          <TextBlock DockPanel.Dock="Top" Text="System Hardware &amp; OS Summary" FontSize="16" FontWeight="Bold" Margin="0,0,0,12" Foreground="#58A6FF"/>
          <StackPanel DockPanel.Dock="Bottom" Margin="0,8,0,0">
            <Button Name="btnRefreshInfo" Content="Refresh System Info" HorizontalAlignment="Left"/>
          </StackPanel>
          <TextBox Name="txtSysInfo" IsReadOnly="True" Background="#0D0F13" Foreground="#58A6FF"
                   FontFamily="Consolas" FontSize="13" BorderThickness="0" Padding="10"
                   VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"/>
        </DockPanel>
      </Grid>

      <TextBox Name="txtLog" Grid.Row="1" IsReadOnly="True" Background="#0D0F13" Foreground="#9BE59B"
               FontFamily="Consolas" FontSize="12" BorderThickness="0" Padding="8"
               VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"/>
    </Grid>
  </Grid>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Parse($xaml)
foreach ($n in 'navTweaks','navExtreme','navInstall','navClean','navSysInfo','pgTweaks','pgExtreme','pgInstall','pgClean','pgSysInfo','tweakList','extremeList','appList','btnXApply','btnXUndo',
               'btnApply','btnUndo','btnRP','btnInstall','btnTemp','btnBin','btnDns','btnShader','btnSfc','btnRefreshInfo','txtSysInfo','txtLog') {
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
foreach ($t in $Extreme) {
    $cb = New-Object Windows.Controls.CheckBox
    $cb.Content = "$($t.Name)   [$($t.Risk)]"; $cb.ToolTip = $t.Desc; $cb.Tag = $t
    if ($t.Risk -eq 'High') { $cb.Foreground = '#FF5C5C' } elseif ($t.Risk -eq 'Medium') { $cb.Foreground = '#FFC857' }
    [void]$extremeList.Children.Add($cb)
    $desc = New-Object Windows.Controls.TextBlock
    $desc.Text = $t.Desc; $desc.Foreground = '#8A90A0'; $desc.FontSize = 11
    $desc.Margin = '24,-2,0,4'; $desc.TextWrapping = 'Wrap'
    [void]$extremeList.Children.Add($desc)
}
foreach ($k in $Apps.Keys) {
    $cb = New-Object Windows.Controls.CheckBox
    $cb.Content = $k; $cb.Tag = $Apps[$k]; $cb.Width = 220
    [void]$appList.Children.Add($cb)
}

function Show-Page($name) {
    foreach ($p in 'pgTweaks','pgExtreme','pgInstall','pgClean','pgSysInfo') {
        (Get-Variable $p).Value.Visibility = if ($p -eq $name) { 'Visible' } else { 'Collapsed' }
    }
}
$navTweaks.Add_Click({ Show-Page 'pgTweaks' })
$navExtreme.Add_Click({ Show-Page 'pgExtreme' })
$navInstall.Add_Click({ Show-Page 'pgInstall' })
$navClean.Add_Click({ Show-Page 'pgClean' })
$navSysInfo.Add_Click({ 
    Show-Page 'pgSysInfo'
    Refresh-SysInfo
})

function Refresh-SysInfo {
    Log 'Gathering system specifications...'
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor
    $cs = Get-CimInstance Win32_ComputerSystem
    $gpu = Get-CimInstance Win32_VideoController
    $disk = Get-CimInstance Win32_LogicalDisk | Where-Object DeviceID -eq 'C:'

    $totalRamGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    $freeRamGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $diskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    $diskTotalGB = [math]::Round($disk.Size / 1GB, 2)

    $info = @"
==================================================
 OS: $($os.Caption) ($($os.OSArchitecture))
 Version: $($os.Version)
--------------------------------------------------
 CPU: $($cpu.Name)
 Cores: $($cpu.NumberOfCores) (Threads: $($cpu.NumberOfLogicalProcessors))
--------------------------------------------------
 GPU: $($gpu.Name)
--------------------------------------------------
 RAM: ${freeRamGB} GB Free / ${totalRamGB} GB Total
 C: Drive: ${diskFreeGB} GB Free / ${diskTotalGB} GB Total
 Computer Name: $($cs.Name)
==================================================
"@
    $txtSysInfo.Text = $info
    Log 'System specifications loaded.'
}

$btnRefreshInfo.Add_Click({ Refresh-SysInfo })

function Run-Tweaks($mode, $list) {
    $picked = $list.Children | Where-Object { $_ -is [Windows.Controls.CheckBox] -and $_.IsChecked }
    if (-not $picked) { Log 'Nothing selected.'; return }
    if ($list -eq $extremeList -and $mode -eq 'Apply') {
        $names = ($picked | ForEach-Object { $_.Tag.Name }) -join "`n- "
        $ans = [Windows.MessageBox]::Show("Apply these EXTREME/Advanced tweaks?`n`n- $names`n`nA restore point will be created first.", 'EduUtil Pro', 'YesNo', 'Warning')
        if ($ans -ne 'Yes') { Log 'Cancelled.'; return }
    }
    if ($mode -eq 'Apply') { New-SafeRestorePoint }
    foreach ($cb in $picked) {
        try {
            Log "$mode : $($cb.Content)"
            & $cb.Tag.$mode
        } catch { Log "  failed: $($_.Exception.Message)" }
    }
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Log 'Done. Some tweaks require a system reboot or sign-out to fully take effect.'
}

$btnApply.Add_Click({ Run-Tweaks 'Apply' $tweakList })
$btnXApply.Add_Click({ Run-Tweaks 'Apply' $extremeList })
$btnXUndo.Add_Click({ Run-Tweaks 'Undo' $extremeList })
$btnUndo.Add_Click({ Run-Tweaks 'Undo' $tweakList })
$btnRP.Add_Click({ $script:rpDone = $false; New-SafeRestorePoint })

$btnInstall.Add_Click({
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Log 'winget not found. Install "App Installer" from Microsoft Store.'; return }
    $picked = $appList.Children | Where-Object IsChecked
    if (-not $picked) { Log 'Nothing selected.'; return }
    foreach ($cb in $picked) {
        Log "Installing $($cb.Content)..."
        $p = Start-Process winget.exe -ArgumentList "install --id $($cb.Tag) -e --silent --accept-package-agreements --accept-source-agreements" -WindowStyle Hidden -PassThru
        $null = $p.Handle
        while (-not $p.HasExited) { Pump; Start-Sleep -Milliseconds 150 }
        if ($p.ExitCode -eq 0) { Log "  $($cb.Content) installed successfully." } else { Log "  $($cb.Content) finished with exit code $($p.ExitCode) (may already be installed)." }
    }
    Log 'Install queue finished.'
})

$btnTemp.Add_Click({
    Log 'Cleaning Temp files, Prefetch & System logs...'
    Remove-Item "$env:TEMP\*", "$env:WINDIR\Temp\*", "$env:WINDIR\Prefetch\*" -Recurse -Force -ErrorAction SilentlyContinue
    Log 'Temp and Prefetch cleanup completed (locked files skipped).'
})

$btnBin.Add_Click({ 
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Log 'Recycle Bin emptied successfully.' 
})

$btnDns.Add_Click({ 
    ipconfig /flushdns | Out-Null
    Log 'DNS resolver cache flushed.' 
})

$btnShader.Add_Click({
    Log 'Cleaning browser caches & update download caches...'
    Remove-Item "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache\*", "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\*", "$env:WINDIR\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
    Log 'Browser & Windows Update caches cleaned.'
})

$btnSfc.Add_Click({
    Start-Process cmd -ArgumentList '/k sfc /scannow & DISM /Online /Cleanup-Image /RestoreHealth'
    Log 'Opened SFC + DISM repair tool in a new command window.'
})

Log 'EduUtil Pro ready. Select features and click Apply. A restore point will be created automatically.'
[void]$window.ShowDialog()
