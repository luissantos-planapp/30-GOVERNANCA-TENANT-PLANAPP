<#
.SYNOPSIS
    Fase 2 (Desenho do Modelo Alvo) — gera a Matriz de Remediacao RBAC do PLANAPP
    a partir do inventario produzido na Fase 1 (Invoke-RBACInventory.ps1).

.DESCRIPTION
    Le o CSV de inventario (perfil, papel, nivel de ambito) e produz um workbook Excel
    com o mapeamento de cada atribuicao atual para o modelo-alvo baseado em grupos de
    seguranca (SG-AZ-<dominio>-<role>, conforme a Politica de Nomenclaturas v2.0, Seccao 7).

    Folhas geradas:
      1. Resumo               - indicadores e plano de remediacao
      2. Grupos-Alvo          - catalogo dos grupos SG-AZ-* a criar (role / ambito MG)
      3. Matriz Remediacao    - utilizadores internos -> grupo-alvo / acao / prioridade
      4. Service Principals   - identidades de servico (rever em separado)
      5. Contas Externas      - convidados B2B com acesso direto
      6. Grupos Existentes    - grupos ja atribuidos (validar / normalizar nomes)

    A logica de classificacao (dominio, grupo-alvo, acao, prioridade) e identica a usada
    no gerador de referencia, para resultados reproduziveis.

.PARAMETER InventoryCsv
    Caminho para o CSV de inventario (Fase 1). Por omissao usa o CSV mais recente
    'PLANAPP-RBAC-Inventario-*.csv' na pasta atual.

.PARAMETER OutputPath
    Caminho do workbook .xlsx a gerar. Por omissao na pasta atual.

.EXAMPLE
    .\New-RBACTargetMatrix.ps1 -InventoryCsv .\PLANAPP-RBAC-Inventario-20260607-094845.csv

.NOTES
    Requisito: modulo ImportExcel  (Install-Module ImportExcel -Scope CurrentUser).
    Apenas processa um ficheiro local — nao acede ao Azure.
#>

[CmdletBinding()]
param(
    [string] $InventoryCsv,
    [string] $OutputPath = (Join-Path (Get-Location) "PLANAPP-RBAC-Matriz-Alvo-Fase2.xlsx")
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    throw "Modulo 'ImportExcel' nao instalado. Instale com:  Install-Module ImportExcel -Scope CurrentUser"
}
Import-Module ImportExcel

if (-not $InventoryCsv) {
    $InventoryCsv = Get-ChildItem -Filter 'PLANAPP-RBAC-Inventario-*.csv' |
                    Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $InventoryCsv -or -not (Test-Path $InventoryCsv)) {
    throw "Inventario nao encontrado. Indique -InventoryCsv com o CSV da Fase 1."
}

Write-Host "A ler inventario: $InventoryCsv" -ForegroundColor Cyan
$inv = Import-Csv -Path $InventoryCsv

#region ---------- Logica de mapeamento (Fase 2) ----------

$DomainCode = @{ 'Plataforma' = 'Platform'; 'Produção' = 'Prd'; 'Não-Produção' = 'Nprd'; 'Sandbox' = 'Sandbox' }
$RoleCode   = @{ 'Owner' = 'Owner'; 'Contributor' = 'Contributor'; 'Reader' = 'Reader' }
$TargetMg   = @{ 'Plataforma' = 'mg-planapp-platform'; 'Produção' = 'mg-planapp-lz-prod';
                 'Não-Produção' = 'mg-planapp-lz-nprd'; 'Sandbox' = 'mg-planapp-sandbox' }

function Get-Domain {
    param([string] $Ambito, [string] $Scope)
    $t = ("$Ambito $Scope").ToLower()
    if ($t -match 'sandbox') { return 'Sandbox' }
    if ($t -match 'decom|disab|temp') { return 'Descontinuadas' }
    if ($t -match 'nprd|dev|staging|test') { return 'Não-Produção' }   # nprd antes de prd
    if ($t -match 'prd|prod') { return 'Produção' }
    if ($t -match 'hub|shared|platform|datagov|fabric|backup|netsec') { return 'Plataforma' }
    if ($t -match 'enterprise|-ea-') { return 'Raiz/EA' }
    return 'Indefinido'
}

