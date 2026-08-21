# Arquitetura, Camadas, Repositórios e Linguagens

> Parte da skill **schematize-elixir**. As referências cruzadas (§N) apontam para seções do corpo completo — todas presentes no conjunto de references desta skill. A base agnóstica desses pisos é a **schematize-engineering**; segurança ofensiva/defensiva é a **schematize-pentest**.

## Índice
- 2. Estrutura de Repositórios
- 3. Linguagens
- 4. Arquitetura
- 5. Estrutura de Pastas
- 6. Complexidade e Tamanho
- 7. Dependências Internas e Shared Libraries
- 8. CQRS e Padrões de Aplicação

---

## 2. Estrutura de Repositórios

**MUST**
- Um repositório = uma aplicação ou um bounded context.
- Comunicação entre serviços via HTTP, gRPC, eventos ou mensageria — nunca via banco compartilhado. Entre nós BEAM, distribuição Erlang / `libcluster` / Phoenix.PubSub é canal legítimo **dentro** do mesmo bounded context, nunca ponte de domínio entre contextos distintos (o detalhe de clustering está em `references/concorrencia.md`).
- Cada serviço é dono do seu schema Ecto e do seu `Repo`.
- **Nome do repositório:** `<projeto>_<contexto>[_<lang>]` em snake_case minúsculo. `<projeto>` = slug do produto/organização; `<contexto>` = a aplicação/bounded context daquele repo (`api`, `worker`, `gateway`, `presence`, `backoffice`…); `_<lang>` é sufixo **opcional** pra desambiguar linguagem (`_ex` Elixir, `_go` Go, `_rs` Rust, `_ts` TypeScript). Como um repo = um contexto, o nome espelha isso. Ex.: `loja_api_ex`, `loja_gateway_ex`, `loja_front`, `loja_worker_go`. O nome do repo casa com o `:app` do `mix.exs` (`loja_api_ex` → `app: :loja_api`).
- **Independência de runtime (cada serviço é entidade à parte):** todo serviço **sobe e opera sozinho**. A indisponibilidade de qualquer outro serviço **nunca** impede o boot nem derruba este — depender de outro serviço para *iniciar/funcionar* é VETADO (nada de "o `ledger` não sobe se o `core` estiver fora"). Na BEAM isso é natural: a *supervision tree* da aplicação (`Application.start/2`) sobe com o dependente ausente e trata a falha por **let-it-crash + supervisão**, não por crash em cascata. Dependente ausente vira **degradação graciosa** (fallback, resposta parcial, circuit breaker, enfileira e segue). Como não perder o dado quando a chamada falha: `references/dados-eventos.md` (§18).
- **`<projeto>_ops` (control plane de desenvolvimento):** todo sistema multi-repo tem um repo **`<projeto>_ops`** — a ferramenta de operação do workspace, rodada por dev/agente e **fora do runtime do produto**. Faz bootstrap/instalação, update, manutenção, troubleshooting e roda os testes/`mix test` **através de todos os repos** (clona, `mix deps.get`, `mix ecto.migrate`, semeia, sobe/para o release e testa cada serviço). Não é aplicação OTP do produto nem é deployada com ele; é essencial pra tocar um sistema de múltiplos repositórios. Como toda ferramenta, sobe com **observabilidade integrada** (Grafana/LGTM+, `:telemetry`, ver `references/observabilidade.md` §16).
- **Contenção no workspace (nunca sair da pasta do projeto):** o **diretório de projeto atual é o workspace**; toda aplicação/repo do sistema nasce e mora **dentro dele**. Vai criar uma aplicação nova? Crie uma **pasta pra ela dentro da pasta atual** (`./<projeto>_<contexto>/`) e trabalhe lá — **nunca** largue arquivos soltos no root pra depois **subir de diretório** (`cd ..`, `../`) e criar os outros repos fora. Num sistema multi-repo os repos são **irmãos dentro do mesmo workspace** (clonados ali pelo `<projeto>_ops`), não espalhados pela máquina. **VETADO** criar/ler/escrever fora do workspace: diretório-pai, `~`, `~/Documents`, `~/Downloads`, `/tmp` do usuário, Área de Trabalho. O agente **não sai da pasta do projeto** — nem pra vasculhar, nem pra criar — a menos que o usuário peça explicitamente.

