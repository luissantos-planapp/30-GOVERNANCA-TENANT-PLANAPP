#Requires -Modules Az.Accounts, Az.ResourceGraph
<#
.SYNOPSIS
    Inventário completo de todos os recursos Azure em todas as subscrições do tenant PLANAPP.
.DESCRIPTION
    Usa o Azure Resource Graph para listar todos os recursos do tenant numa única query,
    sem necessidade de iterar por cada subscrição. Exporta CSV com todos os recursos
    e análise de conformidade de nomenclatura vs. política PLANAPP.
    Projeto: 20260320-001 — Governança do Tenant PLANAPP
.NOTES
    Autor  : Luís Santos / PLANAPP SITDIA
    Data   : 2026-03-21
    Versão : 1.0
#>

param(
    [string]$OutputPath = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$timestamp = Get-Date -Format "yyyyMMdd_HHmm"
$csvAll    = Join-Path $OutputPath "04_inventario_recursos_$timestamp.csv"
$csvNaming = Join-Path $OutputPath "05_naming_compliance_$timestamp.csv"
$csvTags   = Join-Path $OutputPath "06_tags_compliance_$timestamp.csv"

# ─────────────────────────────────────────────
# Padrão de nomenclatura PLANAPP (v1.1)
# Prefixos por tipo de recurso
# ─────────────────────────────────────────────
$prefixMap = @{
    "microsoft.compute/virtualmachines"              = "vm"
    "microsoft.compute/virtualmachinescalesets"      = "vmss"
    "microsoft.compute/disks"                        = "disk"
    "microsoft.compute/snapshots"                    = "snap"
    "microsoft.compute/availabilitysets"             = "avail"
    "microsoft.compute/galleries"                    = "cgall"
    "microsoft.compute/images"                       = "imdef"
    "microsoft.network/virtualnetworks"              = "vnet"
    "microsoft.network/networksecuritygroups"        = "nsg"
    "microsoft.network/publicipaddresses"            = "pip"
    "microsoft.network/networkinterfaces"            = "nic"
    "microsoft.network/loadbalancers"                = "lb"
    "microsoft.network/applicationgateways"          = "agw"
    "microsoft.network/firewalls"                    = "afw"
    "microsoft.network/firewallpolicies"             = "afwp"
    "microsoft.network/virtualnetworkgateways"       = "vgw"
    "microsoft.network/localnetworkgateways"         = "lgw"
    "microsoft.network/connections"                  = "con"
    "microsoft.network/routetables"                  = "rt"
    "microsoft.network/privatednszones"              = "dnspr"
    "microsoft.network/privateendpoints"             = "pep"
    "microsoft.network/bastionhosts"                 = "bas"
    "microsoft.network/natgateways"                  = "ng"
    "microsoft.storage/storageaccounts"              = "sa"
    "microsoft.keyvault/vaults"                      = "kv"
    "microsoft.web/sites"                            = "app"
    "microsoft.web/serverfarms"                      = "asp"
    "microsoft.insights/components"                  = "appi"
    "microsoft.operationalinsights/workspaces"       = "law"
    "microsoft.containerregistry/registries"         = "cr"
    "microsoft.containerservice/managedclusters"     = "aks"
    "microsoft.app/containerapps"                    = "ca"
    "microsoft.app/managedenvironments"              = "cae"
    "microsoft.servicebus/namespaces"                = "sb"
    "microsoft.eventhub/namespaces"                  = "evhns"
    "microsoft.sql/servers"                          = "sql"
    "microsoft.sql/servers/databases"                = "sqldb"
    "microsoft.documentdb/databaseaccounts"          = "cosmos"
    "microsoft.datafactory/factories"                = "adf"
    "microsoft.cognitiveservices/accounts"           = "cog"
    "microsoft.machinelearningservices/workspaces"   = "mlw"
    "microsoft.apimanagement/service"                = "apim"
    "microsoft.logic/workflows"                      = "logic"
    "microsoft.automation/automationaccounts"        = "aa"
    "microsoft.recoveryservices/vaults"              = "rsv"
    "microsoft.notificationhubs/namespaces"          = "nhn"
    "microsoft.signalrservice/signalr"               = "sigr"
    "microsoft.search/searchservices"                = "srch"
    "microsoft.cache/redis"                          = "redis"
    "microsoft.cdn/profiles"                         = "cdnp"
    "microsoft.resources/resourcegroups"             = "rg"
}

# Tags obrigatórias PLANAPP
$mandatoryTags = @("departamento", "ambiente", "projeto", "centrocusto")

# ─────────────────────────────────────────────
# 1. Autenticação
# ─────────────────────────────────────────────
Write-Host "`n[1/4] A verificar autenticação..." -ForegroundColor Cyan
$ctx = Get-AzContext
if (-not $ctx) {
    Write-Host "     Sem sessão ativa. A iniciar login..." -ForegroundColor Yellow
    Connect-AzAccount -AccountId "luis.santos@planapp.gov.pt"
    $ctx = Get-AzContext
}
Write-Host ("     Conta  : {0}" -f $ctx.Account.Id) -ForegroundColor Green
Write-Host ("     Tenant : {0}" -f $ctx.Tenant.Id)  -ForegroundColor Green

# ─────────────────────────────────────────────
# 2. Inventário via Azure Resource Graph
# ─────────────────────────────────────────────
Write-Host "`n[2/4] A recolher todos os recursos via Azure Resource Graph..." -ForegroundColor Cyan
Write-Host "      (query cross-subscription — pode demorar alguns segundos)" -ForegroundColor Gray

$query = @"
Resources
| project
    id,
    name,
    type,
    resourceGroup,
    location,
    subscriptionId,
    tags,
    kind,
    sku = tostring(sku),
    provisioningState = tostring(properties.provisioningState)
| order by subscriptionId asc, type asc, name asc
"@

# Paginar resultados (Resource Graph devolve max 1000 por página)
$allResources = [System.Collections.Generic.List[PSObject]]::new()
$skipToken    = $null

do {
    $params = @{ Query = $query; First = 1000 }
    if ($skipToken) { $params["SkipToken"] = $skipToken }

    $result    = Search-AzGraph @params
    $allResources.AddRange($result.Data)
    $skipToken = $result.SkipToken
    Write-Host ("      ... {0} recursos recolhidos" -f $allResources.Count) -ForegroundColor Gray
} while ($skipToken)

Write-Host ("     Total de recursos: {0}" -f $allResources.Count) -ForegroundColor Green

# ─────────────────────────────────────────────
# 3. Exportar inventário completo
# ─────────────────────────────────────────────
Write-Host "`n[3/4] A processar e exportar inventário..." -ForegroundColor Cyan

# Obter nome da subscrição (cache)
$subNames = @{}
Get-AzSubscription | ForEach-Object { $subNames[$_.Id] = $_.Name }

$resourceRows    = [System.Collections.Generic.List[PSObject]]::new()
$namingRows      = [System.Collections.Generic.List[PSObject]]::new()
$tagRows         = [System.Collections.Generic.List[PSObject]]::new()

foreach ($r in $allResources) {
    $subName   = $subNames[$r.subscriptionId] ?? $r.subscriptionId
    $typeNorm  = $r.type.ToLower()
    $prefix    = $prefixMap[$typeNorm]
    $tagsObj   = $r.tags

    # ── Tags: verificar obrigatórias ──
    $tagsJson     = if ($tagsObj) { ($tagsObj | ConvertTo-Json -Compress) } else { "{}" }
    $tagKeys      = if ($tagsObj) { ($tagsObj.PSObject.Properties.Name | ForEach-Object { $_.ToLower() }) } else { @() }
    $tagsOk       = $true
    $tagsFaltando = @()
    foreach ($tag in $mandatoryTags) {
        if ($tagKeys -notcontains $tag) {
            $tagsOk = $false
            $tagsFaltando += $tag
        }
    }

    # ── Nomenclatura: verificar padrão pla- ──
    $namingOk     = $false
    $namingIssue  = ""
    if ($prefix) {
        # Padrão: começa com pla- E contém o prefixo esperado
        if ($r.name -match "^pla[-]" -and $r.name -match "[-]${prefix}\d{3}") {
            $namingOk = $true
        } elseif ($r.name -match "^pla" -and $r.name -match $prefix) {
            # Storage accounts (sem hífens): plawehubnetsecsa001
            $namingOk = $true
        } else {
            $namingIssue = "Nome não segue padrão: esperado prefixo '$prefix' com convenção pla-*-$prefix+NNN"
        }
    } else {
        $namingIssue = "Tipo de recurso sem prefixo mapeado na política"
    }

    # ── Row completo ──
    $row = [PSCustomObject]@{
        SubscriptionName  = $subName
        SubscriptionId    = $r.subscriptionId
        ResourceGroup     = $r.resourceGroup
        Name              = $r.name
        Type              = $r.type
        Location          = $r.location
        Kind              = $r.kind
        SKU               = $r.sku
        ProvisioningState = $r.provisioningState
        Tags              = $tagsJson
        TagsOK            = $tagsOk
        TagsFaltando      = ($tagsFaltando -join ", ")
        NamingOK          = $namingOk
        NamingIssue       = $namingIssue
        PrefixEsperado    = $prefix
    }
    $resourceRows.Add($row)

    # ── Rows específicos de naming ──
    if (-not $namingOk -and $prefix) {
        $namingRows.Add([PSCustomObject]@{
            SubscriptionName = $subName
            ResourceGroup    = $r.resourceGroup
            Name             = $r.name
            Type             = $r.type
            PrefixEsperado   = $prefix
            Problema         = $namingIssue
        })
    }

    # ── Rows específicos de tags ──
    if (-not $tagsOk) {
        $tagRows.Add([PSCustomObject]@{
            SubscriptionName = $subName
            ResourceGroup    = $r.resourceGroup
            Name             = $r.name
            Type             = $r.type
            TagsFaltando     = ($tagsFaltando -join ", ")
            TagsPresentes    = ($tagKeys -join ", ")
        })
    }
}

$resourceRows | Export-Csv -Path $csvAll    -NoTypeInformation -Encoding UTF8
$namingRows   | Export-Csv -Path $csvNaming -NoTypeInformation -Encoding UTF8
$tagRows      | Export-Csv -Path $csvTags   -NoTypeInformation -Encoding UTF8

# ─────────────────────────────────────────────
# 4. Resumo
# ─────────────────────────────────────────────
Write-Host "`n[4/4] A calcular métricas de conformidade..." -ForegroundColor Cyan

$totalRecursos    = $resourceRows.Count
$namingOkCount    = ($resourceRows | Where-Object { $_.NamingOK }).Count
$namingNokCount   = ($resourceRows | Where-Object { -not $_.NamingOK -and $_.PrefixEsperado }).Count
$tagsOkCount      = ($resourceRows | Where-Object { $_.TagsOK }).Count
$tagsNokCount     = ($resourceRows | Where-Object { -not $_.TagsOK }).Count
$namingPct        = if ($totalRecursos) { [math]::Round($namingOkCount / $totalRecursos * 100, 1) } else { 0 }
$tagsPct          = if ($totalRecursos) { [math]::Round($tagsOkCount  / $totalRecursos * 100, 1) } else { 0 }

# Tipos mais comuns
$topTypes = $resourceRows | Group-Object Type | Sort-Object Count -Descending | Select-Object -First 10

# Por subscrição
$porSub = $resourceRows | Group-Object SubscriptionName | Sort-Object Count -Descending |
          Select-Object Name, Count

# Regiões
$porRegiao = $resourceRows | Group-Object Location | Sort-Object Count -Descending |
             Select-Object Name, Count

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor White
Write-Host " INVENTÁRIO COMPLETO — RESUMO" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor White
Write-Host (" Total de recursos analisados : {0}" -f $totalRecursos)
Write-Host ""
Write-Host " Conformidade de Nomenclatura (política PLANAPP v1.1):"
Write-Host ("   Conforme    : {0,4}  ({1}%)" -f $namingOkCount,  $namingPct)  -ForegroundColor Green
Write-Host ("   Não conforme: {0,4}  ({1}%)" -f $namingNokCount, (100 - $namingPct)) -ForegroundColor $(if ($namingNokCount -gt 0) {"Red"} else {"Green"})
Write-Host ""
Write-Host " Conformidade de Tags obrigatórias:"
Write-Host ("   Com todas as tags    : {0,4}  ({1}%)" -f $tagsOkCount,  $tagsPct) -ForegroundColor Green
Write-Host ("   Com tags em falta    : {0,4}  ({1}%)" -f $tagsNokCount, (100 - $tagsPct)) -ForegroundColor $(if ($tagsNokCount -gt 0) {"Yellow"} else {"Green"})
Write-Host ""
Write-Host " Recursos por Subscrição:"
$porSub | ForEach-Object { Write-Host ("   {0,-40} {1}" -f $_.Name, $_.Count) }
Write-Host ""
Write-Host " Top 10 tipos de recursos:"
$topTypes | ForEach-Object { Write-Host ("   {0,-55} {1}" -f $_.Name, $_.Count) }
Write-Host ""
Write-Host " Regiões utilizadas:"
$porRegiao | ForEach-Object { Write-Host ("   {0,-30} {1}" -f $_.Name, $_.Count) }
Write-Host ""
Write-Host " Ficheiros gerados:"
Write-Host ("   {0}" -f $csvAll)
Write-Host ("   {0}" -f $csvNaming)
Write-Host ("   {0}" -f $csvTags)
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor White
