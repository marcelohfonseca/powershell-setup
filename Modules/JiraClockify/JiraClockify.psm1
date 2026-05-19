# =============================================================================
# JiraClockify.psm1
# Módulo com funções de integração Jira + Clockify via CLI e API REST
# =============================================================================

# =============================================================================
# SEÇÃO 1: Utilitários internos
# Sem dependências externas; usados pelas demais funções.
# =============================================================================

function Get-MyJiraIssues {
    $json = acli jira workitem search `
        --jql "assignee = currentUser() AND statusCategory != Done" `
        --fields "summary" `
        --json | ConvertFrom-Json

    $json | ForEach-Object {
        "$($_.key) - $($_.fields.summary)"
    }
}

function Get-JiraUsers {
    $raw = acli jira workitem search `
        --jql "project = NDI AND assignee IS NOT EMPTY" `
        --fields "assignee" `
        --json

    $json = [System.Text.Encoding]::UTF8.GetString(
        [System.Text.Encoding]::Default.GetBytes($raw)
    ) | ConvertFrom-Json

    $json |
        ForEach-Object { $_.fields.assignee } |
        Where-Object { $_ } |
        Sort-Object displayName -Unique
}

function Get-ClockifyProjects {
    $result = Invoke-RestMethod `
        -Uri "https://api.clockify.me/api/v1/workspaces/$env:CLOCKIFY_WORKSPACE/projects?page-size=500" `
        -Headers @{ "X-Api-Key" = $env:CLOCKIFY_API_KEY }
    return @($result)
}

function Get-ClockifyTags {
    $result = Invoke-RestMethod `
        -Uri "https://api.clockify.me/api/v1/workspaces/$env:CLOCKIFY_WORKSPACE/tags?archived=false&page-size=500" `
        -Headers @{ "X-Api-Key" = $env:CLOCKIFY_API_KEY }
    return @($result)
}


# =============================================================================
# SEÇÃO 2: Jira — leitura e interação
# =============================================================================

function Jira-List {
    acli jira workitem search `
        --jql "assignee = currentUser() AND statusCategory != Done" `
        --paginate
}

function Jira-View {
    param([string]$key)
    acli jira workitem view $key
}

Register-ArgumentCompleter -CommandName Jira-View -ParameterName key -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    Get-MyJiraIssues |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object {
            $key = ($_ -split " - ")[0]
            [System.Management.Automation.CompletionResult]::new($key, $key, 'ParameterValue', $_)
        }
}

function Get-JiraMyself {
    if (-not $env:JIRA_BASE_URL -or -not $env:JIRA_USER -or -not $env:JIRA_API_TOKEN) { return $null }
    $bytes   = [System.Text.Encoding]::UTF8.GetBytes("$($env:JIRA_USER):$($env:JIRA_API_TOKEN)")
    $b64     = [Convert]::ToBase64String($bytes)
    $headers = @{ "Authorization" = "Basic $b64"; "Accept" = "application/json" }
    Invoke-RestMethod -Uri "$($env:JIRA_BASE_URL)/rest/api/3/myself" -Headers $headers
}

function Invoke-JiraTransition {
    param(
        [string]$key,
        [string]$status
    )

    $bytes   = [System.Text.Encoding]::UTF8.GetBytes("$($env:JIRA_USER):$($env:JIRA_API_TOKEN)")
    $b64     = [Convert]::ToBase64String($bytes)
    $headers = @{ "Authorization" = "Basic $b64"; "Content-Type" = "application/json"; "Accept" = "application/json" }

    # Busca as transições disponíveis
    $transitions = Invoke-RestMethod `
        -Uri "$($env:JIRA_BASE_URL)/rest/api/3/issue/$key/transitions" `
        -Headers $headers | Select-Object -ExpandProperty transitions

    $target = $transitions | Where-Object { $_.name -like "*$status*" } | Select-Object -First 1

    if (-not $target) {
        Write-Host "⚠️ Status '$status' não encontrado. Disponíveis: $(($transitions.name) -join ', ')" -ForegroundColor Yellow
        return $false
    }

    $body = @{ transition = @{ id = $target.id } } | ConvertTo-Json
    Invoke-RestMethod `
        -Method POST `
        -Uri "$($env:JIRA_BASE_URL)/rest/api/3/issue/$key/transitions" `
        -Headers $headers `
        -Body $body | Out-Null

    return $true
}

