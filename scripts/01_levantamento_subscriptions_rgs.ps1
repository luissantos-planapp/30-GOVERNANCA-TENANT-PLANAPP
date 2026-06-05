#Requires -Modules Az.Accounts, Az.Resources
<#
.SYNOPSIS
    Levantamento de Subscriptions e Resource Groups do tenant PLANAPP.
.DESCRIPTION
    Script de governança que lista todas as subscriptions e resource groups do tenant,
    cruza com as atribuições RBAC (owners) e exporta para CSV.
    Projeto: 20260320-001 — Governança do Tenant PLANAPP
.NOTES
    Autor  : Luís Santos / PLANAPP SITDIA
    Data   : 2026-03-20
    Versão : 1.0
#>

param(
    [string]$OutputPath = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$timestamp   = Get-Date -Format "yyyyMMdd_HHmm"
$outDir      = $OutputPath
$csvSubs     = Join-Path $outDir "01_subscriptions_$timestamp.csv"
$csvRGs      = Join-Path $outDir "02_resource_groups_$timestamp.csv"
$csvOwners   = Join-Path $outDir "03_rg_owners_$timestamp.csv"

# ─────────────────────────────────────────────
# 1. Autenticação
# ─────────────────────────────────────────────
Write-Host "`n[1/4] A verificar autenticação..." -ForegroundColor Cyan
$ctx = Get-AzContext
if (-not $ctx) {
    Write-Host "     Sem sessão ativa. A iniciar login interativo..." -ForegroundColor Yellow
    Connect-AzAccount
    $ctx = Get-AzContext
}
Write-Host ("     Conta  : {0}" -f $ctx.Account.Id) -ForegroundColor Green
Write-Host ("     Tenant : {0}" -f $ctx.Tenant.Id)  -ForegroundColor Green

# ─────────────────────────────────────────────
# 2. Listar Subscriptions
# ─────────────────────────────────────────────
Write-Host "`n[2/4] A recolher subscriptions do tenant..." -ForegroundColor Cyan
$subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" } | Sort-Object Name

$subRows = $subscriptions | ForEach-Object {
    [PSCustomObject]@{
        SubscriptionName = $_.Name
        SubscriptionId   = $_.Id
        TenantId         = $_.TenantId
        State            = $_.State
    }
}

$subRows | Export-Csv -Path $csvSubs -NoTypeInformation -Encoding UTF8
Write-Host ("     {0} subscriptions encontradas → {1}" -f $subRows.Count, $csvSubs) -ForegroundColor Green

# Mostrar tabela no ecrã
$subRows | Format-Table -AutoSize

# ─────────────────────────────────────────────
# 3. Listar Resource Groups (todas as subs)
# ─────────────────────────────────────────────
Write-Host "`n[3/4] A recolher Resource Groups em todas as subscriptions..." -ForegroundColor Cyan
$rgRows = [System.Collections.Generic.List[PSObject]]::new()

foreach ($sub in $subscriptions) {
    Write-Host ("     → Sub: {0}" -f $sub.Name) -ForegroundColor Gray
    Set-AzContext -SubscriptionId $sub.Id -WarningAction SilentlyContinue | Out-Null

    $rgs = Get-AzResourceGroup | Sort-Object ResourceGroupName
    foreach ($rg in $rgs) {
        $rgRows.Add([PSCustomObject]@{
            SubscriptionName  = $sub.Name
            SubscriptionId    = $sub.Id
            ResourceGroupName = $rg.ResourceGroupName
            Location          = $rg.Location
            ProvisioningState = $rg.ProvisioningState
            Tags              = ($rg.Tags | ConvertTo-Json -Compress -ErrorAction SilentlyContinue)
        })
    }
}

$rgRows | Export-Csv -Path $csvRGs -NoTypeInformation -Encoding UTF8
Write-Host ("     {0} resource groups encontrados → {1}" -f $rgRows.Count, $csvRGs) -ForegroundColor Green

# ─────────────────────────────────────────────
# 4. Levantamento de Owners por Resource Group
# ─────────────────────────────────────────────
Write-Host "`n[4/4] A recolher atribuições RBAC (Owner) por Resource Group..." -ForegroundColor Cyan
$ownerRows = [System.Collections.Generic.List[PSObject]]::new()

foreach ($sub in $subscriptions) {
    Write-Host ("     → Sub: {0}" -f $sub.Name) -ForegroundColor Gray
    Set-AzContext -SubscriptionId $sub.Id -WarningAction SilentlyContinue | Out-Null

    $rgs = Get-AzResourceGroup
    foreach ($rg in $rgs) {
        $scope = "/subscriptions/$($sub.Id)/resourceGroups/$($rg.ResourceGroupName)"

        # Owners diretos no RG
        $owners = Get-AzRoleAssignment -Scope $scope -RoleDefinitionName "Owner" `
                    -ErrorAction SilentlyContinue |
                  Where-Object { $_.Scope -eq $scope }   # excluir herança da sub

        if ($owners) {
            foreach ($o in $owners) {
                $ownerRows.Add([PSCustomObject]@{
                    SubscriptionName  = $sub.Name
                    SubscriptionId    = $sub.Id
                    ResourceGroupName = $rg.ResourceGroupName
                    Location          = $rg.Location
                    OwnerDisplayName  = $o.DisplayName
                    OwnerSignInName   = $o.SignInName
                    OwnerObjectType   = $o.ObjectType   # User, Group, ServicePrincipal
                    OwnerObjectId     = $o.ObjectId
                    RoleScope         = $o.Scope
                    Inherited         = $false
                })
            }
        } else {
            # RG sem owner direto
            $ownerRows.Add([PSCustomObject]@{
                SubscriptionName  = $sub.Name
                SubscriptionId    = $sub.Id
                ResourceGroupName = $rg.ResourceGroupName
                Location          = $rg.Location
                OwnerDisplayName  = "⚠️ SEM OWNER DIRETO"
                OwnerSignInName   = ""
                OwnerObjectType   = ""
                OwnerObjectId     = ""
                RoleScope         = ""
                Inherited         = $null
            })
        }
    }
}

$ownerRows | Export-Csv -Path $csvOwners -NoTypeInformation -Encoding UTF8
Write-Host ("     Resultado exportado → {0}" -f $csvOwners) -ForegroundColor Green

# ─────────────────────────────────────────────
# Resumo final
# ─────────────────────────────────────────────
$semOwner     = ($ownerRows | Where-Object { $_.OwnerDisplayName -like "*SEM OWNER*" }).Count
$comOwner     = ($ownerRows | Where-Object { $_.OwnerDisplayName -notlike "*SEM OWNER*" }).Count
$tiposConta   = $ownerRows | Where-Object { $_.OwnerObjectType } | 
                Group-Object OwnerObjectType | Select-Object Name, Count

Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor White
Write-Host " RESUMO DO LEVANTAMENTO" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor White
Write-Host (" Subscriptions analisadas : {0}" -f $subscriptions.Count)
Write-Host (" Resource Groups total    : {0}" -f $rgRows.Count)
Write-Host (" RGs com Owner direto     : {0}" -f $comOwner) -ForegroundColor Green
Write-Host (" RGs SEM Owner direto     : {0}" -f $semOwner) -ForegroundColor $(if ($semOwner -gt 0) {"Red"} else {"Green"})
Write-Host ""
Write-Host " Tipos de conta com role Owner:"
$tiposConta | ForEach-Object { Write-Host ("   {0,-20} {1}" -f $_.Name, $_.Count) }
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor White
Write-Host "`n Ficheiros gerados:"
Write-Host ("   {0}" -f $csvSubs)
Write-Host ("   {0}" -f $csvRGs)
Write-Host ("   {0}" -f $csvOwners)
Write-Host ""
