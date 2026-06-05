#Requires -Modules Az.Accounts
<#
.SYNOPSIS
    Gera relatório HTML de Governança AI Foundry para o tenant PLANAPP.
.DESCRIPTION
    Lê os CSV produzidos pelo script 04_inventario_ai_foundry.ps1 e gera
    um relatório HTML completo com sumário executivo, inventário, deployments
    de modelos e plano de remediação prioritizado.

    Saída: 04_ai_foundry_relatorio_YYYYMMDD_HHmm.html (no directório raiz do projeto)
.NOTES
    Autor  : Luís Santos / PLANAPP SITDIA
    Data   : 2026-05-26
    Versão : 1.0
#>

param(
    [string]$OutputPath    = (Split-Path $PSScriptRoot -Parent),
    [string]$CsvInventario = "",
    [string]$CsvDeployments = "",
    [string]$CsvRemediacao  = ""
)

$timestamp = Get-Date -Format "yyyyMMdd_HHmm"
$reportDate = Get-Date -Format "dd/MM/yyyy HH:mm"

# ─── Localizar CSVs mais recentes se não especificados ─────────────────────
if (-not $CsvInventario) {
    $CsvInventario  = Get-ChildItem -Path $OutputPath -Filter "04a_ai_foundry_inventario_*.csv" |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $CsvDeployments) {
    $CsvDeployments = Get-ChildItem -Path $OutputPath -Filter "04b_ai_foundry_deployments_*.csv" |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $CsvRemediacao) {
    $CsvRemediacao  = Get-ChildItem -Path $OutputPath -Filter "04c_ai_foundry_remediacao_*.csv" |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}

if (-not $CsvInventario -or -not (Test-Path $CsvInventario)) {
    Write-Error "Ficheiro de inventário não encontrado. Execute primeiro o script 04_inventario_ai_foundry.ps1"
    exit 1
}

Write-Host "`n[HTML] A gerar relatório..." -ForegroundColor Cyan
Write-Host ("  Inventário  : {0}" -f (Split-Path $CsvInventario -Leaf))
Write-Host ("  Deployments : {0}" -f (Split-Path $CsvDeployments -Leaf))
Write-Host ("  Remediação  : {0}" -f (Split-Path $CsvRemediacao -Leaf))

$inv = Import-Csv $CsvInventario
$dep = Import-Csv $CsvDeployments
$rem = Import-Csv $CsvRemediacao

# ─── Métricas para sumário ─────────────────────────────────────────────────
$totalRecursos    = $inv.Count
$totalDeployments = $dep.Count
$totalRemediacao  = $rem.Count

$conformeCount  = ($inv | Where-Object { $_.NomenclaturaCAF -like "*Conforme*" -and $_.NomenclaturaCAF -notlike "*Não*" }).Count
$nConformeCount = $totalRecursos - $conformeCount
$pctConformidade = if ($totalRecursos -gt 0) { [math]::Round($conformeCount / $totalRecursos * 100) } else { 0 }

$tagsCOnformes   = ($inv | Where-Object { $_.TagsConformes -like "*Conforme*" -and $_.TagsConformes -notlike "*Faltam*" }).Count
$redesExpostas   = ($inv | Where-Object { $_.RedePublica -like "*Exposta*" }).Count

$remAlta   = ($rem | Where-Object { $_.Prioridade -eq "Alta" }).Count
$remMedia  = ($rem | Where-Object { $_.Prioridade -eq "Média" }).Count
$remBaixa  = ($rem | Where-Object { $_.Prioridade -eq "Baixa" }).Count

# Distribuição por tipo
$nMLW   = ($inv | Where-Object { $_.Tipo -like "*MachineLearning*" }).Count
$nOAI   = ($inv | Where-Object { $_.Kind -eq "OpenAI" }).Count
$nAIS   = ($inv | Where-Object { $_.Kind -eq "AIServices" }).Count
$nDI    = ($inv | Where-Object { $_.Kind -eq "FormRecognizer" }).Count

