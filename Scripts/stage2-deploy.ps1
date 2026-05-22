[CmdletBinding()]
param(
    [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$ProfilePath,
    [switch]$Mirror,
    [switch]$DryRun
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

function Resolve-ProfilePath {
    if ($ProfilePath) {
        return $ProfilePath
    }

    if ($PROFILE -is [string] -and -not [string]::IsNullOrWhiteSpace($PROFILE)) {
        return $PROFILE
    }

    return $PROFILE.CurrentUserAllHosts
}

function Invoke-RobocopySync {
    param(
        [string]$From,
        [string]$To,
        [switch]$MirrorMode
    )

    $args = @($From, $To, '/E', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
    if ($MirrorMode) {
        $args += '/MIR'
    }

    if ($DryRun) {
        Write-Host "[dry-run] robocopy $($args -join ' ')" -ForegroundColor Yellow
        return
    }

    & robocopy @args | Out-Null
    $exitCode = $LASTEXITCODE
    if ($exitCode -gt 7) {
        throw "Robocopy falhou para '$From' -> '$To'. ExitCode: $exitCode"
    }
}

$resolvedProfilePath = Resolve-ProfilePath
$targetRoot = Split-Path -Parent $resolvedProfilePath
$targetConf = Join-Path $targetRoot 'conf.d'
$targetModules = Join-Path $targetRoot 'Modules'

$sourceProfile = Join-Path $SourceRoot 'Microsoft.PowerShell_profile.ps1'
$sourceConf = Join-Path $SourceRoot 'conf.d'
$sourceModules = Join-Path $SourceRoot 'Modules'

Write-Step 'Validando origem'
foreach ($path in @($sourceProfile, $sourceConf, $sourceModules)) {
    if (-not (Test-Path $path)) {
        throw "Origem nao encontrada: $path"
    }
}

Write-Step 'Preparando destino'
Invoke-Action -Description "Criar diretorio alvo $targetRoot" -Action {
    New-Item -Path $targetRoot -ItemType Directory -Force | Out-Null
}

foreach ($path in @($targetConf, $targetModules)) {
    Invoke-Action -Description "Criar diretorio $path" -Action {
        New-Item -Path $path -ItemType Directory -Force | Out-Null
    }
}

Write-Step 'Backup do profile existente'
if (Test-Path $resolvedProfilePath) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = "$resolvedProfilePath.bak.$timestamp"

    Invoke-Action -Description "Backup em $backupPath" -Action {
        Copy-Item -Path $resolvedProfilePath -Destination $backupPath -Force
    }
}

Write-Step 'Publicando profile'
Invoke-Action -Description "Copiar $sourceProfile para $resolvedProfilePath" -Action {
    Copy-Item -Path $sourceProfile -Destination $resolvedProfilePath -Force
}

Write-Step 'Sincronizando conf.d'
Invoke-RobocopySync -From $sourceConf -To $targetConf -MirrorMode:$Mirror

Write-Step 'Sincronizando Modules'
Invoke-RobocopySync -From $sourceModules -To $targetModules -MirrorMode:$Mirror

Write-Step 'Validacao de arquivos minimos'
$requiredFiles = @(
    $resolvedProfilePath,
    (Join-Path $targetConf 'aliases.ps1'),
    (Join-Path $targetConf 'completions.ps1'),
    (Join-Path $targetConf 'modules.ps1'),
    (Join-Path $targetModules 'JiraClockify\JiraClockify.psm1')
)

foreach ($file in $requiredFiles) {
    if (Test-Path $file) {
        Write-Host "[ok] $file"
    }
    else {
        Write-Warning "[missing] $file"
    }
}

Write-Host "`nEtapa 2 concluida." -ForegroundColor Green
Write-Host 'Proximo passo: executar Scripts/stage3-python.ps1 (ferramentas Python globais via pipx)'
Write-Host 'Em seguida: Scripts/test-setup.ps1'
