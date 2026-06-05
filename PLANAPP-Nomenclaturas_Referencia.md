# Política de Nomenclaturas Azure — PLANAPP

> **Fonte:** PLANAPP-Política_Nomenclaturas_v1.1.pdf  
> **Versão:** 1.1 · **Data:** 19/05/2025 · **Autora:** Sara Gonçalves (Unipartner)  
> **Documento de referência para o projeto de Governança do Tenant PLANAPP (20260320-001)**

---

## 1. Estrutura Geral de Nomenclatura

Baseada no **Cloud Adoption Framework (CAF)** da Microsoft, adaptada às necessidades da PLANAPP.

### Padrão base

```
<entidade>-<datacenter>-<ambiente>-<projeto>-<prefixoRecurso><numeração>
```

**Exemplo (Resource Group):**
```
pla-we-prd-site-rg001
```

### Componentes de nomeação

| Componente | Descrição | Valores / Exemplos |
|---|---|---|
| **Entidade** | Identificador da organização | `pla` (PLANAPP) — 3 chars |
| **Datacenter / Região** | Região Azure do deploy | `we` (West Europe), `ne` (North Europe), `pt` (Portugal on-prem) |
| **Ambiente** | Ciclo de vida / ambiente | `hub`, `prd`, `nprd`, `dev`, `qua`, `shared` |
| **Projeto / Serviço** | Aplicação ou workload | `site`, `logs`, `pbi`, `apim` — 2 a 8 chars |
| **Prefixo do recurso** | Tipo de recurso Azure | ver tabela abaixo |
| **Numeração** | Sequência numérica | `001` a `999` (3 dígitos) |

---

## 2. Regras Gerais

- **Letras minúsculas** em todos os recursos, **exceto** subscrições e management groups (maiúsculas).
- **Sem caracteres especiais**: proibido `*`, `#`, `&`, `+`, `:`, `<`, `>`, `?`, `_`. O carácter `-` é permitido quando o recurso o suporta.
- **Unicidade global** obrigatória para recursos PaaS com endpoints públicos (Storage Accounts, Key Vaults, App Services, Redis Cache, etc.).
- **Prefixo do tipo de recurso** antes da numeração.
- No mesmo Resource Group **nunca** podem existir recursos com o mesmo nome.
- Recursos partilhados transversalmente por vários projetos/workloads devem usar `shared` como componente de projeto.
- A região/datacenter é uma boa prática recomendada pela Microsoft mas pode ser dispensada.

### Tamanhos dos componentes

| Componente | Nº de caracteres |
|---|---|
| Entidade (organização) | 3 chars (`pla`) |
| Ambiente | 3 a 6 chars (`hub`, `prd`, `nprd`, `dev`, `qua`, `shared`) |
| Plataforma Azure (opcional) | 2 chars (a–z) |
| Departamento | 2 a 5 chars (a–z) |
| Tier | 2 a 3 chars (a–z) |
| Projeto | 2 a 8 chars (a–z) |
| Serviço | 2 a 4 chars (a–z) |
| Localização | 2 chars (sigla do datacenter Azure) |
| Prefixo do tipo de recurso | 2 a 5 chars (a–z) |
| Numeração | 3 dígitos (`001`–`999`) |
| Budget, Alerta, Blueprint | até 20 chars (permite `-`) |
| Hostname de VM | até 16 chars |

---

## 3. Prefixos por Tipo de Recurso

