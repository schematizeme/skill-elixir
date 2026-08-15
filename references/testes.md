# Testes, Pentest e Makefile

> **Dividida:** §22.4–§23 (padrão de script, seeds, CI, pentest §22.7–22.8, Q.A. §22.9, Makefile/aliases `mix`) estão em `references/testes-execucao.md`. Numeração contínua entre os dois.

> Parte da skill **schematize-elixir**. As referências cruzadas (§N) apontam para seções do corpo completo — todas presentes no conjunto de references desta skill. A camada **agnóstica de linguagem** (os dois eixos de teste, pisos de cobertura, o `<project>_ops` como control plane, o fluxo de Q.A.) vem de **`schematize-engineering`**; aqui está a **especialização Elixir** (ExUnit, ExCoveralls, StreamData, Mox, Ecto Sandbox, Sobelow/Credo/Dialyzer). Pentest aprofundado: **`schematize-pentest`**.

## Índice
- 22. Testes
- 23. Makefile Padrão

---

## 22. Testes

**Obrigatório**
- Testes em **dois eixos**: por código (ExUnit unit/integration, dentro de cada app OTP) e por sistema vivo (smoke/security/pentest/authz/hardening/chaos/simulated, no repo `<project>_ops`).
- Caminhos críticos (auth, pagamento, autorização, billing, eventos de domínio, multi-tenancy) têm testes explícitos cobrindo sucesso, o **caminho de erro** (`{:error, _}`) e edge cases — independentemente da cobertura agregada. Em Elixir, "só o happy-path" é especialmente traiçoeiro: o pattern-match feliz compila e passa, e o ramo `{:error, _}` que ninguém testou é onde o `case`/`with` estoura em produção.

**Cobertura mínima (por código)** — aferida por **ExCoveralls** (`mix coveralls`):

| Camada | Elixir (o que é) | Mínimo |
|---|---|---|
| `domain` | contexts/entidades puras, `Ecto.Changeset`, structs de domínio, lógica sem I/O | 80% |
| `application` | casos de uso, orquestração, `GenServer`/`Task`, sagas | 70% |
| `infrastructure` | `Repo`, adapters HTTP/broker, `Phoenix.Controller`/`Plug`, clients externos | 40% |
| Global | agregado do app | 60% |

> Editar o threshold no `coveralls.json` (`minimum_coverage`) ou marcar `@tag :skip` pra "passar o CI" é VETADO (§37). O número é contrato.

**Mutation testing (SHOULD)** no domínio em serviços críticos: em Elixir a ferramenta é **`muzak`** (mutação sobre a AST; a variante paga `muzak_pro` integra com `mix`). Onde `muzak` não cobre um caso, force a mutação à mão (inverter guard, trocar `>=` por `>`, `{:ok, _}` por `{:error, _}`) e prove que **algum** teste quebra. Cobertura sem mutação mede execução, não verificação.

---

### 22.1 Test Kit do `<project>_ops`

Toda a malha de testes "do sistema vivo" mora num repo dedicado (`<project>_ops`), invocada por um CLI único. Os testes **por código** (ExUnit) moram em cada app (`<project>_<contexto>_ex/test/`); o kit os invoca via `mix test`.

**Estrutura padrão**

```
<project>_ops/
├── bin/
│   └── <project>-test          # CLI: run modes, agrega saída
├── tests/
│   ├── lib.sh                  # helpers compartilhados (cores, assertions, http_call) — bundlado
│   ├── README.md               # tabela de modos × scripts × duração
│   ├── smoke/                  # health, rotas-chave, shape de respostas
│   ├── integration/            # login real + CRUD ponta-a-ponta
│   ├── security/               # auth bypass, headers, rate-limit
│   ├── pentest/                # OWASP + extensão
│   ├── authz/                  # RBAC/ReBAC + multi-tenancy isolation
│   ├── hardening/              # TLS, cookies, CORS, exposed paths
│   ├── chaos/                  # fuzz, property-based, kill de processo/BEAM, db-disconnect
│   ├── simulated/              # matriz exaustiva: rotas × personas × injections (run.py bundlado)
│   ├── seeds/                  # SQL de setup (personas de teste, superadmin)
│   ├── unit/                   # delega `mix test` / `mix coveralls` por app
│   └── workspace-code.sh       # smell-scan no monorepo (arquivos > N linhas, `Credo`, etc.)
├── Makefile
└── README.md
```

