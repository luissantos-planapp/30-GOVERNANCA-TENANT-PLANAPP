<#
.SYNOPSIS
    Fase 1 (Descoberta e Inventario) do Plano de Implementacao do Modelo RBAC do PLANAPP.
    Levantamento completo das atuais atribuicoes RBAC do tenant Azure.

.DESCRIPTION
    Extrai TODAS as role assignments do tenant PLANAPP em todos os niveis de ambito
    (Management Group, Subscricao e Resource Group) e produz um inventario consolidado.

    Para cada atribuicao mapeia:
      - Perfil / principal:  Utilizador, Grupo, Service Principal ou Identidade Gerida
      - Papel atribuido:     Owner, Contributor, Reader, etc. (RoleDefinitionName)
      - Nivel de ambito:     Management Group | Subscricao | Resource Group | Recurso
      - Atribuicao direta vs herdada (relevante para o principio "heranca no nivel mais alto")

    O resultado e exportado para CSV e JSON e e apresentado um resumo agregado na consola,
    servindo de base para a Fase 2 (Desenho do Modelo Alvo).

    Alinhado com o Microsoft Cloud Adoption Framework (CAF) / Enterprise-Scale e com a
    recomendacao do plano de automatizar o levantamento via Azure PowerShell.

.PARAMETER OutputFolder
    Pasta de destino dos ficheiros de inventario. Por omissao, o diretorio atual.

.PARAMETER ManagementGroupRoot
    Nome (Id) do Management Group raiz a partir do qual percorrer a hierarquia.
    Por omissao usa o Tenant Root Group (Id = Tenant Id).

    Para o PLANAPP pode indicar, p.ex., "mg-planapp" se existir um MG raiz dedicado.

.PARAMETER IncludeResourceGroups
    Quando presente, percorre tambem cada Resource Group de cada subscricao
    (necessario porque a auditoria indicou que 91% dos RG nao tem owner direto).
    Ativo por omissao; use -IncludeResourceGroups:$false para um levantamento mais rapido.

.PARAMETER IncludeClassicAdmins
    Inclui os Co-Administradores / Account Admins classicos (modelo antigo) no inventario.

.EXAMPLE
    .\Invoke-RBACInventory.ps1 -OutputFolder .\rbac-inventario -Verbose

.EXAMPLE
    .\Invoke-RBACInventory.ps1 -ManagementGroupRoot "mg-planapp" -IncludeResourceGroups

.NOTES
    Requisitos:
      - PowerShell 7.x (recomendado) ou Windows PowerShell 5.1
      - Modulos: Az.Accounts, Az.Resources, Az.ResourceGraph (opcional, acelera Resource Groups)
      - Permissoes de leitura (Reader) ao nivel do Management Group raiz para visibilidade total.
        Para ler todas as atribuicoes recomenda-se tambem o papel
        "Management Group Reader" + "Reader" herdado por todas as subscricoes.

    Execucao apenas de LEITURA: o script nao cria, altera nem remove qualquer atribuicao.
#>

[CmdletBinding()]
param(
    [string] $OutputFolder = (Get-Location).Path,
    [string] $ManagementGroupRoot,
    [bool]   $IncludeResourceGroups = $true,
    [switch] $IncludeClassicAdmins
)

#region ---------- Pre-requisitos e contexto ----------

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Module {
    param([string] $Name)
    if (-not (Get-Module -ListAvailable -Name $Name)) {
        throw "Modulo '$Name' nao instalado. Instale com:  Install-Module $Name -Scope CurrentUser"
    }
    Import-Module $Name -ErrorAction Stop
}

Write-Verbose "A validar modulos Az..."
Assert-Module -Name 'Az.Accounts'
Assert-Module -Name 'Az.Resources'

# Garantir sessao autenticada
$ctx = $null
try { $ctx = Get-AzContext } catch { $ctx = $null }
if (-not $ctx) {
    Write-Host "Sem sessao Azure ativa. A iniciar Connect-AzAccount..." -ForegroundColor Yellow
    Connect-AzAccount | Out-Null
    $ctx = Get-AzContext
}

