# Política de Nomenclaturas do PLANAPP

> **Versão:** 2.0  
> **Data:** 2026-06-05  
> **Estado:** Rascunho para revisão e aprovação  
> **Origem:** Revisão da versão 1.1 e consolidação da proposta v2.0

## 1. Objetivo
Estabelecer regras únicas de nomenclatura e metadados para todos os ambientes e recursos do PLANAPP, garantindo consistência, legibilidade, rastreabilidade, automação e governação.

## 2. Âmbito
Esta política aplica-se a:

- Recursos Microsoft Azure (subscrições, resource groups e serviços).
- Microsoft Fabric (workspaces e artefactos de dados/analytics).
- Azure AI Foundry e Copilot Studio (agentes e recursos associados).
- Power Platform (ambientes, soluções, apps, flows e Dataverse).
- Ambientes de ciclo de vida (hub, shared, prd, nprd, dev, qua).
- Identidade e acessos (Microsoft Entra ID).
- Colaboração Microsoft 365 (Teams, SharePoint, OneDrive, OneNote).
- Estrutura de pastas e ficheiros (alinhada com a Norma Interna 002-2021).

## 3. Princípios Gerais

- **Consistência:** mesma ordem de componentes para o mesmo tipo de objeto.
- **Legibilidade:** nome compreensível sem documentação adicional.
- **Concisão:** abreviaturas normalizadas e nomes curtos.
- **Unicidade:** garantir unicidade no âmbito exigido (local, tenant, global).
- **Sem dados sensíveis:** não incluir informação pessoal, segredos ou classificações.
- **Caracteres permitidos:** `a-z`, `0-9` e `-` (quando suportado pelo recurso).
- **Sem acentos e espaços** em nomes técnicos.
- **Minúsculas em Azure**, salvo exceções explícitas do serviço.

## 4. Glossário de Códigos

| Componente | Código | Significado |
|---|---|---|
| Organização | `pla` | PLANAPP |
| Região primária | `ne` | North Europe |
| Região secundária | `we` | West Europe |
| Produção | `prd` | Produção |
| Não-produção | `nprd` | Não-produção |
| Desenvolvimento | `dev` | Desenvolvimento |
| Qualidade | `qua` | Qualidade/Testes |
| Partilhado | `shared` | Serviços comuns |
| Conectividade central | `hub` | Hub de rede |

## 5. Azure: Estrutura de Nomes

### 5.1 Padrão base (v2)

```text
[tipo-recurso]-[workload]-[ambiente]-[regiao]-[instancia]
```

Exemplo:

```text
rg-site-prd-ne-001
```

### 5.2 Componentes

| Componente | Regra | Exemplo |
|---|---|---|
| tipo-recurso | Prefixo normalizado do recurso | `rg`, `vm`, `st`, `kv` |
| workload | Aplicação/projeto/carga de trabalho | `site`, `logs`, `pla` |
| ambiente | Código de ambiente | `prd`, `dev`, `qua`, `shared`, `hub` |
| regiao | Região Azure | `ne`, `we` |
| instancia | Sequência de 3 dígitos | `001`, `002` |

### 5.3 Prefixos Azure (catálogo completo v2)