**CLI padrão**

```bash
<project> test                  # default: smoke
<project> test smoke
<project> test integration
<project> test security
<project> test pentest
<project> test authz
<project> test hardening
<project> test chaos
<project> test simulated
<project> test unit             # mix test + mix coveralls por app
<project> test all              # tudo exceto chaos+unit
<project> test full             # all + chaos + unit
<project> test seed-superadmin  # setup inicial (uma vez)
```

**MUST**
- Cada script é executável standalone: `bash tests/smoke/auth-endpoints.sh` deve rodar e sair `0/1`.
- Cada script declara `TEST_NAME` e usa helpers de `lib.sh` (`test_pass`, `test_fail`, `test_skip`, `test_section`, `test_summary`, `http_call`, `assert_http_in`). O `lib.sh` bundlado é **agnóstico de linguagem** — o alvo é a API HTTP, não o BEAM.
- Banner ENORME em vermelho quando há falha — feedback visual impossível de ignorar em CI.
- Skip sem erro quando dependência opcional falta (ex.: `openssl` ausente em hardening/tls).

---

### 22.2 Saída estruturada (machine-readable)

Toda execução escreve em `/<project>/logs/test-<YYYY-MM-DD>-<HHMMSS-pid>/`:

| Arquivo | Conteúdo |
|---|---|
| `summary.txt` | PASS/FAIL por script, legível |
| `summary.json` | **fonte única pra dashboards/CI** — schema fixo abaixo |
| `run-totals.txt` | 7 linhas: mode, started, finished, duration, scripts, pass, fail, exit |
| `<mode>-<name>.log` | output completo de cada script |
| `cookies.txt` | sessão dos personas (só em `integration`) |
| `coverage-summary.{txt,json}` | cobertura por app, extraída do ExCoveralls (só em `unit`) |

**Schema `summary.json`**

```json
{
  "started_at": "2026-05-11T11:35:50Z",
  "finished_at": "2026-05-11T11:35:57Z",
  "duration_seconds": 7,
  "mode": "smoke",
  "log_dir": "/<project>/logs/test-2026-05-11-083550-448694",
  "scripts": [
    {"category": "smoke", "name": "auth-endpoints", "status": "pass"},
    {"category": "smoke", "name": "services-health", "status": "fail"}
  ],
  "totals": {"pass": 23, "fail": 1, "scripts": 24, "exit_code": 1}
}
```

**MUST**
- Exit code 0 se tudo passou; 1 se qualquer caso falhou. O `mix test` já sai `1` em falha — não engula com `|| true`.
- `summary.json` é contrato — não quebre os campos `mode`, `totals`, `scripts[]`.
- Logs zipados e enviados pra storage de longo prazo após cada CI run (90 dias mínimo).

---

### 22.3 Categorias de teste (por modo)

#### `smoke` — saúde do sistema, < 2min

Cobre: health/metrics de cada serviço (`/health`, `/ready`, `PromEx` em `/metrics`), rotas-chave do router Phoenix/Plug, frontends, observability stack, endpoints por domínio (auth, catalog, billing, etc.), DB connectivity (`Ecto.Repo` acessível), microservices-status, shape de health/metrics, response-time p95, CORS preflight, OpenAPI availability, log scan pra PII vazada.

Falha = bloqueio de deploy. Roda **antes e depois** de cada `update` em todo ambiente.

**MUST — anti "verde mentiroso" (smoke que passa com bug dentro)**

Um smoke que só confere status `200` é teatro: a rota responde, o conteúdo está quebrado, e o deploy passa. Para impedir isso:

