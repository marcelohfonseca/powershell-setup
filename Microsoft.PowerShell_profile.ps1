using namespace System.Management.Automation
using namespace System.Management.Automation.Language

# =============================================================================
# UTF-8 Encoding
# =============================================================================

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

# =============================================================================
# Core modules
# =============================================================================

if ($host.Name -eq 'ConsoleHost' -and $PSVersionTable.PSEdition -eq 'Core') {
    if (Get-Module -ListAvailable -Name PSReadLine) {
        Import-Module PSReadLine
    }
}

if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module Terminal-Icons
}

# =============================================================================
# Oh My Posh
# =============================================================================

if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh `
        --config "$env:POSH_THEMES_PATH\star.omp.json" |
        Invoke-Expression
}

# =============================================================================
# Load configs
# =============================================================================

$profileRoot = Split-Path -Parent $PROFILE
$configPath = Join-Path $profileRoot 'conf.d'

Get-ChildItem "$configPath/*.ps1" -ErrorAction SilentlyContinue |
Sort-Object Name |
ForEach-Object {
    . $_.FullName
}

# =============================================================================
# Mise
# =============================================================================

if (Get-Command mise -ErrorAction SilentlyContinue) {
    mise activate pwsh | Out-String | Invoke-Expression
}