function Get-TargetGroup {
    param([string] $Domain, [string] $Role)
    if ($DomainCode.ContainsKey($Domain) -and $RoleCode.ContainsKey($Role)) {
        return "SG-AZ-$($DomainCode[$Domain])-$($RoleCode[$Role])"
    }
    return ''
}

function Get-TargetScope {
    param([string] $Domain, [string] $Nivel)
    if ($TargetMg.ContainsKey($Domain)) {
        if ($Nivel -in @('Management Group', 'Subscricao')) { return $TargetMg[$Domain] }
        return "$($TargetMg[$Domain]) (ou grupo de projeto)"
    }
    return 'N/A'
}

function Get-Priority {
    param([string] $Role, [bool] $External = $false)
    if ($External) { return 'Alta' }
    if ($Role -in @('Owner', 'User Access Administrator', 'Role Based Access Control Administrator')) { return 'Alta' }
    if ($Role -like '*Administrator*') { return 'Alta' }
    if ($Role -eq 'Contributor') { return 'Média' }
    if ($Role -like '*Reader*') { return 'Baixa' }
    return 'Média'
}

function Get-UserAction {
    param([string] $Domain, [string] $Nivel, [string] $Target)
    if ($Target) {
        if ($Nivel -in @('Management Group', 'Subscricao')) { return 'Migrar p/ grupo (MG)' }
        return 'Criar grupo de projeto (granular)'
    }
    if ($Domain -in @('Descontinuadas', 'Raiz/EA')) { return 'Rever / Remover (âmbito a descontinuar)' }
    return 'Papel especializado — manter direto ou grupo dedicado'
}

function Get-Obs {
    param([string] $Domain, [string] $Nivel, [string] $Role)
    $n = @()
    if ($Nivel -eq 'Recurso') { $n += 'Atribuição em recurso individual — avaliar grupo de projeto' }
    if ($Domain -eq 'Indefinido') { $n += 'Domínio não classificado — rever manualmente' }
    if ($Role -eq 'Owner' -and $Nivel -in @('Management Group', 'Subscricao')) { $n += 'Owner direto em âmbito amplo — prioridade' }
    return ($n -join '; ')
}

$prioRank = @{ 'Alta' = 0; 'Média' = 1; 'Baixa' = 2 }

#endregion

#region ---------- Segmentacao e construcao das linhas ----------

foreach ($a in $inv) {
    $a | Add-Member -NotePropertyName Dominio2 -NotePropertyValue (Get-Domain $a.AmbitoNome $a.Scope) -Force
    $a | Add-Member -NotePropertyName IsExt -NotePropertyValue ([bool]($a.PrincipalLogin -match '#EXT#')) -Force
}

$groups = $inv | Where-Object { $_.Perfil -eq 'Grupo' }
$sps    = $inv | Where-Object { $_.Perfil -in @('Service Principal', 'Identidade Gerida') }
$exts   = $inv | Where-Object { $_.Perfil -eq 'Utilizador' -and $_.IsExt }
$users  = $inv | Where-Object { $_.Perfil -eq 'Utilizador' -and -not $_.IsExt }

