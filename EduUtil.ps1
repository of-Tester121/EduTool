#requires -Version 5.1
<#
.SYNOPSIS
    EduUtil - Windows Performance & Maintenance Utility  (v3: animated loader, 150+ more tweaks, Toolbox, live monitor)

#>

$RepoUrl = 'https://raw.githubusercontent.com/of-Tester121/EduTool/main/EduUtil.ps1'
$AppVersion = '3.0'

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


# ======================================================================
#  CONSOLE LOADING SCREEN (matrix rain -> logo shine -> live hardware scan)
#  Skip it with:  $env:EDUUTIL_NOSPLASH = 1   (or press any key while it runs)
# ======================================================================
function Show-EduSplash {
    if ($env:EDUUTIL_NOSPLASH) { return }
    if ($Host.Name -ne 'ConsoleHost') { return }
    $oldFg = [Console]::ForegroundColor; $oldTitle = $Host.UI.RawUI.WindowTitle
    $script:splashSkip = $false
    try {
        $W = [Console]::WindowWidth; $H = [Console]::WindowHeight
        if ($W -lt 64 -or $H -lt 22) { return }
        [Console]::CursorVisible = $false
        $Host.UI.RawUI.WindowTitle = 'EduUtil - starting...'
        $full = [string][char]0x2588; $shade = [string][char]0x2591

        function Sp-Put([int]$x, [int]$y, [string]$t, $c) {
            if ($x -lt 0 -or $x -ge ($W - 1) -or $y -lt 0 -or $y -ge ($H - 1)) { return }
            [Console]::SetCursorPosition($x, $y); [Console]::ForegroundColor = $c; [Console]::Write($t)
        }
        function Sp-Key { try { if ([Console]::KeyAvailable) { [void][Console]::ReadKey($true); $script:splashSkip = $true } } catch { } ; return $script:splashSkip }

        # ---- phase 1: matrix rain ----
        Clear-Host
        $rnd = New-Object System.Random
        $glyphs = '01#$%&*<>=+/\|abcdefXYZ'
        $cols = [int](($W - 2) / 2)
        $ys = New-Object 'int[]' $cols; $sp = New-Object 'int[]' $cols; $ln = New-Object 'int[]' $cols
        for ($i = 0; $i -lt $cols; $i++) { $ys[$i] = -$rnd.Next(0, $H); $sp[$i] = $rnd.Next(1, 3); $ln[$i] = $rnd.Next(5, 12) }
        for ($f = 0; $f -lt 34; $f++) {
            for ($i = 0; $i -lt $cols; $i++) {
                $x = $i * 2
                $y = $ys[$i]
                Sp-Put $x $y ($glyphs[$rnd.Next(0, $glyphs.Length)]) 'White'
                Sp-Put $x ($y - 1) ($glyphs[$rnd.Next(0, $glyphs.Length)]) 'Green'
                Sp-Put $x ($y - 3) ($glyphs[$rnd.Next(0, $glyphs.Length)]) 'DarkGreen'
                Sp-Put $x ($y - $ln[$i]) ' ' 'Black'
                $ys[$i] = $y + $sp[$i]
            }
            if (Sp-Key) { return }
            Start-Sleep -Milliseconds 32
        }
        # wipe the rain away column by column
        for ($i = 0; $i -lt $cols; $i++) {
            for ($y = 0; $y -lt ($H - 1); $y++) { Sp-Put ($i * 2) $y ' ' 'Black' }
            if (($i % 4) -eq 0) { Start-Sleep -Milliseconds 6 }
        }
        Clear-Host

        # ---- phase 2: logo with shine sweep ----
        $logo = @(
        ' _____  ____   _   _  _   _  _____  ___  _     ',
        '| ____||  _ \ | | | || | | ||_   _||_ _|| |    ',
        '|  _|  | | | || | | || | | |  | |   | | | |    ',
        '| |___ | |_| || |_| || |_| |  | |   | | | |___ ',
        '|_____||____/  \___/  \___/   |_|  |___||_____|'
        )
        $lw = $logo[0].Length
        $x0 = [int][math]::Max(0, ($W - $lw) / 2); $y0 = [int][math]::Max(1, ($H - 17) / 2)
        for ($sweep = -6; $sweep -le ($lw + 6); $sweep += 2) {
            for ($r = 0; $r -lt $logo.Count; $r++) {
                $line = $logo[$r]
                $a = [math]::Max(0, [math]::Min($lw, $sweep)); $b = [math]::Max(0, [math]::Min($lw, $sweep + 5))
                [Console]::SetCursorPosition($x0, $y0 + $r)
                [Console]::ForegroundColor = 'Cyan'; [Console]::Write($line.Substring(0, $a))
                [Console]::ForegroundColor = 'White'; [Console]::Write($line.Substring($a, $b - $a))
                [Console]::ForegroundColor = 'DarkCyan'; [Console]::Write($line.Substring($b))
            }
            if (Sp-Key) { return }
            Start-Sleep -Milliseconds 22
        }
        for ($r = 0; $r -lt $logo.Count; $r++) { Sp-Put $x0 ($y0 + $r) $logo[$r] 'Cyan' }

        $sub = "W I N D O W S   P E R F O R M A N C E   &   M A I N T E N A N C E   v$AppVersion"
        $sx = [int][math]::Max(0, ($W - $sub.Length) / 2)
        for ($i = 0; $i -lt $sub.Length; $i++) { Sp-Put ($sx + $i) ($y0 + 6) ([string]$sub[$i]) 'Gray'; Start-Sleep -Milliseconds 8 }
        $bar = ([string][char]0x2500) * [math]::Min($lw, $W - 4)
        Sp-Put $x0 ($y0 + 7) $bar 'DarkGray'

        # ---- phase 3: boot steps (real work) with spinner + progress bar ----
        $steps = @(
            @{ L = 'Verifying administrator session'; A = { 'elevated' } },
            @{ L = 'Loading WPF framework';          A = { Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms; 'ready' } },
            @{ L = 'Reading Windows build';          A = { $o = Get-CimInstance Win32_OperatingSystem; "$($o.Caption) (build $($o.BuildNumber))" } },
            @{ L = 'Detecting processor';            A = { $c = Get-CimInstance Win32_Processor | Select-Object -First 1; "$($c.Name.Trim()) - $($c.NumberOfCores)C/$($c.NumberOfLogicalProcessors)T" } },
            @{ L = 'Detecting graphics card';        A = { $g = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name }); if ($g.Count) { ($g | Select-Object -First 2 | ForEach-Object { $_.Name }) -join ' + ' } else { 'none found' } } },
            @{ L = 'Measuring memory';               A = { $m = Get-CimInstance Win32_ComputerSystem; "$([math]::Round($m.TotalPhysicalMemory / 1GB, 1)) GB RAM" } },
            @{ L = 'Scanning storage';               A = { $d = @(Get-CimInstance Win32_DiskDrive | Select-Object -First 2); ($d | ForEach-Object { "$($_.Model.Trim()) ($([math]::Round($_.Size / 1GB)) GB)" }) -join ', ' } },
            @{ L = 'Preparing backup and log folders'; A = { 'ok' } },
            @{ L = 'Arming tweak engine';            A = { 'ok' } }
        )
        $spin = '|', '/', '-', '\'
        $barW = [math]::Min(46, $W - 12); $barX = [int][math]::Max(0, ($W - $barW - 8) / 2); $barY = $y0 + 8 + $steps.Count + 2
        $rowY = $y0 + 9
        for ($s = 0; $s -lt $steps.Count; $s++) {
            $y = $rowY + $s
            for ($k = 0; $k -lt 7; $k++) {
                Sp-Put $x0 $y ("[ " + $spin[$k % 4] + " ] " + $steps[$s].L + "...") 'Yellow'
                Start-Sleep -Milliseconds 40
            }
            $res = ''
            try { $res = [string](& $steps[$s].A) } catch { $res = 'skipped' }
            $maxRes = $W - $x0 - $steps[$s].L.Length - 12
            if ($res.Length -gt $maxRes -and $maxRes -gt 4) { $res = $res.Substring(0, $maxRes - 3) + '...' }
            Sp-Put $x0 $y (' ' * ($W - $x0 - 2)) 'Black'
            Sp-Put $x0 $y '[ ' 'DarkGray'; Sp-Put ($x0 + 2) $y 'OK' 'Green'; Sp-Put ($x0 + 4) $y ' ] ' 'DarkGray'
            Sp-Put ($x0 + 7) $y $steps[$s].L 'Gray'
            Sp-Put ($x0 + 8 + $steps[$s].L.Length) $y $res 'DarkCyan'
            $pct = [int](100 * ($s + 1) / $steps.Count); $fill = [int]($barW * $pct / 100)
            Sp-Put $barX $barY ('[' + ($full * $fill) + ($shade * ($barW - $fill)) + '] ' + $pct.ToString().PadLeft(3) + '%') 'Cyan'
            if (Sp-Key) { return }
        }
        # finale: flash the bar and announce
        $msg = 'ALL SYSTEMS GO  -  LAUNCHING EDUUTIL'
        for ($f = 0; $f -lt 6; $f++) {
            $c = if ($f % 2) { 'Cyan' } else { 'White' }
            Sp-Put $barX $barY ('[' + ($full * $barW) + '] 100%') $c
            Sp-Put ([int][math]::Max(0, ($W - $msg.Length) / 2)) ($barY + 2) $msg $c
            Start-Sleep -Milliseconds 90
        }
        Start-Sleep -Milliseconds 250
    } catch { }
    finally {
        try { [Console]::ForegroundColor = $oldFg; [Console]::CursorVisible = $true; Clear-Host; $Host.UI.RawUI.WindowTitle = $oldTitle } catch { }
    }
}

Show-EduSplash
Write-Host "EduUtil v$AppVersion is running. Keep this window open - closing it closes EduUtil." -ForegroundColor Cyan
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

# ---------- extra helpers used by the v3 tweak packs ----------
$NOTIF  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings'
$EXPL   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
$POLW   = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows'
$WUPOL  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$SHBLK  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'
$CRASH  = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
$MEMMGR = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
$DESKI  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel'

# HKLM shell-verb helpers (context menu entries) - uses the .NET registry API so '*' keys work
function Set-ShellVerb([string]$SubKey, [string]$Label, [string]$Command, [string]$Icon = '') {
    $k = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($SubKey)
    try {
        $k.SetValue('', $Label)
        if ($Icon) { $k.SetValue('Icon', $Icon) }
        $c = $k.CreateSubKey('command')
        try { $c.SetValue('', $Command) } finally { $c.Close() }
    } finally { $k.Close() }
}
function Set-HklmDefault([string]$SubKey, [string]$Value) {
    $k = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($SubKey)
    try { $k.SetValue('', $Value) } finally { $k.Close() }
}
function Remove-HklmKey([string]$SubKey) {
    try { [Microsoft.Win32.Registry]::LocalMachine.DeleteSubKeyTree($SubKey, $false) } catch { }
}
function Test-HklmKey([string]$SubKey) {
    $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($SubKey)
    if ($k) { $k.Close(); return $true }
    return $false
}

# hosts-file telemetry block (clearly marked so it can be removed exactly)
$HostsFile  = Join-Path $env:WINDIR 'System32\drivers\etc\hosts'
$HostsBegin = '# >>> EduUtil telemetry block (begin)'
$HostsEnd   = '# <<< EduUtil telemetry block (end)'
$TelemetryHosts = @(
    'vortex.data.microsoft.com','vortex-win.data.microsoft.com','telemetry.microsoft.com','watson.telemetry.microsoft.com',
    'oca.telemetry.microsoft.com','sqm.telemetry.microsoft.com','telecommand.telemetry.microsoft.com','df.telemetry.microsoft.com',
    'reports.wes.df.telemetry.microsoft.com','services.wes.df.telemetry.microsoft.com','sqm.df.telemetry.microsoft.com',
    'telemetry.urs.microsoft.com','survey.watson.microsoft.com','watson.microsoft.com','statsfe2.ws.microsoft.com',
    'diagnostics.support.microsoft.com','oca.microsoft.com','kmwatsonc.events.data.microsoft.com','choice.microsoft.com',
    'redir.metaservices.microsoft.com','compatexchange.cloudapp.net'
)
function Get-HostsLines {
    if (Test-Path -LiteralPath $HostsFile) { return @(Get-Content -LiteralPath $HostsFile -ErrorAction Stop) }
    return @()
}
function Remove-HostsBlock {
    $lines = Get-HostsLines
    $out = New-Object System.Collections.Generic.List[string]
    $skip = $false
    foreach ($l in $lines) {
        if ($l -eq $HostsBegin) { $skip = $true; continue }
        if ($l -eq $HostsEnd)   { $skip = $false; continue }
        if (-not $skip) { $out.Add($l) }
    }
    Set-Content -LiteralPath $HostsFile -Value $out -Encoding ASCII -ErrorAction Stop
}
function Set-HostsBlock([string[]]$Domains) {
    Remove-HostsBlock
    $add = @($HostsBegin) + @($Domains | ForEach-Object { "0.0.0.0 $_" }) + @($HostsEnd)
    Add-Content -LiteralPath $HostsFile -Value $add -Encoding ASCII -ErrorAction Stop
    ipconfig /flushdns | Out-Null
}
function Test-HostsBlock { return (@(Get-HostsLines) -contains $HostsBegin) }

