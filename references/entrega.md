# Entrega: Templates, Flags, IA Assistida, DoD, Evolução e Índice

> Parte da skill **schematize-elixir**. Continuação de `operacao.md` (numeração de seções **preservada**, §29+): templates, feature flags, uso de IA assistida, Definition of Done, evolução e índice de funcionalidades. Cross-refs por número de seção continuam válidos. Os pisos de tamanho/documentação vivem em `padroes-codigo.md`; os de teste em `testes.md`/`testes-execucao.md`; os anti-padrões vetados na `anti-padroes.md` (§37). Base agnóstica na **schematize-engineering**.

---

## 29. Templates

```
/templates
├── README.md
├── ADR.md
├── TASK.md
├── PR_TEMPLATE.md
├── ISSUE_TEMPLATE.md
├── RUNBOOK.md
├── MAPA.md               # arquivo-guia da aplicação (padroes-codigo §4)
├── INDEX_GLOBAL.md       # índice global da aplicação (§39)
├── INDEX_FUNCTIONS.md    # índice de microfunções (§39)
└── OPENAPI_TEMPLATE.yaml
```

README mínimo: o que é, como rodar (`mix setup`, `mix deps.get`), como testar (`mix test`), como deployar (release / `mix release`), dependências (hex.pm + versão de OTP/Elixir), observabilidade (Telemetry/OpenTelemetry), oncall e runbook.

**Piso Elixir do scaffolding** — todo projeto novo nasce com:
- `.formatter.exs` versionado (formatação é contrato, não gosto — §35).
- `.credo.exs` versionado com o preset da casa (Credo reprova o build).
- `mix.exs` com `dialyzer:` configurado (Dialyxir) e PLT cacheado no CI.
- `mix aliases` que encapsulem o fluxo: `mix setup`, `mix ci`, `mix ecto.setup`, `mix ecto.reset`. O `make ci` (§23) apenas orquestra os aliases — a fonte da verdade é o `mix.exs`.
- Se for Phoenix/API: `OpenApiSpex` ligado, spec derivada dos controllers e validada no CI (`make docs`).

---

---

## 31. Feature Flags

Obrigatório para features críticas, migrações e rollouts graduais.
Capacidades: rollout por % de tráfego, segmentação por tenant/usuário, kill switch, expiração de flag.
No ecossistema Elixir/BEAM: **FunWithFlags** (backend Ecto ou Redis, com gate por actor/group/%), OpenFeature (SDK Elixir) para padronizar a interface, ou GrowthBook via SDK. A avaliação da flag roda **no servidor** (nunca decidida no cliente — liga com §38); o estado propaga entre nós via PubSub para não haver flag "meio ligada" no cluster.

Flag é temporária por design: toda flag nasce com **dono e data de expiração** registrados. Flag zumbi (ligada 100% há meses, sem remoção do código morto) é dívida — vira item de limpeza, não decoração permanente.

---

---

## 34. Uso de IA Assistida

**MUST**
- Código gerado por IA passa pelo mesmo PR review humano que qualquer outro.
- Autor humano é responsável: assina o commit, entende o código, mantém.
- Saídas de IA não substituem ADR.
- **IA opera sob a §37 (anti-padrões vetados) integralmente.** Gerar código que viola um item VETADO é defeito, não estilo — rejeita no review.
- **IA gera o archive (§28) junto com o código**, na mesma entrega.
- **Código Elixir gerado por IA vem com `@doc` + `@spec`** nas funções públicas e passa por `mix format` + Credo antes do PR — sem isso o `/elixir-index` e o `/elixir-review` reprovam (§39, §35).

**MUST NOT / VETADO**
- Colar trecho gerado sem ler.
- Aceitar dependências hex.pm sugeridas sem verificar nome, dono e downloads (typosquatting em hex é real — §37); pacote não fixado em `mix.lock` não entra.
- Submeter código que não passa em `mix ci` (`make ci`).
- Aceitar "solução rápida" da IA que burla um piso de segurança da §37 — ex.: interpolar valor cru em `Ecto.Adapters.SQL.query/4`, atomizar entrada externa (`String.to_atom/1`), ou capturar erro com `rescue`/`catch` engolindo a causa.

**SHOULD**
- Prompt e contexto relevantes registrados no chat archive quando a decisão for não trivial.
- Verificar licença de snippets longos sugeridos.

### 34.1 Handoff de contexto em sessões longas

Sessões longas de agente degradam quando o contexto enche: o modelo "esquece" decisões e a compactação automática resume de forma lossy. Para não perder estado, o handoff é **proativo e arquivado**, não reativo. Detalhe de ferramenta em `references/contexto-claude-code.md`.

