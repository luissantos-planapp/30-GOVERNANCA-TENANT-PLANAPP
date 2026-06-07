#Requires -Modules Az.Accounts, Az.Resources
<#
.SYNOPSIS
    Aplica tags nos Resource Groups a partir de ficheiro Excel preenchido manualmente.
.DESCRIPTION
    Le o ficheiro Excel com as tags preenchidas e atualiza os Resource Groups no Azure.
    As colunas de tag reconhecidas sao: departamento, ambiente, projeto, centrocusto, owner.

    Estrutura esperada no Excel (colunas obrigatorias):
      - SubscriptionId  (ou SubscriptionName)
      - ResourceGroup

    Colunas de tag (qualquer subconjunto):
      - departamento
      - ambiente
      - projeto
      - centrocusto
      - owner

    Celulas vazias sao ignoradas (nao sobrescrevem tags existentes com valor vazio).
    Celulas com "PREENCHER" sao ignoradas.

.PARAMETER ExcelFile
    Caminho para o ficheiro .xlsx preenchido.
.PARAMETER OutputPath
    Pasta de destino para o CSV de resultado (default: EstruturaTenantV2\csv).
.PARAMETER WhatIf
    Simula sem efetuar alteracoes no Azure.
.EXAMPLE
    .\09_aplicar_tags_from_excel.ps1 -ExcelFile "..\EstruturaTenantV2\csv\08_tag_changes_20260606_1926.xlsx"
    .\09_aplicar_tags_from_excel.ps1 -ExcelFile ".\tags.xlsx" -WhatIf
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ExcelFile,

    [string]$OutputPath = (Join-Path $PSScriptRoot "..\EstruturaTenantV2\csv"),

    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─────────────────────────────────────────────────────────────────
# 1. Garantir modulo ImportExcel
# ─────────────────────────────────────────────────────────────────
Write-Host "`n[1/5] A verificar modulo ImportExcel..." -ForegroundColor Cyan
if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    Write-Host "     Modulo nao encontrado. A instalar..." -ForegroundColor Yellow
    try {
        Install-Module -Name ImportExcel -Scope CurrentUser -Force -AllowClobber
        Write-Host "     ImportExcel instalado com sucesso." -ForegroundColor Green
    }
    catch {
        Write-Error "Nao foi possivel instalar o modulo ImportExcel: $_"
        exit 1
    }
}
Import-Module ImportExcel -ErrorAction Stop
Write-Host "     ImportExcel disponivel." -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────
# 2. Ler Excel
# ─────────────────────────────────────────────────────────────────
Write-Host "`n[2/5] A ler ficheiro Excel..." -ForegroundColor Cyan
$excelPath = Resolve-Path $ExcelFile -ErrorAction Stop
Write-Host ("     Ficheiro: {0}" -f $excelPath) -ForegroundColor DarkGray

$rows = Import-Excel -Path $excelPath -ErrorAction Stop
Write-Host ("     Linhas lidas: {0}" -f $rows.Count) -ForegroundColor Green

# Detetar colunas disponiveis
$allColumns = $rows | Select-Object -First 1 | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
Write-Host ("     Colunas encontradas: {0}" -f ($allColumns -join ", ")) -ForegroundColor DarkGray

# Validar coluna de identificacao do RG
$hasSubId   = $allColumns -contains "SubscriptionId"
$hasSubName = $allColumns -contains "SubscriptionName"
$hasRG      = $allColumns -contains "ResourceGroup"

if (-not $hasRG) {
    Write-Error "Coluna 'ResourceGroup' nao encontrada no Excel."
    exit 1
}
if (-not $hasSubId -and -not $hasSubName) {
    Write-Error "E necessaria a coluna 'SubscriptionId' ou 'SubscriptionName' no Excel."
    exit 1
}

# Colunas de tag reconhecidas
$tagColumns = @("departamento", "ambiente", "projeto", "centrocusto", "owner") |
              Where-Object { $allColumns -contains $_ }

if ($tagColumns.Count -eq 0) {
    Write-Error "Nenhuma coluna de tag encontrada. Esperado: departamento, ambiente, projeto, centrocusto, owner"
    exit 1
}
Write-Host ("     Colunas de tag a processar: {0}" -f ($tagColumns -join ", ")) -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────
# 3. Autenticacao Azure
# ─────────────────────────────────────────────────────────────────
Write-Host "`n[3/5] A verificar autenticacao Azure..." -ForegroundColor Cyan
$ctx = Get-AzContext
if (-not $ctx) {
    Write-Host "     Sem sessao ativa. A iniciar login interativo..." -ForegroundColor Yellow
    Connect-AzAccount | Out-Null
    $ctx = Get-AzContext
}
Write-Host ("     Conta  : {0}" -f $ctx.Account.Id) -ForegroundColor Green
Write-Host ("     Tenant : {0}" -f $ctx.Tenant.Id)  -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────
# 4. Processar cada linha
# ─────────────────────────────────────────────────────────────────
Write-Host "`n[4/5] A aplicar tags nos Resource Groups..." -ForegroundColor Cyan
if ($WhatIf) { Write-Host "     MODO WHATIF - nenhuma alteracao sera efetuada no Azure" -ForegroundColor Yellow }

$results = [System.Collections.Generic.List[PSObject]]::new()
$currentSubId = $null

$total   = $rows.Count
$counter = 0
$nApplied  = 0
$nSkipped  = 0
$nFailed   = 0
$nNoChange = 0