- **Assertar conteúdo, não só status.** Toda rota-chave valida o **shape do body** (campos esperados via `jq -e`), não apenas o código HTTP. `200` com body vazio, `{}`, `null`, `[]` onde deveria haver dado, ou HTML de erro com status 200 = **FALHA**.
- **Assertion negativa obrigatória.** Cada rota crítica também testa que o que **não** deveria estar lá não está: sem stack trace do Elixir (`** (`, `(RuntimeError)`, `Ecto.` no body, linhas de `lib/.../*.ex`), sem `error`/`exception` no body de sucesso, sem `nil`/`:error` serializado cru, sem placeholder de template EEx/HEEx não renderizado (`<%=`, `{{`, `${`, `%s`).
- **Self-test do próprio smoke (meta-teste).** O suite roda o `scripts/smoke-selfcheck.sh` bundlado, que **força uma falha conhecida** (bate numa rota fake `/_smoke_canary_should_404` esperando 404, e dispara uma asserção que deve falhar de propósito no modo `--self-check`) pra provar que o runner **consegue reportar FAIL**. Contrato: `smoke-selfcheck.sh` em modo normal sai `0`, em `--self-check` sai `0` **só porque** a falha forçada foi corretamente reportada como FAIL. Se o "self-check" passa quando deveria falhar, o smoke está cego → CI quebra. Nenhum teste pode ser estruturalmente incapaz de falhar.
- **Cobertura de rota verificada.** O smoke compara as rotas que testou contra o inventário do router (`mix phx.routes` ou o catalog do OpenAPI). **Rota em produção sem caso de smoke = FALHA**, não silêncio. (Liga com §35 e com `simulated`.)
- **Sem `|| true`, sem swallow.** Proibido `curl ... || true`, `set +e` sem `set -e` de volta, ou condição que transforma erro em pass. Falha de rede/timeout numa dependência obrigatória é FAIL, não skip (skip só pra dependência **opcional** declarada).
- **Latência e dado fresco.** Healthcheck que devolve `200` cacheado/estático não conta — `/ready` valida dependência **de verdade** (`Ecto.Adapters.SQL.query(Repo, "SELECT 1")`, ping no broker/`Oban`), e o smoke afere `response-time p95` contra o SLO (§30). Resposta lenta demais = FALHA.
- **Fail loud.** Banner vermelho ENORME (§22.1) e o `summary.json` com `totals.fail > 0` travando o deploy. Verde só quando **todas** as asserções de conteúdo passaram.

> Smoke que nunca falha não é smoke saudável — é smoke quebrado. Se você não viu o teste falhar de propósito, você não sabe se ele funciona.

#### `integration` — fluxos end-to-end com credenciais reais, < 3min

Cobre: login do superadmin com cookie real, CRUD course/user/subscription via API admin, upload de imagem, reset de senha completo. Bate na API HTTP viva (não no `ConnTest`), usando seed `tests/seeds/test-superadmin.sql` pra garantir user existente.

**Requer pré-seed**: rodar `<project> test seed-superadmin` na primeira vez no ambiente.

> Este `integration` (sistema vivo) é diferente do teste de integração **por código** com `Phoenix.ConnTest`/`Ecto.Adapters.SQL.Sandbox`, que roda dentro do app OTP no modo `unit` (§22, §22.3 `unit`). O primeiro exercita o deploy real; o segundo, a lógica isolada com banco em transação revertida.

#### `security` — controles de segurança "óbvios", < 1min

Cobre: auth bypass tentando rotas admin sem cookie, headers de segurança (CSP, X-Content-Type, HSTS) via `Plug`, rate limit no login (50 paralelas → expect 429), formato de password hash (`Argon2`/`Bcrypt` cost adequado — `argon2id` preferido), `mix deps.audit` (**MixAudit**) + `mix hex.audit` sem vuln aberta, JWT algorithm validation (assinatura assimétrica, `alg` travado).

#### `pentest` — OWASP Top 10 + extensão, < 3min

> Metodologia, mapa de endpoints, matriz de autorização por persona e arsenal por classe estão em **`schematize-pentest`**. Aqui é a bateria de rejeição rota-por-rota que a malha `<project>_ops` executa (princípios em §22.8).