$tenantId = $ctx.Tenant.Id
Write-Host "Tenant ativo: $tenantId  (conta: $($ctx.Account.Id))" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$csvPath   = Join-Path $OutputFolder "PLANAPP-RBAC-Inventario-$timestamp.csv"
$jsonPath  = Join-Path $OutputFolder "PLANAPP-RBAC-Inventario-$timestamp.json"
$sumPath   = Join-Path $OutputFolder "PLANAPP-RBAC-Resumo-$timestamp.txt"

#endregion

#region ---------- Funcoes auxiliares ----------

# Classifica o nivel de ambito a partir da string de Scope da atribuicao.
function Get-ScopeLevel {
    param([string] $Scope)
    if ([string]::IsNullOrWhiteSpace($Scope)) { return 'Desconhecido' }
    switch -Regex ($Scope) {
        '/providers/Microsoft\.Management/managementGroups/[^/]+$'         { return 'Management Group' }
        '^/subscriptions/[0-9a-fA-F-]+$'                                   { return 'Subscricao' }
        '^/subscriptions/[0-9a-fA-F-]+/resourceGroups/[^/]+$'              { return 'Resource Group' }
        '^/subscriptions/[0-9a-fA-F-]+/resourceGroups/[^/]+/providers/.+'  { return 'Recurso' }
        '^/$'                                                              { return 'Tenant Root' }
        default                                                            { return 'Outro' }
    }
}

# Normaliza o tipo de principal (perfil) exigido pelo inventario.
function Get-PrincipalType {
    param($Assignment)
    $t = $Assignment.ObjectType
    if ([string]::IsNullOrWhiteSpace($t)) { return 'Desconhecido' }
    switch ($t) {
        'User'             { 'Utilizador' }
        'Group'            { 'Grupo' }
        'ServicePrincipal' { 'Service Principal' }
        'ForeignGroup'     { 'Grupo Externo (B2B)' }
        'MSI'              { 'Identidade Gerida' }
        default            { $t }
    }
}

# Constroi a linha normalizada do inventario.
function New-InventoryRow {
    param(
        $Assignment,
        [string] $QueriedScope,
        [string] $ScopeName,
        [string] $ScopeDomain
    )

    $level     = Get-ScopeLevel -Scope $Assignment.Scope
    $isInherit = ($Assignment.Scope -ne $QueriedScope)

    [pscustomobject][ordered]@{
        Dominio            = $ScopeDomain
        NivelAmbito        = $level
        AmbitoNome         = $ScopeName
        Scope              = $Assignment.Scope
        Perfil             = Get-PrincipalType -Assignment $Assignment
        Papel              = $Assignment.RoleDefinitionName
        PrincipalNome      = $Assignment.DisplayName
        PrincipalLogin     = $Assignment.SignInName
        PrincipalObjectId  = $Assignment.ObjectId
        AtribuicaoDireta   = (-not $isInherit)
        Herdada            = $isInherit
        RoleAssignmentId   = $Assignment.RoleAssignmentId
        RoleAssignmentName = $Assignment.RoleAssignmentName
        CanDelegate        = $Assignment.CanDelegate
        Condicao           = $Assignment.Condition
    }
}

#endregion

#region ---------- Recolha de role assignments ----------

$inventory = New-Object System.Collections.Generic.List[object]
$seenIds   = New-Object System.Collections.Generic.HashSet[string]

function Add-Assignments {
    param(
        [array] $Assignments,
        [string] $QueriedScope,
        [string] $ScopeName,
        [string] $ScopeDomain
    )
    if (-not $Assignments) { return }
    foreach ($a in $Assignments) {
        # Dedupe global por RoleAssignmentId (heranca repete a mesma atribuicao em varios scopes).
        $key = if ($a.RoleAssignmentId) { $a.RoleAssignmentId } else { "$($a.ObjectId)|$($a.RoleDefinitionName)|$($a.Scope)" }
        if (-not $seenIds.Add($key)) { continue }
        $inventory.Add( (New-InventoryRow -Assignment $a -QueriedScope $QueriedScope -ScopeName $ScopeName -ScopeDomain $ScopeDomain) )
    }
}

