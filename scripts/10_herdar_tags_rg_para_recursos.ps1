#Requires -Modules Az.Accounts, Az.Resources
<#
.SYNOPSIS
    Propaga as tags do Resource Group para todos os seus recursos.
.DESCRIPTION
    Le as tags do Resource Group indicado e aplica-as em cada recurso
    dentro desse RG, fazendo merge (nao sobrescreve tags proprias do
    recurso que nao existam no RG).

.PARAMETER ResourceGroupName
    Nome do Resource Group (obrigatorio).
.PARAMETER SubscriptionId
    ID da subscricao. Se omitido usa o contexto Azure atual.
.PARAMETER WhatIf
    Simula sem efetuar alteracoes no Azure.
.PARAMETER OverwriteExisting
    Se definido, sobrescreve valores de tags ja existentes no recurso
    com o valor do RG. Por defeito so adiciona tags em falta.

.EXAMPLE
    .\10_herdar_tags_rg_para_recursos.ps1 -ResourceGroupName "pla-we-hub-netsec-rg001"
    .\10_herdar_tags_rg_para_recursos.ps1 -ResourceGroupName "pla-we-hub-netsec-rg001" -WhatIf
    .\10_herdar_tags_rg_para_recursos.ps1 -ResourceGroupName "pla-we-hub-netsec-rg001" -OverwriteExisting
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [string]$SubscriptionId,

    [switch]$WhatIf,

    [switch]$OverwriteExisting
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─────────────────────────────────────────────────────────────────
# 1. Autenticacao e contexto
# ─────────────────────────────────────────────────────────────────
Write-Host "`n[1/4] A verificar autenticacao Azure..." -ForegroundColor Cyan
$ctx = Get-AzContext
if (-not $ctx) {
    Write-Host "     Sem sessao ativa. A iniciar login interativo..." -ForegroundColor Yellow
    Connect-AzAccount | Out-Null
    $ctx = Get-AzContext
}

if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
    $ctx = Get-AzContext
}

Write-Host ("     Conta        : {0}" -f $ctx.Account.Id) -ForegroundColor Green
Write-Host ("     Subscricao   : {0} ({1})" -f $ctx.Subscription.Name, $ctx.Subscription.Id) -ForegroundColor Green
if ($WhatIf)            { Write-Host "     MODO WHATIF  : nenhuma alteracao sera efetuada" -ForegroundColor Yellow }
if ($OverwriteExisting) { Write-Host "     OVERWRITE    : tags existentes no recurso serao sobrescritas" -ForegroundColor Yellow }

# ─────────────────────────────────────────────────────────────────
# 2. Ler tags do Resource Group
# ─────────────────────────────────────────────────────────────────
Write-Host "`n[2/4] A ler tags do Resource Group '$ResourceGroupName'..." -ForegroundColor Cyan

$rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop

if (-not $rg.Tags -or $rg.Tags.Count -eq 0) {
    Write-Host "     O Resource Group nao tem tags definidas. Nada a propagar." -ForegroundColor Yellow
    exit 0
}

Write-Host ("     Tags encontradas ({0}):" -f $rg.Tags.Count) -ForegroundColor Green
foreach ($k in $rg.Tags.Keys) {
    Write-Host ("       {0} = {1}" -f $k, $rg.Tags[$k]) -ForegroundColor DarkGray
}

# ─────────────────────────────────────────────────────────────────
# 3. Propagar para cada recurso
# ─────────────────────────────────────────────────────────────────
Write-Host "`n[3/4] A obter recursos do Resource Group..." -ForegroundColor Cyan
$resources = @(Get-AzResource -ResourceGroupName $ResourceGroupName -ErrorAction Stop)

Write-Host ("     Recursos encontrados: {0}" -f $resources.Count) -ForegroundColor Green
Write-Host ""

$nApplied  = 0
$nSkipped  = 0
$nFailed   = 0
$results   = [System.Collections.Generic.List[PSObject]]::new()