**VETADO**
- **Aplicação monolítica que acopla múltiplos bounded contexts num só deploy/processo.** Não se cogita "começar monolito e quebrar depois" sem ADR explícito de plano e prazo de quebra. Misturar domínios de negócio "pra entregar rápido" é dívida disfarçada de produtividade.
- **Umbrella virando monólito** — usar `apps/` de um projeto umbrella pra colar domínios que deviam ser serviços separados, com um `Repo` único compartilhado, apps enxergando os schemas Ecto uns dos outros e um único release monstro. Umbrella é conveniência de build de **um** bounded context (ou de contextos coirmãos deliberadamente coesos), não desculpa pra big ball of mud com pasta bonita.
- **Monólito distribuído** — o pior dos dois mundos: serviços separados fisicamente, mas acoplados por banco compartilhado, dep Hex de domínio (§7) ou chamadas síncronas em cascata (RPC entre nós, `GenServer.call` remoto sem fronteira). Tão proibido quanto o monólito clássico.
- **Big ball of mud** — código sem fronteira de contexto, onde todo módulo `alias`-eia todo módulo.

**SHOULD**
- Evitar mais de um domínio de negócio no mesmo repositório.
- Leitura cross-service por réplica read-only só com ADR e contrato documentado.

**MAY**
- *Modular monolith* — **projeto umbrella** com um app por bounded context, cada um com seu `Repo`/schema, fronteira de contexto rígida e comunicação **só por API pública** (uma fachada de Context Phoenix, nunca `alias` do módulo interno do vizinho) — **somente com ADR** que justifique estágio do produto e contenha o plano de extração pra repos separados. É exceção registrada, não default. Nunca usar como atalho para colar domínios.

> Não existe "MVP monolítico que vira microserviço depois" sem o ADR que prova que o depois tem data. Sem isso, "depois" é "nunca", e "nunca" é um umbrella de 40 apps com `Repo` compartilhado em produção.

---

---

## 3. Linguagens

**A casa não tem "a linguagem única"; tem um rol sancionado e um guia de fit.** A engenharia (schematize-engineering) é agnóstica: os pisos — segurança, testes, archive, DoD, IAM, ops, observabilidade — são os mesmos em toda linguagem. A linguagem muda o **como**, não o **o quê**. Esta skill especializa o rol para **Elixir**.

**Backend (serviço novo) — escolha UMA, com ADR (§27) justificando o fit:**

| Linguagem | Skill | Sufixo de repo |
|---|---|---|
| **Go** | `schematize-go` | `_go` |
| **Rust** | `schematize-rust` | `_rs` |
| **Elixir** | `schematize-elixir` | `_ex` |
| **C#** (.NET) | `schematize-csharp` | `_cs` |
| **Zig** | `schematize-zig` | `_zig` |
| **Ruby** | `schematize-ruby` | `_rb` |

**Frontend — Node (e só frontend).** **Next.js** é a stack principal; **Astro** e outros frameworks consolidados são permitidos — governado por **schematize-web**. O server-side do próprio front (route handlers, server actions, BFF) faz parte do frontend e segue o §13.4/§38 (segredo só server-side). Isso vale **apenas** para frontend — **não** reabre Node como linguagem de serviço backend. A UI de um app Phoenix (LiveView/HEEx/canais como transporte de UI) é frontend e delega ao schematize-web; o Phoenix aqui é backend de API/canais/tempo-real.

