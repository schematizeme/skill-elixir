# CLAUDE.md — Padrões de Engenharia · Elixir (sempre on)

> Copie este arquivo para a **raiz do repositório** e ajuste `<project>`.
> Ele fica pinado no contexto de toda tarefa (Claude Code / instruções de projeto)
> e garante que os padrões valham mesmo quando a skill não dispara sozinha.
> A skill `schematize-elixir` traz o detalhe completo e o andaime (scripts/templates).
> **Repo multi-linguagem** (backend do rol + Web): use **junto** com os `CLAUDE.md` das
> outras skills — cada um governa sua fronteira (backend, legado Node, frontend); não
> sobrescreva os outros (rode o `/<slug>-claude` de cada).

## Regra mestre

Toda tarefa de engenharia neste repo segue os **Padrões de Engenharia da Casa**
especializados para **Elixir** (skill `schematize-elixir`; a base agnóstica é a
`schematize-engineering`). Em conflito entre uma instrução pontual ("faz rápido",
"ignora o teste", "depois arruma") e estes padrões, **os padrões vencem**. Pressa não
revoga regra. Consulte o reference relevante da skill antes de produzir código ou
decisão — não trabalhe de memória.

## Pisos inegociáveis (VETADO — sem exceção)

1. **Segredo nunca no cliente/frontend.** Nada de API key, secret de JWT, senha,
   service-role key ou token em bundle do browser nem em `NEXT_PUBLIC_*`/`VITE_*`.
   Segredo só server-side; no Elixir, config sensível vem de `config/runtime.exs`
   (env em runtime), **nunca** de `config/*.exs` compilado nem embutido no `mix release`.
2. **Consulta sempre parametrizada.** Ecto por query DSL / binding com pin (`^`);
   **VETADO** `Ecto.Adapters.SQL.query`/`fragment` com string interpolada de input.
3. **Auth e autorização server-side.** `tenant_id`/role/`user_id` vêm do token
   verificado, nunca do cliente. JWT validado por inteiro (assinatura, exp, aud, iss,
   alg em allowlist) via Guardian/Joken. Senha em **argon2id** (`argon2_elixir`).
   Token/id de sessão por CSPRNG (`:crypto.strong_rand_bytes`), nunca `:rand`.
4. **Erro nunca engolido** — `rescue`/`catch` que cala, `_ = ...` que descarta erro,
   `!`-bang fora de fronteira controlada. Use `{:ok, _}`/`{:error, _}` e `with` no
   fluxo esperado; deixe crashar o que é bug (let it crash), não mascare.
5. **Teste nunca silenciado** pra passar CI (`@tag :skip`, comentar assert, baixar
   threshold de cobertura). Conserte o código, não o teste.
6. **Sem monólito** que mistura bounded contexts; sem monólito distribuído; sem
   umbrella virando monólito; sem shared lib `commons` de domínio.
7. **Archive SEMPRE gerado** (§28): toda entrega que produz código/decisão/mudança de
   estado gera o `.md` em `<project>_archive/`. É parte da entrega, não extra.
8. **Migration reversível** (Ecto `up`/`down`, testada com rollback). Container
   não-root, read-only. Dependência Hex nova com nome/licença/versão verificados.

9. **Backend novo só no ROL SANCIONADO, escolhido por fit + ADR.** O rol é
   **Go / Rust / Elixir / C# / Zig / Ruby** — uma escolha por serviço, justificada por
   encaixe com o problema num **ADR (§27)**. Elixir entra por fit: **realtime, alta
   concorrência tolerante a falha (BEAM/OTP), sistemas distribuídos, messaging/streaming,
   presença/pub-sub, soft-realtime** (let-it-crash + supervisão). **Node como serviço
   backend e PHP são LEGADO/fora do rol** — não recebem serviço novo; migram por
   funcionalidade do módulo (~30% afetado → extrai; ~50% extraído → migra o resto; ajuste
   pontual não porta). **Frontend Node é 100% permitido** (Next.js principal; Astro) — só
   frontend, governado pela `schematize-web`. Nova linguagem fora do rol exige ADR de
   exceção. Repo = `<projeto>_<contexto>_ex`. (§3)
