[CmdletBinding()]
param(
    [string]$ProfilePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-ProfilePath {
    if ($ProfilePath) {
        return $ProfilePath
    }

    if ($PROFILE -is [string] -and -not [string]::IsNullOrWhiteSpace($PROFILE)) {
        return $PROFILE
    }

    return $PROFILE.CurrentUserAllHosts
}

$resolvedProfilePath = Resolve-ProfilePath
$profileRoot = Split-Path -Parent $resolvedProfilePath

Write-Host "Profile alvo: $resolvedProfilePath"

$checks = @(
    @{ Name = 'profile'; Path = $resolvedProfilePath },
    @{ Name = 'conf.d'; Path = (Join-Path $profileRoot 'conf.d') },
    @{ Name = 'Modules'; Path = (Join-Path $profileRoot 'Modules') },
    @{ Name = 'JiraClockify module'; Path = (Join-Path $profileRoot 'Modules\JiraClockify\JiraClockify.psm1') }
)

$hasFailure = $false
foreach ($check in $checks) {
    if (Test-Path $check.Path) {
        Write-Host "[ok] $($check.Name): $($check.Path)"
    }
    else {
        Write-Warning "[missing] $($check.Name): $($check.Path)"
        $hasFailure = $true
    }
}

$commands = @('winget', 'pwsh', 'oh-my-posh', 'eza', 'fzf', 'rg')
foreach ($command in $commands) {
    if (Get-Command $command -ErrorAction SilentlyContinue) {
        Write-Host "[ok] comando: $command"
    }
    else {
        Write-Warning "[missing] comando: $command"
    }
}

try {
    . $resolvedProfilePath
    Write-Host '[ok] profile carregado sem erro fatal'
}
catch {
    Write-Warning "[error] falha ao carregar profile: $($_.Exception.Message)"
    $hasFailure = $true
}

if ($hasFailure) {
    Write-Error 'Validacao final encontrou pendencias.'
    exit 1
}

Write-Host 'Validacao final concluida com sucesso.' -ForegroundColor Green