**Fit do Elixir — quando esta é a linguagem certa (a decisão vira ADR §27):**
- **Realtime e alta concorrência tolerante a falha** — a BEAM/OTP entrega milhões de processos leves isolados, escalonamento preemptivo e *let-it-crash* com supervisão. Gateway de WebSocket/SSE, chat, notificações, dashboards ao vivo.
- **Sistemas distribuídos** — distribuição Erlang nativa, `libcluster`, `:global`/`:pg`, CRDTs; nós que entram e saem sem derrubar o sistema.
- **Messaging/streaming** — ingestão e processamento de eventos com `Broadway`/`GenStage` (backpressure de verdade), pipelines de fila (SQS/RabbitMQ/Kafka).
- **Presença e pub/sub** — `Phoenix.Presence` e `Phoenix.PubSub` como músculo do produto.
- **Soft-realtime** — latência p99 previsível sob carga, graças ao escalonador justo e ao GC por processo (sem *stop-the-world* global).

> Regra de fit: um gateway realtime/presença/streaming pede **Elixir**; um serviço de auth/cripto/parsing hostil pede Rust; um job de rede simples pede Go; um utilitário de sistema pede Zig; uma integração .NET pede C#; um script/protótipo pede Ruby. Se dois encaixam, escolha o **default pragmático** (Go) e registre o porquê no ADR. Elixir **não** é escolha por gosto: é escolha por concorrência/tolerância a falha/tempo-real.

**MUST**
- Versão exata de Erlang/OTP e Elixir em uso fica em `references/stack-versoes.md`; `mix.exs` fixa `elixir:` e o `.tool-versions`/`mise` fixa OTP.
- Não misturar linguagens dentro do **mesmo bounded context** sem ADR.
- **Serviço backend novo dentro do rol sancionado, com ADR de escolha.** Criar backend novo **fora do rol** (ou sem o ADR que justifica o fit) é VETADO. Node-backend e PHP são **legado** e não recebem serviço novo (§3.1, §3.2).
- **Nova linguagem fora do rol** exige **ADR de exceção** aprovado — não se adota por preferência.

**SHOULD**
- Escolha por **encaixe com o problema**, não por preferência. Elixir entra quando o fit acima manda; em empate técnico contra o default pragmático, registre o porquê no ADR.
- Frameworks são bem-vindos; abstrações mágicas não. Critério: consigo entender o stack trace e a árvore de supervisão? Metaprogramação (`macro`) só quando remove boilerplate real — nunca como esperteza que esconde o fluxo.

### 3.1 Legado fora do rol (Node-backend) — migração por funcionalidade

Node como linguagem de **serviço backend** e PHP estão **fora do rol** (não reabrem). O que existe é **legado**: fica como está até ser tocado e migra para uma linguagem do rol — **Elixir quando o fit (realtime/concorrência/distribuído) manda**, senão a que couber — guiado por esforço (não big-bang) e medido **por funcionalidade do módulo**, não por linha.

**Modelo da métrica.** Um módulo tem N funcionalidades (ex.: 10 — cálculo, ABAC, CRUD, etc.). O quanto uma mudança "pesa" é a fração de funcionalidades que ela altera ou cria sobre o total do módulo. Ex.: módulo com 10 funcionalidades — refatorar 2 = 20%; refatorar 3 (ou criar ~4 novas) ≈ 30%.

**MUST**
- **Não mexer no que está feito em legado, a menos que solicitado.** Node-backend funcionando fica como está até ser tocado.
- **Gatilho de extração (~30%):** quando uma mudança atingir ~30% das funcionalidades do módulo (alteradas + novas), **não cresça o legado** — extraia essa(s) funcionalidade(s) para um **serviço/Context à parte na linguagem do rol** (Elixir se o fit pedir) e incorpore o comportamento antigo nessa nova base.
- **Extração incremental:** conforme se mexe no módulo legado ao longo do tempo, vai-se extraindo aos poucos para a linguagem do rol.
- **Virada dos 50%:** quando ~50% do módulo já estiver extraído/inutilizado (substituído pela versão nova), **migra-se os 50% restantes de uma vez** — encerra o módulo legado.
- **Ajuste pontual não porta.** Mudança pequena/localizada (abaixo do gatilho) é feita no próprio legado, sem portabilidade.
- Toda migração registra ADR (§27) e segue o DDD híbrido/coexistência (§4.X, §36): flag de coexistência, sem big-bang.

