# Segurança, Auth, Multi-tenancy, LGPD e Frontend

> Parte da skill **schematize-elixir**. As referências cruzadas (§N) apontam para seções do corpo completo — todas presentes no conjunto de references desta skill. A base agnóstica vive na `schematize-engineering`; o teste adversarial vive na `schematize-pentest`.

## Índice
- 13. Segurança
- 14. Autenticação e Autorização
- 15. Multi-tenancy
- 32. LGPD e Dados Pessoais
- 38. Frontend / Phoenix / LiveView — Regras Específicas

---

## 13. Segurança

**MUST — pipeline (fail on high/critical)**
- Dependabot ou Renovate (mix.exs + mix.lock).
- SAST: **Sobelow** (scanner de segurança Phoenix/Plug) + **Credo** com checks de segurança; Semgrep/CodeQL quando disponível para Elixir.
- SCA: **`mix_audit`** (`mix deps.audit`) contra a base de advisories do Hex + verificação de licenças; **`mix hex.audit`** para pacotes retirados/deprecados.
- Container scan (Trivy / Grype) sobre a imagem do `mix release`.
- Secret scan (Gitleaks) — pega segredo commitado em `config/*.exs`, `.env`, `rel/`.
- Commit signing (GPG / SSH / Sigstore).
- SBOM no build (CycloneDX ou SPDX; `sbom` do `mix` ou geração no CI).

**MUST — runtime**
- Container **não-root**, **read-only filesystem**; o `mix release` roda como user Linux próprio (casa com `ops.md` §3).
- Distroless ou chainguard quando viável; **multi-stage build** (compila com a imagem `elixir`, roda o release sobre `debian-slim`/`alpine` com só o ERTS).
- Healthcheck na imagem (endpoint `/healthz` do Plug/Phoenix).
- **`config :logger, level: :info`** em prod (nunca `:debug`, que vaza payload); **filtro de parâmetros** (`config :phoenix, :filter_parameters`) cobrindo `password`, `token`, `secret`, `cpf`, `card` (§32).

**MUST — segredos (Elixir/OTP)**
- **Segredo NUNCA em `config/config.exs`, `config/prod.exs` ou qualquer `config/*.exs` compilado** — esses viram parte do BEAM/`.beam` no build e do artefato do `mix release`, versionados e distribuídos. **Todo segredo entra em runtime via `config/runtime.exs`** lendo de `System.fetch_env!/1` (ou secret manager), que roda **na inicialização do release, não na compilação**.
  ```elixir
  # config/runtime.exs — avaliado no boot do release, no ambiente de destino
  if config_env() == :prod do
    config :meu_app, MeuApp.Repo,
      url: System.fetch_env!("DATABASE_URL"),
      pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))

    config :meu_app, MeuAppWeb.Endpoint,
      secret_key_base: System.fetch_env!("SECRET_KEY_BASE")
  end
  ```
- **`SECRET_KEY_BASE`, chaves de assinatura, `DATABASE_URL`, tokens de provedor** vêm do ambiente (`RELEASE_*`, `env.sh.eex` do release, secret manager: Vault, AWS/GCP Secret Manager, sealed-secrets) — **nunca hardcoded, nunca no `mix.lock`, nunca no bundle do release**.
- `config/runtime.exs` **falha rápido** (`fetch_env!` levanta em vez de rodar com segredo faltando/`nil`). Segredo ausente derruba o boot — não vira `nil` silencioso.
- Rotação documentada; `secret_key_base` rotacionável sem invalidar tudo (cookie signing salt versionado).

**Licenças permitidas:** MIT, Apache 2.0, BSD, MPL 2.0, ISC.
**Bloqueadas sem ADR:** GPL/AGPL, SSPL, proprietárias.

### 13.1 Ecto — SEMPRE parametrizado, NUNCA SQL concatenado

**Piso inegociável:** toda query passa pela **DSL do Ecto** (`from`, `where`, `Repo.get`) ou por **SQL parametrizado com `?`/pin `^`**. O Ecto parametriza por padrão — o binding `^valor` vira placeholder no driver, nunca interpolação textual.

**Certo:**
```elixir
from(u in User, where: u.email == ^email and u.tenant_id == ^tenant_id)
Repo.get_by(User, id: id, tenant_id: tenant_id)
Ecto.Adapters.SQL.query(Repo, "SELECT * FROM users WHERE id = $1", [id])  # placeholders + params
from(u in User, where: fragment("? = ANY(?)", u.role, ^roles))            # fragment com pin
```

