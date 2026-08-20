# Changelog — schematize-elixir

## [0.2.0] — 2026-08-20
Piso "efeito externo NUNCA sai de não-produção" no recorte Elixir/Phoenix (Swoosh).
### Adicionado
- **`SKILL.md`**: novo piso inegociável — efeito externo (e-mail/SMS/push/webhook/cobrança) não acontece fora de `prd`; adapter Swoosh por ambiente em `config/runtime.exs`, guard dentro do `Auth.Mailer`, cap por execução, domínio de teste em rota nula. Nova linha no mapa de references.
- **`references/iam.md` §3.1** — *Disparo do Email OTP fora de prd*: seleção de adapter em `config/runtime.exs` (`Swoosh.Adapters.Local` com `Plug.Swoosh.MailboxPreview` / `Swoosh.Adapters.Test` fora de prd, `Resend.Swoosh.Adapter` só em prd com `System.fetch_env!/1`), `Auth.Mailer.Transport` privado + `Auth.Mailer.deliver/1` com guard deny-by-default (`{:error, {:external_recipient_blocked, to}}`, `to`/`cc`/`bcc`, endereço malformado bloqueado, env ausente ⇒ não-prd), `Auth.Mailer.Quota` com `:counters`/`:persistent_term` (`MAIL_MAX_PER_RUN`, default 50) e suite ExUnit que **espera a recusa** (`assert_no_email_sent/0`, `assert_email_sent/1`, abort do cap). Novo item no checklist de DoD do IAM.
- **`references/testes-execucao.md` §22.5** — seeds/personas com e-mail só no domínio de teste (`sequence(:email, ...)` do `ExMachina`), veto a caixa real com gate `grep` no CI, e o teste que vê o vermelho do guard.
- **`references/anti-padroes.md`** — nova seção *Efeitos externos* com o item **50** (mandar de verdade fora de prd) e o caminho certo.
- **`assets/CLAUDE.md`** — piso **17** (efeito externo fora de não-produção, recorte Swoosh).
### Mudado
- **`description`** do frontmatter passa a listar o piso de efeito externo entre os inegociáveis.

## [0.1.2] — 2026-08-18
Correção da contradição do muro pré-login de IAM (alinha ao `iam.md` da schematize-engineering).
### Mudado
- **/elixir-iam**: removido o "2º fator forte obrigatório antes do acesso pleno" e o "força 2º fator no 1º login" — o muro pré-login / deadlock de bootstrap VETADO pela norma. Agora senha+Email OTP = 2FA baseline; fator forte é nudge + step-up just-in-time.


Formato: [Keep a Changelog]; versionamento: SemVer. Esta skill é a **especialização
para Elixir** (Phoenix/Ecto/OTP sobre a BEAM) da base agnóstica `schematize-engineering`:
os pisos são os mesmos de toda a casa; o que muda é o ferramental, o modelo de
concorrência e o ecossistema. Frontend delega ao `schematize-web`; teste de segurança
na `schematize-pentest`.

[Keep a Changelog]: https://keepachangelog.com/pt-BR/1.1.0/

## [0.1.1] — 2026-08-18
Q.A. repointado para a skill dedicada **schematize-qa**.
### Mudado
- **`/elixir-qa` virou wrapper fino** da **schematize-qa** (`/qa-plan` → `/qa-run`) no recorte Elixir (`mix test`/ExUnit). Referências ao antigo **§22.9** removidas de `SKILL.md`, `references/testes-execucao.md`, `assets/CLAUDE.md` e `/elixir-help`.

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
