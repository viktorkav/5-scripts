#Requires -Version 5.1
<#
.SYNOPSIS
    Mostra os maiores arquivos e pastas do disco.
.DESCRIPTION
    Escaneia recursivamente (ate 4 niveis) para encontrar os maiores arquivos
    e pastas. Formata tamanhos em KB/MB/GB com cores para itens grandes.
    Mostra resumo de uso do disco.
.PARAMETER Path
    Caminho da pasta a escanear. Padrao: pasta do usuario.
.PARAMETER Count
    Quantidade de itens a mostrar. Padrao: 20.
.EXAMPLE
    .\scanner-espaco.ps1
    .\scanner-espaco.ps1 "$env:USERPROFILE" 10
.NOTES
    Caso a execucao seja bloqueada, rode:
      Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
#>

param(
    [string]$Path = $env:USERPROFILE,
    [int]$Count = 20
)

# ── Resolver caminho ──

$Target = (Resolve-Path -Path $Path -ErrorAction SilentlyContinue).Path
if (-not $Target -or -not (Test-Path -Path $Target -PathType Container)) {
    Write-Host "Erro: '$Path' nao e um diretorio valido." -ForegroundColor Red
    Read-Host "  Pressione Enter para sair"
    exit 1
}

# ── Funcoes auxiliares ──

function Format-HumanSize {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) {
        return "{0:N1} GB" -f ($Bytes / 1GB)
    }
    elseif ($Bytes -ge 1MB) {
        return "{0:N0} MB" -f ($Bytes / 1MB)
    }
    elseif ($Bytes -ge 1KB) {
        return "{0:N0} KB" -f ($Bytes / 1KB)
    }
    else {
        return "$Bytes B"
    }
}

function Write-ColoredSize {
    param(
        [string]$SizeStr,
        [long]$Bytes
    )
    if ($Bytes -ge 5GB) {
        Write-Host $SizeStr.PadLeft(10) -NoNewline -ForegroundColor Red
    }
    elseif ($Bytes -ge 1GB) {
        Write-Host $SizeStr.PadLeft(10) -NoNewline -ForegroundColor Yellow
    }
    else {
        Write-Host $SizeStr.PadLeft(10) -NoNewline
    }
}

function Get-ShortPath {
    param([string]$FullPath)
    $home = $env:USERPROFILE
    if ($FullPath.StartsWith($home)) {
        return "~" + $FullPath.Substring($home.Length)
    }
    return $FullPath
}

# ── Main ──

Write-Host ""
Write-Host "  Escaneando " -NoNewline
Write-Host "$Target" -NoNewline -ForegroundColor White
Write-Host "..."
Write-Host "  (isso pode levar alguns segundos)" -ForegroundColor DarkGray
Write-Host ""

# ── Top pastas ──

Write-Host "  $Count maiores pastas:" -ForegroundColor White
Write-Host ""

$topDirs = Get-ChildItem -Path $Target -Directory -ErrorAction SilentlyContinue |
    ForEach-Object {
        $dirSize = (Get-ChildItem -Path $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        if ($null -eq $dirSize) { $dirSize = 0 }
        [PSCustomObject]@{
            Path = $_.FullName
            Size = [long]$dirSize
        }
    } |
    Sort-Object -Property Size -Descending |
    Select-Object -First $Count

if ($topDirs -and $topDirs.Count -gt 0) {
    foreach ($dir in $topDirs) {
        if ($dir.Size -eq 0) { continue }
        $sizeStr = Format-HumanSize -Bytes $dir.Size
        Write-Host "  " -NoNewline
        Write-ColoredSize -SizeStr $sizeStr -Bytes $dir.Size
        $displayPath = Get-ShortPath -FullPath $dir.Path
        Write-Host "  $displayPath"
    }
}
else {
    Write-Host "  (nenhuma subpasta encontrada)" -ForegroundColor DarkGray
}

Write-Host ""

# ── Top arquivos ──

Write-Host "  $Count maiores arquivos:" -ForegroundColor White
Write-Host ""

$topFiles = Get-ChildItem -Path $Target -Recurse -File -Depth 4 -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike '.*' } |
    Sort-Object -Property Length -Descending |
    Select-Object -First $Count

if ($topFiles -and $topFiles.Count -gt 0) {
    foreach ($file in $topFiles) {
        $sizeStr = Format-HumanSize -Bytes $file.Length
        Write-Host "  " -NoNewline
        Write-ColoredSize -SizeStr $sizeStr -Bytes $file.Length
        $displayPath = Get-ShortPath -FullPath $file.FullName
        Write-Host "  $displayPath"
    }
}
else {
    Write-Host "  (nenhum arquivo encontrado)" -ForegroundColor DarkGray
}

Write-Host ""

# ── Resumo do disco ──

$driveLetter = (Split-Path -Path $Target -Qualifier).TrimEnd(':')
$driveInfo = Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue

if ($driveInfo) {
    $usedBytes = $driveInfo.Used
    $freeBytes = $driveInfo.Free
    $totalBytes = $usedBytes + $freeBytes
    if ($totalBytes -gt 0) {
        $pct = [math]::Round(($usedBytes / $totalBytes) * 100)
        $usedStr = Format-HumanSize -Bytes $usedBytes
        $totalStr = Format-HumanSize -Bytes $totalBytes
        Write-Host "  " -NoNewline
        Write-Host "Disco:" -NoNewline -ForegroundColor White
        Write-Host " ${usedStr} usados de ${totalStr} (${pct}%)"
    }
}

Write-Host ""
Read-Host "  Pressione Enter para sair"