**MUST**
- Definir um **limite de handoff** (tokens) abaixo do teto da janela — cedo o suficiente pra sobrar espaço pra escrever o resumo. Sugestão: ~25% da janela (ex.: 250k numa janela de 1M).
- Ao cruzar o limite, **antes de qualquer compactação**, gerar dois artefatos em `<project>_archive/context/`:
  - `<YYYY-MM-DD-HH-MM-SS>-context.md` — estado do projeto, decisões tomadas, arquivos tocados, onde parou.
  - `<YYYY-MM-DD-HH-MM-SS>-checklist.md` — **feito vs. em aberto**.
- Só então compactar/limpar o contexto. O handoff é archive obrigatório (§28) — armazenar **sempre** em `<project>_archive`.
- **Rede de segurança determinística:** um backup do estado é capturado automaticamente antes de toda compactação (manual ou automática), independente de o agente ter lembrado de gerar os MDs acima.

**SHOULD**
- O limite é configurável por ambiente/projeto (ex.: env var `CTX_THRESHOLD`), não hardcoded.
- O resumo de contexto preserva o que **você** escolhe (foco na tarefa corrente), não o que a compactação automática adivinha.

> Compactação automática é rede, não plano. Em sessão longa, o handoff arquivado vem antes do teto — quem controla o que sobrevive é você, não o resumo lossy. Comandos: `/elixir-cc`, `/elixir-handoff`.

---

---

## 35. Definition of Done

Uma task está pronta quando, cumulativamente. Roda pelo gate `/elixir-review`:

- [ ] `mix test` **verde de verdade** (unit + integration), cobertura nos mínimos — sem `@tag :skip` novo, sem teste comentado, sem asserção afrouxada pra "passar" (§37)
- [ ] Caminhos críticos com testes explícitos (ExUnit; property-based com StreamData onde o domínio pede)
- [ ] **`mix format --check-formatted` limpo** — formatação é contrato
- [ ] **Credo sem ofensa nova** (config `.credo.exs` versionada; `--strict` no domínio crítico)
- [ ] **Dialyzer (Dialyxir) limpo no domínio crítico** — `@spec` nas funções públicas; PLT no CI
- [ ] **Teste emulado por IA (`simulated`, §22.3) executado — 100% das rotas do inventário acessíveis pra quem deve e bloqueadas pra quem não deve; rota fantasma/morta = bloqueio**
- [ ] **Pentest de entrada limpo: sem `500`, sem coerção de tipo, sem eco não-escapado, sem vazamento cross-tenant (§22.3, §22.8)**
- [ ] `mix sobelow` / SAST + `mix deps.audit` (SCA) limpos
- [ ] **Nenhum item da §37 (anti-padrões vetados) presente no diff**
- [ ] **Arquivos ≤ 750 linhas (~500 úteis + ~250 de `@doc`/comentário); código útil > 300 linhas (~400 obs) flagueado e registrado como dívida (§6, padroes-codigo §1); toda função pública com `@doc` + `@spec` de contexto — o quê + de onde vem → pra onde vai (padroes-codigo §3)**
- [ ] **Índice de funcionalidades atualizado no mesmo PR — global e microfunções (§39); `/elixir-index` sem função órfã (`nº entradas == nº funções`)**
- [ ] **MAPA da aplicação atualizado no mesmo PR (padroes-codigo §4)**
- [ ] Observabilidade implementada (`Logger` estruturado, Telemetry/métricas, traces OpenTelemetry, audit se aplicável)
- [ ] OpenAPI atualizada (se for API — `OpenApiSpex`, `make docs`)
- [ ] **Migration Ecto reversível testada** — `mix ecto.migrate` e `mix ecto.rollback` verdes; `change` autorreversível ou par `up/down` explícito (se houver schema change)
- [ ] Documentação atualizada (README, ADR, runbook se aplicável)
- [ ] Smoke tests executados em staging **(com asserção de conteúdo e self-check anti verde-mentiroso — §22.3)**
- [ ] CI verde, code review aprovado
- [ ] **Archive de chat/task gerado e commitado (§28) — gate rígido, não opcional**
- [ ] Feature flag configurada (se aplicável)
- [ ] CODEOWNERS aplicável revisou

> Os itens em negrito são **bloqueantes absolutos**: archive (§28), ausência de macaquice (§37), teste emulado por IA com rota 100% acessível (§22.3), pentest de entrada limpo (§22.8), migration reversível testada, e o quarteto de qualidade Elixir (`mix format --check-formatted`, Credo sem ofensa nova, Dialyzer limpo no crítico, `mix test` verde de verdade). Faltando qualquer um, a task **não está pronta** — independente de todo o resto estar verde. Smoke verde não basta: tem que ser smoke que **prova** conteúdo, não só status. Verde-mentiroso (teste que passa sem exercer o código) é falha, não aprovação.

---

---

## 36. Evolução

