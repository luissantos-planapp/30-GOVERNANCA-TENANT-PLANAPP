<#
.SYNOPSIS
    Fase 4 (Migracao Faseada) - atribui cada grupo SG-AZ-* ao seu role no Management
    Group correspondente, em Azure RBAC, comecando pelos ambitos menos criticos.

.DESCRIPTION
    Le o CSV de grupos criados (SG-AZ-Grupos-Criados-*.csv), que mapeia cada grupo ao seu
    Role (Owner/Contributor/Reader) e ao Management Group alvo (AmbitoAlvoMG), e cria a
    atribuicao de role (New-AzRoleAssignment) no scope do MG. As permissoes herdam para
    as subscricoes, resource groups e recursos abaixo.

    A atribuicao do role ao GRUPO e PERMANENTE. Nos grupos de Owner, o just-in-time e
    garantido pela ELEGIBILIDADE PIM da pertenca ao grupo (Fase 3): quando um membro do
    trio ativa a pertenca, herda o role Owner do grupo no MG.

    Ordem faseada (recomendada): Sandbox -> Nao-Producao -> Plataforma -> Producao.

    Caracteristicas:
      - Idempotente: se a atribuicao ja existir no scope, deteta e ignora.
      - Apenas ADICIONA. Nao remove atribuicoes diretas antigas (coexistencia; Fase 6).
      - Suporta -WhatIf / -Confirm.
      - Filtro por dominio (-Domains) para correr onda a onda.
      - Exporta relatorio do resultado.

.PARAMETER GroupsCsv
    CSV de grupos criados na Fase 3 (por omissao 'SG-AZ-Grupos-Criados-*.csv' mais recente).

.PARAMETER Domains
    Dominios a processar nesta execucao. Valores: Sandbox, Nprd, Platform, Prd, All.
    Por omissao 'All'. Para a 1a onda, use: -Domains Sandbox,Nprd.

.PARAMETER ReportPath
    CSV de resultado (por omissao 'SG-AZ-RoleAssign-Resultado-<timestamp>.csv').

.EXAMPLE
    # Simulacao da 1a onda (menos criticos)
    .\Set-RBACRoleAssignments.ps1 -Domains Sandbox,Nprd -WhatIf

.EXAMPLE
    # Aplicar a 1a onda
    .\Set-RBACRoleAssignments.ps1 -Domains Sandbox,Nprd

.EXAMPLE
    # 2a onda, apos validacao
    .\Set-RBACRoleAssignments.ps1 -Domains Platform,Prd

.NOTES
    Requisitos:
      - Modulos: Az.Accounts, Az.Resources (Install-Module Az -Scope CurrentUser).
      - Permissoes: User Access Administrator ou Owner no scope de cada Management Group.
      - Apenas cria atribuicoes Azure RBAC; nao altera grupos nem PIM.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string] $GroupsCsv,
    [ValidateSet('Sandbox', 'Nprd', 'Platform', 'Prd', 'Transversal', 'All')]
    [string[]] $Domains = @('All'),
    [string] $ReportPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (Get-Module -Name 'Microsoft.Graph*') {
    Write-Warning "Modulos Microsoft.Graph estao carregados nesta sessao. Isto pode causar conflito de assemblies (Azure.Identity) com o Az e o erro 'Method not found'."
    Write-Warning "Recomendado: feche esta sessao e corra este script numa sessao NOVA do PowerShell, sem o Microsoft.Graph importado."
}

foreach ($m in 'Az.Accounts', 'Az.Resources') {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        throw "Modulo '$m' nao instalado. Instale com: Install-Module Az -Scope CurrentUser"
    }
    Import-Module $m -ErrorAction Stop
}

