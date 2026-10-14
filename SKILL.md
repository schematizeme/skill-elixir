---
name: schematize-elixir
metadata:
  version: 0.5.1
description: >-
  Backend em Elixir/OTP: Phoenix, Ecto, Oban, LiveView, supervisão. Use ao projetar ou revisar mix.exs, *.ex/*.exs: API, GenServer, migration, CI. Entra por fit + ADR.
---

# Padrões de Engenharia da Casa — Elixir

Conjunto normativo que rege como software de backend é projetado, construído, testado e operado aqui, **com Elixir sobre a BEAM/OTP** (Phoenix, Ecto, OTP). Mesma base normativa das demais skills da casa (`schematize-engineering` é a base agnóstica); o que muda é o ferramental, o modelo de concorrência e o ecossistema da linguagem — **nunca o piso**.

**Versão:** skill `schematize-elixir` v0.5.1. Changelog em `CHANGELOG.md`.

## Linguagem: Elixir no rol sancionado (por fit + ADR)

A casa **não tem "a linguagem única"**; tem **um rol sancionado** e um **guia de fit**. Backend novo nasce numa das linguagens do rol — **Go, Rust, Elixir, C#, Zig, Ruby** — escolhida por **encaixe com o problema** e registrada em **ADR (§27)**.

- **Elixir entra por fit:** **realtime e alta concorrência tolerante a falha** (BEAM/OTP), sistemas distribuídos, messaging/streaming, presença/pub-sub, soft-realtime. Modelo de atores, let-it-crash + supervisão. É a escolha certa para gateways realtime, canais, fan-out de eventos, filas e pipelines.
- **Node como serviço backend e PHP são LEGADO/fora do rol** — não recebem serviço novo; migram por funcionalidade do módulo (~30% afetado → extrai; ~50% extraído → migra o resto; ajuste pontual não porta).
- **Frontend Node é 100% permitido** (Next.js principal; Astro) — só frontend, governado pela `schematize-web`. **UI server-rendered em Phoenix (LiveView/HEEx/canais) é governada AQUI, por esta skill** (LiveView, estado do socket, auth, deploy), herdando da `schematize-web` apenas os pisos agnósticos de front: a11y WCAG 2.2 AA, Core Web Vitals, segurança de front (CSP, sem HTML não sanitizado, segredo só server-side) e SEO. Next/Astro continuam da `schematize-web`.
- Detalhe e critérios em `references/arquitetura.md` (§3) e `references/stack-versoes.md`.

## Precedência e herança (leia antes de divergir)

<!-- herdado:engineering/precedencia:backend linguagem="Elixir/OTP" -->Esta skill é o **recorte Elixir/OTP** da base. Duas regras governam a relação, e elas resolvem sozinhas
quase toda dúvida de "onde está escrito o quê":

1. **Onde esta skill divergir da base, a BASE MANDA.** `schematize-engineering` é a normativa; aqui
   mora a **especialização** — o mecanismo, a lib, a sintaxe, o gate da linguagem. Divergência de
   *piso* entre este arquivo e a base é **defeito desta skill**, não uma variante local aceitável.
   Achou uma? É item de correção, não licença. *(Foi assim que o `argon2id-only` da casa virou
   "argon2id ou PBKDF2" em uma skill só, e o rol de 6 linguagens virou "só Go e Rust" em três.)*
2. **O que não está repetido aqui é HERDADO, não dispensado.** A ausência de um piso neste repo
   nunca significa que ele não vale — significa que ele não muda de forma nesta linguagem. Em
   especial, valem integralmente, sem cópia local:
   - **§28 Archive** — `<projeto>/<projeto>_archive/` é **repositório git próprio, PRIVADO e
     obrigatório**, criticidade 0 (`schematize-archive`; ADR-0005 para a planta canônica).
   - **§39 Índice/MAPA** — enumeração exaustiva (uma entrada por unidade chamável, `M == N`) e o
     **grafo com arestas em ASCII (`A -> B`), NUNCA a seta unicode** — o parser do app lê ASCII.
   - **§35 Definition of Done** e a lista de anti-padrões **§37** (citada por **título**, nunca por
     número: a numeração dos itens diverge entre skills).
   - **IAM** (`schematize-engineering` → `references/iam.md`): identidade ≠ email, ≥2 fatores, ReBAC multi-tenant,
     **alcançabilidade do 2º fator** (o fator de recuperação tem de ser alcançável quando o
     principal cai — senão o 2FA vira bug de bootstrap que tranca o dono para fora), os parâmetros
     mínimos de argon2id, sessão longa e logout irreversível.
   - **Rol sancionado** — Go, Rust, Elixir, C#, Zig, Ruby, por **fit + ADR**
     (`schematize-engineering` → `references/linguagens.md`). Esta skill é **uma** delas, não a
     régua das outras.
   - **Efeito externo** nunca sai de não-produção (`schematize-engineering` →
     `references/efeitos-externos.md`; gate em `scripts/check-external-effects.sh`, distribuído
     aqui — ADR-0008).<!-- /herdado -->

## Comandos (Claude Code)

Digite `/elixir-help` pra ver todos. Em resumo:

| Comando | O que faz |
|---|---|
| `/elixir-help` | lista todos os comandos do schematize-elixir |
| `/elixir-cc` | context compact: gera context.md + checklist.md no archive e roda `/compact` |
| `/elixir-handoff` | gera o handoff (context.md + checklist.md) **sem** compactar — pra fim de sessão |
| `/elixir-claude` | cria/atualiza o `CLAUDE.md` da raiz com a versão atual da skill |
| `/elixir-qa` | Q.A. no contexto Elixir — wrapper da **schematize-qa** (`/qa-plan` → `/qa-run`) com `mix test`/ExUnit |
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
| **Efeito externo fora de prd (e-mail/SMS/push): adapter Swoosh por ambiente, sink por default, guard no `Auth.Mailer`, cap com `:counters`, domínio de teste em rota nula** | `references/iam.md` (§3.1) + `schematize-engineering/references/efeitos-externos.md` |
| **IAM (identidade+autorização): auth como microserviço Elixir separado (`auth.<domain>`), ID≠email, ≥2 fatores/passkey/Resend/Twilio, ReBAC multi-tenant, sessão longa/logout irreversível, migração de legado** | `references/iam.md` |
| **Cadeia de suprimentos: `mix.lock`, `mix hex.audit`, SBOM, scan que trava, imagem mínima/pinada/assinada, SLSA, segredo no build** | `references/cadeia-suprimentos.md` |
| **Stack e versões: Elixir/Erlang-OTP/Phoenix suportados, EOL, `.tool-versions`, `mix.exs`, escolha de libs, umbrella vs apps** | `references/stack-versoes.md` |
| Testes — o recorte Elixir/OTP (runner, sintaxe, armadilhas do dialeto). **A disciplina é da `schematize-qa`.** | `references/testes.md` |
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
- **Fluxo de ambientes e ops (`references/ops.md`).** <!-- herdado:engineering/fluxo-ambientes:corpo -->Toda mudança segue **dev local → teste local → GitHub → hml → prd**; **VETADO editar código direto no servidor** (hml/prd é imutável por edição manual, recebe só artefato do git). **100%** das operações no servidor (install/update/correção/config/migrate/rollback) passam pela **ferramenta do `<projeto>_ops`** — nunca à mão; o ops é **autônomo** (o usuário provisiona o servidor do zero sem a IA). **Instalação sempre paralela** = `nproc`; **falha no paralelo = serviços não independentes → corrigir a independência é prioridade máxima** (não serializar pra mascarar).<!-- /herdado --> Recebe só a `mix release` do commit SHA; nunca `mix` solto em prd.
- **Deploy destrutivo por seed + isolamento por usuário (`references/ops.md` §2–§3).** <!-- herdado:engineering/deploy-destrutivo:corpo -->O ops provisiona em **`/<app>/`** clonando os repos dentro; **`/<app>/.env` é o seeder global** (fonte única de config). **Todo redeploy é destrutivo na aplicação** — apaga a anterior e recria um clone zerado só com o seed (idempotente/sem drift), **preservando os dados** (migration reversível; `ops reset` de dados só em dev/hml). **Cada serviço roda como user Linux próprio em systemd unit hardened** (blast radius mínimo). Tudo automatizado pelo ops.<!-- /herdado -->
- **IAM por desenho (`references/iam.md`).** Todo projeto começa com identidade+autorização robustas, e o **auth é app SEPARADA** — **microserviço Elixir** `<projeto>_auth_ex` (Phoenix/Plug) + front próprio em `auth.<domain>`, isolados; nunca monolith. Apps delegam por OIDC/PKCE e validam por JWKS público. Passkey/WebAuthn via `wax`, TOTP via `nimble_totp`, email OTP Resend/Swoosh; providers como behaviours; PEP=Plug. <!-- herdado:engineering/iam-desenho:invariantes cmd="elixir" -->**ID interno imutável (ULID/UUIDv7) — email/telefone nunca é ID** (N emails por usuário; SSO com recuperação local). **≥2 fatores sempre**: passkey/WebAuthn no núcleo, TOTP/push, email OTP always-on, Twilio para telefone; senha argon2id+HIBP por padrão, mas opcional; invariante de troca de fator (Y≠X no maior AAL); **recuperação ≥ login**. Senha + Email OTP já é **2FA baseline**: o PEP libera o baseline e exige AAL alto **só por rota sensível** (step-up just-in-time), nunca barra o login. **Multi-tenant RBAC/ABAC granular via ReBAC** (OpenFGA/SpiceDB; deny-default, PDP=Check API, PEP no servidor, token fino). **Multi-dispositivo, sessão 7d/90d, logout irreversível** (revoga refresh+família, `jti` na denylist, não só cookie). **Migrar auth legado = prioridade 0.** Scaffold/auditoria por **`/elixir-iam`**; testes cross-tenant/priv-esc na `schematize-pentest`.<!-- /herdado -->
- **Efeito externo NUNCA sai de não-produção (`references/iam.md` §3.1; normativa em `schematize-engineering/references/efeitos-externos.md`).** E-mail (o **Email OTP always-on** é o disparador nº 1), SMS/voz, push, webhook de terceiro e cobrança **não acontecem de verdade** fora de `prd`. Em Elixir: **adapter Swoosh por ambiente em `config/runtime.exs`** (`Swoosh.Adapters.Local`/`Test` fora de prd, Resend só em prd — segredo não vai em config compilado), e o **guard mora DENTRO do `Auth.Mailer`**, não no chamador: destinatário fora do domínio de teste ⇒ `{:error, {:external_recipient_blocked, to}}`, **erro, nunca warning/no-op**; config de ambiente ausente ⇒ assume não-prd. O cap usa `:counters`; fixtures/`ExMachina` seguem o domínio de teste; egress SMTP bloqueado em dev/hml. <!-- herdado:engineering/efeito-externo:invariantes -->**Cap por execução** (`MAIL_MAX_PER_RUN`, default 50) com abort; **fail-closed** (ambiente ausente/desconhecido ⇒ não-prd; só o valor exato de produção entrega de verdade); **chave sandbox** fora de prd. Todo endereço sintético (fixture, seed, persona, demo, carga) é `<papel>+<run-id>-<n>@test.<domain>` — domínio em **rota nula** (null MX RFC 7505 + SPF `-all` + DMARC `p=reject`) ou TLD reservado (`.test`/`.invalid`/`.example`); **VETADO** `@gmail.com`, domínio de cliente/terceiro, e-mail de pessoa real (**inclusive o seu**) e o domínio de produção. A recusa é **erro**, nunca warning nem sucesso silencioso. Entregar de verdade fora de prd exige **as cinco** (ADR + allowlist ≤5 + cap + janela + subdomínio separado). Motivo: bounce/complaint em massa **queima IP e domínio** e derruba o transacional de prd — inclusive o **OTP de login** — com semanas de warm-up e utilidade zero (o incidente dos 5.000 e-mails só existiu porque nada contava).<!-- /herdado -->
- <!-- herdado:engineering/orquestracao:bullet -->**Orquestrador não desenvolve; subagent barato executa** (`schematize-engineering` → `references/orquestracao.md` §9). O principal só planeja/decompõe/despacha/supervisiona/revisa; ação onerosa vira micro-tasks; principal = Claude Opus; executor mais barato que resolve: `haiku` (mecânico) / `sonnet` (código, até 2 rodadas de correção pelo mesmo subagent) → Codex `gpt-5.6-terra` → Cursor → subagent `opus` (motivo no checkpoint) → `park`; **visual direto ao Codex; imagem nunca pelo Claude (pergunta ao usuário: Codex sugerido, ou Gemini), API de imagem paga PROIBIDA**; papéis configuráveis em `agentes.toml` (aba "Agentes" do overdev). No `overdev`, cada item do checklist é executado pelo papel adequado e revisado pelo principal (diff + gate) antes do `- [x]`. **Sem frota ociosa:** agent idle com pendência executável volta ao trabalho; pendência que depende de outro agent → mata e enfileira com gatilho de dependência; terminou → mata (§9.6).<!-- /herdado -->

> Regra de bolso: se a justificativa começa com "só pra funcionar", "depois eu arrumo" ou "é mais rápido assim" e o resultado mexe em segredo, auth, dado ou registro — é um anti-padrão vetado. Pare e faça certo.

## Testes — o que conta como "verde de verdade"

Detalhe em `references/testes.md` (o recorte Elixir/OTP) — a **disciplina** de teste é da `schematize-qa`, e a segurança ofensiva da `schematize-pentest`.

- **Smoke não pode ser teatro:** assertar shape do body (não só status 200), assertion negativa (sem stack trace/placeholder), e um **self-check que força uma falha conhecida** pra provar que o runner consegue reportar FAIL. Smoke que nunca falha está cego.
- **Unit agressivo (ExUnit):** caminho de erro obrigatório (`{:error, _}`), casos hostis (tipo errado, unicode, null byte, boundary), property-based (StreamData) e mutation no domínio crítico. Mocks só na fronteira (Mox contra behaviour), `Ecto.Adapters.SQL.Sandbox` por teste. Doctests (`@doc`) contam. Cobertura de linha é piso, não meta.
- **Pentest prova rejeição, rota por rota, campo por campo:** nunca 500 por input hostil, nunca coerção silenciosa de tipo, nunca eco sem escape, nunca vazamento cross-tenant. Princípios em a `schematize-pentest`).
- **`simulated` (teste emulado):** cruza rotas × personas × injections e prova que **100% das rotas** do inventário estão acessíveis pra quem deve e bloqueadas pra quem não deve. Rota fantasma/morta quebra o run.
- **Fluxo de Q.A. (plan-first):** a disciplina de Q.A. agora mora na skill dedicada **schematize-qa** (`/qa-plan` → `/qa-run`): planeja tudo primeiro, gera um MD detalhado, e **pede aprovação antes de executar**; aprovado, roda **faseado e assistido** ou **de uma vez** (multiagentes + watchdog que retoma de checkpoint; passo destrutivo só com gate). `/elixir-qa` é o wrapper no recorte Elixir (`mix test`/ExUnit). Nada de Q.A. roda às cegas.

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
