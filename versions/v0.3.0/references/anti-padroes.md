# Filosofia, Aplicação Universal e Anti-Padrões Vetados


> **PONTEIRO, não cópia.** A normativa deste tema é da base: **`schematize-engineering`** →
> `references/anti-padroes.md`. Leia lá primeiro; aqui fica **só o que muda em Elixir/OTP**.
>
> **Onde este arquivo divergir da base, a BASE MANDA** (`SKILL.md` §"Precedência e herança").
> Em 2026-08-21 os blocos idênticos à base foram **podados mecanicamente** (`tools/podar-clone.mjs`),
> que é por que a numeração dos itens **salta**: o número é o da base, e o item que não aparece aqui
> é porque **não muda nesta linguagem** — procure-o lá. Manter a cópia era manter a próxima deriva
> (foi assim que o `argon2id-only` da casa virou "ou PBKDF2" numa skill e o rol de 6 linguagens
> virou "só Go e Rust" em três).

## 0. Como Ler

Versões concretas de Erlang/OTP, Elixir e libs ficam em **`references/stack-versoes.md`**, atualizado independentemente deste corpo.

## 1. Filosofia

**Princípios:** Clean Code, SOLID, KISS, DRY (com bom senso — duplicação acidental ≠ duplicação semântica). Em Elixir: *let-it-crash* com supervisão, funções puras + dados imutáveis no núcleo, processo só onde há estado/serialização/isolamento de falha — não macro-esperteza que esconde o fluxo.

## 37. Anti-Padrões Vetados — "Macaquices" que Terminam Rápido e Quebram em Produção

### Segredos e exposição

1. **Segredo no bundle do cliente.** API key privada, secret de JWT, senha de banco, service-role key, token de pagamento no código que vai pro browser, ou em `NEXT_PUBLIC_*` / `VITE_*` / `REACT_APP_*`. Em Phoenix, segredo em `assigns`/HEEx que renderiza no cliente conta também.
   → Segredo **só server-side** (BFF, secret manager, `config/runtime.exs`). O navegador não guarda segredo (§13.4, §38).

2. **PII / token / senha em query string ou URL.** Acaba em log de acesso, histórico do browser, header `Referer`, e no `Logger` do Phoenix.
   → Vai em body ou header apropriado, nunca na URL (§32, §16.1).

3. **Segredo real em `config/config.exs` (compilado no release) ou `.env`/`runtime.exs` commitado**, ou hardcoded "temporário" no código.
   → Segredo lido em **`config/runtime.exs`** de variável de ambiente / secret manager; `config.exs` é compile-time e vaza no release. `.env.example` sem valores; Gitleaks no pipeline (§13).

### Injeção e execução

4. **SQL cru com interpolação de string** — `Repo.query!("... WHERE x = '#{input}'")` ou `fragment("... = #{input}")` montando a query com input externo.
   → Ecto **sempre parametrizado**: binds `^var` na query, `fragment("... = ?", ^input)`, `Repo.query!(sql, [param])`. Nunca `#{}` dentro de SQL (§10).

5. **`Code.eval_string`/`Code.eval_quoted`, `String.to_atom/1` de input (atom exhaustion), `System.cmd`/`:os.cmd` com string de shell** contendo qualquer parte vinda de input.
   → Nunca `eval` de input. `System.cmd(cmd, args)` com **args em lista** (sem shell), allowlist de comandos, `String.to_existing_atom/1` para converter só átomos já conhecidos.

6. **Desabilitar verificação TLS** (`ssl: [verify: :verify_none]`, `verify: :verify_none` no `:hackney`/Finch/`:httpc`) pra "funcionar logo".
   → `verify: :verify_peer` com CA store. mTLS interno. Se o cert está errado, conserta o cert.

### Auth e autorização

7. **Auth/authz só no client** (`if (user.isAdmin)` no React decide acesso).
   → Toda decisão de acesso é **server-side** (plug/PEP no Phoenix, §15). Front é UX, não controle.

8. **Confiar em `tenant_id` / `role` / `user_id` vindos do body, params ou header do cliente** sem validar contra o token.
   → Derivar sempre do token verificado, server-side, em `conn.assigns` populado por plug (§15).