# --- Matriz Remediacao (utilizadores internos) ---
$matriz = foreach ($u in $users) {
    $tgt = Get-TargetGroup $u.Dominio2 $u.Papel
    [pscustomobject][ordered]@{
        'Domínio'        = $u.Dominio2
        'Nível Âmbito'   = $u.NivelAmbito
        'Âmbito (atual)' = $u.AmbitoNome
        'Papel atual'    = $u.Papel
        'Utilizador'     = $u.PrincipalNome
        'Login'          = $u.PrincipalLogin
        'Âmbito-Alvo'    = Get-TargetScope $u.Dominio2 $u.NivelAmbito
        'Grupo-Alvo'     = $tgt
        'Ação'           = Get-UserAction $u.Dominio2 $u.NivelAmbito $tgt
        'Prioridade'     = Get-Priority $u.Papel
        'Observações'    = Get-Obs $u.Dominio2 $u.NivelAmbito $u.Papel
    }
}
$matriz = $matriz | Sort-Object @{e={$prioRank[$_.'Prioridade']}}, 'Domínio', 'Papel atual'

# --- Service Principals ---
$spRows = foreach ($s in $sps) {
    [pscustomobject][ordered]@{
        'Domínio'          = $s.Dominio2
        'Nível Âmbito'     = $s.NivelAmbito
        'Âmbito'           = $s.AmbitoNome
        'Papel'            = $s.Papel
        'Service Principal'= if ($s.PrincipalNome) { $s.PrincipalNome } else { '(sem nome)' }
        'Ação'             = 'Segregar — conta de serviço (validar necessidade)'
        'Scope'            = $s.Scope
    }
}
$spRows = $spRows | Sort-Object 'Domínio', 'Papel'

# --- Contas Externas (B2B) ---
$extRows = foreach ($e in $exts) {
    [pscustomobject][ordered]@{
        'Domínio'      = $e.Dominio2
        'Nível Âmbito' = $e.NivelAmbito
        'Âmbito'       = $e.AmbitoNome
        'Papel'        = $e.Papel
        'Convidado'    = $e.PrincipalNome
        'Login'        = $e.PrincipalLogin
        'Ação'         = 'Rever acesso externo (B2B)'
        'Prioridade'   = Get-Priority $e.Papel $true
    }
}
$extRows = $extRows | Sort-Object @{e={$prioRank[$_.'Prioridade']}}, 'Domínio'

# --- Grupos Existentes ---
$grpRows = foreach ($g in $groups) {
    [pscustomobject][ordered]@{
        'Domínio'      = $g.Dominio2
        'Nível Âmbito' = $g.NivelAmbito
        'Âmbito'       = $g.AmbitoNome
        'Papel'        = $g.Papel
        'Grupo'        = $g.PrincipalNome
        'Convenção'    = if ($g.PrincipalNome -like 'SG-*') { 'Conforme convenção' } else { 'Normalizar p/ SG-AZ-*' }
    }
}
$grpRows = $grpRows | Sort-Object 'Domínio', 'Papel', 'Grupo'