| Categoria | Recurso | Prefixo |
|---|---|---|
| Core | Subscription (referência documental) | `sub` |
| Core | Management Group (referência documental) | `mg` |
| Core | Resource Group | `rg` |
| Rede | Virtual Network | `vnet` |
| Rede | Subnet | `snet` |
| Rede | Network Security Group | `nsg` |
| Rede | Route Table | `rt` |
| Rede | User Defined Route | `udr` |
| Rede | Public IP | `pip` |
| Rede | Public IP Prefix | `pipp` |
| Rede | Load Balancer | `lb` |
| Rede | Application Gateway | `agw` |
| Rede | NAT Gateway | `nat` |
| Rede | VPN Gateway | `vpngw` |
| Rede | Local Network Gateway | `lng` |
| Rede | ExpressRoute Circuit | `erc` |
| Rede | Private Endpoint | `pep` |
| Rede | Private DNS Zone | `pdns` |
| Rede | DNS Zone | `dns` |
| Rede | Azure Firewall | `afw` |
| Rede | DDoS Protection Plan | `ddos` |
| Rede | Bastion | `bas` |
| Compute | Virtual Machine | `vm` |
| Compute | Virtual Machine Scale Set | `vmss` |
| Compute | Availability Set | `avset` |
| Compute | Disk (Managed Disk) | `disk` |
| Compute | Disk Snapshot | `snap` |
| Compute | Image (Compute Gallery Image) | `img` |
| Compute | Proximity Placement Group | `ppg` |
| Web e API | App Service Plan | `plan` |
| Web e API | Web App | `app` |
| Web e API | Function App | `func` |
| Web e API | API Management | `apim` |
| Web e API | Logic App | `logic` |
| Web e API | Static Web App | `swa` |
| Containers | Container Registry | `cr` |
| Containers | AKS Cluster | `aks` |
| Containers | Container Apps Environment | `cae` |
| Containers | Container App | `ca` |
| Containers | Container Instance | `aci` |
| Dados | Storage Account | `st` |
| Dados | Blob Container | `blob` |
| Dados | File Share | `share` |
| Dados | Queue Storage | `queue` |
| Dados | Table Storage | `table` |
| Dados | SQL Server | `sql` |
| Dados | SQL Database | `sqldb` |
| Dados | SQL Managed Instance | `sqlmi` |
| Dados | Azure Cosmos DB Account | `cos` |
| Dados | Azure Cosmos DB Database | `cosdb` |
| Dados | Azure Cosmos DB Container | `cosc` |
| Dados | Azure Database for PostgreSQL Flexible Server | `psql` |
| Dados | Azure Database for MySQL Flexible Server | `mysql` |
| Dados | Azure Cache for Redis / Azure Managed Redis | `redis` |
| Dados | Data Factory | `adf` |
| Dados | Synapse Workspace | `syn` |
| Dados | Synapse SQL Pool (Dedicated) | `synsql` |
| Dados | Event Hubs Namespace | `evh` |
| Dados | Event Hub | `eh` |
| Dados | Service Bus Namespace | `sb` |
| Dados | Service Bus Queue | `sbq` |
| Dados | Service Bus Topic | `sbt` |
| Dados | Service Bus Subscription | `sbs` |
| Dados | Stream Analytics Job | `asa` |
| Dados | Data Explorer (ADX/Kusto) Cluster | `adx` |
| Dados | Data Explorer Database | `adxdb` |
| AI e Analytics | Log Analytics Workspace | `log` |
| AI e Analytics | Application Insights | `appi` |
| AI e Analytics | Azure AI Services (Cognitive Services Account) | `ais` |
| AI e Analytics | Azure OpenAI / AI Foundry Model Resource | `aoai` |
| AI e Analytics | Azure AI Search | `srch` |
| AI e Analytics | Azure Machine Learning Workspace | `mlw` |
| AI e Analytics | Azure AI Foundry Hub/Project (quando aplicável) | `aif` |
| Segurança e Identidade | Key Vault | `kv` |
| Segurança e Identidade | Managed Identity (User Assigned) | `id` |
| Segurança e Identidade | Microsoft Entra Application (referência) | `sp` |
| Segurança e Identidade | Recovery Services Vault | `rsv` |
| Segurança e Identidade | Backup Vault | `bv` |
| Segurança e Identidade | Sentinel (sobre Log Analytics) | `si` |
| Integração e Operações | Automation Account | `aa` |
| Integração e Operações | Monitor Action Group | `ag` |
| Integração e Operações | Monitor Alert Rule | `alrt` |
| Integração e Operações | Dashboard / Workbook | `wb` |

Notas:

- Este catálogo é a referência oficial de prefixos Azure no PLANAPP.
- Novos prefixos devem ser aprovados pela Equipa GSI antes de uso em produção.
- Quando existir limitação de naming do serviço, prevalece a regra técnica do serviço Azure.
- Para recursos sem naming técnico em Azure (ex.: Subscription, Management Group), os prefixos acima aplicam-se a inventários, documentação e automação.

### 5.4 Restrições específicas

- **Storage Account:** sem hífen, apenas minúsculas e dígitos, máximo 24 caracteres.
- **Nomes globais (ex.: Key Vault, App Service, Storage):** obrigatoriamente únicos a nível global.
- Respeitar sempre as limitações de naming por serviço Azure.

### 5.5 Tags obrigatórias

| Tag | Descrição | Exemplo |
|---|---|---|
| `departamento` | Responsável funcional/técnico | `GSI` |
| `ambiente` | Ciclo de vida | `producao` |
| `projeto` | Projeto ou iniciativa | `website-institucional` |
| `centrocusto` | Centro de custo | `CC-001` |

