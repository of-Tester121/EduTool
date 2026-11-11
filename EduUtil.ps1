#requires -Version 5.1
<#
.SYNOPSIS
    EduUtil - Windows Performance & Maintenance Utility 

#>

$RepoUrl = 'https://raw.githubusercontent.com/of-Tester121/EduTool/main/EduUtil.ps1'
$AppVersion = '2.0'

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

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# ---------- data folder / logging ----------
$DataDir    = Join-Path $env:ProgramData 'EduUtil'
$BackupFile = Join-Path $DataDir 'backup.json'
$LogFile    = Join-Path $DataDir 'EduUtil.log'
if (-not (Test-Path -LiteralPath $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }
$script:LogLines = New-Object System.Collections.Generic.List[string]
$script:window = $null

# ---------- helpers ----------
function Set-Reg {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()]$Value,
        [ValidateSet('DWord','QWord','String','ExpandString','MultiString','Binary')][string]$Type = 'DWord'
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
}

function Get-RegValue($Path, $Name) {
    try {
        $k = Get-Item -LiteralPath $Path -ErrorAction Stop
        return $k.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
    } catch { return $null }
}

function Remove-Prop($path, $names) {
    foreach ($n in $names) { Remove-ItemProperty -LiteralPath $path -Name $n -ErrorAction SilentlyContinue }
}

function Pump {
    if ($script:window) {
        $script:window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
    }
}

function Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg"
    $script:LogLines.Add($line)
    try { Add-Content -LiteralPath $LogFile -Value $line -ErrorAction SilentlyContinue } catch { }
    if ($txtStatus) {
        $txtStatus.Text = "$(Get-Date -Format 'HH:mm')  |  $msg"
        if ($txtLog) { $txtLog.AppendText($line + [Environment]::NewLine); $txtLog.ScrollToEnd() }
        Pump
    }
}

function Confirm-Action($text, $icon = 'Question') {
    return ([System.Windows.MessageBox]::Show($text, 'EduUtil', 'YesNo', $icon) -eq 'Yes')
}

$script:BusyDepth = 0
function Set-Busy([bool]$busy) {
    if ($busy) { $script:BusyDepth++ } else { $script:BusyDepth = [math]::Max(0, $script:BusyDepth - 1) }
    $isBusy = $script:BusyDepth -gt 0
    if ($rootGrid) { $rootGrid.IsEnabled = -not $isBusy }
    if ($script:window) { $script:window.Cursor = if ($isBusy) { [System.Windows.Input.Cursors]::Wait } else { $null } }
    Pump
}

# Run an external program hidden while keeping the window responsive.
function Invoke-Hidden([string]$File, [string]$Arguments = '') {
    Set-Busy $true
    try {
        $sp = @{ FilePath = $File; WindowStyle = 'Hidden'; PassThru = $true; ErrorAction = 'Stop' }
        if ($Arguments) { $sp.ArgumentList = $Arguments }
        $p = Start-Process @sp
        $null = $p.Handle
        while (-not $p.HasExited) { Pump; Start-Sleep -Milliseconds 150 }
        return $p.ExitCode
    } finally { Set-Busy $false }
}

function Get-FolderSizeMB($paths) {
    $total = 0
    foreach ($p in @($paths)) {
        if ($p -and (Test-Path -LiteralPath $p)) {
            $s = (Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            if ($s) { $total += $s }
        }
    }
    return [math]::Round($total / 1MB, 1)
}

function Restart-Explorer {
    Log 'Restarting Explorer...'
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    Log 'Explorer restarted.'
}

$script:rpDone = $false
function New-SafeRestorePoint {
    if ($script:rpDone) { return $true }
    Log 'Creating a Windows restore point...'
    $srKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $oldFreq = Get-RegValue $srKey 'SystemRestorePointCreationFrequency'
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
        # Windows silently skips restore points if one was made in the last 24h; lift that limit temporarily.
        Set-Reg $srKey 'SystemRestorePointCreationFrequency' 0
        Checkpoint-Computer -Description "EduUtil $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction SilentlyContinue
        $script:rpDone = $true
        Log 'Restore point created.'
        return $true
    } catch {
        Log "Restore point unavailable: $($_.Exception.Message)"
        return $false
    } finally {
        if ($null -eq $oldFreq) { Remove-Prop $srKey @('SystemRestorePointCreationFrequency') } else { Set-Reg $srKey 'SystemRestorePointCreationFrequency' $oldFreq }
    }
}

# ---------- backup store (exact undo) ----------
$script:Backup = @{}
if (Test-Path -LiteralPath $BackupFile) {
    try {
        $raw = Get-Content -LiteralPath $BackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        foreach ($prop in $raw.PSObject.Properties) {
            $h = @{}
            foreach ($q in $prop.Value.PSObject.Properties) { $h[$q.Name] = $q.Value }
            $script:Backup[$prop.Name] = $h
        }
    } catch { $script:Backup = @{} }
}
function Save-BackupFile {
    try { $script:Backup | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $BackupFile -Encoding UTF8 -ErrorAction Stop } catch { }
}

function Backup-RegValue($Path, $Name) {
    $key = "reg|$Path|$Name"
    if ($script:Backup.ContainsKey($key)) { return }
    $entry = @{ Exists = $false; Value = $null; Kind = $null }
    try {
        $k = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($k.GetValueNames() -contains $Name) {
            $kind = [string]$k.GetValueKind($Name)
            $val  = $k.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
            if ($kind -eq 'Binary') { $val = [Convert]::ToBase64String([byte[]]$val) }
            $entry = @{ Exists = $true; Value = $val; Kind = $kind }
        }
    } catch { }
    $script:Backup[$key] = $entry
}

function Restore-RegValue($Path, $Name) {
    $key = "reg|$Path|$Name"
    if (-not $script:Backup.ContainsKey($key)) { return $false }
    $b = $script:Backup[$key]
    if ($b.Exists -and $b.Kind -in 'DWord','QWord','String','ExpandString','MultiString','Binary') {
        $v = $b.Value
        switch ($b.Kind) {
            'Binary'      { $v = [Convert]::FromBase64String([string]$v) }
            'MultiString' { $v = [string[]]@($v) }
            'DWord'       { $v = [int64]$v; if ($v -gt [int32]::MaxValue) { $v = [int32]($v - 4294967296) } else { $v = [int32]$v } }
            'QWord'       { $v = [int64]$v }
        }
        Set-Reg $Path $Name $v $b.Kind
    } elseif (-not $b.Exists) {
        Remove-Prop $Path @($Name)
    }
    $script:Backup.Remove($key)
    return $true
}

# Registry spec shorthand: RegV <path> <name> <value> [type] [default-if-no-backup]
$NoDefault = '__EDU_REMOVE__'
function RegV($P, $N, $V, $T = 'DWord', $D = $NoDefault) { @{ P = $P; N = $N; V = $V; T = $T; D = $D } }

# Power-setting spec: AC value index for SCHEME_CURRENT
function PwrV($Sub, $Setting, $V, $D) { @{ Sub = $Sub; Set = $Setting; V = $V; D = $D } }

function Get-PowerAcValue($sub, $setting) {
    $out = (powercfg /qh SCHEME_CURRENT $sub $setting 2>$null) -join "`n"
    $hex = [regex]::Matches($out, '0x([0-9a-fA-F]{8})')
    if ($hex.Count -ge 2) { return [Convert]::ToInt32($hex[$hex.Count - 2].Groups[1].Value, 16) }
    return $null
}

function Get-SvcStartMode($name) {
    $svc = Get-Service $name -ErrorAction SilentlyContinue
    if (-not $svc) { return $null }
    switch ([string]$svc.StartType) {
        'Automatic' {
            $delayed = Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Services\$name" 'DelayedAutostart'
            if ($delayed -eq 1) { return 'delayed-auto' } else { return 'auto' }
        }
        'Manual'   { return 'demand' }
        'Disabled' { return 'disabled' }
        'Boot'     { return 'boot' }
        'System'   { return 'system' }
    }
    return 'demand'
}

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

