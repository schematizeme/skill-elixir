# IAM — Identidade e Autorização da casa (piso inegociável, angle Elixir)

Piso normativo de **identidade, autenticação e autorização** da casa, especializado para
**backend Elixir** (o serviço de auth é um microserviço Elixir sobre Phoenix/Plug/OTP).
**Todo projeto começa com um IAM robusto por desenho** — segurança é inegociável. A base
agnóstica vive na `schematize-engineering` (`references/iam.md`); aqui ela ganha a topologia
de serviço, as libs do Hex e os padrões OTP da casa. O teste adversarial vive na
`schematize-pentest`.

Princípios-âncora: **separar identidade de autorização**; **nunca menos de 2 fatores**
(senha + Email OTP **já conta** como 2FA baseline — fator forte é incentivado e just-in-time,
**nunca muro pré-login**); **força adaptável ao risco** (2FA→3FA + negação deceptiva sob
suspeita); **recuperação tão forte quanto o login**; **deny-by-default**; **enforcement sempre
no servidor**. O buraco clássico é ter 2FA no login e um reset por 1 email que passa por
cima — aqui isso é vetado.

> **Pow/Assent/`mix phx.gen.auth` NÃO são a solução completa.** `mix phx.gen.auth` scaffolda
> um cadastro/login com sessão e `Ecto.Changeset`; **Pow** cobre registro/reset/lembrar;
> **Assent** cobre OAuth2/OIDC de terceiros. Tudo isso **scaffolda partes**, mas **não
> substitui o desenho da casa**: app de auth SEPARADA em `auth.<domain>`, ID≠email, ≥2 fatores
> por desenho, ReBAC multi-tenant, sessão longa e logout irreversível. Use-os como peças
> internas do `<projeto>_auth_ex`, nunca como "o auth já está pronto".

## 1. Topologia — auth é uma APLICAÇÃO SEPARADA (microserviço Elixir)

- **A autenticação é um serviço próprio, com link próprio e front próprio**, servido em
  **`auth.<domain>`**. **VETADO** apensar o auth ao escopo principal como monolith — nem
  como um **contexto `MyApp.Accounts.Auth` embutido** no app principal.
- **Microserviço de auth em Elixir** (`<projeto>_auth_ex`, Phoenix/Plug sobre OTP) + **front
  de auth** próprio (`<projeto>_authfront`), com **repo, deploy, user Linux e systemd/container
  isolados** por conta própria (casa com o isolamento por app do `ops.md` §3). Cada um roda
  como **`mix release`** com user Linux próprio. Comprometer o app principal **não** compromete
  o IdP.
- **O app principal (e todo cliente) delega ao auth por OIDC/OAuth2.1 + PKCE:** redireciona
  pra `auth.<domain>`, recebe tokens de volta. O `<projeto>_auth_ex` é o **IdP da casa**
  (self-hosted, consumido por N apps) — expõe os endpoints padrão (`/authorize`, `/token`,
  `/introspect`, `/revoke`, `/.well-known/openid-configuration`, `/.well-known/jwks.json`).
- **Chave de assinatura de token vive SÓ no `<projeto>_auth_ex`.** Ele expõe **JWKS**
  (`/.well-known/jwks.json`); consumidores validam por **JWKS público** (ex.: `joken_jwks`
  buscando e cacheando o JWKS, ou `JOSE`), **nunca guardam a chave privada**. A assinatura
  (Ed25519/EdDSA ou RS256) só acontece dentro do auth; a rotação é publicada via `kid`. Os
  segredos vêm do **`config/runtime.exs`** lendo o secret manager, nunca de `config/*.exs`
  compilado (casa com `seguranca.md` §13).

## 2. Modelo de identidade

- **ID interno imutável e opaco** (ULID/UUIDv7 — libs `ecto_ulid`/`uniq`) é o `sub`. **Email e
  telefone NUNCA são ID** — são *identificadores* ligados ao usuário, cada um com estado de
  verificação. No schema Ecto/Postgres: **`users(id)`** + **`identifiers(user_id, kind, value,
  verified_at)`** 1..N, **nunca** email como PK. O `binary_id` do schema é ULID/UUIDv7, gerado
  no domínio, não `bigserial` sequencial exposto.
