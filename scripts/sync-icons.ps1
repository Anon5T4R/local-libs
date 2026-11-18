# sync-icons.ps1 - confere/puxa os icones 128 px do craft-update a partir dos apps.
# Uso:
#   powershell -File scripts/sync-icons.ps1                    # = -Mode check (nao altera nada; exit 1 se divergir)
#   powershell -File scripts/sync-icons.ps1 -Mode pull         # copia a fonte de cada app para crates/update/assets/icons
#   powershell -File scripts/sync-icons.ps1 -AppsRoot ~/Dev/dev-arch/underworld-apps
# NAO copia para dentro dos apps: depois do pull, rode `sync.ps1 -Mode push` (replica o crate).
# Requer: PowerShell 5.1+. Rodar na raiz do repo local-libs.
param(
  [ValidateSet('check', 'pull')] [string]$Mode = 'check',
  [string]$AppsRoot = 'C:\Dev\underworld-apps'   # no Arch: ~/Dev/dev-arch/underworld-apps
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $root 'crates\update\assets\icons'

# Tabela unica: PNG no crate -> app -> fonte (128 px) relativa a raiz do app.
$icons = @(
  @{ Png = 'localoffice.png';   App = 'local-office';    Src = 'assets\app-icon\hicolor\128x128\apps\com.local.localoffice.png' },
  @{ Png = 'localpdf.png';      App = 'local-pdf';       Src = 'assets\app-icon\hicolor\128x128\apps\com.local.localpdf.png' },
  @{ Png = 'localsheets.png';   App = 'local-sheets';    Src = 'assets\app-icon\hicolor\128x128\apps\com.local.localsheets.png' },
  @{ Png = 'localslides.png';   App = 'local-slides';    Src = 'assets\app-icon\hicolor\128x128\apps\com.local.localslides.png' },
  @{ Png = 'localpaint.png';    App = 'local-paint';     Src = 'assets\app-icon\hicolor\128x128\apps\com.localpaint.app.png' },
  @{ Png = 'localvector.png';   App = 'local-vector';    Src = 'assets\app-icon\hicolor\128x128\apps\com.localvector.app.png' },
  @{ Png = 'localphoto.png';    App = 'local-photo';     Src = 'assets\app-icon\hicolor\128x128\apps\com.localphoto.app.png' },
  @{ Png = 'localobsidian.png'; App = 'local-obsidian';  Src = 'assets\app-icon\hicolor\128x128\apps\com.localobsidian.app.png' },
  @{ Png = 'localmind.png';     App = 'local-mind';      Src = 'assets\app-icon\hicolor\128x128\apps\com.localmind.app.png' },
  @{ Png = 'local-image.png';   App = 'local-image';     Src = 'assets\app-icon\hicolor\128x128\apps\local-image.png' },
  @{ Png = 'local-keys.png';    App = 'local-keys';      Src = 'assets\app-icon\hicolor\128x128\apps\local-keys.png' },
  @{ Png = 'local-utils.png';   App = 'local-utils';     Src = 'assets\app-icon\hicolor\128x128\apps\local-utils.png' },
  @{ Png = 'local-player.png';  App = 'local-player-rs'; Src = 'assets\app-icon\hicolor\128x128\apps\local-player-rs.png' }
)

function Get-Sha([string]$path) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { return [BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($path))).Replace('-', '') }
  finally { $sha.Dispose() }
}

if (-not [System.IO.Directory]::Exists($dest)) { throw "destino ausente: $dest" }

$bad = 0; $pulled = 0
foreach ($i in $icons) {
  $srcPath = [System.IO.Path]::Combine($AppsRoot, $i.App, $i.Src)
  $dstPath = Join-Path $dest $i.Png
  if (-not [System.IO.File]::Exists($srcPath)) {
    Write-Host ("fonte ausente  {0,-18} {1}" -f $i.Png, $srcPath); $bad++; continue
  }
  $same = [System.IO.File]::Exists($dstPath) -and ((Get-Sha $srcPath) -eq (Get-Sha $dstPath))
  if ($same) { Write-Host ("ok             {0,-18} <- {1}" -f $i.Png, $i.App); continue }
  if ($Mode -eq 'pull') {
    [System.IO.File]::WriteAllBytes($dstPath, [System.IO.File]::ReadAllBytes($srcPath))
    Write-Host ("atualizado     {0,-18} <- {1}" -f $i.Png, $i.App); $pulled++
  } else {
    Write-Host ("diverge        {0,-18} <- {1}" -f $i.Png, $i.App); $bad++
  }
}

if ($Mode -eq 'pull') {
  Write-Host "pull: $pulled atualizado(s), $bad fonte(s) ausente(s)."
  if ($pulled -gt 0) { Write-Host 'proximo passo: sync.ps1 -Mode push (replica o crate para os apps).' }
} else {
  Write-Host "check: $($icons.Count - $bad)/$($icons.Count) ok."
}
if ($bad -gt 0) { exit 1 }
