#Requires -Version 5.1
<#
.SYNOPSIS
    Gerenciador de workspace multi-monitor para Windows.
.DESCRIPTION
    Abre aplicativos e posiciona janelas de acordo com perfis salvos.
    Suporta captura do layout atual, deteccao de monitores, e menu interativo.

    Posicoes nomeadas: left, right, full, top, bottom,
      top-left, top-right, bottom-left, bottom-right
    Posicoes customizadas: x%,y%,w%,h% (porcentagem da area visivel)

    Config: $env:USERPROFILE\.config\workspace-profiles.conf
.PARAMETER Profile
    Nome do perfil a carregar (quando invocado sem flags).
.EXAMPLE
    .\setup-workspace.ps1                  # Menu interativo
    .\setup-workspace.ps1 dev              # Carrega perfil "dev"
    .\setup-workspace.ps1 --save trabalho  # Grava layout atual como "trabalho"
    .\setup-workspace.ps1 --detect         # Mostra monitores conectados
.NOTES
    Caso a execucao seja bloqueada, rode:
      Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
#>

# ═══════════════════════════════════════════
# Win32 API declarations via P/Invoke
# ═══════════════════════════════════════════

# Add User32 functions for window management
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class User32 {
    // Move and resize a window
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

    // Bring a window to the foreground
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    // Get the bounding rectangle of a window
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    // Check if a window is visible
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    // Get window title text length
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern int GetWindowTextLength(IntPtr hWnd);

    // Get window title text
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    // Show/restore a window
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    // Constants for ShowWindow
    public const int SW_RESTORE = 9;
    public const int SW_SHOW = 5;
    public const int SW_MINIMIZE = 6;
}

// Rectangle structure for GetWindowRect
[StructLayout(LayoutKind.Sequential)]
public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}
"@ -ErrorAction SilentlyContinue

# Add System.Windows.Forms for screen/display detection
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

# ═══════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════

$ConfigFile = if ($env:WORKSPACE_CONFIG) { $env:WORKSPACE_CONFIG } else { Join-Path $env:USERPROFILE ".config\workspace-profiles.conf" }

# System processes to skip during capture
$SkipProcesses = @(
    'explorer', 'SearchUI', 'SearchHost', 'ShellExperienceHost',
    'StartMenuExperienceHost', 'SystemSettings', 'TextInputHost',
    'ApplicationFrameHost', 'LockApp', 'LogiOverlay', 'SecurityHealthSystray',
    'svchost', 'csrss', 'dwm', 'winlogon', 'taskhostw', 'sihost',
    'RuntimeBroker', 'backgroundTaskHost', 'WidgetService', 'Widgets'
)

# ═══════════════════════════════════════════
# Helper functions
# ═══════════════════════════════════════════

function Get-DisplayInfo {
    <#
    .DESCRIPTION
        Returns info about all connected monitors using System.Windows.Forms.Screen.
        Each entry: Name, BoundsX, BoundsY, BoundsW, BoundsH, WorkX, WorkY, WorkW, WorkH
    #>
    $screens = [System.Windows.Forms.Screen]::AllScreens
    $result = @()
    $idx = 0
    foreach ($screen in $screens) {
        $idx++
        $name = $screen.DeviceName
        # Clean up device name (e.g., \\.\DISPLAY1 -> DISPLAY1)
        if ($name -match 'DISPLAY\d+') {
            $friendlyName = $Matches[0]
        }
        else {
            $friendlyName = "Monitor $idx"
        }
        if ($screen.Primary) {
            $friendlyName = "$friendlyName (Principal)"
        }

        $result += [PSCustomObject]@{
            Index   = $idx
            Name    = $friendlyName
            RawName = $screen.DeviceName
            Primary = $screen.Primary
            BoundsX = $screen.Bounds.X
            BoundsY = $screen.Bounds.Y
            BoundsW = $screen.Bounds.Width
            BoundsH = $screen.Bounds.Height
            WorkX   = $screen.WorkingArea.X
            WorkY   = $screen.WorkingArea.Y
            WorkW   = $screen.WorkingArea.Width
            WorkH   = $screen.WorkingArea.Height
        }
    }
    return $result
}