- **Identificadores 1..N por usuário** (emails, telefones, identidades SSO, passkeys, apps,
  chaves FIDO2). **Ter mais de um email é incentivado** (resiliência a brick de provedor).
- **Identificador só vale verificado** — não loga nem recupera sem verificação (`verified_at`
  não-nulo).
- **SSO nunca é ponto único de falha:** cadastro via SSO (via **Assent**) **força ≥1 fator de
  recuperação local** (email de recuperação + códigos de backup), pra provedor banido ≠ conta
  perdida.
- **Account-linking explícito:** SSO chegando com email já verificado em outra conta →
  linkar vs. bloquear **com confirmação** (anti-takeover). Nunca linkar por email não
  verificado.
- **Nudge de email secundário (anti-brick):** com só 1 email, a UI **sugere adicionar um
  secundário**. **Detecta o provedor** do atual (gmail / hotmail-outlook / yahoo /
  próprio-corporativo) e **recomenda que o secundário seja preferencialmente de OUTRO
  provedor**, com um **"i" de tooltip no hover**: *"Um segundo email, de preferência em outro
  provedor, garante que você não perca o acesso caso perca acesso a este email."* Sugestão,
  não obrigação. (Regra do domínio, exposta pelo auth ao `authfront`.)

## 3. Fatores e níveis de garantia (AAL — NIST 800-63B)

Classificar a **força** de cada fator permite "email sempre disponível" sem abrir mão de
segurança: operação sensível exige fator forte; email/SMS servem de fallback.

| Tier | Fatores | Uso |
|---|---|---|
| **Alto (phishing-resistant)** | **Passkey/WebAuthn (núcleo)**, chave FIDO2, push aprovado no app | Ops sensíveis: trocar fator, admin, cross-tenant, billing, recuperação |
| **Médio** | TOTP (app autenticador), senha + posse | Login + 2º fator |
| **Baixo (fallback)** | **Email OTP (Resend)**, **SMS/voz (Twilio)** | **É o 2º fator baseline da conta** (senha+OTP = 2FA); sempre disponível; **não** autoriza ação sensível sozinho (aí exige step-up forte) |

- **Passkey/WebAuthn é núcleo** (não roadmap): já é "2 fatores num" (dispositivo +
  biometria), phishing-resistant. Em Elixir, use a lib **`wax`** (registro/asserção WebAuthn).
- **Email OTP (Resend via `Swoosh`) ligado por padrão, inclusive em HML** — só o operador
  desliga.
- **Twilio por padrão** para verificação de telefone e 2FA por SMS/voz (`ex_twilio` ou cliente
  HTTP com `Finch`/`Req`).
- **Provedores plugáveis por behaviour:** o core depende de **behaviours**, não de SDK:
  ```elixir
  defmodule Auth.EmailProvider do
    @callback send_otp(to :: String.t(), code :: String.t()) :: :ok | {:error, term()}
  end
  defmodule Auth.SmsProvider do
    @callback send_otp(to :: String.t(), code :: String.t()) :: :ok | {:error, term()}
  end
  defmodule Auth.PushProvider do
    @callback request_approval(device_token :: String.t(), challenge :: map()) ::
                {:ok, Approval.t()} | {:error, term()}
  end
  ```
  As impls (`ResendEmailProvider`, `TwilioSmsProvider`) são **selecionadas por config**
  (`config :auth, :email_provider, ResendEmailProvider`), trocáveis sem tocar no core. Chamadas
  de rede são resilientes (timeout, retry+backoff+jitter, store-and-forward via **Oban** em
  falha — casa com `dados-eventos.md`).
- **TOTP** por **`nimble_totp`** (geração/validação de código com janela).
- **Senha por padrão, opcional por escolha:** o usuário **cria senha no cadastro** (padrão
  cultural; **argon2id** via **`argon2_elixir`** com custo adequado + verificação contra base de
  vazadas/HIBP por k-anonymity), mas o **seletor de modos de autenticação permite marcá-la como
  opcional** e viver de passkey/OTP/app. O `Argon2` já é CPU-bound e roda no processo da request
  sem bloquear o scheduler do BEAM indevidamente; para picos, isole num pool de tarefas.
