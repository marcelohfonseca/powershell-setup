[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipNerdFont,
    [switch]$SkipExecutionPolicy,
    [string[]]$PackageIds = @(
        'Microsoft.PowerShell',
        'Microsoft.Sudo',
        'JanDeDobbeleer.OhMyPosh',
        'JetBrains.JetBrainsMono.NerdFont',
        'eza-community.eza',
        'junegunn.fzf',
        'jdx.mise',
        'ajeetdsouza.zoxide',
        'sharkdp.bat',
        'sharkdp.fd',
        'BurntSushi.ripgrep.MSVC',
        'Git.Git',
        'GitHub.cli',
        '7zip.7zip',
        'Neovim.Neovim'
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Invoke-Action {
    param(
        [string]$Description,
        [scriptblock]$Action
    )

    if ($DryRun) {
        Write-Host "[dry-run] $Description" -ForegroundColor Yellow
        return
    }

    & $Action
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Refresh-PathFromRegistry {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath"
}

function Ensure-Winget {
    if (Test-Command -Name 'winget') {
        return $true
    }

    Write-Warning 'winget nao foi encontrado no PATH. Tentando bootstrap via Microsoft.WinGet.Client.'

    try {
        Invoke-Action -Description 'Install-PackageProvider NuGet' -Action {
            Install-PackageProvider -Name NuGet -Force | Out-Null
        }

        Invoke-Action -Description 'Install-Module Microsoft.WinGet.Client' -Action {
            Install-Module -Name Microsoft.WinGet.Client -Repository PSGallery -Force -Scope CurrentUser | Out-Null
        }

        Invoke-Action -Description 'Repair-WinGetPackageManager' -Action {
            Repair-WinGetPackageManager -AllUsers | Out-Null
        }
    }
    catch {
        Write-Warning "Bootstrap automatico do winget falhou: $($_.Exception.Message)"
    }

    Refresh-PathFromRegistry

    if (Test-Command -Name 'winget') {
        return $true
    }

    Write-Warning 'winget ainda indisponivel. Instale/atualize App Installer e execute novamente.'
    return $false
}

function Install-WingetPackage {
    param([string]$Id)

    if ($SkipNerdFont -and $Id -eq 'JetBrains.JetBrainsMono.NerdFont') {
        Write-Host "[skip] $Id" -ForegroundColor DarkYellow
        return
    }

    Invoke-Action -Description "winget install $Id" -Action {
        winget install --id $Id --exact --source winget --accept-package-agreements --accept-source-agreements --silent
    }
}

Write-Step 'Pre-checks'
Write-Host "PowerShell: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
Write-Host "Sessao administrativa: $(Test-IsAdmin)"

if (-not (Ensure-Winget)) {
    throw 'Winget nao esta funcional. Encerrando etapa 1.'
}

Write-Step 'Instalando/atualizando pacotes essenciais via winget'
foreach ($packageId in $PackageIds) {
    Install-WingetPackage -Id $packageId
}

Write-Step 'Atualizando PATH da sessao'
Invoke-Action -Description 'Refresh PATH' -Action {
    Refresh-PathFromRegistry
}

if (-not $SkipExecutionPolicy) {
    Write-Step 'Ajustando ExecutionPolicy (CurrentUser)'
    try {
        Invoke-Action -Description 'Set-ExecutionPolicy RemoteSigned CurrentUser' -Action {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        }
    }
    catch {
        Write-Warning "Nao foi possivel ajustar ExecutionPolicy: $($_.Exception.Message)"
    }
}

Write-Step 'Validacoes basicas'
$commandsToCheck = @('winget', 'pwsh', 'oh-my-posh', 'eza', 'fzf', 'rg')
foreach ($command in $commandsToCheck) {
    if (Test-Command -Name $command) {
        Write-Host "[ok] $command"
    }
    else {
        Write-Warning "[missing] $command"
    }
}

Write-Host "`nEtapa 1 concluida." -ForegroundColor Green
Write-Host 'Proximo passo: executar Scripts/stage2-deploy.ps1'
Write-Host 'Em seguida: Scripts/stage3-python.ps1 (ferramentas Python globais via pipx)'
