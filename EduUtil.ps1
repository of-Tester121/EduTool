#requires -Version 5.1
<#
.SYNOPSIS
    EduUtil - Windows Performance & Maintenance Utility
.DESCRIPTION
    Self-elevating WPF utility for Windows maintenance, privacy controls, gaming configuration,
    system diagnostics, cleanup, and software installation.
#>

$RepoUrl = 'https://raw.githubusercontent.com/of-Tester121/EduTool/main/EduUtil.ps1'

# ---------- self-elevate ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if ($PSCommandPath) {
        $quotedPath = '"' + $PSCommandPath + '"'
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File $quotedPath"
    } else {
        $arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"irm '$RepoUrl' | iex`""
    }
    try { Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments | Out-Null } catch { }
    return
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ---------- helpers ----------
function Set-Reg {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet('DWord','QWord','String','ExpandString','MultiString','Binary')][string]$Type = 'DWord'
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
}

function Pump {
    $window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
}

function Log($msg) {
    # Status stays inside the app; no console or terminal output is emitted.
    if ($txtStatus) {
        $txtStatus.Text = "$(Get-Date -Format 'HH:mm')  |  $msg"
        Pump
    }
}

$script:rpDone = $false
function New-SafeRestorePoint {
    if ($script:rpDone) { return $true }
    Log 'Creating a Windows restore point...'
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
        Checkpoint-Computer -Description 'EduUtil' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        $script:rpDone = $true
        Log 'Restore point created.'
        return $true
    } catch {
        Log "Restore point unavailable: $($_.Exception.Message)"
        return $false
    }
}

# ---------- standard tweaks ----------
$Tweaks = @(
    @{ Name = 'Disable telemetry'
       Desc = 'Applies the Windows diagnostic-data policy and disables the Connected User Experiences service. Some diagnostics may stop working.'
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
       Desc = 'Activates the optional Ultimate Performance plan. It can use more power and generate more heat; it does not guarantee higher game FPS.'
       Apply = {
           $activeText = powercfg /getactivescheme 2>&1
           if (-not $script:PreviousPowerScheme -and "$activeText" -match '([0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})') { $script:PreviousPowerScheme = $Matches[1] }
           $listText = powercfg /list 2>&1
           $planId = $null
           foreach ($line in $listText) {
               if ("$line" -match '([0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}).*Ultimate Performance') { $planId = $Matches[1]; break }
           }
           if (-not $planId) {
               $created = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1
               if ("$created" -match '([0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})') { $planId = $Matches[1] }
           }
           if (-not $planId) { throw 'Windows could not create or locate the Ultimate Performance plan.' }
           powercfg -setactive $planId | Out-Null
       }
       Undo = {
           if ($script:PreviousPowerScheme) { powercfg -setactive $script:PreviousPowerScheme | Out-Null }
           else { powercfg -setactive 381b4222-f694-41f0-9685-ff5bb260df2e | Out-Null }
       } },

    @{ Name = 'High Performance power plan'
       Desc = 'Activates Windows High Performance mode. It may increase idle power and heat; compare temperatures and performance before keeping it.'
       Apply = {
           $activeText = powercfg /getactivescheme 2>&1
           if (-not $script:PreviousPowerScheme -and "$activeText" -match '([0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})') { $script:PreviousPowerScheme = $Matches[1] }
           powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c | Out-Null
       }
       Undo = {
           if ($script:PreviousPowerScheme) { powercfg -setactive $script:PreviousPowerScheme | Out-Null }
           else { powercfg -setactive 381b4222-f694-41f0-9685-ff5bb260df2e | Out-Null }
       } },

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
       Apply = { reg add 'HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' /f /ve 2>&1 | Out-Null }
       Undo  = { reg delete 'HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}' /f 2>&1 | Out-Null } },

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
       Apply = { powercfg -h off | Out-Null }
       Undo  = { powercfg -h on | Out-Null } },

    @{ Name = 'Disable Sticky Keys shortcut annoyance'
       Desc = 'Stops Shift x5 popup dialogs during gaming.'
       Apply = { Set-Reg 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' 'String' }
       Undo  = { Set-Reg 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '510' 'String' } }
)