| Tipo de Recurso | Prefixo |
|---|---|
| AKS cluster | `aks` |
| Alert | `alt` |
| API Management service | `apim` |
| App Service Environment | `ase` |
| App Service Plan | `asp` |
| Application Gateway | `agw` |
| Application Insights | `appi` |
| Automation account | `aa` |
| Availability set | `avail` |
| Azure Analysis Services Server | `aas` |
| Azure Arc enabled Kubernetes cluster | `arck` |
| Azure Arc enabled server | `arcs` |
| Azure Cache for Redis | `redis` |
| Azure Compute Gallery | `cgall` |
| Azure Cosmos DB database | `cosmos` |
| Azure Data Factory | `adf` |
| Azure Data Lake Analytics | `dla` |
| Azure Data Lake Storage | `dls` |
| Azure Databricks workspace | `dbw` |
| Azure Migrate project | `migr` |
| Azure SQL Database | `sqldb` |
| Azure SQL Database server | `sql` |
| Azure Stream Analytics | `asa` |
| Azure Synapse Analytics | `syn` |
| Azure Synapse Analytics Workspaces | `synw` |
| Backup Vault | `bvault` |
| Backup Vault policy | `bkpol` |
| Bastion | `bas` |
| Blueprint | `bp` |
| Blueprint Assignment | `bpa` |
| Budget | `bgt` |
| Connections | `con` |
| Container Apps | `ca` |
| Container Apps Environment | `cae` |
| Container instance | `ci` |
| Container registry | `cr` |
| DNS private resolver | `dnspr` |
| Event Hubs | `evh` |
| Event Hubs namespace | `evhns` |
| Express Route Circuit | `erc` |
| File share | `share` |
| Firewall | `afw` |
| Firewall policy | `afwp` |
| Function App | `func` |
| Gateway connection | `cn` |
| IoT hub | `iot` |
| Key Vault | `kv` |
| Load balancer (external) | `lbe` |
| Load balancer (internal) | `lbi` |
| Load balancer rule | `rule` |
| Local Network Gateway | `lgw` |
| Log Analytics workspace | `law` |
| Logic Apps | `logic` |
| Managed disk (data) | `ddisk` |
| Managed disk (OS) | `osdisk` |
| Managed Identity | `mid` |
| Management group | `mg` |
| MySQL database | `mysql` |
| NAT gateway | `ng` |
| Network interface (NIC) | `nic` |
| Network security group (NSG) | `nsg` |
| NSG security rules | `nsgsr` |
| Notification Hubs | `nh` |
| Notification Hubs namespace | `nhn` |
| Policy | `polic` |
| PostgreSQL database | `psql` |
| Power BI Embedded | `pbi` |
| Private endpoint | `pep` |
| Private Link | `pl` |
| Public IP | `pip` |
| Public IP address prefix | `ippre` |
| Recovery Services vault | `rsv` |
| **Resource group** | **`rg`** |
| Route filter | `rf` |
| Route server | `rtserv` |
| Route table | `rt` |
| Service Bus | `sb` |
| Service Bus queue | `sbq` |
| Service Bus topic | `sbt` |
| Service Bus topic subscription | `sbts` |
| Service Fabric cluster | `sf` |
| Snapshot | `snap` |
| SQL Managed Instance | `sqlmi` |
| SSH Key | `sshk` |
| **Storage account** | **`sa`** |
| User defined route (UDR) | `udr` |
| Virtual desktop application group | `vdag` |
| Virtual desktop host pool | `vdpool` |
| Virtual desktop scaling plan | `vdscaling` |
| Virtual desktop workspace | `vdws` |
| Virtual machine | `vm` |
| Virtual machine scale set | `vmss` |
| Virtual network | `vnet` |
| Virtual network gateway | `vgw` |
| Virtual network peering | `peer` |
| Virtual network subnet | `snet` |
| VM image definition | `imdef` |
| VM storage account | `stvm` |
| VPN connection | `vcn` |
| VPN Gateway | `vpng` |
| VPN site | `vst` |
| Web app | `app` |
| Web Application Firewall (WAF) policy | `waf` |
| WAF policy rule group | `wafrg` |

---

## 4. Tags Obrigatórias

| Identificação | Descrição | Nome da Tag | Exemplo |
|---|---|---|---|
| Departamento | Departamento responsável pelos recursos / workloads | `departamento` | `dsi`, `rh` |
| Ambiente | Ambiente de implementação do projeto ou serviço | `ambiente` | `prd`, `qua`, `dev` |
| Projeto | Nome do projeto ou serviço associado ao recurso | `projeto` | `site`, `iot`, `pbi` |
| Centro de Custo | Centro de custo a imputar | `centrocusto` | `12345` |

---

## 5. Acordo de Nomenclaturas — Exemplos por Recurso

