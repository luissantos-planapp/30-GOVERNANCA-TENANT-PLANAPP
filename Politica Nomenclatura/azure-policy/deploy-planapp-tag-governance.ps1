<#
=====================================================================
 PLANAPP - Governanca de tags via Azure Policy
 ---------------------------------------------------------------------
 Cria as definicoes de politica, agrupa-as numa iniciativa e atribui-a
 a um ambito (management group ou subscricao), com:
   - Exigencia das 4 tags obrigatorias: equipa, ambiente, projeto, centrocusto
   - Valores controlados para 'equipa' (comeca por EMSITDIA) e 'ambiente'
   - Heranca automatica das 4 tags a partir do resource group (efeito Modify)
   - Identidade gerida + papel Tag Contributor + tarefas de remediacao

 Requisitos: modulo Az (Az.Resources, Az.PolicyInsights), sessao iniciada
 (Connect-AzAccount) com permissoes de Owner/Resource Policy Contributor
 e User Access Administrator no ambito alvo.

 ESTRATEGIA DE ROLLOUT (recomendada):
   1. Executar com -Effect Audit (predefinido) e observar a conformidade.
   2. Etiquetar os resource groups (fonte de heranca) e remediar.
   3. Mudar para -Effect Deny apos validacao.
=====================================================================
#>

param(
  # Ambito de atribuicao. Exemplos:
  #   Management group: "/providers/Microsoft.Management/managementGroups/<mgId>"
  #   Subscricao:       "/subscriptions/<subscriptionId>"
  [Parameter(Mandatory = $true)] [string] $Scope,

  # Local da identidade gerida (necessario para o efeito Modify).
  [string] $Location = "westeurope",

  # Audit (observacao) ou Deny (imposicao). Comecar por Audit.
  [ValidateSet("Audit", "Deny")] [string] $Effect = "Audit",

  # Valores canonicos aceites para a tag 'equipa'.
  [string[]] $AllowedEquipas = @("EMSITDIA"),

  # Codigos de ambiente aceites.
  [string[]] $AllowedAmbientes = @("hub", "prd", "nprd", "dev", "qua", "shared"),

  # Pasta com os ficheiros 01/02/03-*.json (predefinido: pasta do script).
  [string] $DefinitionsPath = $PSScriptRoot
)

$ErrorActionPreference = "Stop"
$tags = @("equipa", "ambiente", "projeto", "centrocusto")

Write-Host "==> A criar definicoes de politica personalizadas..." -ForegroundColor Cyan

$defRequire = New-AzPolicyDefinition `
  -Name "planapp-require-mandatory-tags" `
  -DisplayName "PLANAPP - Exigir tags obrigatorias (equipa, ambiente, projeto, centrocusto)" `
  -Policy (Join-Path $DefinitionsPath "01-policy-require-tags.json") `
  -ManagementGroupName $null  # se o ambito for management group, passar -ManagementGroupName <mgId> aqui e no assign

$defEquipa = New-AzPolicyDefinition `
  -Name "planapp-allowed-equipa" `
  -DisplayName "PLANAPP - Valores permitidos para a tag 'equipa'" `
  -Policy (Join-Path $DefinitionsPath "02-policy-allowed-equipa.json")

$defAmbiente = New-AzPolicyDefinition `
  -Name "planapp-allowed-ambiente" `
  -DisplayName "PLANAPP - Valores permitidos para a tag 'ambiente'" `
  -Policy (Join-Path $DefinitionsPath "03-policy-allowed-ambiente.json")

# Politica incorporada (built-in) que herda uma tag do resource group SE estiver em falta.
# Resolvida por nome para nao depender de GUIDs.
Write-Host "==> A resolver a built-in de heranca de tags..." -ForegroundColor Cyan
$inherit = Get-AzPolicyDefinition -Builtin |
  Where-Object { $_.Properties.DisplayName -eq "Inherit a tag from the resource group if missing" } |
  Select-Object -First 1
if (-not $inherit) { throw "Nao foi encontrada a built-in 'Inherit a tag from the resource group if missing'." }

# ---------------------------------------------------------------------
# Construir a iniciativa (policy set)
# ---------------------------------------------------------------------
Write-Host "==> A construir a iniciativa..." -ForegroundColor Cyan

$refs = @(
  @{ policyDefinitionId = $defRequire.PolicyDefinitionId;  policyDefinitionReferenceId = "require-mandatory-tags"; parameters = @{ effect = @{ value = "[parameters('effect')]" } }; groupNames = @("obrigatoriedade") }
  @{ policyDefinitionId = $defEquipa.PolicyDefinitionId;   policyDefinitionReferenceId = "allowed-equipa";         parameters = @{ effect = @{ value = "[parameters('effect')]" }; allowedEquipas  = @{ value = "[parameters('allowedEquipas')]" } };  groupNames = @("valores-controlados") }
  @{ policyDefinitionId = $defAmbiente.PolicyDefinitionId; policyDefinitionReferenceId = "allowed-ambiente";       parameters = @{ effect = @{ value = "[parameters('effect')]" }; allowedAmbientes = @{ value = "[parameters('allowedAmbientes')]" } }; groupNames = @("valores-controlados") }
)