function Show-Displays {
    $displays = Get-DisplayInfo
    if ($displays.Count -eq 0) {
        Write-Host "  Nenhum display detectado." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "  Monitores conectados:" -ForegroundColor White
    Write-Host ""

    $headerFmt = "  {0,-4} {1,-28} {2,-14} {3,-12} {4}" -f "#", "Nome", "Resolucao", "Orientacao", "Origem"
    Write-Host $headerFmt
    $sepFmt = "  {0,-4} {1,-28} {2,-14} {3,-12} {4}" -f "--", ("--" * 14), ("--" * 7), ("--" * 6), ("--" * 5)
    Write-Host $sepFmt

    foreach ($d in $displays) {
        $orient = if ($d.BoundsH -gt $d.BoundsW) { "retrato" } else { "paisagem" }
        $res = "$($d.BoundsW)x$($d.BoundsH)"
        $origin = "($($d.BoundsX), $($d.BoundsY))"
        $line = "  {0,-4} {1,-28} {2,-14} {3,-12} {4}" -f $d.Index, $d.Name, $res, $orient, $origin
        Write-Host $line
    }

    Write-Host ""
    Write-Host "  Para usar no config, adicione o mapeamento:" -ForegroundColor White
    Write-Host ""
    foreach ($d in $displays) {
        Write-Host "  monitor.$($d.Index)=$($d.Name)" -ForegroundColor Cyan
    }
    Write-Host ""
    Write-Host "  Salve em: $ConfigFile" -ForegroundColor DarkGray
    Write-Host ""
}

function Resolve-Display {
    <#
    .DESCRIPTION
        Resolves a monitor number from config to actual display info.
        Tries config mapping first, then falls back to index.
    #>
    param([int]$MonitorNum)

    $displays = Get-DisplayInfo
    $displayName = ""

    # Try config mapping
    if (Test-Path $ConfigFile) {
        $configLines = Get-Content -Path $ConfigFile -ErrorAction SilentlyContinue
        foreach ($line in $configLines) {
            if ($line -match "^monitor\.$MonitorNum=(.+)$") {
                $displayName = $Matches[1].Trim()
                break
            }
        }
    }

    # Match by name
    if ($displayName) {
        $match = $displays | Where-Object { $_.Name -like "*$displayName*" } | Select-Object -First 1
        if ($match) { return $match }
    }

    # Fallback to index
    $match = $displays | Where-Object { $_.Index -eq $MonitorNum } | Select-Object -First 1
    if ($match) { return $match }

    # Last resort: first display
    return $displays | Select-Object -First 1
}

function Get-DisplayForPoint {
    <#
    .DESCRIPTION
        Determines which display a window's top-left corner is on.
    #>
    param([int]$X, [int]$Y)

    $displays = Get-DisplayInfo
    foreach ($d in $displays) {
        if ($X -ge $d.BoundsX -and $X -lt ($d.BoundsX + $d.BoundsW) -and
            $Y -ge $d.BoundsY -and $Y -lt ($d.BoundsY + $d.BoundsH)) {
            return $d
        }
    }

    # Fallback: closest display (manhattan distance to center)
    $bestDist = [int]::MaxValue
    $bestDisplay = $displays[0]
    foreach ($d in $displays) {
        $cx = $d.BoundsX + [int]($d.BoundsW / 2)
        $cy = $d.BoundsY + [int]($d.BoundsH / 2)
        $dist = [math]::Abs($X - $cx) + [math]::Abs($Y - $cy)
        if ($dist -lt $bestDist) {
            $bestDist = $dist
            $bestDisplay = $d
        }
    }
    return $bestDisplay
}

function Get-NamedPosition {
    <#
    .DESCRIPTION
        Calculates pixel bounds (x, y, w, h) from a named or percentage position
        relative to a display's working area.
    #>
    param(
        [string]$Position,
        [int]$VX, [int]$VY, [int]$VW, [int]$VH
    )

    # Custom percentage: x%,y%,w%,h%
    if ($Position -match '^\d+,\d+,\d+,\d+$') {
        $parts = $Position -split ','
        $px = [int]$parts[0]; $py = [int]$parts[1]
        $pw = [int]$parts[2]; $ph = [int]$parts[3]
        return @{
            X = $VX + [int]($VW * $px / 100)
            Y = $VY + [int]($VH * $py / 100)
            W = [int]($VW * $pw / 100)
            H = [int]($VH * $ph / 100)
        }
    }

    $halfW = [int]($VW / 2)
    $halfH = [int]($VH / 2)

    switch ($Position) {
        'left'         { return @{ X = $VX;          Y = $VY;          W = $halfW; H = $VH } }
        'right'        { return @{ X = $VX + $halfW; Y = $VY;          W = $halfW; H = $VH } }
        'full'         { return @{ X = $VX;          Y = $VY;          W = $VW;    H = $VH } }
        'top'          { return @{ X = $VX;          Y = $VY;          W = $VW;    H = $halfH } }
        'bottom'       { return @{ X = $VX;          Y = $VY + $halfH; W = $VW;    H = $halfH } }
        'top-left'     { return @{ X = $VX;          Y = $VY;          W = $halfW; H = $halfH } }
        'top-right'    { return @{ X = $VX + $halfW; Y = $VY;          W = $halfW; H = $halfH } }
        'bottom-left'  { return @{ X = $VX;          Y = $VY + $halfH; W = $halfW; H = $halfH } }
        'bottom-right' { return @{ X = $VX + $halfW; Y = $VY + $halfH; W = $halfW; H = $halfH } }
        default        { return @{ X = $VX;          Y = $VY;          W = $VW;    H = $VH } }
    }
}

function Detect-PositionName {
    <#
    .DESCRIPTION
        Detects a named position from percentage coordinates, or returns custom x,y,w,h.
    #>
    param([int]$PX, [int]$PY, [int]$PW, [int]$PH)

    $tolerance = 5

    # Check each named position
    $positions = @{
        'full'         = @(0,   0,  100, 100)
        'left'         = @(0,   0,  50,  100)
        'right'        = @(50,  0,  50,  100)
        'top'          = @(0,   0,  100, 50)
        'bottom'       = @(0,   50, 100, 50)
        'top-left'     = @(0,   0,  50,  50)
        'top-right'    = @(50,  0,  50,  50)
        'bottom-left'  = @(0,   50, 50,  50)
        'bottom-right' = @(50,  50, 50,  50)
    }

    foreach ($entry in $positions.GetEnumerator()) {
        $expected = $entry.Value
        if ([math]::Abs($PX - $expected[0]) -le $tolerance -and
            [math]::Abs($PY - $expected[1]) -le $tolerance -and
            [math]::Abs($PW - $expected[2]) -le $tolerance -and
            [math]::Abs($PH - $expected[3]) -le $tolerance) {
            return $entry.Key
        }
    }

    return "$PX,$PY,$PW,$PH"
}

function Display-NameToConfigNum {
    <#
    .DESCRIPTION
        Maps a display name to its config monitor number.
    #>
    param([string]$TargetName)

    if (Test-Path $ConfigFile) {
        foreach ($line in (Get-Content -Path $ConfigFile -ErrorAction SilentlyContinue)) {
            if ($line -match '^monitor\.(\d+)=(.+)$') {
                $num = $Matches[1]
                $pattern = $Matches[2].Trim()
                if ($TargetName -like "*$pattern*") {
                    return [int]$num
                }
            }
        }
    }

    # Fallback: index from display list
    $displays = Get-DisplayInfo
    foreach ($d in $displays) {
        if ($d.Name -eq $TargetName) {
            return $d.Index
        }
    }
    return 1
}

# ═══════════════════════════════════════════
# Config and profiles
# ═══════════════════════════════════════════

function Get-ProfileLines {
    if (-not (Test-Path $ConfigFile)) { return @() }
    $lines = Get-Content -Path $ConfigFile -ErrorAction SilentlyContinue |
        Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*$' -and $_ -notmatch '^monitor\.' -and $_ -match '\|' }
    return @($lines)
}

function Get-ProfileNames {
    $lines = Get-ProfileLines
    if ($lines.Count -eq 0) { return @() }
    $names = $lines | ForEach-Object { ($_ -split '\|')[0] } | Sort-Object -Unique
    return @($names)
}

function Show-Profiles {
    $lines = Get-ProfileLines
    $names = Get-ProfileNames
    if ($names.Count -eq 0) { return $false }

    foreach ($pname in $names) {
        $apps = ($lines | Where-Object { ($_ -split '\|')[0] -eq $pname } |
            ForEach-Object { ($_ -split '\|')[1] } | Sort-Object -Unique) -join ", "
        $label = $pname.PadRight(12)
        Write-Host "     " -NoNewline
        Write-Host "$label" -NoNewline -ForegroundColor Cyan
        Write-Host " $apps"
    }
    return $true
}

# ═══════════════════════════════════════════
# Window capture
# ═══════════════════════════════════════════

function Get-VisibleWindows {
    <#
    .DESCRIPTION
        Enumerates all visible windows with position and size.
        Returns array of objects with ProcessName, Handle, X, Y, W, H.
    #>
    $windows = @()

    $processes = Get-Process | Where-Object {
        $_.MainWindowHandle -ne [IntPtr]::Zero -and
        $_.ProcessName -notin $SkipProcesses -and
        [User32]::IsWindowVisible($_.MainWindowHandle)
    }

    foreach ($proc in $processes) {
        $hwnd = $proc.MainWindowHandle
        $rect = New-Object RECT
        if ([User32]::GetWindowRect($hwnd, [ref]$rect)) {
            $w = $rect.Right - $rect.Left
            $h = $rect.Bottom - $rect.Top
            # Skip tiny windows (less than 80x80)
            if ($w -gt 80 -and $h -gt 80) {
                # Get window title
                $titleLen = [User32]::GetWindowTextLength($hwnd)
                $title = ""
                if ($titleLen -gt 0) {
                    $sb = New-Object System.Text.StringBuilder($titleLen + 1)
                    [void][User32]::GetWindowText($hwnd, $sb, $sb.Capacity)
                    $title = $sb.ToString()
                }

                $windows += [PSCustomObject]@{
                    ProcessName = $proc.ProcessName
                    Title       = $title
                    Handle      = $hwnd
                    X           = $rect.Left
                    Y           = $rect.Top
                    W           = $w
                    H           = $h
                }
            }
        }
    }

    return $windows
}

# ═══════════════════════════════════════════
# Save profile
# ═══════════════════════════════════════════

function Save-Profile {
    param([string]$ProfileName)

    Write-Host ""
    Write-Host "  Detectando monitores..." -ForegroundColor DarkGray

    $displays = Get-DisplayInfo
    if ($displays.Count -eq 0) {
        Write-Host "  Falha ao detectar monitores." -ForegroundColor Red
        return
    }

    Write-Host "  Capturando janelas..." -ForegroundColor DarkGray
    $windows = Get-VisibleWindows

    if ($windows.Count -eq 0) {
        Write-Host "  Nenhuma janela encontrada." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "  Layout capturado:" -ForegroundColor White
    Write-Host ""

    $profileLines = @()

    foreach ($win in $windows) {
        # Find which display this window is on
        $display = Get-DisplayForPoint -X $win.X -Y $win.Y

        # Calculate percentage positions relative to working area
        if ($display.WorkW -gt 0 -and $display.WorkH -gt 0) {
            $px = [int](($win.X - $display.WorkX) * 100 / $display.WorkW)
            $py = [int](($win.Y - $display.WorkY) * 100 / $display.WorkH)
            $pw = [int]($win.W * 100 / $display.WorkW)
            $ph = [int]($win.H * 100 / $display.WorkH)
        }
        else {
            $px = 0; $py = 0; $pw = 100; $ph = 100
        }

        # Detect named position
        $position = Detect-PositionName -PX $px -PY $py -PW $pw -PH $ph

        # Get config monitor number
        $configNum = Display-NameToConfigNum -TargetName $display.Name

        $profileLines += "$ProfileName|$($win.ProcessName)|$configNum|$position"

        $appLabel = $win.ProcessName.PadRight(20)
        $displayLabel = $display.Name.PadRight(20)
        Write-Host "  " -NoNewline
        Write-Host ([char]0x2713) -NoNewline -ForegroundColor Green
        Write-Host " $appLabel" -NoNewline
        Write-Host " $([char]0x2192) " -NoNewline
        Write-Host "$displayLabel" -NoNewline -ForegroundColor White
        Write-Host "  $position" -ForegroundColor Cyan
    }

    $monitorCount = ($profileLines | ForEach-Object { ($_ -split '\|')[2] } | Sort-Object -Unique).Count
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "$($profileLines.Count) janelas" -NoNewline -ForegroundColor White
    Write-Host " em " -NoNewline
    Write-Host "$monitorCount" -NoNewline -ForegroundColor White
    Write-Host " monitores"

    # Confirm
    Write-Host ""
    Write-Host "  Salvar perfil " -NoNewline
    Write-Host "`"$ProfileName`"" -NoNewline -ForegroundColor Cyan
    $confirm = Read-Host "? [S/n]"
    if ($confirm -match '^[nN]') {
        Write-Host "  Cancelado." -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    # Ensure config directory and file exist
    $configDir = Split-Path -Path $ConfigFile -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path $ConfigFile)) {
        # Create config with monitor mapping
        $configContent = @("# workspace-profiles.conf")
        $configContent += "# Formato: perfil|App Name|monitor|posicao"
        $configContent += ""
        $configContent += "# -- Mapeamento de monitores --"
        foreach ($d in $displays) {
            $configContent += "monitor.$($d.Index)=$($d.Name)"
        }
        $configContent += ""
        Set-Content -Path $ConfigFile -Value ($configContent -join "`n") -Encoding UTF8
    }

    # Remove old profile lines if they exist
    if (Test-Path $ConfigFile) {
        $existing = Get-Content -Path $ConfigFile -ErrorAction SilentlyContinue
        $filtered = $existing | Where-Object { $_ -notmatch "^$([regex]::Escape($ProfileName))\|" }
        Set-Content -Path $ConfigFile -Value ($filtered -join "`n") -Encoding UTF8
    }

    # Append new profile
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    $appendContent = @("")
    $appendContent += "# -- $ProfileName (gravado em $timestamp) --"
    $appendContent += $profileLines
    Add-Content -Path $ConfigFile -Value ($appendContent -join "`n") -Encoding UTF8

    Write-Host ""
    Write-Host "  Perfil `"$ProfileName`" salvo em $ConfigFile" -ForegroundColor Green
    Write-Host "  Para restaurar: setup-workspace $ProfileName" -ForegroundColor DarkGray
    Write-Host ""
}

# ═══════════════════════════════════════════
# Load profile
# ═══════════════════════════════════════════

function Start-Profile {
    param([string]$TargetProfile)

    $allLines = Get-ProfileLines
    $profileEntries = @($allLines | Where-Object { ($_ -split '\|')[0] -eq $TargetProfile })

    if ($profileEntries.Count -eq 0) {
        Write-Host ""
        Write-Host "  Perfil '" -NoNewline
        Write-Host "$TargetProfile" -NoNewline -ForegroundColor Red
        Write-Host "' nao encontrado."
        Write-Host ""
        Show-Profiles | Out-Null
        exit 1
    }

    Write-Host ""
    Write-Host "  Carregando perfil: " -NoNewline
    Write-Host "$TargetProfile" -ForegroundColor Cyan

    Write-Host "  Detectando monitores..." -ForegroundColor DarkGray
    $displays = Get-DisplayInfo

    if ($displays.Count -eq 0) {
        Write-Host "  Falha ao detectar monitores." -ForegroundColor Red
        exit 1
    }

    Write-Host "  $($displays.Count) monitores detectados" -ForegroundColor DarkGray

    # Parse entries
    $entries = @()
    foreach ($line in $profileEntries) {
        $parts = $line -split '\|'
        $entries += [PSCustomObject]@{
            Profile  = $parts[0]
            App      = $parts[1]
            Monitor  = [int]$parts[2]
            Position = $parts[3]
        }
    }

    $uniqueApps = $entries | Select-Object -ExpandProperty App -Unique

    # Open apps
    Write-Host ""
    Write-Host "  Abrindo apps..."

    foreach ($app in $uniqueApps) {
        $existing = Get-Process -Name $app -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero }

        if (-not $existing) {
            try {
                Start-Process -FilePath $app -ErrorAction Stop
                Write-Host "  " -NoNewline
                Write-Host ([char]0x2713) -NoNewline -ForegroundColor Green
                Write-Host " $app  " -NoNewline
                # Wait for main window to appear
                $waited = 0
                $proc = $null
                while ($waited -lt 20) {
                    Start-Sleep -Milliseconds 500
                    $waited++
                    $proc = Get-Process -Name $app -ErrorAction SilentlyContinue |
                        Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
                        Select-Object -First 1
                    if ($proc) { break }
                }
                if ($proc) {
                    Write-Host "(pid $($proc.Id))" -ForegroundColor DarkGray
                }
                else {
                    Write-Host "(aguardando...)" -ForegroundColor DarkGray
                }
            }
            catch {
                Write-Host "  " -NoNewline
                Write-Host "x $app nao encontrado" -ForegroundColor DarkGray
            }
        }
        else {
            $pid = $existing[0].Id
            Write-Host "  " -NoNewline
            Write-Host ([char]0x2713) -NoNewline -ForegroundColor Green
            Write-Host " $app  " -NoNewline
            Write-Host "(pid $pid)" -ForegroundColor DarkGray
        }
    }

    Start-Sleep -Seconds 1

    # Position windows
    Write-Host ""
    Write-Host "  Posicionando janelas..."

    foreach ($app in $uniqueApps) {
        $appEntries = @($entries | Where-Object { $_.App -eq $app })
        $procs = @(Get-Process -Name $app -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero })

        $winIdx = 0
        foreach ($entry in $appEntries) {
            $display = Resolve-Display -MonitorNum $entry.Monitor

            $bounds = Get-NamedPosition -Position $entry.Position `
                -VX $display.WorkX -VY $display.WorkY `
                -VW $display.WorkW -VH $display.WorkH

            if ($winIdx -lt $procs.Count) {
                $hwnd = $procs[$winIdx].MainWindowHandle

                # Restore window if minimized
                [void][User32]::ShowWindow($hwnd, [User32]::SW_RESTORE)
                Start-Sleep -Milliseconds 100

                # Set foreground
                [void][User32]::SetForegroundWindow($hwnd)
                Start-Sleep -Milliseconds 50

                # Move and resize
                [void][User32]::MoveWindow($hwnd, $bounds.X, $bounds.Y, $bounds.W, $bounds.H, $true)

                Write-Host "  " -NoNewline
                Write-Host ([char]0x2713) -NoNewline -ForegroundColor Green
                $winNum = $winIdx + 1
                Write-Host " $app [$winNum] " -NoNewline
                Write-Host "$([char]0x2192) " -NoNewline
                Write-Host "$($display.Name)" -NoNewline -ForegroundColor White
                Write-Host "  $($entry.Position) ($($bounds.X),$($bounds.Y) $($bounds.W)x$($bounds.H))" -ForegroundColor DarkGray
            }

            $winIdx++
        }
    }

    Write-Host ""
    Write-Host "  Workspace `"$TargetProfile`" pronto." -ForegroundColor Green
    Write-Host ""
}

# ═══════════════════════════════════════════
# Generate config
# ═══════════════════════════════════════════

function New-Config {
    $configDir = Split-Path -Path $ConfigFile -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }

    $displays = Get-DisplayInfo

    $mapping = ""
    foreach ($d in $displays) {
        $mapping += "monitor.$($d.Index)=$($d.Name)`n"
    }

    $configContent = @"
# workspace-profiles.conf
# Formato: perfil|App Name|monitor|posicao
#
# Posicoes nomeadas:
#   left, right, full, top, bottom
#   top-left, top-right, bottom-left, bottom-right
#
# Posicoes customizadas (porcentagem da area visivel):
#   x%,y%,largura%,altura%
#   Exemplo: 0,0,100,45 = topo com 45% da altura

# -- Mapeamento de monitores --
# (rode setup-workspace --detect pra atualizar)
$mapping
"@

    Set-Content -Path $ConfigFile -Value $configContent -Encoding UTF8

    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host ([char]0x2713) -NoNewline -ForegroundColor Green
    Write-Host " Config criada em " -NoNewline
    Write-Host "$ConfigFile" -ForegroundColor White

    if ($displays.Count -gt 0) {
        Write-Host ""
        Write-Host "  Monitores detectados e mapeados:"
        foreach ($d in $displays) {
            Write-Host "    " -NoNewline
            Write-Host "monitor.$($d.Index)" -NoNewline -ForegroundColor Cyan
            Write-Host " = $($d.Name) ($($d.BoundsW)x$($d.BoundsH))"
        }
    }

    Write-Host ""
    Write-Host "  Rode " -NoNewline -ForegroundColor DarkGray
    Write-Host "setup-workspace" -NoNewline -ForegroundColor White
    Write-Host " pra gravar seu primeiro perfil." -ForegroundColor DarkGray
    Write-Host ""
}