function Test-TaskDisabled($task) {
    $idx = $task.LastIndexOf('\')
    $path = $task.Substring(0, $idx + 1); $name = $task.Substring($idx + 1)
    $st = Get-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction SilentlyContinue
    if (-not $st) { return $null }
    return ([string]$st.State -eq 'Disabled')
}

# ---------- generic tweak engine ----------
# A tweak may contain any combination of:
#   Reg   = @( (R path name value [type] [default]) ... )   registry values (backed up)
#   Svc   = @('ServiceName' ...); SvcDefault = 'demand'     services to disable (start mode backed up)
#   Tasks = @('\Path\Task' ...)                             scheduled tasks to disable
#   Pwr   = @( (PwrV sub setting value default) ... )         AC power settings of the active plan (backed up)
#   Apply / Undo / Test = { scriptblocks }                  custom logic
#   Reboot = $true / Explorer = $true                       post-action prompts
function Invoke-Tweak($t, $mode) {
    if ($t.Reg) {
        foreach ($s in $t.Reg) {
            if ($mode -eq 'Apply') {
                Backup-RegValue $s.P $s.N
                Set-Reg $s.P $s.N $s.V $s.T
            } else {
                if (-not (Restore-RegValue $s.P $s.N)) {
                    if ($s.D -is [string] -and $s.D -eq $NoDefault) { Remove-Prop $s.P @($s.N) }
                    else { Set-Reg $s.P $s.N $s.D $s.T }
                }
            }
        }
    }
    if ($t.Svc) {
        foreach ($n in $t.Svc) {
            $key = "svc|$n"
            if ($mode -eq 'Apply') {
                $cur = Get-SvcStartMode $n
                if ($null -eq $cur) { continue }
                if (-not $script:Backup.ContainsKey($key)) { $script:Backup[$key] = @{ Mode = $cur } }
                Set-SvcStart @($n) 'disabled'
            } else {
                $m = if ($script:Backup.ContainsKey($key)) { $script:Backup[$key].Mode } elseif ($t.SvcDefault) { $t.SvcDefault } else { 'demand' }
                if ($m -eq 'disabled' -and -not $script:Backup.ContainsKey($key)) { $m = 'demand' }
                Set-SvcStart @($n) $m
                $script:Backup.Remove($key)
            }
        }
    }
    if ($t.Tasks) { Set-Tasks $t.Tasks ($mode -ne 'Apply') }
    if ($t.Pwr) {
        foreach ($s in $t.Pwr) {
            $key = "pwr|$($s.Sub)|$($s.Set)"
            if ($mode -eq 'Apply') {
                if (-not $script:Backup.ContainsKey($key)) {
                    $cur = Get-PowerAcValue $s.Sub $s.Set
                    if ($null -ne $cur) { $script:Backup[$key] = @{ Value = $cur } }
                }
                powercfg -attributes $s.Sub $s.Set -ATTRIB_HIDE 2>$null | Out-Null
                powercfg -setacvalueindex SCHEME_CURRENT $s.Sub $s.Set $s.V | Out-Null
            } else {
                $v = if ($script:Backup.ContainsKey($key)) { $script:Backup[$key].Value } else { $s.D }
                powercfg -setacvalueindex SCHEME_CURRENT $s.Sub $s.Set $v | Out-Null
                $script:Backup.Remove($key)
            }
        }
        powercfg -setactive SCHEME_CURRENT | Out-Null
    }
    $action = $t[$mode]
    if ($action -is [scriptblock]) { & $action }
    Save-BackupFile
}

function Test-Tweak($t) {
    try {
        if ($t.Test -is [scriptblock]) { return [bool](& $t.Test) }
        $results = @()
        if ($t.Reg) {
            foreach ($s in $t.Reg) {
                $cur = Get-RegValue $s.P $s.N
                if ($null -eq $cur) { $results += $false; continue }
                if ($cur -is [byte[]]) { $results += (($cur -join ',') -eq (([byte[]]$s.V) -join ',')) }
                elseif ($s.T -eq 'DWord' -and ($s.V -is [int] -or $s.V -is [long] -or $s.V -is [uint32])) { $results += ([uint32]([int64]$cur -band 0xFFFFFFFF) -eq [uint32]([int64]$s.V -band 0xFFFFFFFF)) }
                else { $results += ("$cur" -eq "$($s.V)") }
            }
        }
        if ($t.Svc) {
            $existing = @($t.Svc | Where-Object { Get-Service $_ -ErrorAction SilentlyContinue })
            foreach ($n in $existing) { $results += ([string](Get-Service $n).StartType -eq 'Disabled') }
        }
        if ($t.Tasks) {
            foreach ($tk in $t.Tasks) { $r = Test-TaskDisabled $tk; if ($null -ne $r) { $results += $r } }
        }
        if ($t.Pwr) {
            foreach ($s in $t.Pwr) { $results += ((Get-PowerAcValue $s.Sub $s.Set) -eq $s.V) }
        }
        if ($results.Count -eq 0) { return $null }
        return -not ($results -contains $false)
    } catch { return $null }
}

# ======================================================================
#  EVERYDAY TWEAKS  (Category / Preset tags drive grouping and presets)
# ======================================================================
$CDM  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$ADV  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$EDGE = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
$WSP  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'

$Tweaks = @(
    # ---------------- Privacy ----------------
    @{ Name = 'Disable telemetry'; Category = 'Privacy'; Preset = @('Recommended','Privacy')
       Desc = 'Sets diagnostic data to the lowest level your edition allows and disables the Connected User Experiences (DiagTrack) service.'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0),
                 (RegV 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0),
                 (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DisableOneSettingsDownloads' 1) )
       Svc  = @('DiagTrack'); SvcDefault = 'auto' },

    @{ Name = 'Disable activity history'; Category = 'Privacy'; Preset = @('Recommended','Privacy')
       Desc = 'Stops Windows logging and uploading your activity timeline.'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 0),
                 (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0),
                 (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0) ) },

    @{ Name = 'Disable advertising ID'; Category = 'Privacy'; Preset = @('Recommended','Privacy')
       Desc = 'Stops apps from using the per-user advertising ID for personalized ads.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0),
                 (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1) ) },

    @{ Name = 'Reduce Windows feedback prompts'; Category = 'Privacy'; Preset = @('Recommended','Privacy')
       Desc = 'Stops Windows from periodically asking for feedback and showing feedback notifications.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0),
                 (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 1) ) },

    @{ Name = 'Disable app launch tracking'; Category = 'Privacy'; Preset = @('Recommended','Privacy')
       Desc = 'Turns off Start menu app-launch tracking used for personalized suggestions.'
       Reg  = @( (RegV $ADV 'Start_TrackProgs' 0 'DWord' 1) ) },

    @{ Name = 'Stop tracking recently opened documents'; Category = 'Privacy'; Preset = @('Privacy')
       Desc = 'Stops recent-document history in Start and Jump Lists.'
       Reg  = @( (RegV $ADV 'Start_TrackDocs' 0 'DWord' 1) ) },

    @{ Name = 'Disable tailored Windows experiences'; Category = 'Privacy'; Preset = @('Recommended','Privacy')
       Desc = 'Stops Windows from using diagnostic data to personalize tips and recommendations.'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1),
                 (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0) ) },

    @{ Name = 'Disable Windows Recall / AI snapshots'; Category = 'Privacy'; Preset = @('Recommended','Privacy')
       Desc = 'Blocks Recall from saving screen snapshots on Copilot+ PCs. No effect on PCs without Recall.'
       Reg  = @( (RegV 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1),
                 (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1),
                 (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement' 0) ) },

    @{ Name = 'Disable online speech recognition'; Category = 'Privacy'; Preset = @('Privacy')
       Desc = 'Voice typing and speech features stop sending audio to Microsoft. Offline speech still works.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0) ) },

    @{ Name = 'Disable inking & typing personalization'; Category = 'Privacy'; Preset = @('Privacy')
       Desc = 'Stops collecting typing and handwriting samples to build a personal dictionary.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1),
                 (RegV 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1),
                 (RegV 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0),
                 (RegV 'HKCU:\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0) ) },

    @{ Name = 'Disable typing insights'; Category = 'Privacy'; Preset = @('Privacy')
       Desc = 'Turns off typing statistics collected by the touch keyboard and text suggestions.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\input\Settings' 'InsightsEnabled' 0) ) },

    @{ Name = 'Disable cloud clipboard sync'; Category = 'Privacy'; Preset = @('Privacy')
       Desc = 'Clipboard history stays on this PC and is not synced across devices.'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'AllowCrossDeviceClipboard' 0) ) },

    @{ Name = 'Disable location services'; Category = 'Privacy'; Preset = @('Privacy')
       Desc = 'Turns off system location. Breaks Find My Device, automatic time zone, and location in Weather/Maps.'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' 'DisableLocation' 1) ) },

    @{ Name = 'Stop websites reading your language list'; Category = 'Privacy'; Preset = @('Recommended','Privacy')
       Desc = 'Websites can no longer fingerprint you using your installed language list.'
       Reg  = @( (RegV 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' 1) ) },

    @{ Name = 'Disable Windows Error Reporting uploads'; Category = 'Privacy'; Preset = @('Privacy')
       Desc = 'Crash reports are no longer sent to Microsoft. Local crash dumps are still created.'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1) ) },

    @{ Name = 'Opt out of PowerShell 7 / .NET CLI telemetry'; Category = 'Privacy'; Preset = @('Privacy','Developer')
       Desc = 'Sets the official opt-out environment variables for PowerShell 7 and the dotnet CLI (machine-wide).'
       Reg  = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' 'POWERSHELL_TELEMETRY_OPTOUT' '1' 'String'),
                 (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' 'DOTNET_CLI_TELEMETRY_OPTOUT' '1' 'String') ) },

    @{ Name = 'Disable Microsoft Office telemetry'; Category = 'Privacy'; Preset = @('Privacy')
       Desc = 'Applies Office policies to stop sending optional diagnostic data. Only matters if Office is installed.'
       Reg  = @( (RegV 'HKCU:\Software\Policies\Microsoft\office\common\clienttelemetry' 'SendTelemetry' 3),
                 (RegV 'HKCU:\Software\Policies\Microsoft\office\16.0\common\clienttelemetry' 'DisableTelemetry' 1),
                 (RegV 'HKCU:\Software\Policies\Microsoft\office\16.0\common\privacy' 'disconnectedstate' 2) ) },

    # ---------------- Ads & suggestions ----------------
    @{ Name = 'Disable consumer features / suggested apps'; Category = 'Ads & suggestions'; Preset = @('Recommended','Privacy')
       Desc = 'Stops Windows auto-installing promoted apps (Candy Crush etc).'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1),
                 (RegV $CDM 'SilentInstalledAppsEnabled' 0),
                 (RegV $CDM 'PreInstalledAppsEnabled' 0),
                 (RegV $CDM 'OemPreInstalledAppsEnabled' 0) ) },

    @{ Name = 'Turn off Windows tips and suggestions'; Category = 'Ads & suggestions'; Preset = @('Recommended','Privacy')
       Desc = 'Disables promotional suggestions and setup tips in Settings and the Start menu.'
       Reg  = @( (RegV $CDM 'SystemPaneSuggestionsEnabled' 0), (RegV $CDM 'SubscribedContent-338388Enabled' 0),
                 (RegV $CDM 'SubscribedContent-338389Enabled' 0), (RegV $CDM 'SubscribedContent-338393Enabled' 0),
                 (RegV $CDM 'SubscribedContent-353694Enabled' 0), (RegV $CDM 'SubscribedContent-353696Enabled' 0),
                 (RegV $CDM 'SoftLandingEnabled' 0) ) },

    @{ Name = 'Disable lock-screen tips and ads'; Category = 'Ads & suggestions'; Preset = @('Recommended')
       Desc = 'Removes promotional tips and fun facts from the lock screen.'
       Reg  = @( (RegV $CDM 'RotatingLockScreenOverlayEnabled' 0), (RegV $CDM 'SubscribedContent-338387Enabled' 0) ) },

    @{ Name = 'Disable "Finish setting up your device" nags'; Category = 'Ads & suggestions'; Preset = @('Recommended')
       Desc = 'Stops the full-screen "Let''s finish setting up" prompts and the post-update welcome experience.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0),
                 (RegV $CDM 'SubscribedContent-310093Enabled' 0) ) },

    @{ Name = 'Disable File Explorer OneDrive/Microsoft 365 ads'; Category = 'Ads & suggestions'; Preset = @('Recommended')
       Desc = 'Hides sync-provider notifications (ads) shown at the top of File Explorer.'
       Reg  = @( (RegV $ADV 'ShowSyncProviderNotifications' 0) ); Explorer = $true },

    @{ Name = 'Disable Start menu recommendations & account nags'; Category = 'Ads & suggestions'; Preset = @('Recommended')
       Desc = 'Removes promoted apps/websites from Start "Recommended" and Microsoft account reminders (Windows 11).'
       Reg  = @( (RegV $ADV 'Start_IrisRecommendations' 0), (RegV $ADV 'Start_AccountNotifications' 0) ); Explorer = $true },

    @{ Name = 'Disable Bing web results in Start search'; Category = 'Ads & suggestions'; Preset = @('Recommended','Privacy')
       Desc = 'Start menu search only searches your PC - faster and nothing typed is sent to Bing.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0 'DWord' 1),
                 (RegV 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1),
                 (RegV $WSP 'DisableWebSearch' 1), (RegV $WSP 'ConnectedSearchUseWeb' 0), (RegV $WSP 'AllowCortana' 0) ) },

    @{ Name = 'Disable Windows search highlights'; Category = 'Ads & suggestions'; Preset = @('Recommended')
       Desc = 'Removes trending/web highlights from the search box. Local search still works.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 0),
                 (RegV $ADV 'ShowSearchHighlights' 0 'DWord' 1),
                 (RegV $WSP 'EnableDynamicContentInWSB' 0) ) },

    @{ Name = 'Disable Copilot & taskbar button'; Category = 'Ads & suggestions'; Preset = @('Recommended')
       Desc = 'Turns off Windows Copilot policy and removes the taskbar button.'
       Reg  = @( (RegV 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1),
                 (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1),
                 (RegV $ADV 'ShowCopilotButton' 0 'DWord' 1) ); Explorer = $true },

    @{ Name = 'Debloat Microsoft Edge'; Category = 'Ads & suggestions'; Preset = @('Recommended','Privacy')
       Desc = 'Turns off the Edge sidebar, shopping assistant, recommendations, feedback and optional diagnostic data. Edge will show "managed by your organization".'
       Reg  = @( (RegV $EDGE 'HubsSidebarEnabled' 0), (RegV $EDGE 'EdgeShoppingAssistantEnabled' 0),
                 (RegV $EDGE 'PersonalizationReportingEnabled' 0), (RegV $EDGE 'ShowRecommendationsEnabled' 0),
                 (RegV $EDGE 'UserFeedbackAllowed' 0), (RegV $EDGE 'DiagnosticData' 0),
                 (RegV $EDGE 'SpotlightExperiencesAndRecommendationsEnabled' 0), (RegV $EDGE 'ShowMicrosoftRewards' 0),
                 (RegV $EDGE 'EdgeFollowEnabled' 0), (RegV $EDGE 'HideFirstRunExperience' 1) ) },

    @{ Name = 'Disable Edge background startup'; Category = 'Ads & suggestions'; Preset = @('Recommended','Gaming')
       Desc = 'Stops Edge from preloading at sign-in (Startup Boost) and running in the background after closing.'
       Reg  = @( (RegV $EDGE 'StartupBoostEnabled' 0), (RegV $EDGE 'BackgroundModeEnabled' 0) ) },

    @{ Name = 'Stop Edge creating desktop shortcuts on update'; Category = 'Ads & suggestions'; Preset = @('Recommended')
       Desc = 'Edge updates will no longer re-add the Edge icon to your desktop.'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' 'CreateDesktopShortcutDefault' 0) ) },

    @{ Name = 'Turn off taskbar widgets button'; Category = 'Ads & suggestions'; Preset = @()
       Desc = 'Hides the Widgets button. On newer Windows 11 builds use "Disable Widgets / News feed" in Advanced instead.'
       Reg  = @( (RegV $ADV 'TaskbarDa' 0 'DWord' 1) ); Explorer = $true },

    @{ Name = 'Disable News and Interests (Windows 10)'; Category = 'Ads & suggestions'; Preset = @()
       Desc = 'Hides the weather/news taskbar feed on Windows 10.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds' 'ShellFeedsTaskbarViewMode' 2) ); Explorer = $true },

    # ---------------- Gaming & input ----------------
    @{ Name = 'Disable Game DVR / background capture'; Category = 'Gaming & input'; Preset = @('Recommended','Gaming')
       Desc = 'Removes background recording overhead. Use OBS/ShadowPlay if you still want clips.'
       Reg  = @( (RegV 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0 'DWord' 1),
                 (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0 'DWord' 1),
                 (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0) ) },

    @{ Name = 'Enable Windows Game Mode'; Category = 'Gaming & input'; Preset = @('Recommended','Gaming')
       Desc = 'Prioritizes the game you are playing and pauses Windows Update driver installs/restart notifications while gaming.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1), (RegV 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1) ) },

    @{ Name = 'Optimizations for windowed games'; Category = 'Gaming & input'; Preset = @('Gaming')
       Desc = 'Windows 11 flip-model upgrade for DX10/11 windowed and borderless games: lower latency and enables VRR/Auto HDR.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' 'DirectXUserGlobalSettings' 'SwapEffectUpgradeEnable=1;' 'String') ) },

    @{ Name = 'Disable mouse acceleration'; Category = 'Gaming & input'; Preset = @('Gaming')
       Desc = 'Turns off "Enhance pointer precision" for flat 1:1 aim.'
       Reg  = @( (RegV 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' 'String' '1'),
                 (RegV 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String' '6'),
                 (RegV 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String' '10') ) },

    @{ Name = 'Disable Sticky / Filter / Toggle Keys shortcuts'; Category = 'Gaming & input'; Preset = @('Recommended','Gaming')
       Desc = 'Stops the Shift x5, hold-Shift and Num Lock popups from interrupting games. The accessibility features stay available in Settings.'
       Reg  = @( (RegV 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' 'String' '510'),
                 (RegV 'HKCU:\Control Panel\Accessibility\Keyboard Response' 'Flags' '122' 'String' '126'),
                 (RegV 'HKCU:\Control Panel\Accessibility\ToggleKeys' 'Flags' '58' 'String' '62') ) },

    @{ Name = 'Faster keyboard repeat'; Category = 'Gaming & input'; Preset = @('Gaming')
       Desc = 'Shortest repeat delay and fastest repeat rate. Takes effect after sign-out.'
       Reg  = @( (RegV 'HKCU:\Control Panel\Keyboard' 'KeyboardDelay' '0' 'String' '1'),
                 (RegV 'HKCU:\Control Panel\Keyboard' 'KeyboardSpeed' '31' 'String' '31') ) },

    @{ Name = 'Stop controller Guide button opening Game Bar'; Category = 'Gaming & input'; Preset = @('Gaming')
       Desc = 'Pressing the Xbox button on a controller no longer opens the Game Bar overlay.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\GameBar' 'UseNexusForGameBarEnabled' 0) ) },

    @{ Name = 'Limit Windows Update background bandwidth'; Category = 'Gaming & input'; Preset = @('Gaming')
       Desc = 'Caps background update downloads at 30% of bandwidth to reduce ping spikes while gaming or streaming.'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DOPercentageMaxBackgroundBandwidth' 30) ) },

    @{ Name = 'Disable Delivery Optimization peer sharing'; Category = 'Gaming & input'; Preset = @('Recommended','Gaming','Privacy')
       Desc = 'Stops your PC uploading Windows updates to other PCs. Windows Update still works.'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0) ) },

    # ---------------- Performance ----------------
    @{ Name = 'Ultimate Performance power plan'; Category = 'Performance'; Preset = @()
       Desc = 'Activates the hidden Ultimate Performance plan (desktops). More power and heat; not recommended for laptops on battery.'
       Apply = {
           $activeText = powercfg /getactivescheme 2>&1
           if (-not $script:Backup.ContainsKey('powerplan') -and "$activeText" -match '([0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})') { $script:Backup['powerplan'] = @{ Guid = $Matches[1] } }
           $planId = $null
           foreach ($line in (powercfg /list 2>&1)) {
               if ("$line" -match '([0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}).*Ultimate') { $planId = $Matches[1]; break }
           }
           if (-not $planId) {
               $created = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1
               if ("$created" -match '([0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})') { $planId = $Matches[1] }
           }
           if (-not $planId) { throw 'Windows could not create or locate the Ultimate Performance plan.' }
           powercfg -setactive $planId | Out-Null
       }
       Undo = {
           $g = if ($script:Backup.ContainsKey('powerplan')) { $script:Backup['powerplan'].Guid } else { '381b4222-f694-41f0-9685-ff5bb260df2e' }
           powercfg -setactive $g | Out-Null; $script:Backup.Remove('powerplan')
       }
       Test = { "$(powercfg /getactivescheme 2>&1)" -match 'Ultimate' } },

    @{ Name = 'High Performance power plan'; Category = 'Performance'; Preset = @('Gaming')
       Desc = 'Activates Windows High Performance: CPU stays at higher clocks. May increase idle power and heat.'
       Apply = {
           $activeText = powercfg /getactivescheme 2>&1
           if (-not $script:Backup.ContainsKey('powerplan') -and "$activeText" -match '([0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})') { $script:Backup['powerplan'] = @{ Guid = $Matches[1] } }
           powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1 | Out-Null
           if ($LASTEXITCODE -ne 0) {
               $created = powercfg -duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1
               if ("$created" -match '([0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})') { powercfg -setactive $Matches[1] | Out-Null } else { throw 'High Performance plan is not available (Modern Standby PCs hide it).' }
           }
       }
       Undo = {
           $g = if ($script:Backup.ContainsKey('powerplan')) { $script:Backup['powerplan'].Guid } else { '381b4222-f694-41f0-9685-ff5bb260df2e' }
           powercfg -setactive $g | Out-Null; $script:Backup.Remove('powerplan')
       }
       Test = { "$(powercfg /getactivescheme 2>&1)" -match '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c|High performance' } },

    @{ Name = 'Remove startup app delay'; Category = 'Performance'; Preset = @('Recommended')
       Desc = 'Startup apps launch immediately after sign-in instead of waiting ~10 seconds.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 0),
                 (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'WaitForIdleState' 0) ) },

    @{ Name = 'Faster menu response'; Category = 'Performance'; Preset = @('Recommended')
       Desc = 'Shortens menu hover delay from 400 ms to 120 ms.'
       Reg  = @( (RegV 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '120' 'String' '400') ) },

    @{ Name = 'Faster shutdown'; Category = 'Performance'; Preset = @('Recommended')
       Desc = 'Waits 2 s instead of 5 s for hung apps/services at shutdown. Apps with unsaved work still prompt you.'
       Reg  = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control' 'WaitToKillServiceTimeout' '2000' 'String' '5000'),
                 (RegV 'HKCU:\Control Panel\Desktop' 'HungAppTimeout' '2000' 'String' '5000'),
                 (RegV 'HKCU:\Control Panel\Desktop' 'WaitToKillAppTimeout' '5000' 'String' '20000') ); Reboot = $true },

    @{ Name = 'Disable transparency effects'; Category = 'Performance'; Preset = @()
       Desc = 'Turns off acrylic blur in Start/taskbar. Slightly lighter on the GPU, mainly useful on integrated graphics.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0 'DWord' 1) ) },

    @{ Name = 'Disable NTFS last-access timestamps'; Category = 'Performance'; Preset = @('Recommended')
       Desc = 'Stops a metadata write every time a file is read. Reduces disk I/O, especially on HDDs and large folders.'
       Apply = { fsutil behavior set disablelastaccess 1 | Out-Null }
       Undo  = { fsutil behavior set disablelastaccess 2 | Out-Null }
       Test  = { $o = "$(fsutil behavior query disablelastaccess 2>&1)"; $o -match '=\s*(1|3)\b' } },

    @{ Name = 'Make sure SSD TRIM is enabled'; Category = 'Performance'; Preset = @('Recommended')
       Desc = 'Ensures Windows sends TRIM to SSDs, which keeps write speed high over time. Normally already on.'
       Apply = { fsutil behavior set DisableDeleteNotify 0 | Out-Null }
       Undo  = { }
       Test  = { $o = "$(fsutil behavior query DisableDeleteNotify 2>&1)"; ($o -match 'NTFS DisableDeleteNotify\s*=\s*0') -or ($o -match '^\s*DisableDeleteNotify\s*=\s*0') } },

    @{ Name = 'Speed up large folders (no folder-type sniffing)'; Category = 'Performance'; Preset = @('Recommended')
       Desc = 'Explorer stops scanning folder contents to guess "Pictures/Music" layouts - big folders like Downloads open much faster.'
       Reg  = @( (RegV 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell' 'FolderType' 'NotSpecified' 'String') ); Explorer = $true },

    @{ Name = 'Lower Defender scheduled-scan CPU usage'; Category = 'Performance'; Preset = @('Recommended','Gaming')
       Desc = 'Limits scheduled Defender scans to 25% CPU and low priority. Real-time protection is unchanged.'
       Apply = {
           if (-not $script:Backup.ContainsKey('mp|cpu')) { $script:Backup['mp|cpu'] = @{ Value = (Get-MpPreference).ScanAvgCPULoadFactor } }
           Set-MpPreference -ScanAvgCPULoadFactor 25 -ErrorAction Stop
           try { Set-MpPreference -EnableLowCpuPriority $true -ErrorAction Stop } catch { }
       }
       Undo = {
           $v = if ($script:Backup.ContainsKey('mp|cpu')) { [int]$script:Backup['mp|cpu'].Value } else { 50 }
           Set-MpPreference -ScanAvgCPULoadFactor $v -ErrorAction SilentlyContinue
           try { Set-MpPreference -EnableLowCpuPriority $false -ErrorAction Stop } catch { }
           $script:Backup.Remove('mp|cpu')
       }
       Test = { (Get-MpPreference -ErrorAction Stop).ScanAvgCPULoadFactor -le 25 } },

    @{ Name = 'Enable Storage Sense'; Category = 'Performance'; Preset = @('Recommended')
       Desc = 'Windows automatically clears temp files and old Recycle Bin items when disk space runs low.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '01' 1) ) },

    @{ Name = 'Disable hibernation'; Category = 'Performance'; Preset = @()
       Desc = 'Deletes hiberfil.sys (frees disk space roughly 40-100% of your RAM). Also disables Fast Startup. Not recommended on laptops.'
       Apply = { powercfg -h off | Out-Null }
       Undo  = { powercfg -h on | Out-Null }
       Test  = { (Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled') -eq 0 } },

    @{ Name = 'Do not reopen apps automatically after sign-in'; Category = 'Performance'; Preset = @('Recommended')
       Desc = 'Stops supported apps reopening after a restart. Apps in Startup are unaffected.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon' 'RestartApps' 0) ) },

    # ---------------- Explorer & taskbar ----------------
    @{ Name = 'Show file extensions and hidden files'; Category = 'Explorer & taskbar'; Preset = @('Recommended','Developer')
       Desc = 'Explorer shows .exe/.txt extensions (helps spot fake "photo.jpg.exe" malware) and hidden files.'
       Reg  = @( (RegV $ADV 'HideFileExt' 0 'DWord' 1), (RegV $ADV 'Hidden' 1 'DWord' 2) ); Explorer = $true },

    @{ Name = 'Classic right-click menu (Windows 11)'; Category = 'Explorer & taskbar'; Preset = @()
       Desc = 'Brings back the full context menu without "Show more options".'
       Apply = { reg add 'HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' /f /ve 2>&1 | Out-Null }
       Undo  = { reg delete 'HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}' /f 2>&1 | Out-Null }
       Test  = { Test-Path 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' }
       Explorer = $true },

    @{ Name = 'Open File Explorer to "This PC"'; Category = 'Explorer & taskbar'; Preset = @()
       Desc = 'Explorer opens to your drives instead of Home/Quick access.'
       Reg  = @( (RegV $ADV 'LaunchTo' 1) ) },

    @{ Name = 'Hide recent & frequent files in Explorer Home'; Category = 'Explorer & taskbar'; Preset = @('Privacy')
       Desc = 'Quick access/Home stops listing recently used files and frequent folders.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer' 'ShowRecent' 0 'DWord' 1),
                 (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer' 'ShowFrequent' 0 'DWord' 1) ); Explorer = $true },

    @{ Name = 'Show full path in Explorer title bar'; Category = 'Explorer & taskbar'; Preset = @('Developer')
       Desc = 'Displays the complete folder path in the window title.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState' 'FullPath' 1 'DWord' 0) ); Explorer = $true },

    @{ Name = 'Hide Gallery from Explorer navigation'; Category = 'Explorer & taskbar'; Preset = @()
       Desc = 'Removes the Windows 11 Gallery entry from the Explorer sidebar.'
       Reg  = @( (RegV 'HKCU:\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}' 'System.IsPinnedToNameSpaceTree' 0) ); Explorer = $true },

    @{ Name = 'Add "End task" to taskbar right-click'; Category = 'Explorer & taskbar'; Preset = @('Recommended','Gaming','Developer')
       Desc = 'Right-click any taskbar app to force-close a frozen game or program (Windows 11 23H2+).'
       Reg  = @( (RegV "$ADV\TaskbarDeveloperSettings" 'TaskbarEndTask' 1) ); Explorer = $true },

    @{ Name = 'Show seconds in taskbar clock'; Category = 'Explorer & taskbar'; Preset = @()
       Desc = 'Adds seconds to the system clock. Uses slightly more power on laptops.'
       Reg  = @( (RegV $ADV 'ShowSecondsInSystemClock' 1 'DWord' 0) ); Explorer = $true },

    @{ Name = 'Align taskbar to the left (Windows 11)'; Category = 'Explorer & taskbar'; Preset = @()
       Desc = 'Classic left-aligned Start button and icons.'
       Reg  = @( (RegV $ADV 'TaskbarAl' 0 'DWord' 1) ) },

    @{ Name = 'Hide Task View button'; Category = 'Explorer & taskbar'; Preset = @()
       Desc = 'Removes the Task View button from the taskbar. Win+Tab still works.'
       Reg  = @( (RegV $ADV 'ShowTaskViewButton' 0 'DWord' 1) ) },

    @{ Name = 'Hide taskbar search box'; Category = 'Explorer & taskbar'; Preset = @()
       Desc = 'Removes the search box/icon. Press Win and type to search as usual.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 0) ) },

    @{ Name = 'Hide Chat / Meet Now taskbar icons'; Category = 'Explorer & taskbar'; Preset = @('Recommended')
       Desc = 'Removes the Teams Chat (Windows 11) and Meet Now (Windows 10) icons.'
       Reg  = @( (RegV $ADV 'TaskbarMn' 0 'DWord' 1), (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'HideSCAMeetNow' 1) ); Explorer = $true },

    @{ Name = 'Disable Aero Shake'; Category = 'Explorer & taskbar'; Preset = @()
       Desc = 'Shaking a window no longer minimizes every other window.'
       Reg  = @( (RegV $ADV 'DisallowShaking' 1) ) },

    @{ Name = 'Dark mode for apps and Windows'; Category = 'Explorer & taskbar'; Preset = @()
       Desc = 'Switches Windows and apps to the dark theme.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' 0 'DWord' 1),
                 (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'SystemUsesLightTheme' 0 'DWord' 1) ) },

    # ---------------- Developer ----------------
    @{ Name = 'Enable Win32 long paths'; Category = 'Developer'; Preset = @('Developer')
       Desc = 'Lifts the 260-character path limit (fixes deep node_modules / git checkout errors).'
       Reg  = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' 1 'DWord' 0) ) },

    @{ Name = 'Enable Developer Mode'; Category = 'Developer'; Preset = @('Developer')
       Desc = 'Allows symlinks without admin, sideloading, and dev features used by many toolchains.'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' 'AllowDevelopmentWithoutDevLicense' 1 'DWord' 0) ) },

    @{ Name = 'Allow local PowerShell scripts (RemoteSigned)'; Category = 'Developer'; Preset = @('Developer')
       Desc = 'Sets the current user''s execution policy to RemoteSigned: local scripts run, downloaded ones must be signed.'
       Apply = {
           if (-not $script:Backup.ContainsKey('execpolicy')) { $script:Backup['execpolicy'] = @{ Value = [string](Get-ExecutionPolicy -Scope CurrentUser) } }
           Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
       }
       Undo = {
           $v = if ($script:Backup.ContainsKey('execpolicy')) { $script:Backup['execpolicy'].Value } else { 'Undefined' }
           Set-ExecutionPolicy $v -Scope CurrentUser -Force -ErrorAction SilentlyContinue; $script:Backup.Remove('execpolicy')
       }
       Test = { [string](Get-ExecutionPolicy -Scope CurrentUser) -eq 'RemoteSigned' } },

    @{ Name = 'Enable sudo for Windows (inline)'; Category = 'Developer'; Preset = @('Developer')
       Desc = 'Turns on the built-in sudo command (Windows 11 24H2+).'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo' 'Enabled' 3 'DWord' 0) ) },

    @{ Name = 'Verbose boot / shutdown status messages'; Category = 'Developer'; Preset = @('Developer')
       Desc = 'Shows what Windows is doing during slow sign-ins and shutdowns - great for diagnosing hangs.'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'VerboseStatus' 1) ) },

    # ---------------- Security ----------------
    @{ Name = 'Disable AutoRun / AutoPlay on all drives'; Category = 'Security'; Preset = @('Recommended')
       Desc = 'USB drives and discs can no longer launch programs automatically - a classic malware vector.'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoDriveTypeAutoRun' 255),
                 (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers' 'DisableAutoplay' 1 'DWord' 0) ) },

    @{ Name = 'Defender: block potentially unwanted apps (PUA)'; Category = 'Security'; Preset = @('Recommended')
       Desc = 'Defender blocks adware, bundleware installers and crypto miners.'
       Apply = { Set-MpPreference -PUAProtection Enabled -ErrorAction Stop }
       Undo  = { Set-MpPreference -PUAProtection Disabled -ErrorAction SilentlyContinue }
       Test  = { (Get-MpPreference -ErrorAction Stop).PUAProtection -eq 1 } },

    @{ Name = 'Disable LLMNR multicast name resolution'; Category = 'Security'; Preset = @('Recommended')
       Desc = 'Prevents LLMNR spoofing attacks on public Wi-Fi. DNS is unaffected.'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'EnableMulticast' 0) ) },

    @{ Name = 'Disable SMBv1 protocol'; Category = 'Security'; Preset = @('Recommended')
       Desc = 'Removes the obsolete protocol abused by WannaCry. Only very old NAS devices need it.'
       Apply = { Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction Stop | Out-Null }
       Undo  = { Enable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -All -ErrorAction SilentlyContinue | Out-Null }
       Test  = { $f = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop; [string]$f.State -ne 'Enabled' }
       Reboot = $true },

    @{ Name = 'Disable Remote Assistance'; Category = 'Security'; Preset = @('Recommended')
       Desc = 'Blocks unsolicited Remote Assistance connections (common in tech-support scams). Quick Assist still works.'
       Reg  = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowToGetHelp' 0 'DWord' 1) ) }
)

# ======================================================================
#  ADVANCED CONTROLS  (Risk: Low / Medium / High - nothing preselected)
# ======================================================================
$TelemetryTasks = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
    '\Microsoft\Windows\Application Experience\StartupAppTask',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\Windows Error Reporting\QueueReporting',
    '\Microsoft\Windows\Feedback\Siuf\DmClient',
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
    '\Microsoft\Windows\Autochk\Proxy',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
    '\Microsoft\Windows\Maps\MapsUpdateTask',
    '\Microsoft\Windows\Maps\MapsToastTask'
)
$SUB_PROC  = '54533251-82be-4824-96c1-47b60b740d00'
$SUB_WIFI  = '19cae613-332a-4b8d-9a62-2b8f08b4e2f9'

$Extreme = @(
    # ---------------- Services ----------------
    @{ Name = 'Disable SysMain (Superfetch)'; Risk = 'Medium'; Category = 'Services'
       Desc = 'Troubleshooting option for constant 100% disk usage on HDDs. On SSD systems it usually helps, so leave it on unless you have that problem.'
       Svc = @('SysMain'); SvcDefault = 'auto' },

    @{ Name = 'Disable Windows Search indexer'; Risk = 'Medium'; Category = 'Services'
       Desc = 'Stops background file indexing. Start/Explorer search for files becomes much slower. Pair with "Everything Search" from Applications.'
       Svc = @('WSearch'); SvcDefault = 'delayed-auto' },

    @{ Name = 'Disable Xbox services'; Risk = 'Medium'; Category = 'Services'
       Desc = 'Breaks Xbox app sign-in, Game Pass, cloud saves and Xbox Wireless controllers. Only for PCs that never use Xbox features.'
       Svc = @('XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc') },

    @{ Name = 'Disable Print Spooler + Fax'; Risk = 'Medium'; Category = 'Services'
       Desc = 'Also closes the PrintNightmare attack surface. Do not use if you print or "print to PDF".'
       Svc = @('Spooler','Fax'); SvcDefault = 'auto' },

    @{ Name = 'Disable Bluetooth services'; Risk = 'Medium'; Category = 'Services'
       Desc = 'Breaks Bluetooth controllers, mice, keyboards and headsets.'
       Svc = @('bthserv','BTAGService','BthAvctpSvc') },

    @{ Name = 'Disable rarely used background services'; Risk = 'Medium'; Category = 'Services'
       Desc = 'Maps, retail demo, error reporting, Insider, geolocation, mobile hotspot, link tracking, WAP push, phone, wallet, parental controls, payments/NFC.'
       Svc = @('MapsBroker','RetailDemo','WerSvc','wisvc','lfsvc','icssvc','WMPNetworkSvc','RemoteRegistry','TrkWks','dmwappushservice','PhoneSvc','WalletService','diagnosticshub.standardcollector.service','WpcMonSvc','SEMgrSvc') },

    @{ Name = 'Disable telemetry scheduled tasks'; Risk = 'Low'; Category = 'Services'
       Desc = 'Turns off Compatibility Appraiser, CEIP, feedback, disk-diagnostic and maps telemetry tasks.'
       Tasks = $TelemetryTasks },

    @{ Name = 'Block background Store apps'; Risk = 'Low'; Category = 'Services'
       Desc = 'Prevents Store apps from running invisibly. Live tiles/notifications for some Store apps may stop.'
       Reg = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1 'DWord' 0),
                (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground' 2) ) },

    @{ Name = 'Disable Widgets / News feed (policy)'; Risk = 'Low'; Category = 'Services'
       Desc = 'Removes the Widgets board and its WebView2 background processes (~100-300 MB RAM).'
       Reg = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0),
                (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' 'EnableFeeds' 0) ); Explorer = $true },

    @{ Name = 'Disable OneDrive sync'; Risk = 'Medium'; Category = 'Services'
       Desc = 'Turns off OneDrive and closes it. Do not use if OneDrive backs up your Desktop, Documents or Pictures.'
       Reg = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1) )
       Apply = { taskkill /f /im OneDrive.exe 2>&1 | Out-Null } },

    @{ Name = 'Uninstall OneDrive completely'; Risk = 'High'; Category = 'Services'
       Desc = 'Removes the OneDrive app. Files already on this PC stay, but cloud-only files become inaccessible. Undo reinstalls it with winget.'
       Apply = {
           taskkill /f /im OneDrive.exe 2>&1 | Out-Null
           $setup = @("$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
           if ($setup) { [void](Invoke-Hidden $setup '/uninstall') }
           elseif (Get-Command winget -ErrorAction SilentlyContinue) { [void](Invoke-Hidden 'winget.exe' 'uninstall --id Microsoft.OneDrive -e --silent --accept-source-agreements') }
           else { throw 'OneDrive setup not found.' }
       }
       Undo = { if (Get-Command winget -ErrorAction SilentlyContinue) { [void](Invoke-Hidden 'winget.exe' 'install --id Microsoft.OneDrive -e --silent --accept-package-agreements --accept-source-agreements') } }
       Test = { -not (Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe") -and -not (Test-Path "${env:ProgramFiles}\Microsoft OneDrive\OneDrive.exe") } },

    # ---------------- CPU & power ----------------
    @{ Name = 'Max-performance visual effects'; Risk = 'Low'; Category = 'CPU & power'
       Desc = 'Turns off window/taskbar animations and fades for a snappier desktop. Keeps font smoothing.'
       Reg = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2 'DWord' 0),
                (RegV 'HKCU:\Control Panel\Desktop' 'UserPreferencesMask' ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) 'Binary' ([byte[]](0x9E,0x3E,0x07,0x80,0x12,0x00,0x00,0x00))),
                (RegV 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String' '1'),
                (RegV 'HKCU:\Control Panel\Desktop' 'FontSmoothing' '2' 'String' '2'),
                (RegV $ADV 'TaskbarAnimations' 0 'DWord' 1),
                (RegV $ADV 'ListviewAlphaSelect' 1 'DWord' 1),
                (RegV 'HKCU:\Software\Microsoft\Windows\DWM' 'EnableAeroPeek' 0 'DWord' 1) ); Explorer = $true },

    @{ Name = 'Disable CPU power throttling (EcoQoS)'; Risk = 'Medium'; Category = 'CPU & power'
       Desc = 'Stops Windows forcing background apps onto efficiency cores / low clocks. Helps streaming/recording while gaming; more heat on laptops.'
       Reg = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1) ); Reboot = $true },

    @{ Name = 'Gaming CPU scheduling priority (MMCSS)'; Risk = 'Low'; Category = 'CPU & power'
       Desc = 'Gives the multimedia "Games" task the highest GPU/CPU scheduling priority and favors foreground apps with short, variable quanta.'
       Reg = @( (RegV 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 10 'DWord' 20),
                (RegV 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'GPU Priority' 8 'DWord' 8),
                (RegV 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'Priority' 6 'DWord' 2),
                (RegV 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'Scheduling Category' 'High' 'String' 'Medium'),
                (RegV 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'SFIO Priority' 'High' 'String' 'Normal'),
                (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 38 'DWord' 2) ) },

    @{ Name = 'Aggressive CPU boost mode (AC power)'; Risk = 'Medium'; Category = 'CPU & power'
       Desc = 'Lets the CPU reach turbo clocks faster and more often while plugged in. More heat and fan noise.'
       Pwr = @( (PwrV $SUB_PROC 'be337238-0d82-4146-a960-4f3749d470c7' 2 1) ) },

    @{ Name = 'Disable CPU core parking (AC power)'; Risk = 'Medium'; Category = 'CPU & power'
       Desc = 'Keeps all cores unparked while plugged in, reducing wake-up latency spikes. Higher idle power.'
       Pwr = @( (PwrV $SUB_PROC '0cc5b647-c1df-4637-891a-dec35c318583' 100 10) ) },

    @{ Name = 'Minimum processor state 100% (AC power)'; Risk = 'Medium'; Category = 'CPU & power'
       Desc = 'CPU never down-clocks while plugged in. Removes clock ramp-up lag; noticeably higher idle temperature.'
       Pwr = @( (PwrV $SUB_PROC '893dee8e-2bef-41e0-89c6-b55d0929964c' 100 5) ) },

    @{ Name = 'Disable USB selective suspend (AC power)'; Risk = 'Low'; Category = 'CPU & power'
       Desc = 'Fixes USB mice, headsets and controllers that randomly disconnect or lag after idling.'
       Pwr = @( (PwrV '2a737441-1930-4402-8d77-b2bebba308a3' '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' 0 1) ) },

    @{ Name = 'Disable PCIe Link State Power Management (AC)'; Risk = 'Medium'; Category = 'CPU & power'
       Desc = 'Keeps PCIe links (GPU/NVMe) at full power. Can fix micro-stutter on some systems; higher idle power.'
       Pwr = @( (PwrV 'SUB_PCIEXPRESS' 'ASPM' 0 1) ) },

    @{ Name = 'Never spin down hard disks (AC)'; Risk = 'Low'; Category = 'CPU & power'
       Desc = 'Stops HDDs sleeping after 20 minutes, removing the multi-second hitch when a game loads from a sleeping drive.'
       Pwr = @( (PwrV 'SUB_DISK' 'DISKIDLE' 0 1200) ) },

    @{ Name = 'Wi-Fi adapter max performance (AC)'; Risk = 'Low'; Category = 'CPU & power'
       Desc = 'Disables Wi-Fi power saving while plugged in - steadier ping on wireless.'
       Pwr = @( (PwrV $SUB_WIFI '12bbebe6-58d6-4636-95bb-3217ef867c1a' 0 0) ) },

    @{ Name = 'Global timer resolution requests (Windows 11)'; Risk = 'Medium'; Category = 'CPU & power'
       Desc = 'Restores pre-2004 behavior where a game''s high-resolution timer request applies system-wide. Can improve frame pacing; more power use.'
       Reg = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'GlobalTimerResolutionRequests' 1) ); Reboot = $true },

    @{ Name = 'Disable memory compression'; Risk = 'Medium'; Category = 'CPU & power'
       Desc = 'Saves CPU spent compressing RAM. Only consider with 32 GB+ RAM; on 8-16 GB it makes things worse.'
       Apply = { Disable-MMAgent -MemoryCompression -ErrorAction Stop }
       Undo  = { Enable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue }
       Test  = { -not (Get-MMAgent -ErrorAction Stop).MemoryCompression }
       Reboot = $true },

    @{ Name = 'Disable Windows Fast Startup'; Risk = 'Low'; Category = 'CPU & power'
       Desc = 'Real full shutdowns. Fixes many driver, Wake-on-LAN and dual-boot issues; cold boot may take a few seconds longer.'
       Reg = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0 'DWord' 1) ) },

    # ---------------- Graphics ----------------
    @{ Name = 'Hardware-accelerated GPU scheduling (HAGS)'; Risk = 'Medium'; Category = 'Graphics'
       Desc = 'Required for DLSS Frame Generation. Supported on GTX 10/RX 5000 and newer with current drivers. Reboot required.'
       Reg = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 'DWord' 1) ); Reboot = $true },

    @{ Name = 'Disable fullscreen optimizations (global)'; Risk = 'Low'; Category = 'Graphics'
       Desc = 'Forces legacy exclusive fullscreen for older DX9/DX11 games. Results vary - per-game settings in Game boost are preferred.'
       Reg = @( (RegV 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' 2 'DWord' 0),
                (RegV 'HKCU:\System\GameConfigStore' 'GameDVR_HonorUserFSEBehaviorMode' 1 'DWord' 0),
                (RegV 'HKCU:\System\GameConfigStore' 'GameDVR_DXGIHonorFSEWindowsCompatible' 1 'DWord' 0) ) },

    @{ Name = 'MPO display workaround'; Risk = 'Medium'; Category = 'Graphics'
       Desc = 'Disables Multiplane Overlay. Only use if you have flicker, black screens or stutter with multiple monitors.'
       Reg = @( (RegV 'HKLM:\SOFTWARE\Microsoft\Windows\DWM' 'OverlayTestMode' 5) ); Reboot = $true },

    @{ Name = 'Increase GPU driver timeout (TDR 8s)'; Risk = 'Low'; Category = 'Graphics'
       Desc = 'Gives the GPU 8 s instead of 2 s before Windows resets the driver. Fixes "display driver stopped responding" during heavy loads/shader compiles.'
       Reg = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'TdrDelay' 8) ); Reboot = $true },

    # ---------------- Network ----------------
    @{ Name = 'Disable network throttling + Nagle (TCP no-delay)'; Risk = 'Medium'; Category = 'Network'
       Desc = 'Removes multimedia network throttling and Nagle''s algorithm on all interfaces. Can lower latency in some older TCP-based games.'
       Apply = {
           Backup-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex'
           reg add 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' /v NetworkThrottlingIndex /t REG_DWORD /d 0xffffffff /f 2>&1 | Out-Null
           Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' | ForEach-Object {
               Set-Reg $_.PSPath 'TcpAckFrequency' 1; Set-Reg $_.PSPath 'TCPNoDelay' 1
           }
       }
       Undo = {
           if (-not (Restore-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex')) {
               Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' 10
           }
           Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' | ForEach-Object { Remove-Prop $_.PSPath @('TcpAckFrequency','TCPNoDelay') }
       }
       Test = { [uint32]([int64](Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex') -band 0xFFFFFFFF) -eq 4294967295 } },

    @{ Name = 'Disable network adapter power saving'; Risk = 'Medium'; Category = 'Network'
       Desc = 'Stops Windows turning off Ethernet/Wi-Fi adapters to save power. Fixes random disconnects after idle. Disables Wake-on-LAN.'
       Apply = { Get-NetAdapter -Physical -ErrorAction Stop | ForEach-Object { Disable-NetAdapterPowerManagement -Name $_.Name -NoRestart -ErrorAction SilentlyContinue } }
       Undo  = { Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object { Enable-NetAdapterPowerManagement -Name $_.Name -NoRestart -ErrorAction SilentlyContinue } } },

    @{ Name = 'Disable Teredo tunneling'; Risk = 'Medium'; Category = 'Network'
       Desc = 'Removes an IPv6 tunnel that can cause odd routing. Breaks Xbox party chat/"Teredo unable to qualify" - leave on if you use Xbox networking.'
       Apply = { netsh interface teredo set state disabled | Out-Null }
       Undo  = { netsh interface teredo set state type=default | Out-Null }
       Test  = { "$(netsh interface teredo show state 2>&1)" -match 'disabled' } },

    @{ Name = 'Block Wi-Fi Sense hotspot auto-connect'; Risk = 'Low'; Category = 'Network'
       Desc = 'Prevents auto-joining suggested open hotspots.'
       Reg = @( (RegV 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots' 'value' 0 'DWord' 1) ) },

    # ---------------- Storage ----------------
    @{ Name = 'Disable reserved storage (~7 GB)'; Risk = 'Medium'; Category = 'Storage'
       Desc = 'Frees the space Windows reserves for updates. Feature updates may fail on nearly full drives.'
       Apply = { $c = Invoke-Hidden 'DISM.exe' '/Online /Set-ReservedStorageState /State:Disabled /Quiet'; if ($c -ne 0) { throw "DISM exit code $c (pending updates can block this)" } }
       Undo  = { [void](Invoke-Hidden 'DISM.exe' '/Online /Set-ReservedStorageState /State:Enabled /Quiet') }
       Test  = { [string](Get-WindowsReservedStorageState -ErrorAction Stop).ReservedStorageState -eq 'Disabled' } },

    @{ Name = 'Disable 8.3 short file names'; Risk = 'Low'; Category = 'Storage'
       Desc = 'Stops NTFS creating legacy DOS names for every new file - faster file creation in big folders. Existing names are kept.'
       Apply = { fsutil 8dot3name set 1 | Out-Null }
       Undo  = { fsutil 8dot3name set 2 | Out-Null }
       Test  = { "$(fsutil 8dot3name query 2>&1)" -match ':\s*1\b|\b1\s*\(' } },

    # ---------------- Updates ----------------
    @{ Name = 'Windows Update: notify only (no auto reboot)'; Risk = 'Medium'; Category = 'Updates'
       Desc = 'Updates are downloaded only when you choose, and Windows never reboots while you are signed in. Install security updates regularly.'
       Reg = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'AUOptions' 2),
                (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate' 0),
                (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoRebootWithLoggedOnUsers' 1) ) },

    @{ Name = 'Exclude drivers from Windows Update'; Risk = 'Medium'; Category = 'Updates'
       Desc = 'Stops Windows Update replacing your GPU/chipset drivers with older generic ones. You must update drivers yourself.'
       Reg = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'ExcludeWUDriversInQualityUpdate' 1) ) },

    @{ Name = 'Disable Microsoft Store auto app updates'; Risk = 'Medium'; Category = 'Updates'
       Desc = 'Stops Store apps updating in the background. You must update them manually.'
       Reg = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore' 'AutoDownload' 2) ) },

    @{ Name = 'Remove the Recall optional feature'; Risk = 'Medium'; Category = 'Updates'
       Desc = 'Uninstalls the Recall component on Windows 11 24H2+. Does nothing on builds without it.'
       Apply = { Disable-WindowsOptionalFeature -Online -FeatureName Recall -NoRestart -ErrorAction Stop | Out-Null }
       Undo  = { Enable-WindowsOptionalFeature -Online -FeatureName Recall -NoRestart -ErrorAction SilentlyContinue | Out-Null }
       Test  = { $f = Get-WindowsOptionalFeature -Online -FeatureName Recall -ErrorAction Stop; [string]$f.State -ne 'Enabled' }
       Reboot = $true },

    # ---------------- Security trade-offs ----------------
    @{ Name = 'Disable Core Isolation / VBS (Memory Integrity)'; Risk = 'High'; Category = 'Security trade-offs'
       Desc = 'Can recover 5-10% FPS in CPU-bound games, but removes kernel exploit protection. Some anti-cheats (Valorant, FACEIT) require it ON. Reboot required.'
       Reg = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0),
                (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0) ); Reboot = $true },

    @{ Name = 'Turn off Windows hypervisor'; Risk = 'High'; Category = 'Security trade-offs'
       Desc = 'Fully stops Hyper-V from loading at boot (lowers DPC latency). Breaks WSL2, Docker Desktop, Windows Sandbox, Android subsystem and VBS. Reboot required.'
       Apply = { bcdedit /set hypervisorlaunchtype off | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'bcdedit failed (BitLocker/Secure Boot policy may block it).' } }
       Undo  = { bcdedit /set hypervisorlaunchtype auto | Out-Null }
       Test  = { "$(bcdedit /enum '{current}' 2>&1)" -match 'hypervisorlaunchtype\s+Off' }
       Reboot = $true }
)

# High-risk security bypasses (Defender removal, UAC off, Spectre/Meltdown mitigation disabling) are intentionally not included.

# ======================================================================
#  APPLICATION CATALOG (winget IDs)
# ======================================================================
$AppCatalog = [ordered]@{
    'Browsers' = [ordered]@{
        'Brave'                = 'Brave.Brave'
        'Firefox'              = 'Mozilla.Firefox'
        'Google Chrome'        = 'Google.Chrome'
        'LibreWolf'            = 'LibreWolf.LibreWolf'
        'Vivaldi'              = 'Vivaldi.Vivaldi'
    }
    'Gaming' = [ordered]@{
        'Steam'                = 'Valve.Steam'
        'Epic Games'           = 'EpicGames.EpicGamesLauncher'
        'GOG Galaxy'           = 'GOG.Galaxy'
        'EA app'               = 'ElectronicArts.EADesktop'
        'Ubisoft Connect'      = 'Ubisoft.Connect'
        'Battle.net'           = 'Blizzard.BattleNet'
        'Playnite'             = 'Playnite.Playnite'
        'Discord'              = 'Discord.Discord'
    }
    'Game runtimes (fixes missing DLL errors)' = [ordered]@{
        'VC++ 2015-2022 x64'   = 'Microsoft.VCRedist.2015+.x64'
        'VC++ 2015-2022 x86'   = 'Microsoft.VCRedist.2015+.x86'
        'DirectX legacy runtime' = 'Microsoft.DirectX'
        '.NET Desktop Runtime 8' = 'Microsoft.DotNet.DesktopRuntime.8'
        'Java (Temurin 21 JRE)' = 'EclipseAdoptium.Temurin.21.JRE'
    }
    'Hardware & tuning' = [ordered]@{
        'HWiNFO'               = 'REALiX.HWiNFO'
        'MSI Afterburner'      = 'Guru3D.Afterburner'
        'CPU-Z'                = 'CPUID.CPU-Z'
        'GPU-Z'                = 'TechPowerUp.GPU-Z'
        'CrystalDiskInfo'      = 'CrystalDewWorld.CrystalDiskInfo'
        'CrystalDiskMark'      = 'CrystalDewWorld.CrystalDiskMark'
        'NVCleanstall'         = 'TechPowerUp.NVCleanstall'
        'Display Driver Uninstaller' = 'Wagnardsoft.DisplayDriverUninstaller'
        'LatencyMon'           = 'Resplendence.LatencyMon'
        'OCCT'                 = 'OCBase.OCCT.Personal'
    }
    'Media & streaming' = [ordered]@{
        'VLC Media Player'     = 'VideoLAN.VLC'
        'Spotify'              = 'Spotify.Spotify'
        'OBS Studio'           = 'OBSProject.OBSStudio'
        'ShareX'               = 'ShareX.ShareX'
        'Audacity'             = 'Audacity.Audacity'
        'HandBrake'            = 'HandBrake.HandBrake'
    }
    'Utilities' = [ordered]@{
        '7-Zip'                = '7zip.7zip'
        'Everything Search'    = 'voidtools.Everything'
        'PowerToys'            = 'Microsoft.PowerToys'
        'WizTree'              = 'AntibodySoftware.WizTree'
        'Revo Uninstaller'     = 'RevoUninstaller.RevoUninstaller'
        'Bitwarden'            = 'Bitwarden.Bitwarden'
        'Notepad++'            = 'Notepad++.Notepad++'
        'Flow Launcher'        = 'Flow-Launcher.Flow-Launcher'
        'Rufus'                = 'Rufus.Rufus'
        'qBittorrent'          = 'qBittorrent.qBittorrent'
        'Sumatra PDF'          = 'SumatraPDF.SumatraPDF'
        'Malwarebytes'         = 'Malwarebytes.Malwarebytes'
        'Autoruns'             = 'Microsoft.Sysinternals.Autoruns'
        'Process Explorer'     = 'Microsoft.Sysinternals.ProcessExplorer'
    }
    'Development' = [ordered]@{
        'VS Code'              = 'Microsoft.VisualStudioCode'
        'Windows Terminal'     = 'Microsoft.WindowsTerminal'
        'PowerShell 7'         = 'Microsoft.PowerShell'
        'Git'                  = 'Git.Git'
        'GitHub CLI'           = 'GitHub.cli'
        'GitHub Desktop'       = 'GitHub.GitHubDesktop'
        'Python 3.13'          = 'Python.Python.3.13'
        'Node.js LTS'          = 'OpenJS.NodeJS.LTS'
        '.NET SDK 8'           = 'Microsoft.DotNet.SDK.8'
        'Rustup'               = 'Rustlang.Rustup'
        'Go'                   = 'GoLang.Go'
        'Docker Desktop'       = 'Docker.DockerDesktop'
        'Postman'              = 'Postman.Postman'
        'JetBrains Toolbox'    = 'JetBrains.Toolbox'
        'Visual Studio 2022 Community' = 'Microsoft.VisualStudio.2022.Community'
        'WinSCP'               = 'WinSCP.WinSCP'
        'PuTTY'                = 'PuTTY.PuTTY'
    }
    'Communication' = [ordered]@{
        'Zoom'                 = 'Zoom.Zoom'
        'Telegram'             = 'Telegram.TelegramDesktop'
        'Signal'               = 'OpenWhisperSystems.Signal'
        'Slack'                = 'SlackTechnologies.Slack'
    }
}

# ======================================================================
#  PREINSTALLED STORE APPS (debloat) - wildcards allowed
# ======================================================================
$BloatCatalog = [ordered]@{
    'Microsoft News'            = @('Microsoft.BingNews')
    'Weather'                   = @('Microsoft.BingWeather')
    'Bing Search app'           = @('Microsoft.BingSearch')
    'Get Help'                  = @('Microsoft.GetHelp')
    'Tips'                      = @('Microsoft.Getstarted')
    'Solitaire Collection'      = @('Microsoft.MicrosoftSolitaireCollection')
    'Microsoft 365 (Office hub)'= @('Microsoft.MicrosoftOfficeHub')
    'OneNote for Windows 10'    = @('Microsoft.Office.OneNote')
    'Feedback Hub'              = @('Microsoft.WindowsFeedbackHub')
    'Maps'                      = @('Microsoft.WindowsMaps')
    'People'                    = @('Microsoft.People')
    'Skype'                     = @('Microsoft.SkypeApp')
    'Clipchamp'                 = @('Clipchamp.Clipchamp')
    'Microsoft To Do'           = @('Microsoft.Todos')
    'Teams (personal)'          = @('MicrosoftTeams','MSTeams')
    'Power Automate'            = @('Microsoft.PowerAutomateDesktop')
    'Cortana'                   = @('Microsoft.549981C3F5F10')
    'Movies & TV'               = @('Microsoft.ZuneVideo')
    'Mixed Reality Portal'      = @('Microsoft.MixedReality.Portal')
    '3D Viewer'                 = @('Microsoft.Microsoft3DViewer')
    'Paint 3D'                  = @('Microsoft.MSPaint')
    'Mail and Calendar (legacy)'= @('microsoft.windowscommunicationsapps')
    'Outlook (new)'             = @('Microsoft.OutlookForWindows')
    'Dev Home'                  = @('Microsoft.Windows.DevHome')
    'Phone Link'                = @('Microsoft.YourPhone')
    'Microsoft Family'          = @('MicrosoftCorporationII.MicrosoftFamily')
    'Quick Assist'              = @('MicrosoftCorporationII.QuickAssist')
    'Copilot app'               = @('Microsoft.Copilot','Microsoft.Windows.Ai.Copilot.Provider')
    'Xbox app (Game Pass)'      = @('Microsoft.GamingApp')
    'Xbox Game Bar'             = @('Microsoft.XboxGamingOverlay')
    'Candy Crush games'         = @('*CandyCrush*')
    'Spotify (Store)'           = @('SpotifyAB.SpotifyMusic')
    'Disney+'                   = @('*Disney*')
    'TikTok'                    = @('*TikTok*')
    'Facebook / Instagram'      = @('*Facebook*','*Instagram*')
    'LinkedIn'                  = @('*LinkedIn*')
    'Prime Video'               = @('*AmazonVideo*')
}

# ======================================================================
#  GUI XAML
# ======================================================================
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="EduUtil | Windows Utility" Width="1180" Height="800" MinWidth="980" MinHeight="680" WindowStartupLocation="CenterScreen"
        Background="#111318" FontFamily="Segoe UI" Foreground="#E6E8ED">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Background" Value="#3B82F6"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="14,8"/>
      <Setter Property="Margin" Value="0,0,8,8"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.82"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.65"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="bd" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Ghost" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="#262B35"/>
    </Style>
    <Style x:Key="Danger" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="#8D3A3A"/>
    </Style>
    <Style x:Key="Chip" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="#1E2A3D"/>
      <Setter Property="Foreground" Value="#9CC3FF"/>
      <Setter Property="Padding" Value="10,5"/>
      <Setter Property="FontSize" Value="12"/>
    </Style>
    <Style x:Key="Nav" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="#C9CED8"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Margin" Value="0,0,0,4"/>
      <Setter Property="Padding" Value="12,8"/>
    </Style>
    <Style x:Key="Tool" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="#262B35"/>
      <Setter Property="Width" Value="250"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#E6E6E6"/>
      <Setter Property="Margin" Value="0,4"/>
      <Setter Property="FontSize" Value="14"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#1A1E26"/>
      <Setter Property="Foreground" Value="#E6E8ED"/>
      <Setter Property="BorderBrush" Value="#303642"/>
      <Setter Property="CaretBrush" Value="#E6E8ED"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="8,5"/>
    </Style>
    <Style x:Key="H1" TargetType="TextBlock">
      <Setter Property="FontSize" Value="20"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Margin" Value="0,0,0,4"/>
    </Style>
    <Style x:Key="Sub" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#8D95A5"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="Margin" Value="0,0,0,10"/>
    </Style>
    <Style x:Key="H2" TargetType="TextBlock">
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="#58A6FF"/>
      <Setter Property="Margin" Value="0,14,0,8"/>
    </Style>
  </Window.Resources>

  <Grid Name="rootGrid" Margin="12">
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="190"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>

    <!-- Sidebar -->
    <DockPanel Grid.Column="0" Margin="0,0,14,0">
      <StackPanel DockPanel.Dock="Top">
        <TextBlock Text="EDUUTIL" FontSize="20" FontWeight="SemiBold" Margin="4,0,0,0"/>
        <TextBlock Name="txtVersion" Text="SYSTEM UTILITY" FontSize="9" Foreground="#737B8C" Margin="5,0,0,16"/>
      </StackPanel>
      <StackPanel DockPanel.Dock="Bottom" Margin="0,8,0,0">
        <Button Name="btnExportProfile" Content="Export profile" Style="{StaticResource Ghost}" Margin="0,0,0,6" ToolTip="Save the currently checked tweaks, advanced controls and apps to a JSON file"/>
        <Button Name="btnImportProfile" Content="Import profile" Style="{StaticResource Ghost}" Margin="0,0,0,6" ToolTip="Check items from a previously exported profile"/>
        <Button Name="btnRP" Content="Create restore point" Style="{StaticResource Ghost}" Margin="0,0,0,0"/>
      </StackPanel>
      <ScrollViewer VerticalScrollBarVisibility="Auto">
        <StackPanel>
          <Button Name="navTweaks"  Content="Tweaks"            Style="{StaticResource Nav}"/>
          <Button Name="navExtreme" Content="Advanced"          Style="{StaticResource Nav}"/>
          <Button Name="navGame"    Content="Game boost"        Style="{StaticResource Nav}"/>
          <Button Name="navDebloat" Content="Debloat"           Style="{StaticResource Nav}"/>
          <Button Name="navStartup" Content="Startup apps"      Style="{StaticResource Nav}"/>
          <Button Name="navInstall" Content="Applications"      Style="{StaticResource Nav}"/>
          <Button Name="navClean"   Content="Maintenance"       Style="{StaticResource Nav}"/>
          <Button Name="navNetwork" Content="Network"           Style="{StaticResource Nav}"/>
          <Button Name="navSysInfo" Content="System &amp; health" Style="{StaticResource Nav}"/>
          <Button Name="navLog"     Content="Activity log"      Style="{StaticResource Nav}"/>
        </StackPanel>
      </ScrollViewer>
    </DockPanel>

    <Grid Grid.Column="1">
      <Grid.RowDefinitions>
        <RowDefinition Height="*"/>
        <RowDefinition Height="30"/>
      </Grid.RowDefinitions>

      <Grid Grid.Row="0">
        <!-- TWEAKS -->
        <DockPanel Name="pgTweaks">
          <StackPanel DockPanel.Dock="Top">
            <TextBlock Text="Everyday optimizations" Style="{StaticResource H1}"/>
            <TextBlock Style="{StaticResource Sub}" Text="Safe, reversible Windows, privacy, gaming and quality-of-life settings. Green = currently applied. Undo restores the exact values you had before."/>
            <WrapPanel Margin="0,0,0,6">
              <TextBlock Text="Presets:" Foreground="#8D95A5" VerticalAlignment="Center" Margin="0,0,8,8"/>
              <Button Name="btnPresetRec"  Content="Recommended" Style="{StaticResource Chip}"/>
              <Button Name="btnPresetGame" Content="Gaming"      Style="{StaticResource Chip}"/>
              <Button Name="btnPresetPriv" Content="Privacy"     Style="{StaticResource Chip}"/>
              <Button Name="btnPresetDev"  Content="Developer"   Style="{StaticResource Chip}"/>
              <Button Name="btnSelAll"     Content="Select visible" Style="{StaticResource Chip}"/>
              <Button Name="btnSelUnapplied" Content="Select not-applied" Style="{StaticResource Chip}"/>
              <Button Name="btnSelNone"    Content="Clear"       Style="{StaticResource Chip}"/>
            </WrapPanel>
            <TextBox Name="txtTweakSearch" Height="32" ToolTip="Filter by name, description or category" Margin="0,0,0,8"/>
          </StackPanel>
          <WrapPanel DockPanel.Dock="Bottom" Margin="0,8,0,0">
            <Button Name="btnApply" Content="Apply selected"/>
            <Button Name="btnUndo"  Content="Undo selected" Style="{StaticResource Ghost}" ToolTip="Restores the values that existed before EduUtil changed them (or Windows defaults if no backup exists)"/>
            <Button Name="btnRefreshState" Content="Refresh status" Style="{StaticResource Ghost}"/>
            <TextBlock Name="txtTweakCount" Foreground="#8D95A5" VerticalAlignment="Center" Margin="6,0,0,8"/>
          </WrapPanel>
          <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Name="tweakList" Margin="0,0,10,0"/></ScrollViewer>
        </DockPanel>

        <!-- ADVANCED -->
        <DockPanel Name="pgExtreme" Visibility="Collapsed">
          <StackPanel DockPanel.Dock="Top">
            <TextBlock Text="Advanced controls" Style="{StaticResource H1}"/>
            <TextBlock Style="{StaticResource Sub}" Text="System-level changes that trade power, compatibility or security for performance. Read each description. Nothing is preselected and a restore point is created first."/>
            <WrapPanel Margin="0,0,0,6">
              <Button Name="btnXSelLow"  Content="Select low-risk" Style="{StaticResource Chip}"/>
              <Button Name="btnXSelNone" Content="Clear"           Style="{StaticResource Chip}"/>
            </WrapPanel>
            <TextBox Name="txtExtremeSearch" Height="32" ToolTip="Filter advanced controls" Margin="0,0,0,8"/>
          </StackPanel>
          <WrapPanel DockPanel.Dock="Bottom" Margin="0,8,0,0">
            <Button Name="btnXApply" Content="Apply selected" Style="{StaticResource Danger}"/>
            <Button Name="btnXUndo"  Content="Undo selected" Style="{StaticResource Ghost}"/>
            <Button Name="btnXRefresh" Content="Refresh status" Style="{StaticResource Ghost}"/>
          </WrapPanel>
          <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Name="extremeList" Margin="0,0,10,0"/></ScrollViewer>
        </DockPanel>

        <!-- GAME BOOST -->
        <DockPanel Name="pgGame" Visibility="Collapsed">
          <StackPanel DockPanel.Dock="Top">
            <TextBlock Text="Game boost" Style="{StaticResource H1}"/>
            <TextBlock Style="{StaticResource Sub}" Text="Per-game settings that Windows actually honors. Pick a game's .exe (not the launcher), choose options, and apply. Works with Steam, Epic, Battle.net and others."/>
            <Grid Margin="0,0,0,10">
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <TextBox Name="txtGameExe" Height="32" Grid.Column="0" IsReadOnly="True" Margin="0,0,8,0"/>
              <Button Name="btnBrowseGame" Content="Browse .exe..." Grid.Column="1" Margin="0"/>
            </Grid>
            <CheckBox Name="chkGameGpu" Content="Use high-performance GPU (fixes laptops running games on integrated graphics)" IsChecked="True"/>
            <CheckBox Name="chkGameCpu" Content="High CPU priority every launch (Image File Execution Options)" IsChecked="True"/>
            <CheckBox Name="chkGameFso" Content="Disable fullscreen optimizations for this game (older DX9/DX11 titles)"/>
            <CheckBox Name="chkGameDpi" Content="Override high-DPI scaling (fixes blurry/oversized old games)"/>
            <WrapPanel Margin="0,10,0,0">
              <Button Name="btnGameApply"  Content="Apply to this game"/>
              <Button Name="btnGameRemove" Content="Remove settings for this game" Style="{StaticResource Ghost}"/>
              <Button Name="btnGameModeSettings" Content="Game Mode settings" Style="{StaticResource Ghost}"/>
              <Button Name="btnGraphicsSettings" Content="Windows graphics settings" Style="{StaticResource Ghost}"/>
            </WrapPanel>
            <TextBlock Text="Games configured by EduUtil (click to select)" Style="{StaticResource H2}"/>
          </StackPanel>
          <ListBox Name="lstGames" Background="#0D0F13" Foreground="#C9CED8" BorderThickness="0" FontFamily="Consolas" FontSize="12"/>
        </DockPanel>

        <!-- DEBLOAT -->
        <DockPanel Name="pgDebloat" Visibility="Collapsed">
          <StackPanel DockPanel.Dock="Top">
            <TextBlock Text="Remove preinstalled apps" Style="{StaticResource H1}"/>
            <TextBlock Style="{StaticResource Sub}" Text="Only apps that are actually installed are selectable. Removed apps can be reinstalled from the Microsoft Store. Core apps (Store, Calculator, Photos, Terminal, Notepad, Paint, Snipping Tool) are never listed."/>
            <WrapPanel>
              <CheckBox Name="chkBloatProvisioned" Content="Also remove for new user accounts (provisioned package)" IsChecked="True" Margin="0,0,16,8"/>
              <Button Name="btnBloatSelAll" Content="Select all installed" Style="{StaticResource Chip}"/>
              <Button Name="btnBloatSelNone" Content="Clear" Style="{StaticResource Chip}"/>
            </WrapPanel>
          </StackPanel>
          <WrapPanel DockPanel.Dock="Bottom" Margin="0,8,0,0">
            <Button Name="btnBloatRemove" Content="Remove selected" Style="{StaticResource Danger}"/>
            <Button Name="btnBloatRefresh" Content="Rescan" Style="{StaticResource Ghost}"/>
          </WrapPanel>
          <ScrollViewer VerticalScrollBarVisibility="Auto"><WrapPanel Name="bloatList"/></ScrollViewer>
        </DockPanel>

        <!-- STARTUP -->
        <DockPanel Name="pgStartup" Visibility="Collapsed">
          <StackPanel DockPanel.Dock="Top">
            <TextBlock Text="Startup apps" Style="{StaticResource H1}"/>
            <TextBlock Style="{StaticResource Sub}" Text="Checked = runs at sign-in. Unchecking disables an entry exactly like Task Manager does (nothing is deleted, so you can re-enable it anytime). Fewer startup apps = faster boot and more free RAM."/>
          </StackPanel>
          <WrapPanel DockPanel.Dock="Bottom" Margin="0,8,0,0">
            <Button Name="btnStartupApply"   Content="Apply changes"/>
            <Button Name="btnStartupRefresh" Content="Rescan" Style="{StaticResource Ghost}"/>
            <Button Name="btnStartupFolder"  Content="Open startup folder" Style="{StaticResource Ghost}"/>
            <Button Name="btnTaskMgr"        Content="Open Task Manager" Style="{StaticResource Ghost}"/>
          </WrapPanel>
          <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Name="startupList" Margin="0,0,10,0"/></ScrollViewer>
        </DockPanel>

        <!-- APPLICATIONS -->
        <DockPanel Name="pgInstall" Visibility="Collapsed">
          <StackPanel DockPanel.Dock="Top">
            <TextBlock Text="Applications" Style="{StaticResource H1}"/>
            <TextBlock Style="{StaticResource Sub}" Text="Silent installs, uninstalls and updates through winget (official sources)."/>
            <TextBox Name="txtAppSearch" Height="32" ToolTip="Filter applications" Margin="0,0,0,8"/>
          </StackPanel>
          <WrapPanel DockPanel.Dock="Bottom" Margin="0,8,0,0">
            <Button Name="btnInstall"    Content="Install selected"/>
            <Button Name="btnUninstall"  Content="Uninstall selected" Style="{StaticResource Ghost}"/>
            <Button Name="btnUpgradeAll" Content="Update ALL installed apps" Style="{StaticResource Ghost}"/>
            <Button Name="btnAppSelNone" Content="Clear selection" Style="{StaticResource Ghost}"/>
          </WrapPanel>
          <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Name="appList"/></ScrollViewer>
        </DockPanel>

        <!-- MAINTENANCE -->
        <ScrollViewer Name="pgClean" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
          <StackPanel>
            <TextBlock Text="Maintenance" Style="{StaticResource H1}"/>
            <TextBlock Style="{StaticResource Sub}" Text="Cleanup reports how much space it freed. Files in use are skipped. Shader caches rebuild on next launch (brief first-run stutter)."/>
            <TextBlock Text="CLEANUP" Style="{StaticResource H2}"/>
            <WrapPanel>
              <Button Name="btnTemp"        Content="Clean temporary files"          Style="{StaticResource Tool}"/>
              <Button Name="btnBin"         Content="Empty Recycle Bin"              Style="{StaticResource Tool}"/>
              <Button Name="btnShader"      Content="Clear GPU shader caches"        Style="{StaticResource Tool}"/>
              <Button Name="btnDiskCleanup" Content="Deep Disk Cleanup (safe set)"   Style="{StaticResource Tool}"/>
              <Button Name="btnWUCache"     Content="Clear Windows Update cache"     Style="{StaticResource Tool}"/>
              <Button Name="btnDOCache"     Content="Clear Delivery Optimization cache" Style="{StaticResource Tool}"/>
              <Button Name="btnComponent"   Content="Clean component store (WinSxS)" Style="{StaticResource Tool}"/>
              <Button Name="btnThumb"       Content="Rebuild thumbnail &amp; icon cache" Style="{StaticResource Tool}"/>
              <Button Name="btnStoreCache"  Content="Reset Microsoft Store cache"    Style="{StaticResource Tool}"/>
              <Button Name="btnCleanAll"    Content="One-click cleanup (all safe)"   Style="{StaticResource Tool}" Background="#2F6B4F"/>
            </WrapPanel>
            <TextBlock Text="REPAIR" Style="{StaticResource H2}"/>
            <WrapPanel>
              <Button Name="btnSfc"            Content="Repair Windows (DISM + SFC)"   Style="{StaticResource Tool}"/>
              <Button Name="btnOptimizeDrive"  Content="Optimize all drives (TRIM/defrag)" Style="{StaticResource Tool}"/>
              <Button Name="btnRestartExplorer" Content="Restart Explorer"             Style="{StaticResource Tool}"/>
              <Button Name="btnResetWU"        Content="Reset Windows Update components" Style="{StaticResource Tool}"/>
              <Button Name="btnChkdsk"         Content="Schedule disk check (chkdsk)"  Style="{StaticResource Tool}"/>
            </WrapPanel>
            <TextBlock Text="DIAGNOSTICS" Style="{StaticResource H2}"/>
            <WrapPanel>
              <Button Name="btnDiskHealth"   Content="Drive health (SMART)"        Style="{StaticResource Tool}"/>
              <Button Name="btnBattery"      Content="Battery health report"       Style="{StaticResource Tool}"/>
              <Button Name="btnReliability"  Content="Reliability Monitor (crashes)" Style="{StaticResource Tool}"/>
              <Button Name="btnMemTest"      Content="Windows Memory Diagnostic"   Style="{StaticResource Tool}"/>
              <Button Name="btnRestorePoints" Content="Open System Restore"        Style="{StaticResource Tool}"/>
              <Button Name="btnWinUpdate"    Content="Open Windows Update"         Style="{StaticResource Tool}"/>
            </WrapPanel>
          </StackPanel>
        </ScrollViewer>

        <!-- NETWORK -->
        <DockPanel Name="pgNetwork" Visibility="Collapsed">
          <StackPanel DockPanel.Dock="Top">
            <TextBlock Text="Network" Style="{StaticResource H1}"/>
            <TextBlock Style="{StaticResource Sub}" Text="DNS changes apply to all connected adapters. A faster DNS speeds up page loads and game-server lookups; it does not change in-game ping."/>
            <TextBlock Text="DNS PROVIDER" Style="{StaticResource H2}" Margin="0,4,0,8"/>
            <WrapPanel>
              <Button Name="btnDnsCloudflare" Content="Cloudflare 1.1.1.1"/>
              <Button Name="btnDnsGoogle"     Content="Google 8.8.8.8"/>
              <Button Name="btnDnsQuad9"      Content="Quad9 9.9.9.9 (malware blocking)"/>
              <Button Name="btnDnsAuto"       Content="Automatic (DHCP)" Style="{StaticResource Ghost}"/>
              <Button Name="btnDnsBench"      Content="Benchmark DNS speed" Style="{StaticResource Ghost}"/>
            </WrapPanel>
            <TextBlock Text="TOOLS" Style="{StaticResource H2}" Margin="0,4,0,8"/>
            <WrapPanel>
              <Button Name="btnDns"          Content="Flush DNS cache" Style="{StaticResource Ghost}"/>
              <Button Name="btnAdapters"     Content="Show adapters &amp; DNS" Style="{StaticResource Ghost}"/>
              <Button Name="btnNetworkReset" Content="Reset network stack" Style="{StaticResource Danger}"/>
            </WrapPanel>
            <Grid Margin="0,4,0,8">
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <TextBox Name="txtPingHost" Height="32" Text="1.1.1.1, 8.8.8.8, 9.9.9.9" ToolTip="Comma-separated hosts or IPs (e.g. a game server)" Margin="0,0,8,0"/>
              <Button Name="btnPing" Grid.Column="1" Content="Latency / jitter test" Margin="0"/>
            </Grid>
          </StackPanel>
          <TextBox Name="txtNetOut" IsReadOnly="True" Background="#0D0F13" Foreground="#9CC3FF" FontFamily="Consolas" FontSize="12" BorderThickness="0" Padding="10" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"/>
        </DockPanel>

        <!-- SYSTEM INFO -->
        <DockPanel Name="pgSysInfo" Visibility="Collapsed">
          <StackPanel DockPanel.Dock="Top">
            <TextBlock Text="System &amp; health check" Style="{StaticResource H1}"/>
            <TextBlock Style="{StaticResource Sub}" Text="Hardware summary plus a health check that flags real-world issues: RAM running below rated speed (XMP/EXPO), single-channel memory, 60 Hz on a high-refresh monitor, old GPU drivers, low disk space and more."/>
          </StackPanel>
          <WrapPanel DockPanel.Dock="Bottom" Margin="0,8,0,0">
            <Button Name="btnRefreshInfo" Content="Run health check"/>
            <Button Name="btnCopyInfo"    Content="Copy report" Style="{StaticResource Ghost}"/>
            <Button Name="btnSaveInfo"    Content="Save report to Desktop" Style="{StaticResource Ghost}"/>
          </WrapPanel>
          <TextBox Name="txtSysInfo" IsReadOnly="True" Background="#0D0F13" Foreground="#9CC3FF" FontFamily="Consolas" FontSize="12.5" BorderThickness="0" Padding="10" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"/>
        </DockPanel>

        <!-- LOG -->
        <DockPanel Name="pgLog" Visibility="Collapsed">
          <StackPanel DockPanel.Dock="Top">
            <TextBlock Text="Activity log" Style="{StaticResource H1}"/>
            <TextBlock Name="txtLogPath" Style="{StaticResource Sub}"/>
          </StackPanel>
          <WrapPanel DockPanel.Dock="Bottom" Margin="0,8,0,0">
            <Button Name="btnOpenLogFolder" Content="Open data folder" Style="{StaticResource Ghost}"/>
            <Button Name="btnClearBackup"   Content="Forget saved backups" Style="{StaticResource Ghost}" ToolTip="Undo will fall back to Windows defaults afterwards"/>
          </WrapPanel>
          <TextBox Name="txtLog" IsReadOnly="True" Background="#0D0F13" Foreground="#AAB2C0" FontFamily="Consolas" FontSize="12" BorderThickness="0" Padding="10" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"/>
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
$script:window = $window
$xmlDoc = [xml]$xaml
foreach ($node in $xmlDoc.SelectNodes('//*[@Name]')) { Set-Variable -Name $node.Name -Value $window.FindName($node.Name) -Scope Script }

# ======================================================================
#  TWEAK LISTS (rows with live status badges)
# ======================================================================
$txtVersion.Text = "SYSTEM UTILITY  v$AppVersion"
$txtLogPath.Text = "Log file: $LogFile   |   Backups: $BackupFile"
$script:TweakRecs   = New-Object System.Collections.Generic.List[object]
$script:ExtremeRecs = New-Object System.Collections.Generic.List[object]
$script:TweakHeaders   = @{}
$script:ExtremeHeaders = @{}

function New-TweakRow($t, [bool]$isAdv) {
    $border = New-Object System.Windows.Controls.Border
    $border.Background = '#161A21'; $border.CornerRadius = New-Object System.Windows.CornerRadius 6
    $border.Padding = '10,6,10,6'; $border.Margin = '0,0,0,6'
    $grid = New-Object System.Windows.Controls.Grid
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = [System.Windows.GridLength]::Auto
    [void]$grid.ColumnDefinitions.Add($c1); [void]$grid.ColumnDefinitions.Add($c2)

    $sp = New-Object System.Windows.Controls.StackPanel
    $cb = New-Object System.Windows.Controls.CheckBox
    $label = $t.Name
    if ($isAdv) { $label = "$($t.Name)   [$($t.Risk)]" }
    if ($t.Reboot) { $label += '   (restart)' }
    $cb.Content = $label; $cb.Tag = $t; $cb.Margin = '0,2,0,2'
    if ($isAdv) { if ($t.Risk -eq 'High') { $cb.Foreground = '#E08A8A' } elseif ($t.Risk -eq 'Medium') { $cb.Foreground = '#D6B676' } }
    $desc = New-Object System.Windows.Controls.TextBlock
    $desc.Text = $t.Desc; $desc.Foreground = '#8A90A0'; $desc.FontSize = 11.5
    $desc.Margin = '22,0,0,2'; $desc.TextWrapping = 'Wrap'
    [void]$sp.Children.Add($cb); [void]$sp.Children.Add($desc)

    $st = New-Object System.Windows.Controls.TextBlock
    $st.FontSize = 11; $st.Margin = '12,4,0,0'; $st.VerticalAlignment = 'Top'; $st.Foreground = '#6B7280'; $st.Text = '...'
    [System.Windows.Controls.Grid]::SetColumn($st, 1)
    [void]$grid.Children.Add($sp); [void]$grid.Children.Add($st)
    $border.Child = $grid

    return [pscustomobject]@{ CB = $cb; Status = $st; Tweak = $t; Row = $border; Category = $t.Category
                              Search = "$($t.Name) $($t.Desc) $($t.Category) $($t.Risk)"; State = $null }
}

function Build-TweakList($panel, $items, [bool]$isAdv, $recs, $headers) {
    $panel.Children.Clear(); $recs.Clear(); $headers.Clear()
    $order = @(); foreach ($t in $items) { if ($order -notcontains $t.Category) { $order += $t.Category } }
    foreach ($cat in $order) {
        $h = New-Object System.Windows.Controls.TextBlock
        $h.Style = $window.FindResource('H2')
        $count = @($items | Where-Object { $_.Category -eq $cat }).Count
        $h.Text = "$($cat.ToUpper())  ($count)"
        [void]$panel.Children.Add($h); $headers[$cat] = $h
        foreach ($t in ($items | Where-Object { $_.Category -eq $cat })) {
            $rec = New-TweakRow $t $isAdv
            [void]$panel.Children.Add($rec.Row); $recs.Add($rec)
        }
    }
}
Build-TweakList $tweakList   $Tweaks  $false $script:TweakRecs   $script:TweakHeaders
Build-TweakList $extremeList $Extreme $true  $script:ExtremeRecs $script:ExtremeHeaders

function Set-RecFilter($recs, $headers, $query) {
    $term = [string]$query
    $visibleCats = @{}
    foreach ($r in $recs) {
        $ok = [string]::IsNullOrWhiteSpace($term) -or $r.Search.IndexOf($term, [StringComparison]::OrdinalIgnoreCase) -ge 0
        $r.Row.Visibility = if ($ok) { 'Visible' } else { 'Collapsed' }
        if ($ok) { $visibleCats[$r.Category] = $true }
    }
    foreach ($k in $headers.Keys) { $headers[$k].Visibility = if ($visibleCats.ContainsKey($k)) { 'Visible' } else { 'Collapsed' } }
}
$txtTweakSearch.Add_TextChanged({ Set-RecFilter $script:TweakRecs $script:TweakHeaders $txtTweakSearch.Text })
$txtExtremeSearch.Add_TextChanged({ Set-RecFilter $script:ExtremeRecs $script:ExtremeHeaders $txtExtremeSearch.Text })

function Update-RecStatus($recs) {
    $i = 0
    foreach ($r in $recs) {
        $s = Test-Tweak $r.Tweak
        $r.State = $s
        if ($s -eq $true)      { $r.Status.Text = [char]0x25CF + ' Applied'; $r.Status.Foreground = '#4ADE80'; $r.Row.Background = '#14211A' }
        elseif ($s -eq $false) { $r.Status.Text = [char]0x25CB + ' Default'; $r.Status.Foreground = '#6B7280'; $r.Row.Background = '#161A21' }
        else                   { $r.Status.Text = '';                         $r.Row.Background = '#161A21' }
        $i++; if ($i % 6 -eq 0) { Pump }
    }
    $applied = @($script:TweakRecs | Where-Object { $_.State -eq $true }).Count
    $xapplied = @($script:ExtremeRecs | Where-Object { $_.State -eq $true }).Count
    $txtTweakCount.Text = "$applied of $($script:TweakRecs.Count) everyday tweaks applied  |  $xapplied of $($script:ExtremeRecs.Count) advanced"
}

function Run-Tweaks($mode, $recs, [bool]$isAdv) {
    $picked = @($recs | Where-Object { $_.CB.IsChecked -and $_.Row.Visibility -eq 'Visible' })
    if ($picked.Count -eq 0) { Log 'No visible items selected.'; return }

    if ($isAdv -and $mode -eq 'Apply') {
        $names = ($picked | ForEach-Object { "$($_.Tweak.Name) [$($_.Tweak.Risk)]" }) -join "`n- "
        if (-not (Confirm-Action "Apply these advanced system changes?`n`n- $names`n`nSome options affect security, compatibility, device behavior or power use. A restore point will be attempted first." 'Warning')) { Log 'Advanced changes cancelled.'; return }
    }
    if ($mode -eq 'Apply') {
        if (-not (New-SafeRestorePoint)) {
            if (-not (Confirm-Action 'Windows could not create a restore point. Continue anyway? (EduUtil still backs up every registry value it changes.)' 'Warning')) { Log 'Cancelled because no restore point was available.'; return }
        }
    }

    Set-Busy $true
    $failed = 0; $errors = @(); $needReboot = $false; $needExplorer = $false
    try {
        foreach ($r in $picked) {
            try {
                Log "$mode : $($r.Tweak.Name)"
                Invoke-Tweak $r.Tweak $mode
                if ($r.Tweak.Reboot) { $needReboot = $true }
                if ($r.Tweak.Explorer) { $needExplorer = $true }
            } catch {
                $failed++; $errors += "$($r.Tweak.Name): $($_.Exception.Message)"
                Log "Failed: $($r.Tweak.Name) - $($_.Exception.Message)"
            }
        }
        Save-BackupFile
        Update-RecStatus $picked
        Update-RecStatus @()
    } finally { Set-Busy $false }

    $ok = $picked.Count - $failed
    if ($failed -gt 0) {
        $details = ($errors | Select-Object -First 8) -join "`n"
        [System.Windows.MessageBox]::Show("$ok succeeded, $failed could not be applied:`n`n$details", 'EduUtil', 'OK', 'Warning') | Out-Null
    }
    Log "$mode finished: $ok succeeded, $failed failed."
    if ($needExplorer -and -not $needReboot) {
        if (Confirm-Action 'Some changes affect Explorer/taskbar. Restart Explorer now to see them? (Open Explorer windows will close.)') { Restart-Explorer }
    }
    if ($needReboot) {
        if (Confirm-Action 'Some changes need a restart to take effect. Restart Windows now?' 'Question') { Restart-Computer -Force }
        else { Log 'Restart Windows later to finish applying changes.' }
    }
}

$btnApply.Add_Click({ Run-Tweaks 'Apply' $script:TweakRecs $false })
$btnUndo.Add_Click({ Run-Tweaks 'Undo'  $script:TweakRecs $false })
$btnXApply.Add_Click({ Run-Tweaks 'Apply' $script:ExtremeRecs $true })
$btnXUndo.Add_Click({ Run-Tweaks 'Undo'  $script:ExtremeRecs $true })
$btnRefreshState.Add_Click({ Set-Busy $true; try { Update-RecStatus $script:TweakRecs } finally { Set-Busy $false }; Log 'Status refreshed.' })
$btnXRefresh.Add_Click({ Set-Busy $true; try { Update-RecStatus $script:ExtremeRecs } finally { Set-Busy $false }; Log 'Status refreshed.' })
$btnRP.Add_Click({ $script:rpDone = $false; [void](New-SafeRestorePoint) })

# ---------- presets & selection ----------
function Select-Preset($preset) {
    $txtTweakSearch.Text = ''
    $n = 0
    foreach ($r in $script:TweakRecs) {
        $on = @($r.Tweak.Preset) -contains $preset
        $r.CB.IsChecked = $on; if ($on) { $n++ }
    }
    Log "$preset preset: $n items checked. Review them, then click Apply selected."
}
$btnPresetRec.Add_Click({  Select-Preset 'Recommended' })
$btnPresetGame.Add_Click({ Select-Preset 'Gaming' })
$btnPresetPriv.Add_Click({ Select-Preset 'Privacy' })
$btnPresetDev.Add_Click({  Select-Preset 'Developer' })
$btnSelAll.Add_Click({  foreach ($r in $script:TweakRecs) { if ($r.Row.Visibility -eq 'Visible') { $r.CB.IsChecked = $true } } })
$btnSelUnapplied.Add_Click({ foreach ($r in $script:TweakRecs) { $r.CB.IsChecked = ($r.Row.Visibility -eq 'Visible' -and $r.State -eq $false) } })
$btnSelNone.Add_Click({ foreach ($r in $script:TweakRecs) { $r.CB.IsChecked = $false } })
$btnXSelLow.Add_Click({ foreach ($r in $script:ExtremeRecs) { $r.CB.IsChecked = ($r.Tweak.Risk -eq 'Low' -and $r.Row.Visibility -eq 'Visible') } })
$btnXSelNone.Add_Click({ foreach ($r in $script:ExtremeRecs) { $r.CB.IsChecked = $false } })

# ======================================================================
#  PROFILES
# ======================================================================
$btnExportProfile.Add_Click({
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = 'EduUtil profile (*.json)|*.json'; $dlg.FileName = 'EduUtil-profile.json'
    if (-not $dlg.ShowDialog()) { return }
    $prof = [ordered]@{
        Version  = $AppVersion
        Tweaks   = @($script:TweakRecs   | Where-Object { $_.CB.IsChecked } | ForEach-Object { $_.Tweak.Name })
        Advanced = @($script:ExtremeRecs | Where-Object { $_.CB.IsChecked } | ForEach-Object { $_.Tweak.Name })
        Apps     = @($script:AppRecs     | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    }
    $prof | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $dlg.FileName -Encoding UTF8
    Log "Profile saved: $($dlg.FileName) ($($prof.Tweaks.Count) tweaks, $($prof.Advanced.Count) advanced, $($prof.Apps.Count) apps)"
})
$btnImportProfile.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'EduUtil profile (*.json)|*.json'
    if (-not $dlg.ShowDialog()) { return }
    try {
        $p = Get-Content -LiteralPath $dlg.FileName -Raw | ConvertFrom-Json
        $tw = @($p.Tweaks); $ad = @($p.Advanced); $ap = @($p.Apps)
        foreach ($r in $script:TweakRecs)   { $r.CB.IsChecked = $tw -contains $r.Tweak.Name }
        foreach ($r in $script:ExtremeRecs) { $r.CB.IsChecked = $ad -contains $r.Tweak.Name }
        foreach ($c in $script:AppRecs)     { $c.IsChecked = $ap -contains $c.Tag }
        Log "Profile loaded: $($tw.Count) tweaks, $($ad.Count) advanced, $($ap.Count) apps checked. Review each page and click Apply/Install."
    } catch { Log "Could not read profile: $($_.Exception.Message)" }
})

# ======================================================================
#  GAME BOOST
# ======================================================================
$GpuPrefKey = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
$LayersKey  = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
$IfeoKey    = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'

function Set-LayerFlag($exe, $flag, [bool]$on) {
    $cur = [string](Get-RegValue $LayersKey $exe)
    $tokens = @($cur -split '\s+' | Where-Object { $_ -and $_ -ne '~' -and $_ -ne $flag })
    if ($on) { $tokens += $flag }
    if ($tokens.Count -eq 0) { Remove-Prop $LayersKey @($exe) } else { Set-Reg $LayersKey $exe ('~ ' + ($tokens -join ' ')) 'String' }
}
function Set-GpuPref($exe, [bool]$on) {
    $cur = [string](Get-RegValue $GpuPrefKey $exe)
    $parts = @($cur -split ';' | Where-Object { $_ -and $_ -notmatch '^GpuPreference=' })
    if ($on) { $parts += 'GpuPreference=2' }
    if ($parts.Count -eq 0) { Remove-Prop $GpuPrefKey @($exe) } else { Set-Reg $GpuPrefKey $exe (($parts -join ';') + ';') 'String' }
}
function Set-CpuPriority($exe, [bool]$on) {
    $leaf = [IO.Path]::GetFileName($exe)
    $k = "$IfeoKey\$leaf\PerfOptions"
    if ($on) { Set-Reg $k 'CpuPriorityClass' 3 }
    else {
        Remove-Item -LiteralPath $k -Recurse -Force -ErrorAction SilentlyContinue
        $parent = Get-Item -LiteralPath "$IfeoKey\$leaf" -ErrorAction SilentlyContinue
        if ($parent -and $parent.ValueCount -eq 0 -and $parent.SubKeyCount -eq 0) { Remove-Item -LiteralPath "$IfeoKey\$leaf" -Force -ErrorAction SilentlyContinue }
    }
}
function Refresh-GameList {
    $lstGames.Items.Clear()
    $paths = @()
    $k = Get-Item -LiteralPath $GpuPrefKey -ErrorAction SilentlyContinue
    if ($k) { $paths += $k.GetValueNames() | Where-Object { $_ -like '*.exe' } }
    $l = Get-Item -LiteralPath $LayersKey -ErrorAction SilentlyContinue
    if ($l) { $paths += $l.GetValueNames() | Where-Object { [string]$l.GetValue($_) -match 'DISABLEDXMAXIMIZEDWINDOWEDMODE|HIGHDPIAWARE' } }
    foreach ($p in ($paths | Sort-Object -Unique)) {
        $tags = @()
        if ([string](Get-RegValue $GpuPrefKey $p) -match 'GpuPreference=2') { $tags += 'GPU:High' }
        $lay = [string](Get-RegValue $LayersKey $p)
        if ($lay -match 'DISABLEDXMAXIMIZEDWINDOWEDMODE') { $tags += 'FSO:off' }
        if ($lay -match 'HIGHDPIAWARE') { $tags += 'DPI:app' }
        if ((Get-RegValue "$IfeoKey\$([IO.Path]::GetFileName($p))\PerfOptions" 'CpuPriorityClass') -eq 3) { $tags += 'CPU:High' }
        $item = New-Object System.Windows.Controls.ListBoxItem
        $item.Content = "{0,-28} {1}" -f ('[' + ($tags -join '] [') + ']'), $p
        $item.Tag = $p
        [void]$lstGames.Items.Add($item)
    }
    if ($lstGames.Items.Count -eq 0) { [void]$lstGames.Items.Add('No games configured yet.') }
}
$lstGames.Add_SelectionChanged({
    $sel = $lstGames.SelectedItem
    if ($sel -is [System.Windows.Controls.ListBoxItem] -and $sel.Tag) {
        $p = [string]$sel.Tag
        $txtGameExe.Text = $p
        $chkGameGpu.IsChecked = ([string](Get-RegValue $GpuPrefKey $p) -match 'GpuPreference=2')
        $lay = [string](Get-RegValue $LayersKey $p)
        $chkGameFso.IsChecked = ($lay -match 'DISABLEDXMAXIMIZEDWINDOWEDMODE')
        $chkGameDpi.IsChecked = ($lay -match 'HIGHDPIAWARE')
        $chkGameCpu.IsChecked = ((Get-RegValue "$IfeoKey\$([IO.Path]::GetFileName($p))\PerfOptions" 'CpuPriorityClass') -eq 3)
    }
})
$btnBrowseGame.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'Game executable (*.exe)|*.exe'; $dlg.Title = 'Select the game executable'
    $steam = "${env:ProgramFiles(x86)}\Steam\steamapps\common"
    if (Test-Path $steam) { $dlg.InitialDirectory = $steam }
    if ($dlg.ShowDialog()) { $txtGameExe.Text = $dlg.FileName }
})
$btnGameApply.Add_Click({
    $exe = $txtGameExe.Text
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { Log 'Pick a game .exe first.'; return }
    try {
        Set-GpuPref    $exe ([bool]$chkGameGpu.IsChecked)
        Set-CpuPriority $exe ([bool]$chkGameCpu.IsChecked)
        Set-LayerFlag  $exe 'DISABLEDXMAXIMIZEDWINDOWEDMODE' ([bool]$chkGameFso.IsChecked)
        Set-LayerFlag  $exe 'HIGHDPIAWARE' ([bool]$chkGameDpi.IsChecked)
        Log "Game boost applied to $([IO.Path]::GetFileName($exe)). Restart the game to take effect."
    } catch { Log "Game boost failed: $($_.Exception.Message)" }
    Refresh-GameList
})
$btnGameRemove.Add_Click({
    $exe = $txtGameExe.Text
    if (-not $exe) { Log 'Pick a game first.'; return }
    Set-GpuPref $exe $false; Set-CpuPriority $exe $false
    Set-LayerFlag $exe 'DISABLEDXMAXIMIZEDWINDOWEDMODE' $false; Set-LayerFlag $exe 'HIGHDPIAWARE' $false
    Log "Removed EduUtil settings for $([IO.Path]::GetFileName($exe))."
    Refresh-GameList
})
$btnGameModeSettings.Add_Click({ Start-Process 'ms-settings:gaming-gamemode' })
$btnGraphicsSettings.Add_Click({ Start-Process 'ms-settings:display-advancedgraphics' })

# ======================================================================
#  DEBLOAT
# ======================================================================
$script:BloatScanned = $false
function Refresh-Bloat {
    Set-Busy $true
    try {
        Log 'Scanning installed Store apps...'
        $bloatList.Children.Clear()
        try { $all = @(Get-AppxPackage -AllUsers -ErrorAction Stop) } catch { $all = @(Get-AppxPackage) }
        $n = 0
        foreach ($k in $BloatCatalog.Keys) {
            $pats = $BloatCatalog[$k]
            $found = @($all | Where-Object { $nm = $_.Name; @($pats | Where-Object { $nm -like $_ }).Count -gt 0 })
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Width = 280; $cb.Tag = $pats
            if ($found.Count -gt 0) { $cb.Content = $k; $n++ } else { $cb.Content = "$k  (not installed)"; $cb.IsEnabled = $false; $cb.Foreground = '#5B6270' }
            if ($k -like 'Xbox*') { $cb.ToolTip = 'Needed for Game Pass and Xbox achievements.' }
            [void]$bloatList.Children.Add($cb)
        }
        $script:BloatScanned = $true
        Log "Found $n removable preinstalled apps."
    } finally { Set-Busy $false }
}
$btnBloatRefresh.Add_Click({ Refresh-Bloat })
$btnBloatSelAll.Add_Click({ foreach ($c in $bloatList.Children) { if ($c.IsEnabled) { $c.IsChecked = $true } } })
$btnBloatSelNone.Add_Click({ foreach ($c in $bloatList.Children) { $c.IsChecked = $false } })
$btnBloatRemove.Add_Click({
    $picked = @($bloatList.Children | Where-Object { $_.IsChecked -and $_.IsEnabled })
    if ($picked.Count -eq 0) { Log 'Nothing selected.'; return }
    if (-not (Confirm-Action "Remove $($picked.Count) app(s)?`n`n$(($picked | ForEach-Object { $_.Content }) -join ', ')`n`nThey can be reinstalled from the Microsoft Store." 'Warning')) { return }
    [void](New-SafeRestorePoint)
    Set-Busy $true
    try {
        $prov = @()
        if ($chkBloatProvisioned.IsChecked) { try { $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop) } catch { } }
        foreach ($cb in $picked) {
            Log "Removing $($cb.Content)..."
            foreach ($pat in $cb.Tag) {
                foreach ($pkg in @(Get-AppxPackage -AllUsers -Name $pat -ErrorAction SilentlyContinue)) {
                    try { Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop }
                    catch { Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue }
                    Pump
                }
                foreach ($pp in @($prov | Where-Object { $_.DisplayName -like $pat })) {
                    Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction SilentlyContinue | Out-Null
                }
            }
        }
    } finally { Set-Busy $false }
    Log 'App removal finished.'
    Refresh-Bloat
})