function Jira-Create {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$summary,

        [Parameter(Mandatory = $false)]
        [string]$project = "NDI",

        [Parameter(Mandatory = $false)]
        [ValidateSet("Story", "Melhoria", "Bug", "Tarefa", "Subtarefa", "Epic")]
        [string]$type = "Story",

        [Parameter(Mandatory = $false)]
        [string]$desc,

        [Parameter(Mandatory = $false)]
        [string]$assignee,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Urgente", "Muito alto", "Alto", "Médio", "Baixo", "Muito baixo", "Bug Alto", "Bug Médio", "Bug Baixo", "Melhoria")]
        [string]$priority = "Baixo",

        [Parameter(Mandatory = $false)]
        [ValidateSet("Backlog", "EM ANDAMENTO", "AGUARDANDO", "HOMOLOGAÇÃO", "GARANTIA DA QUALIDADE", "CONCLUÍDO", "Cancelado")]
        [string]$status
    )

    # ── Credenciais ───────────────────────────────────────────────────────────
    if (-not $env:JIRA_BASE_URL -or -not $env:JIRA_USER -or -not $env:JIRA_API_TOKEN) {
        Write-Host "❌ Variáveis JIRA_BASE_URL, JIRA_USER e JIRA_API_TOKEN são necessárias." -ForegroundColor Red
        return
    }

    $bytes   = [System.Text.Encoding]::UTF8.GetBytes("$($env:JIRA_USER):$($env:JIRA_API_TOKEN)")
    $b64     = [Convert]::ToBase64String($bytes)
    $headers = @{
        "Authorization" = "Basic $b64"
        "Content-Type"  = "application/json"
        "Accept"        = "application/json"
    }

    # ── Assignee: resolve accountId pelo displayName ──────────────────────────
    $assigneeObj = $null
    if ($assignee) {
        $target = Get-JiraUsers | Where-Object { $_.displayName -like "*$assignee*" } | Select-Object -First 1
        if ($target) {
            $assigneeObj = @{ id = $target.accountId }
            Write-Host "✓ Assignee => $($target.displayName)"
        } else {
            Write-Host "⚠️ Usuário '$assignee' não encontrado, usando usuário atual..." -ForegroundColor Yellow
            $myself = Get-JiraMyself
            if ($myself) { $assigneeObj = @{ id = $myself.accountId } }
        }
    } else {
        $myself = Get-JiraMyself
        if ($myself) {
            $assigneeObj = @{ id = $myself.accountId }
            Write-Host "✓ Assignee => $($myself.displayName) (padrão)"
        }
    }

    # ── Body ──────────────────────────────────────────────────────────────────
    $fields = [ordered]@{
        project   = @{ key = $project }
        summary   = $summary
        issuetype = @{ name = $type }
    }

    if ($desc) {
        $fields.description = @{
            type    = "doc"
            version = 1
            content = @(
                @{
                    type    = "paragraph"
                    content = @(
                        @{ type = "text"; text = $desc }
                    )
                }
            )
        }
    }

    if ($assigneeObj) { $fields.assignee = $assigneeObj }
    if ($priority)    { $fields.priority = @{ name = $priority } }

    $body = @{ fields = $fields } | ConvertTo-Json -Depth 10

    # ── Request ───────────────────────────────────────────────────────────────
    try {
        $result = Invoke-RestMethod `
            -Method POST `
            -Uri "$($env:JIRA_BASE_URL)/rest/api/3/issue" `
            -Headers $headers `
            -Body $body

        Write-Host ""
        Write-Host "✅ Card criado => $($result.key)" -ForegroundColor Green
        Write-Host "Título    => $summary"
        Write-Host "Projeto   => $project"
        Write-Host "Tipo      => $type"
        if ($priority)    { Write-Host "Prioridade => $priority" }
        Write-Host "URL       => $($env:JIRA_BASE_URL)/browse/$($result.key)" -ForegroundColor Cyan
        if ($status) {
            $ok = Invoke-JiraTransition -key $result.key -status $status
            if ($ok) { Write-Host "Status    => $status" -ForegroundColor Green }
        }
    }
    catch {
        Write-Host "❌ Erro ao criar card" -ForegroundColor Red
        if ($_.ErrorDetails?.Message) { Write-Host $_.ErrorDetails.Message -ForegroundColor Yellow }
        else                          { Write-Host $_.Exception.Message -ForegroundColor Yellow }
    }
}