# ═══════════════════════════════════════════
# Interactive menu
# ═══════════════════════════════════════════

function Show-InteractiveMenu {
    Write-Host ""

    $profileNames = Get-ProfileNames
    $hasProfiles = $profileNames.Count -gt 0

    Write-Host "  Setup Workspace" -ForegroundColor White
    Write-Host ""

    if ($hasProfiles) {
        Write-Host "  " -NoNewline
        Write-Host "1)" -NoNewline -ForegroundColor Cyan
        Write-Host " Carregar perfil"
        Show-Profiles | Out-Null
        Write-Host ""
    }

    Write-Host "  " -NoNewline
    Write-Host "2)" -NoNewline -ForegroundColor Cyan
    Write-Host " Gravar layout atual como perfil"
    Write-Host ""

    if ($hasProfiles) {
        $choice = Read-Host "  Escolha [1/2]"
    }
    else {
        Write-Host "  Nenhum perfil salvo ainda." -ForegroundColor DarkGray
        Write-Host ""
        $choice = Read-Host "  Pressione ENTER pra gravar o layout atual"
        if ([string]::IsNullOrEmpty($choice)) { $choice = "2" }
    }

    switch ($choice) {
        "1" {
            if (-not $hasProfiles) {
                Write-Host "  Nenhum perfil disponivel." -ForegroundColor Red
                return
            }
            Write-Host ""
            $profile = Read-Host "  Nome do perfil"
            if ([string]::IsNullOrEmpty($profile)) {
                Write-Host "  Cancelado." -ForegroundColor DarkGray
                return
            }
            Start-Profile -TargetProfile $profile
        }
        { $_ -eq "2" -or $_ -eq "" } {
            Write-Host ""
            $name = Read-Host "  Nome pro novo perfil"
            if ([string]::IsNullOrEmpty($name)) {
                Write-Host "  Cancelado." -ForegroundColor DarkGray
                return
            }
            # Sanitize name (lowercase, no spaces)
            $name = $name.ToLower() -replace '\s+', '-'
            Save-Profile -ProfileName $name
        }
        default {
            # Try as profile name
            if ($hasProfiles -and $choice -in $profileNames) {
                Start-Profile -TargetProfile $choice
            }
            else {
                Write-Host "  Opcao invalida." -ForegroundColor Red
            }
        }
    }
}

