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

> **Qual versao eu uso?**
>
> | Seu sistema | Pasta dos scripts |
> |-------------|-------------------|
> | **Windows** | `windows/` — use os arquivos `.bat` (clique duplo) |
> | **macOS**   | Raiz do projeto — arquivos `.sh` |
> | **Linux**   | `linux/` — arquivos `.sh` |
>
> Se voce esta no **Windows**, use apenas os arquivos da pasta `windows/`.
> Os arquivos `.sh` da raiz sao para macOS e **nao funcionam no Windows**.

## Instalacao

### Windows

**Opcao 1 — Baixar ZIP (mais facil)**

1. Clique no botao verde **Code** no topo desta pagina
2. Clique em **Download ZIP**
3. Extraia o ZIP em qualquer lugar (ex: sua area de trabalho)
4. Abra a pasta `windows`
5. Clique duas vezes no script `.bat` que quiser usar

**Opcao 2 — Via terminal (PowerShell)**

```powershell
git clone https://github.com/viktorkav/5-scripts.git
cd 5-scripts\windows
```

Depois e so clicar duas vezes no `.bat` desejado, ou rodar pelo terminal:

```powershell
.\organizar-downloads.bat
.\scanner-espaco.bat
```

> **Nota:** Os arquivos `.bat` ja cuidam das permissoes automaticamente.
> Voce nao precisa alterar nenhuma configuracao do PowerShell.

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

## Uso

### organizar-downloads

Organiza arquivos por extensao em subpastas categorizadas.

**Windows (clique duplo):** Abra `organizar-downloads.bat` — organiza a pasta atual.

**Terminal:**
```bash
organizar-downloads              # organiza a pasta atual
organizar-downloads ~/Downloads  # organiza ~/Downloads
```

Categorias: Imagens, Documentos, Videos, Audio, Instaladores, Compactados, Codigo, Outros.

### scanner-espaco

Mostra os maiores arquivos e pastas, com resumo de disco.

**Windows (clique duplo):** Abra `scanner-espaco.bat` — escaneia sua pasta de usuario.

**Terminal:**
```bash
scanner-espaco            # escaneia a pasta atual
scanner-espaco ~ 30       # top 30 em ~/
```

### cacar-duplicatas

Encontra duplicatas por SHA-256. Nenhum arquivo e deletado.

**Windows (clique duplo):** Abra `cacar-duplicatas.bat` — escaneia a pasta atual.

**Terminal:**
```bash
cacar-duplicatas                 # escaneia a pasta atual
cacar-duplicatas ~/Fotos 4096    # minimo 4 KB
```

Pre-filtra por tamanho antes de calcular hashes — rapido mesmo em pastas grandes. Ignora `node_modules`, `.venv`, `.git`, `__pycache__`.

### scanner-wifi

Escaneia redes proximas e recomenda o canal menos congestionado.

**Windows (clique duplo):** Abra `scanner-wifi.bat`.

**Terminal:**
```bash
scanner-wifi
```

Mostra SSID, canal, sinal, seguranca e mapa de congestionamento por canal (2.4 GHz e 5 GHz).

### setup-workspace

Posiciona janelas automaticamente em multiplos monitores usando perfis.

**Windows (clique duplo):** Abra `setup-workspace.bat` — abre o menu interativo.

**Terminal:**
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
│   ├── organizar-downloads.bat   ← clique duplo pra rodar
│   ├── scanner-espaco.bat
│   ├── cacar-duplicatas.bat
│   ├── scanner-wifi.bat
│   ├── setup-workspace.bat
│   ├── organizar-downloads.ps1   (scripts PowerShell)
│   ├── scanner-espaco.ps1
│   ├── cacar-duplicatas.ps1
│   ├── scanner-wifi.ps1
│   └── setup-workspace.ps1
├── LICENSE
└── README.md
```

## Problemas comuns

**Windows: "O script nao abre" / "A janela fecha sozinha"**
Use os arquivos `.bat` (nao os `.ps1`). Clique duplo no `.bat` e o script vai rodar corretamente.

**Windows: "Nao tenho permissao para mover arquivos"**
Isso pode acontecer com arquivos que tem nomes muito longos. O script `organizar-downloads` mostra quais arquivos falharam — voce pode renomea-los manualmente e rodar de novo.

**Baixei os arquivos errados**
Se voce esta no Windows, use apenas os arquivos da pasta `windows/`. Os arquivos `.sh` na raiz do projeto sao para macOS.

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