Register-ArgumentCompleter -CommandName Jira-Create -ParameterName assignee -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    Get-JiraUsers |
        Where-Object { $_.displayName -like "*$wordToComplete*" } |
        ForEach-Object {
            $completionText = "'$($_.displayName)'"
            [System.Management.Automation.CompletionResult]::new(
                $completionText, $_.displayName, 'ParameterValue', $_.displayName
            )
        }
}

function Jira-Comment {
    param(
        [string]$key,
        [string]$msg
    )

    acli jira workitem comment create `
        --key $key `
        --body $msg
}

Register-ArgumentCompleter -CommandName Jira-Comment -ParameterName key -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    Get-MyJiraIssues |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object {
            $key = ($_ -split " - ")[0]
            [System.Management.Automation.CompletionResult]::new($key, $key, 'ParameterValue', $_)
        }
}

function Jira-Mention {
    param(
        [string]$issue,
        [string]$user,
        [string]$msg
    )

    $target = Get-JiraUsers |
        Where-Object { $_.displayName -like "*$user*" } |
        Select-Object -First 1

    if (-not $target) {
        Write-Host "Usuário não encontrado"
        return
    }

    Write-Host "Mention => $($target.displayName) ($($target.accountId))"

    $body = @{
        type    = "doc"
        version = 1
        content = @(
            @{
                type    = "paragraph"
                content = @(
                    @{
                        type  = "mention"
                        attrs = @{
                            id   = $target.accountId
                            text = "@$($target.displayName)"
                        }
                    },
                    @{
                        type = "text"
                        text = " $msg"
                    }
                )
            }
        )
    } | ConvertTo-Json -Depth 10

    acli jira workitem comment create `
        --key $issue `
        --body $body
}

Register-ArgumentCompleter -CommandName Jira-Mention -ParameterName issue -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    Get-MyJiraIssues |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object {
            $key = ($_ -split " - ")[0]
            [System.Management.Automation.CompletionResult]::new($key, $key, 'ParameterValue', $_)
        }
}

Register-ArgumentCompleter -CommandName Jira-Mention -ParameterName user -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    Get-JiraUsers |
        Where-Object { $_.displayName -like "*$wordToComplete*" } |
        ForEach-Object {
            $completionText = "'$($_.displayName)'"
            [System.Management.Automation.CompletionResult]::new(
                $completionText, $_.displayName, 'ParameterValue', $_.displayName
            )
        }
}


# =============================================================================
# SEÇÃO 3: Clockify — timer
# =============================================================================

