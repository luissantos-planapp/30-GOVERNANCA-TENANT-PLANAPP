# Plano de Implementação para Adequação à Política de Nomenclaturas v2.0

## 1. Objetivo
Executar a adequação progressiva dos recursos atuais Azure do tenant PLANAPP à Política de Nomenclaturas v2.0, com mínimo impacto operacional e controlo formal de exceções.

## 2. Baseline do Levantamento (2026-06-05)
- Recursos inventariados: 548
- Resource Groups identificados: 83
- Subscrições com recursos: 7 (de 9 subscrições visíveis)
- Conformidade de tags obrigatórias (departamento, ambiente, projeto, centrocusto): 0/548 totalmente conformes
- Recursos com naming fora do padrão base permitido (^ [a-z0-9-]+ $): 198 (36,13%)

### 2.1 Distribuição por subscrição (recursos)
- PlanApp-prd-sub001: 246
- PlanApp-nprd-sub001: 194
- PlanApp-hub-sub001: 99
- PlanAPP-AZURE-TEMP: 4
- PlanAPP-fabric-suboo1: 3
- PlanApp-365-backup-001: 1
- Microsoft Azure Enterprise (1beacf...): 1

### 2.2 Lacunas de tags obrigatórias (volume)
- departamento em falta: 541
- ambiente em falta: 546
- projeto em falta: 546
- centrocusto em falta: 548

## 3. Princípios de Execução
- Segurança e continuidade primeiro: evitar alterações destrutivas sem plano de cutover e rollback.
- Prioridade por risco e impacto: começar por produção e workloads críticos.
- Corrigir rápido o que é de baixo risco (tags), planear por ondas o que exige recriação/migração.
- Exceções explícitas e temporárias: tudo o que não puder ser corrigido já deve ser registado com prazo.

## 4. Estratégia de Implementação por Fases

## Fase 0 - Mobilização e Governação (Semana 1)
Objetivo: criar estrutura de decisão e execução.

Entregáveis:
- RACI formal (GSI, owners de subscrição, owners de RG, equipas aplicacionais).
- Catálogo de exceções (template e fluxo de aprovação).
- Definição de ondas de migração por subscrição e criticidade.

Ações:
- Nomear owner por subscrição e por resource group.
- Congelar criação de novos recursos fora do processo controlado.
- Definir janela de mudança para produção.

Critério de saída:
- Governança aprovada e calendário publicado.

## Fase 1 - Remediação de Tags (Semanas 2-4)
Objetivo: atingir cobertura de tags obrigatórias em todo o estate.

Entregáveis:
- Plano de mapeamento de valores válidos por tag.
- Script de remediação em lote por subscrição/RG.
- Dashboard de cobertura por tag.

Ações:
- Definir dicionário de valores permitidos (ex.: ambiente = prd/nprd/dev/qua/shared/hub).
- Aplicar tags obrigatórias em massa nos recursos sem dependências críticas.
- Tratar recursos herdados/geridos por plataforma com regra de exceção, quando aplicável.

KPIs:
- >=95% de recursos com 4 tags obrigatórias até final da Fase 1.
- 100% em produção até final da semana 3.

Critério de saída:
- Cobertura de tags estabilizada e monitorização ativa.

## Fase 2 - Normalização de Naming (Semanas 3-8)
Objetivo: reduzir não conformidades de naming com prioridade por risco.

Entregáveis:
- Matriz de decisão por tipo de recurso: renomeável, recriável, exceção.
- Backlog priorizado por subscrição e tipo.
- Planos de cutover para recursos sem rename suportado.

Ações:
- Classificar cada recurso não conforme em:
  - Classe A: renomeação simples e sem downtime relevante.
  - Classe B: recriação/migração com impacto controlado.
  - Classe C: não elegível no curto prazo (exceção temporária).
- Executar por ondas:
  - Onda 1: nprd/dev/hub não crítico.
  - Onda 2: shared e serviços transversais.
  - Onda 3: produção crítica com janela aprovada.

KPIs:
- Reduzir naming inválido de 198 para <=80 até semana 6.
- Reduzir naming inválido para <=20 até semana 8.

Critério de saída:
- Naming não conforme residual apenas com exceção aprovada.

## Fase 3 - Enforcement Preventivo (Semanas 5-9)
Objetivo: impedir regressão de conformidade.

Entregáveis:
- Iniciativa Azure Policy para naming e tags.
- Estratégia deny/audit por ambiente.
- Runbook operacional de correção automática.

Ações:
- Publicar policies em modo audit em todas as subscrições.
- Ajustar falso-positivos e casos especiais.
- Evoluir para deny progressivo (dev/nprd primeiro, prd depois).

KPIs:
- 0 novos recursos sem tags obrigatórias após go-live de deny.
- <=2% de recursos novos fora de naming por mês (com tendência para 0%).

Critério de saída:
- Controlo preventivo ativo e aceite pelas equipas.

## Fase 4 - Operação Contínua e Auditoria (A partir da Semana 10)
Objetivo: institucionalizar conformidade contínua.

Entregáveis:
- Relatório mensal de conformidade por subscrição.
- Revisão trimestral de exceções e expiração de prazos.
- Gate de CI/CD para validação de naming/tags antes de deploy.

Ações:
- Recolha mensal automatizada do inventário.
- Alertas para regressões por domínio e owner.
- Revisão anual da política v2 conforme evolução tecnológica.

KPIs:
- >=98% conformidade global sustentada.
- 100% exceções com validade, owner e plano de remediação.

## 5. Priorização Inicial Recomendada
1. Produção (PlanApp-prd-sub001): foco imediato em tags e workloads críticos.
2. Não-produção (PlanApp-nprd-sub001): remediação rápida em volume.
3. Hub (PlanApp-hub-sub001): padronização de rede e serviços base.
4. Restantes subscrições de baixa volumetria: fecho rápido.

## 6. Backlog Técnico Inicial (Primeiros 15 dias)
- Task 1: consolidar inventário detalhado por RG e tipo de recurso.
- Task 2: aprovar dicionário de valores para tags obrigatórias.
- Task 3: criar scripts de tagging em lote com modo dry-run.
- Task 4: gerar lista de recursos não renomeáveis e estratégia de migração.
- Task 5: criar políticas Azure em modo audit para naming e tags.
- Task 6: definir dashboard executivo e operacional de conformidade.

## 7. Riscos e Mitigações
- Risco: recurso não suporta rename.
  - Mitigação: plano de recriação com cutover e rollback.
- Risco: impacto em produção por alteração de nomes globais.
  - Mitigação: janela de mudança, testes prévios e comunicação.
- Risco: falta de ownership por recurso.
  - Mitigação: owner obrigatório por RG e escalonamento GSI.
- Risco: regressão após correções.
  - Mitigação: Azure Policy deny progressivo + gate CI/CD.

## 8. Critérios de Sucesso do Programa
- Tags obrigatórias: >=98% em 60 dias, 100% em produção.
- Naming conforme: >=90% em 90 dias.
- Exceções: 100% registadas, justificadas e com prazo.
- Sustentação: sem crescimento de não conformidades por 3 ciclos mensais.

## 9. Próximos Passos Imediatos
1. Validar este plano com a Equipa GSI e owners de subscrição.
2. Aprovar dicionário oficial de tags e valores.
3. Iniciar Fase 1 na subscrição PlanApp-prd-sub001 com piloto controlado.
4. Publicar dashboard de baseline e meta por semana.