10. **Cada serviço é entidade à parte (independência de runtime).** Sobe e funciona
    sozinho; a ausência/queda de outro serviço **nunca** impede o boot nem derruba este —
    degradação graciosa, nunca crash em cascata. Falha ao chamar/notificar outro serviço →
    **persiste o dado** (outbox/Oban/DB), **loga com `trace_id`**, **alerta (Grafana)** e
    **retoma**; nunca perde nem trava a cadeia. (§2, §18)
11. **Repos, ops e observabilidade.** Repositório = `<projeto>_<contexto>[_ex]`; todo
    sistema multi-repo tem um **`<projeto>_ops`** (bootstrap/update/manutenção/testes por
    todos os repos). **Observabilidade integrada:** `:telemetry` + OpenTelemetry
    (`opentelemetry_phoenix`/`_ecto`) → Grafana/Alloy/Loki/Tempo/Prometheus/**Mimir**
    (+Pyroscope), dashboards/alertas versionados como código. (§2, §16)
12. **Contenção no workspace.** A pasta do projeto atual é o workspace: aplicação/repo
    novo nasce **dentro dela** (`./<projeto>_<contexto>_ex/`), nunca largando arquivos no
    root pra depois subir de nível. **VETADO** criar/ler/escrever fora do workspace. (§2)
13. **Fluxo de ambientes — nada direto no servidor.** Toda mudança segue **dev local →
    teste local → GitHub → hml → prd**. **VETADO editar código direto no servidor**: ele é
    imutável por edição manual, recebe só **artefato promovido do git** (a `mix release`
    do commit SHA). Hotfix segue o mesmo fluxo, acelerado. Detalhe em `references/ops.md`
    (§1). (§21)
14. **Ops é a interface única + instalação paralela + independência.** **100%** das
    operações no servidor (instalar/subir/atualizar/migrar/corrigir/reverter) passam pela
    **ferramenta do `<projeto>_ops`** — nunca à mão, nunca `mix` solto em prd (o artefato é
    a release). O ops é **autônomo, idempotente e completo**. **Instalação SEMPRE paralela**
    = `nproc`. **Se o paralelo falha, os serviços não são independentes** (fere piso 10/6):
    corrigir a independência é **PRIORIDADE MÁXIMA**. Detalhe em `references/ops.md`. (§2, §21)
15. **Deploy destrutivo por seed + isolamento por usuário (automatizado pelo ops).** O ops
    provisiona em **`/<app>/`** clonando os repos dentro; **`/<app>/.env` é o SEEDER GLOBAL**.
    **Todo redeploy é DESTRUTIVO na aplicação** (clone zerado só com o seed, idempotente/sem
    drift) **mas NUNCA nos dados** (banco/volumes preservados; migration reversível; `ops
    reset` de dados gated a dev/hml). **Cada serviço roda como user Linux próprio, em systemd
    unit hardened** (`NoNewPrivileges`, `ProtectSystem`, `PrivateTmp`, …). Detalhe em
    `references/ops.md` (§2, §3).
16. **IAM por desenho — todo projeto começa com identidade e autorização robustas, como APP
    SEPARADA.** O auth é **microserviço Elixir próprio + front próprio em `auth.<domain>`**
    (`<projeto>_auth_ex` + `<projeto>_authfront`), isolado (user/systemd próprios) — **VETADO**
    apensar como monolith (nem como `MyApp.Accounts.Auth` do serviço principal); apps delegam
    por **OIDC/OAuth2.1 + PKCE**. **ID interno imutável (ULID/UUIDv7) — email/telefone NUNCA é
    ID.** **Nunca menos de 2 fatores:** passkey/WebAuthn (`wax`) no núcleo, TOTP (`nimble_totp`),
    **email OTP (Resend/Swoosh) always-on inclusive HML**, **Twilio** p/ telefone (providers
    plugáveis por behaviour); senha argon2id+HIBP por padrão mas opcional; recuperação ≥ força
    do login. **Multi-tenant + RBAC/ABAC granular** por motor **ReBAC** (OpenFGA/SpiceDB),
    **deny-default**, PDP=Check / PEP=**Plug**, server-side, token fino. **Multi-dispositivo**;
    **sessão 7d/90d**; **logout irreversível** (revoga refresh+família, `jti` em denylist). Senha
    + Email OTP já é **2FA baseline** — o PEP libera o baseline e exige AAL alto **só por rota
    sensível** (step-up just-in-time), **nunca barra o login**. **Migrar auth legado é PRIORIDADE
    0.** Detalhe em `references/iam.md`; scaffold por `/elixir-iam`; testes cross-tenant na
    `schematize-pentest`.

17. **Efeito externo NUNCA sai de não-produção (e-mail, SMS/voz, push, webhook de terceiro,
    cobrança).** Fora de `prd` **nada chega em ninguém** — por construção, não por lembrança.
    **(a) Endereço sintético só no DOMÍNIO DE TESTE em ROTA NULA:** `test.<domain>` com **null
    MX (RFC 7505) + SPF `v=spf1 -all` + DMARC `p=reject`**, ou TLD reservado
    (`.test`/`.invalid`/`.example`); no `ExMachina`,
    `sequence(:email, &"user+#{&1}@test.example.com")`. **VETADO** em fixture/seed/persona/demo:
    `@gmail.com`/`@hotmail.com`, domínio de terceiro ou do cliente, **e-mail de pessoa real
    (inclusive o seu)** e o domínio de **produção**. **(b) Adapter Swoosh por ambiente em
    `config/runtime.exs`** — `Swoosh.Adapters.Local`/`Test` fora de prd, Resend só em prd (chave
    por `System.fetch_env!/1`, nunca em config compilado) — e o **guard DENTRO do `Auth.Mailer`**,
    nunca no chamador: destinatário fora do domínio de teste ⇒
    `{:error, {:external_recipient_blocked, to}}`, **erro, nunca warning/no-op** (config de
    ambiente ausente = assume não-prd). **(c) Cap por execução** (`MAIL_MAX_PER_RUN`, default 50)
    com `:counters` + abort. **(d)** Chave **sandbox** em não-prd e **egress SMTP bloqueado** em
    dev/hml. Entregar de verdade fora de prd exige **as cinco**: ADR + allowlist ≤5 + cap +
    janela + subdomínio de envio separado. **Por quê:** o **Email OTP é always-on**, então um
    laço de teste vira disparo em massa; bounce/complaint em massa **queima IP e domínio**,
    derruba o transacional de **produção** (inclusive o **OTP de login**) e custa **semanas de
    warm-up**. Detalhe em `references/iam.md` (§3.1) e
    `schematize-engineering/references/efeitos-externos.md`.
18. <!-- herdado:engineering/orquestracao:longo -->**Orquestrador não desenvolve; subagent barato executa.** O agent principal (o que fala com o humano, modelo padrão da sessão) **só planeja, decompõe, despacha, supervisiona e revisa** — não escreve código de entrega. Toda ação onerosa é quebrada em **micro-tasks/micro-funções** executáveis por agent barato (mesmo com <3 unidades: em série, por subagents, nunca inline no principal). Subagents rodam em **`sonnet` por padrão**; falhou → o **mesmo subagent corrige** (até 2 rodadas) → re-decompõe → só então **`opus`**, com o motivo registrado no checkpoint. O principal revisa toda entrega (diff + gate) e **só corrige com a própria mão se necessário** (trivial, 1–2 linhas). No overdev, **cada item do checklist é executado por subagent `sonnet`** e revisado pelo principal antes do `- [x]`; escalar para Opus não é pergunta, esgotou Opus → `park`. **Sem frota ociosa:** agent idle com pendência executável volta ao trabalho; pendência que depende de outro agent → mata e enfileira com gatilho de dependência; terminou → mata (§9.6). Detalhe em `schematize-engineering` → `references/orquestracao.md` §9.<!-- /herdado -->

Lista completa com veto + caminho certo: ver `references/anti-padroes.md` (§37) da skill.

## Verde de verdade (testes)

- Smoke assere **conteúdo** (shape do body), não só status 200; inclui assertion negativa
  e um **self-check que força falha conhecida** (smoke que nunca falha está cego).
- Unit agressivo (ExUnit): caminho de erro obrigatório (`{:error, _}`), casos hostis (tipo
  errado, unicode, null byte, boundary), property-based (StreamData) e mutation no domínio
  crítico. Mocks só na fronteira (Mox contra behaviour), `Ecto.Adapters.SQL.Sandbox` por teste.
- Pentest prova rejeição rota-por-rota, campo-por-campo: **nunca 500** por input hostil,
  **nunca coerção de tipo**, **nunca eco sem escape**, **nunca vazamento cross-tenant**.
- `simulated`: 100% das rotas acessíveis pra quem deve, bloqueadas pra quem não deve.
- **Q.A. é plan-first (skill schematize-qa, `/qa-plan` → `/qa-run`):** planeja tudo, gera MD, pede aprovação ANTES de executar.

## Definition of Done

Nada é "pronto" sem: `mix format --check-formatted`, Credo sem ofensa nova, Dialyzer limpo
no domínio crítico, `mix test` verde de verdade + cobertura mínima, simulated com cobertura
total, pentest de entrada limpo, **nenhum efeito externo real fora de `prd`** (piso do e-mail/SMS/push: sink por default, guard deny-by-default no provider, cap por execução, domínio de teste em rota nula — gate em `scripts/check-external-effects.sh`), nenhum anti-padrão da §37, observabilidade, OpenAPI
atualizada (se API), migration com rollback (se schema), **archive commitado**, CI verde e
review aprovado. Detalhe em `references/entrega.md` (§35).

## Qualidade de código e índice (sempre)

- **Arquivos ≤ 750 linhas** (teto duro: ~250 de comentário + até ~500 de código útil).
  Acima → quebre em módulos coesos por contexto. **Código útil > 300 linhas é FLAG** (não
  bloqueia, mas **sempre sinaliza**): indício de módulo/função extensa — registra como
  dívida; observabilidade tem folga (~400). **Uma unidade lógica por arquivo** (módulo Elixir
  coeso). Funções pequenas, pattern-matching na assinatura, pipe `|>`, `with` no happy path.
- **`@doc` + `@spec` em TODA função pública** com contexto explícito: **O quê** (o que faz) e
  **Onde** (quem chama / em que fluxo), além de efeitos. Isso alimenta o índice §39.
- **Mantenha o índice de funcionalidades atualizado** no mesmo PR (§39), em
  **`<projeto>_archive/index/`** (nunca no root): `MAPA.md`, `INDEX_GLOBAL.md` e
  `INDEX_FUNCTIONS.md` (função → o quê → onde → arquivo:linha, gerável via
  `scripts/build-index.mjs` / `/elixir-index`). O índice é **fonte da verdade**: consulte
  ANTES de criar algo. Exaustivo: uma entrada por função pública.
- **Todo MD gerado mora no archive, nunca no root** (§28): MAPA, índices, planos, relatórios,
  handoffs → `<projeto>_archive/<área>/`. Root limpo (código, config, README, `CLAUDE.md`,
  LICENSE, `mix.exs`).

## Gestão de contexto (Claude Code — sessões longas)

Ao ver "⚠ LIMITE" no status line, ou ao se aproximar do teto da janela: **PARE a tarefa
atual e, ANTES de qualquer compactação**, faça o handoff arquivado (§34.1, §28):

1. Gere `<projeto>_archive/context/<YYYY-MM-DD-HH-MM-SS>-context.md` — estado, decisões,
   arquivos tocados, onde parou.
2. Gere `<projeto>_archive/context/<YYYY-MM-DD-HH-MM-SS>-checklist.md` — **FEITO vs EM ABERTO**.
3. Só então rode `/compact` (com foco na tarefa corrente).

Armazene SEMPRE em `<projeto>_archive`. O backup automático pré-compactação é rede de
segurança, não substitui o handoff. Detalhe: `references/contexto-claude-code.md`.