**VETADO — sem exceção, sem ADR (§37):**
- **`Ecto.Adapters.SQL.query`/`query!` com string interpolada:** `"SELECT * FROM users WHERE email = '#{email}'"` é SQL injection. O input vai **sempre** na lista de parâmetros, nunca na string.
- **`fragment/1` com input concatenado:** `fragment("status = '#{status}'")` quebra a parametrização do `fragment`. Use `fragment("status = ?", ^status)`.
- **Nome de tabela/coluna vindo de input** montado por string — se precisar de coluna dinâmica, use **allowlist** de átomos conhecidos, nunca o valor cru do cliente.
- **`Repo.query` para montar `IN (...)`** por interpolação — use `where: u.id in ^ids`.

### 13.2 CSPRNG — `:crypto.strong_rand_bytes`, nunca `:rand`

Token de sessão, código de reset, OTP, `jti`, salt e qualquer segredo gerado usam **`:crypto.strong_rand_bytes/1`** (CSPRNG do OpenSSL). **VETADO** `:rand.uniform/:rand.bytes` (PRNG determinístico, previsível) e `Enum.random` para material de segurança (§37).
```elixir
token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
```

### 13.3 Erro nunca engolido

**VETADO** `rescue`/`catch` que cala o erro (`rescue _ -> :ok`, `rescue _ -> nil`) e **`!`-bang sem tratamento** onde a falha é esperada (usar o par `{:ok, _}/{:error, _}` e um `with`). Engolir exceção esconde falha de auth, de validação e de integridade. Deixe **crashar** (filosofia OTP: supervisor reinicia estado limpo) ou trate explicitamente com `with`/`case` — nunca um `rescue` genérico que devolve sucesso falso (§37, `padroes-codigo.md`).

### 13.4 Segredos no Cliente / Frontend / LiveView

**VETADO — sem exceção, sem ADR**

- **Qualquer segredo no que vai pro browser.** API key privada, `secret_key_base`, chave de assinatura de JWT, senha de banco, service-role key (Supabase/Firebase admin), token de provedor de pagamento, chave de terceiro — **nada** disso entra em template `.heex`, `assign` de LiveView serializado pro socket, `data-*` de HTML ou JS do `assets/`. O navegador não guarda segredo. Ponto.
- **`assign` de LiveView é serializado pro cliente** — o que vai pro `socket.assigns` renderizado trafega e é inspecionável. Segredo fica em `assign_private`/estado de servidor não renderizado, ou nem entra no socket.
- Chamar API de terceiro com chave secreta **direto do JS/cliente**. Toda chamada com segredo passa por um **controller/LiveView server-side ou contexto** (§38).
- Guardar token de sessão em `localStorage`/`sessionStorage`. Sessão vai em **cookie `HttpOnly` + `Secure` + `SameSite`** (§38, §14).
- Confiar em validação de auth/role feita no client como controle de acesso — é UX. A decisão é **sempre server-side** (§15, §37).

> "Coloca a chave no assign pra funcionar no LiveView" não é solução, é vazamento agendado. Se o socket serializa, o atacante já leu.

---

## 14. Autenticação e Autorização

- OAuth2 / OIDC (o auth da casa é app separada — ver `iam.md`).
- **JWT via `Guardian` ou `Joken`**, assinado com **RS256 ou EdDSA (Ed25519)**; **nunca HS256** em fluxo público (chave simétrica compartilhada com o consumidor = qualquer consumidor forja token).
- **Validação COMPLETA do JWT em toda request:** assinatura, `exp`, `nbf`, `aud`, `iss` e **`alg` contra allowlist explícita** (no `Joken`, fixe o `signer`/`alg`; no `Guardian`, configure `allowed_algos`). Decodificar o payload e confiar (`Joken.peek_claims` sem verificar) é **VETADO** (§37). Rejeitar `alg: none` e `alg` trocado (kid confusion).
- Refresh token rotativo com detecção de reuso (revoga a família — ver `iam.md` §6).
- RBAC com permissões granulares; ABAC quando necessário (motor ReBAC — `iam.md` §5).
- **Hash de senha: `argon2id` via `argon2_elixir`** (custo/`t_cost`/`m_cost` adequados ao hardware; `Argon2.verify_pass`/`Argon2.add_hash`). **`argon2_elixir` já faz comparação em tempo constante e `no_user_verify` contra timing/user-enum.** `bcrypt_elixir` (cost ≥ 12) só como legado em migração. **MD5/SHA1/`:crypto.hash` sem salt/plaintext são VETADOS** (§37).
- Tokens, ids de sessão, OTP e códigos de reset por **`:crypto.strong_rand_bytes`** (§13.2) — nunca `:rand`.
- **Comparação de segredo em tempo constante:** `Plug.Crypto.secure_compare/2` (ou `:crypto.hash_equals`) para comparar token/HMAC/OTP — nunca `==` (timing oracle).
- **CSRF:** todo form Phoenix carrega token; o pipeline usa **`plug :protect_from_forgery`** e **`plug :put_secure_browser_headers`**. LiveView valida o CSRF token no `connect`. VETADO desligar `protect_from_forgery` "pra API funcionar" — API stateless usa Bearer, não cookie de sessão.