# Additional everyday options. These are intentionally conservative and reversible.
$Tweaks += @(
    @{ Name = 'Enable Windows Game Mode';
       Desc = 'Turns on Windows Game Mode scheduling. It does not guarantee higher FPS, but helps Windows prioritize recognized games.';
       Apply = {
           Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1
           Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
       }
       Undo = {
           Remove-Prop 'HKCU:\Software\Microsoft\GameBar' @('AllowAutoGameMode','AutoGameModeEnabled')
       } },

    @{ Name = 'Disable Windows search highlights';
       Desc = 'Removes web/trending highlights from Windows Search. Local file search remains available.';
       Apply = {
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 0
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSearchHighlights' 0
       }
       Undo = {
           Remove-Prop 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' @('IsDynamicSearchBoxEnabled')
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSearchHighlights' 1
       } },

    @{ Name = 'Turn off Windows tips and suggestions';
       Desc = 'Disables promotional suggestions and setup tips in Settings and the Start menu.';
       Apply = {
           $p = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
           foreach ($n in @('SystemPaneSuggestionsEnabled','SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-353694Enabled','SubscribedContent-353696Enabled')) { Set-Reg $p $n 0 }
       }
       Undo = {
           Remove-Prop 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' @('SystemPaneSuggestionsEnabled','SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-353694Enabled','SubscribedContent-353696Enabled')
       } },

    @{ Name = 'Disable advertising ID';
       Desc = 'Stops Windows apps from using the per-user advertising ID for personalized ads.';
       Apply = { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 }
       Undo = { Remove-Prop 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' @('Enabled') } },

    @{ Name = 'Reduce Windows feedback prompts';
       Desc = 'Stops Windows from periodically asking for feedback.';
       Apply = {
           $p = 'HKCU:\Software\Microsoft\Siuf\Rules'
           Set-Reg $p 'NumberOfSIUFInPeriod' 0
           Remove-Prop $p @('PeriodInNanoSeconds')
       }
       Undo = { Remove-Prop 'HKCU:\Software\Microsoft\Siuf\Rules' @('NumberOfSIUFInPeriod','PeriodInNanoSeconds') } },

    @{ Name = 'Disable app launch tracking';
       Desc = 'Turns off Start menu app-launch tracking used for personalized suggestions.';
       Apply = { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackProgs' 0 }
       Undo = { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackProgs' 1 } },

    @{ Name = 'Faster menu response';
       Desc = 'Sets the Windows menu animation delay to a shorter, still usable value.';
       Apply = { Set-Reg 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '120' 'String' }
       Undo = { Set-Reg 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '400' 'String' } },

    @{ Name = 'Disable Edge background startup';
       Desc = 'Prevents Microsoft Edge from staying in the background or using Startup Boost. Only affects Edge.';
       Apply = {
           $p = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
           Set-Reg $p 'StartupBoostEnabled' 0
           Set-Reg $p 'BackgroundModeEnabled' 0
       }
       Undo = { Remove-Prop 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' @('StartupBoostEnabled','BackgroundModeEnabled') } },

    @{ Name = 'Disable Windows lock-screen tips';
       Desc = 'Removes promotional tips and suggestions from the lock screen.';
       Apply = {
           $p = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
           Set-Reg $p 'RotatingLockScreenOverlayEnabled' 0
           Set-Reg $p 'SubscribedContent-338387Enabled' 0
       }
       Undo = { Remove-Prop 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' @('RotatingLockScreenOverlayEnabled','SubscribedContent-338387Enabled') } },

    @{ Name = 'Disable Delivery Optimization peer sharing';
       Desc = 'Stops Windows Update from sharing update downloads with other PCs. Windows Update still works.';
       Apply = { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0 }
       Undo = { Remove-Prop 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' @('DODownloadMode') } },

    @{ Name = 'Turn off taskbar widgets button';
       Desc = 'Hides the Widgets button for the current user. Reversible from this app.';
       Apply = { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa' 0 }
       Undo = { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa' 1 } },

    @{ Name = 'Stop tracking recently opened documents';
       Desc = 'Stops Windows from keeping recent-document history in Start and Jump Lists. This is mainly a privacy and clutter setting.';
       Apply = { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackDocs' 0 }
       Undo = { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackDocs' 1 } },

    @{ Name = 'Disable tailored Windows experiences';
       Desc = 'Stops Windows from using diagnostic data to personalize tips and recommendations.';
       Apply = { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1 }
       Undo = { Remove-Prop 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' @('DisableTailoredExperiencesWithDiagnosticData') } },

    @{ Name = 'Do not reopen apps automatically after sign-in';
       Desc = 'Stops supported apps from reopening automatically after a restart or sign-in. Apps you add to Startup are unaffected.';
       Apply = { Set-Reg 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon' 'RestartApps' 0 }
       Undo = { Remove-Prop 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon' @('RestartApps') } }
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
       Desc = 'Troubleshooting option for persistent high disk usage. Disabling it can make some systems slower; do not use by default.'
       Apply = { Set-SvcStart @('SysMain') 'disabled' }
       Undo  = { Set-SvcStart @('SysMain') 'auto' } },

    @{ Name = 'Disable Windows Search indexer'; Risk = 'Medium'
       Desc = 'Stops file indexing, which can reduce background disk activity on some PCs. File and Start search become slower.'
       Apply = { Set-SvcStart @('WSearch') 'disabled' }
       Undo  = { Set-SvcStart @('WSearch') 'delayed-auto' } },

    @{ Name = 'Disable Xbox services'; Risk = 'Medium'
       Desc = 'Disables Xbox sign-in, Game Pass integration, and some Xbox controller features. Leave enabled if you use Xbox services or an Xbox controller.'
       Apply = { Set-SvcStart @('XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc') 'disabled' }
       Undo  = { Set-SvcStart @('XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc') 'demand' } },

    @{ Name = 'Disable Print Spooler + Fax'; Risk = 'Medium'
       Desc = 'Disables printing and fax services. Do not use if you print, scan through a printer, or use fax software.'
       Apply = { Set-SvcStart @('Spooler','Fax') 'disabled' }
       Undo  = { Set-SvcStart @('Spooler') 'auto'; Set-SvcStart @('Fax') 'demand' } },

    @{ Name = 'Disable Bluetooth services'; Risk = 'Medium'
       Desc = 'Disables Bluetooth support. Do not use with Bluetooth controllers, mice, keyboards, or headsets.'
       Apply = { Set-SvcStart @('bthserv','BTAGService','BthAvctpSvc') 'disabled' }
       Undo  = { Set-SvcStart @('bthserv','BTAGService','BthAvctpSvc') 'demand' } },

    @{ Name = 'Disable useless background services'; Risk = 'Medium'
       Desc = 'Maps, retail demo, error reporting, Insider, geolocation, hotspot, remote registry, etc.'
       Apply = { Set-SvcStart @('MapsBroker','RetailDemo','WerSvc','wisvc','lfsvc','icssvc','WMPNetworkSvc','RemoteRegistry','TrkWks','dmwappushservice','PhoneSvc','WalletService','diagnosticshub.standardcollector.service') 'disabled' }
       Undo  = { Set-SvcStart @('MapsBroker','RetailDemo','WerSvc','wisvc','lfsvc','icssvc','WMPNetworkSvc','TrkWks','dmwappushservice','PhoneSvc','WalletService','diagnosticshub.standardcollector.service') 'demand'; Set-SvcStart @('RemoteRegistry') 'disabled' } },

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
       Desc = 'Turns off OneDrive sync and closes it. Do not use if OneDrive backs up your Desktop, Documents, or Pictures.'
       Apply = { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1; taskkill /f /im OneDrive.exe 2>&1 | Out-Null }
       Undo  = { Remove-Prop 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' @('DisableFileSyncNGSC') } },

    @{ Name = 'Max-performance visual effects'; Risk = 'Low'
       Desc = 'Turns off non-essential window/taskbar animations for snappy UI responsiveness.'
       Apply = {
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2
           Set-Reg 'HKCU:\Control Panel\Desktop' 'UserPreferencesMask' ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) 'Binary'
           Set-Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 0
       }
       Undo = {
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 0
           Set-Reg 'HKCU:\Control Panel\Desktop' 'UserPreferencesMask' ([byte[]](0x9E,0x3E,0x07,0x80,0x12,0x00,0x00,0x00)) 'Binary'
           Set-Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '1' 'String'
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 1
       } },

    @{ Name = 'Disable CPU power throttling'; Risk = 'Medium'
       Desc = 'Prevents Windows EcoQoS power throttling. Can increase heat and power use; does not guarantee more FPS.'
       Apply = { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1 }
       Undo  = { Remove-Prop 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' @('PowerThrottlingOff') } },

    @{ Name = 'Gaming CPU scheduling priority'; Risk = 'Low'
       Desc = 'Changes multimedia scheduling and foreground priority values. Experimental; results vary and it can affect audio/video workloads.'
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

    @{ Name = 'Network scheduling / TCP delay test'; Risk = 'Medium'
       Desc = 'Disables Windows multimedia network throttling. This is experimental and does not guarantee lower ping or better FPS.'
       Apply = {
           reg add 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' /v NetworkThrottlingIndex /t REG_DWORD /d 0xffffffff /f 2>&1 | Out-Null
           Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' | ForEach-Object {
               Set-Reg $_.PSPath 'TcpAckFrequency' 1
               Set-Reg $_.PSPath 'TCPNoDelay' 1
           }
       }
       Undo = {
           reg add 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' /v NetworkThrottlingIndex /t REG_DWORD /d 10 /f 2>&1 | Out-Null
           Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' | ForEach-Object {
               Remove-Prop $_.PSPath @('TcpAckFrequency','TCPNoDelay')
           }
       } },

    @{ Name = 'Hardware-accelerated GPU scheduling (HAGS)'; Risk = 'Medium'
       Desc = 'Requests Hardware-Accelerated GPU Scheduling. It only works on supported GPU/driver combinations and may not help every game. Reboot required.'
       Apply = { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 }
       Undo  = { Remove-Prop 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' @('HwSchMode') } },

    @{ Name = 'MPO display workaround'; Risk = 'Medium'
       Desc = 'Troubleshooting workaround for flicker or black screens. Do not enable unless you are experiencing a display issue.'
       Apply = { Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\DWM' 'OverlayTestMode' 5 }
       Undo  = { Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\DWM' 'OverlayTestMode' -ErrorAction SilentlyContinue } },

    @{ Name = 'Disable fullscreen optimizations'; Risk = 'Low'
       Desc = 'Changes legacy fullscreen behavior flags. Results vary by game; use per-game compatibility settings first.'
       Apply = {
           $p = 'HKCU:\System\GameConfigStore'
           Set-Reg $p 'GameDVR_FSEBehaviorMode' 2; Set-Reg $p 'GameDVR_HonorUserFSEBehaviorMode' 1; Set-Reg $p 'GameDVR_DXGIHonorFSEWindowsCompatible' 1
       }
       Undo = {
           $p = 'HKCU:\System\GameConfigStore'
           Set-Reg $p 'GameDVR_FSEBehaviorMode' 0; Set-Reg $p 'GameDVR_HonorUserFSEBehaviorMode' 0; Set-Reg $p 'GameDVR_DXGIHonorFSEWindowsCompatible' 0
       } },

    @{ Name = 'Windows Update: notify only (no auto reboot)'; Risk = 'Medium'
       Desc = 'Stops automatic updates and forced reboots while working or gaming.'
       Apply = {
           $p = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
           Set-Reg $p 'AUOptions' 2; Set-Reg $p 'NoAutoRebootWithLoggedOnUsers' 1
       }
       Undo = { Remove-Prop 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' @('AUOptions','NoAutoRebootWithLoggedOnUsers') } },

    @{ Name = 'Disable Core Isolation / VBS (Memory Integrity)'; Risk = 'High'
       Desc = 'Disables VBS and Memory Integrity security protections. This can reduce security; only test if you understand the trade-off. Reboot required.'
       Apply = {
           Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0
           Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0
       }
       Undo = {
           Remove-Prop 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' @('Enabled')
           Remove-Prop 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' @('EnableVirtualizationBasedSecurity')
       } }
)


# Further advanced controls. Medium/high items are opt-in and are never preselected.
$Extreme += @(
    @{ Name = 'Disable Microsoft Store auto app updates'; Risk = 'Medium';
       Desc = 'Stops Store apps from updating automatically. You must check for app updates manually.';
       Apply = { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore' 'AutoDownload' 2 }
       Undo = { Remove-Prop 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore' @('AutoDownload') } },

    @{ Name = 'Disable USB selective suspend (AC power)'; Risk = 'Medium';
       Desc = 'Can help diagnose USB mouse/controller disconnects. Uses more power and is not a universal latency tweak.';
       Apply = {
           powercfg -setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 | Out-Null
           powercfg -setactive SCHEME_CURRENT | Out-Null
       }
       Undo = {
           powercfg -setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1 | Out-Null
           powercfg -setactive SCHEME_CURRENT | Out-Null
       } },

    @{ Name = 'Disable PCIe Link State Power Management (AC)'; Risk = 'Medium';
       Desc = 'Disables PCIe link power saving while plugged in. May increase idle power and temperatures; test only if troubleshooting stutter.';
       Apply = {
           powercfg -setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0 | Out-Null
           powercfg -setactive SCHEME_CURRENT | Out-Null
       }
       Undo = {
           powercfg -setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 1 | Out-Null
           powercfg -setactive SCHEME_CURRENT | Out-Null
       } },

    @{ Name = 'Disable Windows Fast Startup'; Risk = 'Medium';
       Desc = 'Uses a full shutdown instead of hybrid shutdown. Can help troubleshoot driver or dual-boot issues; boot may take longer.';
       Apply = { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0 }
       Undo = { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 1 } }
)

# High-risk security bypasses and speculative-execution mitigation disabling are not included.

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
    'Windows Terminal' = 'Microsoft.WindowsTerminal'
    'PowerShell 7'     = 'Microsoft.PowerShell'
}

# ---------- GUI XAML ----------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="EduUtil | Windows Utility" Width="1080" Height="760" MinWidth="900" MinHeight="650" WindowStartupLocation="CenterScreen"
        Background="#111318" FontFamily="Segoe UI" Foreground="#E6E8ED">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Background" Value="#3B82F6"/>
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
      <TextBlock Text="EDUUTIL" FontSize="19" FontWeight="SemiBold" Margin="0,0,0,2" Foreground="#E6E8ED"/>
      <TextBlock Text="SYSTEM UTILITY" FontSize="9" Foreground="#737B8C" Margin="1,0,0,20"/>
      <Button Name="navTweaks"  Content="Tweaks"     Margin="0,0,0,8" HorizontalContentAlignment="Left"/>
      <Button Name="navExtreme" Content="Advanced" Margin="0,0,0,8" HorizontalContentAlignment="Left" Background="#303642"/>
      <Button Name="navInstall" Content="Applications" Margin="0,0,0,8" HorizontalContentAlignment="Left"/>
      <Button Name="navClean"   Content="Maintenance"    Margin="0,0,0,8" HorizontalContentAlignment="Left"/>
      <Button Name="navSysInfo" Content="System info" Margin="0,0,0,8" HorizontalContentAlignment="Left" Background="#303642"/>
    </StackPanel>

    <Grid Grid.Column="1">
      <Grid.RowDefinitions>
        <RowDefinition Height="*"/>
        <RowDefinition Height="30"/>
      </Grid.RowDefinitions>

      <Grid Grid.Row="0">
        <DockPanel Name="pgTweaks">
          <StackPanel DockPanel.Dock="Top" Margin="0,0,0,10">
            <TextBlock Text="Everyday optimizations" FontSize="19" FontWeight="SemiBold" Margin="0,0,0,4"/>
            <TextBlock Text="Practical Windows, privacy, and gaming settings. Choose only what you want to change." Foreground="#8D95A5" FontSize="12" Margin="0,0,0,10"/>
            <TextBox Name="txtTweakSearch" Height="32" Padding="9,5" Background="#1A1E26" Foreground="#E6E8ED" BorderBrush="#303642" BorderThickness="1" ToolTip="Filter everyday optimizations" />
          </StackPanel>
          <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,10,0,8">
            <Button Name="btnApply" Content="Apply selected"/>
            <Button Name="btnUndo"  Content="Restore defaults" Background="#303642" ToolTip="Applies common Windows defaults; it may not restore custom settings that existed before EduUtil was run."/>
            <Button Name="btnRP"    Content="Create restore point" Background="#303642"/>
          </StackPanel>
          <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Name="tweakList"/></ScrollViewer>
        </DockPanel>

        <DockPanel Name="pgExtreme" Visibility="Collapsed">
          <StackPanel DockPanel.Dock="Top" Margin="0,0,0,10">
            <TextBlock Text="Advanced controls" FontSize="19" FontWeight="SemiBold" Margin="0,0,0,4"/>
            <TextBlock TextWrapping="Wrap" Foreground="#AEB5C2" FontSize="12" Margin="0,0,0,10"
                       Text="Optional system-level changes. Some trade performance, compatibility, security, battery life, or Windows features. Nothing is preselected."/>
            <TextBox Name="txtExtremeSearch" Height="32" Padding="9,5" Background="#1A1E26" Foreground="#E6E8ED" BorderBrush="#303642" BorderThickness="1" ToolTip="Filter advanced controls" />
          </StackPanel>
          <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,10,0,8">
            <Button Name="btnXApply" Content="Apply selected" Background="#8D3A3A"/>
            <Button Name="btnXUndo"  Content="Restore defaults" Background="#303642" ToolTip="Applies common defaults; it may not restore custom settings that existed before EduUtil was run."/>
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
          <TextBlock Text="Cleanup only removes temporary files. Shader caches are rebuilt by games and may cause a short first-run stutter." Foreground="#8D95A5" FontSize="12" TextWrapping="Wrap" Margin="0,0,0,14"/>
          <Button Name="btnTemp"    Content="Clean temporary files"              Margin="0,0,0,10" HorizontalAlignment="Left"/>
          <Button Name="btnBin"     Content="Empty Recycle Bin"                  Margin="0,0,0,10" HorizontalAlignment="Left"/>
          <Button Name="btnDns"     Content="Flush DNS cache"                    Margin="0,0,0,10" HorizontalAlignment="Left"/>
          <Button Name="btnShader"  Content="Clear GPU shader caches"             Margin="0,0,0,10" HorizontalAlignment="Left"/>
          <Button Name="btnOptimizeDrive" Content="Optimize system drive (TRIM / defrag)" Margin="0,0,0,10" HorizontalAlignment="Left"/>
          <Button Name="btnNetworkReset" Content="Reset network stack"            Margin="0,0,0,10" HorizontalAlignment="Left"/>
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

      <Border Grid.Row="1" Background="#191D25" CornerRadius="5" Padding="8,3" Margin="0,8,0,0">
        <TextBlock Name="txtStatus" Text="Ready" Foreground="#AAB2C0" FontSize="11" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
      </Border>
    </Grid>
  </Grid>
</Window>
'@

$window = [System.Windows.Markup.XamlReader]::Parse($xaml)
foreach ($n in 'navTweaks','navExtreme','navInstall','navClean','navSysInfo','pgTweaks','pgExtreme','pgInstall','pgClean','pgSysInfo','tweakList','extremeList','appList','btnXApply','btnXUndo',
               'btnApply','btnUndo','btnRP','btnInstall','btnTemp','btnBin','btnDns','btnShader','btnOptimizeDrive','btnNetworkReset','btnSfc','btnRefreshInfo','txtSysInfo','txtStatus','txtTweakSearch','txtExtremeSearch') {
    Set-Variable -Name $n -Value $window.FindName($n)
}

# Build the searchable option lists
foreach ($t in $Tweaks) {
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Content = $t.Name; $cb.ToolTip = $t.Desc; $cb.Tag = $t
    [void]$tweakList.Children.Add($cb)
    $desc = New-Object System.Windows.Controls.TextBlock
    $desc.Text = $t.Desc; $desc.Foreground = '#8A90A0'; $desc.FontSize = 11
    $desc.Margin = '24,-2,0,5'; $desc.TextWrapping = 'Wrap'
    $desc.Tag = $t.Name
    [void]$tweakList.Children.Add($desc)
}
foreach ($t in $Extreme) {
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Content = "$($t.Name)   [$($t.Risk)]"; $cb.ToolTip = $t.Desc; $cb.Tag = $t
    if ($t.Risk -eq 'High') { $cb.Foreground = '#D97878' } elseif ($t.Risk -eq 'Medium') { $cb.Foreground = '#C9A96A' }
    [void]$extremeList.Children.Add($cb)
    $desc = New-Object System.Windows.Controls.TextBlock
    $desc.Text = $t.Desc; $desc.Foreground = '#8A90A0'; $desc.FontSize = 11
    $desc.Margin = '24,-2,0,5'; $desc.TextWrapping = 'Wrap'
    $desc.Tag = $t.Name
    [void]$extremeList.Children.Add($desc)
}
foreach ($k in $Apps.Keys) {
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Content = $k; $cb.Tag = $Apps[$k]; $cb.Width = 220
    [void]$appList.Children.Add($cb)
}


function Set-ListFilter($panel, $query) {
    $term = [string]$query
    for ($i = 0; $i -lt $panel.Children.Count; $i += 2) {
        $cb = $panel.Children[$i]
        $desc = if (($i + 1) -lt $panel.Children.Count) { $panel.Children[$i + 1] } else { $null }
        $haystack = "$($cb.Content) $($cb.ToolTip)"
        $visible = [string]::IsNullOrWhiteSpace($term) -or $haystack.IndexOf($term, [StringComparison]::OrdinalIgnoreCase) -ge 0
        $visibility = if ($visible) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        $cb.Visibility = $visibility
        if ($desc) { $desc.Visibility = $visibility }
    }
}
$txtTweakSearch.Add_TextChanged({ Set-ListFilter $tweakList $txtTweakSearch.Text })
$txtExtremeSearch.Add_TextChanged({ Set-ListFilter $extremeList $txtExtremeSearch.Text })

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
    $bios = Get-CimInstance Win32_BIOS
    $board = Get-CimInstance Win32_BaseBoard
    $disk = Get-CimInstance Win32_LogicalDisk | Where-Object DeviceID -eq $env:SystemDrive

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
 Driver: $($gpu.DriverVersion)
--------------------------------------------------
 Motherboard: $($board.Manufacturer) $($board.Product)
 BIOS: $($bios.SMBIOSBIOSVersion)
 System: $($cs.SystemType)
--------------------------------------------------
 RAM: ${freeRamGB} GB Free / ${totalRamGB} GB Total
 $($env:SystemDrive) Drive: ${diskFreeGB} GB Free / ${diskTotalGB} GB Total
 Computer Name: $($cs.Name)
==================================================
"@
    $txtSysInfo.Text = $info
    Log 'System specifications loaded.'
}

$btnRefreshInfo.Add_Click({ Refresh-SysInfo })

function Run-Tweaks($mode, $list) {
    $picked = @($list.Children | Where-Object { $_ -is [System.Windows.Controls.CheckBox] -and $_.IsChecked -and $_.Visibility -ne [System.Windows.Visibility]::Collapsed })
    if ($picked.Count -eq 0) { Log 'No visible items selected.'; return }

    if ($list -eq $extremeList -and $mode -eq 'Apply') {
        $names = ($picked | ForEach-Object { $_.Tag.Name }) -join "`n- "
        $ans = [System.Windows.MessageBox]::Show("Apply these advanced system changes?`n`n- $names`n`nSome options can affect security, compatibility, device behavior, or power use. A restore point will be attempted first.", 'EduUtil', 'YesNo', 'Warning')
        if ($ans -ne 'Yes') { Log 'Advanced changes cancelled.'; return }
    }

    if ($mode -eq 'Apply') {
        $restoreOk = New-SafeRestorePoint
        if (-not $restoreOk) {
            $ans = [System.Windows.MessageBox]::Show('Windows could not create a restore point. Continue anyway? A restore point is strongly recommended before system changes.', 'EduUtil', 'YesNo', 'Warning')
            if ($ans -ne 'Yes') { Log 'Cancelled because no restore point was available.'; return }
        }
    }

    $failed = 0
    $errors = @()
    foreach ($cb in $picked) {
        try {
            Log "$mode : $($cb.Tag.Name)"
            $action = $cb.Tag[$mode]
            if ($action -is [scriptblock]) { & $action }
            Log "Completed: $($cb.Tag.Name)"
        } catch {
            $failed++
            $errors += "$($cb.Tag.Name): $($_.Exception.Message)"
            Log "Failed: $($cb.Tag.Name)"
        }
    }
    if ($failed -eq 0) {
        Log 'Finished. Some settings need a sign-out or restart to take effect.'
    } else {
        $details = ($errors | Select-Object -First 8) -join "`n"
        [System.Windows.MessageBox]::Show("Finished with $failed item(s) that could not be applied:`n`n$details", 'EduUtil', 'OK', 'Warning') | Out-Null
        Log "Finished with $failed failed item(s)."
    }
}

$btnApply.Add_Click({ Run-Tweaks 'Apply' $tweakList })
$btnXApply.Add_Click({ Run-Tweaks 'Apply' $extremeList })
$btnXUndo.Add_Click({ Run-Tweaks 'Undo' $extremeList })
$btnUndo.Add_Click({ Run-Tweaks 'Undo' $tweakList })
$btnRP.Add_Click({ $script:rpDone = $false; [void](New-SafeRestorePoint) })

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
    $ans = [System.Windows.MessageBox]::Show('Remove temporary files from your user Temp folder and Windows Temp folder? Open files will be skipped.', 'EduUtil', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }
    Log 'Cleaning temporary files...'
    $targets = @($env:TEMP, "$env:WINDIR\Temp") | Select-Object -Unique
    foreach ($target in $targets) {
        if (Test-Path -LiteralPath $target) {
            Get-ChildItem -LiteralPath $target -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Log 'Temporary-file cleanup finished. Files in use were skipped.'
})

$btnBin.Add_Click({
    $ans = [System.Windows.MessageBox]::Show('Permanently empty the Recycle Bin for this user?', 'EduUtil', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Log 'Recycle Bin cleanup completed.'
})

$btnDns.Add_Click({ 
    ipconfig /flushdns | Out-Null
    Log 'DNS resolver cache flushed.' 
})

$btnShader.Add_Click({
    $ans = [System.Windows.MessageBox]::Show('Clear detected GPU shader caches? Games and apps will rebuild them, which can cause temporary stutter the next time they launch.', 'EduUtil', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }
    Log 'Clearing GPU shader caches...'
    $cachePaths = @(
        "$env:LOCALAPPDATA\D3DSCache",
        "$env:LOCALAPPDATA\NVIDIA\DXCache",
        "$env:LOCALAPPDATA\NVIDIA\GLCache",
        "$env:LOCALAPPDATA\AMD\DxCache",
        "$env:LOCALAPPDATA\AMD\GLCache"
    )
    foreach ($cachePath in $cachePaths) {
        if (Test-Path -LiteralPath $cachePath) {
            Get-ChildItem -LiteralPath $cachePath -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Log 'GPU shader cache cleanup finished.'
})

$btnOptimizeDrive.Add_Click({
    try {
        $driveLetter = $env:SystemDrive.TrimEnd(':')
        Log "Optimizing $env:SystemDrive ..."
        Optimize-Volume -DriveLetter $driveLetter -ErrorAction Stop | Out-Null
        Log 'Drive optimization completed. Windows selected the appropriate SSD/HDD operation.'
    } catch {
        Log "Drive optimization failed: $($_.Exception.Message)"
    }
})

$btnNetworkReset.Add_Click({
    $ans = [System.Windows.MessageBox]::Show('Reset Winsock and the TCP/IP stack? This can fix some network problems, but may remove custom network settings and requires a restart. It does not guarantee lower game ping.', 'EduUtil', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }
    try {
        Log 'Resetting Winsock and TCP/IP...'
        Start-Process -FilePath 'netsh.exe' -ArgumentList 'winsock reset' -WindowStyle Hidden -Wait -ErrorAction Stop | Out-Null
        Start-Process -FilePath 'netsh.exe' -ArgumentList 'int ip reset' -WindowStyle Hidden -Wait -ErrorAction Stop | Out-Null
        Log 'Network stack reset completed. Restart Windows to finish.'
    } catch {
        Log "Network reset failed: $($_.Exception.Message)"
    }
})

$btnSfc.Add_Click({
    $ans = [System.Windows.MessageBox]::Show('Run System File Checker and DISM image repair? This may take a while. The repair process will run silently in the background.', 'EduUtil', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }
    try {
        $repairCommand = 'sfc /scannow; DISM.exe /Online /Cleanup-Image /RestoreHealth'
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($repairCommand))
        Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $encoded" -WindowStyle Hidden
        Log 'Windows repair started in the background.'
    } catch {
        Log "Could not start Windows repair: $($_.Exception.Message)"
    }
})

Log 'Ready. Select only the settings you want to change.'
[void]$window.ShowDialog()