Scripts cobrem (cada um isolado):
- `sql-injection.sh` — payloads SQLi clássicos em query/body. Esperado: 400/422 ou 401/403/404. **NUNCA 500** e nunca 200 com data revelando "OR 1=1". (Ecto com query parametrizada já barra; o teste prova que **nenhuma** rota escapou pra `Ecto.Adapters.SQL.query/4` com string interpolada.)
- `xss.sh` — `<script>`, `<img onerror>`, `javascript:` em campos refletidos. Resposta não pode incluir payload sem escape (HEEx escapa por padrão; `raw/1` é a fuga a caçar).
- `idor.sh` / `user-bola.sh` — IDs de outro tenant/user nos paths.
- `ssrf.sh` — URLs apontando pra `127.0.0.1`, `169.254.169.254`, `file://`, redirect chains (alvo: `Req`/`Finch`/`HTTPoison` que segue redirect cego).
- `jwt-tampering.sh` / `jwt-claim-tampering.sh` / `jwt-algorithm.sh` — alg=none, alg=HS256-com-chave-pública-RS256, exp futuro, sub trocado.
- `path-traversal.sh` — `../`, `..%2f`, null bytes.
- `mass-assignment.sh` — POST com campos extras (`is_admin`, `tenant_id`, `role`, `inserted_at`) que o `cast/3` do changeset deve **ignorar** (só o `cast` das chaves permitidas, nunca `cast` da lista inteira do params).
- `open-redirect.sh` — `?next=https://evil.com`.
- `host-header.sh` — Host header arbitrário pra envenenar links em emails (`url: [host: ...]` do endpoint).
- `csrf.sh` — POST sem origin/referer válido (`Plug.CSRFProtection` nas rotas de sessão).
- `http-method-tampering.sh` — TRACE, OPTIONS, métodos não suportados.
- `request-smuggling.sh` — `Transfer-Encoding: chunked` + `Content-Length` conflitantes.
- `cache-poisoning.sh` — headers exóticos que envenenam CDN.
- `cookie-bomb.sh` — flood de cookies grandes → expect 4xx limpo, não 500.
- `session-fixation.sh` — session ID atribuído pré-login persiste pós-login (deve haver `Plug.Conn.configure_session(renew: true)` no login).
- `timing-attack.sh` — diff de latência entre user existente vs inexistente no login (alvo: < 30% variance; hash sempre roda mesmo pra user inexistente — `Argon2.no_user_verify/0`).
- `atom-exhaustion.sh` — **específico do BEAM**: parâmetros que viram átomo dinamicamente (`String.to_atom/1` em input externo) esgotam a tabela de átomos → derrubam o nó. Esperado: input externo **nunca** vira átomo novo (só `String.to_existing_atom/1`), e o teste prova que 10k chaves distintas não incham a `:erlang.system_info(:atom_count)`.
- `redos.sh` — strings catastróficas pra regex (`aaaaaa...aaa!`).
- `billion-laughs.sh` — JSON/XML bomb (nested arrays profundos); em Elixir, também nested map fundo que estoura o parser.
- `clickjacking.sh` — `X-Frame-Options` / CSP `frame-ancestors`.
- `refresh-token-reuse.sh` — usar mesmo refresh duas vezes → 2ª deve revogar família.
- `parameter-pollution.sh` — `?id=1&id=2` (Plug agrega em lista — o handler assume string?).
- `excessive-data-exposure.sh` — endpoint público vaza email/cpf/telefone (view/`Jason.Encoder` derivando struct inteira sem `@derive {Jason.Encoder, only: [...]}`).
- `header-spoof.sh` — `X-Forwarded-For`, `X-Real-IP`, `X-Original-User` injetados.
- `oversized-payload.sh` — body de 10MB+ → 413 (`Plug.Parsers` `:length`), não 500.