> Os percentuais (~30% pra extrair, ~50% pra finalizar) são os limiares da casa; ajuste por ADR se um módulo específico exigir. A regra é: parou de ser ajuste pontual, vira extração; passou da metade, termina. Detalhe da saída do Node em `schematize-node`.

### 3.2 PHP — legado, migração sumária

**VETADO** — PHP não é linguagem da casa, em nenhuma camada.

- Nenhum código novo em PHP.
- Projeto existente em PHP é **migrado sumariamente** para uma linguagem do rol (Elixir quando o fit realtime/concorrência pedir) — prioridade de migração, com ADR e plano. Não é "quando der"; é dívida ativa a ser zerada.

---

---

## 4. Arquitetura

**MUST — todos os projetos**
- Separação explícita de camadas: `domain`, `application`, `infrastructure`, `interface`.
- Inversão de dependência: domínio não conhece infra.
- **O domínio não importa Ecto, Phoenix nem qualquer lib de IO.** Nada de `use Ecto.Schema` ou `Phoenix.Controller` dentro do núcleo de regra de negócio — struct pura + funções puras no domínio; Ecto vive na infraestrutura.

**SHOULD — projetos com regra de negócio relevante**
- DDD tático (agregados, value objects, eventos de domínio como structs puras).
- Arquitetura hexagonal (ports & adapters). Em Elixir, o *port* é um **behaviour** (`@callback`) no domínio/aplicação; o *adapter* é a implementação concreta na infraestrutura (injetada por config, não por `alias` hardcoded).
- **Phoenix Contexts como bounded contexts do DDD.** O módulo de Context é a fachada pública do contexto (a única superfície que outros módulos chamam); o que está abaixo dele é interno e não se acessa por fora.

**MAY — CRUDs simples**
- Manter as 4 camadas, dispensar táticas DDD pesadas (schema Ecto + Context + controller já dão a separação mínima).

### Dependências permitidas

```
interface       → application
application     → domain
infrastructure  → domain, application
```

### Dependências proibidas

```
domain          → qualquer outra camada
domain          → Ecto, Phoenix, libs de IO, GenServer de infra
application     → interface
```

### Anti-Corruption Layer

**MUST** em integrações com sistemas externos: adapter dedicado em `infrastructure/external/` (um módulo com behaviour) que traduz o modelo externo para o modelo de domínio. **Nunca** expor o payload externo (mapa cru do JSON, struct do SDK) diretamente no domínio.

### 4.X DDD híbrido durante transição

Projetos legados onde código já existe sem separação de camadas (ou um Phoenix "gordo" com regra de negócio no controller/schema) **podem** adotar DDD progressivamente em vez de big-bang. Regras:

**MUST**
- Toda nova feature/refactor em código tocado segue o layout completo (`domain/`, `application/`, `infrastructure/`, `interface/` — ou os `lib/<app>/` correspondentes) — não introduzir mais lógica de negócio dentro de controller/schema/`GenServer` de borda.
- Ao mover/quebrar módulo legado, organize já nas pastas DDD mesmo que internamente alguma função ainda misture responsabilidades (ex.: função de Context ainda montando `Ecto.Query` no meio da regra). Estrutura primeiro, inversão depois.
- Cada PR que toca módulo híbrido **deve** mover ao menos um pedaço pra direção certa (ex.: extrair value object pra `domain/`, mover a query pra um módulo de repositório em `infrastructure/`).
- ADR registrando o débito e o plano de remoção: `<projeto>/<projeto>_archive/decisoes/<n>-ddd-migration-<contexto>.md`.