### 5.6 Exemplos Azure

- `rg-site-prd-ne-001`
- `stplalogsprdne001`
- `kv-pla-shared-ne-001`
- `vnet-hub-prd-ne-001`
- `log-pla-shared-ne-001`

## 6. Nomenclatura de Ambientes

| Ambiente | Código | Finalidade |
|---|---|---|
| Produção | `prd` | Operação com dados reais |
| Não-produção | `nprd` | Ambientes não produtivos |
| Desenvolvimento | `dev` | Construção e experimentação |
| Qualidade | `qua` | Testes e homologação |
| Partilhado | `shared` | Serviços transversais |
| Hub | `hub` | Conectividade e base comum |

Regra transversal: usar sempre código em minúsculas e na posição definida para cada padrão.

## 7. Plataformas de Dados e AI (Fabric, Foundry, Copilot e Power Platform)

### 7.1 Microsoft Fabric

Padrão recomendado para workspaces:

```text
pla-mf-[dominio-ou-projeto]-[ambiente]
```

Exemplos:

- `pla-mf-financas-risco-prd`
- `pla-mf-dados-monitorizacao-dev`

Regras:

- Evitar nomes excessivamente longos (recomendado <= 50 caracteres para legibilidade).
- Em artefactos (lakehouses, pipelines, notebooks), usar prefixos curtos e consistentes:
	- `lh_` para lakehouse
	- `pl_` para pipelines
	- `nb_` para notebooks
- Evitar espaços e acentos em nomes técnicos.

### 7.2 Azure AI Foundry

Os recursos criados no Foundry devem seguir o padrão Azure desta política, evitando nomes aleatórios gerados automaticamente.

Exemplos:

- `pla-az-prd-ia-aoai01`
- `pla-az-nprd-ia-rg001`

Regra crítica:

- Se um recurso for criado com nome fora do padrão e não puder ser renomeado, deve ser recriado de forma conforme.

### 7.3 Copilot Studio

Padrão recomendado para agentes:

```text
pla-cp-[ambiente]-[projeto]-agt[funcao]
```

Exemplos:

- `pla-cp-dev-rh-agtassistente`
- `pla-cp-prd-atendimento-agtsuporte`

Regras:

- Em produção, privilegiar nome funcional limpo para apresentação ao utilizador final.
- Em dev/qua, pode ser usado sufixo de ambiente para facilitar operação e ALM.

### 7.4 Power Platform

Padrões recomendados:

- Ambientes: `PlanApp-PP-[AMBIENTE]-[AREA]`
- Soluções: `[Projeto]_[Ambiente]`
- Canvas Apps: `CA_[Area]_[Nome]`
- Flows: `[Verbo]_[Objeto]_[Contexto]`

Exemplos:

- `PlanApp-PP-PRD-FIN`
- `AtendimentoCidadao_PRD`
- `CA_RH_PedidoFerias`
- `EnviarRelatorioMensal_Scheduled`

## 8. Identidade (Microsoft Entra ID)

### 8.1 Utilizadores

- Contas nominais: `primeiro.ultimo@planapp.gov.pt`.
- Contas administrativas dedicadas: prefixo `adm-`.
- Contas guest: manter endereço de origem e sujeitar a revisão periódica.

### 8.2 Grupos

Padrão:

```text
grp-[finalidade]-[ambito-ou-ambiente]
```

Exemplos:

- `grp-sec-gsi-admins`
- `grp-m365-comunicacao`
- `grp-lic-e3`
- `grp-dl-todos`

### 8.3 Identidades de Serviço

- Managed identities: prefixo `id-`.
- Service principals/aplicações: prefixo `sp-`.

Exemplos:

- `id-site-prd-ne-001`
- `sp-integracao-prd`

## 9. Colaboração (Microsoft 365)

### 9.1 Teams

- Nome de equipa: `[Area/Projeto] - [Finalidade]`.
- Canais: curtos, descritivos e sem codificação técnica desnecessária.
- Projetos temporários: incluir ano/estado quando aplicável.

### 9.2 SharePoint

- Título do site claro e funcional.
- URL curta, em minúsculas, sem acentos e sem espaços.
- Bibliotecas com nomes estáveis e funcionais (`Documentos`, `Modelos`).

