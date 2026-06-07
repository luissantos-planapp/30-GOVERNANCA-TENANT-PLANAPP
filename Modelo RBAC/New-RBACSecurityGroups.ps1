<#
.SYNOPSIS
    Fase 3 (Configuracao dos Grupos de Seguranca) - cria no Microsoft Entra ID os grupos
    de seguranca SG-AZ-* do modelo RBAC alvo do PLANAPP.

.DESCRIPTION
    Cria os grupos de seguranca normalizados (Politica de Nomenclaturas v2.0, Seccao 7),
    com o prefixo SG- e a estrutura SG-AZ-<Dominio>-<Role>. Os grupos de Owner sao criados
    como role-assignable (isAssignableToRole = true).

    Inclui o grupo transversal SG-AZ-Cost-Reader (Cost Management Reader) para FinOps,
    atribuido no MG de topo (mg-planapp) e herdado por todo o tenant.

    Caracteristicas:
      - Idempotente: se o grupo (displayName) ja existir, e ignorado (nao duplica).
      - Apenas cria grupos. As atribuicoes de role em Azure (MG) sao a Fase 4.
      - Suporta -WhatIf / -Confirm.
      - Exporta os objectId para CSV (entrada da Fase 4).
      - Opcional: popular membros a partir de um CSV de mapeamento.

.PARAMETER ExportPath
    CSV onde gravar o mapeamento Grupo -> ObjectId -> Ambito-Alvo (para a Fase 4).

.PARAMETER MemberMappingCsv
    (Opcional) CSV com 'Grupo-Alvo' e ('PrincipalObjectId' ou 'Login') para semear membros.

.PARAMETER GroupOwners
    (Opcional) UPNs a definir como donos (owners) dos grupos.

.PARAMETER IncludeWorkloadsGroup
    Inclui o grupo logico SG-AZ-Workloads-SP. Por omissao $true.

.EXAMPLE
    .\New-RBACSecurityGroups.ps1 -WhatIf

.EXAMPLE
    .\New-RBACSecurityGroups.ps1 -ExportPath .\grupos-criados.csv

.NOTES
    Requisitos:
      - Modulos: Microsoft.Graph.Authentication, Microsoft.Graph.Groups, Microsoft.Graph.Users
      - Scopes: Group.ReadWrite.All e RoleManagement.ReadWrite.Directory (role-assignable)
      - Papel: Privileged Role Administrator ou Global Administrator; licenca Entra ID P1/P2.
      - isAssignableToRole e imutavel apos a criacao.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]   $ExportPath,
    [string]   $MemberMappingCsv,
    [string[]] $GroupOwners,
    [bool]     $IncludeWorkloadsGroup = $true
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

foreach ($m in 'Microsoft.Graph.Authentication', 'Microsoft.Graph.Groups', 'Microsoft.Graph.Users') {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        throw "Modulo '$m' nao instalado. Instale com: Install-Module Microsoft.Graph -Scope CurrentUser"
    }
    Import-Module $m -ErrorAction Stop
}

$needScopes = @('Group.ReadWrite.All', 'RoleManagement.ReadWrite.Directory')
$ctx = $null
try { $ctx = Get-MgContext } catch { $ctx = $null }
if (-not $ctx -or @($needScopes | Where-Object { $_ -notin $ctx.Scopes }).Count -gt 0) {
    Write-Host ("A autenticar no Microsoft Graph (scopes: {0})..." -f ($needScopes -join ', ')) -ForegroundColor Yellow
    Connect-MgGraph -Scopes $needScopes -NoWelcome
    $ctx = Get-MgContext
}
Write-Host ("Graph ligado - tenant: {0}  conta: {1}" -f $ctx.TenantId, $ctx.Account) -ForegroundColor Cyan

