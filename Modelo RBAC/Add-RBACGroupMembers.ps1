<#
.SYNOPSIS
    Fase 3 (Povoamento) - adiciona membros PERMANENTES aos grupos SG-AZ-* no Entra ID,
    a partir do mapa de membros derivado da Matriz de Remediacao (Fase 2).

.DESCRIPTION
    Le o CSV 'SG-AZ-Membros-Mapeamento.csv' e adiciona cada utilizador marcado com
    Incluir = 'Sim' e Metodo = 'Permanente' ao respetivo grupo SG-AZ-*.

    As linhas Metodo = 'PIM-Eligible' (grupos de Owner) sao IGNORADAS aqui e tratadas
    pelo Enable-RBACGroupPIM.ps1 (um utilizador nao pode ser membro permanente e
    elegivel do mesmo grupo em simultaneo).

    Caracteristicas:
      - Idempotente: se o utilizador ja for membro, nao falha (deteta e ignora).
      - Usa os ObjectId do CSV (GroupObjectId / PrincipalObjectId); se faltar, resolve por Login.
      - Suporta -WhatIf / -Confirm.
      - Exporta um relatorio do resultado por linha.

    NOTA DE TRANSICAO SEGURA: este passo apenas COLOCA pessoas em grupos; nao concede
    permissoes. As atribuicoes antigas (diretas) devem manter-se ate a validacao da Fase 4.

.PARAMETER MappingCsv
    CSV de mapeamento (por omissao 'SG-AZ-Membros-Mapeamento.csv' na pasta atual).

.PARAMETER IncludeDeferred
    Se presente, processa TAMBEM as linhas Incluir = 'Nao' (diferidas para o patamar 2).

.PARAMETER ReportPath
    CSV de resultado (por omissao 'SG-AZ-Membros-Resultado-<timestamp>.csv').

.EXAMPLE
    .\Add-RBACGroupMembers.ps1 -WhatIf

.EXAMPLE
    .\Add-RBACGroupMembers.ps1 -MappingCsv .\SG-AZ-Membros-Mapeamento.csv

.NOTES
    Requisitos:
      - Modulos: Microsoft.Graph.Authentication, Microsoft.Graph.Groups, Microsoft.Graph.Users
      - Scopes: GroupMember.ReadWrite.All (e User.Read.All se resolver por Login)
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string] $MappingCsv = (Join-Path (Get-Location) 'SG-AZ-Membros-Mapeamento.csv'),
    [switch] $IncludeDeferred,
    [string] $ReportPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

foreach ($m in 'Microsoft.Graph.Authentication', 'Microsoft.Graph.Groups', 'Microsoft.Graph.Users') {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        throw "Modulo '$m' nao instalado. Instale com: Install-Module Microsoft.Graph -Scope CurrentUser"
    }
    Import-Module $m -ErrorAction Stop
}