# NetBIOS over TCP/IP (per adapter) - 2 = disabled, 0 = default (DHCP decides)
$NetbtKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces'
function Set-NetbiosAll([int]$mode) {
    foreach ($k in (Get-ChildItem -LiteralPath $NetbtKey -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like 'Tcpip_*' })) {
        Set-Reg $k.PSPath 'NetbiosOptions' $mode 'DWord'
    }
}
function Test-NetbiosOff {
    $ks = @(Get-ChildItem -LiteralPath $NetbtKey -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like 'Tcpip_*' })
    if ($ks.Count -eq 0) { return $null }
    foreach ($k in $ks) { if ((Get-RegValue $k.PSPath 'NetbiosOptions') -ne 2) { return $false } }
    return $true
}

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
#  EVERYDAY TWEAKS - PACK 2 (v3)
# ======================================================================
$Tweaks += @(
    # ---------------- Privacy (more) ----------------
    @{ Name = 'Disable Customer Experience Improvement Program (CEIP)'; Category = 'Privacy'; Preset = @('Recommended','Privacy')
       Desc = 'Opts the PC out of the Windows CEIP usage-statistics program.'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows' 'CEIPEnable' 0) ) },

    @{ Name = 'Disable application compatibility telemetry'; Category = 'Privacy'; Preset = @('Recommended','Privacy')
       Desc = 'Turns off the inventory collector, Steps Recorder and application-impact telemetry.'
       Reg  = @( (RegV "$POLW\AppCompat" 'DisableInventory' 1), (RegV "$POLW\AppCompat" 'DisableUAR' 1), (RegV "$POLW\AppCompat" 'AITEnable' 0) ) },

    @{ Name = 'Disable handwriting data sharing'; Category = 'Privacy'; Preset = @('Privacy')
       Desc = 'Stops handwriting samples and handwriting error reports being sent to Microsoft.'
       Reg  = @( (RegV "$POLW\TabletPC" 'PreventHandwritingDataSharing' 1), (RegV "$POLW\HandwritingErrorReports" 'PreventHandwritingErrorReports' 1) ) },

    @{ Name = 'Disable Windows settings sync'; Category = 'Privacy'; Preset = @('Privacy')
       Desc = 'Themes, passwords, language and other settings are no longer synced through your Microsoft account.'
       Reg  = @( (RegV "$POLW\SettingSync" 'DisableSettingSync' 2), (RegV "$POLW\SettingSync" 'DisableSettingSyncUserOverride' 1) ) },

    @{ Name = 'Disable shared experiences / Nearby sharing'; Category = 'Privacy'; Preset = @('Privacy')
       Desc = 'Turns off "Continue on another device" and nearby sharing (Cross Device Platform).'
       Reg  = @( (RegV "$POLW\System" 'EnableCdp' 0),
                 (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CDP' 'CdpSessionUserAuthzPolicy' 0 'DWord' 1),
                 (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CDP' 'NearShareChannelUserAuthzPolicy' 0 'DWord' 1),
                 (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CDP' 'RomeSdkChannelUserAuthzPolicy' 0 'DWord' 1) ) },

    @{ Name = 'Disable Find My Device location reporting'; Category = 'Privacy'; Preset = @('Privacy')
       Desc = 'The PC stops reporting its location to Microsoft. You can no longer locate a lost or stolen device through your account.'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice' 'AllowFindMyDevice' 0) ) },

    @{ Name = 'Disable clipboard history'; Category = 'Privacy'; Preset = @('Privacy')
       Desc = 'Win+V clipboard history is turned off, so copied items are not kept in memory.'
       Reg  = @( (RegV "$POLW\System" 'AllowClipboardHistory' 0) ) },

    @{ Name = 'Disable Windows Insider / preview builds'; Category = 'Privacy'; Preset = @('Privacy')
       Desc = 'Blocks preview-build enrollment and hides the Insider page in Settings.'
       Reg  = @( (RegV "$POLW\PreviewBuilds" 'AllowBuildPreview' 0), (RegV 'HKLM:\SOFTWARE\Microsoft\WindowsSelfHost\UI\Visibility' 'HideInsiderPage' 1) ) },

    @{ Name = 'Defender: never send file samples to Microsoft'; Category = 'Privacy'; Preset = @('Privacy')
       Desc = 'Defender keeps protecting you but no longer uploads suspicious files for analysis (cloud lookups of hashes still work).'
       Apply = { Set-MpPreference -SubmitSamplesConsent NeverSend -ErrorAction Stop }
       Undo  = { Set-MpPreference -SubmitSamplesConsent SendSafeSamples -ErrorAction SilentlyContinue }
       Test  = { (Get-MpPreference -ErrorAction Stop).SubmitSamplesConsent -eq 2 } },

    @{ Name = 'Disable SmartScreen web check for Store apps'; Category = 'Privacy'; Preset = @('Privacy')
       Desc = 'Store apps stop sending the web addresses they load to SmartScreen.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AppHost' 'EnableWebContentEvaluation' 0 'DWord' 1) ) },

    @{ Name = 'Chrome: stop metrics, feedback and background mode'; Category = 'Privacy'; Preset = @('Privacy')
       Desc = 'Applies Chrome policies: no usage statistics, no feedback prompts, no running in the background after you close it.'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Policies\Google\Chrome' 'MetricsReportingEnabled' 0), (RegV 'HKLM:\SOFTWARE\Policies\Google\Chrome' 'UrlKeyedAnonymizedDataCollectionEnabled' 0),
                 (RegV 'HKLM:\SOFTWARE\Policies\Google\Chrome' 'UserFeedbackAllowed' 0), (RegV 'HKLM:\SOFTWARE\Policies\Google\Chrome' 'BackgroundModeEnabled' 0),
                 (RegV 'HKLM:\SOFTWARE\Policies\Google\Chrome' 'SafeBrowsingExtendedReportingEnabled' 0) ) },

    @{ Name = 'Firefox: disable telemetry, studies and Pocket'; Category = 'Privacy'; Preset = @('Privacy')
       Desc = 'Applies Firefox enterprise policies that switch off telemetry, Shield studies and Pocket.'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox' 'DisableTelemetry' 1), (RegV 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox' 'DisableFirefoxStudies' 1),
                 (RegV 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox' 'DisablePocket' 1) ) },

    @{ Name = 'Brave: disable Rewards, Wallet, VPN and AI chat'; Category = 'Privacy'; Preset = @('Privacy')
       Desc = 'Hides the promotional crypto/VPN/AI features in Brave via policy.'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave' 'BraveRewardsDisabled' 1), (RegV 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave' 'BraveWalletDisabled' 1),
                 (RegV 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave' 'BraveVPNDisabled' 1), (RegV 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave' 'BraveAIChatEnabled' 0) ) },

    @{ Name = 'Disable Click to Do / AI shortcuts (Windows 11 24H2+)'; Category = 'Privacy'; Preset = @('Privacy')
       Desc = 'Turns off the Click to Do screen-analysis overlay. No effect on older builds.'
       Reg  = @( (RegV "$POLW\WindowsAI" 'DisableClickToDo' 1) ) },

    # ---------------- Ads & suggestions (more) ----------------
    @{ Name = 'Disable cloud-optimized content'; Category = 'Ads & suggestions'; Preset = @('Recommended','Privacy')
       Desc = 'Stops Windows pulling promotional and "optimized" content from the cloud into Start and Settings.'
       Reg  = @( (RegV "$POLW\CloudContent" 'DisableCloudOptimizedContent' 1), (RegV "$POLW\CloudContent" 'DisableConsumerAccountStateContent' 1) ) },

    @{ Name = 'Disable Windows Spotlight features'; Category = 'Ads & suggestions'; Preset = @('Recommended')
       Desc = 'Turns off Spotlight on the desktop, lock screen and Settings, third-party suggestions and the "Learn about this picture" desktop icon.'
       Reg  = @( (RegV 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsSpotlightFeatures' 1),
                 (RegV 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsSpotlightOnActionCenter' 1),
                 (RegV 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsSpotlightOnSettings' 1),
                 (RegV 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsSpotlightWindowsWelcomeExperience' 1),
                 (RegV 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' 'DisableThirdPartySuggestions' 1),
                 (RegV 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' 'DisableSpotlightCollectionOnDesktop' 1),
                 (RegV $DESKI '{2cc5ca98-6485-489a-920e-b3e88a6ccce3}' 1) ); Explorer = $true },

    @{ Name = 'Edge: clean new-tab page, no Collections, send Do Not Track'; Category = 'Ads & suggestions'; Preset = @('Privacy')
       Desc = 'Removes the MSN news feed from the new-tab page and the Collections feature, and sends the Do Not Track header.'
       Reg  = @( (RegV $EDGE 'NewTabPageContentEnabled' 0), (RegV $EDGE 'EdgeCollectionsEnabled' 0), (RegV $EDGE 'ConfigureDoNotTrack' 1) ) },

    @{ Name = 'Hide "Recently added" apps in Start'; Category = 'Ads & suggestions'; Preset = @()
       Desc = 'Start stops listing newly installed apps at the top of the app list.'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'HideRecentlyAddedApps' 1) ); Explorer = $true },

    # ---------------- Explorer & taskbar (more) ----------------
    @{ Name = 'Show This PC, User Files, Network and Control Panel on desktop'; Category = 'Explorer & taskbar'; Preset = @()
       Desc = 'Adds the classic desktop icons back.'
       Reg  = @( (RegV $DESKI '{20D04FE0-3AEA-1069-A2D8-08002B30309D}' 0 'DWord' 1), (RegV $DESKI '{59031a47-3f72-44a7-89c5-5595fe6b30ee}' 0 'DWord' 1),
                 (RegV $DESKI '{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}' 0 'DWord' 1), (RegV $DESKI '{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}' 0 'DWord' 1) ); Explorer = $true },

    @{ Name = 'Never combine taskbar buttons'; Category = 'Explorer & taskbar'; Preset = @()
       Desc = 'Every window gets its own taskbar button with a label (also on secondary monitors).'
       Reg  = @( (RegV $ADV 'TaskbarGlomLevel' 2 'DWord' 0), (RegV $ADV 'MMTaskbarGlomLevel' 2 'DWord' 0) ); Explorer = $true },

    @{ Name = 'Show all tray icons (Windows 10)'; Category = 'Explorer & taskbar'; Preset = @()
       Desc = 'Stops Windows hiding tray icons behind the arrow.'
       Reg  = @( (RegV $EXPL 'EnableAutoTray' 0 'DWord' 1) ); Explorer = $true },

    @{ Name = 'Compact spacing in File Explorer (Windows 11)'; Category = 'Explorer & taskbar'; Preset = @()
       Desc = 'Reduces the padding between items like Windows 10 did, fitting more files on screen.'
       Reg  = @( (RegV $ADV 'UseCompactMode' 1 'DWord' 0) ); Explorer = $true },

    @{ Name = 'Disable Snap layouts flyout (Windows 11)'; Category = 'Explorer & taskbar'; Preset = @()
       Desc = 'Removes the layout picker that pops up when hovering the maximize button and the snap bar when dragging.'
       Reg  = @( (RegV $ADV 'EnableSnapAssistFlyout' 0 'DWord' 1), (RegV $ADV 'EnableSnapBar' 0 'DWord' 1) ); Explorer = $true },

    @{ Name = 'Start menu: show more pins (Windows 11)'; Category = 'Explorer & taskbar'; Preset = @()
       Desc = 'Gives pinned apps more room and shrinks the Recommended area.'
       Reg  = @( (RegV $ADV 'Start_Layout' 1 'DWord' 0) ); Explorer = $true },

    @{ Name = 'Hide OneDrive from the Explorer sidebar'; Category = 'Explorer & taskbar'; Preset = @()
       Desc = 'Removes the OneDrive entry from the navigation pane (files and sync are not touched).'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' 'System.IsPinnedToNameSpaceTree' 0 'DWord' 1),
                 (RegV 'HKLM:\SOFTWARE\Classes\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' 'System.IsPinnedToNameSpaceTree' 0 'DWord' 1) ); Explorer = $true },

    @{ Name = 'Show item check boxes in Explorer'; Category = 'Explorer & taskbar'; Preset = @()
       Desc = 'Adds a tick box to every file so you can multi-select with the mouse only.'
       Reg  = @( (RegV $ADV 'AutoCheckSelect' 1 'DWord' 0) ); Explorer = $true },

    @{ Name = 'Navigation pane: expand to current folder'; Category = 'Explorer & taskbar'; Preset = @()
       Desc = 'The sidebar follows the folder you are in and always shows every drive and folder.'
       Reg  = @( (RegV $ADV 'NavPaneExpandToCurrentFolder' 1 'DWord' 0), (RegV $ADV 'NavPaneShowAllFolders' 1 'DWord' 0) ); Explorer = $true },

    @{ Name = 'Show accent color on title bars and borders'; Category = 'Explorer & taskbar'; Preset = @()
       Desc = 'Window title bars use your accent color instead of plain white/black.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\Windows\DWM' 'ColorPrevalence' 1 'DWord' 0) ) },

    # ---------------- Sign-in & lock screen ----------------
    @{ Name = 'Skip the lock screen'; Category = 'Sign-in & lock screen'; Preset = @()
       Desc = 'Goes straight to the password / PIN box. Works on Pro, Enterprise and Education editions.'
       Reg  = @( (RegV "$POLW\Personalization" 'NoLockScreen' 1) ) },

    @{ Name = 'Disable sign-in screen blur'; Category = 'Sign-in & lock screen'; Preset = @('Recommended')
       Desc = 'Shows the sign-in background sharp instead of acrylic-blurred (saves a little GPU work).'
       Reg  = @( (RegV "$POLW\System" 'DisableAcrylicBackgroundOnLogon' 1) ) },

    @{ Name = 'Disable lock-screen camera'; Category = 'Sign-in & lock screen'; Preset = @()
       Desc = 'Removes the swipe-down camera shortcut from the lock screen.'
       Reg  = @( (RegV "$POLW\Personalization" 'NoLockScreenCamera' 1) ) },

    @{ Name = 'Hide notifications on the lock screen'; Category = 'Sign-in & lock screen'; Preset = @('Privacy')
       Desc = 'Toasts no longer appear above the lock screen, so nobody walking past can read them.'
       Reg  = @( (RegV $NOTIF 'NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK' 0 'DWord' 1), (RegV $NOTIF 'NOC_GLOBAL_SETTING_ALLOW_CRITICAL_TOASTS_ABOVE_LOCK' 0 'DWord' 1) ) },

    # ---------------- Notifications & sound ----------------
    @{ Name = 'Disable the Windows startup sound'; Category = 'Notifications & sound'; Preset = @()
       Desc = 'Silences the boot chime.'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation' 'DisableStartupSound' 1 'DWord' 0),
                 (RegV 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'DisableStartupSound' 1) ) },

    @{ Name = 'Disable notification sounds'; Category = 'Notifications & sound'; Preset = @()
       Desc = 'Toast notifications still appear but stop making a sound.'
       Reg  = @( (RegV $NOTIF 'NOC_GLOBAL_SETTING_ALLOW_NOTIFICATION_SOUND' 0 'DWord' 1) ) },

    @{ Name = 'Stop Windows lowering volume during calls'; Category = 'Notifications & sound'; Preset = @('Gaming')
       Desc = 'Sets communications activity to "Do nothing" so voice chat does not duck your game audio.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\Multimedia\Audio' 'UserDuckingPreference' 3 'DWord' 1) ) },

    @{ Name = 'Turn off all toast notifications and Action Center'; Category = 'Notifications & sound'; Preset = @()
       Desc = 'No pop-up notifications from any app and the notification center is disabled.'
       Reg  = @( (RegV 'HKCU:\Software\Policies\Microsoft\Windows\CurrentVersion\PushNotifications' 'NoToastApplicationNotification' 1),
                 (RegV 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableNotificationCenter' 1) ); Explorer = $true },

    @{ Name = 'Silence non-critical Windows Security notifications'; Category = 'Notifications & sound'; Preset = @('Recommended')
       Desc = 'Hides the summary and recommendation pop-ups from Windows Security. Threat alerts still show.'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications' 'DisableEnhancedNotifications' 1) ) },

    # ---------------- Gaming & input (more) ----------------
    @{ Name = 'Disable touch and pen visual feedback'; Category = 'Gaming & input'; Preset = @('Gaming')
       Desc = 'Removes the circle/ripple drawn under touches and pen taps.'
       Reg  = @( (RegV 'HKCU:\Control Panel\Cursors' 'ContactVisualization' 0 'DWord' 1), (RegV 'HKCU:\Control Panel\Cursors' 'GestureVisualization' 0 'DWord' 31) ) },

    @{ Name = 'Disable accessibility hotkeys (High Contrast, Narrator)'; Category = 'Gaming & input'; Preset = @('Gaming')
       Desc = 'Stops Left Alt + Left Shift + Print Screen and Win+Ctrl+Enter from popping up in the middle of a game.'
       Reg  = @( (RegV 'HKCU:\Control Panel\Accessibility\HighContrast' 'Flags' '4194' 'String' '126'),
                 (RegV 'HKCU:\Software\Microsoft\Narrator\NoRoam' 'WinEnterLaunchEnabled' 0 'DWord' 1) ) },

    @{ Name = 'Faster hover previews'; Category = 'Gaming & input'; Preset = @()
       Desc = 'Taskbar thumbnails and tooltips appear after 10 ms instead of 400 ms.'
       Reg  = @( (RegV 'HKCU:\Control Panel\Mouse' 'MouseHoverTime' '10' 'String' '400') ) },

    # ---------------- Quality of life ----------------
    @{ Name = 'Turn NumLock on at startup'; Category = 'Quality of life'; Preset = @()
       Desc = 'NumLock is on at the sign-in screen and after you sign in.'
       Reg  = @( (RegV 'HKCU:\Control Panel\Keyboard' 'InitialKeyboardIndicators' '2' 'String' '0'),
                 (RegV 'Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard' 'InitialKeyboardIndicators' '2' 'String' '0') ) },

    @{ Name = 'Remove "- Shortcut" from new shortcut names'; Category = 'Quality of life'; Preset = @()
       Desc = 'New shortcuts are named like the original instead of "App - Shortcut".'
       Reg  = @( (RegV $EXPL 'link' ([byte[]](0,0,0,0)) 'Binary') ) },

    # ---------------- Windows Update ----------------
    @{ Name = 'Never auto-restart while you are signed in'; Category = 'Windows Update'; Preset = @('Recommended','Gaming')
       Desc = 'Windows installs updates but waits for you to restart instead of rebooting in the middle of your work or game.'
       Reg  = @( (RegV "$WUPOL\AU" 'NoAutoRebootWithLoggedOnUsers' 1) ) },

    @{ Name = 'Delay feature updates by one year'; Category = 'Windows Update'; Preset = @()
       Desc = 'Big Windows version upgrades wait 365 days (Pro/Enterprise/Education). Security patches still install.'
       Reg  = @( (RegV $WUPOL 'DeferFeatureUpdates' 1), (RegV $WUPOL 'DeferFeatureUpdatesPeriodInDays' 365) ) },

    @{ Name = 'Delay monthly quality updates by 7 days'; Category = 'Windows Update'; Preset = @()
       Desc = 'Gives Microsoft a week to pull a bad patch before it reaches you.'
       Reg  = @( (RegV $WUPOL 'DeferQualityUpdates' 1), (RegV $WUPOL 'DeferQualityUpdatesPeriodInDays' 7) ) },

    @{ Name = 'Stop Malicious Software Removal Tool via Windows Update'; Category = 'Windows Update'; Preset = @()
       Desc = 'Skips the monthly MSRT download. Defender still scans normally.'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\MRT' 'DontOfferThroughWUAU' 1) ) },

    # ---------------- Developer (more) ----------------
    @{ Name = 'Do not auto-restart after a crash (BSOD)'; Category = 'Developer'; Preset = @('Developer')
       Desc = 'The blue screen stays on screen so you can read the stop code.'
       Reg  = @( (RegV $CRASH 'AutoReboot' 0 'DWord' 1) ) },

    @{ Name = 'Show technical details on the blue screen'; Category = 'Developer'; Preset = @('Developer')
       Desc = 'Adds the stop code parameters and the failing driver name to the BSOD.'
       Reg  = @( (RegV $CRASH 'DisplayParameters' 1) ) },

    @{ Name = 'Enable ANSI colors in the classic console'; Category = 'Developer'; Preset = @('Developer')
       Desc = 'Turns on virtual-terminal sequences for cmd and PowerShell windows (colored output from git, npm, etc.).'
       Reg  = @( (RegV 'HKCU:\Console' 'VirtualTerminalLevel' 1 'DWord' 0) ) },

    # ---------------- Security (more) ----------------
    @{ Name = 'Disable PowerShell 2.0 engine'; Category = 'Security'; Preset = @('Recommended')
       Desc = 'Removes the legacy engine that attackers use to dodge logging and AMSI. Nothing modern needs it.'
       Apply = { Disable-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2Root -NoRestart -ErrorAction Stop | Out-Null }
       Undo  = { Enable-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2Root -NoRestart -All -ErrorAction SilentlyContinue | Out-Null }
       Test  = { $f = Get-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2Root -ErrorAction Stop; [string]$f.State -ne 'Enabled' } },

    @{ Name = 'Defender: enable network protection'; Category = 'Security'; Preset = @('Recommended')
       Desc = 'Blocks connections to known malicious and phishing hosts from any app.'
       Apply = { Set-MpPreference -EnableNetworkProtection Enabled -ErrorAction Stop }
       Undo  = { Set-MpPreference -EnableNetworkProtection Disabled -ErrorAction SilentlyContinue }
       Test  = { (Get-MpPreference -ErrorAction Stop).EnableNetworkProtection -eq 1 } },

    @{ Name = 'Defender: scan removable drives and archives'; Category = 'Security'; Preset = @()
       Desc = 'Full scans also check USB sticks and compressed files.'
       Apply = { Set-MpPreference -DisableRemovableDriveScanning $false -DisableArchiveScanning $false -ErrorAction Stop }
       Undo  = { Set-MpPreference -DisableRemovableDriveScanning $true -ErrorAction SilentlyContinue }
       Test  = { -not (Get-MpPreference -ErrorAction Stop).DisableRemovableDriveScanning } },

    @{ Name = 'Defender: high cloud-block level'; Category = 'Security'; Preset = @()
       Desc = 'Defender blocks unknown files more aggressively while it waits for a cloud verdict. Occasional false positives.'
       Apply = { Set-MpPreference -CloudBlockLevel High -ErrorAction Stop }
       Undo  = { Set-MpPreference -CloudBlockLevel Default -ErrorAction SilentlyContinue }
       Test  = { (Get-MpPreference -ErrorAction Stop).CloudBlockLevel -ge 2 } },

    @{ Name = 'Block Office macros from the internet'; Category = 'Security'; Preset = @('Recommended')
       Desc = 'Word, Excel and PowerPoint refuse to run macros in files downloaded from the web or email. Only matters if Office is installed.'
       Reg  = @( (RegV 'HKCU:\Software\Policies\Microsoft\office\16.0\word\security' 'blockcontentexecutionfrominternet' 1),
                 (RegV 'HKCU:\Software\Policies\Microsoft\office\16.0\excel\security' 'blockcontentexecutionfrominternet' 1),
                 (RegV 'HKCU:\Software\Policies\Microsoft\office\16.0\powerpoint\security' 'blockcontentexecutionfrominternet' 1) ) },

    # ---------------- Performance (more) ----------------
    @{ Name = 'Merge service host processes (fewer svchost.exe)'; Category = 'Performance'; Preset = @()
       Desc = 'Groups services into fewer svchost processes. Cleaner Task Manager; only meaningful with 8 GB RAM or more. Restart required.'
       Reg  = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control' 'SvcHostSplitThresholdInKB' ([int][math]::Min(2147483647, [math]::Max(3670016, [math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1KB)))) 'DWord' 3670016) ); Reboot = $true },

    # ---------------- Context menu ----------------
    @{ Name = 'Add "Take ownership" to the right-click menu'; Category = 'Context menu'; Preset = @()
       Desc = 'Files and folders get a Take ownership entry (takeown + grant Administrators full control). Handy for stubborn folders.'
       Apply = { Set-ShellVerb 'SOFTWARE\Classes\*\shell\EduTakeOwnership' 'Take ownership' 'cmd.exe /c takeown /f "%1" && icacls "%1" /grant *S-1-5-32-544:F /c /l & pause' 'imageres.dll,-5314'
                 Set-ShellVerb 'SOFTWARE\Classes\Directory\shell\EduTakeOwnership' 'Take ownership' 'cmd.exe /c takeown /f "%1" /r /d y && icacls "%1" /grant *S-1-5-32-544:F /t /c /l & pause' 'imageres.dll,-5314' }
       Undo  = { Remove-HklmKey 'SOFTWARE\Classes\*\shell\EduTakeOwnership'; Remove-HklmKey 'SOFTWARE\Classes\Directory\shell\EduTakeOwnership' }
       Test  = { Test-HklmKey 'SOFTWARE\Classes\Directory\shell\EduTakeOwnership' } },

    @{ Name = 'Add "Open command prompt here" to folder background menu'; Category = 'Context menu'; Preset = @('Developer')
       Desc = 'Right-click empty space in any folder to open cmd in that folder.'
       Apply = { Set-ShellVerb 'SOFTWARE\Classes\Directory\Background\shell\EduCmdHere' 'Open command prompt here' 'cmd.exe /s /k pushd "%V"' 'cmd.exe' }
       Undo  = { Remove-HklmKey 'SOFTWARE\Classes\Directory\Background\shell\EduCmdHere' }
       Test  = { Test-HklmKey 'SOFTWARE\Classes\Directory\Background\shell\EduCmdHere' } },

    @{ Name = 'Add "Open PowerShell window here" to folder background menu'; Category = 'Context menu'; Preset = @('Developer')
       Desc = 'Right-click empty space in any folder to open PowerShell in that folder.'
       Apply = { Set-ShellVerb 'SOFTWARE\Classes\Directory\Background\shell\EduPsHere' 'Open PowerShell window here' "powershell.exe -NoExit -Command `"Set-Location -LiteralPath '%V'`"" 'powershell.exe' }
       Undo  = { Remove-HklmKey 'SOFTWARE\Classes\Directory\Background\shell\EduPsHere' }
       Test  = { Test-HklmKey 'SOFTWARE\Classes\Directory\Background\shell\EduPsHere' } },

    @{ Name = 'Add "Kill not responding tasks" to the desktop menu'; Category = 'Context menu'; Preset = @()
       Desc = 'One click on the desktop closes every frozen app.'
       Apply = { Set-ShellVerb 'SOFTWARE\Classes\DesktopBackground\Shell\EduKillHung' 'Kill not responding tasks' 'cmd.exe /c taskkill.exe /f /fi "status eq not responding"' 'taskmgr.exe' }
       Undo  = { Remove-HklmKey 'SOFTWARE\Classes\DesktopBackground\Shell\EduKillHung' }
       Test  = { Test-HklmKey 'SOFTWARE\Classes\DesktopBackground\Shell\EduKillHung' } },

    @{ Name = 'Add "Restart Explorer" to the desktop menu'; Category = 'Context menu'; Preset = @()
       Desc = 'Fixes a frozen taskbar or desktop with one click.'
       Apply = { Set-ShellVerb 'SOFTWARE\Classes\DesktopBackground\Shell\EduRestartExplorer' 'Restart Explorer' 'cmd.exe /c taskkill.exe /f /im explorer.exe & start explorer.exe' 'explorer.exe' }
       Undo  = { Remove-HklmKey 'SOFTWARE\Classes\DesktopBackground\Shell\EduRestartExplorer' }
       Test  = { Test-HklmKey 'SOFTWARE\Classes\DesktopBackground\Shell\EduRestartExplorer' } },

    @{ Name = 'Add "Copy to folder" and "Move to folder" to the right-click menu'; Category = 'Context menu'; Preset = @()
       Desc = 'Classic shell entries that open a folder picker to copy or move the selected items.'
       Apply = { Set-HklmDefault 'SOFTWARE\Classes\AllFilesystemObjects\shellex\ContextMenuHandlers\Copy To' '{C2FBB630-2971-11D1-A18C-00C04FD75D13}'
                 Set-HklmDefault 'SOFTWARE\Classes\AllFilesystemObjects\shellex\ContextMenuHandlers\Move To' '{C2FBB631-2971-11D1-A18C-00C04FD75D13}' }
       Undo  = { Remove-HklmKey 'SOFTWARE\Classes\AllFilesystemObjects\shellex\ContextMenuHandlers\Copy To'; Remove-HklmKey 'SOFTWARE\Classes\AllFilesystemObjects\shellex\ContextMenuHandlers\Move To' }
       Test  = { Test-HklmKey 'SOFTWARE\Classes\AllFilesystemObjects\shellex\ContextMenuHandlers\Copy To' } },

    @{ Name = 'Add "Open with Notepad" for every file type'; Category = 'Context menu'; Preset = @()
       Desc = 'Quickly view any file as plain text.'
       Apply = { Set-ShellVerb 'SOFTWARE\Classes\*\shell\EduOpenNotepad' 'Open with Notepad' 'notepad.exe "%1"' 'notepad.exe' }
       Undo  = { Remove-HklmKey 'SOFTWARE\Classes\*\shell\EduOpenNotepad' }
       Test  = { Test-HklmKey 'SOFTWARE\Classes\*\shell\EduOpenNotepad' } },

    @{ Name = 'Declutter right-click menu (Cast to, Give access, Include in library, Pin to Start)'; Category = 'Context menu'; Preset = @()
       Desc = 'Blocks four rarely used shell extensions from the classic context menu.'
       Reg  = @( (RegV $SHBLK '{7AD84985-87B4-4a16-BE58-8B72A5B390F7}' '' 'String'), (RegV $SHBLK '{f81e9010-6ea4-11ce-a7ff-00aa003ca9f6}' '' 'String'),
                 (RegV $SHBLK '{3dad6c5d-2167-4cae-9914-f99e41c12cfa}' '' 'String'), (RegV $SHBLK '{470C0EBD-5D73-4d58-9CED-E91E22E23282}' '' 'String') ); Explorer = $true },

    @{ Name = 'Remove "Restore previous versions" from the right-click menu'; Category = 'Context menu'; Preset = @()
       Desc = 'Hides the shadow-copy entry. Restore points and File History are not affected.'
       Reg  = @( (RegV $SHBLK '{596AB062-B4D2-4215-9F74-E9109B0A8153}' '' 'String') ); Explorer = $true }
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


# ======================================================================
#  ADVANCED CONTROLS - PACK 2 (v3)   (Risk: Low / Medium / High)
# ======================================================================
$ExtraTelemetryTasks = @(
    '\Microsoft\Windows\Application Experience\MareBackup',
    '\Microsoft\Windows\Application Experience\PcaPatchDbTask',
    '\Microsoft\Windows\Application Experience\AitAgent',
    '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask',
    '\Microsoft\Windows\Customer Experience Improvement Program\BthSQM',
    '\Microsoft\Windows\Customer Experience Improvement Program\HypervisorFlightingTask',
    '\Microsoft\Windows\NetTrace\GatherNetworkInfo',
    '\Microsoft\Windows\Device Information\Device',
    '\Microsoft\Windows\Device Information\Device User',
    '\Microsoft\Windows\DiskFootprint\Diagnostics',
    '\Microsoft\Windows\Flighting\FeatureConfig\ReconcileFeatures',
    '\Microsoft\Windows\Flighting\OneSettings\RefreshCache',
    '\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem'
)
$OfficeTelemetryTasks = @(
    '\Microsoft\Office\OfficeTelemetryAgentFallBack', '\Microsoft\Office\OfficeTelemetryAgentFallBack2016',
    '\Microsoft\Office\OfficeTelemetryAgentLogOn', '\Microsoft\Office\OfficeTelemetryAgentLogOn2016'
)
$SUB_VIDEO = '7516b95f-f776-4464-8c53-06167f40cc99'
$SUB_SLEEP = '238c9fa8-0aad-41ed-83f4-97be242c8f20'
$SUB_USB   = '2a737441-1930-4402-8d77-b2bebba308a3'
$PFX       = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'

$Extreme += @(
    # ---------------- Services (more) ----------------
    @{ Name = 'Disable Remote Desktop services'; Risk = 'Medium'; Category = 'Services'
       Desc = 'Stops the PC from being a Remote Desktop host and closes that attack surface. Outgoing RDP connections still work. Do not use while connected through Remote Desktop.'
       Svc = @('TermService','UmRdpService','SessionEnv'); SvcDefault = 'demand' },

    @{ Name = 'Disable Windows Biometric Service'; Risk = 'Medium'; Category = 'Services'
       Desc = 'Breaks fingerprint and face sign-in (Windows Hello biometrics). PIN and password still work.'
       Svc = @('WbioSrvc'); SvcDefault = 'demand' },

    @{ Name = 'Disable touch keyboard and handwriting service'; Risk = 'Low'; Category = 'Services'
       Desc = 'Desktop PCs only. Breaks the on-screen keyboard, pen input and emoji panel typing on touch devices.'
       Svc = @('TabletInputService'); SvcDefault = 'demand' },

    @{ Name = 'Disable Smart Card services'; Risk = 'Low'; Category = 'Services'
       Desc = 'Only needed for smart-card readers (corporate / government sign-in).'
       Svc = @('SCardSvr','ScDeviceEnum','SCPolicySvc'); SvcDefault = 'demand' },

    @{ Name = 'Disable Connected Devices Platform (CDP)'; Risk = 'Medium'; Category = 'Services'
       Desc = 'Breaks Nearby sharing, Timeline-style features and some Phone Link pairing.'
       Svc = @('CDPSvc'); SvcDefault = 'delayed-auto' },

    @{ Name = 'Disable sensor services'; Risk = 'Medium'; Category = 'Services'
       Desc = 'Desktops only. Laptops and tablets lose auto-brightness, rotation and some location features.'
       Svc = @('SensrSvc','SensorService','SensorDataService'); SvcDefault = 'demand' },

    @{ Name = 'Disable Windows Image Acquisition (scanners and cameras)'; Risk = 'Low'; Category = 'Services'
       Desc = 'Scanners and some webcams stop importing images through Windows. Normal webcam use in apps is unaffected.'
       Svc = @('stisvc'); SvcDefault = 'demand' },

    @{ Name = 'Disable Secondary Logon'; Risk = 'Low'; Category = 'Services'
       Desc = 'Breaks "Run as a different user" from the right-click menu.'
       Svc = @('seclogon'); SvcDefault = 'demand' },

    @{ Name = 'Disable Windows Remote Management and Remote Registry'; Risk = 'Low'; Category = 'Services'
       Desc = 'Closes remote PowerShell / WinRM and remote registry access. Only IT admins need them.'
       Svc = @('WinRM','RemoteRegistry'); SvcDefault = 'demand' },

    @{ Name = 'Disable Offline Files and legacy network helpers'; Risk = 'Low'; Category = 'Services'
       Desc = 'Turns off Offline Files, the NetBIOS helper and AllJoyn router. Rarely used at home.'
       Svc = @('CscService','lmhosts','AJRouter'); SvcDefault = 'demand' },

    @{ Name = 'Disable Telephony and SMS Router services'; Risk = 'Low'; Category = 'Services'
       Desc = 'Unused on desktops without modems or cellular hardware.'
       Svc = @('TapiSrv','SmsRouter'); SvcDefault = 'demand' },

    @{ Name = 'Disable Diagnostic Policy / WDI services'; Risk = 'Medium'; Category = 'Services'
       Desc = 'Stops the built-in troubleshooters and diagnostic data processing. "Troubleshoot problems" will not work.'
       Svc = @('DPS','WdiServiceHost','WdiSystemHost'); SvcDefault = 'auto' },

    @{ Name = 'Disable NVIDIA telemetry container'; Risk = 'Low'; Category = 'Services'
       Desc = 'Stops the NVIDIA usage-reporting service. GeForce drivers and control panel keep working.'
       Svc = @('NvTelemetryContainer'); SvcDefault = 'auto' },

    @{ Name = 'Disable block-level backup engine'; Risk = 'Low'; Category = 'Services'
       Desc = 'Only used by the old Windows Backup (Backup and Restore) feature.'
       Svc = @('wbengine'); SvcDefault = 'demand' },

    @{ Name = 'Disable third-party updater services (Google, Adobe, Edge, Firefox)'; Risk = 'Medium'; Category = 'Services'
       Desc = 'Browsers and Adobe stop updating themselves in the background. Update them manually - outdated browsers are a security risk.'
       Svc = @('gupdate','gupdatem','AdobeARMservice','edgeupdate','edgeupdatem','MozillaMaintenance'); SvcDefault = 'auto' },

    @{ Name = 'Disable automatic maintenance'; Risk = 'Medium'; Category = 'Services'
       Desc = 'Stops the nightly maintenance window (idle defrag/TRIM, scans, diagnostics). Run Maintenance tasks manually from time to time.'
       Reg = @( (RegV 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance' 'MaintenanceDisabled' 1) ) },

    # ---------------- Telemetry & hosts ----------------
    @{ Name = 'Block Microsoft telemetry domains (hosts file)'; Risk = 'Medium'; Category = 'Telemetry & hosts'
       Desc = 'Adds a clearly marked block to the hosts file that sends known telemetry hosts to 0.0.0.0. Windows Update and Store are not touched. Some antivirus tools warn when hosts changes.'
       Apply = { Set-HostsBlock $TelemetryHosts }
       Undo  = { Remove-HostsBlock; ipconfig /flushdns | Out-Null }
       Test  = { Test-HostsBlock } },

    @{ Name = 'Disable diagnostic tracking auto-loggers'; Risk = 'Low'; Category = 'Telemetry & hosts'
       Desc = 'Stops the DiagTrack and SQM event-trace sessions from starting at boot.'
       Reg = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\AutoLogger-Diagtrack-Listener' 'Start' 0 'DWord' 1),
                (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\SQMLogger' 'Start' 0 'DWord' 1) ); Reboot = $true },

    @{ Name = 'Disable extra diagnostic and flighting tasks'; Risk = 'Low'; Category = 'Telemetry & hosts'
       Desc = 'Turns off 13 more scheduled tasks: app-experience backup, CEIP kernel/Bluetooth, device info, disk footprint, flighting and power diagnostics.'
       Tasks = $ExtraTelemetryTasks },

    @{ Name = 'Disable Microsoft Office telemetry agent tasks'; Risk = 'Low'; Category = 'Telemetry & hosts'
       Desc = 'Turns off the Office Telemetry Agent scheduled tasks. Only matters if Office is installed.'
       Tasks = $OfficeTelemetryTasks },

    @{ Name = 'Enable automatic DNS over HTTPS (Windows 11)'; Risk = 'Low'; Category = 'Telemetry & hosts'
       Desc = 'Windows upgrades to encrypted DNS automatically when your DNS server supports it (Cloudflare, Google, Quad9 all do).'
       Reg = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' 'EnableAutoDoh' 2) ) },

    # ---------------- CPU & power (more) ----------------
    @{ Name = 'Energy performance preference: maximum performance (AC)'; Risk = 'Low'; Category = 'CPU & power'
       Desc = 'Tells the CPU to favor speed over efficiency on supported processors (Intel Speed Shift / AMD CPPC).'
       Pwr = @( (PwrV $SUB_PROC '36687f9e-e3a5-4dbf-b1dc-15eb381c6863' 0 50) ) },

    @{ Name = 'Disable CPU idle states / C-states (AC)'; Risk = 'Medium'; Category = 'CPU & power'
       Desc = 'Cores never enter deep idle: lowest wake-up latency but much higher idle power and heat. Desktops with good cooling only.'
       Pwr = @( (PwrV $SUB_PROC '5d76a2ca-e8c0-402f-a133-2158492d58ad' 1 0) ) },

    @{ Name = 'Never turn off the display (AC power)'; Risk = 'Low'; Category = 'CPU & power'
       Desc = 'The screen stays on while plugged in. Good for dashboards and long sessions; not for OLED screens.'
       Pwr = @( (PwrV $SUB_VIDEO '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e' 0 600) ) },

    @{ Name = 'Never put the PC to sleep (AC power)'; Risk = 'Low'; Category = 'CPU & power'
       Desc = 'Stops automatic sleep while plugged in. Downloads, servers and renders are never interrupted.'
       Pwr = @( (PwrV $SUB_SLEEP '29f6c1db-86da-48c5-9fdb-f2b67b1f44da' 0 1800) ) },

    @{ Name = 'Disable wake timers (AC power)'; Risk = 'Low'; Category = 'CPU & power'
       Desc = 'Stops scheduled tasks and apps from waking the PC from sleep in the middle of the night.'
       Pwr = @( (PwrV $SUB_SLEEP 'bd3b718a-0680-4d9d-8ab2-e1d2b4ac806d' 0 1) ) },

    @{ Name = 'Disable USB 3 link power management (AC)'; Risk = 'Low'; Category = 'CPU & power'
       Desc = 'Fixes USB 3 devices (headsets, capture cards, controllers) that disconnect or lag when idle.'
       Pwr = @( (PwrV $SUB_USB 'd4e98f31-5ffe-4ce1-be31-1b38b384c009' 0 1) ) },

    # ---------------- Memory ----------------
    @{ Name = 'Keep the Windows kernel in RAM (disable paging executive)'; Risk = 'Medium'; Category = 'Memory'
       Desc = 'Drivers and the kernel are never paged out to disk. Only with 16 GB RAM or more. Restart required.'
       Reg = @( (RegV $MEMMGR 'DisablePagingExecutive' 1 'DWord' 0) ); Reboot = $true },

    @{ Name = 'Disable Prefetcher and Superfetch (registry)'; Risk = 'Medium'; Category = 'Memory'
       Desc = 'Stops Windows pre-loading app data into RAM. Reduces background disk reads; apps on HDDs may launch slower. Restart required.'
       Reg = @( (RegV $PFX 'EnablePrefetcher' 0 'DWord' 3), (RegV $PFX 'EnableSuperfetch' 0 'DWord' 3) ); Reboot = $true },

    @{ Name = 'Disable memory page combining'; Risk = 'Low'; Category = 'Memory'
       Desc = 'Stops Windows scanning RAM for identical pages to merge. Saves a little CPU; uses a little more RAM.'
       Apply = { Disable-MMAgent -PageCombining -ErrorAction Stop }
       Undo  = { Enable-MMAgent -PageCombining -ErrorAction SilentlyContinue }
       Test  = { -not (Get-MMAgent -ErrorAction Stop).PageCombining } },

    @{ Name = 'Disable application pre-launch and launch prefetching'; Risk = 'Medium'; Category = 'Memory'
       Desc = 'Windows no longer predicts and pre-loads apps you use often. Frees RAM; apps may open slightly slower the first time.'
       Apply = { Disable-MMAgent -ApplicationPreLaunch -ApplicationLaunchPrefetching -ErrorAction Stop }
       Undo  = { Enable-MMAgent -ApplicationPreLaunch -ApplicationLaunchPrefetching -ErrorAction SilentlyContinue }
       Test  = { $m = Get-MMAgent -ErrorAction Stop; (-not $m.ApplicationPreLaunch) -and (-not $m.ApplicationLaunchPrefetching) } },

    @{ Name = 'Disable crash memory dumps'; Risk = 'Low'; Category = 'Memory'
       Desc = 'No dump file is written after a blue screen. Saves disk space and writes, but nobody can analyse the crash afterwards.'
       Reg = @( (RegV $CRASH 'CrashDumpEnabled' 0 'DWord' 7) ) },

    # ---------------- Boot & kernel ----------------
    @{ Name = 'Disable dynamic tick'; Risk = 'Medium'; Category = 'Boot & kernel'
       Desc = 'Keeps the system timer ticking at a steady rate. Can reduce stutter in some games; raises idle power use. Restart required.'
       Apply = { bcdedit /set disabledynamictick yes | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'bcdedit failed (Secure Boot / BitLocker policy may block it).' } }
       Undo  = { bcdedit /deletevalue disabledynamictick | Out-Null }
       Test  = { "$(bcdedit /enum '{current}' 2>&1)" -match 'disabledynamictick\s+Yes' }
       Reboot = $true },

    @{ Name = 'Shorten boot menu timeout to 3 seconds'; Risk = 'Low'; Category = 'Boot & kernel'
       Desc = 'Only matters on dual-boot or recovery-menu setups. Shaves a few seconds off every start.'
       Apply = { bcdedit /timeout 3 | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'bcdedit failed.' } }
       Undo  = { bcdedit /timeout 30 | Out-Null }
       Test  = { "$(bcdedit /enum '{bootmgr}' 2>&1)" -match '(?m)timeout\s+3\s*$' } },

    @{ Name = 'Skip automatic startup repair loop'; Risk = 'Medium'; Category = 'Boot & kernel'
       Desc = 'Windows no longer launches Automatic Repair after failed boots. Useful if a bad driver traps you in a repair loop, but you lose the safety net.'
       Apply = { bcdedit /set '{current}' bootstatuspolicy ignoreallfailures | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'bcdedit failed.' } }
       Undo  = { bcdedit /deletevalue '{current}' bootstatuspolicy | Out-Null }
       Test  = { "$(bcdedit /enum '{current}' 2>&1)" -match 'bootstatuspolicy\s+IgnoreAllFailures' } },

    # ---------------- Latency & input ----------------
    @{ Name = 'Smaller mouse and keyboard input queues'; Risk = 'Low'; Category = 'Latency & input'
       Desc = 'Cuts the driver data queue from 100 to 16 entries so stale input is dropped sooner. Restart required.'
       Reg = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters' 'MouseDataQueueSize' 16 'DWord' 100),
                (RegV 'HKLM:\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters' 'KeyboardDataQueueSize' 16 'DWord' 100) ); Reboot = $true },

    # ---------------- Network (more) ----------------
    @{ Name = 'Disable NetBIOS over TCP/IP (all adapters)'; Risk = 'Medium'; Category = 'Network'
       Desc = 'Closes a legacy name-resolution channel used for spoofing attacks. Breaks name lookups for very old file shares.'
       Apply = { Set-NetbiosAll 2 }
       Undo  = { Set-NetbiosAll 0 }
       Test  = { Test-NetbiosOff } },

    @{ Name = 'Prefer IPv4 over IPv6'; Risk = 'Low'; Category = 'Network'
       Desc = 'Keeps IPv6 enabled but tries IPv4 first. Fixes slow connects on networks with broken IPv6. Restart required.'
       Reg = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters' 'DisabledComponents' 32) ); Reboot = $true },

    @{ Name = 'Network hardening: block source routing and ICMP redirects'; Risk = 'Low'; Category = 'Network'
       Desc = 'Stops the PC accepting packets that try to steer its traffic. No effect on normal use.'
       Reg = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'DisableIPSourceRouting' 2),
                (RegV 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters' 'DisableIPSourceRouting' 2),
                (RegV 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'EnableICMPRedirect' 0) ) },

    # ---------------- Storage (more) ----------------
    @{ Name = 'Increase NTFS memory usage'; Risk = 'Low'; Category = 'Storage'
       Desc = 'Lets NTFS use more paged-pool RAM for file-system caches. Helps folders with millions of files. Restart required.'
       Reg = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsMemoryUsage' 2) ); Reboot = $true },

    # ---------------- Security hardening ----------------
    @{ Name = 'Disable Windows Script Host (.vbs / .js)'; Risk = 'Medium'; Category = 'Security hardening'
       Desc = 'Blocks double-click VBScript and JScript files, a top malware delivery method. Breaks legacy scripts and some installers.'
       Reg = @( (RegV 'HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings' 'Enabled' 0) ) },

    @{ Name = 'Send NTLMv2 only (refuse LM and NTLMv1)'; Risk = 'Medium'; Category = 'Security hardening'
       Desc = 'Rejects the weak legacy sign-in protocols. Old NAS boxes and ancient Windows versions on your network may stop connecting.'
       Reg = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'LmCompatibilityLevel' 5) ) },

    @{ Name = 'Restrict anonymous enumeration of accounts and shares'; Risk = 'Low'; Category = 'Security hardening'
       Desc = 'Anonymous network users can no longer list account names and shares on this PC.'
       Reg = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'RestrictAnonymous' 1 'DWord' 0) ) }
)

# keep the scary category at the bottom of the list
$Extreme = @($Extreme | Where-Object { $_.Category -ne 'Security trade-offs' }) + @($Extreme | Where-Object { $_.Category -eq 'Security trade-offs' })

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
#  CATALOG EXTRAS (v3) - merged into the lists above, existing entries win
# ======================================================================
$AppExtras = [ordered]@{
    'Browsers' = [ordered]@{
        'Opera GX'                 = 'Opera.OperaGX'
        'Tor Browser'              = 'TorProject.TorBrowser'
        'Thunderbird (email)'      = 'Mozilla.Thunderbird'
    }
    'Gaming' = [ordered]@{
        'Minecraft Launcher'       = 'Mojang.MinecraftLauncher'
        'Prism Launcher (Minecraft)' = 'PrismLauncher.PrismLauncher'
        'Roblox Player'            = 'Roblox.Roblox'
        'Roblox Studio'            = 'Roblox.RobloxStudio'
        'Heroic Games Launcher'    = 'HeroicGamesLauncher.HeroicGamesLauncher'
        'Overwolf'                 = 'Overwolf.Overwolf'
        'Parsec'                   = 'Parsec.Parsec'
        'Moonlight'                = 'MoonlightGameStreamingProject.Moonlight'
        'Sunshine (game streaming host)' = 'LizardByte.Sunshine'
        'Logitech G HUB'           = 'Logitech.GHUB'
        'SteelSeries GG'           = 'SteelSeries.GG'
        'TeamSpeak'                = 'TeamSpeakSystems.TeamSpeakClient'
        'Mumble'                   = 'Mumble.Mumble.Client'
    }
    'Hardware & tuning' = [ordered]@{
        'HWMonitor'                = 'CPUID.HWMonitor'
        'Core Temp'                = 'ALCPU.CoreTemp'
        'Fan Control'              = 'Rem0o.FanControl'
        'RTSS (RivaTuner)'         = 'Guru3D.RTSS'
        'Process Lasso'            = 'BitSum.ProcessLasso'
        'ThrottleStop'             = 'TechPowerUp.ThrottleStop'
        'NVIDIA Profile Inspector' = 'Orbmu2k.NvidiaProfileInspector'
    }
    'Media & streaming' = [ordered]@{
        'Streamlabs'               = 'Streamlabs.Streamlabs'
        'foobar2000'               = 'PeterPawlowski.foobar2000'
        'FFmpeg'                   = 'Gyan.FFmpeg'
        'yt-dlp'                   = 'yt-dlp.yt-dlp'
        'Kdenlive'                 = 'KDE.Kdenlive'
        'DaVinci Resolve'          = 'Blackmagic.DaVinciResolve'
    }
    'Creative' = [ordered]@{
        'Blender'                  = 'BlenderFoundation.Blender'
        'GIMP'                     = 'GIMP.GIMP'
        'Krita'                    = 'KDE.Krita'
        'Inkscape'                 = 'Inkscape.Inkscape'
        'Paint.NET'                = 'dotPDNLLC.paintdotnet'
    }
    'Utilities' = [ordered]@{
        'AutoHotkey'               = 'AutoHotkey.AutoHotkey'
        'Ditto (clipboard manager)' = 'Ditto.Ditto'
        'Greenshot'                = 'Greenshot.Greenshot'
        'TreeSize Free'            = 'JAMSoftware.TreeSize.Free'
        'WinDirStat'               = 'WinDirStat.WinDirStat'
        'BleachBit'                = 'BleachBit.BleachBit'
        'Bulk Crap Uninstaller'    = 'Klocman.BulkCrapUninstaller'
        'NanaZip'                  = 'M2Team.NanaZip'
        'Files (modern file manager)' = 'FilesCommunity.Files'
        'TranslucentTB'            = 'CharlesMilette.TranslucentTB'
        'Rainmeter'                = 'Rainmeter.Rainmeter'
        'Ventoy'                   = 'Ventoy.Ventoy'
        'balenaEtcher'             = 'Balena.Etcher'
        'Sysinternals Suite'       = 'Microsoft.Sysinternals.Suite'
        'LocalSend'                = 'LocalSend.LocalSend'
        'LibreOffice'              = 'TheDocumentFoundation.LibreOffice'
        'Obsidian'                 = 'Obsidian.Obsidian'
        'AnyDesk'                  = 'AnyDeskSoftwareGmbH.AnyDesk'
        'RustDesk'                 = 'RustDesk.RustDesk'
    }
    'Security & privacy' = [ordered]@{
        'KeePassXC'                = 'KeePassXCTeam.KeePassXC'
        'VeraCrypt'                = 'IDRIX.VeraCrypt'
        'WireGuard'                = 'WireGuard.WireGuard'
        'Proton VPN'               = 'Proton.ProtonVPN'
        'Mullvad VPN'              = 'MullvadVPN.MullvadVPN'
        'Cloudflare WARP'          = 'Cloudflare.Warp'
        'simplewall (firewall)'    = 'Henry++.simplewall'
        'O&O ShutUp10++'           = 'OO-Software.ShutUp10'
    }
    'Development' = [ordered]@{
        'Cursor'                   = 'Anysphere.Cursor'
        'Sublime Text 4'           = 'SublimeHQ.SublimeText.4'
        'Java JDK 21 (Temurin)'    = 'EclipseAdoptium.Temurin.21.JDK'
        'IntelliJ IDEA Community'  = 'JetBrains.IntelliJIDEA.Community'
        'Android Studio'           = 'Google.AndroidStudio'
        'CMake'                    = 'Kitware.CMake'
        'LLVM / Clang'             = 'LLVM.LLVM'
        'MSYS2'                    = 'MSYS2.MSYS2'
        'VS 2022 Build Tools'      = 'Microsoft.VisualStudio.2022.BuildTools'
        'Windows Subsystem for Linux' = 'Microsoft.WSL'
        'Wireshark'                = 'WiresharkFoundation.Wireshark'
        'DB Browser for SQLite'    = 'DBBrowserForSQLite.DBBrowserForSQLite'
        'FileZilla'                = 'TimKosse.FileZilla.Client'
    }
}
foreach ($cat in $AppExtras.Keys) {
    if (-not $AppCatalog.Contains($cat)) { $AppCatalog[$cat] = [ordered]@{} }
    foreach ($app in $AppExtras[$cat].Keys) {
        if (-not $AppCatalog[$cat].Contains($app)) { $AppCatalog[$cat][$app] = $AppExtras[$cat][$app] }
    }
}

$BloatExtras = [ordered]@{
    'Xbox extras (TCUI, speech overlay, identity)' = @('Microsoft.Xbox.TCUI','Microsoft.XboxSpeechToTextOverlay','Microsoft.XboxIdentityProvider')
    'Media Player (Groove Music)'  = @('Microsoft.ZuneMusic')
    'Widgets (Web Experience Pack)' = @('MicrosoftWindows.Client.WebExperience')
    'Netflix'                      = @('*Netflix*')
    'Hulu'                         = @('*Hulu*')
    'Twitter / X'                  = @('*Twitter*')
    'Dolby Access'                 = @('DolbyLaboratories.DolbyAccess')
    'Messenger'                    = @('*Messenger*')
    'Roblox (Store version)'       = @('ROBLOXCORPORATION.ROBLOX')
    'Plex (Store version)'         = @('*PlexMediaPlayer*')
    'Amazon Alexa'                 = @('*Alexa*')
    'Pinterest / Instagram web apps' = @('*Pinterest*')
}
foreach ($b in $BloatExtras.Keys) { if (-not $BloatCatalog.Contains($b)) { $BloatCatalog[$b] = $BloatExtras[$b] } }

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
        <Border Background="#161A21" CornerRadius="6" Padding="10,8" Margin="0,0,0,10">
          <StackPanel>
            <TextBlock Text="LIVE" FontSize="9" Foreground="#737B8C" Margin="0,0,0,4"/>
            <DockPanel><TextBlock Name="txtLiveCpu" DockPanel.Dock="Right" Text="--%" FontSize="11" Foreground="#9CC3FF"/><TextBlock Text="CPU" FontSize="11" Foreground="#AAB2C0"/></DockPanel>
            <ProgressBar Name="barCpu" Height="4" Minimum="0" Maximum="100" Value="0" Foreground="#58A6FF" Background="#262B35" BorderThickness="0" Margin="0,2,0,6"/>
            <DockPanel><TextBlock Name="txtLiveRam" DockPanel.Dock="Right" Text="--%" FontSize="11" Foreground="#9CC3FF"/><TextBlock Text="RAM" FontSize="11" Foreground="#AAB2C0"/></DockPanel>
            <ProgressBar Name="barRam" Height="4" Minimum="0" Maximum="100" Value="0" Foreground="#A78BFA" Background="#262B35" BorderThickness="0" Margin="0,2,0,6"/>
            <TextBlock Name="txtLiveUp" Text="Uptime --" FontSize="10" Foreground="#737B8C"/>
          </StackPanel>
        </Border>
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
          <Button Name="navTools"   Content="Toolbox"           Style="{StaticResource Nav}"/>
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
              <Button Name="btnSelApplied" Content="Select applied" Style="{StaticResource Chip}" ToolTip="Check everything already applied - then click Undo selected to roll it all back"/>
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
              <Button Name="btnXSelApplied" Content="Select applied" Style="{StaticResource Chip}"/>
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

        <!-- TOOLBOX -->
        <ScrollViewer Name="pgTools" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
          <StackPanel Margin="0,0,10,0">
            <TextBlock Text="Toolbox" Style="{StaticResource H1}"/>
            <TextBlock Style="{StaticResource Sub}" Text="Power tools: temporary boost mode, RAM cleaner, process manager, system utilities, Windows features and quick launchers. Results appear in the output box at the bottom of this page."/>
            <TextBlock Text="BOOST AND MEMORY" Style="{StaticResource H2}"/>
            <WrapPanel>
              <Button Name="btnBoost"      Content="Boost mode: ON" Style="{StaticResource Tool}" Background="#2F6B4F" ToolTip="Temporarily switches to High performance, pauses SysMain/Search/DiagTrack/Print Spooler/Error Reporting and trims RAM. Turn it off (or close EduUtil) to restore everything."/>
              <Button Name="btnFreeRam"    Content="Free RAM now" Style="{StaticResource Tool}" ToolTip="Trims every process working set and purges the standby list."/>
              <Button Name="btnPlanBal"    Content="Power plan: Balanced" Style="{StaticResource Tool}"/>
              <Button Name="btnPlanHigh"   Content="Power plan: High performance" Style="{StaticResource Tool}"/>
              <Button Name="btnPlanSaver"  Content="Power plan: Power saver" Style="{StaticResource Tool}"/>
              <Button Name="btnPlanShow"   Content="Show active power plan" Style="{StaticResource Tool}"/>
            </WrapPanel>
            <TextBlock Text="PROCESS MANAGER" Style="{StaticResource H2}"/>
            <WrapPanel>
              <Button Name="btnProcList" Content="List top 30 by memory" Style="{StaticResource Tool}"/>
              <Button Name="btnProcKill" Content="End selected process" Style="{StaticResource Danger}" Width="250"/>
            </WrapPanel>
            <ListBox Name="lstProc" Height="190" Background="#0D0F13" Foreground="#C9CED8" BorderThickness="0" FontFamily="Consolas" FontSize="12" Margin="0,0,0,6"/>
            <TextBlock Text="SYSTEM TOOLS" Style="{StaticResource H2}"/>
            <WrapPanel>
              <Button Name="btnBrowserCache" Content="Clear browser caches" Style="{StaticResource Tool}" ToolTip="Chrome, Edge, Brave, Firefox caches only. Logins, history and bookmarks are kept."/>
              <Button Name="btnLargeFiles"   Content="Find 30 largest files" Style="{StaticResource Tool}"/>
              <Button Name="btnExportApps"   Content="Export installed programs (CSV)" Style="{StaticResource Tool}"/>
              <Button Name="btnWifi"         Content="Show saved Wi-Fi passwords" Style="{StaticResource Tool}"/>
              <Button Name="btnActivation"   Content="Windows activation status" Style="{StaticResource Tool}"/>
              <Button Name="btnRebuildSearch" Content="Rebuild search index" Style="{StaticResource Tool}"/>
              <Button Name="btnClearEvents"  Content="Clear all event logs" Style="{StaticResource Tool}"/>
              <Button Name="btnReregStore"   Content="Re-register Store apps" Style="{StaticResource Tool}" ToolTip="Fixes apps that crash or will not open (Settings, Start, Store, Photos...). Takes a few minutes."/>
              <Button Name="btnGodMode"      Content="Create God Mode folder" Style="{StaticResource Tool}"/>
              <Button Name="btnHostsOpen"    Content="Open hosts file" Style="{StaticResource Tool}"/>
              <Button Name="btnUpdateCheck"  Content="Check for EduUtil update" Style="{StaticResource Tool}" Background="#2A3550"/>
            </WrapPanel>
            <TextBlock Text="WINDOWS FEATURES (installs via DISM)" Style="{StaticResource H2}"/>
            <WrapPanel>
              <Button Name="btnFeatNet35"   Content="Enable .NET Framework 3.5" Style="{StaticResource Tool}"/>
              <Button Name="btnFeatWsl"     Content="Enable WSL + Virtual Machine Platform" Style="{StaticResource Tool}"/>
              <Button Name="btnFeatSandbox" Content="Enable Windows Sandbox" Style="{StaticResource Tool}"/>
              <Button Name="btnFeatHyperV"  Content="Enable Hyper-V" Style="{StaticResource Tool}"/>
              <Button Name="btnFeatTelnet"  Content="Enable Telnet client" Style="{StaticResource Tool}"/>
              <Button Name="btnFeatDialog"  Content="Open Windows Features dialog" Style="{StaticResource Tool}"/>
            </WrapPanel>
            <TextBlock Text="QUICK LAUNCH" Style="{StaticResource H2}"/>
            <WrapPanel Name="quickLaunch"/>
            <TextBlock Text="OUTPUT" Style="{StaticResource H2}"/>
            <TextBox Name="txtToolsOut" IsReadOnly="True" Height="230" Background="#0D0F13" Foreground="#9CC3FF" FontFamily="Consolas" FontSize="12" BorderThickness="0" Padding="10" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="NoWrap" Margin="0,0,0,12"/>
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
    <Border Name="loadingOverlay" Grid.ColumnSpan="2" Panel.ZIndex="100" Background="#F5111318">
      <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
        <Grid Width="84" Height="84" HorizontalAlignment="Center">
          <Ellipse Stroke="#1E2430" StrokeThickness="6"/>
          <Path Stroke="#58A6FF" StrokeThickness="6" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Data="M 42,3 A 39,39 0 0 1 81,42" RenderTransformOrigin="0.5,0.5">
            <Path.RenderTransform><RotateTransform x:Name="spinA"/></Path.RenderTransform>
          </Path>
          <Path Stroke="#A78BFA" StrokeThickness="6" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Data="M 42,81 A 39,39 0 0 1 3,42" RenderTransformOrigin="0.5,0.5">
            <Path.RenderTransform><RotateTransform x:Name="spinB"/></Path.RenderTransform>
          </Path>
          <TextBlock Text="E" FontSize="28" FontWeight="Bold" Foreground="#E6E8ED" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Grid>
        <TextBlock Text="EDUUTIL" FontSize="22" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,18,0,2"/>
        <TextBlock Name="txtLoadStep" Text="Starting..." Foreground="#8D95A5" FontSize="12" HorizontalAlignment="Center"/>
        <ProgressBar Name="barLoad" Width="260" Height="4" Margin="0,14,0,0" Minimum="0" Maximum="100" Value="5" Foreground="#58A6FF" Background="#262B35" BorderThickness="0"/>
      </StackPanel>
      <Border.Triggers>
        <EventTrigger RoutedEvent="FrameworkElement.Loaded">
          <BeginStoryboard>
            <Storyboard RepeatBehavior="Forever">
              <DoubleAnimation Storyboard.TargetName="spinA" Storyboard.TargetProperty="Angle" From="0" To="360" Duration="0:0:1.1"/>
              <DoubleAnimation Storyboard.TargetName="spinB" Storyboard.TargetProperty="Angle" From="360" To="0" Duration="0:0:1.7"/>
            </Storyboard>
          </BeginStoryboard>
        </EventTrigger>
      </Border.Triggers>
    </Border>
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
        $h.Cursor = 'Hand'; $h.ToolTip = 'Click to check / uncheck everything in this category'
        $h.Tag = [pscustomobject]@{ Cat = $cat; Recs = $recs }
        $h.Add_MouseLeftButtonUp({ param($sender, $e)
            $info = $sender.Tag
            $mine = @($info.Recs | Where-Object { $_.Category -eq $info.Cat -and $_.Row.Visibility -eq 'Visible' })
            $anyOff = @($mine | Where-Object { -not $_.CB.IsChecked }).Count -gt 0
            foreach ($r in $mine) { $r.CB.IsChecked = $anyOff }
        })
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
#  TOOLBOX (v3)
# ======================================================================
function Write-ToolOut($text) { $txtToolsOut.AppendText([string]$text + [Environment]::NewLine); $txtToolsOut.ScrollToEnd(); Pump }
function Get-FreeRamMB { [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1KB) }

# ---------- select-applied chips (bulk undo helpers) ----------
$btnSelApplied.Add_Click({ foreach ($r in $script:TweakRecs) { $r.CB.IsChecked = ($r.Row.Visibility -eq 'Visible' -and $r.State -eq $true) } })
$btnXSelApplied.Add_Click({ foreach ($r in $script:ExtremeRecs) { $r.CB.IsChecked = ($r.Row.Visibility -eq 'Visible' -and $r.State -eq $true) } })

# ---------- RAM cleaner ----------
function Initialize-MemApi {
    if ('EduMem' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class EduMem {
    [DllImport("psapi.dll")] static extern int EmptyWorkingSet(IntPtr hProcess);
    [DllImport("ntdll.dll")] static extern uint NtSetSystemInformation(int InfoClass, IntPtr Info, int Length);
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr h, uint acc, out IntPtr tok);
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool LookupPrivilegeValue(string host, string name, out long luid);
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool AdjustTokenPrivileges(IntPtr tok, bool disAll, ref TokPriv tp, int len, IntPtr prev, IntPtr relen);
    [StructLayout(LayoutKind.Sequential, Pack=1)] struct TokPriv { public int Count; public long Luid; public int Attr; }
    static bool EnablePrivilege(string name) {
        IntPtr tok;
        if (!OpenProcessToken(System.Diagnostics.Process.GetCurrentProcess().Handle, 0x28, out tok)) return false;
        TokPriv tp = new TokPriv(); tp.Count = 1; tp.Attr = 2;
        long luid;
        if (!LookupPrivilegeValue(null, name, out luid)) return false;
        tp.Luid = luid;
        return AdjustTokenPrivileges(tok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
    }
    public static uint PurgeStandby() {
        EnablePrivilege("SeProfileSingleProcessPrivilege");
        IntPtr p = Marshal.AllocHGlobal(4); Marshal.WriteInt32(p, 4);
        uint r = NtSetSystemInformation(80, p, 4);
        Marshal.FreeHGlobal(p);
        return r;
    }
    public static int TrimAll() {
        int n = 0;
        foreach (System.Diagnostics.Process pr in System.Diagnostics.Process.GetProcesses()) {
            try { if (EmptyWorkingSet(pr.Handle) != 0) n++; } catch { }
        }
        return n;
    }
}
'@
}
function Invoke-FreeRam {
    Initialize-MemApi
    $before = Get-FreeRamMB
    $n = [EduMem]::TrimAll()
    $r = [EduMem]::PurgeStandby()
    Start-Sleep -Milliseconds 600
    $after = Get-FreeRamMB
    return [pscustomobject]@{ Trimmed = $n; Purge = $r; Freed = ($after - $before); Free = $after }
}
$btnFreeRam.Add_Click({
    Set-Busy $true
    try {
        Log 'Freeing RAM...'
        $res = Invoke-FreeRam
        $msg = "RAM cleaned: trimmed $($res.Trimmed) processes, standby list purge code $($res.Purge). Free RAM now $($res.Free) MB (change: $($res.Freed) MB)."
        Log $msg; Write-ToolOut $msg
    } catch { Log "RAM cleaner failed: $($_.Exception.Message)" } finally { Set-Busy $false }
})

# ---------- boost mode (temporary, fully restored) ----------
$script:Boost = $null
$BoostServices = @('SysMain','WSearch','DiagTrack','Spooler','WerSvc')
function Get-ActivePlanGuid {
    $o = (powercfg /getactivescheme) -join ' '
    if ($o -match '([0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})') { return $Matches[1] }
    return $null
}
function Start-Boost {
    $state = @{ Plan = (Get-ActivePlanGuid); Stopped = @() }
    powercfg /setactive SCHEME_MIN 2>$null | Out-Null
    foreach ($n in $BoostServices) {
        $s = Get-Service $n -ErrorAction SilentlyContinue
        if ($s -and $s.Status -eq 'Running' -and $s.CanStop) {
            try { Stop-Service $n -Force -ErrorAction Stop; $state.Stopped += $n } catch { }
        }
    }
    try { [void](Invoke-FreeRam) } catch { }
    $script:Boost = $state
    $btnBoost.Content = 'Boost mode: OFF (restore)'; $btnBoost.Background = '#8A3B3B'
    Log "Boost ON. Paused services: $($state.Stopped -join ', '). Power plan set to High performance."
}
function Stop-Boost {
    if (-not $script:Boost) { return }
    foreach ($n in $script:Boost.Stopped) { try { Start-Service $n -ErrorAction SilentlyContinue } catch { } }
    if ($script:Boost.Plan) { powercfg /setactive $script:Boost.Plan 2>$null | Out-Null }
    $script:Boost = $null
    $btnBoost.Content = 'Boost mode: ON'; $btnBoost.Background = '#2F6B4F'
    Log 'Boost OFF. Services and power plan restored.'
}
$btnBoost.Add_Click({
    Set-Busy $true
    try {
        if ($script:Boost) { Stop-Boost }
        else {
            if (-not (Confirm-Action "Boost mode will, until you turn it off or close EduUtil:`n- switch to the High performance power plan`n- pause SysMain, Windows Search, DiagTrack, Print Spooler and Error Reporting`n- trim RAM`n`nNothing is changed permanently. Continue?")) { return }
            Start-Boost
        }
    } finally { Set-Busy $false }
})
$window.Add_Closing({ try { Stop-Boost } catch { } })

# ---------- power plans ----------
$btnPlanBal.Add_Click({ powercfg /setactive SCHEME_BALANCED | Out-Null; Log 'Power plan: Balanced.' })
$btnPlanHigh.Add_Click({ powercfg /setactive SCHEME_MIN | Out-Null; if ($LASTEXITCODE -eq 0) { Log 'Power plan: High performance.' } else { Log 'High performance plan is not available on this PC. Use the Ultimate Performance tweak instead.' } })
$btnPlanSaver.Add_Click({ powercfg /setactive SCHEME_MAX | Out-Null; Log 'Power plan: Power saver.' })
$btnPlanShow.Add_Click({ Write-ToolOut ((powercfg /getactivescheme) -join ' '); Write-ToolOut ((powercfg /list) -join [Environment]::NewLine) })

# ---------- process manager ----------
$ProtectedProcs = @('system','idle','registry','smss','csrss','wininit','winlogon','services','lsass','svchost','dwm','fontdrvhost','memory compression','msmpeng','explorer')
function Refresh-Procs {
    $lstProc.Items.Clear()
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.WorkingSet64 -gt 0 } | Sort-Object WorkingSet64 -Descending | Select-Object -First 30
    foreach ($p in $procs) {
        $item = New-Object System.Windows.Controls.ListBoxItem
        $item.Content = ('{0,-30} PID {1,-7} {2,7} MB' -f $p.ProcessName, $p.Id, [math]::Round($p.WorkingSet64 / 1MB))
        $item.Tag = [pscustomobject]@{ Id = $p.Id; Name = $p.ProcessName }
        $item.Foreground = '#C9CED8'
        [void]$lstProc.Items.Add($item)
    }
    Log "Process list refreshed ($($lstProc.Items.Count) shown)."
}
$btnProcList.Add_Click({ Refresh-Procs })
$btnProcKill.Add_Click({
    $sel = $lstProc.SelectedItem
    if (-not $sel) { Log 'Select a process in the list first.'; return }
    $info = $sel.Tag
    if ($ProtectedProcs -contains $info.Name.ToLower() -or $info.Id -eq $PID) { Log "$($info.Name) is protected and will not be ended."; return }
    if (-not (Confirm-Action "End $($info.Name) (PID $($info.Id))? Unsaved work in that program is lost." 'Warning')) { return }
    try { Stop-Process -Id $info.Id -Force -ErrorAction Stop; Log "Ended $($info.Name) (PID $($info.Id))."; Refresh-Procs }
    catch { Log "Could not end $($info.Name): $($_.Exception.Message)" }
})

# ---------- system tools ----------
$btnBrowserCache.Add_Click({
    if (-not (Confirm-Action 'Clear Chrome, Edge, Brave and Firefox caches? Close those browsers first. Logins, history and bookmarks are kept.')) { return }
    $paths = New-Object System.Collections.Generic.List[string]
    $roots = @("$env:LOCALAPPDATA\Google\Chrome\User Data", "$env:LOCALAPPDATA\Microsoft\Edge\User Data", "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data")
    foreach ($r in $roots) {
        if (Test-Path -LiteralPath $r) {
            foreach ($prof in (Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })) {
                foreach ($sub in 'Cache','Code Cache','GPUCache','Service Worker\CacheStorage') { $paths.Add((Join-Path $prof.FullName $sub)) }
            }
        }
    }
    $ff = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path -LiteralPath $ff) { foreach ($d in (Get-ChildItem -LiteralPath $ff -Directory -ErrorAction SilentlyContinue)) { $paths.Add((Join-Path $d.FullName 'cache2')) } }
    Set-Busy $true; try { Log 'Clearing browser caches...'; $mb = Clear-Folders $paths.ToArray() } finally { Set-Busy $false }
    $msg = "Browser caches cleared: $mb MB freed."; Log $msg; Write-ToolOut $msg
})
$btnLargeFiles.Add_Click({
    Set-Busy $true
    try {
        Log 'Scanning your user folder for the largest files (this can take a while)...'
        $job = Start-Job -ArgumentList $env:USERPROFILE -ScriptBlock {
            param($root)
            $top = New-Object System.Collections.Generic.List[object]; $min = 0
            Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                if ($top.Count -lt 30 -or $_.Length -gt $min) {
                    $top.Add([pscustomobject]@{ L = $_.Length; P = $_.FullName })
                    if ($top.Count -gt 30) { $top = [System.Collections.Generic.List[object]]@($top | Sort-Object L -Descending | Select-Object -First 30); $min = $top[$top.Count - 1].L }
                }
            }
            $top | Sort-Object L -Descending | ForEach-Object { '{0,9} MB   {1}' -f [math]::Round($_.L / 1MB, 1), $_.P }
        }
        while ($job.State -eq 'Running') { Pump; Start-Sleep -Milliseconds 200 }
        $out = @(Receive-Job $job -ErrorAction SilentlyContinue); Remove-Job $job -Force
        $txtToolsOut.Clear(); Write-ToolOut "30 largest files under $env:USERPROFILE`n"
        foreach ($l in $out) { Write-ToolOut $l }
        Log 'Largest-file scan finished.'
    } catch { Log "Scan failed: $($_.Exception.Message)" } finally { Set-Busy $false }
})
$btnExportApps.Add_Click({
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $apps = Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate | Sort-Object DisplayName -Unique
    $out = Join-Path ([Environment]::GetFolderPath('Desktop')) 'installed-programs.csv'
    $apps | Export-Csv -LiteralPath $out -NoTypeInformation -Encoding UTF8
    $msg = "Exported $(@($apps).Count) programs to $out"; Log $msg; Write-ToolOut $msg
})
$btnWifi.Add_Click({
    if (-not (Confirm-Action 'Show the passwords of Wi-Fi networks saved on THIS PC? They will appear in the output box below.')) { return }
    $tmp = Join-Path $env:TEMP ('eduwifi_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        netsh wlan export profile key=clear folder="$tmp" 2>&1 | Out-Null
        $files = @(Get-ChildItem -LiteralPath $tmp -Filter '*.xml' -ErrorAction SilentlyContinue)
        $txtToolsOut.Clear()
        if ($files.Count -eq 0) { Write-ToolOut 'No saved Wi-Fi profiles found (or no Wi-Fi adapter).' }
        foreach ($f in $files) {
            try {
                $x = [xml](Get-Content -LiteralPath $f.FullName -Raw)
                $pw = $x.WLANProfile.MSM.security.sharedKey.keyMaterial
                if (-not $pw) { $pw = '(open network / no stored key)' }
                Write-ToolOut ('{0,-32} {1}' -f $x.WLANProfile.name, $pw)
            } catch { }
        }
        Log "Listed $($files.Count) saved Wi-Fi networks."
    } finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
})
$btnActivation.Add_Click({
    try {
        $p = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND ApplicationId='55c92734-d682-4d71-983e-d6ec3f16059f'" -ErrorAction Stop | Select-Object -First 1
        $st = switch ([int]$p.LicenseStatus) { 0 {'Unlicensed'} 1 {'Licensed (activated)'} 2 {'Out-of-box grace period'} 3 {'Out-of-tolerance grace period'} 4 {'Non-genuine grace period'} 5 {'Notification mode'} 6 {'Extended grace period'} default {'Unknown'} }
        $msg = "$($p.Name): $st"; Log $msg; Write-ToolOut $msg
    } catch { Log "Could not read activation status: $($_.Exception.Message)" }
})
$btnRebuildSearch.Add_Click({
    if (-not (Confirm-Action 'Rebuild the Windows Search index? Search results may be incomplete for a while as it re-indexes.')) { return }
    Set-Busy $true
    try {
        Stop-Service WSearch -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath "$env:ProgramData\Microsoft\Search\Data\Applications\Windows\Windows.edb" -Force -ErrorAction SilentlyContinue
        Start-Service WSearch -ErrorAction SilentlyContinue
    } finally { Set-Busy $false }
    Log 'Search index reset. Windows will rebuild it in the background.'
})
$btnClearEvents.Add_Click({
    if (-not (Confirm-Action 'Clear ALL Windows event logs? Troubleshooting history is lost. This cannot be undone.' 'Warning')) { return }
    Set-Busy $true
    $n = 0
    try {
        foreach ($l in (Get-WinEvent -ListLog * -ErrorAction SilentlyContinue)) {
            try { [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($l.LogName); $n++ } catch { }
            if ($n % 15 -eq 0) { Pump }
        }
    } finally { Set-Busy $false }
    Log "Cleared $n event logs."
})
$btnReregStore.Add_Click({
    if (-not (Confirm-Action 'Re-register all built-in Store apps for all users? Fixes broken Start/Settings/Store/Photos. Takes a few minutes; errors for in-use apps are ignored.')) { return }
    $cmd = 'Get-AppxPackage -AllUsers | ForEach-Object { if ($_.InstallLocation) { Add-AppxPackage -DisableDevelopmentMode -Register (''{0}\AppXManifest.xml'' -f $_.InstallLocation) -ErrorAction SilentlyContinue } }'
    Log 'Re-registering Store apps...'
    $code = Invoke-Hidden 'powershell.exe' "-NoProfile -ExecutionPolicy Bypass -Command `"$cmd`""
    Log "Store apps re-registered (code $code). Restart if anything still misbehaves."
})
$btnGodMode.Add_Click({
    $gm = Join-Path ([Environment]::GetFolderPath('Desktop')) 'GodMode.{ED7BA470-8E54-465E-825C-99712043E01C}'
    if (-not (Test-Path -LiteralPath $gm)) { New-Item -ItemType Directory -Path $gm | Out-Null }
    Log 'God Mode folder created on your desktop.'
})
$btnHostsOpen.Add_Click({ Start-Process notepad.exe $HostsFile })

# ---------- update checker ----------
$btnUpdateCheck.Add_Click({
    try {
        Log 'Checking GitHub for a newer EduUtil...'
        $txt = (Invoke-WebRequest -UseBasicParsing -Uri $RepoUrl -TimeoutSec 15).Content
        if ($txt -match '\$AppVersion\s*=\s*''([\d\.]+)''') {
            $remote = [version]$Matches[1]; $local = [version]$AppVersion
            if ($remote -gt $local) {
                Log "Update available: v$remote (you have v$local)."
                if (Confirm-Action "EduUtil v$remote is available (you have v$local). Download it and restart now?") {
                    $args2 = "-NoProfile -ExecutionPolicy Bypass -Command `"irm '$RepoUrl' | iex`""
                    Start-Process powershell.exe -ArgumentList $args2 -Verb RunAs | Out-Null
                    $window.Close()
                }
            } else { Log "You are on the latest version (v$local)."; Write-ToolOut "EduUtil v$local is up to date." }
        } else { Log 'Could not read the version number from GitHub.' }
    } catch { Log "Update check failed: $($_.Exception.Message)" }
})