function Clockify-Start {
    param(
        [Parameter(Mandatory = $false)]
        [string]$prj,
        [Parameter(Mandatory = $false)]
        [string[]]$tag,       # <-- era [string], agora aceita array
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$desc
    )

    $headers = @{
        "X-Api-Key"    = $env:CLOCKIFY_API_KEY
        "Content-Type" = "application/json"
    }

    # ── Projeto ───────────────────────────────────────────────────────────────
    $projectId   = $null
    $projectName = $null

    if ($prj) {
        $existingProject = Get-ClockifyProjects |
            Where-Object { $_.name -match "^\[$([regex]::Escape($prj))\]" } |
            Select-Object -First 1

        if ($existingProject -is [array]) { $existingProject = $existingProject[0] }

        if ($existingProject) {
            $projectId   = $existingProject.id
            $projectName = $existingProject.name
            Write-Host "✓ Projeto encontrado => $projectName"
        }
        else {
            Write-Host "Projeto não encontrado no Clockify"
            Write-Host "Criando projeto a partir do Jira..."

            $issue = acli jira workitem view $prj --json | ConvertFrom-Json
            if (-not $issue) { Write-Host "Card Jira não encontrado"; return }

            $projectName    = "[$($issue.key)] $($issue.fields.summary)"
            $newProjectBody = @{ name = $projectName; isPublic = $false } | ConvertTo-Json

            try {
                $createdProject = Invoke-RestMethod `
                    -Method POST `
                    -Uri "https://api.clockify.me/api/v1/workspaces/$env:CLOCKIFY_WORKSPACE/projects" `
                    -Headers $headers `
                    -Body $newProjectBody
                $projectId = $createdProject.id
                Write-Host "✓ Projeto criado => $projectName"
            }
            catch {
                Write-Host "Erro ao criar projeto"
                if ($_.ErrorDetails?.Message) { Write-Host $_.ErrorDetails.Message }
                return
            }
        }
    }

    # ── Tags ──────────────────────────────────────────────────────────────────
    $tagIds = [System.Collections.Generic.List[string]]::new()

    foreach ($t in $tag) {
        $existingTag = Get-ClockifyTags | Where-Object { $_.name -eq $t } | Select-Object -First 1

        if ($existingTag -and $existingTag.id) {
            $tagIds.Add([string]$existingTag.id)
            Write-Host "✓ Tag encontrada => $($existingTag.name)"
        }
        else {
            Write-Host "Tag não encontrada, criando: $t..."
            try {
                $createdTag = Invoke-RestMethod `
                    -Method POST `
                    -Uri "https://api.clockify.me/api/v1/workspaces/$env:CLOCKIFY_WORKSPACE/tags" `
                    -Headers $headers `
                    -Body (@{ name = $t } | ConvertTo-Json)
                $tagIds.Add([string]$createdTag.id)
                Write-Host "✓ Tag criada => $t"
            }
            catch {
                $errMsg = $_.ErrorDetails?.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($errMsg?.code -eq 501) {
                    Write-Host "Tag já existe remotamente, buscando pelo nome..."
                    $existingTag = Invoke-RestMethod `
                        -Uri "https://api.clockify.me/api/v1/workspaces/$env:CLOCKIFY_WORKSPACE/tags?name=$([uri]::EscapeDataString($t))&page-size=10" `
                        -Headers @{ "X-Api-Key" = $env:CLOCKIFY_API_KEY } |
                        Where-Object { $_.name -eq $t } |
                        Select-Object -First 1
                    if ($existingTag?.id) {
                        $tagIds.Add([string]$existingTag.id)
                        Write-Host "✓ Tag recuperada => $t"
                    } else {
                        Write-Host "⚠️ Tag '$t' não pôde ser recuperada, pulando..." -ForegroundColor Yellow
                    }
                }
                else {
                    Write-Host "⚠️ Não foi possível criar a tag '$t', pulando..." -ForegroundColor Yellow
                    if ($_.ErrorDetails?.Message) { Write-Host $_.ErrorDetails.Message }
                }
            }
        }
    }

    # ── Criação do timer ──────────────────────────────────────────────────────
    $body = @{
        start       = (Get-Date).ToUniversalTime().ToString("o")
        description = $desc
        billable    = $true
        type        = "REGULAR"
    }
    if ($projectId) { $body.projectId = [string]$projectId }
    if ($tagIds.Count -gt 0) { $body.tagIds = $tagIds.ToArray() }

    try {
        $result = Invoke-RestMethod `
            -Method POST `
            -Uri "https://api.clockify.me/api/v1/workspaces/$env:CLOCKIFY_WORKSPACE/time-entries" `
            -Headers $headers `
            -Body ($body | ConvertTo-Json)

        Write-Host ""
        Write-Host "▶ Timer iniciado"
        if ($projectName) { Write-Host "Projeto   => $projectName" }
        if ($tagIds.Count -gt 0) { Write-Host "Tags      => $($tag -join ', ')" }
        Write-Host "Descrição => $desc"
        Write-Host "Id        => $($result.id)"
    }
    catch {
        Write-Host "Erro ao iniciar timer"
        if ($_.ErrorDetails?.Message) { Write-Host $_.ErrorDetails.Message }
    }
}

Register-ArgumentCompleter -CommandName Clockify-Start -ParameterName prj -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    Get-MyJiraIssues |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object {
            $key = ($_ -split " - ")[0]
            [System.Management.Automation.CompletionResult]::new($key, $key, 'ParameterValue', $_)
        }
}

