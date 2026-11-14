# sync.ps1 - sincroniza crates/update do local-libs para os apps da suite.
# Uso:
#   powershell -File scripts/sync.ps1 -Mode verify              # confere fonte + 10 apps (nao altera nada)
#   powershell -File scripts/sync.ps1 -Mode push [-Apps a,b]    # copia a fonte para os apps e verifica
# Requer: PowerShell 5.1+, git nos repos. Rodar na raiz do repo local-libs.
param(
  [ValidateSet('verify', 'push')] [string]$Mode = 'verify',
  # Default: todos os apps que tiverem libs/craft-libs/crates/update
  [string[]]$Apps = @()
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'crates\update'
$appsRoot = 'C:\Dev\underworld-apps'   # no Arch: ~/Dev/dev-arch/underworld-apps

if ($Apps.Count -eq 0) {
  $Apps = Get-ChildItem $appsRoot -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName 'libs\craft-libs\crates\update') } |
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
Write-Host "fonte: $srcCount arquivos"

# 1. manifest no repo (fonte de verdade declarada)
$manifestPath = Join-Path $root 'HASHES.update'
if ($Mode -eq 'push') {
  [System.IO.File]::WriteAllText($manifestPath, $srcHash, (New-Object System.Text.UTF8Encoding($false)))
} elseif (Test-Path $manifestPath) {
  if ((Get-DirHash $src) -ne [System.IO.File]::ReadAllText($manifestPath)) {
    throw 'DRIFT: crates/update diverge do HASHES.update commitado - rode -Mode push para regenerar (e explique no commit por que a fonte mudou).'
  }
}

# 2. apps
$fail = 0
foreach ($app in $Apps) {
  $dst = Join-Path $appsRoot "$app\libs\craft-libs\crates\update"
  if (-not (Test-Path $dst)) { Write-Warning "$app : destino ausente ($dst)"; $fail++; continue }
  if ($Mode -eq 'push' -and (Get-DirHash $dst) -ne $srcHash) {
    robocopy $src $dst /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
  }
  $ok = (Get-DirHash $dst) -eq $srcHash
  Write-Host ("{0} : {1}" -f $app, $(if ($ok) { 'OK' } else { 'DIVERGE' }))
  if (-not $ok) { $fail++ }
}
if ($fail -gt 0) { throw "$fail app(s) divergente(s) da fonte." }
Write-Host 'Todos os apps conferem com a fonte.'