# Uma referencia de heranca (Modify) por cada tag obrigatoria.
foreach ($t in $tags) {
  $refs += @{
    policyDefinitionId          = $inherit.PolicyDefinitionId
    policyDefinitionReferenceId = "inherit-$t"
    parameters                  = @{ tagName = @{ value = $t } }
    groupNames                  = @("heranca")
  }
}

$initiativeParams = @{
  effect           = @{ type = "String"; allowedValues = @("Audit", "Deny", "Disabled"); defaultValue = "Audit"; metadata = @{ displayName = "Efeito" } }
  allowedEquipas   = @{ type = "Array";  defaultValue = $AllowedEquipas;   metadata = @{ displayName = "Equipas permitidas" } }
  allowedAmbientes = @{ type = "Array";  defaultValue = $AllowedAmbientes; metadata = @{ displayName = "Ambientes permitidos" } }
}

$groups = @(
  @{ name = "obrigatoriedade";     displayName = "Obrigatoriedade das tags" }
  @{ name = "valores-controlados"; displayName = "Valores controlados" }
  @{ name = "heranca";             displayName = "Heranca a partir do resource group" }
)

$set = New-AzPolicySetDefinition `
  -Name "planapp-tag-governance" `
  -DisplayName "PLANAPP - Governanca de tags (obrigatoriedade + valores + heranca)" `
  -Description "Iniciativa que impoe as 4 tags obrigatorias da Politica de Nomenclaturas v2.0, controla os valores de 'equipa' e 'ambiente' e herda as tags do resource group." `
  -Metadata '{ "category": "Tags", "version": "1.0.0" }' `
  -PolicyDefinition ($refs | ConvertTo-Json -Depth 20) `
  -GroupDefinition ($groups | ConvertTo-Json -Depth 10) `
  -Parameter ($initiativeParams | ConvertTo-Json -Depth 20)

# ---------------------------------------------------------------------
# Atribuir a iniciativa com identidade gerida (necessaria para Modify)
# ---------------------------------------------------------------------
Write-Host "==> A atribuir a iniciativa no ambito $Scope (efeito: $Effect)..." -ForegroundColor Cyan

$assignment = New-AzPolicyAssignment `
  -Name "planapp-tag-governance" `
  -DisplayName "PLANAPP - Governanca de tags" `
  -PolicySetDefinition $set `
  -Scope $Scope `
  -IdentityType SystemAssigned `
  -Location $Location `
  -PolicyParameterObject @{
    effect           = $Effect
    allowedEquipas   = $AllowedEquipas
    allowedAmbientes = $AllowedAmbientes
  }

# Conceder 'Tag Contributor' a identidade para permitir a remediacao (Modify).
Write-Host "==> A conceder o papel 'Tag Contributor' a identidade gerida..." -ForegroundColor Cyan
Start-Sleep -Seconds 20  # aguardar a propagacao da identidade no Entra ID
$role = Get-AzRoleDefinition -Name "Tag Contributor"
New-AzRoleAssignment `
  -ObjectId $assignment.Identity.PrincipalId `
  -RoleDefinitionId $role.Id `
  -Scope $Scope | Out-Null

# ---------------------------------------------------------------------
# Tarefas de remediacao para as politicas Modify (heranca)
# ---------------------------------------------------------------------
Write-Host "==> A iniciar tarefas de remediacao (heranca de tags)..." -ForegroundColor Cyan
foreach ($t in $tags) {
  Start-AzPolicyRemediation `
    -Name "remediate-inherit-$t" `
    -PolicyAssignmentId $assignment.PolicyAssignmentId `
    -PolicyDefinitionReferenceId "inherit-$t" `
    -Scope $Scope | Out-Null
  Write-Host "    - remediacao iniciada para a tag '$t'"
}

Write-Host ""
Write-Host "Concluido. Iniciativa atribuida em modo '$Effect'." -ForegroundColor Green
Write-Host "Proximos passos:" -ForegroundColor Yellow
Write-Host "  1. Garantir que os RESOURCE GROUPS tem as 4 tags (sao a fonte da heranca)."
Write-Host "  2. Rever a conformidade no portal (Policy > Compliance) apos ~30 min."
Write-Host "  3. Quando estavel, reexecutar com -Effect Deny para impor."