function Clockify-Current {
    $headers = @{
        "X-Api-Key"    = $env:CLOCKIFY_API_KEY
        "Content-Type" = "application/json"
    }

    try {
        $uri      = "https://api.clockify.me/api/v1/workspaces/$env:CLOCKIFY_WORKSPACE/user/$env:CLOCKIFY_USER/time-entries?in-progress=true"
        $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers -ErrorAction Stop

        if (-not $response -or $response.Count -eq 0) {
            Write-Host "ℹ️ Nenhum timer rodando agora." -ForegroundColor Gray
            return
        }

        $entry = $response | Select-Object -First 1
        $desc  = if ([string]::IsNullOrWhiteSpace($entry.description)) { "Tarefa sem nome" } else { $entry.description }

        $startTime = $entry.timeInterval.start
        if (-not $startTime) { Write-Host "❌ startTime inválido" -ForegroundColor Red; return }

        $startTime = if ($startTime -is [datetime]) {
            $startTime.ToUniversalTime()
        } else {
            [DateTimeOffset]::Parse($startTime).ToUniversalTime()
        }

        $diff = [DateTimeOffset]::UtcNow - $startTime
        if ($diff -lt [timespan]::Zero) { $diff = $diff.Negate() }

        $tempo = "{0}:{1:00}:{2:00}" -f [math]::Floor($diff.TotalHours), $diff.Minutes, $diff.Seconds
        Write-Host "🚀 Ativo: $desc [$tempo]" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Erro na API do Clockify" -ForegroundColor Red
        Write-Host "Detalhe: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Clockify-Stop {
    $headers = @{
        "X-Api-Key"    = $env:CLOCKIFY_API_KEY
        "Content-Type" = "application/json"
    }
    try {
        $uriGet = "https://api.clockify.me/api/v1/workspaces/$env:CLOCKIFY_WORKSPACE/user/$env:CLOCKIFY_USER/time-entries?in-progress=true"
        $active = @(Invoke-RestMethod -Method GET -Uri $uriGet -Headers $headers)

        # Filtra entradas que realmente têm id
        $active = $active | Where-Object { $_.id }

        if (-not $active -or $active.Count -eq 0) {
            Write-Host "ℹ️ Nenhum timer ativo." -ForegroundColor Gray
            return
        }

        foreach ($entry in $active) {
            $id  = $entry.id
            $uri = "https://api.clockify.me/api/v1/workspaces/$env:CLOCKIFY_WORKSPACE/time-entries/$id"

            $bodyObj = @{
                start       = $entry.timeInterval.start
                end         = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                description = $entry.description
                projectId   = $entry.projectId
                taskId      = $entry.taskId
                billable    = $entry.billable
                tagIds      = @($entry.tagIds | Where-Object { $_ })
            }

            $stopped = Invoke-RestMethod -Method PUT -Uri $uri -Headers $headers -Body ($bodyObj | ConvertTo-Json -Depth 10)

            # Mesma lógica do Current para tratar datetime local vs string ISO
            $desc      = if ([string]::IsNullOrWhiteSpace($entry.description)) { "Tarefa sem nome" } else { $entry.description }
            $startTime = $entry.timeInterval.start
            $startTime = if ($startTime -is [datetime]) {
                $startTime.ToUniversalTime()
            } else {
                [DateTimeOffset]::Parse($startTime).ToUniversalTime()
            }
            $diff = [DateTimeOffset]::UtcNow - $startTime
            if ($diff -lt [timespan]::Zero) { $diff = $diff.Negate() }
            $tempo = "{0}:{1:00}:{2:00}" -f [math]::Floor($diff.TotalHours), $diff.Minutes, $diff.Seconds
            Write-Host "⏹ Parado: $desc [$tempo]" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "❌ Erro ao parar timer" -ForegroundColor Red
        if ($_.ErrorDetails?.Message) { Write-Host "Detalhes: $($_.ErrorDetails.Message)" -ForegroundColor Yellow }
        else                          { Write-Host $_.Exception.Message -ForegroundColor Yellow }
    }
}


# =============================================================================
# SEÇÃO 4: Clockify — relatórios
# =============================================================================

function Clockify-Summary {
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
        [string]$from,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
        [string]$to,

        [Parameter(Mandatory = $false)]
        [string]$prj,

        [Parameter(Mandatory = $false)]
        [string]$tag,

        [Parameter(Mandatory = $false)]
        [ValidateSet("project", "date", "tag", "all")]
        [string]$type = "all"
    )

    $headers = @{
        "X-Api-Key"    = $env:CLOCKIFY_API_KEY
        "Content-Type" = "application/json"
    }

    # ── Grupos ────────────────────────────────────────────────────────────────
    $groups = [System.Collections.Generic.List[string]]::new()
    switch ($type) {
        "project" { $groups.Add("PROJECT") }
        "date"    { $groups.Add("DATE")    }
        "tag"     { $groups.Add("TAG")     }
        default   { $groups.Add("DATE"); $groups.Add("PROJECT"); $groups.Add("TAG") }
    }

    $body = @{
        dateRangeStart = "${from}T00:00:00.000Z"
        dateRangeEnd   = "${to}T23:59:59.999Z"
        summaryFilter  = @{
            groups = $groups.ToArray()
        }
    }

    if ($prj) {
        $found = Get-ClockifyProjects | Where-Object { $_.name -like "*$prj*" } | Select-Object -First 1
        if ($found) { $body.projects = @{ ids = @($found.id) } }
        else        { Write-Warning "Projeto não encontrado: $prj" }
    }

    if ($tag) {
        $found = Get-ClockifyTags | Where-Object { $_.name -eq $tag } | Select-Object -First 1
        if ($found) { $body.tags = @{ ids = @($found.id) } }
        else        { Write-Warning "Tag não encontrada: $tag" }
    }

    try {
        $result = Invoke-RestMethod `
            -Method POST `
            -Uri "https://reports.api.clockify.me/v1/workspaces/$env:CLOCKIFY_WORKSPACE/reports/summary" `
            -Headers $headers `
            -Body ($body | ConvertTo-Json -Depth 10 -Compress)

        Write-Host ""
        Write-Host "📊 Relatório Sumarizado: $from → $to" -ForegroundColor Cyan

        function fmtDur($seconds) {
            $d = [timespan]::FromSeconds($seconds)
            "{0}h {1:00}m" -f [math]::Floor($d.TotalHours), $d.Minutes
        }

        if ($type -eq "project") {
            $sep = "-" * 58
            Write-Host $sep -ForegroundColor DarkGray
            Write-Host ("{0,-45} {1,10}" -f "Projeto", "Duração") -ForegroundColor DarkGray
            Write-Host $sep -ForegroundColor DarkGray
            foreach ($g in $result.groupOne) {
                $name = if ($g.name) { $g.name } else { "(sem projeto)" }
                if ($name.Length -gt 43) { $name = $name.Substring(0, 40) + "..." }
                Write-Host ("{0,-45} {1,10}" -f $name, (fmtDur $g.duration))
            }
            Write-Host $sep -ForegroundColor DarkGray

        } elseif ($type -eq "date") {
            $sep = "-" * 28
            Write-Host $sep -ForegroundColor DarkGray
            Write-Host ("{0,-15} {1,10}" -f "Data", "Duração") -ForegroundColor DarkGray
            Write-Host $sep -ForegroundColor DarkGray
            foreach ($g in $result.groupOne) {
                $name = if ($g.name) { $g.name.Substring(0, 10) } else { "?" }
                Write-Host ("{0,-15} {1,10}" -f $name, (fmtDur $g.duration))
            }
            Write-Host $sep -ForegroundColor DarkGray
            $totalTempo = fmtDur $result.totals[0].totalTime
            $labelLen   = $sep.Length - 9
            Write-Host ("{0,-$labelLen} {1,8}" -f "Total", $totalTempo) -ForegroundColor Yellow

        } elseif ($type -eq "tag") {
            $sep = "-" * 58
            Write-Host $sep -ForegroundColor DarkGray
            Write-Host ("{0,-45} {1,10}" -f "Tag", "Duração") -ForegroundColor DarkGray
            Write-Host $sep -ForegroundColor DarkGray
            foreach ($g in $result.groupOne) {
                $name = if ($g.name) { $g.name } else { "(sem tag)" }
                if ($name.Length -gt 43) { $name = $name.Substring(0, 40) + "..." }
                Write-Host ("{0,-45} {1,10}" -f $name, (fmtDur $g.duration))
            }
            Write-Host $sep -ForegroundColor DarkGray
            $totalTempo = fmtDur $result.totals[0].totalTime
            $labelLen   = $sep.Length - 9
            Write-Host ("{0,-$labelLen} {1,8}" -f "Total", $totalTempo) -ForegroundColor Yellow

        } else {
            $sep = "-" * 103
            Write-Host $sep -ForegroundColor DarkGray
            Write-Host ("{0,-12} {1,-60} {2,-20} {3,8}" -f "Data", "Projeto", "Tag", "Duração") -ForegroundColor DarkGray
            Write-Host $sep -ForegroundColor DarkGray
            foreach ($g in $result.groupOne) {
                $date = if ($g.name) { $g.name.Substring(0, 10) } else { "?" }
                foreach ($sub in $g.children) {
                    $projName = if ($sub.name) { $sub.name } else { "(sem projeto)" }
                    if ($projName.Length -gt 58) { $projName = $projName.Substring(0, 55) + "..." }
                    foreach ($leaf in $sub.children) {
                        $tagName = if ($leaf.name) { $leaf.name } else { "(sem tag)" }
                        if ($tagName.Length -gt 18) { $tagName = $tagName.Substring(0, 15) + "..." }
                        Write-Host ("{0,-12} {1,-60} {2,-20} {3,8}" -f $date, $projName, $tagName, (fmtDur $leaf.duration))
                    }
                }
            }
            Write-Host $sep -ForegroundColor DarkGray
            $totalTempo = fmtDur $result.totals[0].totalTime
            $count      = $result.totals[0].entriesCount
            $labelLen   = $sep.Length - 9
            Write-Host ("{0,-$labelLen} {1,8}" -f "Total ($count entradas)", $totalTempo) -ForegroundColor Yellow
        }

        Write-Host ""
    }
    catch {
        Write-Host "❌ Erro ao gerar relatório sumarizado" -ForegroundColor Red
        if ($_.ErrorDetails?.Message) { Write-Host $_.ErrorDetails.Message -ForegroundColor Yellow }
        else                          { Write-Host $_.Exception.Message -ForegroundColor Yellow }
    }
}

Register-ArgumentCompleter -CommandName Clockify-Summary -ParameterName prj -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    Get-MyJiraIssues |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object {
            $key = ($_ -split " - ")[0]
            [System.Management.Automation.CompletionResult]::new($key, $key, 'ParameterValue', $_)
        }
}

