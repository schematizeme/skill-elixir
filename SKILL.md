---
name: schematize-elixir
metadata:
  version: 0.1.0
description: Padrões normativos de engenharia da casa especializados para Elixir (Phoenix/Ecto/OTP sobre a BEAM) — arquitetura, concorrência/OTP, segurança, IAM, testes, pentest, dados, observabilidade, deploy, archive. Use SEMPRE que for projetar, gerar, revisar ou refatorar backend/API/serviço/channel/schema/migration/infra/CI/CD/teste ou deploy em Elixir — mesmo que o usuário não cite "padrão" explicitamente. Aplique também ao decidir arquitetura, escolher stack, modelar eventos/banco, desenhar árvore de supervisão, escrever testes/pentest, configurar observabilidade, ou produzir ADR/runbook/archive. Contém pisos inegociáveis de segurança (segredo nunca no cliente, consulta sempre parametrizada no Ecto, auth server-side, IAM por desenho como app separada, archive obrigatório) e de código (≤750 linhas/arquivo, uma unidade lógica por arquivo, @doc/@spec em toda função pública, MAPA da aplicação) que vetam atalhos inseguros. Frontend delega ao schematize-web.
---

# Padrões de Engenharia da Casa — Elixir

Conjunto normativo que rege como software de backend é projetado, construído, testado e operado aqui, **com Elixir sobre a BEAM/OTP** (Phoenix, Ecto, OTP). Mesma base normativa das demais skills da casa (`schematize-engineering` é a base agnóstica); o que muda é o ferramental, o modelo de concorrência e o ecossistema da linguagem — **nunca o piso**.

**Versão:** skill `schematize-elixir` v0.1.0. Changelog em `CHANGELOG.md`.

## Linguagem: Elixir no rol sancionado (por fit + ADR)

A casa **não tem "a linguagem única"**; tem **um rol sancionado** e um **guia de fit**. Backend novo nasce numa das linguagens do rol — **Go, Rust, Elixir, C#, Zig, Ruby** — escolhida por **encaixe com o problema** e registrada em **ADR (§27)**.

- **Elixir entra por fit:** **realtime e alta concorrência tolerante a falha** (BEAM/OTP), sistemas distribuídos, messaging/streaming, presença/pub-sub, soft-realtime. Modelo de atores, let-it-crash + supervisão. É a escolha certa para gateways realtime, canais, fan-out de eventos, filas e pipelines.
- **Node como serviço backend e PHP são LEGADO/fora do rol** — não recebem serviço novo; migram por funcionalidade do módulo (~30% afetado → extrai; ~50% extraído → migra o resto; ajuste pontual não porta).
- **Frontend Node é 100% permitido** (Next.js principal; Astro) — só frontend, governado pela `schematize-web`. Aqui, Phoenix/LiveView cobrem **API/backend/channels**; a UI de produto delega ao `schematize-web`.
- Detalhe e critérios em `references/arquitetura.md` (§3) e `references/stack-versoes.md`.

## Comandos (Claude Code)

Digite `/elixir-help` pra ver todos. Em resumo:

| Comando | O que faz |
|---|---|
| `/elixir-help` | lista todos os comandos do schematize-elixir |
| `/elixir-cc` | context compact: gera context.md + checklist.md no archive e roda `/compact` |
| `/elixir-handoff` | gera o handoff (context.md + checklist.md) **sem** compactar — pra fim de sessão |
| `/elixir-claude` | cria/atualiza o `CLAUDE.md` da raiz com a versão atual da skill |
| `/elixir-qa` | fluxo de Q.A. plan-first (§22.9): planeja, gera MD, pede aprovação, roda |
| `/elixir-review` | roda o gate da DoD/§37 no diff (`mix format`, Credo, Dialyzer, arquivo >750 bloqueia / >300 úteis flag, função sem `@doc`/`@spec`, índice, migration reversível) |
| `/elixir-iam` | força/audita/scaffolda o IAM (identidade≠email, ≥2 fatores, ReBAC multi-tenant, sessão longa/logout irreversível) como microserviço Elixir separado em `auth.<domain>`, ou porta um auth legado |
| `/elixir-index` | (re)gera o índice de microfunções (§39) a partir dos `@doc`/`@spec` |
| `/elixir-ops` | audita/scaffolda o `<projeto>_ops` (interface única): fluxo de ambientes, instalação paralela (`nproc`), independência |
| `/elixir-load` | carrega à força TODO o corpo normativo e passa a aplicá-lo no projeto atual |

Os comandos ficam em `assets/commands/` e são instalados em `.claude/commands/`.

## Como usar esta skill