# ═══════════════════════════════════════════
# Main - Parse arguments
# ═══════════════════════════════════════════

# PowerShell does not handle --flags natively in param(), so we parse $args manually
$scriptArgs = $args

if ($scriptArgs.Count -eq 0) {
    Show-InteractiveMenu
}
elseif ($scriptArgs[0] -eq '--detect') {
    Show-Displays
}
elseif ($scriptArgs[0] -eq '--save') {
    if ($scriptArgs.Count -lt 2) {
        Write-Host "Uso: setup-workspace --save <nome-do-perfil>"
        exit 1
    }
    Save-Profile -ProfileName $scriptArgs[1]
}
elseif ($scriptArgs[0] -eq '--init') {
    New-Config
}
elseif ($scriptArgs[0] -eq '--help' -or $scriptArgs[0] -eq '-h') {
    Write-Host ""
    Write-Host "  Uso: setup-workspace [comando]"
    Write-Host ""
    Write-Host "  Comandos:"
    Write-Host "    (sem args)          Menu interativo (carregar ou gravar)"
    Write-Host "    <perfil>            Abre e posiciona apps do perfil"
    Write-Host "    --save <nome>       Grava o layout atual como perfil"
    Write-Host "    --detect            Mostra monitores conectados"
    Write-Host "    --init              Cria arquivo de configuracao"
    Write-Host "    --help              Mostra esta ajuda"
    Write-Host ""
    Write-Host "  Config: $ConfigFile"
    Write-Host ""
}
else {
    # Treat as profile name
    Start-Profile -TargetProfile $scriptArgs[0]
}