$counter = 0
foreach ($res in $resources) {
    $counter++

    # Construir tags merged
    $mergedTags = @{}

    # Comecar pelas tags atuais do recurso
    if ($res.Tags) {
        foreach ($k in $res.Tags.Keys) {
            $mergedTags[$k] = [string]$res.Tags[$k]
        }
    }

    # Aplicar tags do RG
    $addedKeys    = [System.Collections.Generic.List[string]]::new()
    $skippedKeys  = [System.Collections.Generic.List[string]]::new()

    foreach ($k in $rg.Tags.Keys) {
        $rgVal = [string]$rg.Tags[$k]
        if ($mergedTags.ContainsKey($k)) {
            if ($OverwriteExisting -and $mergedTags[$k] -ne $rgVal) {
                $mergedTags[$k] = $rgVal
                $addedKeys.Add("${k}=${rgVal}")
            } else {
                $skippedKeys.Add($k)
            }
        } else {
            $mergedTags[$k] = $rgVal
            $addedKeys.Add("${k}=${rgVal}")
        }
    }

    if ($addedKeys.Count -eq 0) {
        $nSkipped++
        $results.Add([PSCustomObject]@{
            Recurso         = $res.Name
            Tipo            = $res.ResourceType
            TagsAdicionadas = ""
            TagsIgnoradas   = ($skippedKeys -join ", ")
            Status          = "SemAlteracao"
            Detalhe         = ""
        })
        Write-Host ("  [{0}/{1}] [--] {2}" -f $counter, $resources.Count, $res.Name) -ForegroundColor DarkGray
        continue
    }

    if (-not $WhatIf) {
        try {
            Set-AzResource -ResourceId $res.ResourceId -Tag $mergedTags -Force -ErrorAction Stop | Out-Null
            $nApplied++
            $status  = "Aplicado"
            $detalhe = ""
        }
        catch {
            $nFailed++
            $status  = "Falhou"
            $detalhe = $_.Exception.Message
            Write-Warning ("  [{0}/{1}] Falha em {2}: {3}" -f $counter, $resources.Count, $res.Name, $_.Exception.Message)
        }
    }
    else {
        $nApplied++
        $status  = "WhatIf"
        $detalhe = "Simulacao"
    }

    $results.Add([PSCustomObject]@{
        Recurso         = $res.Name
        Tipo            = $res.ResourceType
        TagsAdicionadas = ($addedKeys -join " | ")
        TagsIgnoradas   = ($skippedKeys -join ", ")
        Status          = $status
        Detalhe         = $detalhe
    })

    $color = switch ($status) { "Aplicado" { "Green" } "WhatIf" { "Yellow" } "Falhou" { "Red" } default { "DarkGray" } }
    Write-Host ("  [{0}/{1}] [{2}] {3}  -> {4}" -f $counter, $resources.Count, $status, $res.Name, ($addedKeys -join ", ")) -ForegroundColor $color
}

# ─────────────────────────────────────────────────────────────────
# 4. Resumo
# ─────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "─────────────────────────────────────────────" -ForegroundColor White
Write-Host " RESUMO — $ResourceGroupName" -ForegroundColor White
Write-Host "─────────────────────────────────────────────" -ForegroundColor White
Write-Host (" Total de recursos      : {0}" -f $resources.Count)
Write-Host (" Tags aplicadas         : {0}" -f $nApplied) -ForegroundColor Green
Write-Host (" Sem alteracao          : {0}" -f $nSkipped) -ForegroundColor DarkGray
Write-Host (" Falhados               : {0}" -f $nFailed) -ForegroundColor $(if ($nFailed -gt 0) { "Red" } else { "Green" })
Write-Host "─────────────────────────────────────────────" -ForegroundColor White
if ($WhatIf) { Write-Host " MODO WHATIF - nenhuma alteracao foi efetuada" -ForegroundColor Yellow }

$results | Format-Table Recurso, Status, TagsAdicionadas, TagsIgnoradas -AutoSize
