# EduUtil - Windows tweak / install / cleanup toolbox
# Run (admin or not, it self-elevates):
#   irm "https://raw.githubusercontent.com/of-Tester121/EduTool/main/EduUtil.ps1" | iex

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

# ---------- EXTREME tweaks (Risk: Low / Medium / High) ----------
$Extreme = @(
    @{ Name = 'Disable SysMain (Superfetch)'; Risk = 'Medium'
       Desc = 'Stops background preloading + disk thrash. Great on SSDs, slower app launches on HDDs.'
       Apply = { Set-SvcStart @('SysMain') 'disabled' }
       Undo  = { Set-SvcStart @('SysMain') 'auto' } },

    @{ Name = 'Disable Windows Search indexer'; Risk = 'Medium'
       Desc = 'Kills constant indexing CPU/disk use. Start/Explorer search gets slower.'
       Apply = { Set-SvcStart @('WSearch') 'disabled' }
       Undo  = { Set-SvcStart @('WSearch') 'delayed-auto' } },

    @{ Name = 'Disable Xbox services'; Risk = 'Medium'
       Desc = 'Breaks Xbox app, Game Pass and Xbox sign-in (incl. Minecraft Bedrock login). Fine for Steam/Java games.'
       Apply = { Set-SvcStart @('XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc') 'disabled' }
       Undo  = { Set-SvcStart @('XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc') 'demand' } },

    @{ Name = 'Disable Print Spooler + Fax'; Risk = 'Medium'
       Desc = 'No printing while off. Also closes the PrintNightmare attack surface.'
       Apply = { Set-SvcStart @('Spooler','Fax') 'disabled' }
       Undo  = { Set-SvcStart @('Spooler') 'auto'; Set-SvcStart @('Fax') 'demand' } },

    @{ Name = 'Disable Bluetooth services'; Risk = 'Medium'
       Desc = 'Only do this on a desktop with no Bluetooth headset, controller or mouse.'
       Apply = { Set-SvcStart @('bthserv','BTAGService','BthAvctpSvc') 'disabled' }
       Undo  = { Set-SvcStart @('bthserv','BTAGService','BthAvctpSvc') 'demand' } },

    @{ Name = 'Disable useless background services'; Risk = 'Medium'
       Desc = 'Maps, retail demo, error reporting, Insider, geolocation, hotspot, WMP sharing, remote registry, link tracking, dmwappush, phone, wallet, diag hub.'
       Apply = { Set-SvcStart @('MapsBroker','RetailDemo','WerSvc','wisvc','lfsvc','icssvc','WMPNetworkSvc','RemoteRegistry','TrkWks','dmwappushservice','PhoneSvc','WalletService','diagnosticshub.standardcollector.service') 'disabled' }
       Undo  = { Set-SvcStart @('MapsBroker','RetailDemo','WerSvc','wisvc','lfsvc','icssvc','WMPNetworkSvc','TrkWks','dmwappushservice','PhoneSvc','WalletService','diagnosticshub.standardcollector.service') 'demand'; Set-SvcStart @('RemoteRegistry') 'disabled' } },

    @{ Name = 'Disable Delivery Optimization (P2P updates)'; Risk = 'Low'
       Desc = 'Stops Windows uploading updates to other PCs with your bandwidth.'
       Apply = { Set-SvcStart @('DoSvc') 'disabled'; Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0 }
       Undo  = { Set-SvcStart @('DoSvc') 'delayed-auto'; Remove-Prop 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' @('DODownloadMode') } },

    @{ Name = 'Disable telemetry scheduled tasks'; Risk = 'Low'
       Desc = 'Turns off Compatibility Appraiser, CEIP, USB CEIP and error-report tasks.'
       Apply = { Set-Tasks @('\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser','\Microsoft\Windows\Application Experience\ProgramDataUpdater','\Microsoft\Windows\Customer Experience Improvement Program\Consolidator','\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip','\Microsoft\Windows\Windows Error Reporting\QueueReporting') $false }
       Undo  = { Set-Tasks @('\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser','\Microsoft\Windows\Application Experience\ProgramDataUpdater','\Microsoft\Windows\Customer Experience Improvement Program\Consolidator','\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip','\Microsoft\Windows\Windows Error Reporting\QueueReporting') $true } },

    @{ Name = 'Block background apps'; Risk = 'Low'
       Desc = 'Store apps can no longer run in the background eating RAM/CPU.'
       Apply = { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1; Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground' 2 }
       Undo  = { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 0; Remove-Prop 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' @('LetAppsRunInBackground') } },

    @{ Name = 'Disable Widgets / News feed'; Risk = 'Low'
       Desc = 'Removes the widgets/news process from running.'
       Apply = { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0 }
       Undo  = { Remove-Prop 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' @('AllowNewsAndInterests') } },

    @{ Name = 'Disable OneDrive'; Risk = 'Medium'
       Desc = 'Policy-disables OneDrive sync and kills it. Do not use if you rely on OneDrive.'
       Apply = { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1; taskkill /f /im OneDrive.exe 2>&1 | Out-Null }
       Undo  = { Remove-Prop 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' @('DisableFileSyncNGSC') } },

    @{ Name = 'Remove preinstalled bloat apps'; Risk = 'Medium'
       Desc = 'Uninstalls News, Weather, Solitaire, Office hub, Feedback Hub, Phone Link, Groove/Movies, Clipchamp, Teams, Todo, Maps, Skype, etc. NO auto-undo (reinstall from Store).'
       Apply = {
           $bloat = 'Microsoft.BingNews','Microsoft.BingWeather','Microsoft.GetHelp','Microsoft.Getstarted','Microsoft.MicrosoftSolitaireCollection','Microsoft.MicrosoftOfficeHub','Microsoft.WindowsFeedbackHub','Microsoft.YourPhone','Microsoft.ZuneMusic','Microsoft.ZuneVideo','Clipchamp.Clipchamp','Microsoft.People','Microsoft.Todos','Microsoft.PowerAutomateDesktop','Microsoft.549981C3F5F10','MicrosoftTeams','Microsoft.WindowsMaps','Microsoft.SkypeApp','Microsoft.MixedReality.Portal','Microsoft.Microsoft3DViewer'
           foreach ($b in $bloat) { Get-AppxPackage -AllUsers -Name $b | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue }
       }
       Undo  = { Log 'Removed apps cannot be auto-restored. Reinstall them from the Microsoft Store.' } },

    @{ Name = 'Max-performance visual effects'; Risk = 'Low'
       Desc = 'Turns off window/taskbar animations and fades. Sign out to fully apply.'
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
       Desc = 'Windows stops throttling background-ish processes (helps game launchers, streaming, servers).'
       Apply = { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1 }
       Undo  = { Remove-Prop 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' @('PowerThrottlingOff') } },

    @{ Name = 'CPU min state 100% + no core parking'; Risk = 'Medium'
       Desc = 'Cores never park or downclock on AC power. Lower latency, more heat and power use.'
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
       Desc = 'Fixes mouse/headset dropouts and GPU link-state latency on AC power.'
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
       Desc = 'SystemResponsiveness 0, High priority for the Games task, short foreground boost quanta.'
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

    @{ Name = 'Network: no throttling + disable Nagle'; Risk = 'Low'
       Desc = 'Removes the multimedia network throttle and TCP delay. Lower ping in online games.'
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

    @{ Name = 'Hardware-accelerated GPU scheduling'; Risk = 'Low'
       Desc = 'Turns on HAGS (needs a recent GPU + driver). Reboot required.'
       Apply = { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 }
       Undo  = { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 1 } },

    @{ Name = 'Disable fullscreen optimizations'; Risk = 'Low'
       Desc = 'True exclusive fullscreen behaviour for games that stutter in borderless mode.'
       Apply = {
           $p = 'HKCU:\System\GameConfigStore'
           Set-Reg $p 'GameDVR_FSEBehaviorMode' 2; Set-Reg $p 'GameDVR_HonorUserFSEBehaviorMode' 1; Set-Reg $p 'GameDVR_DXGIHonorFSEWindowsCompatible' 1
       }
       Undo = {
           $p = 'HKCU:\System\GameConfigStore'
           Set-Reg $p 'GameDVR_FSEBehaviorMode' 0; Set-Reg $p 'GameDVR_HonorUserFSEBehaviorMode' 0; Set-Reg $p 'GameDVR_DXGIHonorFSEWindowsCompatible' 0
       } },

    @{ Name = 'Disable memory compression'; Risk = 'Medium'
       Desc = 'Saves CPU cycles. Only worth it with 16GB+ RAM. Reboot required.'
       Apply = { Disable-MMAgent -MemoryCompression }
       Undo  = { Enable-MMAgent -MemoryCompression } },

    @{ Name = 'NTFS: disable last-access time + 8.3 names'; Risk = 'Low'
       Desc = 'Fewer disk writes on every file read. Very old 16-bit installers may complain.'
       Apply = { fsutil behavior set disablelastaccess 1 | Out-Null; fsutil behavior set disable8dot3 1 | Out-Null }
       Undo  = { fsutil behavior set disablelastaccess 2 | Out-Null; fsutil behavior set disable8dot3 2 | Out-Null } },

    @{ Name = 'Disable reserved storage'; Risk = 'Low'
       Desc = 'Frees ~7GB Windows keeps reserved for updates.'
       Apply = { DISM /Online /Set-ReservedStorageState /State:Disabled | Out-Null }
       Undo  = { DISM /Online /Set-ReservedStorageState /State:Enabled | Out-Null } },

    @{ Name = 'Timer tweaks (disable dynamic tick)'; Risk = 'Medium'
       Desc = 'Constant timer ticks for lower input latency. Uses a bit more idle power. Reboot required.'
       Apply = { bcdedit /set disabledynamictick yes | Out-Null; bcdedit /deletevalue useplatformclock 2>&1 | Out-Null }
       Undo  = { bcdedit /deletevalue disabledynamictick 2>&1 | Out-Null } },

    @{ Name = 'Windows Update: notify only (no auto install/reboot)'; Risk = 'Medium'
       Desc = 'Windows asks before downloading/installing. Remember to update manually for security patches.'
       Apply = {
           $p = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
           Set-Reg $p 'AUOptions' 2; Set-Reg $p 'NoAutoRebootWithLoggedOnUsers' 1
       }
       Undo = { Remove-Prop 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' @('AUOptions','NoAutoRebootWithLoggedOnUsers') } },

    @{ Name = 'Disable Core Isolation / VBS (Memory Integrity)'; Risk = 'High'
       Desc = 'Big FPS gain in CPU-bound games on some PCs. Turns OFF a major security feature. Reboot required. Undo turns it back on.'
       Apply = {
           Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0
           Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0
       }
       Undo = {
           Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 1
           Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 1
       } },

    @{ Name = 'Disable Spectre/Meltdown mitigations'; Risk = 'High'
       Desc = 'Gains a few % on older Intel CPUs (little on new ones). Leaves CPU side-channel holes open. Reboot required.'
       Apply = {
           $p = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
           Set-Reg $p 'FeatureSettingsOverride' 3; Set-Reg $p 'FeatureSettingsOverrideMask' 3
       }
       Undo = { Remove-Prop 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' @('FeatureSettingsOverride','FeatureSettingsOverrideMask') } }
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
      <Button Name="navExtreme" Content="Extreme"  Margin="0,0,0,8" HorizontalContentAlignment="Left" Background="#C0392B"/>
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

        <DockPanel Name="pgExtreme" Visibility="Collapsed">
          <TextBlock DockPanel.Dock="Top" TextWrapping="Wrap" Foreground="#FF8A5C" Margin="0,0,0,8"
                     Text="Extreme tweaks. Yellow = medium trade-off, red = real security/compat risk. A restore point is made before applying."/>
          <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,8,0,8">
            <Button Name="btnXApply" Content="Apply selected" Background="#C0392B"/>
            <Button Name="btnXUndo"  Content="Undo selected" Background="#444A55"/>
          </StackPanel>
          <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Name="extremeList"/></ScrollViewer>
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
foreach ($n in 'navTweaks','navExtreme','navInstall','navClean','pgTweaks','pgExtreme','pgInstall','pgClean','tweakList','extremeList','appList','btnXApply','btnXUndo',
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
    $cb.Content = $k; $cb.Tag = $Apps[$k]; $cb.Width = 200
    [void]$appList.Children.Add($cb)
}

function Show-Page($name) {
    foreach ($p in 'pgTweaks','pgExtreme','pgInstall','pgClean') {
        (Get-Variable $p).Value.Visibility = if ($p -eq $name) { 'Visible' } else { 'Collapsed' }
    }
}
$navTweaks.Add_Click({ Show-Page 'pgTweaks' })
$navExtreme.Add_Click({ Show-Page 'pgExtreme' })
$navInstall.Add_Click({ Show-Page 'pgInstall' })
$navClean.Add_Click({ Show-Page 'pgClean' })

function Run-Tweaks($mode, $list) {
    $picked = $list.Children | Where-Object { $_ -is [Windows.Controls.CheckBox] -and $_.IsChecked }
    if (-not $picked) { Log 'Nothing selected.'; return }
    if ($list -eq $extremeList -and $mode -eq 'Apply') {
        $names = ($picked | ForEach-Object { $_.Tag.Name }) -join "`n- "
        $ans = [Windows.MessageBox]::Show("Apply these EXTREME tweaks?`n`n- $names`n`nA restore point will be created first.", 'EduUtil', 'YesNo', 'Warning')
        if ($ans -ne 'Yes') { Log 'Cancelled.'; return }
    }
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
$btnApply.Add_Click({ Run-Tweaks 'Apply' $tweakList })
$btnXApply.Add_Click({ Run-Tweaks 'Apply' $extremeList })
$btnXUndo.Add_Click({ Run-Tweaks 'Undo' $extremeList })
$btnUndo.Add_Click({ Run-Tweaks 'Undo' $tweakList })
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
