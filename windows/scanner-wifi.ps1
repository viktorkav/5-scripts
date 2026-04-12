#Requires -Version 5.1
<#
.SYNOPSIS
    Escaneia redes Wi-Fi e sugere o melhor canal.
.DESCRIPTION
    Usa 'netsh wlan show networks mode=bssid' para listar redes visiveis,
    constroi mapa de congestionamento por canal, e recomenda o canal
    nao-sobreposto menos congestionado (1, 6 ou 11 para 2.4 GHz).
    Mostra info da rede atual com 'netsh wlan show interfaces'.
.EXAMPLE
    .\scanner-wifi.ps1
.NOTES
    Requer Wi-Fi ativo. Deve ser executado em Windows.
    Caso a execucao seja bloqueada, rode:
      Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
#>

# ── Funcoes auxiliares ──

function Get-SignalBar {
    param([int]$Count)
    $filled = [math]::Min($Count, 8)
    $empty = 8 - $filled
    return ([string][char]0x2588 * $filled) + ([string][char]0x2591 * $empty)
}

# ── Detectar rede atual ──

Write-Host ""
Write-Host "  Escaneando redes Wi-Fi..."
Write-Host ""

$currentSSID = ""
$currentChannel = ""

$interfaceOutput = netsh wlan show interfaces 2>$null
if ($interfaceOutput) {
    foreach ($line in $interfaceOutput) {
        if ($line -match '^\s*SSID\s*:\s*(.+)$') {
            $currentSSID = $Matches[1].Trim()
        }
        if ($line -match '^\s*Canal\s*:\s*(\d+)' -or $line -match '^\s*Channel\s*:\s*(\d+)') {
            $currentChannel = $Matches[1].Trim()
        }
    }
}

# ── Scan de redes ──

$networkOutput = netsh wlan show networks mode=bssid 2>$null
if (-not $networkOutput) {
    Write-Host "  Nenhuma rede encontrada." -ForegroundColor Red
    Write-Host "  Verifique se o Wi-Fi esta ligado." -ForegroundColor DarkGray
    exit 1
}

# Parse da saida do netsh
# Formato esperado (pode variar por idioma do SO):
#   SSID 1 : NetworkName
#   ...
#   Canal / Channel : 6
#   ...

$networks = @()
$currentNet = @{ SSID = ""; Channel = 0 }

foreach ($line in $networkOutput) {
    # SSID (pular BSSID)
    if ($line -match '^\s*SSID\s+\d*\s*:\s*(.*)$' -and $line -notmatch 'BSSID') {
        $ssid = $Matches[1].Trim()
        if ($ssid -ne "") {
            $currentNet = @{ SSID = $ssid; Channel = 0 }
        }
    }
    # Canal (pt-BR: "Canal", en: "Channel")
    if ($line -match '^\s*(Canal|Channel)\s*:\s*(\d+)') {
        $ch = [int]$Matches[2]
        if ($currentNet.SSID -ne "" -and $ch -gt 0) {
            $networks += [PSCustomObject]@{
                SSID    = $currentNet.SSID
                Channel = $ch
            }
        }
    }
}

if ($networks.Count -eq 0) {
    Write-Host "  Nenhuma rede encontrada." -ForegroundColor Red
    Write-Host "  Verifique se o Wi-Fi esta ligado." -ForegroundColor DarkGray
    exit 1
}

# ── 2.4 GHz ──

Write-Host "  Redes encontradas (2.4 GHz):" -ForegroundColor White
Write-Host ""

$header = "  {0,-6} {1,-6} {2,-10} {3}" -f "Canal", "Redes", "Sinal", "Nomes"
Write-Host $header
$separator = "  {0,-6} {1,-6} {2,-10} {3}" -f ([string][char]0x2500 * 5), ([string][char]0x2500 * 5), ([string][char]0x2500 * 8), ([string][char]0x2500 * 30)
Write-Host $separator

$best24Ch = ""
$best24Count = 999

$channels24 = 1..13