**Validação de tipo e sanitização de entrada** — campo só aceita o que deveria, e o que não deveria vira **422/400 limpo, nunca 500 e nunca persistido cru**:
- `type-confusion.sh` — manda o tipo errado em cada campo: string onde o changeset espera `:integer`/`Ecto.UUID`/`:boolean`/`Ecto.Enum`/`:date`; número onde espera string; array onde espera map; map aninhado onde espera escalar. Esperado: `422` com `changeset.errors`. **Aceitar `"123"` como integer por coerção silenciosa é FALHA** — o `Ecto.Changeset` casta `"123"` → `123` de propósito; prove que o cast **rejeita** o que não deve castar (`"12abc"`, `"true"` pra bool onde a semântica não permite) e que campo `:string` não vira número.
- `boundary-values.sh` — limites numéricos: negativo onde só positivo (`validate_number(greater_than: 0)`), `0`, `MAX_INT+1`, `-1`, float onde espera int, `NaN`, `Infinity`, notação científica (`1e999`).
- `charset-fuzz.sh` — caracteres estrangeiros e estranhos em **todo** campo de texto: unicode astral (emoji 𝕏, `𝓪`), CJK (中文), árabe/hebraico (RTL), combinação de diacríticos, zero-width (`​`), homoglyphs, ` ` null byte, control chars (`\x01`-`\x1f`), BOM. Esperado: aceitar normalizado (NFC via `:unicode.characters_to_nfc_binary/1`) **ou** rejeitar com 422 — **nunca** quebrar encoding (`ArgumentError` de binário inválido = 500 = FALHA), corromper o dado, ou refletir sem escape. Elixir trata string como binário UTF-8: prove que binário inválido (`<<0xFF, 0xFE>>`) não estoura o `Jason`/`Ecto`.
- `format-validation.sh` — campos com formato declarado (email, cpf, telefone, url, uuid, cep) recebem lixo que casa o "shape" mas é inválido (`a@b`, cpf com dígito verificador errado, `uuid` de 35 chars). Validação semântica (`validate_change/3` com regra real), não só `validate_format/3` frouxo.
- `length-overflow.sh` — string acima do `validate_length(max:)` do changeset, campo obrigatório vazio/ausente, whitespace-only. Esperado: 422, e o limite **vem do changeset**, não de um `varchar(255)` implícito que estoura no banco com `Postgrex.Error`.
- `injection-in-every-field.sh` — roda o conjunto SQLi + XSS + path-traversal + command-injection (`System.cmd`/`os.cmd` com input) + template-injection (`EEx`/`${7*7}`/`{{7*7}}`) contra **cada** parâmetro de **cada** rota mutável, não só os "óbvios". Tudo que entra é tratado como hostil até prova de sanitização.

> Regra do pentest de entrada: **todo campo é um campo de ataque.** Se o changeset diz `:integer`, prove que integer é tudo que persiste. Se diz texto, prove que sai escapado e normalizado. Coerção silenciosa e `500` são as duas faces do mesmo bug — e no BEAM, `String.to_atom/1` sobre input hostil é uma terceira face que derruba o nó inteiro.

#### `authz` — autorização e isolamento, < 1min

- `cross-tenant-idor.sh` — tenant A não vê dados de tenant B (cobre §15: `tenant_id` sempre no `where` da query Ecto, nunca query sem escopo).
- `rbac-negative.sh` — viewer não consegue write, editor não consegue admin.
- `privilege-escalation.sh` — tenant_admin não consegue virar platform superadmin.
- `permission-boundary.sh` — combinações de roles + recursos → matriz de allow/deny.
- `tenant-isolation.sh` — cookie/JWT de tenant A injetado em rota de tenant B → 403.

#### `hardening` — endurecimento da superfície de ataque, < 1min

- `tls-config.sh` — TLS 1.2/1.3 ok, 1.0/SSLv3 rejeitados, cert válido, HSTS no header, nome bate.
- `headers-full.sh` — CSP, COOP, CORP, Referrer-Policy, Permissions-Policy, X-Content-Type-Options (via `Plug` de headers).
- `cookies.sh` / `cookie-attributes.sh` — HttpOnly + Secure + SameSite=Lax|Strict em todos os cookies de sessão (`Plug.Session` config).
- `cors.sh` — origens permitidas explícitas, sem `*` em rotas autenticadas (`Corsica`/`CORSPlug` com whitelist).
- `exposed-paths.sh` — `.git/HEAD`, `.env`, `/debug`, `/dev/dashboard` (LiveDashboard fora de prod), `phpinfo.php` retornam 404 (não 200).
- `default-creds.sh` — login com `admin/admin`, `root/root`, `test/test` falha sempre.

#### `chaos` — comportamento sob stress / falha, < 5min