- **2FA por desenho desde o cadastro — senha + Email OTP JÁ é 2FA (fraco, porém válido):**
  a conta **nasce com dois fatores obrigatórios** (senha + código no email verificado,
  always-on) e **já é segura para o baseline**. **VETADO** tratar senha+OTP como "sem 2FA" e
  **barrar o login** até enrolar um fator forte — é o **círculo infinito**. Em Elixir: o **Plug**
  de sessão **libera o acesso baseline** (sessão de AAL médio); **não** exige AAL alto em toda
  rota.
- **Fator forte é INCENTIVADO + just-in-time, nunca muro pré-login:** app OTP / passkey / chave
  são **nudge** e **exigidos só na operação sensível** (o PEP checa o AAL mínimo **por rota
  sensível** e dispara **step-up**) e **escalados sob risco** (§9). Enrolar um fator forte usa o
  Email OTP como verificação (Y≠X, §4): sem deadlock. A ausência de fator forte **degrada o
  sensível** (`403 step_up_required`), não **bloqueia o baseline**.

## 4. Fluxos

**Onboarding:** cita um email → **verifica** → **cria senha** (ou já passkey/app) → **pronto:
2FA baseline (senha + Email OTP) e acesso baseline pleno**. Só **depois**, já dentro, o sistema
**sugere** (nudge, não obriga) reforçar: 2º email de backup + fator forte. **Nunca se barra o
acesso por não ter fator forte** — ele é pedido *just-in-time* na 1ª ação sensível (step-up)
ou sob risco (§9).

**Login:** (1) sem app de 2FA ativo → **OTP por email** (mesmo sem nada habilitado); (2)
com app → **pergunta app ou email**; (3) com vários fatores (passkey/telefone/app) →
**lista todos e o usuário escolhe** qual usar. App = push-approval ou TOTP.

**Gestão de fator — invariante único:**
> **Para mutar o fator X, apresente um fator Y ≠ X, no maior AAL disponível.**
- Desativar/trocar **app** → verifica por **email** (ou outro ≠ app).
- Trocar/adicionar **email complementar** → exige o **app**.
- Add/remover **chave ou telefone** → mesmo princípio, **lista qual usar**.
- Toda mudança **notifica todos os canais verificados**; remover o **último fator forte** =
  **ação com atraso cancelável** (janela pra abortar se for ataque) — implementada como **job
  Oban agendado**, cancelável até disparar.

**Recuperação:** múltiplos caminhos independentes (vários emails, códigos de backup
offline, telefone). **Força ≥ login** (2 fatores ou processo com atraso + revisão),
rate-limit agressivo, tudo auditado. **Reset nunca é bypass de 1 fator.**

## 5. Multi-tenant + RBAC/ABAC — motor ReBAC (estilo Zanzibar)

- **Identidade global, autorização por tenant:** um usuário (1 identidade) pertence a **N
  tenants** via **membership**, com papéis **diferentes por tenant**.
- **Motor de relação (ReBAC), ex. OpenFGA/SpiceDB** — hand-rolar authz em Elixir (um `case`
  gigante de papéis) é onde vazam privilégios. O `<projeto>_auth_ex` **não implementa o motor**:
  fala com o OpenFGA/SpiceDB via client gRPC/HTTP. Autorização em **tuplas** `(objeto, relação,
  usuário/userset)`:
  - `tenant:acme#member@user:01H…`
  - `role:acme/finance-approver#assignee@user:01H…`
  - `invoice:987#parent@tenant:acme` (recurso parenteado ao tenant)
  - permissão computada por *relation rewrite* (member do tenant **E** assignee de papel
    que concede a permissão).
- **Escrita de tuplas** (membership, atribuição de papel, parentesco de recurso) acontece no
  contexto de domínio via cliente do motor, **transacional com o efeito de negócio** (padrão
  **outbox** via Oban quando o motor é externo — nunca dual-write solto).
- **RBAC granular:** permissão = **`recurso:ação`** (`invoice:approve`, `user:invite`);
  papéis-padrão (owner/admin/member/viewer) **+ papéis 100% customizados e granulares por
  tenant** (viram relations/usersets). Deve ser possível criar cargos extremamente granulares
  e atribuí-los.
