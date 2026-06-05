#Requires -Modules Az.Accounts, Az.Resources, Az.CognitiveServices
<#
.SYNOPSIS
    Inventário detalhado dos recursos AI Foundry do tenant PLANAPP com análise de
    conformidade de nomenclatura CAF e relatório de remediação.
.DESCRIPTION
    Enumera todos os recursos AI Foundry em todas as subscriptions ativas:
      • MachineLearningServices/workspaces (Hub, Project, Default)
      • CognitiveServices/accounts (OpenAI, AIServices, FormRecognizer)

    Para cada recurso:
      • Recolhe deployments de modelos (nome, versão, SKU, capacidade)
      • Verifica conformidade com a Política de Nomenclaturas PLANAPP v1.1
      • Verifica tags obrigatórias: departamento, ambiente, projeto, centrocusto
      • Verifica accesso público à rede (publicNetworkAccess)
      • Verifica coerência ambiente/subscription

    Exporta:
      04a_ai_foundry_inventario_YYYYMMDD_HHmm.csv      — inventário completo
      04b_ai_foundry_deployments_YYYYMMDD_HHmm.csv     — deployments de modelos
      04c_ai_foundry_remediacao_YYYYMMDD_HHmm.csv      — não-conformidades e ações

    Projeto: 20260320-001 — Governança do Tenant PLANAPP
.NOTES
    Autor  : Luís Santos / PLANAPP SITDIA
    Data   : 2026-05-26
    Versão : 1.0
    Referência: PLANAPP-Política_Nomenclaturas_v1.1 (Sara Gonçalves, Unipartner)
#>

