#Requires -Version 5.1
<#
.SYNOPSIS
    Encontra arquivos duplicados por hash SHA-256.
.DESCRIPTION
    Escaneia recursivamente, agrupa por tamanho (pre-filtro), depois calcula
    hash SHA-256 apenas dos candidatos com tamanho identico. Mostra grupos de
    duplicatas com espaco recuperavel. Nenhum arquivo e deletado.
    Ignora: node_modules, .git, __pycache__, .venv
.PARAMETER Path
    Caminho da pasta a escanear. Padrao: diretorio atual.
.PARAMETER MinSize
    Tamanho minimo em bytes. Padrao: 1024 (1 KB).
.EXAMPLE
    .\cacar-duplicatas.ps1
    .\cacar-duplicatas.ps1 "$env:USERPROFILE\Documents" 4096
.NOTES
    Caso a execucao seja bloqueada, rode:
      Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
#>

param(
    [string]$Path = ".",
    [long]$MinSize = 1024
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
        return "{0:N1} MB" -f ($Bytes / 1MB)
    }
    elseif ($Bytes -ge 1KB) {
        return "{0:N0} KB" -f ($Bytes / 1KB)
    }
    else {
        return "$Bytes B"
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

# Diretorios a ignorar
$SkipDirs = @('node_modules', '.git', '__pycache__', '.venv', 'venv')

# ── Passo 1: Listar arquivos ──

Write-Host ""
Write-Host "  Escaneando " -NoNewline
Write-Host "$Target" -NoNewline -ForegroundColor White
Write-Host "..."
$minSizeStr = Format-HumanSize -Bytes $MinSize
Write-Host "  (ignorando arquivos < $minSizeStr)" -ForegroundColor DarkGray
Write-Host ""

Write-Host "`r  Listando arquivos..." -NoNewline

$allFiles = Get-ChildItem -Path $Target -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        $dominated = $false
        foreach ($skip in $SkipDirs) {
            if ($_.FullName -match "[\\/]${skip}[\\/]") {
                $dominated = $true
                break
            }
        }
        (-not $dominated) -and ($_.Length -ge $MinSize) -and ($_.Name -notlike '.*')
    }

$totalFiles = @($allFiles).Count
Write-Host "`r  " -NoNewline
Write-Host "$totalFiles" -NoNewline -ForegroundColor White
Write-Host " arquivos encontrados                    "
Write-Host ""

if ($totalFiles -eq 0) {
    Write-Host "  Nenhum arquivo encontrado." -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "  Pressione Enter para sair"
    exit 0
}

# ── Passo 2: Agrupar por tamanho (pre-filtro) ──

Write-Host "`r  Agrupando por tamanho..." -NoNewline

$sizeGroups = $allFiles | Group-Object -Property Length | Where-Object { $_.Count -gt 1 }

$candidates = @()
foreach ($group in $sizeGroups) {
    $candidates += $group.Group
}

$candidateCount = $candidates.Count

if ($candidateCount -eq 0) {
    Write-Host ""
    Write-Host "  Nenhuma duplicata encontrada." -ForegroundColor Green
    Write-Host ""
    Read-Host "  Pressione Enter para sair"
    exit 0
}

Write-Host "`r  " -NoNewline
Write-Host "$candidateCount" -NoNewline -ForegroundColor White
Write-Host " candidatos a duplicata (mesmo tamanho)         "

# ── Passo 3: Calcular hashes ──

$hashed = 0
$hashResults = @()

foreach ($file in $candidates) {
    $hashed++
    if ($hashed % 50 -eq 0) {
        Write-Host "`r  Calculando hashes... $hashed/$candidateCount" -NoNewline
    }
    try {
        $hash = (Get-FileHash -Path $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
        $hashResults += [PSCustomObject]@{
            Hash = $hash
            Size = $file.Length
            Path = $file.FullName
        }
    }
    catch {
        # Arquivo inacessivel, pular
    }
}

Write-Host "`r  Calculando hashes... " -NoNewline
Write-Host "feito" -ForegroundColor Green
Write-Host "                              "
Write-Host ""

# ── Passo 4: Encontrar hashes duplicados ──

$dupGroups = $hashResults | Group-Object -Property Hash | Where-Object { $_.Count -gt 1 }

if ($dupGroups.Count -eq 0) {
    Write-Host "  Nenhuma duplicata encontrada." -ForegroundColor Green
    Write-Host ""
    Read-Host "  Pressione Enter para sair"
    exit 0
}

# ── Passo 5: Exibir resultados ──

Write-Host "  Duplicatas encontradas:" -ForegroundColor White
Write-Host ""

$groupNum = 0
$totalDupFiles = 0
$totalRecoverable = [long]0

foreach ($group in $dupGroups) {
    $groupNum++
    $copies = $group.Count
    $firstSize = $group.Group[0].Size
    $recoverable = [long]$firstSize * ($copies - 1)
    $totalRecoverable += $recoverable
    $totalDupFiles += $copies

    $recoverStr = Format-HumanSize -Bytes $recoverable
    $shortHash = $group.Name.Substring(0, 16)

    Write-Host "  " -NoNewline
    Write-Host "Grupo $groupNum" -NoNewline -ForegroundColor Yellow
    Write-Host " -- $copies copias -- " -NoNewline
    Write-Host "$recoverStr" -NoNewline -ForegroundColor Red
    Write-Host " recuperaveis"

    Write-Host "  SHA-256: ${shortHash}..." -ForegroundColor DarkGray

    foreach ($item in $group.Group) {
        $displayPath = Get-ShortPath -FullPath $item.Path
        Write-Host "    $displayPath"
    }
    Write-Host ""
}

# ── Resumo ──

$totalRecoverStr = Format-HumanSize -Bytes $totalRecoverable

Write-Host "  -----------------------------------------------"
Write-Host "  " -NoNewline
Write-Host "Resumo:" -ForegroundColor White
Write-Host "  Grupos de duplicatas:  " -NoNewline
Write-Host "$groupNum" -ForegroundColor White
Write-Host "  Arquivos duplicados:   " -NoNewline
Write-Host "$totalDupFiles" -ForegroundColor White
Write-Host "  Espaco recuperavel:    " -NoNewline
Write-Host "$totalRecoverStr" -ForegroundColor Red
Write-Host "  -----------------------------------------------"
Write-Host ""
Write-Host "  Nenhum arquivo foi deletado. Revise a lista acima e delete manualmente." -ForegroundColor DarkGray
Write-Host ""
Read-Host "  Pressione Enter para sair"
