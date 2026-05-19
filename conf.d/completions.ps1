# =============================================================================
# Winget completion
# =============================================================================

if (Get-Command winget -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)

        [Console]::InputEncoding =
        [Console]::OutputEncoding =
        $OutputEncoding =
            [System.Text.UTF8Encoding]::new()

        $word = $wordToComplete.Replace('"', '""')
        $ast = $commandAst.ToString().Replace('"', '""')

        winget complete `
            --word="$word" `
            --commandline "$ast" `
            --position $cursorPosition |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new(
                    $_,
                    $_,
                    'ParameterValue',
                    $_
                )
            }
    }
}

# =============================================================================
# Dotnet completion
# =============================================================================

if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
        param($commandName, $wordToComplete, $cursorPosition)

        dotnet complete `
            --position $cursorPosition `
            "$wordToComplete" |

            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new(
                    $_,
                    $_,
                    'ParameterValue',
                    $_
                )
            }
    }
}