**SHOULD**
- Manter teste de cobertura por camada (ver a `schematize-qa`) durante a transição — domain começa com 0%, sobe a cada PR.
- Guard test (ex.: teste que varre `alias`/`import` com `Code`/regex, ou `boundary`/`mix xref`) que **rejeita dependências proibidas** logo que possível (mesmo com whitelist de exceções legadas):
  - `domain/` não faz `use Ecto.Schema`/`Phoenix.*`, nem `alias` de `Infrastructure.*`/`Application.*`/`Interface.*`.
  - `application/` não `alias`-eia `Interface.*`.

**MAY**
- Marcar módulos híbridos com `@moduledoc "@ddd-hybrid: ..."` pra busca fácil e cleanup priorizado.

---

---

## 5. Estrutura de Pastas

### Elixir / Phoenix (um bounded context)

```
lib/
├── <app>/                # o Context (bounded context)
│   ├── domain/           # entities, value-objects, domain services, events (structs/funções puras)
│   ├── application/      # use-cases, commands, queries, ports (behaviours)
│   ├── infrastructure/   # Ecto repos/schemas, messaging, external adapters, telemetry
│   ├── shared/
│   └── application.ex    # supervision tree (Application.start/2)
├── <app>_web/            # interface: Phoenix router, controllers, channels, plugs (UI delega ao schematize-web)
config/                   # config.exs, runtime.exs (segredo só em runtime, §13)
priv/repo/migrations/     # migrations Ecto reversíveis (change/up+down)
test/
mix.exs                   # deps Hex, releases, aliases
```

### Elixir / umbrella (múltiplos bounded contexts coirmãos — ver §2 MAY)

```
apps/
├── <projeto>_core/       # um app por bounded context, cada um com seu Repo/schema
│   └── lib/... (mesma separação domain/application/infrastructure/interface)
├── <projeto>_gateway/    # ex.: app de canais/presença
└── <projeto>_worker/     # ex.: Broadway/GenStage
config/                   # config compartilhada (só infra transversal, nunca domínio cruzado)
mix.exs                   # umbrella root
```

> A separação em camadas é a mesma em Go/Rust/Elixir; o que muda é o layout idiomático (`lib/` + Context + supervision tree). Estruturas equivalentes das linguagens irmãs ficam nas skills irmãs.

---

---

## 6. Complexidade e Tamanho

> **Canônico em `references/padroes-codigo.md`** (arquivo ≤ 750 linhas — ~500 de código útil + ~250 de comentário; flag em > 300 úteis; uma unidade lógica/módulo por arquivo; `@doc`/`@spec` obrigatório com motivo/comportamento/entradas/saídas/efeitos; e `MAPA.md`). Esta seção é o recorte de arquitetura desses pisos — não duplica a regra, contextualiza.

**MUST — arquivos pequenos, micro-funções**
- **Teto duro: ≤ 750 linhas/arquivo** (~250 de comentário + até ~500 de código útil). Acima disso, o arquivo **deve ser quebrado** — extraia responsabilidades em módulos menores e a lógica em **micro-funções** com nome que explica a intenção. Não existe "módulo de 1200 linhas porque é coeso": coesão real cabe em módulos pequenos colaborando. Um `GenServer` gigante que faz tudo é o cheiro clássico — quebre o estado e os `handle_*` em módulos.
- **Flag em > 300 linhas de código útil** (não bloqueia, mas **sempre sinaliza**): passou de 300 úteis (ou ~400 em observabilidade), é **indício** de módulo/função fazendo demais — registre como dívida e **revise quando as prioridades forem resolvidas**.
- **Funções pequenas e de responsabilidade única.** Ideal ≤ 50 linhas; função grande vira micro-funções compostas por *pipe* (`|>`) e *pattern matching*/cláusulas com *guards* no lugar de `if`/`case` aninhado. Use case: uma responsabilidade.
- Exceções (não disparam quebra): testes, migrations, código gerado, schemas/fixtures.

