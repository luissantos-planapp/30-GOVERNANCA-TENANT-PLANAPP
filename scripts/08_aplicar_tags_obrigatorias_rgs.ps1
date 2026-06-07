#Requires -Modules Az.Accounts, Az.Resources
<#
.SYNOPSIS
    Aplica tags obrigatorias nos Resource Groups e exporta CSV de controlo.
.DESCRIPTION
    Percorre todas as subscricoes ativas, garante as tags obrigatorias nos RGs:
    departamento, ambiente, projeto, centrocusto, owner.
    Exporta um CSV com as colunas:
    - subscrition
    - resource group
#>

param(
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\EstruturaTenantV2\csv"),
    [string]$DefaultTagValue = "PREENCHER",
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$requiredTags = @("departamento", "ambiente", "projeto", "centrocusto", "owner")
$timestamp = Get-Date -Format "yyyyMMdd_HHmm"

New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

$csvResourceGroups = Join-Path $OutputPath "08_resource_groups_tags_$timestamp.csv"
$csvTagChanges = Join-Path $OutputPath "08_tag_changes_$timestamp.csv"

Write-Host "\n[1/5] A verificar autenticacao..." -ForegroundColor Cyan
$ctx = Get-AzContext
if (-not $ctx) {
    Write-Host "     Sem sessao ativa. A iniciar login interativo..." -ForegroundColor Yellow
    Connect-AzAccount | Out-Null
    $ctx = Get-AzContext
}
Write-Host ("     Conta  : {0}" -f $ctx.Account.Id) -ForegroundColor Green
Write-Host ("     Tenant : {0}" -f $ctx.Tenant.Id) -ForegroundColor Green

Write-Host "\n[2/5] A recolher subscricoes ativas..." -ForegroundColor Cyan
$subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" } | Sort-Object Name
Write-Host ("     Subscricoes encontradas: {0}" -f $subscriptions.Count) -ForegroundColor Green

$rgRows = [System.Collections.Generic.List[PSObject]]::new()
$changes = [System.Collections.Generic.List[PSObject]]::new()

Write-Host "\n[3/5] A processar Resource Groups e tags obrigatorias..." -ForegroundColor Cyan
foreach ($sub in $subscriptions) {
    Write-Host ("     -> Subscricao: {0}" -f $sub.Name) -ForegroundColor DarkGray
    Set-AzContext -SubscriptionId $sub.Id -WarningAction SilentlyContinue | Out-Null

    $resourceGroups = Get-AzResourceGroup | Sort-Object ResourceGroupName
    foreach ($rg in $resourceGroups) {
        $rgRows.Add([PSCustomObject]@{
            "subscrition"   = $sub.Name
            "resource group" = $rg.ResourceGroupName
        })

        $currentTags = @{}
        if ($rg.Tags) {
            foreach ($k in $rg.Tags.Keys) {
                $currentTags[$k] = [string]$rg.Tags[$k]
            }
        }

        $updatedTags = @{}
        foreach ($k in $currentTags.Keys) {
            $updatedTags[$k] = $currentTags[$k]
        }

        $missingKeys = [System.Collections.Generic.List[string]]::new()
        foreach ($tagName in $requiredTags) {
            $existingKey = $null
            foreach ($k in $updatedTags.Keys) {
                if ($k.ToLower() -eq $tagName) {
                    $existingKey = $k
                    break
                }
            }

            if ($existingKey) {
                if ([string]::IsNullOrWhiteSpace([string]$updatedTags[$existingKey])) {
                    $updatedTags[$existingKey] = $DefaultTagValue
                    $missingKeys.Add($tagName)
                }
            }
            else {
                $updatedTags[$tagName] = $DefaultTagValue
                $missingKeys.Add($tagName)
            }
        }

        if ($missingKeys.Count -gt 0) {
            if (-not $WhatIf) {
                try {
                    Set-AzResourceGroup -Name $rg.ResourceGroupName -Tag $updatedTags -ErrorAction Stop | Out-Null
                    $changes.Add([PSCustomObject]@{
                        SubscriptionName = $sub.Name
                        SubscriptionId   = $sub.Id
                        ResourceGroup    = $rg.ResourceGroupName
                        MissingTags      = ($missingKeys -join ",")
                        AppliedValue     = $DefaultTagValue
                        Mode             = "Applied"
                    })
                }
                catch {
                    $changes.Add([PSCustomObject]@{
                        SubscriptionName = $sub.Name
                        SubscriptionId   = $sub.Id
                        ResourceGroup    = $rg.ResourceGroupName
                        MissingTags      = ($missingKeys -join ",")
                        AppliedValue     = $DefaultTagValue
                        Mode             = "Failed"
                    })
                    Write-Warning ("Falha ao atualizar tags em {0} / {1}: {2}" -f $sub.Name, $rg.ResourceGroupName, $_.Exception.Message)
                }
            }
            else {
                $changes.Add([PSCustomObject]@{
                    SubscriptionName = $sub.Name
                    SubscriptionId   = $sub.Id
                    ResourceGroup    = $rg.ResourceGroupName
                    MissingTags      = ($missingKeys -join ",")
                    AppliedValue     = $DefaultTagValue
                    Mode             = "WhatIf"
                })
            }
        }
    }
}

Write-Host "\n[4/5] A exportar CSVs..." -ForegroundColor Cyan
$rgRows | Export-Csv -Path $csvResourceGroups -NoTypeInformation -Encoding UTF8 -Delimiter ';'
$changes | Export-Csv -Path $csvTagChanges -NoTypeInformation -Encoding UTF8 -Delimiter ';'

Write-Host "\n[5/5] Resumo" -ForegroundColor Cyan
Write-Host ("     Total de Resource Groups: {0}" -f $rgRows.Count) -ForegroundColor Green
Write-Host ("     RGs com tags criadas/atualizadas: {0}" -f $changes.Count) -ForegroundColor Green
Write-Host ("     CSV de RGs: {0}" -f $csvResourceGroups) -ForegroundColor Green
Write-Host ("     CSV de alteracoes: {0}" -f $csvTagChanges) -ForegroundColor Green