# ======================================================================
#  STARTUP MANAGER
# ======================================================================
$SA = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
$StartupSources = @(
    @{ Kind = 'Reg';    Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';             Approved = "HKCU:\$SA\Run";           Scope = 'Current user' },
    @{ Kind = 'Reg';    Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';             Approved = "HKLM:\$SA\Run";           Scope = 'All users' },
    @{ Kind = 'Reg';    Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = "HKLM:\$SA\Run32";         Scope = 'All users (32-bit)' },
    @{ Kind = 'Folder'; Path = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup";       Approved = "HKCU:\$SA\StartupFolder"; Scope = 'User startup folder' },
    @{ Kind = 'Folder'; Path = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp";   Approved = "HKLM:\$SA\StartupFolder"; Scope = 'All-users startup folder' }
)
function Get-StartupEnabled($approved, $name) {
    $v = Get-RegValue $approved $name
    if ($v -is [byte[]] -and $v.Length -gt 0) { return (($v[0] -band 1) -eq 0) }
    return $true
}
function Refresh-Startup {
    $startupList.Children.Clear()
    $count = 0
    foreach ($src in $StartupSources) {
        $entries = @()
        if ($src.Kind -eq 'Reg') {
            $k = Get-Item -LiteralPath $src.Path -ErrorAction SilentlyContinue
            if ($k) { foreach ($n in $k.GetValueNames()) { if ($n) { $entries += @{ Name = $n; Cmd = [string]$k.GetValue($n) } } } }
        } elseif (Test-Path -LiteralPath $src.Path) {
            foreach ($f in (Get-ChildItem -LiteralPath $src.Path -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' })) { $entries += @{ Name = $f.Name; Cmd = $f.FullName } }
        }
        foreach ($e in $entries) {
            $enabled = Get-StartupEnabled $src.Approved $e.Name
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = "$($e.Name)     -  $($src.Scope)"
            $cb.ToolTip = $e.Cmd
            $cb.IsChecked = $enabled
            $cb.Tag = @{ Approved = $src.Approved; Name = $e.Name; Enabled = $enabled }
            [void]$startupList.Children.Add($cb)
            $d = New-Object System.Windows.Controls.TextBlock
            $d.Text = $e.Cmd; $d.Foreground = '#6B7280'; $d.FontSize = 11; $d.Margin = '22,-2,0,6'; $d.TextTrimming = 'CharacterEllipsis'
            [void]$startupList.Children.Add($d)
            $count++
        }
    }
    $enabledCount = @($startupList.Children | Where-Object { $_ -is [System.Windows.Controls.CheckBox] -and $_.IsChecked }).Count
    Log "Startup: $enabledCount of $count entries enabled."
}
$btnStartupRefresh.Add_Click({ Refresh-Startup })
$btnStartupApply.Add_Click({
    $changed = 0
    foreach ($cb in @($startupList.Children | Where-Object { $_ -is [System.Windows.Controls.CheckBox] })) {
        $info = $cb.Tag; $want = [bool]$cb.IsChecked
        if ($want -eq $info.Enabled) { continue }
        $bytes = New-Object byte[] 12
        if ($want) { $bytes[0] = 2 } else {
            $bytes[0] = 3
            [Array]::Copy([BitConverter]::GetBytes([DateTime]::Now.ToFileTime()), 0, $bytes, 4, 8)
        }
        try { Set-Reg $info.Approved $info.Name $bytes 'Binary'; $changed++; Log "$(if ($want) {'Enabled'} else {'Disabled'}) startup entry: $($info.Name)" }
        catch { Log "Could not change $($info.Name): $($_.Exception.Message)" }
    }
    Log "Startup changes applied: $changed."
    Refresh-Startup
})
$btnStartupFolder.Add_Click({ Start-Process explorer.exe "`"$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup`"" })
$btnTaskMgr.Add_Click({ Start-Process taskmgr.exe })

# ======================================================================
#  APPLICATIONS
# ======================================================================
$script:AppRecs = New-Object System.Collections.Generic.List[object]
$script:AppGroups = @()
foreach ($cat in $AppCatalog.Keys) {
    $h = New-Object System.Windows.Controls.TextBlock
    $h.Style = $window.FindResource('H2'); $h.Text = $cat.ToUpper()
    $wp = New-Object System.Windows.Controls.WrapPanel
    [void]$appList.Children.Add($h); [void]$appList.Children.Add($wp)
    $members = @()
    foreach ($k in $AppCatalog[$cat].Keys) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = $k; $cb.Tag = $AppCatalog[$cat][$k]; $cb.Width = 230; $cb.ToolTip = $AppCatalog[$cat][$k]
        [void]$wp.Children.Add($cb); $script:AppRecs.Add($cb); $members += $cb
    }
    $script:AppGroups += [pscustomobject]@{ Header = $h; Members = $members }
}
$txtAppSearch.Add_TextChanged({
    $term = $txtAppSearch.Text
    foreach ($g in $script:AppGroups) {
        $any = $false
        foreach ($cb in $g.Members) {
            $ok = [string]::IsNullOrWhiteSpace($term) -or "$($cb.Content) $($cb.Tag)".IndexOf($term, [StringComparison]::OrdinalIgnoreCase) -ge 0
            $cb.Visibility = if ($ok) { 'Visible' } else { 'Collapsed' }; if ($ok) { $any = $true }
        }
        $g.Header.Visibility = if ($any) { 'Visible' } else { 'Collapsed' }
    }
})
function Test-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return $true }
    Log 'winget not found. Install "App Installer" from the Microsoft Store.'
    Start-Process 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1'
    return $false
}
function Invoke-WingetBatch($verb) {
    if (-not (Test-Winget)) { return }
    $picked = @($script:AppRecs | Where-Object { $_.IsChecked })
    if ($picked.Count -eq 0) { Log 'Nothing selected.'; return }
    $ok = 0; $fail = @()
    foreach ($cb in $picked) {
        Log "$verb $($cb.Content)... ($($ok + $fail.Count + 1)/$($picked.Count))"
        $extra = if ($verb -eq 'install') { '--accept-package-agreements' } else { '' }
        $code = Invoke-Hidden 'winget.exe' "$verb --id $($cb.Tag) -e --silent $extra --accept-source-agreements --disable-interactivity"
        if ($code -eq 0 -or $code -eq -1978335189 -or $code -eq -1978335135) { $ok++ } else { $fail += "$($cb.Content) (code $code)" }
    }
    Log "winget $verb finished: $ok ok$(if ($fail) { '; failed: ' + ($fail -join ', ') })"
}
$btnInstall.Add_Click({ Invoke-WingetBatch 'install' })
$btnUninstall.Add_Click({
    $n = @($script:AppRecs | Where-Object { $_.IsChecked }).Count
    if ($n -and (Confirm-Action "Uninstall $n selected app(s)?" 'Warning')) { Invoke-WingetBatch 'uninstall' }
})
$btnUpgradeAll.Add_Click({
    if (-not (Test-Winget)) { return }
    Log 'Updating all installed apps with winget (this can take a while)...'
    $code = Invoke-Hidden 'winget.exe' 'upgrade --all --silent --include-unknown --accept-package-agreements --accept-source-agreements --disable-interactivity'
    Log "winget upgrade finished (exit code $code)."
})
$btnAppSelNone.Add_Click({ foreach ($c in $script:AppRecs) { $c.IsChecked = $false } })

# ======================================================================
#  MAINTENANCE
# ======================================================================
function Clear-Folders($paths) {
    $before = Get-FolderSizeMB $paths
    foreach ($p in @($paths)) {
        if ($p -and (Test-Path -LiteralPath $p)) {
            Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
            Pump
        }
    }
    $after = Get-FolderSizeMB $paths
    return [math]::Max(0, [math]::Round($before - $after, 1))
}
function Get-FreeGB { [math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'").FreeSpace / 1GB, 2) }

$TempPaths   = @($env:TEMP, "$env:WINDIR\Temp", "$env:LOCALAPPDATA\CrashDumps", "$env:ProgramData\Microsoft\Windows\WER\ReportArchive", "$env:ProgramData\Microsoft\Windows\WER\ReportQueue") | Select-Object -Unique
$ShaderPaths = @("$env:LOCALAPPDATA\D3DSCache", "$env:LOCALAPPDATA\NVIDIA\DXCache", "$env:LOCALAPPDATA\NVIDIA\GLCache",
                 "$env:USERPROFILE\AppData\LocalLow\NVIDIA\PerDriverVersion\DXCache", "$env:LOCALAPPDATA\AMD\DxCache",
                 "$env:LOCALAPPDATA\AMD\DxcCache", "$env:LOCALAPPDATA\AMD\GLCache", "$env:LOCALAPPDATA\AMD\VkCache",
                 "$env:LOCALAPPDATA\Intel\ShaderCache")

$btnTemp.Add_Click({
    if (-not (Confirm-Action 'Remove temporary files, crash dumps and old error reports? Open files are skipped.')) { return }
    Set-Busy $true; try { Log 'Cleaning temporary files...'; $mb = Clear-Folders $TempPaths } finally { Set-Busy $false }
    Log "Temporary-file cleanup freed $mb MB."
})
$btnBin.Add_Click({
    if (-not (Confirm-Action 'Permanently empty the Recycle Bin on all drives?' 'Warning')) { return }
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Log 'Recycle Bin emptied.'
})
$btnShader.Add_Click({
    if (-not (Confirm-Action 'Clear DirectX, NVIDIA, AMD and Intel shader caches? Games rebuild them (short stutter on first launch). Useful after GPU driver updates or when a game stutters/crashes.')) { return }
    Set-Busy $true; try { $mb = Clear-Folders $ShaderPaths } finally { Set-Busy $false }
    Log "Shader caches cleared: $mb MB freed."
})
$btnDiskCleanup.Add_Click({
    if (-not (Confirm-Action 'Run Windows Disk Cleanup with all system categories EXCEPT your Downloads folder, previous Windows installations and reset/recovery files? This can take several minutes.')) { return }
    $free = Get-FreeGB
    $vc = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    $skip = @('DownloadsFolder','Previous Installations','Windows ESD installation files','Windows Upgrade Log Files')
    Get-ChildItem $vc -ErrorAction SilentlyContinue | Where-Object { $skip -notcontains $_.PSChildName } | ForEach-Object { Set-Reg $_.PSPath 'StateFlags0777' 2 }
    Get-ChildItem $vc -ErrorAction SilentlyContinue | Where-Object { $skip -contains $_.PSChildName } | ForEach-Object { Remove-Prop $_.PSPath @('StateFlags0777') }
    Log 'Running Disk Cleanup...'
    [void](Invoke-Hidden 'cleanmgr.exe' '/sagerun:777')
    Log "Disk Cleanup finished. Freed about $([math]::Round((Get-FreeGB) - $free, 2)) GB."
})
function Clear-WUDownloadCache {
    Stop-Service wuauserv, bits -Force -ErrorAction SilentlyContinue
    $mb = Clear-Folders @("$env:WINDIR\SoftwareDistribution\Download")
    Start-Service bits, wuauserv -ErrorAction SilentlyContinue
    return $mb
}
$btnWUCache.Add_Click({
    Set-Busy $true; try { Log 'Clearing Windows Update download cache...'; $mb = Clear-WUDownloadCache } finally { Set-Busy $false }
    Log "Windows Update cache cleared: $mb MB freed. Pending updates will re-download."
})
$btnDOCache.Add_Click({
    try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop; Log 'Delivery Optimization cache cleared.' }
    catch { $mb = Clear-Folders @("$env:WINDIR\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"); Log "Delivery Optimization cache cleared: $mb MB." }
})
$btnComponent.Add_Click({
    if (-not (Confirm-Action 'Clean up superseded Windows components (WinSxS)? Often frees several GB. Installed updates can no longer be uninstalled afterwards. Takes 5-20 minutes.')) { return }
    $free = Get-FreeGB; Log 'Cleaning component store (DISM)...'
    $code = Invoke-Hidden 'DISM.exe' '/Online /Cleanup-Image /StartComponentCleanup /Quiet'
    Log "Component cleanup finished (code $code). Freed about $([math]::Round((Get-FreeGB) - $free, 2)) GB."
})
$btnThumb.Add_Click({
    if (-not (Confirm-Action 'Rebuild thumbnail and icon caches? Explorer will restart. Fixes wrong/blank icons and thumbnails.')) { return }
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 800
    Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" -Filter '*cache_*.db' -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    Log 'Thumbnail and icon caches rebuilt.'
})
$btnStoreCache.Add_Click({ Start-Process wsreset.exe; Log 'Microsoft Store cache reset started (the Store will open when done).' })
$btnCleanAll.Add_Click({
    if (-not (Confirm-Action "One-click cleanup will remove:`n- Temp files, crash dumps, old error reports`n- Windows Update download cache`n- Delivery Optimization cache`n- Recycle Bin contents`n`nContinue?")) { return }
    $free = Get-FreeGB
    Set-Busy $true
    try {
        Log 'One-click cleanup: temp files...'; [void](Clear-Folders $TempPaths)
        Log 'One-click cleanup: Windows Update cache...'; [void](Clear-WUDownloadCache)
        Log 'One-click cleanup: Delivery Optimization...'; try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop } catch { }
        Log 'One-click cleanup: Recycle Bin...'; Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    } finally { Set-Busy $false }
    Log "One-click cleanup done. Freed about $([math]::Round((Get-FreeGB) - $free, 2)) GB on $env:SystemDrive."
})
$btnSfc.Add_Click({
    if (-not (Confirm-Action 'Run DISM image repair followed by System File Checker? Takes 10-30 minutes; you can keep using the PC.')) { return }
    Log 'DISM RestoreHealth running...'
    $d = Invoke-Hidden 'DISM.exe' '/Online /Cleanup-Image /RestoreHealth /Quiet'
    Log "DISM finished (code $d). Running SFC..."
    $s = Invoke-Hidden 'sfc.exe' '/scannow'
    Log "SFC finished (code $s). Details: $env:WINDIR\Logs\CBS\CBS.log. Restart if files were repaired."
})
$btnOptimizeDrive.Add_Click({
    Log 'Optimizing all fixed drives (TRIM for SSDs, defrag for HDDs)...'
    $code = Invoke-Hidden 'defrag.exe' '/C /O'
    Log "Drive optimization finished (code $code)."
})
$btnRestartExplorer.Add_Click({ Restart-Explorer })
$btnResetWU.Add_Click({
    if (-not (Confirm-Action 'Reset Windows Update components? Stops update services, renames SoftwareDistribution and catroot2, then restarts them. Fixes most stuck/failing updates. Update history display is reset.' 'Warning')) { return }
    Set-Busy $true
    try {
        $svcs = 'wuauserv','cryptSvc','bits','msiserver'
        Stop-Service $svcs -Force -ErrorAction SilentlyContinue
        foreach ($p in @("$env:WINDIR\SoftwareDistribution", "$env:WINDIR\System32\catroot2")) {
            Remove-Item "$p.old" -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path $p) { Rename-Item $p "$([IO.Path]::GetFileName($p)).old" -ErrorAction SilentlyContinue }
        }
        Start-Service $svcs -ErrorAction SilentlyContinue
    } finally { Set-Busy $false }
    Log 'Windows Update components reset. Check for updates again.'
})
$btnChkdsk.Add_Click({
    Log "Scanning $env:SystemDrive for file-system errors (online, no reboot)..."
    $code = Invoke-Hidden 'chkdsk.exe' "$env:SystemDrive /scan"
    if ($code -eq 0) { Log 'chkdsk: no problems found.' }
    else {
        Log "chkdsk reported issues (code $code)."
        if (Confirm-Action 'chkdsk found problems. Schedule a repair (chkdsk /f) on next restart?' 'Warning') {
            [void](Invoke-Hidden 'cmd.exe' "/c echo Y| chkdsk $env:SystemDrive /f")
            Log 'Disk repair scheduled for next restart.'
        }
    }
})
$btnDiskHealth.Add_Click({
    try {
        $lines = foreach ($d in (Get-PhysicalDisk -ErrorAction Stop)) {
            $rc = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
            $size = [math]::Round($d.Size / 1GB)
            $wear = if ($rc -and $null -ne $rc.Wear) { "$($rc.Wear)% used" } else { 'n/a' }
            $temp = if ($rc -and $rc.Temperature) { "$($rc.Temperature) C" } else { 'n/a' }
            $hrs  = if ($rc -and $rc.PowerOnHours) { "$($rc.PowerOnHours) h" } else { 'n/a' }
            "$($d.FriendlyName)`n   $($d.MediaType) / $($d.BusType), $size GB`n   Health: $($d.HealthStatus)   Wear: $wear   Temp: $temp   Power-on: $hrs`n"
        }
        [System.Windows.MessageBox]::Show(($lines -join "`n"), 'EduUtil - Drive health', 'OK', 'Information') | Out-Null
    } catch { Log "Drive health unavailable: $($_.Exception.Message)" }
})
$btnBattery.Add_Click({
    if (-not (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)) { Log 'No battery detected on this PC.'; return }
    $out = Join-Path ([Environment]::GetFolderPath('Desktop')) 'battery-report.html'
    powercfg /batteryreport /output "$out" | Out-Null
    if (Test-Path $out) { Start-Process $out; Log "Battery report saved to $out" }
})
$btnReliability.Add_Click({ Start-Process perfmon.exe '/rel' })
$btnMemTest.Add_Click({ Start-Process mdsched.exe })
$btnRestorePoints.Add_Click({ Start-Process rstrui.exe })
$btnWinUpdate.Add_Click({ Start-Process 'ms-settings:windowsupdate' })

# ======================================================================
#  NETWORK
# ======================================================================
function Write-Net($text) { $txtNetOut.AppendText($text + [Environment]::NewLine); $txtNetOut.ScrollToEnd(); Pump }
function Set-DnsAll($servers, $label) {
    try {
        $adapters = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object Status -eq 'Up')
        if ($adapters.Count -eq 0) { Log 'No connected network adapters found.'; return }
        foreach ($a in $adapters) {
            if ($servers) { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $servers -ErrorAction Stop }
            else { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ResetServerAddresses -ErrorAction Stop }
            Write-Net "DNS for '$($a.Name)' set to $label"
        }
        Clear-DnsClientCache
        Log "DNS set to $label on $($adapters.Count) adapter(s)."
    } catch { Log "DNS change failed: $($_.Exception.Message)" }
}
$btnDnsCloudflare.Add_Click({ Set-DnsAll @('1.1.1.1','1.0.0.1','2606:4700:4700::1111','2606:4700:4700::1001') 'Cloudflare' })
$btnDnsGoogle.Add_Click({     Set-DnsAll @('8.8.8.8','8.8.4.4','2001:4860:4860::8888','2001:4860:4860::8844') 'Google' })
$btnDnsQuad9.Add_Click({      Set-DnsAll @('9.9.9.9','149.112.112.112','2620:fe::fe','2620:fe::9') 'Quad9' })
$btnDnsAuto.Add_Click({       Set-DnsAll $null 'Automatic (DHCP)' })
$btnDnsBench.Add_Click({
    $txtNetOut.Clear()
    $domains = 'google.com','steampowered.com','discord.com','microsoft.com','epicgames.com','cloudflare.com','riotgames.com','github.com'
    $current = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.ServerAddresses } | Select-Object -First 1 -ExpandProperty ServerAddresses) | Select-Object -First 1
    $servers = [ordered]@{ 'Cloudflare 1.1.1.1' = '1.1.1.1'; 'Google 8.8.8.8' = '8.8.8.8'; 'Quad9 9.9.9.9' = '9.9.9.9' }
    if ($current) { $servers["Current ($current)"] = $current }
    Write-Net 'DNS benchmark (average lookup time over 8 popular domains)'
    Write-Net '--------------------------------------------------------'
    Set-Busy $true
    try {
        foreach ($k in $servers.Keys) {
            $times = @()
            foreach ($d in $domains) {
                $ms = (Measure-Command { Resolve-DnsName -Name $d -Server $servers[$k] -DnsOnly -NoHostsFile -QuickTimeout -ErrorAction SilentlyContinue | Out-Null }).TotalMilliseconds
                $times += $ms; Pump
            }
            Write-Net ("{0,-28} {1,7:N1} ms" -f $k, (($times | Measure-Object -Average).Average))
        }
    } finally { Set-Busy $false }
    Write-Net 'Lower is better. Pick the fastest with the buttons above.'
})
$btnDns.Add_Click({ ipconfig /flushdns | Out-Null; Log 'DNS resolver cache flushed.' })
$btnAdapters.Add_Click({
    $txtNetOut.Clear()
    foreach ($a in (Get-NetAdapter -ErrorAction SilentlyContinue | Sort-Object Status, Name)) {
        Write-Net "$($a.Name)  [$($a.Status)]"
        Write-Net "   $($a.InterfaceDescription)"
        Write-Net "   Link: $($a.LinkSpeed)   MAC: $($a.MacAddress)"
        $ip = Get-NetIPConfiguration -InterfaceIndex $a.ifIndex -ErrorAction SilentlyContinue
        if ($ip) {
            Write-Net "   IPv4: $(($ip.IPv4Address.IPAddress) -join ', ')   Gateway: $(($ip.IPv4DefaultGateway.NextHop) -join ', ')"
            Write-Net "   DNS : $(($ip.DNSServer | Where-Object AddressFamily -eq 2).ServerAddresses -join ', ')"
        }
        Write-Net ''
    }
})
$btnNetworkReset.Add_Click({
    if (-not (Confirm-Action 'Reset Winsock and TCP/IP? Fixes "connected but no internet" and broken VPN leftovers. Custom IP settings are removed and a restart is required.' 'Warning')) { return }
    [void](Invoke-Hidden 'netsh.exe' 'winsock reset')
    [void](Invoke-Hidden 'netsh.exe' 'int ip reset')
    ipconfig /flushdns | Out-Null
    Log 'Network stack reset completed. Restart Windows to finish.'
})
$btnPing.Add_Click({
    $txtNetOut.Clear()
    $targets = @($txtPingHost.Text -split '[,; ]+' | Where-Object { $_ })
    if (-not $targets) { return }
    Write-Net ("{0,-22} {1,8} {2,8} {3,8} {4,8} {5,7}" -f 'Host','Avg ms','Min','Max','Jitter','Loss')
    Write-Net ('-' * 66)
    Set-Busy $true
    try {
        $ping = New-Object System.Net.NetworkInformation.Ping
        foreach ($h in $targets) {
            $rtts = @(); $lost = 0
            for ($i = 0; $i -lt 20; $i++) {
                try { $r = $ping.Send($h, 1000); if ($r.Status -eq 'Success') { $rtts += [double]$r.RoundtripTime } else { $lost++ } } catch { $lost++ }
                Pump; Start-Sleep -Milliseconds 100
            }
            if ($rtts.Count -gt 0) {
                $jit = 0; for ($j = 1; $j -lt $rtts.Count; $j++) { $jit += [math]::Abs($rtts[$j] - $rtts[$j - 1]) }
                if ($rtts.Count -gt 1) { $jit = $jit / ($rtts.Count - 1) }
                $m = $rtts | Measure-Object -Average -Minimum -Maximum
                Write-Net ("{0,-22} {1,8:N1} {2,8:N0} {3,8:N0} {4,8:N1} {5,6:N0}%" -f $h, $m.Average, $m.Minimum, $m.Maximum, $jit, ($lost * 5))
            } else { Write-Net ("{0,-22} unreachable (100% loss)" -f $h) }
        }
    } finally { Set-Busy $false }
    Write-Net ''
    Write-Net 'Jitter above ~5 ms or any packet loss usually means Wi-Fi interference or a busy connection - try Ethernet.'
})

# ======================================================================
#  SYSTEM INFO & HEALTH CHECK
# ======================================================================
function Get-HealthReport {
    $sb = New-Object System.Text.StringBuilder
    $tips = New-Object System.Collections.Generic.List[string]
    function Add-Line($s) { [void]$sb.AppendLine($s) }

    $os    = Get-CimInstance Win32_OperatingSystem
    $cpu   = @(Get-CimInstance Win32_Processor)[0]
    $cs    = Get-CimInstance Win32_ComputerSystem
    $gpus  = @(Get-CimInstance Win32_VideoController)
    $bios  = Get-CimInstance Win32_BIOS
    $board = Get-CimInstance Win32_BaseBoard
    $mem   = @(Get-CimInstance Win32_PhysicalMemory)
    $cv    = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = "$(Get-RegValue $cv 'CurrentBuild').$(Get-RegValue $cv 'UBR')"
    $disp  = Get-RegValue $cv 'DisplayVersion'
    $uptime = (Get-Date) - $os.LastBootUpTime
    $isLaptop = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)

    Add-Line '================================================================'
    Add-Line " OS        : $($os.Caption) $disp (build $build, $($os.OSArchitecture))"
    Add-Line " Uptime    : $([int]$uptime.TotalDays) d $($uptime.Hours) h      Computer: $($cs.Name)"
    Add-Line '----------------------------------------------------------------'
    Add-Line " CPU       : $($cpu.Name.Trim())"
    Add-Line "             $($cpu.NumberOfCores) cores / $($cpu.NumberOfLogicalProcessors) threads, max $($cpu.MaxClockSpeed) MHz"
    Add-Line " Board     : $($board.Manufacturer) $($board.Product)   BIOS $($bios.SMBIOSBIOSVersion) ($(if ($bios.ReleaseDate) { $bios.ReleaseDate.ToString('yyyy-MM-dd') }))"
    Add-Line '----------------------------------------------------------------'
    $totalGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    $freeGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    Add-Line " RAM       : $totalGB GB total, $freeGB GB free, $($mem.Count) module(s)"
    foreach ($m in $mem) {
        Add-Line ("             {0} GB  {1}  rated {2} MT/s, running {3} MT/s  [{4}]" -f [math]::Round($m.Capacity / 1GB), $m.Manufacturer, $m.Speed, $m.ConfiguredClockSpeed, $m.DeviceLocator)
    }
    Add-Line '----------------------------------------------------------------'
    $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    $vram = @{}
    Get-ChildItem $classKey -ErrorAction SilentlyContinue | ForEach-Object {
        $q = Get-RegValue $_.PSPath 'HardwareInformation.qwMemorySize'; $dn = Get-RegValue $_.PSPath 'DriverDesc'
        if ($q -and $dn) { $vram[$dn] = [math]::Round([double]$q / 1GB, 1) }
    }
    foreach ($g in $gpus) {
        $vr = if ($vram.ContainsKey($g.Name)) { "$($vram[$g.Name]) GB" } else { "$([math]::Round($g.AdapterRAM / 1GB, 1)) GB+" }
        $ddate = if ($g.DriverDate) { $g.DriverDate.ToString('yyyy-MM-dd') } else { '?' }
        Add-Line " GPU       : $($g.Name)   VRAM $vr"
        Add-Line "             Driver $($g.DriverVersion) ($ddate)   $($g.CurrentHorizontalResolution)x$($g.CurrentVerticalResolution) @ $($g.CurrentRefreshRate) Hz"
        if ($g.DriverDate -and ((Get-Date) - $g.DriverDate).TotalDays -gt 180 -and $g.Name -match 'NVIDIA|AMD|Radeon|Intel\(R\) Arc') {
            $tips.Add("GPU driver for $($g.Name) is from $ddate (over 6 months old). New drivers often add game-specific performance fixes.")
        }
        if ($g.CurrentRefreshRate -eq 60 -and $g.MaxRefreshRate -gt 75) {
            $tips.Add("Display is running at 60 Hz but the adapter reports up to $($g.MaxRefreshRate) Hz. If your monitor supports it, raise it in Settings > Display > Advanced display.")
        }
    }
    Add-Line '----------------------------------------------------------------'
    try {
        foreach ($d in (Get-PhysicalDisk -ErrorAction Stop)) {
            Add-Line (" Disk      : {0}  ({1}/{2}, {3} GB, health: {4})" -f $d.FriendlyName, $d.MediaType, $d.BusType, [math]::Round($d.Size / 1GB), $d.HealthStatus)
            if ([string]$d.HealthStatus -ne 'Healthy') { $tips.Add("Drive '$($d.FriendlyName)' reports health '$($d.HealthStatus)'. Back up your data now.") }
            if ([string]$d.MediaType -eq 'HDD' -and $d.DeviceId -eq '0') { $tips.Add('Windows appears to be on a hard drive (HDD). Moving to an SSD is the single biggest speed upgrade available.') }
        }
    } catch { }
    foreach ($v in (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')) {
        $pct = if ($v.Size) { [math]::Round($v.FreeSpace / $v.Size * 100) } else { 0 }
        Add-Line (" Volume    : {0}  {1} GB free of {2} GB ({3}%)" -f $v.DeviceID, [math]::Round($v.FreeSpace / 1GB, 1), [math]::Round($v.Size / 1GB), $pct)
        if ($pct -lt 15) { $tips.Add("Drive $($v.DeviceID) is $pct% free. Keep 15%+ free for SSD performance and updates - try Maintenance > One-click cleanup.") }
    }
    Add-Line '----------------------------------------------------------------'
    $plan = "$(powercfg /getactivescheme 2>&1)" -replace '^.*\(|\).*$', ''
    $hags = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode'
    $gm   = Get-RegValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled'
    $vbs  = $null; try { $vbs = (Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction Stop).VirtualizationBasedSecurityStatus } catch { }
    $sb2  = 'Unknown'; try { $sb2 = if (Confirm-SecureBootUEFI -ErrorAction Stop) { 'On' } else { 'Off' } } catch { $sb2 = 'Unsupported/Legacy BIOS' }
    $tpm  = 'Unknown'; try { $t = Get-Tpm -ErrorAction Stop; $tpm = if ($t.TpmPresent) { "Present (ready: $($t.TpmReady))" } else { 'Not present' } } catch { }
    Add-Line " Power plan: $plan"
    Add-Line " Game Mode : $(if ($gm -eq 0) { 'Off' } else { 'On' })      HAGS: $(if ($hags -eq 2) { 'On' } elseif ($hags -eq 1) { 'Off' } else { 'Default' })"
    Add-Line " VBS       : $(switch ($vbs) { 2 { 'Running' } 1 { 'Enabled, not running' } 0 { 'Off' } default { 'Unknown' } })      Secure Boot: $sb2      TPM: $tpm"
    $pending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    $tempMB = Get-FolderSizeMB @($env:TEMP, "$env:WINDIR\Temp")
    $startupCount = 0
    foreach ($src in $StartupSources) {
        if ($src.Kind -eq 'Reg') { $k = Get-Item -LiteralPath $src.Path -ErrorAction SilentlyContinue; if ($k) { foreach ($n in $k.GetValueNames()) { if ($n -and (Get-StartupEnabled $src.Approved $n)) { $startupCount++ } } } }
        elseif (Test-Path -LiteralPath $src.Path) { foreach ($f in (Get-ChildItem -LiteralPath $src.Path -File -ErrorAction SilentlyContinue | Where-Object Name -ne 'desktop.ini')) { if (Get-StartupEnabled $src.Approved $f.Name) { $startupCount++ } } }
    }
    Add-Line " Temp files: $tempMB MB      Startup apps enabled: $startupCount      Restart pending: $(if ($pending) { 'YES' } else { 'no' })"
    Add-Line '================================================================'

    # ---- recommendations ----
    $memRunning = @($mem | ForEach-Object { $_.ConfiguredClockSpeed } | Where-Object { $_ }) | Sort-Object -Unique | Select-Object -First 1
    $memRated   = @($mem | ForEach-Object { $_.Speed } | Where-Object { $_ }) | Sort-Object -Descending | Select-Object -First 1
    if ($memRunning -and $memRated -and $memRunning -lt $memRated) {
        $tips.Add("RAM is running at $memRunning MT/s but is rated for $memRated MT/s. Enable XMP/EXPO/DOCP in your BIOS - often a 5-15% FPS gain in CPU-bound games.")
    } elseif ($memRunning -and @(2133, 2400, 2666, 4800) -contains [int]$memRunning -and -not $isLaptop) {
        $tips.Add("RAM is running at a JEDEC default speed ($memRunning MT/s). If your kit's box/label lists a higher speed, enable XMP/EXPO in BIOS.")
    }
    if ($mem.Count -eq 1 -and -not $isLaptop) { $tips.Add('Only one RAM module installed (single-channel). Adding a matching second stick doubles memory bandwidth - a large gain for gaming and integrated graphics.') }
    if ($totalGB -lt 15) { $tips.Add("Only $totalGB GB RAM. 16 GB is the practical minimum for modern games with Discord/browser open.") }
    if ($plan -match 'Balanced|Power saver' -and -not $isLaptop) { $tips.Add('Desktop is on the Balanced/Power saver plan. Try "High Performance power plan" in Tweaks if you want maximum clocks.') }
    if ($gm -eq 0) { $tips.Add('Game Mode is off. Enable it in Tweaks > Gaming & input.') }
    if ($hags -ne 2) { $tips.Add('Hardware-accelerated GPU scheduling is off. It is required for DLSS Frame Generation (Advanced > Graphics).') }
    if ($vbs -eq 2) { $tips.Add('Memory Integrity/VBS is running. This costs some FPS in CPU-bound games; it is a security trade-off (see Advanced > Security trade-offs).') }
    if ($uptime.TotalDays -gt 7) { $tips.Add("PC has been running $([int]$uptime.TotalDays) days without a restart. A restart clears memory leaks and finishes updates.") }
    if ($pending) { $tips.Add('A restart is pending to finish installing updates or changes.') }
    if ($tempMB -gt 1024) { $tips.Add("Temp folders hold $([math]::Round($tempMB / 1024, 1)) GB. Run Maintenance > Clean temporary files.") }
    if ($startupCount -gt 10) { $tips.Add("$startupCount apps start with Windows. Disable the ones you do not need on the Startup apps page for a faster boot.") }
    if ($bios.ReleaseDate -and ((Get-Date) - $bios.ReleaseDate).TotalDays -gt 1095) { $tips.Add('BIOS is over 3 years old. Updates from your board/laptop maker often fix stability, memory compatibility and CPU security issues.') }

    Add-Line ''
    Add-Line " HEALTH CHECK - $($tips.Count) recommendation(s)"
    Add-Line '----------------------------------------------------------------'
    if ($tips.Count -eq 0) { Add-Line ' Everything looks good.' }
    $i = 1; foreach ($t in $tips) { Add-Line " $i. $t"; $i++ }
    return $sb.ToString()
}
function Refresh-SysInfo {
    Set-Busy $true
    try { Log 'Running health check...'; $txtSysInfo.Text = Get-HealthReport; Log 'Health check complete.' }
    catch { Log "Health check error: $($_.Exception.Message)" }
    finally { Set-Busy $false }
}
$btnRefreshInfo.Add_Click({ Refresh-SysInfo })
$btnCopyInfo.Add_Click({ if ($txtSysInfo.Text) { [System.Windows.Clipboard]::SetText($txtSysInfo.Text); Log 'Report copied to clipboard.' } })
$btnSaveInfo.Add_Click({
    if (-not $txtSysInfo.Text) { Refresh-SysInfo }
    $out = Join-Path ([Environment]::GetFolderPath('Desktop')) "EduUtil-report-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
    Set-Content -LiteralPath $out -Value $txtSysInfo.Text -Encoding UTF8
    Log "Report saved to $out"
})

# ======================================================================
#  LOG PAGE
# ======================================================================
$btnOpenLogFolder.Add_Click({ Start-Process explorer.exe "`"$DataDir`"" })
$btnClearBackup.Add_Click({
    if (Confirm-Action 'Forget all saved original values? Undo will then fall back to Windows defaults.' 'Warning') {
        $script:Backup = @{}; Save-BackupFile; Log 'Saved backups cleared.'
    }
})

# ======================================================================
#  NAVIGATION
# ======================================================================
$Pages = [ordered]@{
    navTweaks = 'pgTweaks'; navExtreme = 'pgExtreme'; navGame = 'pgGame'; navDebloat = 'pgDebloat'; navStartup = 'pgStartup'
    navInstall = 'pgInstall'; navClean = 'pgClean'; navNetwork = 'pgNetwork'; navSysInfo = 'pgSysInfo'; navLog = 'pgLog'
}
$script:SysInfoLoaded = $false
$script:StartupLoaded = $false
function Show-Page($nav) {
    foreach ($k in $Pages.Keys) {
        $pg = Get-Variable -Name $Pages[$k] -Scope Script -ValueOnly
        $btn = Get-Variable -Name $k -Scope Script -ValueOnly
        if ($k -eq $nav) { $pg.Visibility = 'Visible'; $btn.Background = '#2A3550'; $btn.Foreground = 'White' }
        else { $pg.Visibility = 'Collapsed'; $btn.Background = 'Transparent'; $btn.Foreground = '#C9CED8' }
    }
    switch ($nav) {
        'navGame'    { Refresh-GameList }
        'navDebloat' { if (-not $script:BloatScanned) { Refresh-Bloat } }
        'navStartup' { if (-not $script:StartupLoaded) { Refresh-Startup; $script:StartupLoaded = $true } }
        'navSysInfo' { if (-not $script:SysInfoLoaded) { Refresh-SysInfo; $script:SysInfoLoaded = $true } }
    }
}
foreach ($k in $Pages.Keys) {
    $btn = Get-Variable -Name $k -Scope Script -ValueOnly
    $btn.Tag = $k
    $btn.Add_Click({ param($sender, $e) Show-Page $sender.Tag })
}

# ---------- startup ----------
$window.Add_ContentRendered({
    Show-Page 'navTweaks'
    Log "EduUtil v$AppVersion ready. Checking which tweaks are already applied..."
    Set-Busy $true
    try { Update-RecStatus $script:TweakRecs; Update-RecStatus $script:ExtremeRecs } finally { Set-Busy $false }
    Log 'Ready. Pick a preset or select individual tweaks, then click Apply selected.'
})
[void]$window.ShowDialog()
