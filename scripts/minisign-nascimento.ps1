# minisign-nascimento.ps1 - seta os secrets MINISIGN_KEY/MINISIGN_PASSPHRASE num repo
# de app craft recem-criado e PROVA que ficou certo. Passo padrao do nascimento
# de todo app novo (padrao-craft.md, secao Assinatura minisign).
#
# Uso: powershell -File minisign-nascimento.ps1 -Repo Anon5T4R/Local-Photo
#
# O que faz (e falha se algo nao bater):
#   1. Localiza o backup da chave (Windows: C:\Dev\minisign-suite; Arch: ~/Dev/minisign-suite).
#   2. Se houver pendrive Ventoy (F:\_Meus_Arquivos\Backups\minisign-suite), confere
#      paridade byte a byte (key/pub/passphrase) - backup atualizado e pre-requisito.
#   3. Seta os 2 secrets via gh (sem imprimir valores).
#   4. Confirma via gh secret list que os 2 existem com data de hoje.
#   5. Baixa packaging/minisign.pub do repo e confere que e IDENTICO ao .pub do
#      backup - garante que o CI vai assinar com a chave certa (auto-verificacao
#      do job falha se divergir).
param([Parameter(Mandatory=$true)][string]$Repo)
$ErrorActionPreference = 'Stop'

# 1. fonte
$suite = @('C:\Dev\minisign-suite', "$env:HOME\Dev\minisign-suite") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $suite) { throw 'Backup minisign-suite nao encontrado (C:\Dev\minisign-suite ou ~/Dev/minisign-suite).' }
$key  = Join-Path $suite 'minisign-suite.key'
$pub  = Join-Path $suite 'minisign-suite.pub'
$pass = Join-Path $suite 'PASSPHRASE.txt'
foreach ($f in @($key,$pub,$pass)) { if (-not (Test-Path $f)) { throw "Ausente no backup: $f" } }
Write-Host "fonte: $suite"

# 2. paridade com pendrive (se montado)
$pen = 'F:\_Meus_Arquivos\Backups\minisign-suite'
if (Test-Path $pen) {
  foreach ($n in @('minisign-suite.key','minisign-suite.pub','PASSPHRASE.txt')) {
    $a = (Get-FileHash (Join-Path $suite $n) -Algorithm SHA256).Hash
    $b = (Get-FileHash (Join-Path $pen $n) -Algorithm SHA256).Hash
    if ($a -ne $b) { throw "PENDRIVE DIVERGE de $suite em $n - atualize o backup antes de setar secrets." }
  }
  Write-Host 'pendrive: paridade OK'
} else { Write-Host 'pendrive: nao montado (skipped)' }

# 3. seta
Get-Content $key  -Raw | gh secret set MINISIGN_KEY        -R $Repo | Out-Null
Get-Content $pass -Raw | gh secret set MINISIGN_PASSPHRASE -R $Repo | Out-Null
Write-Host 'secrets setados'

# 4. confirma
$list = gh secret list -R $Repo | Out-String
foreach ($n in @('MINISIGN_KEY','MINISIGN_PASSPHRASE')) {
  if ($list -notmatch [regex]::Escape($n)) { throw "$n NAO aparece no gh secret list de $Repo" }
}
Write-Host 'gh secret list: 2/2 confirmados'

# 5. pubkey do repo = pubkey do backup (requer o repo ja ter recebido o primeiro push)
$ErrorActionPreference = 'Continue'
$repoPub = gh api "repos/$Repo/contents/packaging/minisign.pub" -H 'Accept: application/vnd.github.raw' 2>&1 | Out-String
$ErrorActionPreference = 'Stop'
if (-not $repoPub -or $repoPub -match 'Not Found|empty') {
  Write-Warning "packaging/minisign.pub ainda nao existe em $Repo (repo vazio/sem push?) - rode este script de novo APOS o primeiro push, antes da primeira release."
} else {
  $localPub = [System.IO.File]::ReadAllText($pub).TrimEnd("`r","`n")
  if ($repoPub.TrimEnd("`r","`n") -ne $localPub) { throw 'packaging/minisign.pub do repo DIVERGE do backup - a auto-verificacao do CI vai recusar assinar. Corrija antes da release.' }
  Write-Host 'pubkey do repo identica ao backup'
  Write-Host "OK: $Repo assina com a chave da suite."
}