if (-not (Test-Path $MappingCsv)) { throw "Mapa de membros nao encontrado: $MappingCsv" }
if (-not $ReportPath) {
    $ReportPath = Join-Path (Get-Location) ("SG-AZ-Membros-Resultado-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

$needScopes = @('GroupMember.ReadWrite.All', 'User.Read.All')
$ctx = $null
try { $ctx = Get-MgContext } catch { $ctx = $null }
if (-not $ctx -or @($needScopes | Where-Object { $_ -notin $ctx.Scopes }).Count -gt 0) {
    Write-Host "A autenticar no Microsoft Graph (scopes: $($needScopes -join ', '))..." -ForegroundColor Yellow
    Connect-MgGraph -Scopes $needScopes -NoWelcome
    $ctx = Get-MgContext
}
Write-Host "Graph ligado - tenant: $($ctx.TenantId)  conta: $($ctx.Account)" -ForegroundColor Cyan

$map = Import-Csv $MappingCsv
# Linhas de Owner (Metodo = 'PIM-Eligible') sao tratadas pelo Enable-RBACGroupPIM.ps1.
# Aqui so se adicionam membros PERMANENTES (Metodo ausente ou 'Permanente').
$hasMetodo = $null -ne ($map | Get-Member -Name Metodo -MemberType NoteProperty)
$rows = $map | Where-Object {
    ($IncludeDeferred -or $_.Incluir -eq 'Sim') -and
    ((-not $hasMetodo) -or ($_.Metodo -ne 'PIM-Eligible'))
}
$skippedPim = 0
if ($hasMetodo) {
    $skippedPim = @($map | Where-Object { $_.Incluir -eq 'Sim' -and $_.Metodo -eq 'PIM-Eligible' }).Count
}
$modo = if ($IncludeDeferred) { 'INCLUI diferidas' } else { 'apenas Incluir=Sim, permanentes' }
Write-Host ("Linhas a processar: {0} (de {1} no mapa) - {2}" -f @($rows).Count, @($map).Count, $modo) -ForegroundColor Cyan
if ($skippedPim -gt 0) {
    Write-Host ("Ignoradas {0} linhas PIM-Eligible (grupos de Owner). Use Enable-RBACGroupPIM.ps1." -f $skippedPim) -ForegroundColor Yellow
}

$report = New-Object System.Collections.Generic.List[object]

foreach ($row in $rows) {
    $grupo    = $row.'Grupo-Alvo'
    $groupId  = $row.GroupObjectId
    $memberId = $row.PrincipalObjectId
    $nome     = $row.PrincipalNome

    if (-not $groupId) {
        try { $groupId = @(Get-MgGroup -Filter "displayName eq '$grupo'" -All -ErrorAction Stop)[0].Id }
        catch { Write-Warning ("  Falha a resolver grupo '{0}': {1}" -f $grupo, $_.Exception.Message) }
    }
    if (-not $memberId -and $row.Login) {
        try { $memberId = (Get-MgUser -UserId $row.Login -ErrorAction Stop).Id } catch { }
    }

    if (-not $groupId -or -not $memberId) {
        Write-Warning ("Ignorado (ID em falta): {0} -> {1}" -f $nome, $grupo)
        $report.Add([pscustomobject]@{ Grupo = $grupo; Membro = $nome; Login = $row.Login; Estado = 'ID em falta' })
        continue
    }

    if ($PSCmdlet.ShouldProcess(("{0} <- {1}" -f $grupo, $nome), "Adicionar membro")) {
        try {
            $ref = "https://graph.microsoft.com/v1.0/directoryObjects/$memberId"
            New-MgGroupMemberByRef -GroupId $groupId -BodyParameter @{ '@odata.id' = $ref } -ErrorAction Stop
            Write-Host ("  + {0} <- {1}" -f $grupo, $nome) -ForegroundColor Green
            $report.Add([pscustomobject]@{ Grupo = $grupo; Membro = $nome; Login = $row.Login; Estado = 'Adicionado' })
        } catch {
            $emsg = $_.Exception.Message
            if ($emsg -match 'already exist|references already exist|One or more added object') {
                Write-Host ("  = {0} ja contem {1}" -f $grupo, $nome) -ForegroundColor DarkGray
                $report.Add([pscustomobject]@{ Grupo = $grupo; Membro = $nome; Login = $row.Login; Estado = 'Ja era membro' })
            } else {
                Write-Warning ("  Falha a adicionar {0} a {1}: {2}" -f $nome, $grupo, $emsg)
                $report.Add([pscustomobject]@{ Grupo = $grupo; Membro = $nome; Login = $row.Login; Estado = ("Erro: {0}" -f $emsg) })
            }
        }
    } else {
        $report.Add([pscustomobject]@{ Grupo = $grupo; Membro = $nome; Login = $row.Login; Estado = 'Simulado' })
    }
}

$report | Sort-Object Grupo, Membro | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8
Write-Host "`nResumo:" -ForegroundColor Cyan
$report | Group-Object Estado | ForEach-Object { Write-Host ("  {0,-14} {1}" -f $_.Name, $_.Count) }
Write-Host ("`nRelatorio exportado para: {0}" -f $ReportPath) -ForegroundColor Green