# ---- 1) Management Groups (hierarquia completa) ----
Write-Host "`n[1/3] A percorrer Management Groups..." -ForegroundColor Green

$mgList = @()
try {
    if ($ManagementGroupRoot) {
        $mgList = @( Get-AzManagementGroup -GroupName $ManagementGroupRoot -Expand -Recurse -WarningAction SilentlyContinue )
    } else {
        $mgList = @( Get-AzManagementGroup -WarningAction SilentlyContinue )
    }
} catch {
    Write-Warning "Nao foi possivel enumerar Management Groups: $($_.Exception.Message)"
}

# Achatar a hierarquia para um conjunto unico de MGs.
$mgFlat = @{}
function Add-MgRecursive {
    param($Node)
    if (-not $Node) { return }
    if ($Node.Id -and -not $mgFlat.ContainsKey($Node.Id)) {
        $mgFlat[$Node.Id] = $Node.DisplayName
    }
    if ($Node.PSObject.Properties.Name -contains 'Children' -and $Node.Children) {
        foreach ($child in $Node.Children) {
            if ($child.Type -match 'managementGroups') { Add-MgRecursive -Node $child }
        }
    }
}
foreach ($mg in $mgList) {
    try {
        $full = Get-AzManagementGroup -GroupName $mg.Name -Expand -Recurse -WarningAction SilentlyContinue
        Add-MgRecursive -Node $full
    } catch {
        if ($mg.Id) { $mgFlat[$mg.Id] = $mg.DisplayName }
    }
}

foreach ($mgId in $mgFlat.Keys) {
    $mgName = $mgFlat[$mgId]
    Write-Verbose "  MG: $mgName"
    try {
        $ra = Get-AzRoleAssignment -Scope $mgId -WarningAction SilentlyContinue
        Add-Assignments -Assignments $ra -QueriedScope $mgId -ScopeName $mgName -ScopeDomain 'Management Group'
    } catch {
        Write-Warning "  Falha ao ler atribuicoes no MG '$mgName': $($_.Exception.Message)"
    }
}

# ---- 2) Subscricoes ----
Write-Host "[2/3] A percorrer Subscricoes..." -ForegroundColor Green

$subs = @( Get-AzSubscription -TenantId $tenantId | Where-Object { $_.State -eq 'Enabled' } )
Write-Host "  $($subs.Count) subscricao(oes) ativa(s) encontrada(s)." -ForegroundColor DarkGray

foreach ($sub in $subs) {
    Write-Verbose "  Subscricao: $($sub.Name) ($($sub.Id))"
    Set-AzContext -SubscriptionId $sub.Id -TenantId $tenantId -WarningAction SilentlyContinue | Out-Null
    $subScope = "/subscriptions/$($sub.Id)"

    try {
        $ra = Get-AzRoleAssignment -Scope $subScope -WarningAction SilentlyContinue
        Add-Assignments -Assignments $ra -QueriedScope $subScope -ScopeName $sub.Name -ScopeDomain 'Subscricao'
    } catch {
        Write-Warning "  Falha ao ler atribuicoes na subscricao '$($sub.Name)': $($_.Exception.Message)"
    }

    if ($IncludeClassicAdmins) {
        try {
            $classic = Get-AzRoleAssignment -Scope $subScope -IncludeClassicAdministrators -WarningAction SilentlyContinue |
                       Where-Object { $_.RoleDefinitionName -match 'Administrator' }
            Add-Assignments -Assignments $classic -QueriedScope $subScope -ScopeName $sub.Name -ScopeDomain 'Subscricao (Classic)'
        } catch { Write-Verbose "  Sem administradores classicos legiveis." }
    }

    # ---- 3) Resource Groups da subscricao ----
    if ($IncludeResourceGroups) {
        $rgs = @()
        try { $rgs = @( Get-AzResourceGroup -WarningAction SilentlyContinue ) } catch {
            Write-Warning "  Falha ao listar Resource Groups de '$($sub.Name)': $($_.Exception.Message)"
        }
        foreach ($rg in $rgs) {
            try {
                $ra = Get-AzRoleAssignment -Scope $rg.ResourceId -WarningAction SilentlyContinue
                Add-Assignments -Assignments $ra -QueriedScope $rg.ResourceId -ScopeName "$($sub.Name)/$($rg.ResourceGroupName)" -ScopeDomain 'Resource Group'
            } catch {
                Write-Warning "  Falha no RG '$($rg.ResourceGroupName)': $($_.Exception.Message)"
            }
        }
    }
}