**MUST — toda função pública documentada**
- **TODA função pública tem `@doc` (e `@spec`)** no formato de doc do Elixir. O `@doc` declara, no mínimo:
  - **O quê** — o que a função faz, em uma linha.
  - **Onde é usada / prevista** — quem chama, em que fluxo/camada ela foi pensada pra servir (ex.: "usada pelo use-case `CreateOrder`", "handler do canal `room:*`", "`handle_call` do `LedgerServer`"). Isto dá contexto explícito de propósito e evita função órfã.
  - Parâmetros, retorno e efeitos colaterais relevantes. O `@spec` fixa os tipos (checável por Dialyzer).
- Esse `@doc`/`@spec` é a **fonte do índice de microfunções** (§39) — escreva pensando que ele será extraído e indexado, não como enfeite. Funções privadas (`defp`) e módulos ganham `@moduledoc`/comentário quando a intenção não é óbvia.

Convenção mínima (Elixir):

```elixir
@doc """
O quê: valida o payload de checkout e cria o pedido.
Onde:  use-case CreateOrder; chamado pelo controller POST /v1/checkout.
Efeitos: persiste em orders, publica catalog.order.created via outbox.
"""
@spec create(CreateOrder.t()) :: {:ok, Order.t()} | {:error, term()}
def create(cmd), do: ...
```

**Bloqueio rígido em CI**
- Arquivo de produção > 750 linhas (ou > ~500 de código útil) sem quebra (exceto as exceções acima) → bloqueia; > 300 úteis (~400 obs) → flag registrado.
- Função pública de produção sem `@doc`/`@spec` → bloqueia.
- Complexidade ciclomática > 15 em função de produção (Credo).
- Aninhamento > 4 níveis (prefira `with`, cláusulas de função e *pattern matching* a `case`/`if` empilhados).
- `mix format` e `mix credo --strict` verdes; Dialyzer sem novos warnings.

> Linha de código é proxy ruim para complexidade — complexidade ciclomática é a métrica honesta. Mas módulo gigante e função sem `@doc` são dívidas óbvias: quebre e documente antes do merge.

---

---

## 7. Dependências Internas e Shared Libraries

**MUST**
- Shared libraries (deps Hex internas ou apps de umbrella) são **mínimas** e com escopo claramente delimitado.
- Permitido como shared: observabilidade (`:telemetry`, wrappers de OTel), autenticação/auth (client OIDC/JWKS), primitives de infraestrutura, SDKs internos, logging, configuração.

**MUST NOT**
- Criar `commons` / `core` / `<projeto>_utils` genéricos.
- Compartilhar **lógica de domínio** entre bounded contexts (nem via dep Hex, nem via app de umbrella importado por fora da fachada).
- Compartilhar **schemas Ecto / entidades de domínio**. Cada contexto modela o seu. Um schema compartilhado entre contextos é banco compartilhado disfarçado.

> O caminho mais rápido pra um monólito distribuído é uma dep Hex interna chamada `commons` — ou um app `shared` no umbrella que todo mundo importa.

**SHOULD**
- Deps internas versionadas com SemVer próprio; `mix.lock` **commitado sempre** (piso de reprodutibilidade da cadeia de suprimentos — `references/cadeia-suprimentos.md`).
- Breaking changes em shared lib exigem ADR.

---

---

## 8. CQRS e Padrões de Aplicação

- **Commands**: alteram estado, retornam `{:ok, id}` / `:ok` / `{:error, reason}`.
- **Queries**: nunca alteram estado, otimizadas para leitura, podem usar projeções (read model em tabela/materialized view própria).
- CQRS **não exige** event sourcing.
- Em Elixir, um *command handler* pode ser uma função de Context pura sobre o `Repo`, ou serializar por um `GenServer`/processo quando precisar de ordem/estado por agregado — a escolha e os cuidados de concorrência estão em `references/concorrencia.md`. Não transforme todo caso de uso em `GenServer` por reflexo: processo é pra estado/serialização/isolamento de falha, não pra organizar código.

---

---