# ---------- Windows features ----------
function Enable-Feat($label, $features) {
    if (-not (Confirm-Action "Enable $label? Windows may download components and ask for a restart.")) { return }
    foreach ($f in $features) {
        Log "Enabling $f ..."
        $code = Invoke-Hidden 'dism.exe' "/Online /Enable-Feature /FeatureName:$f /All /NoRestart /Quiet"
        $note = if ($code -eq 0) { 'done' } elseif ($code -eq 3010) { 'done, restart required' } else { 'failed or unavailable on this edition' }
        Log "  $f -> exit code $code ($note)"; Write-ToolOut "$f : $note"
    }
}
$btnFeatNet35.Add_Click({   Enable-Feat '.NET Framework 3.5' @('NetFx3') })
$btnFeatWsl.Add_Click({     Enable-Feat 'WSL and Virtual Machine Platform' @('Microsoft-Windows-Subsystem-Linux','VirtualMachinePlatform') })
$btnFeatSandbox.Add_Click({ Enable-Feat 'Windows Sandbox (Pro/Enterprise only)' @('Containers-DisposableClientVM') })
$btnFeatHyperV.Add_Click({  Enable-Feat 'Hyper-V (Pro/Enterprise only)' @('Microsoft-Hyper-V-All') })
$btnFeatTelnet.Add_Click({  Enable-Feat 'Telnet client' @('TelnetClient') })
$btnFeatDialog.Add_Click({  Start-Process optionalfeatures.exe })

