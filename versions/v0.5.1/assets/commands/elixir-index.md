---
description: (Re)gera o índice de microfunções (§39) a partir dos doc-comments
argument-hint: "[dir de origem, ex: lib]"
---

Atualize o **índice de funcionalidades** (§39) — **fonte da verdade** do projeto e base do MAPA (§4). O índice é **exaustivo**: **uma entrada por função**, de **cada** serviço, **com grafo**. Ele **enumera** o sistema; não resume.

## 1. Enumere e CONTE (a verdade do que existe)

Antes de gerar, descubra **todas** as funções do alvo `${ARGUMENTS:-lib}` — públicas e privadas, incluindo funções nomeadas em módulos, callbacks OTP (`handle_call`/`handle_cast`/`handle_info`), heads de múltiplas cláusulas, guards e closures nomeadas. Conte as declarações (use AST/ctags se houver; senão, ripgrep):

- **Elixir (funções):** `rg -n '^\s*def(p)?\s'` (públicas `def` e privadas `defp`; conta cada cláusula/head)
- **Elixir (módulos):** `rg -n '^\s*defmodule\s'` (um nó por módulo no grafo)
- **Elixir (macros/callbacks):** `rg -n '^\s*(defmacro(p)?|def(p)?)\s'` para pegar `defmacro` também
- **Go:** `rg -n '^\s*func '`
- **Rust:** `rg -n '^\s*(pub\s+)?(async\s+)?fn '` (inclui métodos em `impl`)
- **TS/JS:** `rg -n '(export\s+)?(async\s+)?function |const\s+\w+\s*=\s*(async\s*)?\(|^\s*\w+\s*\([^)]*\)\s*\{'`
- **Python:** `rg -n '^\s*def '`

Trate **múltiplas cláusulas da mesma função** (`def foo(0)`, `def foo(n)`) como **uma função lógica** (por `nome/aridade`) — mas registre todas as cláusulas no `arquivo:linha`. Guarde **N = total de funções** (por `nome/aridade`) por serviço/pasta. É o alvo de completude — e faça para **cada** serviço do sistema, não só o que você tocou.

## 2. Uma entrada por função (sem "relevante")

Para **cada** função encontrada (por `nome/aridade`), uma linha em `<projeto>_archive/index/INDEX_FUNCTIONS.md` (um arquivo por serviço):
`função/aridade | o quê | de onde vem → pra onde vai | chama (out) | é chamada por (in) | efeitos | arquivo:linha`.
Fonte: `scripts/build-index.mjs` se existir; senão, extraia do `@doc`/`@spec` acima da função (§3) — case o `@doc`/`@spec` que precede imediatamente cada `def`/`defp`. **Nenhuma** função fica de fora por "não ser relevante".

## 3. Construa o GRAFO (o mapa não é lista)

- **Grafo de serviços** → `INDEX_GLOBAL.md`: bloco `mermaid flowchart LR` com **todos** os microserviços/apps como nós e arestas `A -->|contrato| B` (rota/evento/fila/mensagem OTP entre nós). Nenhum serviço de fora. Espelhe em adjacência textual (`A -> B (contrato)`) pra grep.
- **Grafo de chamadas** → por serviço, no `INDEX_FUNCTIONS.md` e no `MAPA.md` (§5): `mermaid flowchart` dos pontos de entrada (controllers Phoenix, handlers OTP, jobs Oban) às saídas **+** adjacência `chamador -> chamada`. Cada função (`nome/aridade`) é um nó.

## 4. Concilie a COMPLETUDE (gate duro)

- Conte as entradas do índice (**M**) e compare com **N**, **por serviço**.
- **Se M < N → FALHE.** Liste, **pelo nome/aridade**, as `N - M` funções que ficaram de fora e volte ao passo 2 até `M == N`. Índice com menos entradas que funções é bug, não resumo — o caso "90 linhas pra 100+ funções" é **reprovado aqui**.
- Se `scripts/build-index.mjs` sair com código 1, há função pública sem `@doc`/`@spec` (§3): corrija **na origem** (o quê + de onde→pra onde), não no índice.

## 5. Global + MAPA + confirmação

- `<projeto>_archive/index/INDEX_GLOBAL.md`: **cada** repo/serviço/app com 1 linha, árvore de pastas top-level e o **grafo de serviços**. Nenhum de fora.
- Espelhe no `<projeto>_archive/index/MAPA.md` (§4) — **no archive, nunca no root**: microfunções geradas + grafos (§2.5, §5).
- Confirme ao usuário com **números**: `N funções / M entradas / G serviços no grafo`, e que **M == N** em cada serviço. Se não bater, **não terminou**.