param(
    [string]$OutputPath = (Split-Path $PSScriptRoot -Parent),
    [switch]$IncludeModelDeployments = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$timestamp  = Get-Date -Format "yyyyMMdd_HHmm"
$csvInv     = Join-Path $OutputPath "04a_ai_foundry_inventario_$timestamp.csv"
$csvDeploy  = Join-Path $OutputPath "04b_ai_foundry_deployments_$timestamp.csv"
$csvRemedCA = Join-Path $OutputPath "04c_ai_foundry_remediacao_$timestamp.csv"

# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTES — Política de Nomenclaturas PLANAPP v1.1
# ─────────────────────────────────────────────────────────────────────────────
$PREFIXOS_VALIDOS = @{
    "microsoft.machinelearningservices/workspaces" = @("mlw", "aihub", "aiproj")
    "cognitiveservices/openai"                     = @("aoai", "oai")
    "cognitiveservices/aiservices"                 = @("ais", "aisr")
    "cognitiveservices/formrecognizer"             = @("docint", "di")
}

$AMBIENTES_VALIDOS  = @("hub", "prd", "nprd", "dev", "qua", "shared")
$DATACENTERS_VALIDOS = @("we", "ne", "sc", "no", "pt")
$ENTIDADE           = "pla"
$TAGS_OBRIGATORIAS  = @("departamento", "ambiente", "projeto", "centrocusto")

# Mapeamento subscription → ambiente esperado
$SUB_AMBIENTE_MAP = @{
    "PlanApp-prd-sub001"    = "prd"
    "PlanApp-nprd-sub001"   = "nprd"
    "PlanApp-hub-sub001"    = "hub"
    "PlanAPP-AZURE-TEMP"    = "nprd"   # temporária → tratada como nprd
}

# ─────────────────────────────────────────────────────────────────────────────
# FUNÇÕES AUXILIARES
# ─────────────────────────────────────────────────────────────────────────────

function Test-NomenclaturaCAF {
    <#
    .SYNOPSIS
        Valida se o nome de um recurso respeita o padrão CAF PLANAPP.
        Retorna objeto com IsConform (bool) e Motivos (string[]).
    #>
    param(
        [string]$Nome,
        [string]$TipoRecurso,   # ex: "microsoft.cognitiveservices/accounts"
        [string]$Kind           # ex: "OpenAI", "AIServices", "Hub", "Project"
    )

    $motivos = [System.Collections.Generic.List[string]]::new()

    # 1. Letras minúsculas
    if ($Nome -cmatch '[A-Z]') {
        $motivos.Add("Nome contém maiúsculas (regra: tudo em minúsculas)")
    }

    # 2. Caracteres inválidos (underscore e outros)
    if ($Nome -match '[_*#&+:<>?]') {
        $motivos.Add("Nome contém caracteres inválidos (proibido: _ * # & + : < > ?)")
    }

    # 3. Padrão geral: deve começar com 'pla-'
    if (-not $Nome.StartsWith("pla-")) {
        $motivos.Add("Nome não começa com 'pla-' (entidade PLANAPP)")
    }

    # 4. Estrutura mínima: pla-<dc>-<ambiente>-<projeto>-<prefixo><nº>
    $partes = $Nome.Split("-")
    if ($partes.Count -lt 4) {
        $motivos.Add("Nome tem menos de 4 segmentos separados por '-' (padrão: pla-dc-ambiente-projeto-prefixonº)")
    } else {
        # Verifica datacenter
        if ($partes.Count -ge 2 -and $partes[1] -notin $DATACENTERS_VALIDOS) {
            # Pode não ter datacenter (opcional), verificar se 2ª parte é ambiente
            if ($partes[1] -notin $AMBIENTES_VALIDOS) {
                $motivos.Add("Segmento de datacenter '$($partes[1])' não reconhecido. Valores válidos: $($DATACENTERS_VALIDOS -join ', ')")
            }
        }
        # Verifica presença de componente ambiente
        $temAmbiente = $partes | Where-Object { $_ -in $AMBIENTES_VALIDOS }
        if (-not $temAmbiente) {
            $motivos.Add("Nome não contém componente de ambiente. Valores válidos: $($AMBIENTES_VALIDOS -join ', ')")
        }
    }

    # 5. Detetar nomes auto-gerados pelo AI Foundry (padrão: nome-hashchars-região)
    if ($Nome -match '^[a-z]+-[a-z0-9]{5,10}-(swedencentral|westeurope|norwayeast|northeurope)$') {
        $motivos.Add("Nome auto-gerado pelo AI Foundry (padrão: pessoa-hash-região) — requer renomeação manual")
    }

    # 6. Numeração no final (deve terminar com 3 dígitos)
    if ($Nome -notmatch '\d{3}$') {
        # Só aplica se já passou nos outros critérios básicos (começa com pla-)
        if ($Nome.StartsWith("pla-")) {
            $motivos.Add("Nome não termina com numeração de 3 dígitos (ex: '001')")
        }
    }

    [PSCustomObject]@{
        IsConform = ($motivos.Count -eq 0)
        Motivos   = ($motivos -join " | ")
    }
}

function Get-TagsStatus {
    <#
    .SYNOPSIS Verifica presença das tags obrigatórias. #>
    param([hashtable]$Tags)

    $ausentes = [System.Collections.Generic.List[string]]::new()
    $presentes = [System.Collections.Generic.List[string]]::new()

    foreach ($tag in $TAGS_OBRIGATORIAS) {
        if ($Tags -and $Tags.ContainsKey($tag)) {
            $presentes.Add($tag)
        } else {
            $ausentes.Add($tag)
        }
    }
    [PSCustomObject]@{
        TagsPresentes  = ($presentes -join ", ")
        TagsAusentes   = ($ausentes -join ", ")
        TagsConformes  = ($ausentes.Count -eq 0)
    }
}

function Get-AmbienteConformidade {
    <#
    .SYNOPSIS Verifica se o ambiente do nome do recurso é coerente com a subscription. #>
    param(
        [string]$NomeRecurso,
        [string]$NomeSubscription
    )

    $ambienteEsperado = $SUB_AMBIENTE_MAP[$NomeSubscription]
    if (-not $ambienteEsperado) { return "Sub não mapeada" }

    $partes = $NomeRecurso.Split("-")
    $ambienteNoNome = $partes | Where-Object { $_ -in $AMBIENTES_VALIDOS } | Select-Object -First 1

    if (-not $ambienteNoNome) { return "Sem ambiente no nome" }

    # Casos especiais: nprd pode conter 'nrpd' (typo conhecido)
    $nomeNormalizado = $NomeRecurso -replace "nrpd", "nprd"
    $ambienteNoNomeNorm = $nomeNormalizado.Split("-") | Where-Object { $_ -in $AMBIENTES_VALIDOS } | Select-Object -First 1

    if ($ambienteNoNomeNorm -ne $ambienteEsperado) {
        return "CONFLITO: nome indica '$ambienteNoNomeNorm' mas subscription é '$ambienteEsperado'"
    }
    return "OK"
}

function Get-SafeProp {
    <#
    .SYNOPSIS Acesso seguro a propriedade de objeto — compatível com Set-StrictMode. #>
    param($Obj, [string]$Prop, $Default = "N/A")
    if ($null -eq $Obj) { return $Default }
    $p = $Obj.PSObject.Properties[$Prop]
    if ($null -ne $p) {
        $val = $p.Value
        if ($null -eq $val) { return $Default }
        return $val
    }
    return $Default
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. AUTENTICAÇÃO
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host   "║  PLANAPP — Inventário AI Foundry & Análise CAF              ║" -ForegroundColor Cyan
Write-Host   "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-Host "[1/5] A verificar autenticação..." -ForegroundColor Cyan
$ctx = Get-AzContext
if (-not $ctx) {
    Write-Host "     Sem sessão ativa. A iniciar login interativo..." -ForegroundColor Yellow
    Connect-AzAccount
    $ctx = Get-AzContext
}
Write-Host ("     Conta  : {0}" -f $ctx.Account.Id) -ForegroundColor Green
Write-Host ("     Tenant : {0}" -f $ctx.Tenant.Id)  -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# 2. RECOLHER SUBSCRIPTIONS
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[2/5] A recolher subscriptions ativas..." -ForegroundColor Cyan
$subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" } | Sort-Object Name
Write-Host ("     {0} subscription(s) encontrada(s)" -f $subscriptions.Count) -ForegroundColor Green

# Carregar mapa de owners dos RGs (do CSV mais recente do script 03)
$rgOwnerMap = @{}
$ownerCsv = Get-ChildItem -Path $OutputPath -Filter "03_rg_owners_*.csv" |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($ownerCsv) {
    Write-Host ("     Owners RG carregados de: {0}" -f $ownerCsv.Name) -ForegroundColor Gray
    Import-Csv $ownerCsv.FullName | ForEach-Object {
        $key = "$($_.SubscriptionId)|$($_.ResourceGroupName)"
        $rgOwnerMap[$key] = $_.OwnerDisplayNames
    }
} else {
    Write-Host "     Aviso: CSV de owners (03_rg_owners_*.csv) não encontrado — Owner ficará em branco" -ForegroundColor DarkYellow
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. INVENTÁRIO DE RECURSOS AI FOUNDRY
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[3/5] A recolher recursos AI Foundry..." -ForegroundColor Cyan

$inventario   = [System.Collections.Generic.List[PSObject]]::new()
$deployments  = [System.Collections.Generic.List[PSObject]]::new()

foreach ($sub in $subscriptions) {
    Write-Host ("     → {0}" -f $sub.Name) -ForegroundColor Gray
    Set-AzContext -SubscriptionId $sub.Id -WarningAction SilentlyContinue | Out-Null

    # ── 3a. MachineLearningServices Workspaces ────────────────────────────────
    $mlWorkspaces = Get-AzResource -ResourceType "Microsoft.MachineLearningServices/workspaces" `
                                   -ExpandProperties -ErrorAction SilentlyContinue

    foreach ($ws in $mlWorkspaces) {
        $kind = if ($ws.Kind) { $ws.Kind } else { "Default" }
        $props = $ws.Properties

        $nomCheck   = Test-NomenclaturaCAF -Nome $ws.Name -TipoRecurso $ws.ResourceType -Kind $kind
        $tagsStatus = Get-TagsStatus -Tags $ws.Tags
        $ambCheck   = Get-AmbienteConformidade -NomeRecurso $ws.Name -NomeSubscription $sub.Name

        $inventario.Add([PSCustomObject]@{
            Subscription         = $sub.Name
            SubscriptionId       = $sub.Id
            ResourceGroup        = $ws.ResourceGroupName
            Nome                 = $ws.Name
            Tipo                 = "MachineLearningServices/Workspace"
            Kind                 = $kind
            Localizacao          = $ws.Location
            ProvisioningState    = Get-SafeProp $props "provisioningState"
            PublicNetworkAccess  = Get-SafeProp $props "publicNetworkAccess"
            SKU                  = if ($ws.Sku) { $ws.Sku.Name } else { "Basic" }
            CriadoEm             = Get-SafeProp $props "creationTime"
            FriendlyName         = Get-SafeProp $props "friendlyName" ""
            HubAssociado         = ((Get-SafeProp $props "hubResourceId" "") -replace ".*/", "")
            ProjectosAssociados  = ($(try { $ap = Get-SafeProp $props "associatedWorkspaces" $null; if ($ap) { ($ap | ForEach-Object { ($_ -split "/")[-1] }) -join "; " } else { "" } } catch { "" }))
            StorageAccount       = ((Get-SafeProp $props "storageAccount" "") -replace ".*/", "")
            KeyVault             = ((Get-SafeProp $props "keyVault" "") -replace ".*/", "")
            AppInsights          = ((Get-SafeProp $props "applicationInsights" "") -replace ".*/", "")
            ContainerRegistry    = ((Get-SafeProp $props "containerRegistry" "") -replace ".*/", "")
            Tags                 = if ($ws.Tags) { ($ws.Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; " } else { "" }
            # Conformidade
            NomenclaturaCAF      = if ($nomCheck.IsConform) { "✔ Conforme" } else { "✘ Não conforme" }
            MotivoNomenclatura   = $nomCheck.Motivos
            TagsPresentes        = $tagsStatus.TagsPresentes
            TagsAusentes         = $tagsStatus.TagsAusentes
            TagsConformes        = if ($tagsStatus.TagsConformes) { "✔ Conforme" } else { "✘ Faltam tags" }
            AmbienteCoerente     = $ambCheck
            RedePublica          = if ((Get-SafeProp $props "publicNetworkAccess") -eq "Enabled") { "⚠ Exposta" } else { "✔ Restrita" }
            OwnerRG              = if ($rgOwnerMap.ContainsKey("$($sub.Id)|$($ws.ResourceGroupName)")) { $rgOwnerMap["$($sub.Id)|$($ws.ResourceGroupName)"] } else { "—" }
        })

        Write-Host ("       ML Workspace: {0} ({1})" -f $ws.Name, $kind) -ForegroundColor DarkGray
    }

    # ── 3b. CognitiveServices Accounts ───────────────────────────────────────
    $cogAccounts = Get-AzCognitiveServicesAccount -ErrorAction SilentlyContinue | `
                   Where-Object { $_.AccountName -ne $null }

    foreach ($acct in $cogAccounts) {
        $kind = if ($acct.AccountType) { $acct.AccountType } else { "Unknown" }
        $skuName = if ($acct.Sku) { $acct.Sku.Name } else { "N/A" }

        $nomCheck   = Test-NomenclaturaCAF -Nome $acct.AccountName -TipoRecurso "cognitiveservices/$kind" -Kind $kind
        $tagsStatus = Get-TagsStatus -Tags $acct.Tags
        $ambCheck   = Get-AmbienteConformidade -NomeRecurso $acct.AccountName -NomeSubscription $sub.Name
        $pna        = if ($acct.PublicNetworkAccess) { $acct.PublicNetworkAccess } else { "N/A" }

        $inventario.Add([PSCustomObject]@{
            Subscription         = $sub.Name
            SubscriptionId       = $sub.Id
            ResourceGroup        = $acct.ResourceGroupName
            Nome                 = $acct.AccountName
            Tipo                 = "CognitiveServices/$kind"
            Kind                 = $kind
            Localizacao          = $acct.Location
            ProvisioningState    = if ($acct.ProvisioningState) { $acct.ProvisioningState } else { "N/A" }
            PublicNetworkAccess  = $pna
            SKU                  = $skuName
            CriadoEm             = "N/A"
            FriendlyName         = ""
            HubAssociado         = ""
            ProjectosAssociados  = ""
            StorageAccount       = ""
            KeyVault             = ""
            AppInsights          = ""
            ContainerRegistry    = ""
            Tags                 = if ($acct.Tags) { ($acct.Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; " } else { "" }
            NomenclaturaCAF      = if ($nomCheck.IsConform) { "✔ Conforme" } else { "✘ Não conforme" }
            MotivoNomenclatura   = $nomCheck.Motivos
            TagsPresentes        = $tagsStatus.TagsPresentes
            TagsAusentes         = $tagsStatus.TagsAusentes
            TagsConformes        = if ($tagsStatus.TagsConformes) { "✔ Conforme" } else { "✘ Faltam tags" }
            AmbienteCoerente     = $ambCheck
            RedePublica          = if ($pna -eq "Enabled") { "⚠ Exposta" } else { "✔ Restrita" }
            OwnerRG              = if ($rgOwnerMap.ContainsKey("$($sub.Id)|$($acct.ResourceGroupName)")) { $rgOwnerMap["$($sub.Id)|$($acct.ResourceGroupName)"] } else { "—" }
        })

        Write-Host ("       CogSvc [{0}]: {1}" -f $kind, $acct.AccountName) -ForegroundColor DarkGray

        # ── 3c. Model Deployments ─────────────────────────────────────────────
        if ($IncludeModelDeployments -and ($kind -in @("OpenAI", "AIServices"))) {
            try {
                $modelDeploys = Get-AzCognitiveServicesAccountDeployment `
                    -ResourceGroupName $acct.ResourceGroupName `
                    -AccountName $acct.AccountName `
                    -ErrorAction SilentlyContinue

                if ($modelDeploys) {
                    foreach ($deploy in $modelDeploys) {
                        $dProps = $deploy.Properties
                        $deployments.Add([PSCustomObject]@{
                            Subscription      = $sub.Name
                            ResourceGroup     = $acct.ResourceGroupName
                            ContaAI           = $acct.AccountName
                            Kind              = $kind
                            Localizacao       = $acct.Location
                            DeploymentNome    = $deploy.Name
                            ModeloNome        = (Get-SafeProp (Get-SafeProp $dProps "Model" $null) "Name")
                            ModeloVersao      = (Get-SafeProp (Get-SafeProp $dProps "Model" $null) "Version")
                            ModeloFormato     = (Get-SafeProp (Get-SafeProp $dProps "Model" $null) "Format")
                            SkuNome           = if ($deploy.Sku) { $deploy.Sku.Name } else { "N/A" }
                            SkuCapacidade     = if ($deploy.Sku) { $deploy.Sku.Capacity } else { "N/A" }
                            ProvisioningState = (Get-SafeProp $dProps "ProvisioningState")
                            ScaleType         = (Get-SafeProp (Get-SafeProp $dProps "ScaleSettings" $null) "ScaleType")
                            RateLimitTPM      = "N/A"
                        })
                        $mName = Get-SafeProp (Get-SafeProp $dProps "Model" $null) "Name" "?"
                        $mVer  = Get-SafeProp (Get-SafeProp $dProps "Model" $null) "Version" "?"
                        $mCap  = if ($deploy.Sku) { $deploy.Sku.Capacity } else { "?" }
                        Write-Host ("         ↳ Deploy: {0} | {1} v{2} | {3} TPM" -f $deploy.Name, $mName, $mVer, $mCap) -ForegroundColor DarkGray
                    }
                } else {
                    Write-Host ("         ↳ Sem deployments de modelos") -ForegroundColor DarkYellow
                }
            } catch {
                Write-Host ("         ↳ Erro ao obter deployments: {0}" -f $_.Exception.Message) -ForegroundColor DarkRed
            }
        }
    }
}

Write-Host ("`n     Total recursos encontrados: {0}" -f $inventario.Count) -ForegroundColor Green
Write-Host ("     Total deployments de modelos: {0}" -f $deployments.Count) -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# 4. GERAR RELATÓRIO DE REMEDIAÇÃO
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[4/5] A gerar relatório de remediação..." -ForegroundColor Cyan

$remediacao = [System.Collections.Generic.List[PSObject]]::new()
$prioridades = @{ "Alta" = 1; "Média" = 2; "Baixa" = 3 }

foreach ($rec in $inventario) {

    # ── Problema: Nomenclatura não conforme ──────────────────────────────────
    if ($rec.NomenclaturaCAF -like "*Não conforme*") {

        # Determinar se é auto-gerado (prioridade alta)
        $isAutoGerado = $rec.MotivoNomenclatura -like "*auto-gerado*"
        $prioridade   = if ($isAutoGerado) { "Alta" } else { "Média" }

        # Sugerir nome correto (base)
        $ambienteProposto = if ($SUB_AMBIENTE_MAP[$rec.Subscription]) { $SUB_AMBIENTE_MAP[$rec.Subscription] } else { "nprd" }
        $dcProposto       = switch ($rec.Localizacao) {
            "swedencentral" { "sc" }
            "westeurope"    { "we" }
            "norwayeast"    { "no" }
            "northeurope"   { "ne" }
            default         { "we" }
        }
        $prefixoProposto = switch ($rec.Kind) {
            "OpenAI"         { "aoai" }
            "AIServices"     { "ais"  }
            "FormRecognizer" { "di"   }
            "Hub"            { "aihub"}
            "Project"        { "aiproj"}
            default          { "mlw"  }
        }
        $nomeSugerido = "pla-$dcProposto-$ambienteProposto-<projeto>-$prefixoProposto`001"

        $remediacao.Add([PSCustomObject]@{
            Prioridade       = $prioridade
            Subscription     = $rec.Subscription
            ResourceGroup    = $rec.ResourceGroup
            RecursoAtual     = $rec.Nome
            TipoRecurso      = $rec.Tipo
            Problema         = "Nomenclatura não conforme com CAF PLANAPP v1.1"
            Detalhe          = $rec.MotivoNomenclatura
            AcaoRecomendada  = if ($isAutoGerado) {
                "RECRIAR o recurso com nome conforme. Recursos auto-gerados pelo Foundry não podem ser renomeados diretamente. Nome sugerido: $nomeSugerido"
            } else {
                "Verificar nome e ajustar conforme padrão CAF. Nome sugerido (referência): $nomeSugerido"
            }
            NomeSugerido     = $nomeSugerido
            Referencia       = "PLANAPP-Política_Nomenclaturas_v1.1 §1 e §2"
        })
    }

    # ── Problema: Tags obrigatórias ausentes ─────────────────────────────────
    if ($rec.TagsConformes -like "*Faltam*") {
        $remediacao.Add([PSCustomObject]@{
            Prioridade       = "Média"
            Subscription     = $rec.Subscription
            ResourceGroup    = $rec.ResourceGroup
            RecursoAtual     = $rec.Nome
            TipoRecurso      = $rec.Tipo
            Problema         = "Tags obrigatórias ausentes"
            Detalhe          = "Tags em falta: $($rec.TagsAusentes)"
            AcaoRecomendada  = "Adicionar tags obrigatórias via Portal ou CLI: az resource tag --tags departamento=<val> ambiente=<val> projeto=<val> centrocusto=<val>"
            NomeSugerido     = "N/A"
            Referencia       = "PLANAPP-Política_Nomenclaturas_v1.1 §4 — Tags Obrigatórias"
        })
    }

    # ── Problema: Rede pública exposta ───────────────────────────────────────
    if ($rec.RedePublica -like "*Exposta*") {
        $remediacao.Add([PSCustomObject]@{
            Prioridade       = "Média"
            Subscription     = $rec.Subscription
            ResourceGroup    = $rec.ResourceGroup
            RecursoAtual     = $rec.Nome
            TipoRecurso      = $rec.Tipo
            Problema         = "Acesso público à rede ativo (publicNetworkAccess=Enabled)"
            Detalhe          = "Todos os 18 recursos AI têm rede pública ativa. Risco de exposição não autorizada."
            AcaoRecomendada  = "Avaliar necessidade de acesso público. Em ambientes PRD, configurar Private Endpoint e desativar acesso público. Em NPRD, restringir a IPs específicos via Network Rules."
            NomeSugerido     = "N/A"
            Referencia       = "Azure Security Best Practices — Network Security for AI Services"
        })
    }

    # ── Problema: Incoerência ambiente/subscription ──────────────────────────
    if ($rec.AmbienteCoerente -like "*CONFLITO*") {
        $remediacao.Add([PSCustomObject]@{
            Prioridade       = "Alta"
            Subscription     = $rec.Subscription
            ResourceGroup    = $rec.ResourceGroup
            RecursoAtual     = $rec.Nome
            TipoRecurso      = $rec.Tipo
            Problema         = "Incoerência entre ambiente no nome e subscription"
            Detalhe          = $rec.AmbienteCoerente
            AcaoRecomendada  = "Verificar se o recurso está na subscription correta. Se necessário, mover o recurso para a subscription adequada ao seu ambiente (PRD/NPRD)."
            NomeSugerido     = "N/A"
            Referencia       = "PLANAPP-Política_Nomenclaturas_v1.1 §1 — Componente Ambiente"
        })
    }
}

# Ordenar por prioridade
$remediacao = $remediacao | Sort-Object { $prioridades[$_.Prioridade] }, Subscription, RecursoAtual

Write-Host ("     {0} não-conformidade(s) identificada(s)" -f $remediacao.Count) -ForegroundColor Yellow
$remediacao | Group-Object Prioridade | ForEach-Object {
    $cor = switch ($_.Name) { "Alta" { "Red" } "Média" { "Yellow" } "Baixa" { "Gray" } default { "White" } }
    Write-Host ("       ▸ {0,-6}: {1}" -f $_.Name, $_.Count) -ForegroundColor $cor
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. EXPORTAR CSV
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[5/5] A exportar ficheiros CSV..." -ForegroundColor Cyan

$inventario  | Export-Csv -Path $csvInv    -NoTypeInformation -Encoding UTF8BOM
$deployments | Export-Csv -Path $csvDeploy -NoTypeInformation -Encoding UTF8BOM
$remediacao  | Export-Csv -Path $csvRemedCA -NoTypeInformation -Encoding UTF8BOM

Write-Host ("     ✔ Inventário     : {0}" -f $csvInv)    -ForegroundColor Green
Write-Host ("     ✔ Deployments    : {0}" -f $csvDeploy)  -ForegroundColor Green
Write-Host ("     ✔ Remediação     : {0}" -f $csvRemedCA) -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# SUMÁRIO EXECUTIVO
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host   "║  SUMÁRIO EXECUTIVO                                          ║" -ForegroundColor Cyan
Write-Host   "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

$totalRecursos   = $inventario.Count
$totalConformes  = ($inventario | Where-Object { $_.NomenclaturaCAF -like "*Conforme*" -and $_.NomenclaturaCAF -notlike "*Não*" }).Count
$totalDeployments= $deployments.Count
$totalOpenAI     = ($inventario | Where-Object { $_.Kind -eq "OpenAI" }).Count
$totalAIServices = ($inventario | Where-Object { $_.Kind -eq "AIServices" }).Count
$totalMLW        = ($inventario | Where-Object { $_.Tipo -like "*MachineLearning*" }).Count

Write-Host ("`n  Recursos AI Foundry inventariados : {0}" -f $totalRecursos)
Write-Host ("  ├─ MachineLearning Workspaces     : {0}" -f $totalMLW)
Write-Host ("  ├─ Azure OpenAI                   : {0}" -f $totalOpenAI)
Write-Host ("  ├─ AI Services                    : {0}" -f $totalAIServices)
Write-Host ("  └─ Document Intelligence          : {0}" -f ($inventario | Where-Object { $_.Kind -eq "FormRecognizer" }).Count)
Write-Host ("`n  Deployments de modelos            : {0}" -f $totalDeployments)
Write-Host ("`n  Conformidade nomenclatura CAF     : {0}/{1}" -f $totalConformes, $totalRecursos)
Write-Host ("`n  Não-conformidades identificadas   : {0}" -f $remediacao.Count)

$remediacao | Group-Object Prioridade | ForEach-Object {
    $cor = switch ($_.Name) { "Alta" { "Red" } "Média" { "Yellow" } default { "White" } }
    Write-Host ("  ├─ Prioridade {0,-6}: {1}" -f $_.Name, $_.Count) -ForegroundColor $cor
}

Write-Host "`n  Ficheiros gerados:"
Write-Host ("  ├─ {0}" -f (Split-Path $csvInv -Leaf))
Write-Host ("  ├─ {0}" -f (Split-Path $csvDeploy -Leaf))
Write-Host ("  └─ {0}" -f (Split-Path $csvRemedCA -Leaf))

Write-Host "`n  Concluído em $(Get-Date -Format 'HH:mm:ss')`n" -ForegroundColor Green