- **ABAC por cima:** condições sobre atributos (usuário/recurso/contexto — hora, IP, risco)
  via **conditional/contextual tuples** (ex.: aprova invoice < 10k do próprio setor).
- **PDP/PEP separados:** PDP = **Check API do motor**; **PEP = um `Plug`** em cada serviço que
  chama o Check antes do controller/LiveView (`plug Auth.RequirePermission, "invoice:approve"`).
  **Deny-by-default** (erro/timeout do PDP = nega), enforcement **server-side**, **todo endpoint
  mapeia 1 permissão**. O `tenant_id`/`sub`/role saem **do token verificado** (via `Guardian`),
  nunca do body/header/param do cliente (§ `seguranca.md` §15).
- **Token fino:** carrega `sub`/tenant/sessão/AAL — **sem** a lista de permissões (evita authz
  stale em token longo); decisão consultada no motor e cacheada com TTL curto (**`Cachex`**),
  invalidada por evento de mudança de papel.
- **Toda decisão de authz é logada** (quem / o quê / allow-deny / política), com `trace_id`
  em `Logger.metadata` (casa com a observabilidade da casa) — auditoria + rotina de testes.

## 6. Sessão, multi-dispositivo e logout

- **Multi-dispositivo de 1ª classe:** N sessões simultâneas por usuário, cada uma atada a
  um **dispositivo** (fingerprint + rótulo amigável "Chrome no Windows", IP/geo, último
  uso). Nenhuma sessão derruba a outra. O **session store** (Postgres via Ecto + Redis via
  **Redix**/`Cachex`) guarda uma linha por sessão com `refresh_family_id`, `device_id`, `jti`
  corrente.
- **View de dispositivos/sessões:** lista os ativos e **permite remover um** (revoga a
  sessão daquele device), além de **"sair de todos"**.
- **Sessão longa por padrão (fim do "15 min e é chutado"):** o access token continua curto
  (ex.: 15 min) **mas com refresh silencioso** — para o usuário, a sessão **persiste 7 dias
  por padrão**. No login, **pergunta se o dispositivo é confiável**; se sim, **90 dias**.
  Ops sensíveis ainda pedem **step-up fresco** em AAL alto — sessão longa não enfraquece.
- **Refresh rotativo com detecção de reuso** (reusou um refresh já rotacionado → revoga a
  **família** inteira). O refresh token é opaco (**`:crypto.strong_rand_bytes`**), hasheado no
  store; a família e o `jti` são rastreados server-side.
- **Botão "Sair" bem visível → kill IRREVERSÍVEL da sessão:** não basta apagar o cookie —
  o handler de logout **revoga o refresh token (e a família), apaga o registro de sessão
  server-side, joga o `jti` na denylist (Redis via Redix / DB) até expirar e desassocia o
  push token do device**. Depois do logout, aquela sessão é irrecuperável: nem replay, nem
  refresh, nem "voltar o cookie" reativa. O Plug de validação de access token **consulta a
  denylist de `jti`** a cada request (cache curto via `Cachex`).
- Cookies **`HttpOnly` + `Secure` + `SameSite`**; token nunca em `localStorage`.

## 7. Migração de auth legado — PRIORIDADE 0

Existe auth no padrão antigo → **portar pra este IAM é prioridade máxima** (segurança
inegociável; pode gastar o que precisar). Estratégia **strangler-fig**: dual-run, **re-hash
preguiçoso** no login (valida no algoritmo antigo — bcrypt/pbkdf2/sha — e **re-grava em
`argon2id`** via `argon2_elixir` na hora), mapeia registros legados → modelo novo (dedupe de
emails, cunha IDs internos ULID/UUIDv7), **ativa o Email OTP always-on como 2º fator baseline**
(a conta migrada já entra em 2FA sem muro) e **incentiva enrolar fator forte** (step-up para
sensível), **revoga sessões legadas** e **nunca confia na authz legada** (re-deriva pelas tuplas
do ReBAC). O auth migrado nasce já como **microserviço Elixir separado** (§1). Legado PHP/Node de
auth **não** vira base de código nova — é substituído; código Node/PHP restante segue a regra de
migração da casa (`schematize-node`).