| Recurso | Nomenclatura acordada | Descrição do padrão |
|---|---|---|
| Alert | `pla-we-prd-site-app001-alt001` | Entidade-DC-Ambiente-RecursoAssociado-Prefixo+Nº |
| API Management | `pla-we-prd-shared-apim001` | Entidade-DC-Ambiente-Projeto-Prefixo+Nº |
| App Service Plan | `pla-we-prd-site-asp001` | Entidade-DC-Ambiente-Projeto-Prefixo+Nº *(global único)* |
| Azure App Service | `pla-we-prd-site-app001` | Entidade-DC-Ambiente-Projeto-Prefixo+Nº *(global único)* |
| Application Gateway | `pla-we-prd-shared-agw001` | Entidade-DC-Ambiente-Projeto-Prefixo+Nº |
| Application Insights | `pla-we-prd-site-appi001` | Entidade-DC-Ambiente-Projeto-Prefixo+Nº |
| Availability set | `pla-we-prd-logs-avail001` | Entidade-DC-Ambiente-GrupoVM-Prefixo+Nº |
| Azure Bastion | `pla-we-hub-shared-bas001` | Entidade-DC-Ambiente-Projeto-Prefixo+Nº |
| Azure Bastion Public IP | `pla-we-hub-shared-bas001-pip001` | RecursoAssociado-Prefixo+Nº |
| Azure Firewall | `pla-we-shared-hub-afw001` | Entidade-DC-Ambiente-Projeto-Prefixo+Nº |
| Azure Firewall Policy | `pla-we-shared-hub-afw001-polic001` | RecursoAssociado-Prefixo+Nº |
| Azure Firewall Public IP | `pla-we-shared-hub-afw001-pip001` | RecursoAssociado-Prefixo+Nº |
| Azure Functions | `pla-we-prd-site-logs-func001` | Entidade-DC-Ambiente-Projeto-Serviço-Prefixo+Nº |
| Azure Redis Cache | `pla-we-prd-site-redis001` | Entidade-DC-Ambiente-Projeto-Prefixo+Nº *(global único)* |
| Budget (Organização) | `pla-org-mg-bgt001` | Entidade-Org-MG-Prefixo+Nº |
| Budget (Management Group) | `pla-prd-mg-bgt001` | Entidade-Ambiente-MG-Prefixo+Nº |
| Budget (Resource Group) | `pla-prd-site-rg001-bgt001` | Entidade-Ambiente-RGAssociado-Prefixo+Nº |
| Budget (Subscription) | `pla-prd-hub-bgt001` | Entidade-Ambiente-SubscriptionAssociada-Prefixo+Nº |
| Diagnostic Settings | `pla-we-hub-netsec-law001-Diags001` | LAWNome-Prefixo+Nº |
| Express Route circuit | `pla-we-hub-shared-erc001` | Entidade-DC-Ambiente-Projeto-Prefixo+Nº |
| Key Vault | `pla-we-hub-netsec-kv001` | Entidade-DC-Ambiente-Projeto-Prefixo+Nº *(global único)* |
| Load balancer (internal) | `pla-we-prd-site-fe-ilb001` | Entidade-DC-Ambiente-Projeto-Tier-Prefixo+Nº |
| Load balancer (external) | `pla-we-prd-site-fe-elb001` | Entidade-DC-Ambiente-Projeto-Tier-Prefixo+Nº |
| Local Network Gateway | `pla-pt-prd-ff-lgw001` | Entidade-DC-Ambiente-Site-Prefixo+Nº |
| Log Analytics workspace | `pla-we-hub-netsec-law001` | Entidade-DC-Ambiente-Projeto-Prefixo+Nº |
| Logic Apps | `pla-we-prd-site-logs-logic001` | Entidade-DC-Ambiente-Projeto-Serviço-Prefixo+Nº |
| Management Group | `PlanApp-hub-mg001` | EntidadeSigla-Ambiente-Prefixo+Nº |
| Policy | `pla-prd-site-logs-app001-polic001` | Entidade-Ambiente-RecursoAssociado-Prefixo+Nº |
| **Resource group** | **`pla-we-prd-site-rg001`** | Entidade-DC-Ambiente-Projeto-Prefixo+Nº |
| Route table | `pla-we-hub-shared-vnet001-GatewaySubnet-rt001` | VNetAssociada-SubnetAssociada-Prefixo+Nº |
| Storage Account | `plawehublogssa001` | EntidadeDCAmbienteProjetoServiçoPrefixo+Nº *(sem `-`, global único)* |
| Subscrição | `PlanApp-hub-sub001` | EntidadeSigla-Ambiente-Prefixo+Nº |
| Virtual machine | `vm-prd-logs001` | Prefixo-Ambiente-Projeto+Nº *(hostname ≤ 16 chars)* |
| VM Network Interface (NIC) | `vm-prdlogs001-nic001` | VMAssociada-Prefixo+Nº |
| VM Public IP | `vm-prdlogs001-pip001` | VMAssociada-Prefixo+Nº |
| VM NSG | `vm-prdlogs001-nsg001` | VMAssociada-Prefixo+Nº |
| Virtual network | `pla-we-hub-shared-vnet001` | Entidade-DC-Ambiente-Departamento/Projeto-Prefixo+Nº |
| Virtual network Subnet | `prd-site-fe-snet001` | Ambiente-Projeto-Tier-Prefixo+Nº |
| NSG (subnet) | `prd-site-fe-snet001-nsg001` | SubnetAssociada-Prefixo+Nº |
| Virtual network Gateway | `pla-we-hub-shared-vnet001-vgw001` | VNetAssociada-Prefixo+Nº |
| VNet Gateway IP | `prd-we-shared-vnet001-vgw001-pip001` | VNetGWAssociada-Prefixo+Nº |
| Azure Compute Gallery | `plaweprdsharedcgall001` | EntidadeDCAmbienteProjeto+Prefixo+Nº *(sem `-`)* |
| VM image definition | `pla-we-prd-adse-imdef001` | Entidade-DC-Ambiente-Projeto-Prefixo+Nº |
| VM Snapshot | `vm-prd-logs001-OSDisk-snap001-xxxxxx` | VMAssociada-DiscoAssociado-Prefixo+Nº-Timestamp |
| VM SSH Key | `vm-prd-logs001-sshk001` | VMAssociada-Prefixo+Nº |
| Site-to-site connection | `pla-prd-we-shared-vnet001-pla-pt-prd-ff-lgw001-cn001` | VNetAssociada-LocalNetworkGW-Prefixo+Nº |

