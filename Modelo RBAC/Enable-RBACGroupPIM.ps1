<#
.SYNOPSIS
    Fase 4 (preparacao) - torna os membros dos grupos SG-AZ-*-Owner ELEGIVEIS via
    Microsoft Entra PIM para Grupos (just-in-time), em vez de membros permanentes.

.DESCRIPTION
    Le o mapa de membros (SG-AZ-Membros-Mapeamento.csv) e, para cada linha
    Incluir = 'Sim' e Metodo = 'PIM-Eligible' (os grupos de Owner), cria uma atribuicao
    de ELEGIBILIDADE de membro do grupo no PIM para Grupos.

    Efeito: ninguem e Owner permanente. Cada membro do trio fica elegivel a ativar a
    pertenca ao grupo (e, por heranca, o role Owner atribuido ao grupo no Management
    Group na Fase 4), por tempo limitado e com MFA/aprovacao.

    Caracteristicas:
      - Idempotente: se ja existir elegibilidade para o par (grupo, pessoa), deteta e ignora.
      - Suporta -WhatIf / -Confirm.
      - Elegibilidade sem expiracao por omissao (standing eligibility); ativacao e JIT.

    NOTA: um utilizador NAO pode ser, em simultaneo, membro permanente e elegivel do mesmo
    grupo. Por isso os grupos de Owner sao povoados APENAS por este script - o
    Add-RBACGroupMembers.ps1 ignora as linhas Metodo = 'PIM-Eligible'.

.PARAMETER MappingCsv
    Mapa de membros (por omissao 'SG-AZ-Membros-Mapeamento.csv' na pasta atual).

.PARAMETER AccessId
    Tipo de elegibilidade no grupo: 'member' (por omissao) ou 'owner'.

.PARAMETER DurationDays
    Duracao (dias) da elegibilidade quando -Expiration nao e indicado. Por omissao 365.
    Se a politica PIM do tenant tiver um maximo inferior, reduza este valor.

.PARAMETER Expiration
    Controla a expiracao da elegibilidade:
      - '' (por omissao)        -> duracao limitada de -DurationDays dias (afterDuration).
      - 'noExpiration'          -> permanente (so funciona se a politica PIM o permitir).
      - data ISO 8601           -> data de fim fixa (ex.: '2027-06-30T23:59:59Z').
    Nota: a politica do tenant PLANAPP NAO permite elegibilidade permanente.

.PARAMETER Justification
    Texto de justificacao registado no pedido PIM.

.PARAMETER ReportPath
    CSV de resultado (por omissao 'SG-AZ-PIM-Resultado-<timestamp>.csv').

.EXAMPLE
    .\Enable-RBACGroupPIM.ps1 -WhatIf

.EXAMPLE
    .\Enable-RBACGroupPIM.ps1 -MappingCsv .\SG-AZ-Membros-Mapeamento.csv

.NOTES
    Requisitos:
      - Licenca Microsoft Entra ID P2 (PIM).
      - Modulos: Microsoft.Graph.Authentication, Microsoft.Graph.Identity.Governance.
      - Scope: PrivilegedAccess.ReadWrite.AzureADGroup (papel: Privileged Role Administrator).
      - Os grupos de Owner sao role-assignable (Fase 3), pre-requisito do PIM para Grupos.
      - Defina as politicas de ativacao (duracao max., MFA, aprovacao) no portal PIM.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string] $MappingCsv = (Join-Path (Get-Location) 'SG-AZ-Membros-Mapeamento.csv'),
    [ValidateSet('member', 'owner')] [string] $AccessId = 'member',
    [int]    $DurationDays = 365,
    [string] $Expiration = '',
    [string] $Justification = 'Onboarding RBAC PLANAPP - elegibilidade PIM (just-in-time) para grupos de Owner.',
    [string] $ReportPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

foreach ($m in 'Microsoft.Graph.Authentication', 'Microsoft.Graph.Identity.Governance') {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        throw "Modulo '$m' nao instalado. Instale com: Install-Module Microsoft.Graph -Scope CurrentUser"
    }
    Import-Module $m -ErrorAction Stop
}

