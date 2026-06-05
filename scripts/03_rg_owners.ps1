#Requires -Modules Az.Accounts, Az.Resources
<#
.SYNOPSIS
    Exporta todos os Resource Groups do tenant com os respetivos owners (uma linha por RG).
.DESCRIPTION
    Lista todos os RGs em todas as subscriptions ativas e cruza com atribuições RBAC Owner
    diretas (scope == RG). Owners múltiplos são concatenados com "; " numa única coluna.
    Exporta CSV: 03_rg_owners_YYYYMMDD_HHmm.csv
    Projeto: 20260320-001 — Governança do Tenant PLANAPP
.NOTES
    Autor  : Luís Santos / PLANAPP SITDIA
    Data   : 2026-03-24
    Versão : 1.0
#>

param(
    [string]$OutputPath = (Split-Path $PSScriptRoot -Parent)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$timestamp = Get-Date -Format "yyyyMMdd_HHmm"
$csvOut    = Join-Path $OutputPath "03_rg_owners_$timestamp.csv"

# ─────────────────────────────────────────────
# 1. Autenticação
# ─────────────────────────────────────────────
Write-Host "`n[1/3] A verificar autenticação..." -ForegroundColor Cyan
$ctx = Get-AzContext
if (-not $ctx) {
    Write-Host "     Sem sessão ativa. A iniciar login interativo..." -ForegroundColor Yellow
    Connect-AzAccount
    $ctx = Get-AzContext
}
Write-Host ("     Conta  : {0}" -f $ctx.Account.Id) -ForegroundColor Green
Write-Host ("     Tenant : {0}" -f $ctx.Tenant.Id)  -ForegroundColor Green

# ─────────────────────────────────────────────
# 2. Recolher subscriptions ativas
# ─────────────────────────────────────────────
Write-Host "`n[2/3] A recolher subscriptions..." -ForegroundColor Cyan
$subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" } | Sort-Object Name
Write-Host ("     {0} subscription(s) encontrada(s)" -f $subscriptions.Count) -ForegroundColor Green

# ─────────────────────────────────────────────
# 3. Recolher RGs e owners
# ─────────────────────────────────────────────
Write-Host "`n[3/3] A recolher Resource Groups e owners RBAC..." -ForegroundColor Cyan
$rows = [System.Collections.Generic.List[PSObject]]::new()

foreach ($sub in $subscriptions) {
    Write-Host ("     → {0}" -f $sub.Name) -ForegroundColor Gray
    Set-AzContext -SubscriptionId $sub.Id -WarningAction SilentlyContinue | Out-Null

    $rgs = Get-AzResourceGroup | Sort-Object ResourceGroupName

    foreach ($rg in $rgs) {
        $scope = "/subscriptions/$($sub.Id)/resourceGroups/$($rg.ResourceGroupName)"

        # Owners com scope exato no RG (não herdados da subscription)
        $owners = @(Get-AzRoleAssignment -Scope $scope -RoleDefinitionName "Owner" `
                    -ErrorAction SilentlyContinue |
                  Where-Object { $_.Scope -eq $scope })

        if ($owners) {
            $ownerNames  = ($owners | ForEach-Object { $_.DisplayName })  -join "; "
            $ownerEmails = ($owners | ForEach-Object { $_.SignInName })    -join "; "
            $ownerTypes  = ($owners | ForEach-Object { $_.ObjectType })    -join "; "
            $ownerIds    = ($owners | ForEach-Object { $_.ObjectId })      -join "; "
            $ownerCount  = $owners.Count
            $semOwner    = $false
        } else {
            $ownerNames  = "⚠️ SEM OWNER DIRETO"
            $ownerEmails = ""
            $ownerTypes  = ""
            $ownerIds    = ""
            $ownerCount  = 0
            $semOwner    = $true
        }

        $rows.Add([PSCustomObject]@{
            SubscriptionName  = $sub.Name
            SubscriptionId    = $sub.Id
            ResourceGroupName = $rg.ResourceGroupName
            Location          = $rg.Location
            ProvisioningState = $rg.ProvisioningState
            OwnerCount        = $ownerCount
            SemOwnerDireto    = $semOwner
            OwnerDisplayNames = $ownerNames
            OwnerSignInNames  = $ownerEmails
            OwnerObjectTypes  = $ownerTypes
            OwnerObjectIds    = $ownerIds
        })
    }
}

# ─────────────────────────────────────────────
# Exportar CSV
# ─────────────────────────────────────────────
$rows | Export-Csv -Path $csvOut -NoTypeInformation -Encoding UTF8
Write-Host ("`nCSV exportado → {0}" -f $csvOut) -ForegroundColor Green

# ─────────────────────────────────────────────
# Resumo
# ─────────────────────────────────────────────
$semOwner  = ($rows | Where-Object { $_.SemOwnerDireto }).Count
$comOwner  = ($rows | Where-Object { -not $_.SemOwnerDireto }).Count

Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor White
Write-Host " RESUMO" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor White
Write-Host (" Subscriptions analisadas : {0}" -f $subscriptions.Count)
Write-Host (" Resource Groups total    : {0}" -f $rows.Count)
Write-Host (" RGs com Owner direto     : {0}" -f $comOwner) -ForegroundColor Green
Write-Host (" RGs SEM Owner direto     : {0}" -f $semOwner) -ForegroundColor $(if ($semOwner -gt 0) { "Red" } else { "Green" })
Write-Host ""

# Pré-visualização dos RGs sem owner
if ($semOwner -gt 0) {
    Write-Host " RGs sem owner direto:" -ForegroundColor Red
    $rows | Where-Object { $_.SemOwnerDireto } |
        Select-Object SubscriptionName, ResourceGroupName, Location |
        Format-Table -AutoSize
}