# ─── Função para linha de tabela de inventário ─────────────────────────────
function Get-InvRow {
    param($r)
    $nc  = if ($r.NomenclaturaCAF -like "*Não conforme*") { '<span class="badge badge-danger">✘ Não conforme</span>' } else { '<span class="badge badge-ok">✔ Conforme</span>' }
    $tag = if ($r.TagsConformes -like "*Faltam*") { '<span class="badge badge-warning">✘ Faltam tags</span>' } else { '<span class="badge badge-ok">✔ OK</span>' }
    $net = if ($r.RedePublica -like "*Exposta*") { '<span class="badge badge-warning">⚠ Exposta</span>' } else { '<span class="badge badge-ok">✔ Restrita</span>' }
    $amb = if ($r.AmbienteCoerente -like "*CONFLITO*") { '<span class="badge badge-danger">⚠ Conflito</span>' } else { '<span class="badge badge-ok">✔ OK</span>' }
    $ownerRaw = if ($r.OwnerRG) { $r.OwnerRG } else { "—" }
    $ownerHtml = if ($ownerRaw -like "*SEM OWNER*" -or $ownerRaw -eq "—") {
        '<span class="badge badge-warning">⚠ Sem owner</span>'
    } else {
        '<small>' + [System.Web.HttpUtility]::HtmlEncode($ownerRaw) + '</small>'
    }
    $sub = $r.Subscription -replace "PlanApp-|PlanAPP-", ""
    $kindBadge = switch ($r.Kind) {
        "OpenAI"         { '<span class="kind-badge kind-oai">OpenAI</span>' }
        "AIServices"     { '<span class="kind-badge kind-ais">AI Services</span>' }
        "FormRecognizer" { '<span class="kind-badge kind-di">Doc Intel</span>' }
        "Hub"            { '<span class="kind-badge kind-hub">AI Hub</span>' }
        "Project"        { '<span class="kind-badge kind-proj">AI Project</span>' }
        "Default"        { '<span class="kind-badge kind-mlw">ML Workspace</span>' }
        default          { '<span class="kind-badge kind-mlw">' + $r.Kind + '</span>' }
    }
    $locShort = switch ($r.Localizacao) {
        "swedencentral" { "Sweden Central" }
        "westeurope"    { "West Europe" }
        "norwayeast"    { "Norway East" }
        "northeurope"   { "North Europe" }
        default         { $r.Localizacao }
    }
    $motivo = if ($r.MotivoNomenclatura) { '<br><small class="text-muted">' + [System.Web.HttpUtility]::HtmlEncode($r.MotivoNomenclatura) + '</small>' } else { "" }
    return "<tr>
        <td><strong>$($r.Nome)</strong>$motivo</td>
        <td>$kindBadge</td>
        <td><small>$sub</small></td>
        <td><small>$($r.ResourceGroup)</small></td>
        <td><small>$locShort</small></td>
        <td>$nc</td>
        <td>$tag</td>
        <td>$net</td>
        <td>$amb</td>
        <td>$ownerHtml</td>
    </tr>"
}

# ─── Função para linha de deployments ─────────────────────────────────────
function Get-DepRow {
    param($d)
    $cap = if ($d.SkuCapacidade -ne "N/A" -and $d.SkuCapacidade) { "$($d.SkuCapacidade) TPM" } else { "—" }
    return "<tr>
        <td><strong>$($d.DeploymentNome)</strong></td>
        <td>$($d.ModeloNome)</td>
        <td><small>$($d.ModeloVersao)</small></td>
        <td>$($d.ContaAI)</td>
        <td><small>$($d.Subscription -replace 'PlanApp-|PlanAPP-','')</small></td>
        <td>$($d.SkuNome)</td>
        <td class='text-right'><strong>$cap</strong></td>
    </tr>"
}

# ─── Função para linha de remediação ──────────────────────────────────────
function Get-RemRow {
    param($r)
    $pBadge = switch ($r.Prioridade) {
        "Alta"  { '<span class="badge badge-danger">🔴 Alta</span>' }
        "Média" { '<span class="badge badge-warning">🟡 Média</span>' }
        "Baixa" { '<span class="badge badge-ok">🟢 Baixa</span>' }
        default { $r.Prioridade }
    }
    $acao = [System.Web.HttpUtility]::HtmlEncode($r.AcaoRecomendada)
    $detalhe = [System.Web.HttpUtility]::HtmlEncode($r.Detalhe)
    return "<tr>
        <td>$pBadge</td>
        <td><strong>$($r.RecursoAtual)</strong><br><small class='text-muted'>$($r.ResourceGroup)</small></td>
        <td><small>$($r.Subscription -replace 'PlanApp-|PlanAPP-','')</small></td>
        <td><strong>$($r.Problema)</strong><br><small class='text-muted'>$detalhe</small></td>
        <td><small>$acao</small></td>
    </tr>"
}