if (-not $GroupsCsv) {
    $GroupsCsv = Get-ChildItem -Filter 'SG-AZ-Grupos-Criados-*.csv' |
                 Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $GroupsCsv -or -not (Test-Path $GroupsCsv)) {
    throw "CSV de grupos nao encontrado. Indique -GroupsCsv com o ficheiro da Fase 3."
}
if (-not $ReportPath) {
    $ReportPath = Join-Path (Get-Location) ("SG-AZ-RoleAssign-Resultado-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

$ctx = $null
try { $ctx = Get-AzContext } catch { $ctx = $null }
if (-not $ctx) {
    Write-Host "Sem sessao Azure ativa. A iniciar Connect-AzAccount..." -ForegroundColor Yellow
    Connect-AzAccount | Out-Null
    $ctx = Get-AzContext
}
Write-Host ("Azure ligado - tenant: {0}  conta: {1}" -f $ctx.Tenant.Id, $ctx.Account.Id) -ForegroundColor Cyan

# Mapa MG -> dominio e ordem de onda
$mgMap = @{
    'mg-planapp'          = @{ Domain = 'Transversal'; Order = 0 }
    'mg-planapp-sandbox'  = @{ Domain = 'Sandbox';  Order = 1 }
    'mg-planapp-lz-nprd'  = @{ Domain = 'Nprd';     Order = 2 }
    'mg-planapp-platform' = @{ Domain = 'Platform'; Order = 3 }
    'mg-planapp-lz-prod'  = @{ Domain = 'Prd';      Order = 4 }
}
$roleRank = @{ 'Owner' = 1; 'Contributor' = 2; 'Reader' = 3; 'Cost Management Reader' = 4 }
$allowedRoles = @('Owner', 'Contributor', 'Reader', 'Cost Management Reader')

$wantAll = $Domains -contains 'All'
$wantDomains = if ($wantAll) { @('Transversal', 'Sandbox', 'Nprd', 'Platform', 'Prd') } else { $Domains }

$groups = Import-Csv $GroupsCsv | Where-Object {
    $_.Role -in $allowedRoles -and $mgMap.ContainsKey($_.AmbitoAlvoMG)
}

$plan = foreach ($g in $groups) {
    $info = $mgMap[$g.AmbitoAlvoMG]
    if ($info.Domain -notin $wantDomains) { continue }
    [pscustomobject]@{
        Grupo = $g.Grupo; ObjectId = $g.ObjectId; Role = $g.Role; Mg = $g.AmbitoAlvoMG
        Domain = $info.Domain; Order = $info.Order; RoleRank = $roleRank[$g.Role]
    }
}
$plan = $plan | Sort-Object Order, RoleRank, Grupo

Write-Host ("Atribuicoes a processar: {0} (dominios: {1})" -f @($plan).Count, ($wantDomains -join ', ')) -ForegroundColor Cyan

$report = New-Object System.Collections.Generic.List[object]

foreach ($p in $plan) {
    $scope = "/providers/Microsoft.Management/managementGroups/$($p.Mg)"
    $alvo = ("{0} = {1} @ {2}" -f $p.Grupo, $p.Role, $p.Mg)

    if (-not $p.ObjectId) {
        Write-Warning ("Ignorado (ObjectId em falta): {0}" -f $p.Grupo)
        $report.Add([pscustomobject]@{ Grupo = $p.Grupo; Role = $p.Role; Mg = $p.Mg; Estado = 'ObjectId em falta' })
        continue
    }

    # Idempotencia: existe ja a atribuicao exatamente neste scope?
    $existing = $null
    try {
        $existing = Get-AzRoleAssignment -ObjectId $p.ObjectId -RoleDefinitionName $p.Role -Scope $scope -ErrorAction SilentlyContinue |
                    Where-Object { $_.Scope -eq $scope }
    } catch { }
    if ($existing) {
        Write-Host ("  = ja existente: {0}" -f $alvo) -ForegroundColor DarkGray
        $report.Add([pscustomobject]@{ Grupo = $p.Grupo; Role = $p.Role; Mg = $p.Mg; Estado = 'Ja existente' })
        continue
    }

    if ($PSCmdlet.ShouldProcess($alvo, "Criar atribuicao de role")) {
        try {
            New-AzRoleAssignment -ObjectId $p.ObjectId -RoleDefinitionName $p.Role -Scope $scope -ErrorAction Stop | Out-Null
            Write-Host ("  + atribuido: {0}" -f $alvo) -ForegroundColor Green
            $report.Add([pscustomobject]@{ Grupo = $p.Grupo; Role = $p.Role; Mg = $p.Mg; Estado = 'Atribuido' })
        } catch {
            $emsg = $_.Exception.Message
            if ($emsg -match 'already exist|RoleAssignmentExists|conflict') {
                Write-Host ("  = ja existente: {0}" -f $alvo) -ForegroundColor DarkGray
                $report.Add([pscustomobject]@{ Grupo = $p.Grupo; Role = $p.Role; Mg = $p.Mg; Estado = 'Ja existente' })
            } else {
                Write-Warning ("  Falha em {0}: {1}" -f $alvo, $emsg)
                $report.Add([pscustomobject]@{ Grupo = $p.Grupo; Role = $p.Role; Mg = $p.Mg; Estado = ("Erro: {0}" -f $emsg) })
            }
        }
    } else {
        $report.Add([pscustomobject]@{ Grupo = $p.Grupo; Role = $p.Role; Mg = $p.Mg; Estado = 'Simulado' })
    }
}

$report | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8
Write-Host "`nResumo:" -ForegroundColor Cyan
$report | Group-Object Estado | ForEach-Object { Write-Host ("  {0,-16} {1}" -f $_.Name, $_.Count) }
Write-Host ("`nRelatorio exportado para: {0}" -f $ReportPath) -ForegroundColor Green
Write-Host "Lembrete: mantenha as atribuicoes diretas antigas ate validar (coexistencia). Remocao = Fase 6." -ForegroundColor Yellow
