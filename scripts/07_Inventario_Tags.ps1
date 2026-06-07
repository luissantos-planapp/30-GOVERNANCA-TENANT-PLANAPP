<#
=====================================================================
 PLANAPP - Inventario de Tags do Tenant Azure  (apenas leitura)
---------------------------------------------------------------------
 Percorre todas as subscricoes ativas e:
   1. Lista todas as CHAVES de tag usadas, com nº de recursos e valores distintos.
   2. Exporta o detalhe (uma linha por recurso/tag) para CSV.
   3. Calcula a cobertura das 4 tags obrigatorias (departamento, ambiente,
      projeto, centrocusto), por subscricao e global.

 Nao altera nada. Requer Az.Accounts e Az.Resources.
=====================================================================
#>

#Requires -Modules Az.Accounts, Az.Resources

# --- Configuracao ---------------------------------------------------
$tagsObrigatorias = @("departamento", "ambiente", "projeto", "centrocusto")
$incluirResourceGroups = $true   # tambem inventaria tags ao nivel dos Resource Groups

$stamp  = Get-Date -Format "yyyyMMdd-HHmmss"
$outDir = Join-Path (Get-Location) "planapp-tags-$stamp"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

# --- Estruturas de recolha -----------------------------------------
$detalhe   = New-Object System.Collections.Generic.List[object]
$resumo    = @{}   # chave -> { NumRecursos; Valores (HashSet) }
$cobertura = @{}   # subscricao -> { Total; <tagObrigatoria> -> contagem }
$totalRecursosGlobal = 0
$globalCobertura = @{}; foreach ($t in $tagsObrigatorias) { $globalCobertura[$t] = 0 }

function Add-TagRow {
    param($Sub, $Nome, $Tipo, $RG, $Tags)
    foreach ($k in $Tags.Keys) {
        $v = [string]$Tags[$k]
        $script:detalhe.Add([pscustomobject]@{
            Subscricao    = $Sub
            Recurso       = $Nome
            Tipo          = $Tipo
            GrupoRecursos = $RG
            TagChave      = $k
            TagValor      = $v
        })
        if (-not $script:resumo.ContainsKey($k)) {
            $script:resumo[$k] = [pscustomobject]@{
                NumRecursos = 0
                Valores     = (New-Object System.Collections.Generic.HashSet[string])
            }
        }
        $script:resumo[$k].NumRecursos++
        [void]$script:resumo[$k].Valores.Add($v)
    }
}

# --- Percurso por subscricao ---------------------------------------
$subs = Get-AzSubscription | Where-Object { $_.State -eq 'Enabled' }
Write-Host "Subscricoes ativas: $($subs.Count)" -ForegroundColor Yellow

foreach ($s in $subs) {
    Write-Host "`n== $($s.Name) ==" -ForegroundColor Cyan
    Set-AzContext -SubscriptionId $s.Id | Out-Null

    $cobertura[$s.Name] = @{ Total = 0 }
    foreach ($t in $tagsObrigatorias) { $cobertura[$s.Name][$t] = 0 }

    # Recursos
    $recursos = Get-AzResource
    foreach ($r in $recursos) {
        $totalRecursosGlobal++
        $cobertura[$s.Name].Total++
        $keysLower = @()
        if ($r.Tags) { $keysLower = @($r.Tags.Keys | ForEach-Object { $_.ToLower() }) }
        foreach ($t in $tagsObrigatorias) {
            if ($keysLower -contains $t) { $cobertura[$s.Name][$t]++; $globalCobertura[$t]++ }
        }
        if ($r.Tags -and $r.Tags.Count -gt 0) {
            Add-TagRow -Sub $s.Name -Nome $r.Name -Tipo $r.ResourceType -RG $r.ResourceGroupName -Tags $r.Tags
        }
    }

    # Resource Groups (opcional)
    if ($incluirResourceGroups) {
        foreach ($g in (Get-AzResourceGroup)) {
            if ($g.Tags -and $g.Tags.Count -gt 0) {
                Add-TagRow -Sub $s.Name -Nome $g.ResourceGroupName -Tipo "ResourceGroup" -RG $g.ResourceGroupName -Tags $g.Tags
            }
        }
    }

    Write-Host "   Recursos: $($recursos.Count)" -ForegroundColor DarkGray
}

