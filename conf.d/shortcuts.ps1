# =============================================================================
# Build shortcuts
# =============================================================================

Set-PSReadLineKeyHandler -Key Ctrl+Shift+b `
    -BriefDescription Build `
    -LongDescription "dotnet build" `
    -ScriptBlock {

        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()

        [Microsoft.PowerShell.PSConsoleReadLine]::Insert(
            "dotnet build"
        )

        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
    }
