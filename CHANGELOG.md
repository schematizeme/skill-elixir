# Changelog — schematize-elixir

Formato: [Keep a Changelog]; versionamento: SemVer. Esta skill é a **especialização
para Elixir** (Phoenix/Ecto/OTP sobre a BEAM) da base agnóstica `schematize-engineering`:
os pisos são os mesmos de toda a casa; o que muda é o ferramental, o modelo de
concorrência e o ecossistema. Frontend delega ao `schematize-web`; teste de segurança
na `schematize-pentest`.

[Keep a Changelog]: https://keepachangelog.com/pt-BR/1.1.0/

## [0.1.0] — 2026-08-15

Primeiro release da `schematize-elixir` — Elixir posicionado no **rol sancionado** de
backend (Go/Rust/Elixir/C#/Zig/Ruby, escolha por fit + ADR), por encaixe em **realtime,
alta concorrência tolerante a falha (BEAM/OTP), sistemas distribuídos, messaging/streaming
e presença/pub-sub**.

### Adicionado

- **`SKILL.md`** — porta de entrada: posicionamento de Elixir no rol sancionado, tabela
  dos 10 comandos `/elixir-*`, mapa dos 16 references, pisos inegociáveis (VETADO)
  especializados a Elixir, "verde de verdade" (testes) e andaime pronto.
- **16 references**, especializados a Elixir a partir da base agnóstica:
  - `arquitetura.md` — DDD, Phoenix contexts como bounded contexts, umbrella vs apps,
    anti-monólito, **rol de linguagem sancionada** (§3) com Elixir posicionado por fit.
  - `concorrencia.md` — **novo**: modelo de atores do BEAM/OTP — processos, GenServer,
    árvore de supervisão + estratégias, let-it-crash, Task/Agent, Registry/PubSub,
    backpressure (GenStage/Broadway/Oban), distribuição (nós BEAM), shutdown/drain.
  - `padroes-codigo.md` — limites de código (≤750 / flag >300 úteis), uma unidade lógica
    por módulo, `@doc`/`@spec` em toda função pública (alimenta o índice §39), idiomas
    Elixir (pattern-matching, pipe, `with`, tuplas `{:ok,_}`/`{:error,_}`, `mix format`,
    Credo, Dialyzer).
  - `dados-eventos.md` — Ecto (changesets, migrations reversíveis, `Ecto.Multi`), Broadway/
    GenStage, Oban, Phoenix.PubSub, cache, resiliência, outbox.
  - `seguranca.md` — Ecto parametrizado, segredos via `config/runtime.exs`, JWT via
    Guardian/Joken, argon2id (`argon2_elixir`), CSPRNG (`:crypto.strong_rand_bytes`),
    CSRF/headers, LGPD, multi-tenancy.
  - `iam.md` — IAM da casa como **app separada** (`<projeto>_auth_ex`, Phoenix/Plug),
    OIDC/PKCE, ID≠email, ≥2 fatores (wax/nimble_totp/Swoosh-Resend/Twilio), ReBAC
    (OpenFGA/SpiceDB) com PEP=Plug, sessão longa, logout irreversível, risco adaptativo.
  - `cadeia-suprimentos.md` — `mix.lock`, `mix hex.audit`, scan que trava CI, SBOM,
    imagem mínima/pinada/assinada com `mix release`.
  - `stack-versoes.md` — **novo**: versões suportadas de Elixir/Erlang-OTP/Phoenix, EOL,
    `.tool-versions`, política de bump, escolha de libs núcleo.
  - `testes.md` + `testes-execucao.md` — ExUnit, StreamData, Mox na fronteira,
    `Ecto.Adapters.SQL.Sandbox`, doctests, smoke self-check, `simulated`, Q.A. plan-first,
    CI com `mix`.
  - `observabilidade.md` — `:telemetry` + OpenTelemetry, Logger estruturado, stack LGTM,
    healthchecks, performance da BEAM.
  - `operacao.md` + `ops.md` — deploy via `mix release`, fluxo de ambientes, `<projeto>_ops`
    como interface única, instalação paralela (`nproc`), deploy destrutivo por seed.
  - `entrega.md`, `anti-padroes.md`, `contexto-claude-code.md` — DoD/§39, lista de
    anti-padrões vetados (com "novo backend fora do rol / sem ADR de escolha"), e gestão
    de contexto em sessões longas no Claude Code.
- **10 comandos** `/elixir-*` (`help`, `cc`, `handoff`, `claude`, `qa`, `review`, `iam`,
  `index`, `ops`, `load`), namespaced sem conflito com as outras skills.
- **`assets/CLAUDE.md`** — arquivo "sempre-on" da raiz, com os pisos pinados e a política
  de linguagem sancionada embutida (Elixir posicionado por fit).
- **Andaime** — `scripts/` (test kit, `build-index.mjs`, hooks de contexto) e `assets/`
  (templates ADR/TASK/RUNBOOK/PR, INDEX, CI/lint/hooks especializados a Elixir).
