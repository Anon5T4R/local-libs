# sync.ps1 - sincroniza uma crate do local-libs para os apps da suite.
# Uso:
#   powershell -File scripts/sync.ps1 -Mode verify                       # confere a fonte + os apps (nao altera nada)
#   powershell -File scripts/sync.ps1 -Mode push [-Apps a,b]             # copia a fonte para os apps e verifica
#   powershell -File scripts/sync.ps1 -Crate ai-ui -Mode push [-Apps x]  # outra crate (default: update)
#   powershell -File scripts/sync.ps1 -Crate x -Mode push -Dirs C:\Dev\worktree-claude\local-sheets-tema
#     # pastas de app explicitas (worktrees); em push cria a copia se o app ainda nao tem a crate
#   powershell -File scripts/sync.ps1 -Asset craft-fonts -Mode push     # asset: assets/<Asset> -> <app>/assets/<Asset>
# Requer: PowerShell 5.1+, git nos repos. Rodar na raiz do repo local-libs.
param(
  [ValidateSet('verify', 'push')] [string]$Mode = 'verify',
  # A crate da fonte (`crates/<Crate>`) e o manifesto (`HASHES.<Crate>`).
  [string]$Crate = 'update',
  # Um asset (`assets/<Asset>`, manifesto `HASHES.asset-<Asset>`) no lugar de uma crate; vai para
  # `<app>/assets/<Asset>`.
  [string]$Asset = '',
  # Default: todos os apps que tiverem libs/craft-libs/crates/<Crate>
  [string[]]$Apps = @(),
  # Pastas de app (caminho completo) no lugar de -Apps; para worktrees e crate nova.
  [string[]]$Dirs = @()
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ($Asset) {
  $src = Join-Path $root "assets\$Asset"
  $appRel = "assets\$Asset"
  $manifestName = "HASHES.asset-$Asset"
  $Crate = "asset $Asset"
} else {
  $src = Join-Path $root "crates\$Crate"
  $appRel = "libs\craft-libs\crates\$Crate"
  $manifestName = "HASHES.$Crate"
}
$appsRoot = 'C:\Dev\underworld-apps'   # no Arch: ~/Dev/dev-arch/underworld-apps

if (-not (Test-Path $src)) { throw "fonte ausente: $src" }

# `powershell -File` entrega "a,b" como um texto so: separa aqui.
$Apps = @($Apps | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$Dirs = @($Dirs | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
if ($Dirs.Count -gt 0) {
  $Apps = $Dirs
} elseif ($Apps.Count -eq 0) {
  $Apps = Get-ChildItem $appsRoot -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName $appRel) } |
    ForEach-Object { $_.Name }
}

function Get-DirHash([string]$dir) {
  $files = Get-ChildItem $dir -Recurse -File | Sort-Object FullName
  $lines = foreach ($f in $files) {
    $rel = $f.FullName.Substring($dir.Length + 1).Replace('\', '/')
    $h = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
    "$rel $($f.Length) $h"
  }
  ($lines -join "`n")
}

$srcHash = Get-DirHash $src
$srcCount = (Get-ChildItem $src -Recurse -File).Count
Write-Host "fonte ($Crate): $srcCount arquivos"

# 1. manifest no repo (fonte de verdade declarada)
$manifestPath = Join-Path $root $manifestName
if ($Mode -eq 'push') {
  [System.IO.File]::WriteAllText($manifestPath, $srcHash, (New-Object System.Text.UTF8Encoding($false)))
} elseif (Test-Path $manifestPath) {
  if ((Get-DirHash $src) -ne [System.IO.File]::ReadAllText($manifestPath)) {
    throw "DRIFT: $Crate diverge do $manifestName commitado - rode -Mode push para regenerar (e explique no commit por que a fonte mudou)."
  }
}

# 2. apps
$fail = 0
foreach ($app in $Apps) {
  $appDir = if ($Dirs.Count -gt 0) { $app } else { Join-Path $appsRoot $app }
  $dst = Join-Path $appDir $appRel
  if ($Mode -eq 'push' -and $Dirs.Count -gt 0 -and -not (Test-Path $dst)) {
    New-Item -ItemType Directory -Force $dst | Out-Null
  }
  if (-not (Test-Path $dst)) { Write-Warning "$app : destino ausente ($dst)"; $fail++; continue }
  if ($Mode -eq 'push' -and (Get-DirHash $dst) -ne $srcHash) {
    robocopy $src $dst /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
    # robocopy: 0-7 = sucesso (com ou sem copia), 8+ = falha.
    if ($LASTEXITCODE -ge 8) { throw "$app : robocopy falhou (codigo $LASTEXITCODE)" }
    # O robocopy preserva a data da fonte. Se ela for mais velha que o ultimo build do app, o cargo
    # acha a crate "fresh" e roda o codigo antigo. Data de agora em tudo que foi espelhado.
    $now = Get-Date
    Get-ChildItem $dst -Recurse -File | ForEach-Object { $_.LastWriteTime = $now }
  }
  $ok = (Get-DirHash $dst) -eq $srcHash
  Write-Host ("{0} : {1}" -f $app, $(if ($ok) { 'OK' } else { 'DIVERGE' }))
  if (-not $ok) { $fail++ }
}
if ($fail -gt 0) { throw "$fail app(s) divergente(s) da fonte." }
Write-Host "Todos os apps conferem com a fonte ($Crate)."
