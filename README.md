# Governanca Tenant PLANAPP

Projeto de governanca do tenant Microsoft PLANAPP, evoluido de uma iniciativa de nomenclatura para um programa operacional de:

- Politica e conformidade de naming
- Inventario tecnico do tenant (recursos, tags, owners, management groups)
- Governanca de acessos e roles (modelo RBAC por grupos Entra ID)

## Estado do Projeto

- Estado geral: Em curso
- Data de inicio: 2026-03
- Horizonte: Continuo
- Ultima atualizacao de inventarios: 2026-06-07
- Linha de trabalho atual: consolidacao do modelo RBAC e operacionalizacao recorrente de auditorias

## Evolucao do Projeto

### Fase 1 - Politica de Nomenclaturas

- Base inicial em politica Azure v1.1
- Evolucao para politica v2.0 transversal ao tenant
- Definicao de estrutura de naming para Azure e alinhamento com Fabric/AI Foundry

### Fase 2 - Analise Estrutural e Inventario do Tenant

- Levantamento de subscriptions e resource groups
- Inventario global de recursos com Azure Resource Graph
- Avaliacao de conformidade de nomenclatura
- Auditoria de tags obrigatorias e cobertura
- Inventario de AI Foundry (workspaces, deployments e remediacao)
- Registo da estrutura de management groups

### Fase 3 - Modelo de Governanca RBAC

- Inventario completo de role assignments por ambito
- Definicao da matriz alvo por dominio/ambiente
- Criacao de grupos de seguranca SG-AZ-* no Entra ID
- Mapeamento de membros e atribuicao de roles
- Ativacao de PIM nos grupos elegiveis

## Estrutura do Repositorio

- `scripts/`: automacao de inventario, conformidade e remediacao tecnica
- `EstruturaTenant/`: snapshots CSV das execucoes (V1 e V2)
- `Politica Nomenclatura/`: politica, referencia e plano de implementacao
- `Modelo RBAC/`: scripts e evidencias da implementacao RBAC
- `Dashboards/`: relatorios HTML de suporte a decisao

## Scripts Principais

### Inventario e Conformidade (pasta scripts)

- `01_levantamento_subscriptions_rgs.ps1`: subscriptions, RGs e owners diretos por RG
- `02_inventario_recursos.ps1`: inventario cross-subscription + naming compliance + tags compliance
- `03_rg_owners.ps1`: levantamento dedicado de owners por RG
- `04_inventario_ai_foundry.ps1`: inventario de AI Foundry e deployments
- `05_gerar_relatorio_html.ps1`: geracao de dashboard HTML
- `06_estrutura_management_groups_subscriptions.ps1`: estrutura de management groups e associacoes
- `07_Inventario_Tags.ps1`: detalhe completo de tags e cobertura obrigatoria
- `08_aplicar_tags_obrigatorias_rgs.ps1`: aplicacao de tags base em RGs
- `09_aplicar_tags_from_excel.ps1`: carregamento de tags a partir de Excel
- `10_herdar_tags_rg_para_recursos.ps1`: heranca de tags de RG para recursos
- `Invoke-RBACInventory.ps1`: inventario RBAC (versao utilitaria na pasta scripts)

### RBAC (pasta Modelo RBAC)

- `Invoke-RBACInventory.ps1`: descoberta completa de role assignments no tenant
- `New-RBACTargetMatrix.ps1`: geracao da matriz alvo RBAC
- `New-RBACSecurityGroups.ps1`: criacao idempotente de grupos SG-AZ-* (inclui role-assignable)
- `Add-RBACGroupMembers.ps1`: carga de membros nos grupos
- `Set-RBACRoleAssignments.ps1`: atribuicao de roles aos grupos por ambito
- `Enable-RBACGroupPIM.ps1`: ativacao de PIM

## Artefactos Produzidos

### Inventario do Tenant (EstruturaTenant/V2/csv)

- `01_subscriptions_*.csv`
- `02_resource_groups_*.csv`
- `03_rg_owners_*.csv`
- `04_inventario_recursos_*.csv`
- `05_naming_compliance_*.csv`
- `06_tags_compliance_*.csv`
- `06_management_groups_estrutura_*.csv`
- `04a_ai_foundry_inventario_*.csv`
- `04b_ai_foundry_deployments_*.csv`
- `04c_ai_foundry_remediacao_*.csv`
- `tags-resumo.csv`, `tags-detalhe.csv`, `tags-cobertura.csv`

### RBAC (Modelo RBAC)

- `PLANAPP-RBAC-Inventario-*.csv` e `PLANAPP-RBAC-Inventario-*.json`
- `PLANAPP-RBAC-Resumo-*.txt`
- `PLANAPP-RBAC-Matriz-Alvo-Fase2.xlsx`
- `SG-AZ-Grupos-Criados*.csv`
- `SG-AZ-Membros-Resultado-*.csv`
- `SG-AZ-PIM-Resultado-*.csv`
- `SG-AZ-RoleAssign-Resultado-*.csv`

## Tecnologias e Servicos

- Azure Resource Graph
- Azure Policy
- Azure RBAC + Management Groups
- Microsoft Entra ID / Microsoft Graph
- PowerShell (Az + Microsoft.Graph)
- AI Foundry (inventario e governanca)
- CSV/HTML para auditoria e analise

## Maturidade Atual

O projeto ja nao se limita a nomenclatura. Neste momento funciona como base de governanca tecnica do tenant, com tres capacidades operacionais:

- Observabilidade de configuracao (inventario periodico)
- Medicao de conformidade (naming e tags)
- Controlo de acessos (RBAC por grupos, com evidencias de execucao)

## Backlog Prioritario

1. Formalizar aprovacao institucional da politica de nomenclaturas v2.0.
2. Consolidar cadencia operacional (mensal) para refresh de inventarios V2.
3. Integrar resultados de conformidade com planos de remediacao por equipa.
4. Evoluir enforcement por Azure Policy para naming/tags nas landing zones.
5. Fechar ciclo RBAC com revisoes periodicas de membros, roles e PIM.

## Notas de Operacao

- Os scripts de inventario sao de leitura/auditoria, exceto os scripts de aplicacao de tags e de RBAC.
- Para execucoes RBAC e Graph, garantir contexto de permissao adequado (Az + Microsoft Graph).
- Manter outputs versionados por timestamp para rastreabilidade.