foreach ($ch in $channels24) {
    $chNetworks = $networks | Where-Object { $_.Channel -eq $ch }
    $count = @($chNetworks).Count
    $names = ($chNetworks | Select-Object -ExpandProperty SSID -Unique) -join ", "

    # Rastrear melhor canal nao-sobreposto
    if ($ch -in @(1, 6, 11)) {
        if ($count -lt $best24Count) {
            $best24Count = $count
            $best24Ch = $ch
        }
    }

    # Pular canais vazios que nao sao 1, 6 ou 11
    if ($count -eq 0 -and $ch -notin @(1, 6, 11)) {
        continue
    }

    $bar = Get-SignalBar -Count $count

    # Destacar rede do usuario
    if ($currentSSID -and $names -match [regex]::Escape($currentSSID)) {
        $names = $names -replace [regex]::Escape($currentSSID), $currentSSID
    }

    $chStr = "$ch".PadLeft(4)
    $countStr = "$count"

    if ($count -ge 5) {
        Write-Host "  $chStr    $countStr    $bar  " -NoNewline -ForegroundColor Red
        Write-Host "$names" -ForegroundColor Red
    }
    elseif ($count -ge 3) {
        Write-Host "  $chStr    $countStr    $bar  " -NoNewline -ForegroundColor Yellow
        Write-Host "$names" -ForegroundColor Yellow
    }
    elseif ($count -eq 0) {
        Write-Host "  $chStr    $countStr    $bar  " -NoNewline
        Write-Host "(vazio)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "  $chStr    $countStr    $bar  $names"
    }
}

Write-Host ""

# ── 5 GHz ──

$channels5 = @(36, 40, 44, 48, 52, 56, 60, 64, 149, 153, 157, 161, 165)
$has5GHz = $false
$best5Ch = ""
$best5Count = 999

foreach ($ch in $channels5) {
    $count = @($networks | Where-Object { $_.Channel -eq $ch }).Count
    if ($count -gt 0) { $has5GHz = $true }
}

if ($has5GHz) {
    Write-Host "  Redes encontradas (5 GHz):" -ForegroundColor White
    Write-Host ""
    Write-Host $header
    Write-Host $separator

    foreach ($ch in $channels5) {
        $chNetworks = $networks | Where-Object { $_.Channel -eq $ch }
        $count = @($chNetworks).Count
        $names = ($chNetworks | Select-Object -ExpandProperty SSID -Unique) -join ", "

        if ($count -eq 0) {
            if ($best5Ch -eq "") {
                $best5Ch = $ch
                $best5Count = 0
            }
            continue
        }

        if ($count -lt $best5Count) {
            $best5Count = $count
            $best5Ch = $ch
        }

        $bar = Get-SignalBar -Count $count
        $chStr = "$ch".PadLeft(4)
        $countStr = "$count"

        Write-Host "  $chStr    $countStr    $bar  $names"
    }

    Write-Host ""
}

# ── Diagnostico ──

Write-Host "  -----------------------------------------------"
Write-Host "  Diagnostico:" -ForegroundColor White
Write-Host ""

if ($currentSSID) {
    Write-Host "  Sua rede:        " -NoNewline
    Write-Host "$currentSSID" -ForegroundColor Green
}
else {
    Write-Host "  Sua rede:        " -NoNewline
    Write-Host "(nao detectada)" -ForegroundColor DarkGray
}

if ($currentChannel) {
    $currentCount = @($networks | Where-Object { $_.Channel -eq [int]$currentChannel }).Count
    Write-Host "  Canal atual:     " -NoNewline
    if ($currentCount -ge 5) {
        Write-Host "$currentChannel -- CONGESTIONADO ($currentCount redes)" -ForegroundColor Red
    }
    elseif ($currentCount -ge 3) {
        Write-Host "$currentChannel -- MODERADO ($currentCount redes)" -ForegroundColor Yellow
    }
    else {
        Write-Host "$currentChannel -- BOM ($currentCount redes)" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "  Recomendacao:" -ForegroundColor White

if ($best24Ch) {
    Write-Host "  Canal ideal 2.4: " -NoNewline
    if ($best24Count -eq 0) {
        Write-Host "$best24Ch -- LIVRE" -ForegroundColor Green
    }
    else {
        Write-Host "$best24Ch ($best24Count redes -- menos congestionado)" -ForegroundColor Green
    }
}

if ($best5Ch) {
    Write-Host "  Canal ideal 5G:  " -NoNewline
    if ($best5Count -eq 0) {
        Write-Host "$best5Ch -- LIVRE" -ForegroundColor Green
    }
    else {
        Write-Host "$best5Ch ($best5Count redes -- menos congestionado)" -ForegroundColor Green
    }
}

Write-Host "  -----------------------------------------------"
Write-Host ""
Write-Host "  Acesse o painel do roteador (geralmente 192.168.1.1)" -ForegroundColor DarkGray
Write-Host "  e altere o canal nas configuracoes de Wi-Fi." -ForegroundColor DarkGray
Write-Host ""