- `input-fuzz.sh` — strings longas (10MB), null bytes, unicode astral, JSON malformado, binário inválido.
- `property-based.sh` — idempotência (`POST` com `Idempotency-Key` igual 2x → mesmo resultado), p95 < SLO, JWKS sempre formado corretamente, `Ecto.Enum` com valores fora do range.
- `service-kill.sh` — mata o processo BEAM / `systemctl stop <service>`, mede recuperação do supervisor OTP e do orquestrador (gated por `<PROJECT>_CHAOS_ALLOW=1` — perigoso). Também testa kill de `GenServer` crítico e valida que a `Supervisor` reinicia sem perder estado durável.
- `db-disconnect.sh` — derruba conexão DB momentaneamente, valida que o pool `DBConnection`/`Ecto` recupera sem derrubar o nó.
- `concurrent-load.sh` — 50 GETs concorrentes em rotas públicas, mede taxa de sucesso e p50/p95/p99, hang > 10s = falha. No BEAM, verifica também que o `message queue` de nenhum processo crítico cresce sem limite (backpressure — §9).

#### `simulated` — matriz exaustiva, ~5min

Engine Python (`scripts/simulated/run.py`, bundlado e **agnóstico de linguagem** — bate na API HTTP) que cruza **rotas × personas × injections**:

- **Personas (mínimo 3)** declaradas em `personas.json`:
  - `superadmin` (platform role)
  - `tenant_admin` (escopo de 1 tenant de teste)
  - `normal_user` (sem roles)
  Cada persona declara `expected_access` por categoria de rota (`public`, `auth`, `authenticated`, `admin`, `internal`, `import`).

- **Injections (mínimo 10)** em `injections.json`:
  - SQLi (`' OR 1=1 --`, `'; DROP TABLE users CASCADE; --`)
  - XSS (`<script>alert(1)</script>`)
  - Path traversal (`../../etc/passwd`, `..%2f..%2fetc%2fpasswd`)
  - Null byte, unicode RTL override, long string
  - Atom-exhaustion keys (chaves aleatórias em massa, pra caçar `String.to_atom/1`)
  - Mass-assignment keys (`is_admin`, `tenant_id`, `role`, `inserted_at`, `password_hash`)

- **Rota catalog** — JSON gerado a partir do OpenAPI ou do `mix phx.routes` (inventário do router Phoenix/Plug).

**MUST — cobertura total de rotas (garantia de acessibilidade)**
- O engine **enumera 100% das rotas** do catalog e prova, por persona, que cada uma responde como esperado (acessível pra quem deve, `403`/`401` pra quem não deve). **Rota no catalog sem resultado no `raw.jsonl` = FALHA** — não existe rota "não testada".
- **Reconciliação obrigatória:** rota servida em runtime mas ausente do catalog (rota fantasma) **e** rota no catalog que não responde (rota morta / `404` inesperado) **ambas** quebram o run. O número de rotas testadas tem que bater com o `mix phx.routes`.
- Toda rota é exercida com persona autorizada **e** não autorizada — acessibilidade e isolamento no mesmo passe.
- Saída lista explicitamente, no `report.md`, a **matriz rota × persona × esperado × obtido**, com as linhas `REVIEW` destacadas pra olho humano.

**Outputs**:
- `raw.jsonl` — uma linha por request, toda evidência.
- `report.md` — relatório humano com seções **AUTO** (passou claro) e **REVIEW** (status inesperado, precisa olho humano).
- `summary.json` — totais por categoria.

**Setup**: `bash tests/simulated/setup.sh` cria as 3 personas no DB com hash `argon2id`.

Vars de ambiente úteis (`<PROJECT>_TEST_*`):
- `<P>_TEST_API_BASE` (default `http://127.0.0.1:13000`)
- `<P>_TEST_LOG_DIR` (default `/<project>/logs`)
- `<P>_SIM_TENANT_ID`
- `<P>_SIM_MAX_ROUTES` (debug: limita)
- `<P>_SIM_SKIP_MUTATIONS=1` (só GET)

#### `unit` — testes por código (ExUnit), 5-15min — **agressivos, não decorativos**

CLI delega para o **ExUnit** de cada app OTP:
- **Elixir (principal):** `mix test` (ou `mix test --cover` / `mix coveralls.json` pra cobertura via **ExCoveralls**); `StreamData` pra property-based; **doctests** (`doctest MyMod`); `Mox` nas fronteiras; `Ecto.Adapters.SQL.Sandbox` pra isolamento de banco.
- Auxiliares (quando o app tem NIF/port em outra linguagem): `cargo test` (Rust/Rustler), `go test -race ./...` (Go), `mix test` continua sendo o orquestrador.

