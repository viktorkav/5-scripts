# 5 Scripts

Cinco scripts de produtividade para o terminal — organização de arquivos, limpeza de disco, detecção de redes Wi-Fi, gerenciamento de workspace multi-monitor e caça de duplicatas. Versões para **macOS**, **Linux** e **Windows**.

## Scripts

| Script | O que faz |
|--------|-----------|
| **organizar-downloads** | Organiza arquivos soltos em subpastas por tipo (Imagens, Documentos, Videos, Audio, etc.) |
| **scanner-espaco** | Mostra os maiores arquivos e pastas do disco com resumo de uso |
| **cacar-duplicatas** | Encontra arquivos duplicados por hash SHA-256 sem deletar nada |
| **scanner-wifi** | Escaneia redes Wi-Fi próximas e recomenda o melhor canal |
| **setup-workspace** | Posiciona janelas em múltiplos monitores com perfis salvos |

## Instalacao

### macOS

```bash
git clone https://github.com/viktorkav/5-scripts.git
cd 5-scripts

# Tornar executáveis
chmod +x *.sh

# (Opcional) Acessar de qualquer lugar
mkdir -p ~/bin
for s in *.sh; do ln -sf "$PWD/$s" ~/bin/"${s%.sh}"; done
# Adicione ~/bin ao PATH se ainda não estiver:
# echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
```

### Linux

```bash
git clone https://github.com/viktorkav/5-scripts.git
cd 5-scripts/linux

chmod +x *.sh

# (Opcional) Acessar de qualquer lugar
mkdir -p ~/bin
for s in *.sh; do ln -sf "$PWD/$s" ~/bin/"${s%.sh}"; done
```

### Windows (PowerShell)

```powershell
git clone https://github.com/viktorkav/5-scripts.git
cd 5-scripts\windows

# Se necessário, libere execução de scripts:
# Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Uso

### organizar-downloads

Organiza arquivos por extensao em subpastas categorizadas.

```bash
organizar-downloads              # organiza a pasta atual
organizar-downloads ~/Downloads  # organiza ~/Downloads
```

Categorias: Imagens, Documentos, Videos, Audio, Instaladores, Compactados, Codigo, Outros.

### scanner-espaco

Mostra os maiores arquivos e pastas, com resumo de disco.

```bash
scanner-espaco            # escaneia a pasta atual
scanner-espaco ~ 30       # top 30 em ~/
```

### cacar-duplicatas

Encontra duplicatas por SHA-256. Nenhum arquivo e deletado.

```bash
cacar-duplicatas                 # escaneia a pasta atual
cacar-duplicatas ~/Fotos 4096    # minimo 4 KB
```

Pre-filtra por tamanho antes de calcular hashes — rapido mesmo em pastas grandes. Ignora `node_modules`, `.venv`, `.git`, `__pycache__`.

### scanner-wifi

Escaneia redes proximas e recomenda o canal menos congestionado.

```bash
scanner-wifi
```

Mostra SSID, canal, sinal, seguranca e mapa de congestionamento por canal (2.4 GHz e 5 GHz).

### setup-workspace

Posiciona janelas automaticamente em multiplos monitores usando perfis.

```bash
setup-workspace              # menu interativo
setup-workspace padrao       # carrega o perfil "padrao"
setup-workspace --save work  # salva o layout atual como "work"
setup-workspace --detect     # lista monitores conectados
```

O menu interativo permite carregar um perfil existente ou capturar o layout atual das janelas. A captura detecta automaticamente em qual monitor cada janela esta e calcula as posicoes em porcentagem.

**Config:** `~/.config/workspace-profiles.conf`

```ini
# Mapeamento de monitores
monitor.1=LU28R55
monitor.2=LG HDR 4K
monitor.3=Built-in Retina

# perfil|App|monitor|posicao
padrao|Google Chrome|1|left
padrao|Obsidian|1|right
padrao|Discord|3|full
```

Posicoes: `left`, `right`, `full`, `top`, `bottom`, `top-left`, `top-right`, `bottom-left`, `bottom-right` ou customizada em porcentagem (`x,y,largura,altura`).

## Estrutura

```
5-scripts/
├── organizar-downloads.sh    # macOS
├── scanner-espaco.sh
├── cacar-duplicatas.sh
├── scanner-wifi.sh
├── setup-workspace.sh
├── linux/                    # Linux (bash)
│   ├── organizar-downloads.sh
│   ├── scanner-espaco.sh
│   ├── cacar-duplicatas.sh
│   ├── scanner-wifi.sh
│   └── setup-workspace.sh
├── windows/                  # Windows (PowerShell)
│   ├── organizar-downloads.ps1
│   ├── scanner-espaco.ps1
│   ├── cacar-duplicatas.ps1
│   ├── scanner-wifi.ps1
│   └── setup-workspace.ps1
├── LICENSE
└── README.md
```

## Notas por plataforma

| Recurso | macOS | Linux | Windows |
|---------|-------|-------|---------|
| Wi-Fi scan | `airport -s` | `nmcli` / `iwlist` | `netsh wlan` |
| Hashing | `shasum -a 256` | `sha256sum` | `Get-FileHash` |
| File size | `stat -f '%z'` | `stat -c '%s'` | `(Get-Item).Length` |
| Window mgmt | AppleScript + JXA | `wmctrl` + `xdotool` | Win32 API (P/Invoke) |
| Multi-monitor | NSScreen (JXA) | `xrandr` | `[System.Windows.Forms.Screen]` |

## Licenca

[MIT](LICENSE)
