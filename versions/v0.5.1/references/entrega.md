# Entrega: Templates, Flags, IA Assistida, DoD, Evolução e Índice


> **PONTEIRO, não cópia.** A normativa deste tema é da base: **`schematize-engineering`** →
> `references/entrega.md`. Leia lá primeiro; aqui fica **só o que muda em Elixir/OTP**.
>
> **Onde este arquivo divergir da base, a BASE MANDA** (`SKILL.md` §"Precedência e herança").
> Em 2026-08-21 os blocos idênticos à base foram **podados mecanicamente** (`tools/podar-clone.mjs`),
> que é por que a numeração dos itens **salta**: o número é o da base, e o item que não aparece aqui
> é porque **não muda nesta linguagem** — procure-o lá. Manter a cópia era manter a próxima deriva
> (foi assim que o `argon2id-only` da casa virou "ou PBKDF2" numa skill e o rol de 6 linguagens
> virou "só Go e Rust" em três).

## 29. Templates

README mínimo: o que é, como rodar (`mix setup`, `mix deps.get`), como testar (`mix test`), como deployar (release / `mix release`), dependências (hex.pm + versão de OTP/Elixir), observabilidade (Telemetry/OpenTelemetry), oncall e runbook.

**Piso Elixir do scaffolding** — todo projeto novo nasce com:

- `.formatter.exs` versionado (formatação é contrato, não gosto — §35).

- `.credo.exs` versionado com o preset da casa (Credo reprova o build).

- `mix.exs` com `dialyzer:` configurado (Dialyxir) e PLT cacheado no CI.

- `mix aliases` que encapsulem o fluxo: `mix setup`, `mix ci`, `mix ecto.setup`, `mix ecto.reset`. O `make ci` (ver a `schematize-qa` (Makefile padrao, `references/execucao.md` secao 7)) apenas orquestra os aliases — a fonte da verdade é o `mix.exs`.

- Se for Phoenix/API: `OpenApiSpex` ligado, spec derivada dos controllers e validada no CI (`make docs`).

## 31. Feature Flags

Flag é temporária por design: toda flag nasce com **dono e data de expiração** registrados. Flag zumbi (ligada 100% há meses, sem remoção do código morto) é dívida — vira item de limpeza, não decoração permanente.

## 34. Uso de IA Assistida

- **Código Elixir gerado por IA vem com `@doc` + `@spec`** nas funções públicas e passa por `mix format` + Credo antes do PR — sem isso o `/elixir-index` e o `/elixir-review` reprovam (§39, §35).

- Aceitar dependências hex.pm sugeridas sem verificar nome, dono e downloads (typosquatting em hex é real — §37); pacote não fixado em `mix.lock` não entra.

- Submeter código que não passa em `mix ci` (`make ci`).

- Aceitar "solução rápida" da IA que burla um piso de segurança da §37 — ex.: interpolar valor cru em `Ecto.Adapters.SQL.query/4`, atomizar entrada externa (`String.to_atom/1`), ou capturar erro com `rescue`/`catch` engolindo a causa.

### 34.1 Handoff de contexto em sessões longas

Sessões longas de agente degradam quando o contexto enche: o modelo "esquece" decisões e a compactação automática resume de forma lossy. Para não perder estado, o handoff é **proativo e arquivado**, não reativo. Detalhe de ferramenta em `references/contexto-claude-code.md`.

- O limite é configurável por ambiente/projeto (ex.: env var `CTX_THRESHOLD`), não hardcoded.

> Compactação automática é rede, não plano. Em sessão longa, o handoff arquivado vem antes do teto — quem controla o que sobrevive é você, não o resumo lossy. Comandos: `/elixir-cc`, `/elixir-handoff`.

## 35. Definition of Done

Uma task está pronta quando, cumulativamente. Roda pelo gate `/elixir-review`:

- [ ] `mix test` **verde de verdade** (unit + integration), cobertura nos mínimos — sem `@tag :skip` novo, sem teste comentado, sem asserção afrouxada pra "passar" (§37)

- [ ] Caminhos críticos com testes explícitos (ExUnit; property-based com StreamData onde o domínio pede)