function Clockify-Detailed {
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
        [string]$from,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
        [string]$to,

        [Parameter(Mandatory = $false)]
        [string]$prj,

        [Parameter(Mandatory = $false)]
        [string]$tag
    )

    $headers = @{
        "X-Api-Key"    = $env:CLOCKIFY_API_KEY
        "Content-Type" = "application/json"
    }

    $body = @{
        dateRangeStart = "${from}T00:00:00.000Z"
        dateRangeEnd   = "${to}T23:59:59.999Z"
        detailedFilter = @{
            page       = 1
            pageSize   = 200
            sortColumn = "DATE"
            sortOrder  = "ASCENDING"
        }
    }

    if ($prj) {
        $found = Get-ClockifyProjects | Where-Object { $_.name -like "*$prj*" } | Select-Object -First 1
        if ($found) { $body.projects = @{ ids = @($found.id) } }
        else        { Write-Warning "Projeto não encontrado: $prj" }
    }

    if ($tag) {
        $found = Get-ClockifyTags | Where-Object { $_.name -eq $tag } | Select-Object -First 1
        if ($found) { $body.tags = @{ ids = @($found.id) } }
        else        { Write-Warning "Tag não encontrada: $tag" }
    }

    try {
        $result = Invoke-RestMethod `
            -Method POST `
            -Uri "https://reports.api.clockify.me/v1/workspaces/$env:CLOCKIFY_WORKSPACE/reports/detailed" `
            -Headers $headers `
            -Body ($body | ConvertTo-Json -Depth 10 -Compress)

        $colDate = 12
        $colDesc = 32
        $colProj = 36
        $colTag  = 16
        $colDur  =  8
        # +4 pelos espaços separadores entre as 5 colunas
        $sepLen  = $colDate + $colDesc + $colProj + $colTag + $colDur + 4
        $sep     = "-" * $sepLen

        Write-Host ""
        Write-Host "📋 Relatório Detalhado: $from → $to" -ForegroundColor Cyan
        Write-Host $sep -ForegroundColor DarkGray
        Write-Host ("{0,-$colDate} {1,-$colDesc} {2,-$colProj} {3,-$colTag} {4,$colDur}" `
            -f "Data", "Descrição", "Projeto", "Tag", "Duração") -ForegroundColor DarkGray
        Write-Host $sep -ForegroundColor DarkGray

        # ── Cache antes do loop ───────────────────────────────────────────────────
        $projectsCache = Get-ClockifyProjects
        $tagsCache     = Get-ClockifyTags
        
        foreach ($entry in $result.timeentries) {

            # ── Data: usa zonedStart que já está no fuso correto ──────────────────
            $date = ([datetime]$entry.timeInterval.zonedStart).ToString("yyyy-MM-dd")

            # ── Duração ───────────────────────────────────────────────────────────
            $duration = [timespan]::FromSeconds($entry.timeInterval.duration)
            $tempo    = "{0}h {1:00}m" -f [math]::Floor($duration.TotalHours), $duration.Minutes

            # ── Descrição ─────────────────────────────────────────────────────────
            $desc = if (-not [string]::IsNullOrWhiteSpace($entry.description)) { $entry.description } else { "(sem descrição)" }

            # ── Projeto: lookup pelo projectId ────────────────────────────────────
            $proj = "(sem projeto)"
            if ($entry.projectId) {
                $found = $projectsCache | Where-Object { $_.id -eq $entry.projectId } | Select-Object -First 1
                if ($found) { $proj = $found.name }
            }

            # ── Tag: lookup pelo primeiro tagId ───────────────────────────────────
            $tagName = "(sem tag)"
            if ($entry.tagIds -and $entry.tagIds.Count -gt 0) {
                $found = $tagsCache | Where-Object { $_.id -eq $entry.tagIds[0] } | Select-Object -First 1
                if ($found) { $tagName = $found.name }
            }

            # ── Trunca ────────────────────────────────────────────────────────────
            $maxDesc = $colDesc - 2
            $maxProj = $colProj - 2
            $maxTag  = $colTag  - 2
            if ($desc.Length    -gt $maxDesc) { $desc    = $desc.Substring(0, $maxDesc - 3)   + "..." }
            if ($proj.Length    -gt $maxProj) { $proj    = $proj.Substring(0, $maxProj - 3)   + "..." }
            if ($tagName.Length -gt $maxTag)  { $tagName = $tagName.Substring(0, $maxTag - 3) + "..." }

            Write-Host ("{0,-$colDate} {1,-$colDesc} {2,-$colProj} {3,-$colTag} {4,$colDur}" `
                -f $date, $desc, $proj, $tagName, $tempo)
        }

        Write-Host $sep -ForegroundColor DarkGray
        $total      = [timespan]::FromSeconds($result.totals[0].totalTime)
        $totalTempo = "{0}h {1:00}m" -f [math]::Floor($total.TotalHours), $total.Minutes
        $count      = $result.totals[0].entriesCount
        $labelLen   = $sepLen - $colDur - 1
        Write-Host ("{0,-$labelLen} {1,$colDur}" -f "Total ($count entradas)", $totalTempo) -ForegroundColor Yellow
        Write-Host ""
    }
    catch {
        Write-Host "❌ Erro ao gerar relatório detalhado" -ForegroundColor Red
        if ($_.ErrorDetails?.Message) { Write-Host $_.ErrorDetails.Message -ForegroundColor Yellow }
        else                          { Write-Host $_.Exception.Message -ForegroundColor Yellow }
    }
}
