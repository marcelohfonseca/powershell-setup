# =============================================================================
# Environment variables
# =============================================================================

function Import-Env {
    param([string]$Path = "$HOME\.env")

    if (-not (Test-Path $Path)) {
        Write-Warning "Arquivo .env não encontrado: $Path"
        return
    }

    Get-Content $Path | ForEach-Object {

        if ($_ -match '^\s*([^#][^=]*)=(.*)$') {

            $key = $matches[1].Trim()
            $value = $matches[2].Trim('"').Trim("'")

            [System.Environment]::SetEnvironmentVariable(
                $key,
                $value,
                'Process'
            )
        }
    }
}

$env:ENV_FILE = "$HOME\.env"

Import-Env
