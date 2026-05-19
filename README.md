# powershell-setup

Automacao de setup do PowerShell 7 em Windows em duas etapas:
1. Instalar e preparar ambiente (winget, pwsh, Oh My Posh, ferramentas essenciais).
2. Publicar profile e configuracoes do repositorio para o destino derivado de $PROFILE.

## Estrutura

- Microsoft.PowerShell_profile.ps1
- conf.d/
- Modules/
- Scripts/stage1-install.ps1
- Scripts/stage2-deploy.ps1
- Scripts/test-setup.ps1

## Pre-requisitos

- Windows 10/11.
- PowerShell 5.1 ou PowerShell 7 para iniciar os scripts.
- Conexao com internet para winget/PSGallery.

Observacao: o fluxo tenta elevar privilegio apenas quando necessario.

## Etapa 1 - Bootstrap do ambiente

Executa instalacao/atualizacao de pacotes via winget:

- Microsoft.PowerShell
- JanDeDobbeleer.OhMyPosh
- JetBrains.JetBrainsMono.NerdFont
- eza, fzf, zoxide, bat, fd, ripgrep
- git, gh, 7zip, neovim

Comando:

```powershell
pwsh -ExecutionPolicy Bypass -File .\Scripts\stage1-install.ps1
```

Opcoes uteis:

```powershell
# Simular sem alterar
pwsh -ExecutionPolicy Bypass -File .\Scripts\stage1-install.ps1 -DryRun

# Pular fonte Nerd Font
pwsh -ExecutionPolicy Bypass -File .\Scripts\stage1-install.ps1 -SkipNerdFont

# Nao alterar ExecutionPolicy
pwsh -ExecutionPolicy Bypass -File .\Scripts\stage1-install.ps1 -SkipExecutionPolicy
```

## Etapa 2 - Deploy de profile e configuracoes

Publica os arquivos do repositorio para o local calculado automaticamente por $PROFILE:

- Microsoft.PowerShell_profile.ps1
- conf.d/*
- Modules/*

Comando:

```powershell
pwsh -ExecutionPolicy Bypass -File .\Scripts\stage2-deploy.ps1
```

Opcoes uteis:

```powershell
# Simular sem alterar
pwsh -ExecutionPolicy Bypass -File .\Scripts\stage2-deploy.ps1 -DryRun

# Espelhar destino removendo extras (uso com cautela)
pwsh -ExecutionPolicy Bypass -File .\Scripts\stage2-deploy.ps1 -Mirror

# Forcar profile especifico
pwsh -ExecutionPolicy Bypass -File .\Scripts\stage2-deploy.ps1 -ProfilePath "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
```

Durante a etapa 2, se ja existir profile no destino, e criado backup versionado com timestamp.

## Etapa 3 - Validacao final

```powershell
pwsh -ExecutionPolicy Bypass -File .\Scripts\test-setup.ps1
```

O teste valida:

- Estrutura publicada no destino de $PROFILE.
- Disponibilidade de comandos principais.
- Carregamento do profile sem erro fatal.

## Fluxo recomendado

```powershell
pwsh -ExecutionPolicy Bypass -File .\Scripts\stage1-install.ps1
pwsh -ExecutionPolicy Bypass -File .\Scripts\stage2-deploy.ps1
pwsh -ExecutionPolicy Bypass -File .\Scripts\test-setup.ps1
```

## Troubleshooting rapido

- winget nao encontrado:
	- Atualize/instale App Installer no Windows.
	- Abra novo terminal e rode novamente a etapa 1.
- Oh My Posh sem icones corretos:
	- Configure o terminal para usar Nerd Font (JetBrainsMono Nerd Font).
- Policy bloqueando scripts:
	- Use -ExecutionPolicy Bypass no comando de execucao.
	- Opcionalmente rode Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned.
- Ambiente corporativo sem Store:
	- Execute etapa 1 em modo manual, instalando dependencias aprovadas pela TI.