- Refactors incrementais. Big-bang rewrite exige ADR e plano de rollback.
- Toda migração de runtime/framework/dependência major tem flag de coexistência (§31).
- DDD e o desenho por **contexts do Phoenix** (bounded contexts) podem ser adotados progressivamente — comece pelas bordas e pelos domínios mais complexos; extraia o domínio dos controllers/LiveViews para módulos de contexto puros.
- Migração de versão de **OTP/Elixir** major exige ADR e passa por CI com a versão nova antes do bump em produção.
- Evolução de árvore de supervisão (novos `GenServer`/`Supervisor`/`Task.Supervisor`) é mudança arquitetural — atualiza MAPA (padroes-codigo §4) e, quando muda topologia de processos, ADR (§27).
- **Releases** (`mix release`) evoluem com hot-vs-cold definido por ADR; migração de schema roda via task de release dedicada (`Ecto.Migrator`), nunca `mix ecto.migrate` no nó de produção.

---

---

## 39. Índice de Funcionalidades (fonte da verdade viva)

O código diz **como** está agora; o índice diz **o que existe, onde mora e como se faz cada coisa** — e é tratado como **fonte da verdade do projeto**, consultado antes de criar algo (pra não duplicar) e atualizado a cada mudança. Índice que apodrece é pior que não ter; por isso ele é gerável/validável e tem gate na DoD. Gerado por `/elixir-index`.

**MUST — existência e localização**
- Todo projeto mantém o índice versionado em `<project>_archive/index/` (ou `/docs/index/`), em **dois níveis**:
  - **Índice global da aplicação** (`INDEX_GLOBAL.md`) — o mapa macro: apps do umbrella / contexts / bounded contexts e como se comunicam; a relação de **pastas top-level** (`lib/`, `lib/<app>_web/`, `priv/`, `test/`) e a responsabilidade de cada uma; **o que cada coisa faz** e o ponto de entrada de **como se faz** (link pro fluxo/use-case/runbook). É o "mapa do território" — casa com o MAPA (padroes-codigo §4).
  - **Índice de microfunções** (`INDEX_FUNCTIONS.md`, por app/serviço) — o catálogo fino: cada função/módulo → **o quê**, **onde é usada/prevista**, dependências e efeitos colaterais. Gerado a partir dos `@doc`/`@spec` obrigatórios (§6, padroes-codigo §3).

**MUST — atualização e gate**
- Todo PR que **adiciona, remove ou move** funcionalidade atualiza o índice no mesmo PR. Índice desatualizado **trava o merge** (item da DoD, §35).
- O índice é **fonte da verdade**: ao planejar uma feature, consulte-o primeiro pra não reimplementar o que já existe (anti-duplicação — liga com DRY semântico, §1).
- Formato **machine-friendly** (markdown com tabelas, ou JSON/YAML que renderiza) pra permitir geração e validação automáticas — não prosa solta.

**MUST — completude (uma entrada por função, sem "relevante")**
- O índice de microfunções é **exaustivo**: **uma entrada por unidade chamável** — `def`, `defp`, `defmacro`, função de callback de `GenServer`/`Supervisor`, handler de LiveView, job/consumer, closure nomeada — de **cada** app/serviço do sistema, **pública e privada**. Não existe função "irrelevante": se está no código, está no índice. "Função relevante" **não é filtro** pra pular nada. Cabeças de função com múltiplas cláusulas contam como **uma** entrada por aridade (`nome/aridade`).
- **Invariante verificável (conte, não confie):** por app/serviço, `nº de entradas no índice == nº de funções declaradas no código`. O `/elixir-index` e o CI **contam as declarações** (AST via `Code.string_to_quoted/1`, ou regex de `def `/`defp `/`defmacro `) e **reprovam** se o índice tiver **menos** entradas que funções encontradas — listando as que faltam **pelo nome/aridade**. Índice com 90 linhas para 100+ funções é **falha dura**, não aviso. O mapa não "resume" o sistema; ele **enumera** o sistema.
- **Cobertura total:** o índice **global** lista **cada** app/serviço (nenhum de fora); cada app tem seu índice de funções **completo**. Um sistema de N apps com M funções tem os N apps mapeados e as M funções indexadas.

**MUST — o mapa é um GRAFO, não uma lista**
- O índice/MAPA carrega um **grafo textual** de dependências, navegável em dois níveis:
  - **Grafo de serviços** (cross-app/cross-service): nós = apps/serviços; arestas `A → B` rotuladas pelo **contrato** (rota/evento/fila/tópico PubSub). Quem chama/notifica quem no sistema inteiro.
  - **Grafo de chamadas** (intra-app): por função, **quem ela chama** (out) e **quem a chama** (in) — adjacência `chamador → chamada`. Percorre-se de um ponto de entrada (controller/LiveView/consumer) até a saída, e vê-se o **raio de impacto** de qualquer função.