Gera `coverage-summary.json` agregando cobertura por app a partir do `cover/excoveralls.json`.

**MUST — teste unitário que realmente caça bug (não só cobre linha)**
- **`async: true` só com isolamento provado.** Rodar testes concorrentes é o default rápido do ExUnit, mas `async: true` num teste que toca banco **exige** `Ecto.Adapters.SQL.Sandbox` em modo `:manual` com `checkout` por teste (`SQL.Sandbox.mode(Repo, {:shared, self()})` só onde inevitável). Estado global compartilhado (`Application.put_env`, `:persistent_term`, `GenServer` nomeado, `Mox` em modo global) **proíbe** `async: true` — misturar os dois é flake garantido. Teste flaky por corrida = bug, não "re-roda com `--seed 0`".
- **Caminho de erro é obrigatório, não opcional.** Para cada função, testar o sucesso **e** as falhas: `{:error, changeset}`, `{:error, :not_found}`, timeout, `nil`, lista vazia, cláusula `case`/`with` que cai no `else`, `FunctionClauseError`. Cobertura de 80% só do ramo `{:ok, _}` é cobertura mentirosa — o `with` que não testou o `else` é onde mora o 500.
- **Tabela de casos hostis por changeset/parser:** tipo errado, fora do range, string gigante, vazia, unicode/RTL/null byte, número como string e vice-versa — espelhando o `type-confusion`/`charset-fuzz` do pentest, só que na fronteira da função (o `changeset/2` do schema). Bug de sanitização tem que morrer no unit, antes do pentest achar. **Atom-exhaustion** (`String.to_atom/1` em input) tem teste dedicado: prove que a função usa `to_existing_atom` e falha limpo no átomo inexistente.
- **Property-based testing (SHOULD → MUST em domínio crítico):** `StreamData` (`use ExUnitProperties`; `check all x <- generator()`). Idempotência, round-trip (`encode |> decode == original`), invariantes de agregado, comutatividade. Encontra o edge case que você não imaginou — e o `StreamData` **encolhe** o contraexemplo até o menor caso que quebra.
- **Doctest é teste, não enfeite.** Todo exemplo em `@doc` (`iex> ...`) é executado por `doctest MyMod` e **tem que passar** — doc que mente sobre o retorno quebra o CI. Doctest cobre o contrato público de graça; use pra o happy-path documentado e deixe os casos hostis pro `test`.
- **Mox nas fronteiras — "mock as contract".** Mock **só** contra um `behaviour` (ou protocol) que **você define e possui** — `Mox.defmock(MyApp.HTTPClientMock, for: MyApp.HTTPClient)`. Nunca mocke o que você não possui (a lib `Req`/`Finch`, o `Postgrex`): envolva-o num behaviour da sua fronteira e mocke **esse contrato**. O `Mox` verifica em `verify_on_exit!` que o mock foi chamado como o behaviour promete — mock que diverge do behaviour real é bug do teste, não do código. Mock global (`Mox.set_mox_global`) mata o `async: true`; prefira `set_mox_private`.
- **Mutation no domínio crítico** (§22, `muzak`/mutação manual): se o teste não pega a mutação, o teste é decorativo. **Mutation score mínimo definido por app crítico**, não só line coverage.
- **Boundary obrigatório:** `0`, `-1`, `1`, `MAX`, `MAX+1`, `[]`, `[x]`, muitos. O bug mora na borda — e em Elixir, na cláusula de `case`/pattern que não cobre a lista vazia.
- **Proibido teste que não pode falhar:** `assert true`, teste sem `assert`, mock que devolve o próprio input esperado, `assert {:ok, _} = fun()` que nunca checa o conteúdo do `_`. Revisão de PR rejeita teste tautológico.

> Cobertura mede o que o teste **executa**, não o que ele **verifica**. Mutation testing mede o que ele verifica. Por isso line coverage é piso, não meta — e um `with` verde no ExCoveralls cujo `else` nunca rodou é a mentira mais comum do BEAM.

---