- [ ] **`mix format --check-formatted` limpo** — formatação é contrato

- [ ] **Credo sem ofensa nova** (config `.credo.exs` versionada; `--strict` no domínio crítico)

- [ ] **Dialyzer (Dialyxir) limpo no domínio crítico** — `@spec` nas funções públicas; PLT no CI

- [ ] **Teste emulado por IA (`simulated`, a `schematize-qa` (`references/categorias.md` §§5 e 10)) executado — 100% das rotas do inventário acessíveis pra quem deve e bloqueadas pra quem não deve; rota fantasma/morta = bloqueio**

- [ ] **Pentest de entrada limpo: sem `500`, sem coerção de tipo, sem eco não-escapado, sem vazamento cross-tenant (a `schematize-qa` (`references/categorias.md` §§5 e 10), a `schematize-pentest`)**

- [ ] `mix sobelow` / SAST + `mix deps.audit` (SCA) limpos

- [ ] **Arquivos ≤ 750 linhas (~500 úteis + ~250 de `@doc`/comentário); código útil > 300 linhas (~400 obs) flagueado e registrado como dívida (§6, padroes-codigo §1); toda função pública com `@doc` + `@spec` de contexto — o quê + de onde vem → pra onde vai (padroes-codigo §3)**

- [ ] **Índice de funcionalidades atualizado no mesmo PR — global e microfunções (§39); `/elixir-index` sem função órfã (`nº entradas == nº funções`)**

- [ ] **MAPA da aplicação atualizado no mesmo PR (padroes-codigo §4)**

- [ ] Observabilidade implementada (`Logger` estruturado, Telemetry/métricas, traces OpenTelemetry, audit se aplicável)

- [ ] OpenAPI atualizada (se for API — `OpenApiSpex`, `make docs`)

- [ ] **Migration Ecto reversível testada** — `mix ecto.migrate` e `mix ecto.rollback` verdes; `change` autorreversível ou par `up/down` explícito (se houver schema change)

- [ ] Smoke tests executados em staging **(com asserção de conteúdo e self-check anti verde-mentiroso — a `schematize-qa` (`references/categorias.md` §§5 e 10))**

- [ ] **Nenhum efeito externo real fora de `prd` (se o projeto envia e-mail/SMS/push/webhook/cobrança):** provider default = **sink**, **guard deny-by-default dentro do provider** (com teste que **vê a recusa**), **cap por execução** válido em TODOS os ambientes, e endereços só no **domínio de teste em rota nula**. Normativa: `schematize-engineering` → `references/efeitos-externos.md`; recorte desta linguagem em `references/iam.md` §3.1; anti-padrão §37 *"Disparar efeito externo REAL a partir de não-produção"* (citado **por título**, porque a numeração do §37 diverge entre skills)

> Os itens em negrito são **bloqueantes absolutos**: archive (§28), ausência de macaquice (§37), **nenhum efeito externo real fora de `prd`** (`schematize-engineering` → `references/efeitos-externos.md`), teste emulado por IA com rota 100% acessível (ver a `schematize-qa`, `references/categorias.md` §§5 e 10), pentest de entrada limpo (ver a `schematize-pentest`), migration reversível testada, e o quarteto de qualidade Elixir (`mix format --check-formatted`, Credo sem ofensa nova, Dialyzer limpo no crítico, `mix test` verde de verdade). Faltando qualquer um, a task **não está pronta** — independente de todo o resto estar verde. Smoke verde não basta: tem que ser smoke que **prova** conteúdo, não só status. Verde-mentiroso (teste que passa sem exercer o código) é falha, não aprovação.

## 36. Evolução

- Toda migração de runtime/framework/dependência major tem flag de coexistência (§31).

- DDD e o desenho por **contexts do Phoenix** (bounded contexts) podem ser adotados progressivamente — comece pelas bordas e pelos domínios mais complexos; extraia o domínio dos controllers/LiveViews para módulos de contexto puros.

- Migração de versão de **OTP/Elixir** major exige ADR e passa por CI com a versão nova antes do bump em produção.