foreach ($row in $rows) {
    $counter++
    $rgName  = [string]$row.ResourceGroup
    $subId   = if ($hasSubId)   { [string]$row.SubscriptionId }   else { $null }
    $subName = if ($hasSubName) { [string]$row.SubscriptionName } else { $null }

    if ([string]::IsNullOrWhiteSpace($rgName)) { continue }

    # Construir dicionario de tags a aplicar (ignorar vazios e "PREENCHER")
    $newTagValues = @{}
    foreach ($col in $tagColumns) {
        $val = [string]$row.$col
        if (-not [string]::IsNullOrWhiteSpace($val) -and $val -ne "PREENCHER") {
            $newTagValues[$col] = $val
        }
    }

    if ($newTagValues.Count -eq 0) {
        $nNoChange++
        $results.Add([PSCustomObject]@{
            SubscriptionName = $subName
            SubscriptionId   = $subId
            ResourceGroup    = $rgName
            TagsAtualizadas  = ""
            Status           = "Ignorado"
            Detalhe          = "Sem valores de tag preenchidos"
        })
        continue
    }

    # Mudar contexto de subscricao se necessario
    $subRef = if ($subId) { $subId } else { $subName }
    if ($subRef -ne $currentSubId) {
        try {
            Set-AzContext -SubscriptionId $subRef -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
            $currentSubId = $subRef
        }
        catch {
            $nFailed++
            $results.Add([PSCustomObject]@{
                SubscriptionName = $subName
                SubscriptionId   = $subId
                ResourceGroup    = $rgName
                TagsAtualizadas  = ""
                Status           = "Falhou"
                Detalhe          = "Nao foi possivel mudar contexto para sub '$subRef': $($_.Exception.Message)"
            })
            Write-Warning ("  [{0}/{1}] Falha de contexto para {2}: {3}" -f $counter, $total, $subRef, $_.Exception.Message)
            continue
        }
    }

    # Obter RG e tags atuais
    try {
        $rg = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
    }
    catch {
        $nFailed++
        $results.Add([PSCustomObject]@{
            SubscriptionName = $subName
            SubscriptionId   = $subId
            ResourceGroup    = $rgName
            TagsAtualizadas  = ""
            Status           = "Falhou"
            Detalhe          = "RG nao encontrado: $($_.Exception.Message)"
        })
        Write-Warning ("  [{0}/{1}] RG nao encontrado: {2}" -f $counter, $total, $rgName)
        continue
    }

    # Merge de tags: comecar pelas existentes, sobrescrever com os novos valores
    $mergedTags = @{}
    if ($rg.Tags) {
        foreach ($k in $rg.Tags.Keys) {
            $mergedTags[$k] = [string]$rg.Tags[$k]
        }
    }
    $appliedKeys = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $newTagValues.Keys) {
        $mergedTags[$k] = $newTagValues[$k]
        $appliedKeys.Add("${k}=$($newTagValues[$k])")
    }

    # Aplicar
    if (-not $WhatIf) {
        try {
            Set-AzResourceGroup -Name $rgName -Tag $mergedTags -ErrorAction Stop | Out-Null
            $nApplied++
            $status  = "Aplicado"
            $detalhe = ""
        }
        catch {
            $nFailed++
            $status  = "Falhou"
            $detalhe = $_.Exception.Message
            Write-Warning ("  [{0}/{1}] Falha ao atualizar {2}: {3}" -f $counter, $total, $rgName, $_.Exception.Message)
        }
    }
    else {
        $nApplied++
        $status  = "WhatIf"
        $detalhe = "Simulacao"
    }

    $results.Add([PSCustomObject]@{
        SubscriptionName = $subName
        SubscriptionId   = $subId
        ResourceGroup    = $rgName
        TagsAtualizadas  = ($appliedKeys -join " | ")
        Status           = $status
        Detalhe          = $detalhe
    })

    Write-Host ("  [{0}/{1}] [{2}] {3} / {4}  -> {5}" -f `
        $counter, $total, $status, $subName, $rgName, ($appliedKeys -join ", ")) `
        -ForegroundColor $(
            switch ($status) {
                "Aplicado" { "Green" }
                "WhatIf"   { "Yellow" }
                "Falhou"   { "Red" }
                default    { "DarkGray" }
            }
        )
}

# ─────────────────────────────────────────────────────────────────
# 5. Exportar resultado
# ─────────────────────────────────────────────────────────────────
Write-Host "`n[5/5] A exportar resultado..." -ForegroundColor Cyan
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

$timestamp   = Get-Date -Format "yyyyMMdd_HHmm"
$csvResult   = Join-Path $OutputPath "09_tag_apply_result_$timestamp.csv"
$results | Export-Csv -Path $csvResult -NoTypeInformation -Encoding UTF8 -Delimiter ";"

Write-Host ""
Write-Host "─────────────────────────────────────────────" -ForegroundColor White
Write-Host " RESUMO" -ForegroundColor White
Write-Host "─────────────────────────────────────────────" -ForegroundColor White
Write-Host (" Total de linhas processadas : {0}" -f $total)
Write-Host (" Aplicado com sucesso        : {0}" -f $nApplied) -ForegroundColor Green
Write-Host (" Sem valores preenchidos     : {0}" -f $nNoChange) -ForegroundColor DarkGray
Write-Host (" Falhados                    : {0}" -f $nFailed)  -ForegroundColor $(if ($nFailed -gt 0) { "Red" } else { "Green" })
Write-Host ("─────────────────────────────────────────────") -ForegroundColor White
Write-Host (" CSV de resultado: {0}" -f $csvResult) -ForegroundColor Green
if ($WhatIf) { Write-Host " MODO WHATIF - nenhuma alteracao foi efetuada" -ForegroundColor Yellow }