### Notas
- **(x)** — Obrigatoriedade de nome único a nível **global**
- **(xx)** — Único a nível global e **sem caracteres especiais** (ex: Storage Accounts)
- **(xxx)** — Hostname da VM deve ter até **16 caracteres**
- **(xxxx)** — **Não são permitidos `-`** no nome (ex: Azure Compute Gallery)

---

## 6. Exemplos de Valores dos Componentes

| Símbolo | Significado |
|---|---|
| `pla` | PLANAPP |
| `site` | Projeto "Website da PlanApp" |
| `logs` | Serviço de logs |
| `we` | West Europe |
| `ne` | North Europe |
| `pt` | Portugal (on-prem / localização) |

---

## 7. Responsabilidades

| Função | Responsabilidade |
|---|---|
| **Product Owner** | Revisão, aprovação e publicação da política |
| **Security Infrastructure Manager** | Garantir cumprimento da política |
| **Subscription Manager** | Definição e aprovação de alterações |
| **PLANAPP (equipa)** | Aplicação e adoção da política em todos os recursos |

---

## 8. Convencao Operacional para Grupos Entra ID (Power Platform)

> Esta secao operacionaliza a politica para grupos de seguranca Entra ID usados em ambientes Power Platform.
> O documento original define padrao para recursos Azure; para grupos, adota-se a mesma logica de componentes.

### Padrao recomendado

```
<entidade>-<ambiente>-<projeto>-sg-<funcao><numeracao>
```

### Componentes

| Componente | Regra | Exemplo |
|---|---|---|
| `entidade` | Sigla da organizacao (3 chars) | `pla` |
| `ambiente` | `dev`, `qua`, `prd`, `nprd`, `shared`, `hub` | `dev` |
| `projeto` | 2 a 8 chars em minusculas | `gps` |
| `sg` | Prefixo fixo para security group | `sg` |
| `funcao` | Funcao de acesso | `admin`, `maker`, `user` |
| `numeracao` | Sequencial de 3 digitos | `001` |

### Regras de escrita

- Usar minusculas.
- Separar componentes com `-`.
- Nao usar caracteres especiais proibidos (`*`, `#`, `&`, `+`, `:`, `<`, `>`, `?`, `_`).
- Manter unicidade por tenant para evitar colisao de nomes.

### Matriz minima para Power Platform

| Tipo de acesso | Nome sugerido (DEV) | Papel tipico |
|---|---|---|
| Administracao do ambiente | `pla-dev-gps-sg-admin001` | Environment Admin |
| Desenvolvimento da solucao | `pla-dev-gps-sg-maker001` | Environment Maker |
| Utilizacao controlada | `pla-dev-gps-sg-user001` | Basic User / acesso por app |

### Equivalentes por ambiente

| Ambiente | Admins | Makers | Users |
|---|---|---|---|
| DEV | `pla-dev-gps-sg-admin001` | `pla-dev-gps-sg-maker001` | `pla-dev-gps-sg-user001` |
| UAT (QUA) | `pla-qua-gps-sg-admin001` | `pla-qua-gps-sg-maker001` | `pla-qua-gps-sg-user001` |
| PROD | `pla-prd-gps-sg-admin001` | `pla-prd-gps-sg-maker001` | `pla-prd-gps-sg-user001` |

---

## 9. Políticas Relacionadas

- Política de Categorização e Organização dos Recursos para Azure subscriptions, management groups, resource groups e tags.

---

## 10. Referências

- [Define your naming convention — Cloud Adoption Framework | Microsoft Learn](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming)
- [Abbreviation examples for Azure resources — CAF | Microsoft Learn](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations)
- [Develop your naming and tagging strategy — CAF | Microsoft Learn](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/naming-and-tagging)