### 9.3 OneDrive e OneNote

- OneDrive para trabalho individual/rascunhos.
- Conteúdo final e colaborativo deve residir em SharePoint/Teams.
- OneNote com identificação da área/projeto.

## 10. Pastas e Ficheiros (Norma Interna 002-2021)

### 10.1 Pastas

- Em **MAIÚSCULAS** e sem acentos.
- Numeração sequencial no prefixo: `1.NOME_DA_PASTA`.
- Pastas obrigatórias: `1.INSTRUMENTOS DE GESTAO` e `2.HISTORICO`.

### 10.2 Ficheiros

- Em **MAIÚSCULAS** e sem acentos.
- Começar pelo tipo/designação documental.
- Comprimento máximo recomendado do nome: 30 caracteres.
- Caminho completo (pasta + ficheiro): até 100 caracteres.

Exemplo:

```text
OFICIO_001.2021_MOBILIDADE JPM
```

### 10.3 Boas práticas

- Evitar duplicação entre OneDrive e SharePoint.
- Preferir versionamento nativo M365 a sufixos manuais (`_v2`, `_final`).
- Usar datas no formato `AAAA.MM.DD` quando aplicável.

## 11. Governação e Conformidade

### 11.1 Enforcement

- Em Azure, aplicar Azure Policy para nomenclatura e tags.
- Em Azure AI Foundry, aplicar as mesmas Azure Policies da subscrição.
- Em Fabric, aplicar governação por processo (CoE, auditorias e CI/CD com validações de naming).
- Em Power Platform, usar CoE Starter Kit, ALM e restrição de criação de ambientes.
- Em M365 Groups/Teams, usar Entra ID Naming Policy (prefix/suffix e blocked words).
- Recursos não conformes devem ser sinalizados e corrigidos.
- Em Entra ID e M365, usar processos de aprovisionamento controlados e revisão periódica.

### 11.2 Responsabilidades

| Função | Responsabilidade |
|---|---|
| Equipa GSI | Manter política, definir padrões, fiscalizar conformidade e gerir exceções |
| Criadores de recursos | Aplicar convenções no momento da criação |
| Responsáveis de área/projeto | Garantir organização e conformidade contínua |

### 11.3 Revisão

- Revisão mínima anual.
- Revisão extraordinária em caso de alteração tecnológica ou organizacional relevante.
- Todas as alterações devem constar no controlo de versões.

### 11.4 Mapa de Enforcement por Domínio

| Domínio | Mecanismo principal |
|---|---|
| Azure | Azure Policy / Iniciativas |
| Azure AI Foundry | Azure Policy (herdado do Azure) |
| Microsoft Fabric | Governação manual + auditoria CoE + validações em CI/CD |
| Copilot Studio | ALM por soluções + monitorização CoE |
| Power Platform | CoE Starter Kit + Managed Environments + validações ALM |
| M365 Groups/Teams | Entra ID Naming Policy |
| M365 Sites/Identidades | Processos de aprovisionamento e revisão periódica |

## 12. Processo de Exceções

Quando uma convenção não puder ser cumprida:

1. Submeter pedido formal à Equipa GSI, com recurso, regra e justificação.
2. Realizar avaliação técnica e de risco.
3. Registar decisão (aprovação/recusa), prazo e condicionantes.
4. Rever exceções ativas periodicamente.

Exceções aprovadas não criam precedente automático para novos casos.

## 13. Políticas Relacionadas

- Norma Interna 002-2021 (pastas e ficheiros).
- Política de Segurança da Informação do PLANAPP.
- Política de Gestão de Identidades e Acessos.

## 14. Referências

- Microsoft Cloud Adoption Framework: naming convention.
- Microsoft Cloud Adoption Framework: resource abbreviations.
- Microsoft Entra ID: boas práticas de gestão de identidades.
- Boas práticas de naming para Microsoft Fabric, Power Platform e M365 (governação interna PLANAPP).

## 15. Controlo de Versões

| Versão | Data | Autor | Descrição |
|---|---|---|---|
| 1.0 | 2024 | Equipa GSI | Versão inicial (Azure) |
| 1.1 | 2025-05 | Equipa GSI | Atualização das convenções e tags Azure |
| 2.0 | 2026-06-05 | Luís Santos (proposta) | Alargamento transversal: Azure, Entra ID, M365, pastas/ficheiros, governação e exceções |