## 8. Rotina agressiva de testes (detalhe na schematize-pentest)

Suíte adversarial **contínua** (CI + agendada, fixtures multi-tenant, saída
machine-readable, **gate que trava** em qualquer vazamento):
- **Cross-tenant (BOLA/IDOR):** token do tenant B → IDs do tenant A = 403/404; fuzz de IDs.
- **Priv-esc (BFLA):** papel baixo → ação de papel alto (horizontal e vertical).
- **Matriz persona × endpoint** exaustiva.
- **Abuso de fluxo:** bypass de 2FA, reset pulando 2FA, brute-force/rate-limit de OTP,
  replay de token, reuso de refresh, JWT `alg=none`/kid trocado, session fixation, adulteração
  de asserção SSO, IDOR na gestão de identificadores, bypass de step-up, mass-assignment de
  papel no changeset (`cast` sem allowlist de campos), **logout que não invalidou de verdade**
  (sessão recuperável).

## 9. Autenticação adaptativa por risco (robusta) + transversais

A resposta ao login **varia com o risco calculado** (não é fixa) — é o que torna a conta
difícil de tomar sem chatear o legítimo:
- **Log de sessões/tentativas:** cada tentativa e sessão gravam IP/ASN+reputação, device
  fingerprint, geo, UA, horário, resultado e **score de risco** — na view de sessões (§6) e em
  audit log imutável. É o insumo do score.
- **Score por tentativa:** IP suspeito/novo (Tor/proxy/ASN de abuso), device novo, geovelocidade
  impossível, velocity/brute, hit de honeypot. Baixo = fluxo normal; alto = escala.
- **Escalonamento por risco (2FA→3FA):** sob risco, exige um **fator a mais na ordem de força**
  — **senha → código por email → app OTP/chave**. Acertar senha+email não basta em contexto
  suspeito. Mesmo motor do step-up (§3), disparado pelo **contexto**, não só pela ação.
- **Negação deceptiva / tarpit (falso negativo sob risco):** em contexto suspeito, mesmo com
  **senha correta** o serviço pode responder **genérico `invalid_credentials` uma vez** enquanto
  **computa server-side que a credencial estava certa** e marca que a **próxima** tentativa
  correta **passa** (já com os fatores escalados). Seguro porque: **resposta e tempo IDÊNTICOS**
  ao erro real (sem oráculo — use `Plug.Crypto.secure_compare` e o mesmo path de resposta);
  estado "próxima passa" **curto e escopado** (conta+IP+device, TTL curto via `Cachex`, expira
  sozinho, nunca vira lockout do legítimo); **soma-se** ao 3FA, não substitui; tudo logado.
- **Honeypot:** contas/campos/rotas isca; qualquer interação = sinal forte de hostil → score
  alto, tarpit/deceção, alerta. Nunca serve tráfego real.
- **Anti-automação sempre:** rate-limit + **backoff exponencial** e **lockout progressivo por
  conta+IP** (`Hammer`/`PlugAttack` ou contador em Redis); OTP curto, single-use, `jti` na
  denylist. Barra o abuso sem derrubar o serviço.
- **Notifica o usuário:** login novo/suspeito, novo device, mudança de credencial → aviso nos
  canais verificados, com "não fui eu" (revoga + força reforço).

### Transversais (sempre)
- **Audit log imutável** de toda decisão authn/authz e mudança de credencial — alimenta a
  forense e os testes (liga com a observabilidade LGTM+ da casa; `trace_id` propagado via
  `Logger.metadata`/OpenTelemetry no fluxo de login/authz).
- **Padrões:** OIDC/OAuth2.1 + PKCE; WebAuthn/FIDO2 (`wax`); AALs NIST 800-63B; SCIM (roadmap
  enterprise); FAPI2 se fintech.