# ─── Gerar linhas HTML ─────────────────────────────────────────────────────
$invRows = ($inv | ForEach-Object { Get-InvRow $_ }) -join "`n"
$depRows = ($dep | ForEach-Object { Get-DepRow $_ }) -join "`n"
$remRows = ($rem | ForEach-Object { Get-RemRow $_ }) -join "`n"

# ─── Dados para gráficos Chart.js ─────────────────────────────────────────
$conformeJson  = "[`"Conforme ($conformeCount)`", `"Não conforme ($nConformeCount)`"]"
$conformeData  = "[$conformeCount, $nConformeCount]"
$tiposJson     = "[`"ML Workspace ($nMLW)`", `"Azure OpenAI ($nOAI)`", `"AI Services ($nAIS)`", `"Doc Intelligence ($nDI)`"]"
$tiposData     = "[$nMLW, $nOAI, $nAIS, $nDI]"
$remJson       = "[`"Alta ($remAlta)`", `"Média ($remMedia)`", `"Baixa ($remBaixa)`"]"
$remData       = "[$remAlta, $remMedia, $remBaixa]"

# ─── Template HTML ─────────────────────────────────────────────────────────
$html = @"
<!DOCTYPE html>
<html lang="pt">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>PLANAPP — Governança AI Foundry — Relatório $reportDate</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
<style>
  :root {
    --planapp-blue: #003087;
    --planapp-light: #0066CC;
    --planapp-accent: #00A3E0;
    --danger: #D32F2F;
    --warning: #F57F17;
    --ok: #2E7D32;
    --neutral: #455A64;
    --bg: #F8FAFC;
    --card-bg: #FFFFFF;
    --border: #E0E7EF;
    --text: #1A2332;
    --text-muted: #6B7A8D;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: 'Segoe UI', system-ui, sans-serif;
    background: var(--bg);
    color: var(--text);
    font-size: 13px;
    line-height: 1.5;
  }
  /* ── Header ── */
  .header {
    background: linear-gradient(135deg, var(--planapp-blue) 0%, var(--planapp-light) 60%, var(--planapp-accent) 100%);
    color: white;
    padding: 28px 40px 22px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    box-shadow: 0 2px 12px rgba(0,48,135,0.3);
  }
  .header-left h1 { font-size: 22px; font-weight: 700; letter-spacing: 0.3px; }
  .header-left .subtitle { font-size: 13px; opacity: 0.88; margin-top: 4px; }
  .header-right { text-align: right; font-size: 12px; opacity: 0.85; }
  .header-right .report-date { font-size: 14px; font-weight: 600; margin-bottom: 2px; }
  /* ── Tabs ── */
  .tabs {
    background: white;
    border-bottom: 2px solid var(--border);
    padding: 0 40px;
    display: flex;
    gap: 4px;
    position: sticky; top: 0; z-index: 100;
    box-shadow: 0 1px 4px rgba(0,0,0,0.06);
  }
  .tab-btn {
    padding: 12px 20px;
    border: none; background: transparent;
    color: var(--text-muted);
    cursor: pointer;
    font-size: 13px; font-weight: 600;
    border-bottom: 3px solid transparent;
    margin-bottom: -2px;
    transition: all 0.15s;
  }
  .tab-btn:hover { color: var(--planapp-blue); }
  .tab-btn.active { color: var(--planapp-blue); border-bottom-color: var(--planapp-blue); }
  /* ── Content ── */
  .content { padding: 28px 40px; }
  .tab-panel { display: none; }
  .tab-panel.active { display: block; }
  /* ── Cards de métricas ── */
  .metrics-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(170px, 1fr));
    gap: 16px;
    margin-bottom: 28px;
  }
  .metric-card {
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 18px 20px;
    display: flex; flex-direction: column;
    box-shadow: 0 1px 4px rgba(0,0,0,0.05);
  }
  .metric-card .label { font-size: 11px; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 6px; }
  .metric-card .value { font-size: 30px; font-weight: 700; line-height: 1; }
  .metric-card .sub   { font-size: 12px; color: var(--text-muted); margin-top: 4px; }
  .metric-card.accent-blue .value { color: var(--planapp-blue); }
  .metric-card.accent-ok   .value { color: var(--ok); }
  .metric-card.accent-warn .value { color: var(--warning); }
  .metric-card.accent-danger .value { color: var(--danger); }
  /* ── Charts grid ── */
  .charts-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
    gap: 20px;
    margin-bottom: 28px;
  }
  .chart-card {
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 18px;
    box-shadow: 0 1px 4px rgba(0,0,0,0.05);
  }
  .chart-card h3 { font-size: 13px; font-weight: 700; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.4px; margin-bottom: 14px; }
  .chart-card canvas { max-height: 220px; }
  /* ── Alertas sumário ── */
  .alert-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 12px; margin-bottom: 24px; }
  .alert-box { border-radius: 8px; padding: 14px 16px; border-left: 4px solid; }
  .alert-box.danger { background: #FFF5F5; border-color: var(--danger); }
  .alert-box.warning { background: #FFFDE7; border-color: var(--warning); }
  .alert-box.ok { background: #F1F8F1; border-color: var(--ok); }
  .alert-box .alert-title { font-weight: 700; font-size: 13px; margin-bottom: 4px; }
  .alert-box.danger .alert-title { color: var(--danger); }
  .alert-box.warning .alert-title { color: var(--warning); }
  .alert-box.ok .alert-title { color: var(--ok); }
  /* ── Tabelas ── */
  .section-header {
    display: flex; align-items: center; justify-content: space-between;
    margin-bottom: 12px; margin-top: 8px;
  }
  .section-header h2 { font-size: 16px; font-weight: 700; color: var(--planapp-blue); }
  .section-header .count-badge { background: var(--planapp-blue); color: white; font-size: 11px; font-weight: 700; padding: 2px 10px; border-radius: 12px; }
  .table-wrapper { overflow-x: auto; border-radius: 10px; border: 1px solid var(--border); box-shadow: 0 1px 4px rgba(0,0,0,0.05); margin-bottom: 28px; }
  table { width: 100%; border-collapse: collapse; background: var(--card-bg); }
  thead th {
    background: var(--planapp-blue);
    color: white;
    padding: 10px 12px;
    text-align: left;
    font-size: 11px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    white-space: nowrap;
  }
  tbody tr:nth-child(even) { background: #F8FAFC; }
  tbody tr:hover { background: #EEF4FF; }
  tbody td { padding: 9px 12px; border-bottom: 1px solid var(--border); vertical-align: top; }
  .text-right { text-align: right; }
  .text-muted { color: var(--text-muted); }
  /* ── Badges ── */
  .badge { display: inline-block; padding: 2px 8px; border-radius: 10px; font-size: 11px; font-weight: 700; white-space: nowrap; }
  .badge-ok      { background: #E8F5E9; color: #2E7D32; }
  .badge-warning { background: #FFF8E1; color: #E65100; }
  .badge-danger  { background: #FFEBEE; color: #C62828; }
  .kind-badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 11px; font-weight: 600; }
  .kind-oai  { background: #E3F2FD; color: #1565C0; }
  .kind-ais  { background: #E8EAF6; color: #283593; }
  .kind-di   { background: #FFF8E1; color: #6D4C41; }
  .kind-hub  { background: #E0F7FA; color: #006064; }
  .kind-proj { background: #E8F5E9; color: #1B5E20; }
  .kind-mlw  { background: #F3E5F5; color: #6A1B9A; }
  /* ── Filtro de tabela ── */
  .table-filter { margin-bottom: 10px; }
  .table-filter input {
    padding: 7px 12px; border: 1px solid var(--border); border-radius: 6px;
    font-size: 13px; width: 280px; outline: none;
  }
  .table-filter input:focus { border-color: var(--planapp-accent); }
  /* ── Footer ── */
  .footer {
    background: var(--planapp-blue); color: rgba(255,255,255,0.75);
    text-align: center; padding: 14px 40px;
    font-size: 11px; margin-top: 40px;
  }
  /* ── Print ── */
  @media print {
    .tabs, .table-filter { display: none !important; }
    .tab-panel { display: block !important; page-break-before: auto; }
    .header { print-color-adjust: exact; -webkit-print-color-adjust: exact; }
    table thead { print-color-adjust: exact; -webkit-print-color-adjust: exact; }
    .metric-card, .chart-card, .alert-box { break-inside: avoid; }
  }
</style>
</head>
<body>

<!-- ── Header ────────────────────────────────────────────── -->
<div class="header">
  <div class="header-left">
    <div class="subtitle">PLANAPP | SITDIA — Projeto 20260320-001</div>
    <h1>Governança AI Foundry — Análise CAF</h1>
    <div class="subtitle">Inventário de Recursos AI &amp; Relatório de Conformidade</div>
  </div>
  <div class="header-right">
    <div class="report-date">$reportDate</div>
    <div>Tenant: cdb8a0e2-181d-4de3-896e-6e550ef1eaff</div>
    <div>Luis.Santos@planapp.gov.pt</div>
  </div>
</div>

<!-- ── Tabs ──────────────────────────────────────────────── -->
<div class="tabs">
  <button class="tab-btn active" onclick="showTab('sumario', this)">📊 Sumário Executivo</button>
  <button class="tab-btn" onclick="showTab('inventario', this)">📋 Inventário ($totalRecursos recursos)</button>
  <button class="tab-btn" onclick="showTab('deployments', this)">🤖 Deployments de Modelos ($totalDeployments)</button>
  <button class="tab-btn" onclick="showTab('remediacao', this)">🔧 Plano de Remediação ($totalRemediacao itens)</button>
</div>

<!-- ══════════════════════════════════════════════════════════ -->
<!-- TAB 1 — SUMÁRIO EXECUTIVO                                  -->
<!-- ══════════════════════════════════════════════════════════ -->
<div class="content">
<div id="tab-sumario" class="tab-panel active">

  <!-- Métricas principais -->
  <div class="metrics-grid">
    <div class="metric-card accent-blue">
      <div class="label">Recursos AI Inventariados</div>
      <div class="value">$totalRecursos</div>
      <div class="sub">Em todas as subscriptions</div>
    </div>
    <div class="metric-card accent-blue">
      <div class="label">Deployments de Modelos</div>
      <div class="value">$totalDeployments</div>
      <div class="sub">OpenAI + AI Services</div>
    </div>
    <div class="metric-card $(if ($pctConformidade -lt 50) {'accent-danger'} elseif ($pctConformidade -lt 80) {'accent-warn'} else {'accent-ok'})">
      <div class="label">Conformidade Nomenclatura CAF</div>
      <div class="value">$pctConformidade%</div>
      <div class="sub">$conformeCount de $totalRecursos conformes</div>
    </div>
    <div class="metric-card $(if ($tagsCOnformes -eq 0) {'accent-danger'} elseif ($tagsCOnformes -lt $totalRecursos) {'accent-warn'} else {'accent-ok'})">
      <div class="label">Tags Obrigatórias Completas</div>
      <div class="value">$tagsCOnformes</div>
      <div class="sub">de $totalRecursos recursos</div>
    </div>
    <div class="metric-card $(if ($redesExpostas -gt 0) {'accent-warn'} else {'accent-ok'})">
      <div class="label">Redes Públicas Expostas</div>
      <div class="value">$redesExpostas</div>
      <div class="sub">de $totalRecursos recursos</div>
    </div>
    <div class="metric-card $(if ($remAlta -gt 0) {'accent-danger'} else {'accent-ok'})">
      <div class="label">Não-conformidades Alta</div>
      <div class="value">$remAlta</div>
      <div class="sub">($remMedia Média + $remBaixa Baixa)</div>
    </div>
  </div>

  <!-- Alertas principais -->
  <div class="alert-grid">
    <div class="alert-box danger">
      <div class="alert-title">🔴 5 Recursos com Nome Auto-Gerado</div>
      Recursos criados via AI Foundry Portal com nomes tipo <code>pessoa-hash-região</code>. Não podem ser renomeados — requerem <strong>recriação manual</strong> com nome conforme CAF.
    </div>
    <div class="alert-box danger">
      <div class="alert-title">🔴 Conflito Ambiente/Subscription</div>
      <strong>gpt-utail-nprd-001</strong> e <strong>ml-dev-001</strong> estão na subscription <em>prd</em> mas o nome indica ambiente <em>nprd/dev</em>. Risco de operação em ambiente errado.
    </div>
    <div class="alert-box warning">
      <div class="alert-title">🟡 $redesExpostas Recursos com Rede Pública Activa</div>
      Todos os recursos AI têm <code>publicNetworkAccess=Enabled</code>. Em PRD, deve ser configurado Private Endpoint e acesso público desactivado.
    </div>
    <div class="alert-box warning">
      <div class="alert-title">🟡 Tags Obrigatórias Ausentes</div>
      $(($totalRecursos - $tagsCOnformes)) recursos sem todas as tags obrigatórias (<code>departamento</code>, <code>ambiente</code>, <code>projeto</code>, <code>centrocusto</code>). Impede rastreabilidade de custos.
    </div>
  </div>

  <!-- Gráficos -->
  <div class="charts-grid">
    <div class="chart-card">
      <h3>Conformidade Nomenclatura CAF</h3>
      <canvas id="chartConform"></canvas>
    </div>
    <div class="chart-card">
      <h3>Distribuição por Tipo de Recurso</h3>
      <canvas id="chartTipos"></canvas>
    </div>
    <div class="chart-card">
      <h3>Não-conformidades por Prioridade</h3>
      <canvas id="chartRem"></canvas>
    </div>
  </div>

  <!-- Top 5 recursos com mais deployments -->
  <div class="section-header">
    <h2>Top Recursos por Deployments de Modelos</h2>
  </div>
  <div class="table-wrapper">
    <table>
      <thead><tr><th>Recurso AI</th><th>Tipo</th><th>Subscription</th><th>Localização</th><th style="text-align:right">Nº Deployments</th></tr></thead>
      <tbody>
        $(
          $dep | Group-Object ContaAI | Sort-Object Count -Descending | ForEach-Object {
            $conta = $_.Name
            $match = $inv | Where-Object { $_.Nome -eq $conta } | Select-Object -First 1
            $kind = if ($match) { $match.Kind } else { "—" }
            $subShort = if ($match) { $match.Subscription -replace "PlanApp-|PlanAPP-","" } else { "—" }
            $loc = if ($match) {
                switch ($match.Localizacao) {
                    "swedencentral" { "Sweden Central" }
                    "westeurope"    { "West Europe" }
                    "norwayeast"    { "Norway East" }
                    default         { $match.Localizacao }
                }
            } else { "—" }
            "<tr><td><strong>$conta</strong></td><td>$kind</td><td><small>$subShort</small></td><td><small>$loc</small></td><td style='text-align:right'><strong>$($_.Count)</strong></td></tr>"
          } | Select-Object -First 10
        )
      </tbody>
    </table>
  </div>

</div><!-- /tab-sumario -->

<!-- ══════════════════════════════════════════════════════════ -->
<!-- TAB 2 — INVENTÁRIO                                         -->
<!-- ══════════════════════════════════════════════════════════ -->
<div id="tab-inventario" class="tab-panel">
  <div class="section-header">
    <h2>Inventário Completo de Recursos AI Foundry</h2>
    <span class="count-badge">$totalRecursos recursos</span>
  </div>
  <div class="table-filter">
    <input type="text" id="filterInv" placeholder="🔍 Filtrar por nome, subscription, RG..." onkeyup="filterTable('tableInv','filterInv')">
  </div>
  <div class="table-wrapper">
    <table id="tableInv">
      <thead><tr>
        <th>Nome do Recurso</th>
        <th>Tipo</th>
        <th>Subscription</th>
        <th>Resource Group</th>
        <th>Localização</th>
        <th>Nomenclatura CAF</th>
        <th>Tags</th>
        <th>Rede</th>
        <th>Ambiente</th>
        <th>Owner (RG)</th>
      </tr></thead>
      <tbody>
        $invRows
      </tbody>
    </table>
  </div>
</div><!-- /tab-inventario -->

<!-- ══════════════════════════════════════════════════════════ -->
<!-- TAB 3 — DEPLOYMENTS                                        -->
<!-- ══════════════════════════════════════════════════════════ -->
<div id="tab-deployments" class="tab-panel">
  <div class="section-header">
    <h2>Deployments de Modelos de IA</h2>
    <span class="count-badge">$totalDeployments deployments</span>
  </div>
  <div class="table-filter">
    <input type="text" id="filterDep" placeholder="🔍 Filtrar por modelo, conta, subscription..." onkeyup="filterTable('tableDep','filterDep')">
  </div>
  <div class="table-wrapper">
    <table id="tableDep">
      <thead><tr>
        <th>Deployment</th>
        <th>Modelo</th>
        <th>Versão</th>
        <th>Conta AI</th>
        <th>Subscription</th>
        <th>SKU</th>
        <th style="text-align:right">Capacidade</th>
      </tr></thead>
      <tbody>
        $depRows
      </tbody>
    </table>
  </div>
</div><!-- /tab-deployments -->

<!-- ══════════════════════════════════════════════════════════ -->
<!-- TAB 4 — REMEDIAÇÃO                                         -->
<!-- ══════════════════════════════════════════════════════════ -->
<div id="tab-remediacao" class="tab-panel">
  <div class="section-header">
    <h2>Plano de Remediação de Não-conformidades</h2>
    <span class="count-badge">$totalRemediacao itens</span>
  </div>
  <p style="margin-bottom:14px;color:var(--text-muted);font-size:12px;">
    Ordenado por prioridade. Items <span class="badge badge-danger">Alta</span> requerem ação imediata.
    Items <span class="badge badge-warning">Média</span> devem ser resolvidos no próximo ciclo de governança.
  </p>
  <div class="table-filter">
    <input type="text" id="filterRem" placeholder="🔍 Filtrar por recurso, problema..." onkeyup="filterTable('tableRem','filterRem')">
  </div>
  <div class="table-wrapper">
    <table id="tableRem">
      <thead><tr>
        <th>Prioridade</th>
        <th>Recurso</th>
        <th>Subscription</th>
        <th>Problema</th>
        <th>Ação Recomendada</th>
      </tr></thead>
      <tbody>
        $remRows
      </tbody>
    </table>
  </div>
</div><!-- /tab-remediacao -->

</div><!-- /content -->

<!-- ── Footer ────────────────────────────────────────────── -->
<div class="footer">
  PLANAPP — Plataforma de Ação para o Ambiente e Ordenamento do Território &nbsp;|&nbsp;
  Relatório gerado em $reportDate &nbsp;|&nbsp;
  Luís Santos / SITDIA &nbsp;|&nbsp;
  Projeto 20260320-001 — Governança do Tenant Azure
</div>

<!-- ── Scripts ────────────────────────────────────────────── -->
<script>
function showTab(id, btn) {
  document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
  document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
  document.getElementById('tab-' + id).classList.add('active');
  btn.classList.add('active');
}

function filterTable(tableId, inputId) {
  const filter = document.getElementById(inputId).value.toUpperCase();
  const rows = document.getElementById(tableId).getElementsByTagName('tr');
  for (let i = 1; i < rows.length; i++) {
    const txt = rows[i].textContent.toUpperCase();
    rows[i].style.display = txt.includes(filter) ? '' : 'none';
  }
}

// Charts
const palette = ['#003087','#0066CC','#00A3E0','#00C4B4','#7B61FF','#FF6B6B','#FFC107','#4CAF50'];
const paletteRem = ['#D32F2F','#F57F17','#2E7D32'];

new Chart(document.getElementById('chartConform'), {
  type: 'doughnut',
  data: {
    labels: $conformeJson,
    datasets: [{ data: $conformeData, backgroundColor: ['#2E7D32','#D32F2F'], borderWidth: 2 }]
  },
  options: { responsive: true, plugins: { legend: { position: 'bottom', labels: { font: { size: 12 } } } } }
});

new Chart(document.getElementById('chartTipos'), {
  type: 'doughnut',
  data: {
    labels: $tiposJson,
    datasets: [{ data: $tiposData, backgroundColor: palette.slice(0,4), borderWidth: 2 }]
  },
  options: { responsive: true, plugins: { legend: { position: 'bottom', labels: { font: { size: 12 } } } } }
});

new Chart(document.getElementById('chartRem'), {
  type: 'bar',
  data: {
    labels: ['Alta','Média','Baixa'],
    datasets: [{ label: 'Não-conformidades', data: $remData, backgroundColor: paletteRem, borderRadius: 4 }]
  },
  options: {
    responsive: true,
    plugins: { legend: { display: false } },
    scales: { y: { beginAtZero: true, ticks: { stepSize: 1 } } }
  }
});
</script>
</body>
</html>
"@

# ─── Guardar ficheiro ───────────────────────────────────────────────────────
$htmlPath = Join-Path $OutputPath "04_ai_foundry_relatorio_$timestamp.html"
$html | Out-File -FilePath $htmlPath -Encoding UTF8

Write-Host "`n  ✔ Relatório HTML gerado:" -ForegroundColor Green
Write-Host ("    {0}" -f $htmlPath) -ForegroundColor Cyan

# Abrir no browser
$open = Read-Host "`n  Abrir no browser? [S/n]"
if ($open -ne "n" -and $open -ne "N") {
    Start-Process $htmlPath
}

Write-Host "`n  Dica: Para exportar como PDF, use Ctrl+P no browser → Guardar como PDF`n" -ForegroundColor DarkYellow