# --- Resumo de chaves de tag ---------------------------------------
$resumoTab = $resumo.GetEnumerator() | ForEach-Object {
    [pscustomobject]@{
        TagChave            = $_.Key
        NumRecursos         = $_.Value.NumRecursos
        NumValoresDistintos = $_.Value.Valores.Count
        ValoresExemplo      = (($_.Value.Valores | Select-Object -First 15) -join " | ")
    }
} | Sort-Object NumRecursos -Descending

Write-Host "`n===== TAGS USADAS (resumo) =====" -ForegroundColor Yellow
$resumoTab | Format-Table TagChave, NumRecursos, NumValoresDistintos -AutoSize

# --- Cobertura das tags obrigatorias -------------------------------
$cobTab = foreach ($subNome in $cobertura.Keys) {
    $c = $cobertura[$subNome]; $tot = [math]::Max($c.Total, 1)
    [pscustomobject]@{
        Subscricao  = $subNome
        Recursos    = $c.Total
        departamento= "{0} ({1:P0})" -f $c.departamento, ($c.departamento / $tot)
        ambiente    = "{0} ({1:P0})" -f $c.ambiente,     ($c.ambiente / $tot)
        projeto     = "{0} ({1:P0})" -f $c.projeto,      ($c.projeto / $tot)
        centrocusto = "{0} ({1:P0})" -f $c.centrocusto,  ($c.centrocusto / $tot)
    }
}
Write-Host "`n===== COBERTURA DAS TAGS OBRIGATORIAS =====" -ForegroundColor Yellow
$cobTab | Format-Table -AutoSize

$totG = [math]::Max($totalRecursosGlobal, 1)
Write-Host "`nGlobal ($totalRecursosGlobal recursos):" -ForegroundColor Green
foreach ($t in $tagsObrigatorias) {
    "  {0,-13}: {1} ({2:P1})" -f $t, $globalCobertura[$t], ($globalCobertura[$t] / $totG) | Write-Host
}

# --- Exportacao -----------------------------------------------------
$resumoTab | Export-Csv (Join-Path $outDir "tags-resumo.csv")   -NoTypeInformation -Encoding UTF8
$detalhe   | Export-Csv (Join-Path $outDir "tags-detalhe.csv")  -NoTypeInformation -Encoding UTF8
$cobTab    | Export-Csv (Join-Path $outDir "tags-cobertura.csv") -NoTypeInformation -Encoding UTF8

Write-Host "`nChaves de tag distintas: $($resumo.Keys.Count)" -ForegroundColor Green
Write-Host "Ficheiros gerados em: $outDir" -ForegroundColor Green
Write-Host "  - tags-resumo.csv     (chaves + contagem + valores)" -ForegroundColor Green
Write-Host "  - tags-detalhe.csv    (uma linha por recurso/tag)" -ForegroundColor Green
Write-Host "  - tags-cobertura.csv  (cobertura das tags obrigatorias)" -ForegroundColor Green

<#
=====================================================================
 ALTERNATIVA RAPIDA (Azure Resource Graph) - requer modulo Az.ResourceGraph
 Devolve as chaves de tag distintas e nº de recursos, em segundos, todo o tenant:

 Search-AzGraph -First 1000 -Query @"
 resources
 | where isnotempty(tags)
 | project tags
 | mv-expand tags
 | extend tagKey = tostring(bag_keys(tags)[0])
 | extend tagValue = tostring(tags[tagKey])
 | summarize NumRecursos = count(), Valores = make_set(tagValue, 30) by tagKey
 | order by NumRecursos desc
 "@
=====================================================================
#>