9. **JWT decodado sem validar** assinatura, `exp`, `aud`, `iss`, e `alg` contra allowlist (aceitar `alg: none` ou HS256 com pubkey RS256). Em Elixir: `Joken`/`JOSE` com `verify` desligado ou sem fixar o algoritmo.
   → Validação completa em toda request, `alg` fixado na allowlist (§14).

10. **Hash de senha fraco** — MD5, SHA1 (`:crypto.hash`), sem salt, ou plaintext.
    → **argon2id** (`argon2_elixir`) ou bcrypt cost ≥ 12 (§14).

11. **`:rand`/`Enum.random`/`:erlang.now` pra token, id de sessão, código de reset, nonce** (PRNG não-cripto).
    → CSPRNG: `:crypto.strong_rand_bytes/1` (§14).

### CORS, headers e superfície

12. **`Access-Control-Allow-Origin: *` em rota autenticada** (pior ainda com `allow-credentials`).
    → Allowlist explícita de origens no `Corsica`/plug de CORS (hardening; ver a `schematize-qa`, `references/categorias.md` §§5 e 10).

13. **Endpoint de debug/admin/dashboard sem auth, ou bind em `0.0.0.0`** — `LiveDashboard`, `/metrics`, console remoto exposto.
    → Bind restrito, auth obrigatória; `LiveDashboard`/`/metrics` atrás de auth e 404 externo (ver a `schematize-qa`, `references/categorias.md` §§5 e 10).

14. **Mass assignment** — `cast/3` do Ecto com lista de campos frouxa (ou o mapa inteiro), deixando passar `is_admin`, `tenant_id`, `inserted_at`, `password_hash`.
    → `cast/3` com **allowlist explícita** de campos por changeset/endpoint; nunca `cast(struct, params, Map.keys(params))`.

### Erros, tipos e qualidade

15. **`rescue`/`catch` que engole erro** — `rescue _ -> :ok`, `try ... rescue _ -> nil`, `{:error, _}` ignorado, `_ = resultado`, `with` sem cláusula `else` que trate a falha.
    → Tratar, logar com contexto e `trace_id`, propagar ou degradar de forma consciente. Erro de programação: **deixe crashar** (let-it-crash) e o supervisor trata — não mascare com `rescue` genérico.

16. **`!`-bang sem tratar, `@dialyzer {:nowarn_function}`, `any()`/`term()` no `@spec` pra calar o Dialyzer/Credo.** `Repo.get!`, `String.to_integer/1`, `Map.fetch!` num fluxo onde a falha É esperada e vira 500 cru.
    → `!`-bang **só** quando a falha é violação de contrato que deve crashar sob supervisão; caso esperado usa a variante `{:ok, _} | {:error, _}` e trata. Spec preciso. Suprimir regra **de segurança** (Sobelow/Credo) inline é VETADO sem ADR.

17. **Logar `conn`/request/response inteiro, headers ou params crus "pra debugar"** — `Logger.info(inspect(conn))`, logar `params`/`assigns`.
    → Logar campos específicos, mascarados (`filter_parameters`). Nunca PII/token/senha (§16.1).

### Testes e cobertura

18. **Pular/comentar teste pra passar o CI** — `@tag :skip`, `@moduletag :skip`, `@tag :pending`, comentar o `assert`.
    → Conserta o código, não silencia o teste.

19. **Baixar o threshold de cobertura ou editar o gate** (`test_coverage`/`excoveralls`) pra o número fechar.
    → Cobertura é contrato (ver a `schematize-qa`). Sobe escrevendo teste, não mexendo na régua.

20. **Mockar o próprio sistema sob teste** retornando sucesso fixo, dando "verde" falso.
    → Testar comportamento real; mock só nas bordas externas, via **behaviour + Mox** (contrato explícito), nunca stub que finge o domínio.

### Dados e migrations

21. **Migration irreversível** — `change/0` que o Ecto não sabe reverter sem `up/0`+`down/0`, `execute("...")` sem o inverso, `DROP`/`ALTER` destrutivo sem backup.
    → Reversível, testada com `mix ecto.rollback` antes do merge (§10).

22. **Cache de resposta autenticada sem chave por usuário/tenant** — ETS/Cachex/Nebulex com chave que não segmenta; um user recebe dado do outro.
    → Chave de cache sempre segmentada por usuário e tenant (§11, §15).