- **Formato:** bloco **Mermaid** (`flowchart`) — textual **e** renderiza no GitHub/markdown — **mais** a adjacência em lista/tabela (pra diff, busca e grep). O Mermaid é o desenho; a adjacência é a fonte pesquisável. Ambos gerados pelo `/elixir-index`.

**SHOULD — geração assistida**
- O índice de microfunções é **gerado por script** — `scripts/build-index.mjs` (bundlado, agnóstico de linguagem) — que varre os `@doc`/`@spec` padronizados (§6, padroes-codigo §3) e monta a tabela `função → o quê → onde → arquivo:linha`. O script **sai com código 1** se achar função pública sem contexto (trava o CI). CI compara o índice commitado com o gerado; divergência aponta índice ou `@doc` desatualizado.
- Cada entrada linka pro arquivo/linha de origem.
- Índice global e MAPA revisados em cada mudança arquitetural (junto com o ADR, §27).

**Conteúdo mínimo**

`INDEX_GLOBAL.md`: lista de apps/serviços com 1 linha de propósito cada; por app, árvore de pastas top-level com responsabilidade; mapa de comunicação (quem chama quem, quais eventos/tópicos PubSub/contratos); links pra OpenAPI, SLO, runbook.

`INDEX_FUNCTIONS.md` (por app/serviço, **exaustivo — uma linha por função/aridade**): `função/aridade | o quê | de onde vem → pra onde vai | chama (out) | é chamada por (in) | efeitos | arquivo:linha`; **nº de linhas == nº de funções do app**. Acompanha o **grafo de chamadas** (Mermaid + adjacência). O `INDEX_GLOBAL.md` inclui o **grafo de serviços** (Mermaid) com **todos** os apps/serviços e seus contratos.

> O índice responde "isso já existe? onde? como faço X?" sem precisar reler o código. Se a resposta exige caçar no código, o índice falhou — ou está desatualizado, e isso é bug.

---

---

## Anexo A — Versões Correntes

> Atualizado independentemente do documento principal. Revisão trimestral.

| Stack | Versão alvo (2026-05) |
|---|---|
| Elixir | 1.18+ |
| Erlang/OTP | 27+ |
| Phoenix | 1.7+ (LiveView 1.0+) |
| Ecto | 3.12+ |
| Node.js | 24 LTS (frontend: Next.js, Astro, etc. — §3) |
| Go | 1.25 (auxiliar / IAM microserviço — `references/iam.md` §1) |
| PostgreSQL | 16+ |
| Redis | 7+ |
| Kubernetes | 1.30+ |
| OpenAPI | 3.1 |
| OpenTelemetry | 1.x (estável) |

Mudanças de versão major (Elixir, OTP, Phoenix, Ecto) exigem ADR (§27).

---

---

## Anexo B — Glossário Mínimo

- **Bounded Context / Phoenix Context** — fronteira explícita dentro da qual um modelo de domínio é consistente; em Phoenix, o módulo de contexto que isola o domínio da camada web.
- **Monólito distribuído** — serviços fisicamente separados mas acoplados por banco compartilhado, shared lib de domínio ou cadeia síncrona sem fronteira. O pior dos dois mundos. Proibido (§2).
- **BFF (Backend for Frontend)** — camada server-side que serve um frontend específico e mantém os segredos fora do browser (§38).
- **Outbox Pattern** — gravar evento em tabela no mesmo commit do dado de negócio (`Ecto.Multi`); publicador assíncrono lê a tabela e publica no broker. Garante consistência sem dual-write.
- **Supervision tree** — árvore de supervisão OTP: `Supervisor`/`GenServer`/`Task.Supervisor` que definem estratégia de reinício ("let it crash" com recuperação); topologia de processos é decisão arquitetural.
- **BEAM** — máquina virtual do Erlang sobre a qual Elixir roda; concorrência por processos leves isolados e passagem de mensagem.
- **DLQ** — dead letter queue, fila de mensagens que falharam após retries (ex.: Oban com `max_attempts`).
- **Anti-Corruption Layer** — adapter que isola seu domínio do modelo externo.
- **SLO** — service level objective, alvo mensurável de qualidade (ex: 99.9% das requests < 300ms em 30 dias).
- **Error Budget** — quanto você pode falhar dentro do SLO antes de freezar features.
- **Blameless Postmortem** — análise de incidente focada em sistema/processo, não em culpa individual.
- **CSPRNG** — gerador pseudoaleatório criptograficamente seguro (`:crypto.strong_rand_bytes/1`). Obrigatório para tokens, ids de sessão e segredos (§14).
- **Macaquice** — atalho que parece entregar mais rápido e entrega vulnerabilidade ou dívida. Catalogadas e vetadas na §37.

---