if (-not $ExportPath) {
    $ExportPath = Join-Path (Get-Location) ("SG-AZ-Grupos-Criados-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

# Catalogo: DisplayName | Role | RoleAssignable | Ambito-alvo (MG) | Descricao
$catalog = @(
    @{ Name = 'SG-AZ-Platform-Owner';       Role = 'Owner';       RoleAssignable = $true;  ScopeMg = 'mg-planapp-platform'; Desc = 'PLANAPP RBAC - Owner do dominio Plataforma (SITDIA).' }
    @{ Name = 'SG-AZ-Platform-Contributor'; Role = 'Contributor'; RoleAssignable = $false; ScopeMg = 'mg-planapp-platform'; Desc = 'PLANAPP RBAC - Contributor do dominio Plataforma (sem IAM).' }
    @{ Name = 'SG-AZ-Platform-Reader';      Role = 'Reader';      RoleAssignable = $false; ScopeMg = 'mg-planapp-platform'; Desc = 'PLANAPP RBAC - Reader do dominio Plataforma (auditoria).' }
    @{ Name = 'SG-AZ-Prd-Owner';            Role = 'Owner';       RoleAssignable = $true;  ScopeMg = 'mg-planapp-lz-prod';  Desc = 'PLANAPP RBAC - Owner das LZ de Producao (SITDIA).' }
    @{ Name = 'SG-AZ-Prd-Contributor';      Role = 'Contributor'; RoleAssignable = $false; ScopeMg = 'mg-planapp-lz-prod';  Desc = 'PLANAPP RBAC - Contributor das LZ de Producao.' }
    @{ Name = 'SG-AZ-Prd-Reader';           Role = 'Reader';      RoleAssignable = $false; ScopeMg = 'mg-planapp-lz-prod';  Desc = 'PLANAPP RBAC - Reader das LZ de Producao.' }
    @{ Name = 'SG-AZ-Nprd-Owner';           Role = 'Owner';       RoleAssignable = $true;  ScopeMg = 'mg-planapp-lz-nprd';  Desc = 'PLANAPP RBAC - Owner das LZ de Nao-Producao (SITDIA).' }
    @{ Name = 'SG-AZ-Nprd-Contributor';     Role = 'Contributor'; RoleAssignable = $false; ScopeMg = 'mg-planapp-lz-nprd';  Desc = 'PLANAPP RBAC - Contributor das LZ de Nao-Producao.' }
    @{ Name = 'SG-AZ-Nprd-Reader';          Role = 'Reader';      RoleAssignable = $false; ScopeMg = 'mg-planapp-lz-nprd';  Desc = 'PLANAPP RBAC - Reader das LZ de Nao-Producao.' }
    @{ Name = 'SG-AZ-Sandbox-Owner';        Role = 'Owner';       RoleAssignable = $true;  ScopeMg = 'mg-planapp-sandbox';  Desc = 'PLANAPP RBAC - Owner do dominio Sandbox (SITDIA).' }
    @{ Name = 'SG-AZ-Sandbox-Contributor';  Role = 'Contributor'; RoleAssignable = $false; ScopeMg = 'mg-planapp-sandbox';  Desc = 'PLANAPP RBAC - Contributor do dominio Sandbox.' }
    @{ Name = 'SG-AZ-Sandbox-Reader';       Role = 'Reader';      RoleAssignable = $false; ScopeMg = 'mg-planapp-sandbox';  Desc = 'PLANAPP RBAC - Reader do dominio Sandbox.' }
    @{ Name = 'SG-AZ-Cost-Reader';          Role = 'Cost Management Reader'; RoleAssignable = $false; ScopeMg = 'mg-planapp'; Desc = 'PLANAPP RBAC - Cost Management Reader transversal (FinOps). Leitura de custos em todo o tenant.' }
)
if ($IncludeWorkloadsGroup) {
    $catalog += @{ Name = 'SG-AZ-Workloads-SP'; Role = '(varios)'; RoleAssignable = $false; ScopeMg = 'Por recurso/workload'; Desc = 'PLANAPP RBAC - Segregacao logica de service principals de workloads.' }
}

function Get-MailNickname { param([string] $Name) return ($Name.ToLower() -replace '[^a-z0-9\-_]', '') }

$results = New-Object System.Collections.Generic.List[object]

foreach ($g in $catalog) {
    $name = $g.Name
    $existing = @()
    try { $existing = @(Get-MgGroup -Filter "displayName eq '$name'" -All -ErrorAction Stop) }
    catch { Write-Warning ("Falha ao verificar existencia de '{0}': {1}" -f $name, $_.Exception.Message) }
    if ($existing.Count -gt 0) {
        Write-Host ("= Ja existe: {0} ({1})" -f $name, $existing[0].Id) -ForegroundColor DarkGray
        $results.Add([pscustomobject]@{ Grupo = $name; ObjectId = $existing[0].Id; Estado = 'Existente'; RoleAssignable = $g.RoleAssignable; AmbitoAlvoMG = $g.ScopeMg; Role = $g.Role })
        continue
    }

    $body = @{
        DisplayName        = $name
        Description        = $g.Desc
        MailNickname       = Get-MailNickname $name
        MailEnabled        = $false
        SecurityEnabled    = $true
        IsAssignableToRole = [bool]$g.RoleAssignable
    }

    $tag = if ($g.RoleAssignable) { 'role-assignable' } else { 'standard' }
    if ($PSCmdlet.ShouldProcess($name, ("Criar grupo de seguranca ({0})" -f $tag))) {
        try {
            $new = New-MgGroup -BodyParameter $body -ErrorAction Stop
            $extra = if ($g.RoleAssignable) { ' [role-assignable]' } else { '' }
            Write-Host ("+ Criado: {0} ({1}){2}" -f $name, $new.Id, $extra) -ForegroundColor Green
            $results.Add([pscustomobject]@{ Grupo = $name; ObjectId = $new.Id; Estado = 'Criado'; RoleAssignable = $g.RoleAssignable; AmbitoAlvoMG = $g.ScopeMg; Role = $g.Role })

            if ($GroupOwners) {
                foreach ($ownerUpn in $GroupOwners) {
                    try {
                        $u = Get-MgUser -UserId $ownerUpn -ErrorAction Stop
                        $ref = "https://graph.microsoft.com/v1.0/directoryObjects/$($u.Id)"
                        New-MgGroupOwnerByRef -GroupId $new.Id -BodyParameter @{ '@odata.id' = $ref } -ErrorAction Stop
                        Write-Host ("    owner adicionado: {0}" -f $ownerUpn) -ForegroundColor DarkGreen
                    } catch { Write-Warning ("    Falha ao definir owner '{0}' em {1}: {2}" -f $ownerUpn, $name, $_.Exception.Message) }
                }
            }
        } catch {
            Write-Warning ("Falha ao criar '{0}': {1}" -f $name, $_.Exception.Message)
            $results.Add([pscustomobject]@{ Grupo = $name; ObjectId = ''; Estado = 'Erro'; RoleAssignable = $g.RoleAssignable; AmbitoAlvoMG = $g.ScopeMg; Role = $g.Role })
        }
    } else {
        $results.Add([pscustomobject]@{ Grupo = $name; ObjectId = '(WhatIf)'; Estado = 'Simulado'; RoleAssignable = $g.RoleAssignable; AmbitoAlvoMG = $g.ScopeMg; Role = $g.Role })
    }
}

# (Opcional) Semear membros
if ($MemberMappingCsv) {
    if (-not (Test-Path $MemberMappingCsv)) { throw "Mapeamento de membros nao encontrado: $MemberMappingCsv" }
    Write-Host ("`nA semear membros a partir de: {0}" -f $MemberMappingCsv) -ForegroundColor Cyan
    $map = Import-Csv $MemberMappingCsv
    $idByName = @{}
    foreach ($r in $results) { if ($r.ObjectId -and $r.ObjectId -notmatch 'WhatIf') { $idByName[$r.Grupo] = $r.ObjectId } }

    foreach ($row in $map) {
        $grp = $row.'Grupo-Alvo'
        if (-not $grp -or -not $idByName.ContainsKey($grp)) { continue }
        $principalId = $null
        if (($row.PSObject.Properties.Name -contains 'PrincipalObjectId') -and $row.PrincipalObjectId) {
            $principalId = $row.PrincipalObjectId
        } elseif (($row.PSObject.Properties.Name -contains 'Login') -and $row.Login) {
            try { $principalId = (Get-MgUser -UserId $row.Login -ErrorAction Stop).Id } catch { Write-Warning ("  Utilizador nao resolvido: {0}" -f $row.Login); continue }
        }
        if (-not $principalId) { continue }
        if ($PSCmdlet.ShouldProcess(("{0} <- {1}" -f $grp, $principalId), "Adicionar membro")) {
            try {
                $ref = "https://graph.microsoft.com/v1.0/directoryObjects/$principalId"
                New-MgGroupMemberByRef -GroupId $idByName[$grp] -BodyParameter @{ '@odata.id' = $ref } -ErrorAction Stop
                Write-Host ("  + {0} <- {1}" -f $grp, $principalId) -ForegroundColor Green
            } catch {
                if ($_.Exception.Message -match 'already exist|added object references already') {
                    Write-Host ("  = {0} ja contem {1}" -f $grp, $principalId) -ForegroundColor DarkGray
                } else { Write-Warning ("  Falha a adicionar {0} a {1}: {2}" -f $principalId, $grp, $_.Exception.Message) }
            }
        }
    }
}

$results | Sort-Object Grupo | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
Write-Host "`nResumo:" -ForegroundColor Cyan
$results | Group-Object Estado | ForEach-Object { Write-Host ("  {0,-10} {1}" -f $_.Name, $_.Count) }
Write-Host ("`nMapeamento Grupo -> ObjectId -> Ambito-Alvo exportado para: {0}" -f $ExportPath) -ForegroundColor Green
Write-Host "Use este CSV na Fase 4 (atribuicao dos grupos aos roles nos Management Groups)." -ForegroundColor Green