- Evolução de árvore de supervisão (novos `GenServer`/`Supervisor`/`Task.Supervisor`) é mudança arquitetural — atualiza MAPA (padroes-codigo §4) e, quando muda topologia de processos, ADR (§27).

- **Releases** (`mix release`) evoluem com hot-vs-cold definido por ADR; migração de schema roda via task de release dedicada (`Ecto.Migrator`), nunca `mix ecto.migrate` no nó de produção.

## 39. Índice de Funcionalidades (fonte da verdade viva)

O código diz **como** está agora; o índice diz **o que existe, onde mora e como se faz cada coisa** — e é tratado como **fonte da verdade do projeto**, consultado antes de criar algo (pra não duplicar) e atualizado a cada mudança. Índice que apodrece é pior que não ter; por isso ele é gerável/validável e tem gate na DoD. Gerado por `/elixir-index`.

**MUST — existência e localização**

- Todo projeto mantém o índice versionado em `<project>_archive/index/` (ou `/docs/index/`), em **dois níveis**:
  - **Índice global da aplicação** (`INDEX_GLOBAL.md`) — o mapa macro: apps do umbrella / contexts / bounded contexts e como se comunicam; a relação de **pastas top-level** (`lib/`, `lib/<app>_web/`, `priv/`, `test/`) e a responsabilidade de cada uma; **o que cada coisa faz** e o ponto de entrada de **como se faz** (link pro fluxo/use-case/runbook). É o "mapa do território" — casa com o MAPA (padroes-codigo §4).
  - **Índice de microfunções** (`INDEX_FUNCTIONS.md`, por app/serviço) — o catálogo fino: cada função/módulo → **o quê**, **onde é usada/prevista**, dependências e efeitos colaterais. Gerado a partir dos `@doc`/`@spec` obrigatórios (§6, padroes-codigo §3).

- Todo PR que **adiciona, remove ou move** funcionalidade atualiza o índice no mesmo PR. Índice desatualizado **trava o merge** (item da DoD, §35).

- O índice é **fonte da verdade**: ao planejar uma feature, consulte-o primeiro pra não reimplementar o que já existe (anti-duplicação — liga com DRY semântico, §1).

- Formato **machine-friendly** (markdown com tabelas, ou JSON/YAML que renderiza) pra permitir geração e validação automáticas — não prosa solta.

- O índice de microfunções é **exaustivo**: **uma entrada por unidade chamável** — `def`, `defp`, `defmacro`, função de callback de `GenServer`/`Supervisor`, handler de LiveView, job/consumer, closure nomeada — de **cada** app/serviço do sistema, **pública e privada**. Não existe função "irrelevante": se está no código, está no índice. "Função relevante" **não é filtro** pra pular nada. Cabeças de função com múltiplas cláusulas contam como **uma** entrada por aridade (`nome/aridade`).

- **Invariante verificável (conte, não confie):** por app/serviço, `nº de entradas no índice == nº de funções declaradas no código`. O `/elixir-index` e o CI **contam as declarações** (AST via `Code.string_to_quoted/1`, ou regex de `def `/`defp `/`defmacro `) e **reprovam** se o índice tiver **menos** entradas que funções encontradas — listando as que faltam **pelo nome/aridade**. Índice com 90 linhas para 100+ funções é **falha dura**, não aviso. O mapa não "resume" o sistema; ele **enumera** o sistema.

- **Cobertura total:** o índice **global** lista **cada** app/serviço (nenhum de fora); cada app tem seu índice de funções **completo**. Um sistema de N apps com M funções tem os N apps mapeados e as M funções indexadas.

**MUST — o mapa é um GRAFO, não uma lista**

- O índice/MAPA carrega um **grafo textual** de dependências, navegável em dois níveis:
  - **Grafo de serviços** (cross-app/cross-service): nós = apps/serviços; arestas `A → B` rotuladas pelo **contrato** (rota/evento/fila/tópico PubSub). Quem chama/notifica quem no sistema inteiro.
  - **Grafo de chamadas** (intra-app): por função, **quem ela chama** (out) e **quem a chama** (in) — adjacência `chamador → chamada`. Percorre-se de um ponto de entrada (controller/LiveView/consumer) até a saída, e vê-se o **raio de impacto** de qualquer função.

