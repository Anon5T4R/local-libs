# local-libs

Fonte única das bibliotecas **nossas** da suíte Local (padrão craft). Os apps não
dependem deste repo por path/git — cada um mantém uma **cópia vendored** em
`libs/craft-libs/crates/<crate>` e este repo é a **fonte de verdade** que o
script de sincronização replica e vigia.

## Mecânica (copy-script, modelo `local-ai`)

- **Fonte:** `crates/<crate>` aqui.
- **Cópias:** `libs/craft-libs/crates/<crate>` em cada app.
- **Sync:** `powershell -File scripts/sync.ps1 -Mode verify` confere fonte ×
  apps por hash de diretório; `-Mode push` copia e confere. O commit do
  `HASHES.<crate>` declara o estado canônico — fonte que diverge do manifest sem
  push explícito falha no verify. Worktree ou crate nova num app: `-Dirs <pasta do app>` (o push cria a cópia).
- **Ícones do diálogo de update:** `crates/update/assets/icons/*.png` (128 px) são
  espelho do `hicolor/128x128` de cada app. Ícone mudou num app →
  `powershell -File scripts/sync-icons.ps1 -Mode pull` (copia só os que divergem;
  `-Mode check`, o default, só confere e sai 1 se divergir; `-AppsRoot` p/ o Arch) →
  `sync.ps1 -Mode push` para replicar o crate aos apps. Tabela PNG → app → fonte no topo do script.
- **Instalador MSI:** `python -I scripts/wix-check.py <app> <ref> <wxs> <package.ps1>` compila o `.wxs` com
  binários falsos (segundos, sem build de release). Rode antes de mergear qualquer mudança em `packaging/windows`.
- **Compilação:** acontece dentro do workspace `craft-libs` de cada app (a crate
  herda workspace fields, lints e patches de path do app — egui/winit vendored).
  Este repo **não é workspace de build**.

## Por que copy-script (decisões 2026-11-13, plano-bibliotecas.md)

Rejeitados: **submodule** (um ponteiro por app por mudança + protocolo), **crates.io**
(crate específica da suíte — catálogo, bundle ids — não publicável como está),
**path dep direto** (o CI clona 1 repo por app). **Ganho honesto:** elimina
divergência (drift), não elimina a replicação de commit em cada app — nenhuma
mecânica elimina.

## Crates

| crate | origem | notas |
|---|---|---|
| `craft-update` | fork permanente consciente do upstream storytold | fora do escopo do sync-upstream. Minisign: verificação advisory, `SUITE_PUBKEYS` em lista (rotação = append). |
| `craft-ai-ui` | extraída do Local Obsidian | a superfície de IA da suíte: `ConnectionsPanel`, `StatusStrip`, `ChatPanel`, `WindowPolicy` (`ContextSource`/`LastN`/orçamento com prioridade turno atual > últimos N > doc). Só egui, sem rede: o app inicia o próprio stream e alimenta o painel; prompts, contexto e apply ficam no app. Primeiro consumidor: Local Obsidian. |
| `craft-desktop-theme` | substitui os leitores próprios de sheets, office, pdf, paint e photo | faz `ctx.system_theme()` responder no Linux, onde o winit não informa tema: um plugin egui copia para o `RawInput` a resposta do portal XDG (observador do `craft-platform` vendorizado, feature `appearance`, que reage ao sinal de mudança). Uso: `craft_desktop_theme::follow(&cc.egui_ctx)` uma vez no binário, nunca em teste. Windows/macOS: não instala nada. |
| `craft-icons` | padronização da casca (SVGs dos catálogos do Local Vector e do Local PDF) | um ícone Lucide (ISC) por conceito comum da suíte (tema, configurações, idioma, ajuda, atualização, IA, arquivo, edição, estado), pelo enum `Icon` e pela tabela `ALL` no formato do `SvgIconSet` do craft-ui. Sem dependências. Ícone de ferramenta específica do app fica no catálogo do app. |
| `craft-palette` | padronização da casca (molde: Local Mind) | a paleta de comandos da suíte: caixa de busca sobre os comandos que o app lista (id, nome, grupo, atalho, ativo), filtro por início de palavra sem caixa nem acento, ↑/↓/Enter/Esc. Ctrl+K só onde o app não usa o atalho (`Palette::shortcut_pressed`); a lupa da barra abre sempre. Só egui. |
| `craft-mcp` | extraída do Local Vector; adaptada de `storytold/vectorcraft` + `storytold/wordcraft` (MIT OR Apache-2.0, crédito no README da crate) | a plumbing MCP da suíte: servidor stdio `Server<Handler>` (JSON-RPC 2.0, revisões MCP, batch, panic→erro), `script` (`run --script job.json`: array ou JSON Lines + referências `"$N"`), `automation` (flags `--automation-read-root`/`--automation-write-root` + containment) e `remote` (`mcp --connect PORT`, loopback only). Sem dependências além de `serde_json`. |

**Regra de entrada:** nova crate só entra aqui quando (a) já vive idêntica em
2+ apps, ou (b) é exigida pelo template de app novo (F10). Kit/capacidade
(editor-kit, media-kit, vault-kit) só nasce de app real concluído.

**Manifesto de crate nova:** `publish = false` sempre. Uma dependência `path` sem versão (outra crate
vendorizada, ex. `craft-platform`) numa crate publicável reprova o `cargo-deny` (`wildcards`) nos apps cujo
`deny.toml` não isenta a crate — o `cargo check`/clippy/testes locais não pegam; rode `cargo deny check bans`
num app antes do push.

## Assets

| Asset | Origem | O que é |
|---|---|---|
| `assets/craft-fonts` | fonte única das fontes da suíte (antes espalhada em versões entre os apps) | as fontes vendored da suíte (CJK, árabe, hebraico, devanágari, latinas extras): build input `CRAFT_FONTS_DIR`, que cada app aponta para `assets/craft-fonts` no `.cargo/config.toml`. Espelho em `<app>/assets/craft-fonts` **só nos apps que embutem essas escritas** (mind, obsidian, office, paint, pdf, photo, sheets, slides e vector; keys, image, utils e player não carregam): `sync.ps1 -Asset craft-fonts`. |

## Fluxo de mudança

1. Edite **aqui** e rode `sync.ps1 -Mode push`.
2. Commite este repo (`crates/` + `HASHES.<crate>` juntos) e push.
3. Commite cada app alterado (mensagem aponta o commit da fonte) e push — CI de
   cada app valida o build.
4. Registro no `local-deps` quando a mudança altera dependências.

Commits em português, sem Co-Authored-By. Nunca edite a cópia de um app
diretamente — o verify vai acusar drift e o próximo push sobrescreve.
