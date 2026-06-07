# Governança Tenant PLANAPP

**Projeto:** Governança do tenant Azure da PLANAPP  
**Responsável:** A definir (<email@planapp.gov.pt>)  
**Data Início:** 2026-03  
**Data Fim (estimada):** A definir  
**Duração Estimada:** Contínuo  
**Estado:** 🟢 Em Curso  
**Data de Aprovação:** A definir  
**Aprovado por:** A definir

---

## Visão Geral

Projeto de governança do tenant Microsoft da PLANAPP, com foco inicial em Azure e evolução para uma política transversal de nomenclaturas.

Inclui:

- Política de nomenclaturas v1.1 (Azure) e revisão para v2.0 (transversal ao tenant).
- Scripts PowerShell de inventário (subscrições, recursos, owners e AI Foundry).
- Outputs CSV e dashboard HTML para análise e remediação.

Objetivo: garantir que os ambientes e recursos são geridos de forma consistente, auditável, escalável e alinhada com boas práticas de governação.

## Project Owner

A definir — responsável pela governança IT e conformidade Azure.

## Stakeholders

| Nome / Entidade | Papel | Envolvimento |
|-----------------|-------|--------------|
| Direção PLANAPP | Decisor | Aprovação das políticas de governança |
| Equipa SITDIA | Implementador | Definição e aplicação das políticas |
| Equipas de projeto | Consultado | Adoção das nomenclaturas e políticas |
| Unipartner | Parceiro | Autora da Política de Nomenclaturas v1.1 |

## Parceiros

| Entidade | Papel |
|----------|-------|
| Unipartner | Elaboração da Política de Nomenclaturas Azure v1.1 (Sara Gonçalves) |

## Tecnologias

- Azure Policy (aplicação de regras de governança)
- Azure Resource Graph (inventário e consultas)
- PowerShell (scripts de automação e inventário)
- Microsoft Entra ID (gestão de identidades e owners)
- Azure Management Groups (hierarquia de gestão)
- Microsoft Fabric / AI Foundry (inventário e governança de recursos AI)
- Relatórios HTML e CSV (monitorização e apoio à remediação)

## Padrão de Nomenclatura

### Base histórica (v1.1 - Azure)

Baseado no CAF (Cloud Adoption Framework) da Microsoft:

```
<entidade>-<datacenter>-<ambiente>-<projeto>-<prefixoRecurso><numeração>
```

**Exemplo:** `pla-we-prd-site-rg001`

### Padrão atual em revisão (v2.0)

Para recursos Azure (estrutura recomendada na v2):

```
[tipo-recurso]-[workload]-[ambiente]-[regiao]-[instancia]
```

**Exemplo:** `rg-site-prd-ne-001`

A v2.0 alarga o âmbito para Azure, Entra ID, M365, Fabric, AI Foundry, Copilot Studio e Power Platform.

| Componente | Valores |
|------------|---------|
| Entidade | `pla` (PLANAPP) |
| Datacenter/Região | `we` (West Europe), `ne` (North Europe), `pt` (on-prem) |
| Ambiente | `hub`, `prd`, `nprd`, `dev`, `qua`, `shared` |

## Entregáveis