1. Identifique o domínio da tarefa e **leia o(s) reference(s) relevante(s)** antes de produzir código ou decisão. Não trabalhe de memória — os detalhes (versões, limites, convenções) estão nos arquivos.
2. **Sempre** aplique os pisos inegociáveis abaixo, independente do reference carregado.
3. Ao terminar, valide contra a Definition of Done (`references/entrega.md`, §35) e **gere o archive** (§28, `references/operacao.md`).

Mapa de references — leia o que casa com a tarefa:

| Tarefa | Reference |
|---|---|
| **Limites de código (arquivo ≤750: ~500 úteis + ~250 comentário; flag >300 úteis), uma unidade/arquivo, `@doc`/`@spec`, MAPA** | `references/padroes-codigo.md` |
| Arquitetura, camadas, DDD, contexts do Phoenix, umbrella, anti-monólito, rol de linguagens, CQRS | `references/arquitetura.md` |
| **Concorrência/OTP: processos, GenServer, árvore de supervisão, let-it-crash, Task/Agent, Registry, PubSub, backpressure (GenStage/Broadway/Oban), distribuição (nós BEAM), shutdown** | `references/concorrencia.md` |
| Eventos/mensageria, banco (Ecto), cache, APIs, resiliência, jobs (Oban) | `references/dados-eventos.md` |
| Segurança, auth, JWT (Guardian/Joken), multi-tenancy, LGPD, **segredos/`config/runtime.exs`** | `references/seguranca.md` |
| **IAM (identidade+autorização): auth como microserviço Elixir separado (`auth.<domain>`), ID≠email, ≥2 fatores/passkey/Resend/Twilio, ReBAC multi-tenant, sessão longa/logout irreversível, migração de legado** | `references/iam.md` |
| **Cadeia de suprimentos: `mix.lock`, `mix hex.audit`, SBOM, scan que trava, imagem mínima/pinada/assinada, SLSA, segredo no build** | `references/cadeia-suprimentos.md` |
| **Stack e versões: Elixir/Erlang-OTP/Phoenix suportados, EOL, `.tool-versions`, `mix.exs`, escolha de libs, umbrella vs apps** | `references/stack-versoes.md` |
| Testes — ExUnit, StreamData, Mox, saída machine-readable, categorias (§22.1–22.3) | `references/testes.md` |
| Testes — padrão de script, seeds, CI, pentest, Q.A. plan-first, `mix` aliases (§22.4–23) | `references/testes-execucao.md` |
| Observabilidade, `:telemetry`+OTel, healthchecks, performance (BEAM), FinOps | `references/observabilidade.md` |
| Config, deploy (`mix release`), git/PR, ownership, runbooks/incidentes, ADR, **archive** (§20–28) | `references/operacao.md` |
| **Ops (control plane): fluxo dev→local→github→hml→prd (nada direto no servidor), ops como interface única (100%, autônomo), instalação paralela=`nproc`, independência=invariante** | `references/ops.md` |
| Templates, feature flags, IA assistida, DoD, evolução, índice de funcionalidades (§29+) | `references/entrega.md` |
| Filosofia, aplicação universal e a lista completa de anti-padrões vetados | `references/anti-padroes.md` |
| Gestão de contexto em sessões longas no Claude Code (handoff, hooks) | `references/contexto-claude-code.md` |

## Pisos inegociáveis (VETADO — sem ADR de exceção)

Estes nunca são violados, nem "pra funcionar", nem "pra ir mais rápido". A lista completa com veto + caminho certo está em `references/anti-padroes.md` (§37). Os que mais aparecem em código gerado às pressas:

- **Segredo nunca no cliente.** Nada de API key, secret de JWT, senha de banco ou token em bundle do browser, nem em `NEXT_PUBLIC_*`/`VITE_*`. No Elixir, config sensível vem de `config/runtime.exs` (env em runtime) — **nunca** compilada em `config/*.exs` nem embutida no `mix release`. Detalhe em `references/seguranca.md`.
- **Consulta sempre parametrizada.** Ecto por query DSL / pin (`^`); concatenar input em `fragment`/SQL cru é injeção esperando acontecer.
- **Auth e autorização server-side.** `tenant_id`/role/`user_id` vêm do token verificado, nunca do body/header do cliente. Validação no front é UX, não controle.
- **JWT validado por inteiro** (assinatura, exp, aud, iss, alg em allowlist) via Guardian/Joken. Senha em **argon2id** (`argon2_elixir`). Token/id de sessão por CSPRNG (`:crypto.strong_rand_bytes`), nunca `:rand`.
- **Erro nunca engolido** (`rescue`/`catch` que cala, `_ = ...` que descarta, `!`-bang fora de fronteira controlada); use `{:ok, _}`/`{:error, _}` e `with`. Bug de verdade **deixa crashar** (let it crash) — não mascare.
- **Teste nunca silenciado** pra passar CI (`@tag :skip`, comentar assert, baixar threshold de cobertura). Conserta o código, não o teste.
- **Sem monólito que mistura bounded contexts**, sem monólito distribuído, sem umbrella virando monólito, sem shared lib `commons` de domínio. Detalhe em `references/arquitetura.md`.
- **Archive SEMPRE gerado.** Toda entrega que produz código/decisão/mudança de estado gera o `.md` de archive (§28) — parte da entrega, não extra. Templates em `assets/`.
- **Migration reversível** (Ecto `up`/`down`, testada com rollback). Container não-root, read-only. Dependência Hex nova com nome/licença/versão verificados (typosquatting é real).
- **Pisos de código (`references/padroes-codigo.md`):** arquivos **≤ 750 linhas** (teto duro: ~250 de comentário + ~500 de código útil; acima → quebrar por coesão), **flag em > 300 linhas de código útil**, **uma unidade lógica (módulo) por arquivo**, **`@doc` + `@spec` em toda função pública** (motivo, comportamento, entradas, saídas, efeitos), **`MAPA.md` da aplicação** atualizado no mesmo PR — em **`<projeto>_archive/index/`, nunca no root** — e **índice de microfunções** regenerado (`/elixir-index`). **Todo MD gerado mora no archive**, root limpo (§28).
- **Backend novo só no ROL sancionado (Go/Rust/Elixir/C#/Zig/Ruby), escolhido por fit + ADR.** Elixir entra por fit (realtime/alta concorrência tolerante a falha/BEAM-OTP/distribuído/streaming/pub-sub). **Node como serviço backend e PHP são legado/fora do rol** — não recebem serviço novo; migração medida por funcionalidade do módulo (~30% afetado → extrai; ~50% extraído → migra o resto). **Frontend Node é 100% permitido** (só frontend). Nova linguagem fora do rol exige ADR de exceção. Detalhe em `references/arquitetura.md` (§3).
- **Concorrência sob desenho (`references/concorrencia.md`).** Toda fila/canal é **bounded** (backpressure real — VETADO fila ilimitada/mailbox crescendo sem limite); não bloquear o scheduler (NIF longo → dirty scheduler; nada de `:timer.sleep` em process crítico); árvore de supervisão explícita com estratégia certa; graceful shutdown que drena o que está em voo; `terminate/2` não é garantido — não confie nele para invariante.
- **Fluxo de ambientes e ops (`references/ops.md`).** Toda mudança segue **dev local → teste local → GitHub → hml → prd**; **VETADO editar código direto no servidor** (recebe só a `mix release` do commit SHA). **100%** das operações no servidor passam pela **ferramenta do `<projeto>_ops`** — nunca à mão, nunca `mix` solto em prd; o ops é **autônomo**. **Instalação sempre paralela** = `nproc`; **falha no paralelo = serviços não independentes → prioridade máxima** (não serializar pra mascarar).
- **Deploy destrutivo por seed + isolamento por usuário (`references/ops.md` §2–§3).** O ops provisiona em **`/<app>/`** clonando os repos dentro; **`/<app>/.env` é o seeder global**. **Todo redeploy é destrutivo na aplicação** (clone zerado só com o seed, idempotente/sem drift) **preservando os dados** (migration reversível; `ops reset` de dados só em dev/hml). **Cada serviço roda como user Linux próprio em systemd unit hardened**. Tudo automatizado pelo ops.
- **IAM por desenho (`references/iam.md`).** Todo projeto começa com identidade+autorização robustas, e o **auth é app SEPARADA** — **microserviço Elixir** `<projeto>_auth_ex` (Phoenix/Plug) + front próprio em `auth.<domain>`, isolados; nunca monolith. Apps delegam por OIDC/PKCE e validam por JWKS público. **ID interno imutável (ULID/UUIDv7) — email/telefone nunca é ID.** **≥2 fatores sempre** (passkey/WebAuthn via `wax` no núcleo, TOTP via `nimble_totp`, email OTP Resend/Swoosh always-on, Twilio; providers como behaviours; senha argon2id+HIBP por padrão mas opcional). Senha + Email OTP já é **2FA baseline** — o PEP libera o baseline e exige AAL alto **só por rota sensível** (step-up just-in-time), **nunca barra o login**. **Multi-tenant RBAC/ABAC granular via ReBAC** (OpenFGA/SpiceDB; deny-default, PDP=Check / PEP=Plug, server-side, token fino). **Multi-dispositivo, sessão 7d/90d, logout irreversível.** **Migrar auth legado = prioridade 0.** Scaffold/auditoria por **`/elixir-iam`**; testes cross-tenant/priv-esc na `schematize-pentest`.

> Regra de bolso: se a justificativa começa com "só pra funcionar", "depois eu arrumo" ou "é mais rápido assim" e o resultado mexe em segredo, auth, dado ou registro — é um anti-padrão vetado. Pare e faça certo.

## Testes — o que conta como "verde de verdade"

Detalhe completo em `references/testes.md` (§22.1–22.3) e `references/testes-execucao.md` (§22.4–23). O essencial:

- **Smoke não pode ser teatro:** assertar shape do body (não só status 200), assertion negativa (sem stack trace/placeholder), e um **self-check que força uma falha conhecida** pra provar que o runner consegue reportar FAIL. Smoke que nunca falha está cego.
- **Unit agressivo (ExUnit):** caminho de erro obrigatório (`{:error, _}`), casos hostis (tipo errado, unicode, null byte, boundary), property-based (StreamData) e mutation no domínio crítico. Mocks só na fronteira (Mox contra behaviour), `Ecto.Adapters.SQL.Sandbox` por teste. Doctests (`@doc`) contam. Cobertura de linha é piso, não meta.
- **Pentest prova rejeição, rota por rota, campo por campo:** nunca 500 por input hostil, nunca coerção silenciosa de tipo, nunca eco sem escape, nunca vazamento cross-tenant. Princípios em `references/testes-execucao.md` (§22.8).
- **`simulated` (teste emulado):** cruza rotas × personas × injections e prova que **100% das rotas** do inventário estão acessíveis pra quem deve e bloqueadas pra quem não deve. Rota fantasma/morta quebra o run.
- **Fluxo de Q.A. (plan-first, §22.9):** toda submissão de Q.A. **planeja tudo primeiro**, gera um MD detalhado, e **pede aprovação do usuário antes de executar**. Aprovado, oferece rodar **faseado e assistido** ou **de uma vez** (multiagentes + watchdog que retoma de checkpoint até concluir; passo destrutivo só com gate). Nada de Q.A. roda às cegas.

## Andaime pronto (scripts e templates)

Não escreva do zero o que já está bundlado:

- `scripts/lib.sh` — helpers de teste (`test_pass`, `test_fail`, `test_skip`, `test_section`, `test_summary`, `http_call`, `assert_http_in`). Todo script de teste usa estes.
- `scripts/test-skeleton.sh` — esqueleto obrigatório de `tests/<mode>/<name>.sh`.
- `scripts/smoke-selfcheck.sh` — o meta-teste anti "verde mentiroso".
- `scripts/simulated/run.py` — scaffold do engine rotas × personas × injections.
- `scripts/hooks/context-monitor.mjs` + `scripts/hooks/precompact-backup.mjs` — gestão de contexto no Claude Code (limite de handoff, backup automático em `<projeto>_archive`). Ver `references/contexto-claude-code.md` e `assets/settings.claude.example.json`.
- `assets/ADR.md`, `assets/TASK.md`, `assets/CHAT_ARCHIVE.md`, `assets/PR_TEMPLATE.md`, `assets/RUNBOOK.md` — templates (§27/§28).
- `assets/INDEX_GLOBAL.md` + `assets/INDEX_FUNCTIONS.md` + `scripts/build-index.mjs` — índice de funcionalidades (§39): o global é mantido à mão; o de microfunções é **gerado** dos `@doc`/`@spec` (§6) pelo `build-index.mjs`, que sai 1 se achar função pública sem contexto (trava CI).
- `assets/CLAUDE.md` — arquivo "sempre on" pra colocar na **raiz do repositório**: pina estes padrões no contexto de toda tarefa. Copie e ajuste `<project>`.
- `assets/commands/elixir-cc.md` — comando `/elixir-cc` (context compact): gera `context.md` + `checklist.md` em `<projeto>_archive` e compacta. Copie para `.claude/commands/elixir-cc.md`. Ver `references/contexto-claude-code.md`.

## Aplicação sempre-on

Esta skill é puxada quando a tarefa casa com a descrição. Para garantir que os padrões valham em **toda** interação do repo (e não só nas que disparam a skill), copie `assets/CLAUDE.md` para a raiz do projeto (ou rode `/elixir-claude`). Os dois mecanismos se complementam: o `CLAUDE.md` pina o resumo e aponta pra cá; a skill entrega o detalhe e o andaime.