- **Libs de apoio (Hex):** `argon2_elixir` (hash), `guardian`/`joken`+`joken_jwks`/`jose`
  (JWT/JWKS), `wax` (passkey/WebAuthn), `nimble_totp` (TOTP), `assent` (SSO/OAuth2),
  `swoosh` (email/Resend), `ecto_ulid`/`uniq` (ID), `ecto_sql`/Postgres (persistência),
  `redix`/`cachex` (sessão/denylist/cache), `oban` (jobs/outbox/atraso cancelável), cliente do
  motor ReBAC (OpenFGA/SpiceDB). Nenhuma chave privada fora do `<projeto>_auth_ex`.

## Roadmap de fases
- **F0** Núcleo de identidade (ID imutável, N identificadores, verificação, Resend/Twilio
  plugáveis por behaviour, email OTP always-on) — já como **microserviço Elixir separado** em
  `auth.<domain>`.
- **F1** 2FA baseline por desenho (senha + Email OTP, sem muro pré-login) + fluxos (TOTP via
  `nimble_totp`/push, **passkey** via `wax`, escolha de método, invariante de troca, **nudge**
  de fator forte, step-up just-in-time, **risk engine adaptativo**: score, 2FA→3FA, negação
  deceptiva/tarpit, honeypot).
- **F2** Multi-tenant + **ReBAC** (membership, papéis granulares, PDP/PEP como `Plug`,
  deny-default, token fino, audit).
- **F3** Recuperação resiliente (múltiplos caminhos, força ≥ login, SSO com recuperação
  local, atraso cancelável via Oban, nudge de email secundário).
- **F4** App de 1ª classe + multi-dispositivo (OIDC/PKCE nativo, push-approval, view de
  remover dispositivos, sessão 7d/90d confiável, logout irreversível).
- **F5** Migração de legado (prioridade 0 quando aplicável).
- **F6** Rotina agressiva de testes (cross-tenant, priv-esc, abuso de fluxo — CI + agendada).
- **Roadmap+** chave FIDO2 dedicada, SCIM, FAPI2, trusted contacts.

## Checklist (entra na Definition of Done quando o projeto tem auth)
- [ ] Auth é **app separada** (`<projeto>_auth_ex` + front próprio em `auth.<domain>`, isolados como `mix release` com user/systemd próprios) — não monolith, nem contexto `MyApp.Accounts.Auth` embutido.
- [ ] **ID interno imutável** (ULID/UUIDv7 `binary_id`); email/telefone não são ID; múltiplos emails suportados (`users` + `identifiers`).
- [ ] **2FA baseline por desenho** (senha + Email OTP = 2FA desde o cadastro); fator forte é **nudge + just-in-time (step-up)**, **NUNCA muro pré-login** (o Plug libera o baseline, exige AAL alto só por rota sensível); passkey no núcleo (`wax`); email OTP always-on (`swoosh`/Resend); Twilio; providers como **behaviours** plugáveis.
- [ ] **Risk engine adaptativo:** log de sessões/tentativas + score (IP/device/geo/velocity/honeypot); **2FA→3FA** sob risco; **negação deceptiva/tarpit** (falso negativo, resposta idêntica ao erro real em tempo constante via `secure_compare`, "próxima passa" curta/escopada); notifica login suspeito.
- [ ] Invariante de troca de fator (Y≠X, maior AAL); recuperação ≥ login; SSO (`assent`) com recuperação local; senha em **argon2id** (`argon2_elixir`)+HIBP.
- [ ] **Multi-tenant + RBAC/ABAC** (ReBAC OpenFGA/SpiceDB), deny-default, PDP=Check API / **PEP=Plug**, enforcement server-side, token fino (`Cachex` cache).
- [ ] Multi-dispositivo + view de remover; **sessão 7d/90d**; **logout irreversível** (revoga refresh+família, `jti` na denylist Redix/`Cachex`, não só cookie).
- [ ] JWKS público (assinatura só no auth, chave via `config/runtime.exs`); JWT validado por inteiro (assinatura/exp/aud/iss/alg allowlist) via `guardian`/`joken`.
- [ ] Audit log de authn/authz; risk engine/rate-limit; migração de legado tratada como prioridade 0 (re-hash preguiçoso → argon2id).
- [ ] Rotina agressiva de testes cross-tenant/priv-esc no CI (schematize-pentest); scaffold/auditoria por `/elixir-iam`.