- `PLANAPP-Política_Nomenclaturas_v1.1.pdf` — política oficial de nomenclaturas Azure
- `PLANAPP-Politica_Nomenclaturas_v2.0.md` — proposta v2.0 em Markdown (transversal ao tenant)
- `PLANAPP-Politica_Nomenclaturas_v2.0_Proposta.docx` — proposta v2.0 em Word
- `PLANAPP-Nomenclaturas_Referencia.md` — referência rápida das nomenclaturas
- `PoliticaNomenclatura Transversal ao Tenant.pdf` — proposta de estrutura transversal
- `Análise Critica Política de Nomenclatura.pdf` — análise crítica da v1.1
- `01_levantamento_subscriptions_rgs.ps1` — script de inventário de subscrições e RGs
- `02_inventario_recursos.ps1` — script de inventário de recursos Azure
- `03_rg_owners.ps1` — script de levantamento de owners por RG
- `04_inventario_ai_foundry.ps1` — script de inventário AI Foundry
- `05_gerar_relatorio_html.ps1` — script de geração de relatório HTML
- `03_rg_owners_20260324_1545.csv` — output do inventário de owners (2026-03-24)
- `04a_ai_foundry_inventario_20260526_1000.csv` e `04a_ai_foundry_inventario_20260526_1028.csv` — inventário AI Foundry
- `04b_ai_foundry_deployments_20260526_1000.csv` e `04b_ai_foundry_deployments_20260526_1028.csv` — deployments AI Foundry
- `04c_ai_foundry_remediacao_20260526_1000.csv` e `04c_ai_foundry_remediacao_20260526_1028.csv` — plano de remediação
- `04_ai_foundry_relatorio_20260526_1030.html` — dashboard de governança AI Foundry

## Milestones

| # | Marco | Data Prevista | Estado |
|---|-------|---------------|--------|
| 1 | Política de nomenclaturas v1.1 publicada | 2025-05 | ✅ Concluído |
| 2 | Scripts PowerShell de inventário criados | 2026-03 | ✅ Concluído |
| 3 | Inventário de owners por RG executado | 2026-03-24 | ✅ Concluído |
| 4 | Inventário e dashboard de AI Foundry | 2026-05-26 | ✅ Concluído |
| 5 | Política de nomenclaturas v2.0 (rascunho) | 2026-06-05 | ✅ Concluído |
| 6 | Aprovação formal da v2.0 | A definir | 🔵 Planeado |
| 7 | Implementar enforcement técnico transversal | A definir | 🔵 Planeado |

## Plano de Trabalho (Backlog)

| # | Tarefa | Estado | Responsável | Data Prevista |
|---|--------|--------|-------------|---------------|
| 1 | Validar e aprovar formalmente a política de nomenclaturas v2.0 | 🔵 Planeado | Equipa GSI / Direção | A definir |
| 2 | Definir plano de remediação dos recursos não conformes | 🔵 Planeado | Equipa GSI | A definir |
| 3 | Implementar Azure Policy para enforcement de naming e tags | 🔵 Planeado | Equipa GSI | A definir |
| 4 | Definir governança para Fabric, Copilot e Power Platform (processo + auditoria) | 🔵 Planeado | Equipa GSI | A definir |
| 5 | Automatizar relatório periódico de conformidade (CSV + HTML) | 🔵 Planeado | Equipa GSI | A definir |

**Estados de tarefa:** 🔵 Planeado · 🟢 Em Curso · 🟠 Suspenso · ✅ Concluído · ❌ Cancelado

## Riscos e Mitigações

| # | Risco | Probabilidade | Impacto | Mitigação |
|---|-------|---------------|---------|-----------|
| 1 | Recursos criados sem seguir a política de nomenclaturas | Alta | Médio | Enforçar política via Azure Policy; formação das equipas |
| 2 | Owners de RGs desatualizados | Alta | Médio | Script recorrente de auditoria de owners (trimestral) |
| 3 | Política de nomenclaturas desatualizada | Baixa | Médio | Revisão anual da política |

## RGPD

> **Avaliação de necessidade de parecer do DPO**

- [ ] O projeto envolve tratamento de dados pessoais?  
- [ ] Foi realizada uma Análise de Impacto sobre a Proteção de Dados (AIPD / DPIA)?  
- [ ] Foi solicitado parecer ao DPO? **Data do pedido:** N/A  
- [ ] Parecer recebido? **Data:** N/A  

**Notas RGPD:** Projeto de governança técnica. Os scripts de inventário podem recolher nomes e emails de owners — garantir tratamento conforme com a política de proteção de dados.

## Próximos Passos

- Validar internamente e aprovar formalmente a política v2.0
- Priorizar remediações com base no inventário e dashboard AI Foundry
- Implementar enforcement Azure (naming/tags) e processo de auditoria transversal
- Agendar próxima auditoria de owners de Resource Groups