---

## 15. Multi-tenancy

**MUST — quando aplicável (SaaS, plataformas)**
- Isolamento de tenant explícito em todas as camadas.
- **`tenant_id` vem SEMPRE do token verificado / sessão server-side, NUNCA do body, header ou param do cliente.** Derivar do `Guardian.Plug.current_resource`/claims, colocar no `conn.assigns`/`socket.assigns` privado, e **nunca** aceitar `tenant_id` enviado pelo cliente sem validar contra o token (§37).
- `tenant_id` propagado em contexto, `Logger.metadata`, e traces.
- **Queries com `tenant_id` no `where`, sempre** — de preferência centralizado num helper de contexto (`scope_to_tenant(query, tenant_id)`) que toda leitura/escrita atravessa, para não esquecer numa rota.
- Considerar **Row Level Security no Postgres** com `SET LOCAL app.tenant_id` por transação (Ecto: `Repo.query` do `SET LOCAL` no início da transação) — defesa em profundidade além do `where`.

**SHOULD**
- Testes de cross-tenant leak em CI (token do tenant B → IDs do tenant A = 403/404) — detalhe na `schematize-pentest`.
- Métricas e logs particionáveis por tenant.

---

## 32. LGPD e Dados Pessoais

**MUST**
- Classificação de dados: público, interno, confidencial, pessoal, pessoal sensível.
- **PII nunca em logs.** Use **`config :phoenix, :filter_parameters`** (redige `password`, `token`, `cpf`, `card`, etc. do log de request) e **`redact: true`** nos campos sensíveis do schema Ecto (`field :password_hash, :string, redact: true`) — assim o `inspect` e o log não vazam o valor. `Logger.metadata` nunca carrega CPF/email cru.
- Política de retenção documentada por tipo de dado; jobs de expurgo (Oban) para dado vencido.
- Processo para exercício de direitos (acesso, correção, eliminação, portabilidade) — endpoint/contexto dedicado.
- Criptografia em trânsito (TLS 1.2+) e em repouso para dados pessoais; `Cloak`/`cloak_ecto` para campos cifrados no banco quando exigido.
- DPIA para tratamentos de alto risco.
- **PII nunca em query string / URL** (acaba em log de acesso, histórico, `Referer`) — §37.

---

## 38. Frontend / Phoenix / LiveView — Regras Específicas

**MUST**
- **Fronteira clara servidor/cliente.** Tudo que toca segredo, banco ou terceiro com credencial roda **no servidor** (controller, LiveView `handle_event`, contexto). O `.heex` renderiza dado já autorizado; o socket LiveView **não serializa segredo** pra `assigns`.
- Sessão em **cookie `HttpOnly` + `Secure` + `SameSite=Lax|Strict`** (`Plug.Session` / `Plug.Conn.put_resp_cookie` com as flags). Token de auth **nunca** em `localStorage`/`sessionStorage` (XSS lê tudo lá).
- Headers de segurança via **`plug :put_secure_browser_headers`** + CSP explícita (`content-security-policy`), `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`, `frame-ancestors`. LiveView exige `connect_src`/`ws` na CSP.
- **Sanitização de HTML:** `.heex` escapa por padrão. **VETADO** `raw/1` / `Phoenix.HTML.raw` com conteúdo vindo de input sem sanitização (ex.: markdown de usuário) — sanitize com lib dedicada antes (XSS).
- Validação de input no client é **UX**; a que importa é a **`Ecto.Changeset`** no servidor (§12). Autorização idem é server-side (§15).
- **Upload (`Phoenix.LiveView.Upload`/`Plug.Upload`):** valide **content-type real** (magic bytes, não só extensão), **limite de tamanho** (`max_file_size`), nome sanitizado (nunca use o filename do cliente como path — path traversal), e sirva de storage isolado (nunca do diretório da app). Antivírus/scan quando aplicável.
- Chamada a API de terceiro com chave secreta passa por proxy server-side. O browser nunca segura a chave.

**VETADO**
- Segredo/`secret_key_base`/service-role key no `assets/`, `.heex` ou `assign` serializado do socket.
- `raw/1` com conteúdo não sanitizado (XSS).
- Confiar em `redirect`/`return_to`/`next` param sem allowlist (open redirect — valide contra rotas conhecidas antes do `redirect(to:)`).
- **Atom dinâmico de input:** `String.to_atom(param)` com valor do cliente (esgota a tabela de átomos = DoS). Use `String.to_existing_atom` dentro de allowlist.

> "Bota a chave no assign do LiveView" não existe como solução. Existe como CVE. O cliente pede ao servidor; o servidor guarda o segredo.

---
