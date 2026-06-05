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

Projeto de governança do tenant Azure da PLANAPP. Inclui a política de nomenclaturas Azure baseada no Cloud Adoption Framework (CAF), scripts PowerShell de inventário de subscrições, Resource Groups e owners, e documentação de conformidade. O objetivo é garantir que o tenant Azure da PLANAPP é gerido de forma consistente, auditável e alinhada com as boas práticas Microsoft.

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

## Padrão de Nomenclatura

Baseado no CAF (Cloud Adoption Framework) da Microsoft:

```
<entidade>-<datacenter>-<ambiente>-<projeto>-<prefixoRecurso><numeração>
```

**Exemplo:** `pla-we-prd-site-rg001`

| Componente | Valores |
|------------|---------|
| Entidade | `pla` (PLANAPP) |
| Datacenter/Região | `we` (West Europe), `ne` (North Europe), `pt` (on-prem) |
| Ambiente | `hub`, `prd`, `nprd`, `dev`, `qua`, `shared` |

## Entregáveis

- `PLANAPP-Política_Nomenclaturas_v1.1.pdf` — política oficial de nomenclaturas Azure
- `PLANAPP-Nomenclaturas_Referencia.md` — referência rápida das nomenclaturas
- `01_levantamento_subscriptions_rgs.ps1` — script de inventário de subscrições e RGs
- `02_inventario_recursos.ps1` — script de inventário de recursos Azure
- `03_rg_owners.ps1` — script de levantamento de owners por RG
- `03_rg_owners_20260324_1545.csv` — output do inventário de owners (2026-03-24)

## Milestones

| # | Marco | Data Prevista | Estado |
|---|-------|---------------|--------|
| 1 | Política de nomenclaturas v1.1 publicada | 2025-05 | ✅ Concluído |
| 2 | Scripts PowerShell de inventário criados | 2026-03 | ✅ Concluído |
| 3 | Inventário de owners por RG executado | 2026-03-24 | ✅ Concluído |
| 4 | Implementar Azure Policy de nomenclaturas | A definir | 🔵 Planeado |
| 5 | Revisão anual da política de nomenclaturas | A definir | 🔵 Planeado |

## Plano de Trabalho (Backlog)

| # | Tarefa | Estado | Responsável | Data Prevista |
|---|--------|--------|-------------|---------------|
| 1 | Corrigir recursos não conformes com a política de nomenclaturas | 🔵 Planeado | A definir | A definir |
| 2 | Implementar Azure Policy para enforçar nomenclaturas em novos recursos | 🔵 Planeado | A definir | A definir |
| 3 | Documentar processo de onboarding de novos projetos Azure | 🔵 Planeado | A definir | A definir |
| 4 | Automatizar relatório periódico de conformidade | 🔵 Planeado | A definir | A definir |

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

- Corrigir recursos Azure não conformes com a política de nomenclaturas v1.1
- Implementar Azure Policy para enforçar nomenclaturas em novos recursos
- Agendar próxima auditoria de owners de Resource Groups
