[CmdletBinding()]
param(
    [switch]$DryRun,
    [string[]]$PipxPackages = @(
        'commitizen',
        'cookiecutter',
        'ipython',
        'pdm',
        'pip-audit',
        'poetry',
        'python-dotenv',
        'jupyterlab',
        'ipdb'
    ),
    [string[]]$PipPackages = @(
        'zuban'
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

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Ensure-Pipx {
    if (Test-Command -Name 'pipx') {
        return $true
    }

    Write-Warning 'pipx nao encontrado. Tentando instalar via pip.'

    try {
        Invoke-Action -Description 'pip install pipx --user' -Action {
            pip install pipx --user --quiet
        }
    }
    catch {
        Write-Warning "Falha ao instalar pipx: $($_.Exception.Message)"
        return $false
    }

    # Atualiza PATH para encontrar o pipx recem instalado
    $userScripts = [IO.Path]::Combine($env:APPDATA, 'Python', 'Scripts')
    $localScripts = [IO.Path]::Combine($env:LOCALAPPDATA, 'Programs', 'Python', 'Scripts')

    foreach ($path in @($userScripts, $localScripts)) {
        if (Test-Path $path) {
            $env:Path = "$path;$env:Path"
        }
    }

    if (Test-Command -Name 'pipx') {
        return $true
    }

    Write-Warning 'pipx ainda indisponivel. Instale manualmente e execute novamente.'
    return $false
}

function Install-PipxPackage {
    param([string]$Name)

    Invoke-Action -Description "pipx install $Name" -Action {
        pipx install $Name --quiet
    }
}

function Install-PipPackage {
    param([string]$Name)

    Invoke-Action -Description "pip install $Name --break-system-packages --upgrade" -Action {
        pip install $Name --break-system-packages --upgrade --quiet
    }
}

Write-Step 'Pre-checks'
Write-Host "PowerShell: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"

if (-not (Test-Command -Name 'python')) {
    throw 'python nao encontrado no PATH. Instale Python (via mise ou diretamente) e execute novamente.'
}

Write-Host "Python: $(python --version)"

if (-not (Ensure-Pipx)) {
    throw 'pipx nao esta funcional. Encerrando etapa 3.'
}

Write-Host "pipx: $(pipx --version)"

Write-Step "Instalando pacotes globais via pipx ($($PipxPackages.Count) pacotes)"
foreach ($package in $PipxPackages) {
    Install-PipxPackage -Name $package
}

Write-Step "Instalando pacotes especiais via pip ($($PipPackages.Count) pacotes)"
foreach ($package in $PipPackages) {
    Install-PipPackage -Name $package
}

Write-Step 'Atualizando PATH do pipx'
Invoke-Action -Description 'pipx ensurepath' -Action {
    pipx ensurepath | Out-Null
}

Write-Step 'Validacao final'
$toolChecks = @(
    @{ Name = 'commitizen'; Command = 'cz' },
    @{ Name = 'cookiecutter'; Command = 'cookiecutter' },
    @{ Name = 'ipython'; Command = 'ipython' },
    @{ Name = 'pdm'; Command = 'pdm' },
    @{ Name = 'pip-audit'; Command = 'pip-audit' },
    @{ Name = 'poetry'; Command = 'poetry' },
    @{ Name = 'python-dotenv'; Command = 'dotenv' },
    @{ Name = 'jupyterlab'; Command = 'jupyter' },
    @{ Name = 'zuban'; Command = 'zuban' }
)

foreach ($check in $toolChecks) {
    if (Test-Command -Name $check.Command) {
        Write-Host "[ok] $($check.Name) ($($check.Command))"
    }
    else {
        Write-Warning "[missing] $($check.Name) ($($check.Command))"
    }
}

# ipdb nao expoe um executavel standalone; verifica via pipx list
if (-not $DryRun) {
    $pipxList = & pipx list --short 2>$null
    if ($pipxList -match 'ipdb') {
        Write-Host '[ok] ipdb (via pipx list)'
    }
    else {
        Write-Warning '[missing] ipdb (via pipx list)'
    }
}
else {
    Write-Host "[dry-run] verificar ipdb via pipx list" -ForegroundColor Yellow
}

Write-Host "`nEtapa 3 concluida." -ForegroundColor Green
Write-Host 'Proximo passo: executar Scripts/test-setup.ps1'
