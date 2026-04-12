#Requires -Version 5.1
<#
.SYNOPSIS
    Organiza arquivos por tipo de extensao em subdiretorios.
.DESCRIPTION
    Move arquivos da raiz da pasta alvo para subpastas categorizadas:
    Imagens, Documentos, Videos, Audio, Instaladores, Compactados, Codigo, Outros.
    Conflitos de nome sao resolvidos com sufixo (1), (2), etc.
.PARAMETER Path
    Caminho da pasta a organizar. Padrao: diretorio atual.
.EXAMPLE
    .\organizar-downloads.ps1
    .\organizar-downloads.ps1 "$env:USERPROFILE\Downloads"
.NOTES
    Caso a execucao seja bloqueada, rode:
      Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
#>

param(
    [string]$Path = "."
)

# ── Resolver caminho ──

$Target = (Resolve-Path -Path $Path -ErrorAction SilentlyContinue).Path
if (-not $Target -or -not (Test-Path -Path $Target -PathType Container)) {
    Write-Host "Erro: '$Path' nao e um diretorio valido." -ForegroundColor Red
    exit 1
}

# ── Mapeamento de extensoes para categorias ──

$CategoryMap = @{
    # Imagens
    'jpg' = 'Imagens'; 'jpeg' = 'Imagens'; 'png' = 'Imagens'; 'gif' = 'Imagens'
    'bmp' = 'Imagens'; 'svg' = 'Imagens'; 'webp' = 'Imagens'; 'ico' = 'Imagens'
    'tiff' = 'Imagens'; 'heic' = 'Imagens'; 'heif' = 'Imagens'; 'raw' = 'Imagens'
    'cr2' = 'Imagens'; 'nef' = 'Imagens'; 'avif' = 'Imagens'
    # Documentos
    'pdf' = 'Documentos'; 'doc' = 'Documentos'; 'docx' = 'Documentos'
    'xls' = 'Documentos'; 'xlsx' = 'Documentos'; 'ppt' = 'Documentos'
    'pptx' = 'Documentos'; 'odt' = 'Documentos'; 'ods' = 'Documentos'
    'odp' = 'Documentos'; 'rtf' = 'Documentos'; 'tex' = 'Documentos'
    'pages' = 'Documentos'; 'numbers' = 'Documentos'; 'key' = 'Documentos'
    'epub' = 'Documentos'
    # Videos
    'mp4' = 'Videos'; 'mov' = 'Videos'; 'avi' = 'Videos'; 'mkv' = 'Videos'
    'wmv' = 'Videos'; 'flv' = 'Videos'; 'webm' = 'Videos'; 'm4v' = 'Videos'
    'mpg' = 'Videos'; 'mpeg' = 'Videos'; 'ts' = 'Videos'
    # Audio
    'mp3' = 'Audio'; 'wav' = 'Audio'; 'flac' = 'Audio'; 'aac' = 'Audio'
    'ogg' = 'Audio'; 'wma' = 'Audio'; 'm4a' = 'Audio'; 'opus' = 'Audio'
    'aiff' = 'Audio'; 'alac' = 'Audio'
    # Instaladores
    'dmg' = 'Instaladores'; 'pkg' = 'Instaladores'; 'exe' = 'Instaladores'
    'msi' = 'Instaladores'; 'deb' = 'Instaladores'; 'rpm' = 'Instaladores'
    'appimage' = 'Instaladores'; 'snap' = 'Instaladores'; 'flatpak' = 'Instaladores'
    # Compactados
    'zip' = 'Compactados'; 'rar' = 'Compactados'; '7z' = 'Compactados'
    'tar' = 'Compactados'; 'gz' = 'Compactados'; 'bz2' = 'Compactados'
    'xz' = 'Compactados'; 'tgz' = 'Compactados'; 'zst' = 'Compactados'
    # Codigo
    'py' = 'Codigo'; 'js' = 'Codigo'; 'html' = 'Codigo'; 'css' = 'Codigo'
    'sh' = 'Codigo'; 'json' = 'Codigo'; 'xml' = 'Codigo'; 'yaml' = 'Codigo'
    'yml' = 'Codigo'; 'md' = 'Codigo'; 'csv' = 'Codigo'; 'sql' = 'Codigo'
    'rb' = 'Codigo'; 'go' = 'Codigo'; 'rs' = 'Codigo'; 'java' = 'Codigo'
    'c' = 'Codigo'; 'cpp' = 'Codigo'; 'h' = 'Codigo'; 'swift' = 'Codigo'
    'kt' = 'Codigo'; 'lua' = 'Codigo'; 'r' = 'Codigo'; 'ps1' = 'Codigo'
}

# ── Scan e organizacao ──

Write-Host ""
Write-Host "  Escaneando " -NoNewline
Write-Host "$Target" -NoNewline -ForegroundColor White
Write-Host "..."

$Moved = 0
$Counts = @{}

$Files = Get-ChildItem -Path $Target -File -ErrorAction SilentlyContinue |
    Where-Object { -not $_.Name.StartsWith('.') }

foreach ($file in $Files) {
    $ext = $file.Extension.TrimStart('.').ToLower()

    # Sem extensao
    if ([string]::IsNullOrEmpty($ext)) {
        $category = 'Outros'
    }
    elseif ($CategoryMap.ContainsKey($ext)) {
        $category = $CategoryMap[$ext]
    }
    else {
        $category = 'Outros'
    }

    # Criar pasta destino
    $destDir = Join-Path -Path $Target -ChildPath $category
    if (-not (Test-Path -Path $destDir)) {
        New-Item -Path $destDir -ItemType Directory -Force | Out-Null
    }

    # Resolver conflito de nomes
    $destFile = Join-Path -Path $destDir -ChildPath $file.Name
    if (Test-Path -Path $destFile) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $extension = $file.Extension
        $n = 1
        do {
            $newName = "${baseName} (${n})${extension}"
            $destFile = Join-Path -Path $destDir -ChildPath $newName
            $n++
        } while (Test-Path -Path $destFile)
    }

    Move-Item -Path $file.FullName -Destination $destFile -Force
    Write-Host "  " -NoNewline
    Write-Host ([char]0x2192) -NoNewline -ForegroundColor DarkGray
    Write-Host " $($file.Name) " -NoNewline
    Write-Host ([char]0x2192) -NoNewline -ForegroundColor DarkGray
    Write-Host " ${category}/" -ForegroundColor Cyan

    if ($Counts.ContainsKey($category)) {
        $Counts[$category]++
    }
    else {
        $Counts[$category] = 1
    }
    $Moved++
}

Write-Host ""

if ($Moved -eq 0) {
    Write-Host "  Nenhum arquivo pra organizar." -ForegroundColor DarkGray
}
else {
    Write-Host "  $Moved arquivos organizados:" -ForegroundColor Green

    Write-Host ""
    foreach ($entry in $Counts.GetEnumerator() | Sort-Object -Property Value -Descending) {
        $label = "$($entry.Key):".PadRight(16)
        Write-Host "  ${label}" -NoNewline
        Write-Host "$($entry.Value)" -NoNewline -ForegroundColor White
        Write-Host " arquivos"
    }
}

Write-Host ""