# --- Catalogo Grupos-Alvo ---
$catalog = @(
    [pscustomobject]@{ 'Grupo (Entra ID)'='SG-AZ-Platform-Owner';       Role='Owner';       'Âmbito (MG)'='mg-planapp-platform'; 'Domínio'='Plataforma';   'Role-assignable'='Sim'; 'PIM recomendado'='Sim'; 'Membros estimados'=0; 'Descrição'='Equipa central SITDIA — controlo total da plataforma' }
    [pscustomobject]@{ 'Grupo (Entra ID)'='SG-AZ-Platform-Contributor'; Role='Contributor'; 'Âmbito (MG)'='mg-planapp-platform'; 'Domínio'='Plataforma';   'Role-assignable'='Não'; 'PIM recomendado'='Não'; 'Membros estimados'=0; 'Descrição'='Operação de infraestrutura sem acesso a IAM' }
    [pscustomobject]@{ 'Grupo (Entra ID)'='SG-AZ-Platform-Reader';      Role='Reader';      'Âmbito (MG)'='mg-planapp-platform'; 'Domínio'='Plataforma';   'Role-assignable'='Não'; 'PIM recomendado'='Não'; 'Membros estimados'=0; 'Descrição'='Segurança / Cloud Governance — leitura para auditoria' }
    [pscustomobject]@{ 'Grupo (Entra ID)'='SG-AZ-Prd-Owner';           Role='Owner';       'Âmbito (MG)'='mg-planapp-lz-prod';  'Domínio'='Produção';     'Role-assignable'='Sim'; 'PIM recomendado'='Sim'; 'Membros estimados'=0; 'Descrição'='SITDIA — supervisão e gestão de RBAC nas LZ de produção' }
    [pscustomobject]@{ 'Grupo (Entra ID)'='SG-AZ-Prd-Contributor';     Role='Contributor'; 'Âmbito (MG)'='mg-planapp-lz-prod';  'Domínio'='Produção';     'Role-assignable'='Não'; 'PIM recomendado'='Não'; 'Membros estimados'=0; 'Descrição'='Dev/gestão de aplicações em produção' }
    [pscustomobject]@{ 'Grupo (Entra ID)'='SG-AZ-Prd-Reader';          Role='Reader';      'Âmbito (MG)'='mg-planapp-lz-prod';  'Domínio'='Produção';     'Role-assignable'='Não'; 'PIM recomendado'='Não'; 'Membros estimados'=0; 'Descrição'='Suporte, auditoria e segurança' }
    [pscustomobject]@{ 'Grupo (Entra ID)'='SG-AZ-Nprd-Owner';          Role='Owner';       'Âmbito (MG)'='mg-planapp-lz-nprd';  'Domínio'='Não-Produção'; 'Role-assignable'='Sim'; 'PIM recomendado'='Sim'; 'Membros estimados'=0; 'Descrição'='SITDIA — governação das LZ de não-produção' }
    [pscustomobject]@{ 'Grupo (Entra ID)'='SG-AZ-Nprd-Contributor';    Role='Contributor'; 'Âmbito (MG)'='mg-planapp-lz-nprd';  'Domínio'='Não-Produção'; 'Role-assignable'='Não'; 'PIM recomendado'='Não'; 'Membros estimados'=0; 'Descrição'='Equipas de Dev/Test' }
    [pscustomobject]@{ 'Grupo (Entra ID)'='SG-AZ-Nprd-Reader';         Role='Reader';      'Âmbito (MG)'='mg-planapp-lz-nprd';  'Domínio'='Não-Produção'; 'Role-assignable'='Não'; 'PIM recomendado'='Não'; 'Membros estimados'=0; 'Descrição'='Suporte / QA / auditoria' }
    [pscustomobject]@{ 'Grupo (Entra ID)'='SG-AZ-Sandbox-Owner';       Role='Owner';       'Âmbito (MG)'='mg-planapp-sandbox';  'Domínio'='Sandbox';      'Role-assignable'='Sim'; 'PIM recomendado'='Sim'; 'Membros estimados'=0; 'Descrição'='SITDIA — ciclo de vida dos recursos temporários' }
    [pscustomobject]@{ 'Grupo (Entra ID)'='SG-AZ-Sandbox-Contributor'; Role='Contributor'; 'Âmbito (MG)'='mg-planapp-sandbox';  'Domínio'='Sandbox';      'Role-assignable'='Não'; 'PIM recomendado'='Não'; 'Membros estimados'=0; 'Descrição'='Equipas de experimentação' }
    [pscustomobject]@{ 'Grupo (Entra ID)'='SG-AZ-Sandbox-Reader';      Role='Reader';      'Âmbito (MG)'='mg-planapp-sandbox';  'Domínio'='Sandbox';      'Role-assignable'='Não'; 'PIM recomendado'='Não'; 'Membros estimados'=0; 'Descrição'='Visibilidade opcional de pilotos' }
    [pscustomobject]@{ 'Grupo (Entra ID)'='SG-AZ-Workloads-SP';        Role='(vários)';    'Âmbito (MG)'='Por recurso/workload'; 'Domínio'='Transversal'; 'Role-assignable'='Não'; 'PIM recomendado'='Não'; 'Membros estimados'=0; 'Descrição'='Segregar service principals de workloads (rever caso a caso)' }
)
# Membros estimados = nº de utilizadores internos cujo grupo-alvo corresponde
foreach ($g in $catalog) {
    $g.'Membros estimados' = @($matriz | Where-Object { $_.'Grupo-Alvo' -eq $g.'Grupo (Entra ID)' }).Count
}