Write-Host "[3/3] Recolha concluida. $($inventory.Count) atribuicoes unicas." -ForegroundColor Green

#endregion

#region ---------- Exportacao e resumo ----------

# Ordenar por nivel de ambito e papel para leitura.
$ordered = $inventory |
    Sort-Object @{e={ switch ($_.NivelAmbito) { 'Management Group' {0} 'Subscricao' {1} 'Resource Group' {2} 'Recurso' {3} default {4} } }}, Papel, PrincipalNome

$ordered | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
$ordered | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonPath -Encoding UTF8

# ----- Resumo agregado (indicadores para a Fase 2) -----
$totUnique = $ordered.Count
$byLevel   = $ordered | Group-Object NivelAmbito | Sort-Object Name
$byRole    = $ordered | Group-Object Papel | Sort-Object Count -Descending
$byProfile = $ordered | Group-Object Perfil | Sort-Object Count -Descending
$direct    = @($ordered | Where-Object { $_.AtribuicaoDireta }).Count
$inherited = @($ordered | Where-Object { $_.Herdada }).Count
$userOwner = @($ordered | Where-Object { $_.Papel -eq 'Owner' -and $_.Perfil -eq 'Utilizador' }).Count

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("=========================================================")
[void]$sb.AppendLine(" PLANAPP - Inventario RBAC (Fase 1: Descoberta)")
[void]$sb.AppendLine(" Tenant : $tenantId")
[void]$sb.AppendLine(" Data   : $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
[void]$sb.AppendLine("=========================================================")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Total de atribuicoes unicas : $totUnique")
[void]$sb.AppendLine("  - Diretas                 : $direct")
[void]$sb.AppendLine("  - Herdadas                : $inherited")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Por NIVEL DE AMBITO:")
foreach ($g in $byLevel) { [void]$sb.AppendLine(("  {0,-18} {1}" -f $g.Name, $g.Count)) }
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Por PERFIL (principal):")
foreach ($g in $byProfile) { [void]$sb.AppendLine(("  {0,-22} {1}" -f $g.Name, $g.Count)) }
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Por PAPEL (role):")
foreach ($g in $byRole) { [void]$sb.AppendLine(("  {0,-30} {1}" -f $g.Name, $g.Count)) }
[void]$sb.AppendLine("")
[void]$sb.AppendLine("ALERTA (anti-padrao): Owners atribuidos diretamente a utilizadores = $userOwner")
[void]$sb.AppendLine("  -> Candidatos a migracao para grupos 'az-pla-*-owner' (ver Fase 2/3).")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Ficheiros gerados:")
[void]$sb.AppendLine("  CSV  : $csvPath")
[void]$sb.AppendLine("  JSON : $jsonPath")

$summary = $sb.ToString()
$summary | Out-File -FilePath $sumPath -Encoding UTF8
Write-Host "`n$summary" -ForegroundColor White

Write-Host "Inventario exportado com sucesso." -ForegroundColor Cyan
Write-Host "  CSV : $csvPath"
Write-Host "  JSON: $jsonPath"
Write-Host "  TXT : $sumPath"

#endregion