if (-not (Test-Path $MappingCsv)) { throw "Mapa de membros nao encontrado: $MappingCsv" }
if (-not $ReportPath) {
    $ReportPath = Join-Path (Get-Location) ("SG-AZ-PIM-Resultado-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

$scope = 'PrivilegedAccess.ReadWrite.AzureADGroup'
$ctx = $null
try { $ctx = Get-MgContext } catch { $ctx = $null }
if (-not $ctx -or $scope -notin $ctx.Scopes) {
    Write-Host "A autenticar no Microsoft Graph (scope: $scope)..." -ForegroundColor Yellow
    Connect-MgGraph -Scopes $scope -NoWelcome
    $ctx = Get-MgContext
}
Write-Host "Graph ligado - tenant: $($ctx.TenantId)  conta: $($ctx.Account)" -ForegroundColor Cyan

# A politica PIM do tenant pode nao permitir elegibilidade permanente.
#   -Expiration ''            -> duracao limitada (afterDuration), usando -DurationDays
#   -Expiration 'noExpiration'-> permanente (so se a politica permitir)
#   -Expiration '2027-06-30..'-> data de fim especifica (afterDateTime)
if ($Expiration -eq 'noExpiration') {
    $expBlock = @{ type = 'noExpiration' }
    $expDesc = 'permanente'
} elseif ([string]::IsNullOrWhiteSpace($Expiration)) {
    $expBlock = @{ type = 'afterDuration'; duration = ("P{0}D" -f $DurationDays) }
    $expDesc = ("{0} dias" -f $DurationDays)
} else {
    $expBlock = @{ type = 'afterDateTime'; endDateTime = ([datetime]$Expiration).ToUniversalTime().ToString('o') }
    $expDesc = ("ate {0}" -f $Expiration)
}
Write-Host ("Expiracao da elegibilidade: {0}" -f $expDesc) -ForegroundColor DarkCyan

$map = Import-Csv $MappingCsv
$rows = $map | Where-Object { $_.Incluir -eq 'Sim' -and $_.Metodo -eq 'PIM-Eligible' }
Write-Host ("Elegibilidades a criar: {0} (acesso {1})" -f @($rows).Count, $AccessId) -ForegroundColor Cyan

$report = New-Object System.Collections.Generic.List[object]

foreach ($row in $rows) {
    $grupo    = $row.'Grupo-Alvo'
    $groupId  = $row.GroupObjectId
    $memberId = $row.PrincipalObjectId
    $nome     = $row.PrincipalNome

    if (-not $groupId -or -not $memberId) {
        Write-Warning ("Ignorado (ID em falta): {0} -> {1}" -f $nome, $grupo)
        $report.Add([pscustomobject]@{ Grupo = $grupo; Membro = $nome; Estado = 'ID em falta' })
        continue
    }

    $params = @{
        accessId      = $AccessId
        principalId   = $memberId
        groupId       = $groupId
        action        = 'adminAssign'
        justification = $Justification
        scheduleInfo  = @{
            startDateTime = (Get-Date).ToUniversalTime().ToString('o')
            expiration    = $expBlock
        }
    }

    if ($PSCmdlet.ShouldProcess(("{0} <- {1}" -f $grupo, $nome), ("Criar elegibilidade PIM ({0})" -f $AccessId))) {
        try {
            New-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleRequest -BodyParameter $params -ErrorAction Stop | Out-Null
            Write-Host ("  + elegivel: {0} <- {1}" -f $grupo, $nome) -ForegroundColor Green
            $report.Add([pscustomobject]@{ Grupo = $grupo; Membro = $nome; Estado = 'Elegibilidade criada' })
        } catch {
            $emsg = $_.Exception.Message
            if ($emsg -match 'already|existing|RoleAssignmentExists|conflict') {
                Write-Host ("  = ja elegivel: {0} <- {1}" -f $grupo, $nome) -ForegroundColor DarkGray
                $report.Add([pscustomobject]@{ Grupo = $grupo; Membro = $nome; Estado = 'Ja elegivel' })
            } else {
                Write-Warning ("  Falha em {0} <- {1}: {2}" -f $grupo, $nome, $emsg)
                $report.Add([pscustomobject]@{ Grupo = $grupo; Membro = $nome; Estado = ("Erro: {0}" -f $emsg) })
            }
        }
    } else {
        $report.Add([pscustomobject]@{ Grupo = $grupo; Membro = $nome; Estado = 'Simulado' })
    }
}

$report | Sort-Object Grupo, Membro | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8
Write-Host "`nResumo:" -ForegroundColor Cyan
$report | Group-Object Estado | ForEach-Object { Write-Host ("  {0,-22} {1}" -f $_.Name, $_.Count) }
Write-Host ("`nRelatorio exportado para: {0}" -f $ReportPath) -ForegroundColor Green
Write-Host "Lembrete: defina as politicas de ativacao PIM (duracao, MFA, aprovacao) para estes grupos." -ForegroundColor Yellow