- **Formato:** bloco **Mermaid** (`flowchart`) — textual **e** renderiza no GitHub/markdown — **mais** a adjacência em lista/tabela (pra diff, busca e grep). O Mermaid é o desenho; a adjacência é a fonte pesquisável. Ambos gerados pelo `/elixir-index`.

- O índice de microfunções é **gerado por script** — `scripts/build-index.mjs` (bundlado, agnóstico de linguagem) — que varre os `@doc`/`@spec` padronizados (§6, padroes-codigo §3) e monta a tabela `função → o quê → onde → arquivo:linha`. O script **sai com código 1** se achar função pública sem contexto (trava o CI). CI compara o índice commitado com o gerado; divergência aponta índice ou `@doc` desatualizado.

- Cada entrada linka pro arquivo/linha de origem.

- Índice global e MAPA revisados em cada mudança arquitetural (junto com o ADR, §27).

**Conteúdo mínimo**

`INDEX_GLOBAL.md`: lista de apps/serviços com 1 linha de propósito cada; por app, árvore de pastas top-level com responsabilidade; mapa de comunicação (quem chama quem, quais eventos/tópicos PubSub/contratos); links pra OpenAPI, SLO, runbook.

`INDEX_FUNCTIONS.md` (por app/serviço, **exaustivo — uma linha por função/aridade**): `função/aridade | o quê | de onde vem → pra onde vai | chama (out) | é chamada por (in) | efeitos | arquivo:linha`; **nº de linhas == nº de funções do app**. Acompanha o **grafo de chamadas** (Mermaid + adjacência). O `INDEX_GLOBAL.md` inclui o **grafo de serviços** (Mermaid) com **todos** os apps/serviços e seus contratos.

> O índice responde "isso já existe? onde? como faço X?" sem precisar reler o código. Se a resposta exige caçar no código, o índice falhou — ou está desatualizado, e isso é bug.

## Anexo A — Versões correntes → **`references/stack-versoes.md`**

> **Esta tabela foi REMOVIDA daqui.** Versão de terceiro é **fato com prazo de validade**, e ela
> vivia clonada em 8 `entrega.md` do catálogo — a mesma tabela, com a mesma data, apodrecendo em
> oito lugares ao mesmo tempo (ela ainda apontava uma versão de Go e uma de Kubernetes que **já estavam fora de suporte**). Fato volátil tem **um** lugar por skill: o **anexo volátil**, com **data de
> verificação** e cadência de revisão.
>
> **Onde está agora:** `references/stack-versoes.md` desta skill (versões de Elixir/OTP e do
> ferramental dela) e, para o que é de infraestrutura (Kubernetes, Postgres, Redis, OTel), a
> **`schematize-infra`**.
>
> **A regra que fica:** mudança de versão **major** exige ADR — isso não é volátil e continua aqui.
> E o lint do catálogo (`tools/lint.mjs`, regra `anexo-volatil`) **reprova** versão cravada no
> corpo normativo quando a skill tem anexo: é o detector que impede a próxima safra.

## Anexo B — Glossário Mínimo

- **Bounded Context / Phoenix Context** — fronteira explícita dentro da qual um modelo de domínio é consistente; em Phoenix, o módulo de contexto que isola o domínio da camada web.

- **Outbox Pattern** — gravar evento em tabela no mesmo commit do dado de negócio (`Ecto.Multi`); publicador assíncrono lê a tabela e publica no broker. Garante consistência sem dual-write.

- **Supervision tree** — árvore de supervisão OTP: `Supervisor`/`GenServer`/`Task.Supervisor` que definem estratégia de reinício ("let it crash" com recuperação); topologia de processos é decisão arquitetural.

- **BEAM** — máquina virtual do Erlang sobre a qual Elixir roda; concorrência por processos leves isolados e passagem de mensagem.

- **DLQ** — dead letter queue, fila de mensagens que falharam após retries (ex.: Oban com `max_attempts`).

- **CSPRNG** — gerador pseudoaleatório criptograficamente seguro (`:crypto.strong_rand_bytes/1`). Obrigatório para tokens, ids de sessão e segredos (§14).