# ---------- quick launch grid ----------
$QuickItems = @(
    @('Task Manager','taskmgr.exe',''), @('Device Manager','devmgmt.msc',''), @('Services','services.msc',''), @('Task Scheduler','taskschd.msc',''),
    @('Event Viewer','eventvwr.msc',''), @('Disk Management','diskmgmt.msc',''), @('Computer Management','compmgmt.msc',''), @('Registry Editor','regedit.exe',''),
    @('Group Policy Editor','gpedit.msc',''), @('Resource Monitor','resmon.exe',''), @('Performance Monitor','perfmon.exe',''), @('System Configuration','msconfig.exe',''),
    @('System Information','msinfo32.exe',''), @('DirectX Diagnostics','dxdiag.exe',''), @('Power Options','powercfg.cpl',''), @('Network Connections','ncpa.cpl',''),
    @('Programs and Features','appwiz.cpl',''), @('Environment Variables','rundll32.exe','sysdm.cpl,EditEnvironmentVariables'), @('Advanced System Properties','SystemPropertiesAdvanced.exe',''),
    @('Performance Options','SystemPropertiesPerformance.exe',''), @('Sound settings','mmsys.cpl',''), @('Mouse settings','main.cpl',''),
    @('Firewall (advanced)','wf.msc',''), @('Windows Security','windowsdefender:',''), @('Disk Cleanup','cleanmgr.exe',''), @('Windows Terminal','wt.exe','')
)
foreach ($q in $QuickItems) {
    $b = New-Object System.Windows.Controls.Button
    $b.Content = $q[0]; $b.Style = $window.FindResource('Tool'); $b.Width = 200; $b.Tag = $q
    $b.Add_Click({ param($s, $e)
        $t = $s.Tag
        try {
            if ($t[2]) { Start-Process $t[1] $t[2] } else { Start-Process $t[1] }
        } catch { Log "$($t[0]) is not available on this PC." }
    })
    [void]$quickLaunch.Children.Add($b)
}