#endregion

#region ---------- Resumo ----------

$ownersToUsers = @($inv | Where-Object { $_.Papel -eq 'Owner' -and $_.Perfil -eq 'Utilizador' }).Count
$resourceLevel = @($inv | Where-Object { $_.NivelAmbito -eq 'Recurso' }).Count
$byAction = $matriz | Group-Object 'Ação' | ForEach-Object {
    [pscustomobject]@{ Indicador = $_.Name; Valor = $_.Count }
}

$resumo = @(
    [pscustomobject]@{ Indicador = 'Total de atribuições';                         Valor = $inv.Count }
    [pscustomobject]@{ Indicador = 'Utilizadores internos';                        Valor = @($users).Count }
    [pscustomobject]@{ Indicador = 'Utilizadores externos (B2B)';                  Valor = @($exts).Count }
    [pscustomobject]@{ Indicador = 'Service principals / identidades geridas';     Valor = @($sps).Count }
    [pscustomobject]@{ Indicador = 'Grupos (já conformes)';                        Valor = @($groups).Count }
    [pscustomobject]@{ Indicador = 'Owners atribuídos a utilizadores';             Valor = $ownersToUsers }
    [pscustomobject]@{ Indicador = 'Atribuições em recurso individual';            Valor = $resourceLevel }
    [pscustomobject]@{ Indicador = '— Plano de remediação —';                      Valor = '' }
)
$resumo += $byAction
$resumo += [pscustomobject]@{ Indicador = 'Rever acesso externo (B2B)';           Valor = @($exts).Count }
$resumo += [pscustomobject]@{ Indicador = 'Grupos a criar (catálogo SG-AZ-*)';   Valor = $catalog.Count }

#endregion

#region ---------- Exportacao Excel ----------

if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force }
$xl = @{ Path = $OutputPath; AutoSize = $true; FreezeTopRow = $true; BoldTopRow = $true; AutoFilter = $true }

$resumo  | Export-Excel @xl -WorksheetName 'Resumo'           -Title 'PLANAPP — Modelo RBAC Alvo (Fase 2)' -TitleBold
$catalog | Export-Excel @xl -WorksheetName 'Grupos-Alvo'
$matriz  | Export-Excel @xl -WorksheetName 'Matriz Remediação'
$spRows  | Export-Excel @xl -WorksheetName 'Service Principals'
$extRows | Export-Excel @xl -WorksheetName 'Contas Externas (B2B)'
$grpRows | Export-Excel @xl -WorksheetName 'Grupos Existentes'

# Realce de prioridade (Alta/Média/Baixa) na Matriz e Externas
$rules = @(
    New-ConditionalText -Text 'Alta'  -BackgroundColor '#F8CBAD' -ConditionalTextColor Black
    New-ConditionalText -Text 'Média' -BackgroundColor '#FFE699' -ConditionalTextColor Black
    New-ConditionalText -Text 'Baixa' -BackgroundColor '#C6EFCE' -ConditionalTextColor Black
)
foreach ($sheet in 'Matriz Remediação', 'Contas Externas (B2B)') {
    $resumo | Out-Null
    Export-Excel -Path $OutputPath -WorksheetName $sheet -ConditionalText $rules
}

Write-Host "Matriz-alvo gerada: $OutputPath" -ForegroundColor Green
Write-Host ("  Utilizadores internos : {0}" -f @($users).Count)
Write-Host ("  Externos (B2B)        : {0}" -f @($exts).Count)
Write-Host ("  Service principals    : {0}" -f @($sps).Count)
Write-Host ("  Grupos existentes     : {0}" -f @($groups).Count)
Write-Host ("  Grupos-alvo a criar   : {0}" -f $catalog.Count)

#endregion
