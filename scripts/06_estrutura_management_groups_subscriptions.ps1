#Requires -Modules Az.Accounts, Az.Resources
<#
.SYNOPSIS
    Levantamento da estrutura de Management Groups e subscriptions associadas.
.DESCRIPTION
    Script de governanca que recolhe a arvore de Management Groups do tenant,
    identifica as subscriptions associadas e exporta o resultado para CSV.
.NOTES
    Autor  : Luis Santos / PLANAPP SITDIA
    Data   : 2026-06-06
    Versao : 1.0
#>

param(
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "EstruturaTenantV2\ManagementGroups"),
    [switch]$IncludeDisabledSubscriptions
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$timestamp = Get-Date -Format "yyyyMMdd_HHmm"
$csvPath   = Join-Path $OutputPath "06_management_groups_estrutura_$timestamp.csv"

if (-not (Test-Path -Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

Write-Host "`n[1/4] A verificar autenticacao..." -ForegroundColor Cyan
$ctx = Get-AzContext
if (-not $ctx) {
    Write-Host "     Sem sessao ativa. A iniciar login interativo..." -ForegroundColor Yellow
    Connect-AzAccount | Out-Null
    $ctx = Get-AzContext
}
Write-Host ("     Conta  : {0}" -f $ctx.Account.Id) -ForegroundColor Green
Write-Host ("     Tenant : {0}" -f $ctx.Tenant.Id) -ForegroundColor Green

Write-Host "`n[2/4] A recolher subscriptions do tenant..." -ForegroundColor Cyan
$subscriptions = Get-AzSubscription -TenantId $ctx.Tenant.Id | Sort-Object Name
if (-not $IncludeDisabledSubscriptions) {
    $subscriptions = $subscriptions | Where-Object { $_.State -eq "Enabled" }
}

$subscriptionById = @{}
foreach ($s in $subscriptions) {
    $subscriptionById[$s.Id] = $s
}

$rows = [System.Collections.Generic.List[PSObject]]::new()

function Add-ManagementGroupTree {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Node,

        [string]$ParentManagementGroupId,

        [int]$Depth = 0
    )

    $rows.Add([PSCustomObject]@{
        NodeType                 = "ManagementGroup"
        Depth                    = $Depth
        ManagementGroupId        = $Node.Name
        ManagementGroupName      = $Node.DisplayName
        ParentManagementGroupId  = $ParentManagementGroupId
        SubscriptionId           = ""
        SubscriptionName         = ""
        SubscriptionState        = ""
        TenantId                 = $ctx.Tenant.Id
    })

    foreach ($child in @($Node.Children)) {
        if (-not $child) {
            continue
        }

        if ($child.Type -match "managementGroups") {
            Add-ManagementGroupTree -Node $child -ParentManagementGroupId $Node.Name -Depth ($Depth + 1)
            continue
        }

        if ($child.Type -match "subscriptions") {
            $subId = $child.Name
            $sub   = $subscriptionById[$subId]

            $rows.Add([PSCustomObject]@{
                NodeType                 = "Subscription"
                Depth                    = $Depth + 1
                ManagementGroupId        = $Node.Name
                ManagementGroupName      = $Node.DisplayName
                ParentManagementGroupId  = $Node.Name
                SubscriptionId           = $subId
                SubscriptionName         = if ($sub) { $sub.Name } else { $child.DisplayName }
                SubscriptionState        = if ($sub) { $sub.State } else { "Unknown" }
                TenantId                 = $ctx.Tenant.Id
            })
        }
    }
}

Write-Host "`n[3/4] A recolher estrutura de Management Groups..." -ForegroundColor Cyan
try {
    $tenantRoot = Get-AzManagementGroup -GroupName $ctx.Tenant.Id -Expand -Recurse -WarningAction SilentlyContinue
}
catch {
    throw "Falha ao obter Management Groups. Verifique permissoes (Management Group Reader no tenant root). Detalhe: $($_.Exception.Message)"
}

if (-not $tenantRoot) {
    throw "Nao foi possivel obter o Root Management Group do tenant atual."
}

Add-ManagementGroupTree -Node $tenantRoot -ParentManagementGroupId "" -Depth 0

Write-Host "`n[4/4] A exportar resultado..." -ForegroundColor Cyan
$rows |
    Sort-Object Depth, NodeType, ManagementGroupName, SubscriptionName |
    Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

Write-Host "" 
Write-Host "Estrutura (vista resumida):" -ForegroundColor White
$rows |
    Sort-Object Depth, NodeType, ManagementGroupName, SubscriptionName |
    ForEach-Object {
        $indent = "  " * [Math]::Max($_.Depth, 0)
        if ($_.NodeType -eq "ManagementGroup") {
            Write-Host ("{0}- MG  : {1} ({2})" -f $indent, $_.ManagementGroupName, $_.ManagementGroupId)
        }
        else {
            Write-Host ("{0}- SUB : {1} ({2})" -f $indent, $_.SubscriptionName, $_.SubscriptionId)
        }
    }

$mgCount   = ($rows | Where-Object { $_.NodeType -eq "ManagementGroup" }).Count
$subCount  = ($rows | Where-Object { $_.NodeType -eq "Subscription" }).Count

Write-Host ""
Write-Host "Resumo:" -ForegroundColor White
Write-Host ("  Management Groups : {0}" -f $mgCount)
Write-Host ("  Subscriptions     : {0}" -f $subCount)
Write-Host ("  CSV               : {0}" -f $csvPath)
Write-Host ""