### Operação e entrega

23. **Container root, `chmod 777`, `--privileged`, filesystem RW** "pra funcionar".
    → Não-root, read-only, least-privilege (§13). Release Elixir roda como user dedicado.

24. **Dependência Hex nova sem verificar** nome (typosquatting), manutenção, licença, e sem lockfile (`mix.lock` fora do commit, dep por branch git frouxa).
    → Pin no `mix.lock` commitado, checar nome/manutenção/licença, `mix hex.audit`/SCA no pipeline (§13, §34, `references/cadeia-suprimentos.md`).

25. **Retry infinito / sem backoff/jitter** — DoS no próprio sistema ou no terceiro; `GenServer` que re-tenta em loop apertado.
    → Limite explícito + backoff exponencial + jitter (§9, §18).

27. **Dual-write** — gravar no `Repo` e publicar no broker/PubSub no mesmo fluxo, sem outbox.
    → Transactional Outbox (§9, Anexo B / `references/dados-eventos.md`).

30. **Desligar rate limit, validação de payload/changeset, ou security scan (Sobelow) "temporariamente".**
    → "Temporário" vira permanente. Não se desliga piso de segurança (§12, §13).

31. **Criar serviço backend novo FORA do rol sancionado, ou sem o ADR de escolha que justifica o fit.** Backend novo em Node ou qualquer código novo em PHP entram aqui — são legado.
    → Backend novo **dentro do rol** (Go, Rust, Elixir, C#, Zig, Ruby), com **ADR (§27) de fit**; Node segue valendo pro frontend. Node-backend e PHP são legado e migram por funcionalidade do módulo (§3, §3.1, §3.2). Nova linguagem fora do rol = ADR de exceção.

32. **Serviço que não sobe / crasha porque outro serviço está fora** (acoplamento de runtime, crash em cascata) — "o `ledger` não sobe sem o `core`".
    → Cada serviço é entidade à parte: a supervision tree sobe e opera sozinha; dependente ausente = degradação graciosa, nunca crash (§2, §18).

35. **Editar código direto no servidor** (hml/prd), ou **subir mudança direto pra hml/prd** pulando `dev local → teste local → GitHub`.
    → Servidor é **imutável por edição manual**; recebe só release promovido do git. Hotfix segue o mesmo fluxo, acelerado (`references/ops.md` §1).

36. **Operar o servidor por fora do `<projeto>_ops`** — `ssh` + comando ad-hoc, editar arquivo no servidor, `docker`/`kubectl`/`systemctl`/`remote console` na mão, script solto.
    → **100%** de install/update/config/correção passa por comando do ops. Não tem comando? **cria no ops** (`references/ops.md` §2).

37. **Instalar/subir o sistema em série** ("um serviço de cada vez", 20 min).
    → Instalação **paralela por padrão** = `nproc` (`references/ops.md` §3).

39. **Redeploy que faz patch in-place / não parte do seed** (estado acumulado, drift entre implantações; `hot code upgrade` improvisado sem `.appup`).
    → Todo redeploy é **destrutivo na app**: apaga a anterior e recria um clone zerado a partir de `/<app>/.env` (`references/ops.md` §2). Idempotente e reprodutível.

40. **Config/segredo de serviço fora do seed global**, ou repos do sistema espalhados fora de `/<app>/`.
    → `/<app>/.env` é a **fonte única** de config (lida no `runtime.exs`); o ops clona os repos dentro de `/<app>/` (`references/ops.md` §2).

42. **Dois serviços no mesmo user Linux, release rodando como `root`, ou criar user/unit/permissão à mão.**
    → **Um user + systemd unit hardened por serviço**, provisionado **pelo ops** (`references/ops.md` §3). Blast radius mínimo.

### Concorrência e OTP (BEAM)

43. **`GenServer`/`Agent`/singleton `:global` global como gargalo e ponto único** — todo request serializado por um processo único que vira fila e SPOF ("o `CounterServer` do sistema inteiro").
    → Particione o estado (por chave via `Registry`/`:pg`, `DynamicSupervisor`, `partition`/pool), ou nem use processo (função pura sobre o `Repo`). Estado por agregado, não global. Detalhe em `references/concorrencia.md`.

44. **Processo sem supervisão / `spawn` solto / estado crítico que morre calado** — `spawn`/`Task.start` sem link nem supervisor, estado importante só na memória de um processo sem reconstrução.
    → Tudo sob a **supervision tree**; `Task.Supervisor`/`DynamicSupervisor`; let-it-crash **com estado reconstruível** (persistido/rehidratável). `references/concorrencia.md`.

45. **Bloquear o scheduler / mailbox sem limite / ingestão sem backpressure** — NIF/`:os.cmd`/trabalho pesado travando o scheduler, `GenServer` acumulando mensagens sem teto, consumo de fila sem `GenStage`/`Broadway`.
    → Trabalho pesado em `Task`/porta/dirty scheduler; backpressure real (`GenStage`/`Broadway`); timeouts e `max_demand`. `references/concorrencia.md`.

### IAM (identidade e autorização)

46. **Auth apensado ao escopo principal como monolith** (login/2FA/authz dentro do serviço principal, num Context `Auth` interno, sem serviço/front próprios; chave de assinatura junto do domínio).
    → Auth é **app separada** em `auth.<domain>`: **serviço Elixir/Phoenix** `<projeto>_auth_ex` + `<projeto>_authfront`, isolados; apps delegam por OIDC/OAuth2.1 + PKCE e validam por **JWKS público** (chave só no auth) (`references/iam.md` §1).

47. **Email/telefone como ID de usuário** (`user_id = email`, FK por email, login que assume 1 email), ou 2FA/recuperação com 1 fator só (reset por 1 email que pula o 2FA).
    → **ID interno imutável** (ULID/UUIDv7) como `sub`; email/telefone são identificadores N e verificáveis; **≥2 fatores sempre** (passkey/WebAuthn no núcleo — `wax`); **recuperação ≥ força do login**; senha em **argon2id** (`argon2_elixir`) + checagem HIBP (`references/iam.md` §2–§4).

48. **Autorização hand-rolled / no cliente / permissão embutida em token longo** — `if role == "admin"` espalhado pelos controllers/`GenServer`, checagem só no front, sem multi-tenant, papéis não-granulares.
    → **RBAC/ABAC granular por motor ReBAC** (OpenFGA/SpiceDB via client), **deny-default**, PDP=Check API / PEP=**plug Phoenix** em cada request, **enforcement server-side**, token fino, decisão auditada (`references/iam.md` §5).

49. **Logout que só apaga o cookie** (sessão recuperável por refresh/replay), ou sessão curta que chuta o usuário toda hora sem refresh silencioso.
    → **Logout irreversível** (revoga refresh+família, apaga sessão server-side, `jti` na denylist — Redis/ETS — consultada em toda request pelo PEP); **sessão 7d/90d** com refresh rotativo silencioso, detecção de reuso e multi-dispositivo (`references/iam.md` §6).

### Efeitos externos (e-mail, SMS, push, webhook, cobrança)

50. **Mandar de verdade fora de produção** — `Swoosh.Adapters.Resend`/SMTP real em dev/hml, `@gmail.com` (ou o seu e-mail) em fixture/seed/`ExMachina`/persona, laço de teste criando N contas com **Email OTP always-on** e nenhum contador no caminho.
    → **Adapter por ambiente em `config/runtime.exs`** (`Local`/`Test` fora de prd), **guard dentro do `Auth.Mailer`** (`{:error, {:external_recipient_blocked, to}}`, fail-closed), **cap por execução** (`:counters`, `MAIL_MAX_PER_RUN`) e endereço sintético só em `test.<domain>` com **null MX** (`references/iam.md` §3.1; normativa em `schematize-engineering/references/efeitos-externos.md`). Bounce/complaint em massa **queima IP e domínio** e derruba o OTP de login de **produção** — semanas de warm-up, utilidade zero.

> Regra de bolso: se a justificativa começa com "só pra funcionar", "depois eu arrumo", ou "é mais rápido assim" e o resultado mexe em segredo, auth, dado, registro, concorrência/supervisão, **ou toca o servidor por fora do fluxo/ops** — **provavelmente é uma macaquice desta lista. Para e faz certo.**