# ---------- live monitor in the sidebar ----------
$script:CpuCounter = $null
try { $script:CpuCounter = New-Object System.Diagnostics.PerformanceCounter('Processor', '% Processor Time', '_Total'); [void]$script:CpuCounter.NextValue() } catch { }
function Update-Live {
    try {
        if ($script:CpuCounter) { $c = [int][math]::Round($script:CpuCounter.NextValue()); $barCpu.Value = $c; $txtLiveCpu.Text = "$c%" }
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $total = [double]$os.TotalVisibleMemorySize; $used = $total - [double]$os.FreePhysicalMemory
        $pct = [int][math]::Round(100 * $used / $total)
        $barRam.Value = $pct; $txtLiveRam.Text = "$pct%  $([math]::Round($used / 1MB, 1))/$([math]::Round($total / 1MB, 1)) GB"
        $up = (Get-Date) - $os.LastBootUpTime
        $txtLiveUp.Text = 'Uptime {0}d {1}h {2}m' -f $up.Days, $up.Hours, $up.Minutes
    } catch { }
}
$script:LiveTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:LiveTimer.Interval = [TimeSpan]::FromSeconds(2)
$script:LiveTimer.Add_Tick({ Update-Live })

# ---------- loading overlay helpers ----------
function Set-LoadStep($text, $pct) {
    if ($txtLoadStep) { $txtLoadStep.Text = $text }
    if ($barLoad) { $barLoad.Value = $pct }
    Pump
}
function Hide-LoadOverlay {
    $fade = New-Object System.Windows.Media.Animation.DoubleAnimation(1.0, 0.0, [TimeSpan]::FromMilliseconds(450))
    $fade.Add_Completed({ $loadingOverlay.Visibility = 'Collapsed' })
    $loadingOverlay.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)
}

# ======================================================================
#  NAVIGATION
# ======================================================================
$Pages = [ordered]@{
    navTweaks = 'pgTweaks'; navExtreme = 'pgExtreme'; navGame = 'pgGame'; navDebloat = 'pgDebloat'; navStartup = 'pgStartup'
    navInstall = 'pgInstall'; navClean = 'pgClean'; navTools = 'pgTools'; navNetwork = 'pgNetwork'; navSysInfo = 'pgSysInfo'; navLog = 'pgLog'
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
    try {
        Set-LoadStep 'Checking everyday tweaks...' 20
        Update-RecStatus $script:TweakRecs
        Set-LoadStep 'Checking advanced tweaks...' 65
        Update-RecStatus $script:ExtremeRecs
        Set-LoadStep 'Starting live monitor...' 92
        Update-Live; $script:LiveTimer.Start()
        Set-LoadStep 'Ready' 100
    } finally { Set-Busy $false }
    Hide-LoadOverlay
    Log "Ready. $($script:TweakRecs.Count) everyday + $($script:ExtremeRecs.Count) advanced tweaks loaded. Pick a preset or click a category title to check it all, then Apply selected."
})
[void]$window.ShowDialog()
