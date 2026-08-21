# IAM — Identidade e Autorização da casa (piso inegociável, angle Elixir)

Piso normativo de **identidade, autenticação e autorização** da casa, especializado para
**backend Elixir** (o serviço de auth é um microserviço Elixir sobre Phoenix/Plug/OTP).
**Todo projeto começa com um IAM robusto por desenho** — segurança é inegociável. A base
agnóstica vive na `schematize-engineering` (`references/iam.md`); aqui ela ganha a topologia
de serviço, as libs do Hex e os padrões OTP da casa. O teste adversarial vive na
`schematize-pentest`.

> **Pow/Assent/`mix phx.gen.auth` NÃO são a solução completa.** `mix phx.gen.auth` scaffolda
> um cadastro/login com sessão e `Ecto.Changeset`; **Pow** cobre registro/reset/lembrar;
> **Assent** cobre OAuth2/OIDC de terceiros. Tudo isso **scaffolda partes**, mas **não
> substitui o desenho da casa**: app de auth SEPARADA em `auth.<domain>`, ID≠email, ≥2 fatores
> por desenho, ReBAC multi-tenant, sessão longa e logout irreversível. Use-os como peças
> internas do `<projeto>_auth_ex`, nunca como "o auth já está pronto".

## 1. Topologia — auth é uma APLICAÇÃO SEPARADA (microserviço Elixir)

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

- **Identificador só vale verificado** — não loga nem recupera sem verificação (`verified_at`
  não-nulo).

- **SSO nunca é ponto único de falha:** cadastro via SSO (via **Assent**) **força ≥1 fator de
  recuperação local** (email de recuperação + códigos de backup), pra provedor banido ≠ conta
  perdida.

## 3. Fatores e níveis de garantia (AAL — NIST 800-63B)

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
  > **Parâmetros mínimos (`m` ≥ 19 MiB, `t` ≥ 2, `p` = 1, salt ≥ 16 B CSPRNG, string codificada
  > guardada inteira, re-hash preguiçoso):** na base — `schematize-engineering`, seu
  > `references/iam.md`, seção **2.1 ("Hash de senha — argon2id com parâmetros MÍNIMOS")**.
  > **Nenhuma das 8 skills fixava os números** até 2026-08-21 — e argon2id mal parametrizado é
  > mais fraco que bcrypt bem configurado. Calibre para ~0,5–1 s no hardware do auth e registre
  > o valor medido no ADR do serviço; o default da lib normalmente é o mais fraco. No `argon2_elixir` os custos vêm de config — *"custo adequado" não é número*; fixe `m_cost`/`t_cost`.

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

## 3.1 Disparo do Email OTP fora de prd — sink por default e guard no `Mailer`

O Email OTP é **always-on** (§3): é o auth que manda e-mail em **todo** cadastro, login, troca
de fator e recuperação — inclusive em dev/hml e em **cada volta** de um laço de teste. Por isso
o piso de **efeito externo** da casa incide **primeiro aqui**. A normativa completa (4 camadas,
DNS do domínio de teste, exceção com ADR, runbook de contenção) é a **`schematize-engineering`
→ `references/efeitos-externos.md`**; abaixo está **só o recorte Elixir**.

**Regra:** fora de `prd`, **nenhum e-mail chega em ninguém**. Destinatário sintético só no
**domínio de teste em ROTA NULA** (`test.<domain>` com null MX (RFC 7505) + SPF `v=spf1 -all` +
DMARC `p=reject`, ou TLD reservado `.test`/`.invalid`/`.example`). **VETADO** `@gmail.com` — ou
qualquer caixa real, **inclusive a sua** — em fixture, seed, factory, persona ou demo. **Motivo:**
bounce/complaint em massa **queima o IP e o domínio**, derruba o transacional de produção — a
começar pelo **próprio OTP de login desta §3** — e custa semanas de warm-up. Não tem undo.

### Adapter por ambiente em `config/runtime.exs` — nunca em config compilado

Segredo de provedor **não vai em `config/*.exs` compilado** (`references/seguranca.md` §13.4):
o adapter e a chave são resolvidos **em runtime**, **uma vez**, na configuração — **nunca** no
chamador.

```elixir
# config/runtime.exs
import Config

# Ambiente DECLARADO. Ausente ⇒ assume não-prd (fail-closed): o modo seguro é o default.
app_env = System.get_env("APP_ENV") || "dev"

config :auth,
  env: app_env,
  # Domínios aceitos como destinatário fora de prd (rota nula / TLD reservado).
  test_mail_domains: ~w(test.example.com test invalid example),
  # Allowlist nominal (≤5) da exceção com ADR aceito — vazia por padrão.
  mail_allowlist: [],
  mail_max_per_run: String.to_integer(System.get_env("MAIL_MAX_PER_RUN") || "50")

case app_env do
  "prd" ->
    # Só prd fala com o provedor real — e a chave é obrigatória: sem ela a release NÃO sobe.
    config :auth, Auth.Mailer.Transport,
      adapter: Resend.Swoosh.Adapter,
      api_key: System.fetch_env!("RESEND_API_KEY")

  "test" ->
    # ExUnit: entrega na mailbox do processo de teste (Swoosh.TestAssertions).
    config :auth, Auth.Mailer.Transport, adapter: Swoosh.Adapters.Test

  _ ->
    # dev/hml: caixa local inspecionável — nada sai da máquina.
    config :auth, Auth.Mailer.Transport, adapter: Swoosh.Adapters.Local
end
```

- **`Swoosh.Adapters.Local`** guarda os e-mails em memória e serve a **UI do mailbox** para
  inspeção. Exponha a rota **só fora de prd**:

  ```elixir
  # lib/auth_web/router.ex
  if Application.compile_env(:auth, :dev_routes) do
    scope "/dev" do
      pipe_through :browser
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
  ```

- Em **hml** (multi-nó, mais de um processo), prefira **Mailpit** — SMTP local +
  **API HTTP** — via `Swoosh.Adapters.SMTP` apontado ao container: o teste **lê a caixa** por
  HTTP em vez de adivinhar se saiu.

- Chave de não-prd é **sandbox**, nunca a de prd (`references/ops.md`: seed por ambiente); em
  dev/hml o **egress SMTP (25/465/587) fica bloqueado** — a 3ª camada, na `schematize-infra`.

### O guard mora DENTRO do `Mailer` — o chamador não escolhe e não burla

`use Swoosh.Mailer` fica num módulo **interno de transporte** (`Auth.Mailer.Transport`); o único
módulo público é `Auth.Mailer`, e o `deliver/1` dele **valida antes de entregar**. Assim não
existe "chamei o Swoosh direto" — e o gate do CI trava quem tentar (`Transport` só pode aparecer
dentro de `Auth.Mailer`).

```elixir
defmodule Auth.Mailer.Transport do
  @moduledoc """
  Transporte Swoosh cru do auth.

  PRIVADO por convenção: **só** o `Auth.Mailer` pode chamá-lo, porque é ele que aplica o guard
  de efeito externo. Referência a este módulo fora do `Auth.Mailer` é violação de piso (gate no CI).
  """
  use Swoosh.Mailer, otp_app: :auth
end

defmodule Auth.Mailer do
  @moduledoc """
  Única porta de saída de e-mail do auth (Email OTP, verificação de identificador, avisos).

  Deny-by-default fora de `prd`: destinatário que não seja do domínio de teste é **erro**,
  nunca warning nem no-op silencioso. Ver `schematize-engineering/references/efeitos-externos.md`.
  """
  alias Auth.Mailer.{Quota, Transport}
  require Logger

  @typedoc "Recusa do guard — nada foi entregue."
  @type block ::
          {:external_recipient_blocked, String.t()}
          | {:mail_cap_exceeded, pos_integer()}

  @doc """
  Entrega o e-mail **depois** de provar que ele pode sair neste ambiente.

  O quê: valida todos os destinatários (`to`, `cc`, `bcc`) contra o domínio de teste, consome
  uma unidade do teto por execução e só então chama o transporte Swoosh.
  Onde: toda emissão de Email OTP (§3), verificação de e-mail e notificação de segurança.
  Efeitos: envia (em prd) ou grava no sink; emite `[:auth, :mail, :sent]` via `:telemetry`.

  Retorna `{:error, {:external_recipient_blocked, endereço}}` quando um destinatário externo
  aparece fora de `prd`, e `{:error, {:mail_cap_exceeded, teto}}` quando a execução estoura o
  `MAIL_MAX_PER_RUN`.
  """
  @spec deliver(Swoosh.Email.t()) :: {:ok, term()} | {:error, block() | term()}
  def deliver(%Swoosh.Email{} = email) do
    with :ok <- assert_deliverable(email),
         :ok <- Quota.take() do
      Transport.deliver(email)
    end
  end

  # Deny-by-default: fora de prd só passa domínio de teste ou allowlist nominal (ADR).
  # Endereço malformado (sem exatamente um "@") NÃO passa — fail-closed.
  @spec assert_deliverable(Swoosh.Email.t()) ::
          :ok | {:error, {:external_recipient_blocked, String.t()}}
  defp assert_deliverable(%Swoosh.Email{to: to, cc: cc, bcc: bcc}) do
    (List.wrap(to) ++ List.wrap(cc) ++ List.wrap(bcc))
    |> Enum.map(fn {_name, address} -> address end)
    |> Enum.reduce_while(:ok, fn address, :ok ->
      if deliverable?(address) do
        {:cont, :ok}
      else
        Logger.error(
          "mail BLOQUEADO: #{redact(address)} em env=#{env()}. Nada foi enviado. " <>
            "Use <papel>+<run-id>-<n>@test.<domain> ou registre o ADR de exceção."
        )

        {:halt, {:error, {:external_recipient_blocked, address}}}
      end
    end)
  end

  @doc false
  # Log de auditoria identifica o envio; NÃO expõe a caixa. `alguem@acme.com` vira
  # `al***@acme.com`. Segredo (OTP, token, link mágico) não entra em log de nível nenhum.
  @spec redact(String.t()) :: String.t()
  def redact(address) when is_binary(address) do
    case String.split(address, "@") do
      [local, domain] -> String.slice(local, 0, 2) <> "***@" <> domain
      _ -> "***"
    end
  end

  def redact(_), do: "***"

  @spec deliverable?(String.t()) :: boolean()
  defp deliverable?(address) do
    env() == "prd" or test_domain?(address) or
      String.downcase(address) in Application.get_env(:auth, :mail_allowlist, [])
  end

  # Exatamente um "@" E local part não-vazia. Sem a checagem da local part, `"@test"`
  # casaria com o domínio de teste `test` e passaria pelo guard sendo um endereço
  # malformado — a mesma armadilha do `split("@") |> last` das outras stacks.
  @spec test_domain?(String.t()) :: boolean()
  defp test_domain?(address) do
    case String.split(address, "@") do
      [local, domain] when local != "" and domain != "" ->
        domain = String.downcase(domain)
        Enum.any?(test_domains(), &(domain == &1 or String.ends_with?(domain, "." <> &1)))

      _ ->
        false
    end
  end

  # Config ausente ⇒ NÃO-prd. Nunca o contrário: o default seguro é o que não entrega.
  @spec env() :: String.t()
  defp env, do: Application.get_env(:auth, :env, "dev")

  @spec test_domains() :: [String.t()]
  defp test_domains, do: Application.get_env(:auth, :test_mail_domains, ~w(test invalid example))
end
```

### Cap por execução com `:atomics` (o freio que faltou nos 5.000)

Contador **atômico**, sem processo no caminho quente — um `GenServer` de contador seria gargalo
e SPOF (`references/concorrencia.md`; anti-padrão §37 *"GenServer como contador/cache global no caminho quente"* — citado por título, porque a numeração dos itens do §37 diverge entre skills).

**Por que `:atomics` e não `:counters`:** `:counters` não tem operação de *incrementar e ler* em
um passo. `add` seguido de `get` são DUAS operações, e entre elas outro processo incrementa — o
valor lido não é o desta chamada (TOCTOU). O erro é conservador (bloqueia a mais, nunca a menos),
mas o contador que existe para ser o **freio** do disparo em massa não pode ter race. `:atomics`
tem `add_get/3`: incrementa e devolve o valor resultante atomicamente.

```elixir
defmodule Auth.Mailer.Quota do
  @moduledoc """
  Teto de e-mails por execução (`MAIL_MAX_PER_RUN`, default 50) + abort ao estourar.

  Usa `:atomics` guardado em `:persistent_term`: leitura O(1), sem cópia, sem processo
  intermediário, e `add_get/3` atômico (incrementa e devolve em UM passo).
  """
  @key {__MODULE__, :counter}

  @doc "Cria o contador. Chame no `Auth.Application.start/2`, ANTES da árvore de supervisão."
  @spec setup() :: :ok
  def setup, do: :persistent_term.put(@key, :atomics.new(1, signed: false))

  @doc """
  Consome uma unidade do teto.

  O quê: incrementa e compara com o teto configurado, atomicamente. Onde:
  `Auth.Mailer.deliver/1`, antes do transporte. Retorna `{:error, {:mail_cap_exceeded, teto}}`
  quando estoura — o chamador **aborta** o job/laço; não tenta de novo.

  O cap vale em **TODOS** os ambientes, inclusive `prd`: ele não é uma das camadas de sandbox,
  é o freio contra laço em massa (ADR-0004). Em prd, dimensione `MAIL_MAX_PER_RUN` para o
  volume real.
  """
  @spec take() :: :ok | {:error, {:mail_cap_exceeded, pos_integer()}}
  def take do
    max = Application.get_env(:auth, :mail_max_per_run, 50)
    ref = :persistent_term.get(@key)

    case :atomics.add_get(ref, 1, 1) do
      n when n > max -> {:error, {:mail_cap_exceeded, max}}
      _ -> :ok
    end
  end

  @doc "Zera o contador. Só em teste (`setup` do ExUnit) — em prd o teto vale pela execução."
  @spec reset() :: :ok
  def reset, do: :atomics.put(:persistent_term.get(@key), 1, 0)
end
```

### O teste que vê o vermelho (ExUnit)

O guard sem teste é intenção. O teste **tenta** o `@gmail.com` e **espera a recusa** — e prova
que **nada** saiu.

```elixir
defmodule Auth.MailerTest do
  use ExUnit.Case, async: true
  import Swoosh.TestAssertions

  setup do
    Auth.Mailer.Quota.reset()
    :ok
  end

  test "recusa destinatário externo fora de prd e não entrega nada" do
    email = Auth.Notifier.otp_email("vitima@gmail.com", "123456")

    assert {:error, {:external_recipient_blocked, "vitima@gmail.com"}} = Auth.Mailer.deliver(email)
    assert_no_email_sent()
  end

  test "entrega para o domínio de teste em rota nula" do
    to = "login+#{System.unique_integer([:positive])}@test.example.com"
    email = Auth.Notifier.otp_email(to, "123456")

    assert {:ok, _metadata} = Auth.Mailer.deliver(email)
    assert_email_sent(email)
  end

  test "aborta ao estourar o cap por execução" do
    original = Application.get_env(:auth, :mail_max_per_run)
    Application.put_env(:auth, :mail_max_per_run, 2)
    on_exit(fn -> Application.put_env(:auth, :mail_max_per_run, original) end)

    email = Auth.Notifier.otp_email("carga+1@test.example.com", "123456")

    assert {:ok, _} = Auth.Mailer.deliver(email)
    assert {:ok, _} = Auth.Mailer.deliver(email)
    assert {:error, {:mail_cap_exceeded, 2}} = Auth.Mailer.deliver(email)
  end
end
```

Fixtures e `ExMachina`: o `sequence(:email, &"user+#{&1}@test.example.com")` da factory usa **o
domínio de teste**. Detalhe de seeds/personas na `schematize-qa` (seeds e personas, `references/execucao.md` secao 4)).

## 4. Fluxos

**Onboarding:** cita um email → **verifica** → **cria senha** (ou já passkey/app) → **pronto:
2FA baseline (senha + Email OTP) e acesso baseline pleno**. Só **depois**, já dentro, o sistema
**sugere** (nudge, não obriga) reforçar: 2º email de backup + fator forte. **Nunca se barra o
acesso por não ter fator forte** — ele é pedido *just-in-time* na 1ª ação sensível (step-up)
ou sob risco (§9).

## 5. Multi-tenant + RBAC/ABAC — motor ReBAC (estilo Zanzibar)

- **Escrita de tuplas** (membership, atribuição de papel, parentesco de recurso) acontece no
  contexto de domínio via cliente do motor, **transacional com o efeito de negócio** (padrão
  **outbox** via Oban quando o motor é externo — nunca dual-write solto).

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

- **Refresh rotativo com detecção de reuso** (reusou um refresh já rotacionado → revoga a
  **família** inteira). O refresh token é opaco (**`:crypto.strong_rand_bytes`**), hasheado no
  store; a família e o `jti` são rastreados server-side.

- **Botão "Sair" bem visível → kill IRREVERSÍVEL da sessão:** não basta apagar o cookie —
  o handler de logout **revoga o refresh token (e a família), apaga o registro de sessão
  server-side, joga o `jti` na denylist (Redis via Redix / DB) até expirar e desassocia o
  push token do device**. Depois do logout, aquela sessão é irrecuperável: nem replay, nem
  refresh, nem "voltar o cookie" reativa. O Plug de validação de access token **consulta a
  denylist de `jti`** a cada request (cache curto via `Cachex`).

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

- **Notifica o usuário:** login novo/suspeito, novo device, mudança de credencial → aviso nos
  canais verificados, com "não fui eu" (revoga + força reforço).

### Transversais (sempre)

- **Audit log imutável** de toda decisão authn/authz e mudança de credencial — alimenta a
  forense e os testes (liga com a observabilidade LGTM+ da casa; `trace_id` propagado via
  `Logger.metadata`/OpenTelemetry no fluxo de login/authz).

- **Libs de apoio (Hex):** `argon2_elixir` (hash), `guardian`/`joken`+`joken_jwks`/`jose`
  (JWT/JWKS), `wax` (passkey/WebAuthn), `nimble_totp` (TOTP), `assent` (SSO/OAuth2),
  `swoosh` (email/Resend), `ecto_ulid`/`uniq` (ID), `ecto_sql`/Postgres (persistência),
  `redix`/`cachex` (sessão/denylist/cache), `oban` (jobs/outbox/atraso cancelável), cliente do
  motor ReBAC (OpenFGA/SpiceDB). Nenhuma chave privada fora do `<projeto>_auth_ex`.

## Roadmap de fases

- **F1** 2FA baseline por desenho (senha + Email OTP, sem muro pré-login) + fluxos (TOTP via
  `nimble_totp`/push, **passkey** via `wax`, escolha de método, invariante de troca, **nudge**
  de fator forte, step-up just-in-time, **risk engine adaptativo**: score, 2FA→3FA, negação
  deceptiva/tarpit, honeypot).

- **F2** Multi-tenant + **ReBAC** (membership, papéis granulares, PDP/PEP como `Plug`,
  deny-default, token fino, audit).

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

- [ ] **Efeito externo não sai de não-prd (§3.1):** adapter por ambiente em `config/runtime.exs` (`Swoosh.Adapters.Local`/`Test` fora de prd, Resend só em prd), **guard dentro do `Auth.Mailer`** (destinatário fora do domínio de teste ⇒ `{:error, {:external_recipient_blocked, _}}`), **cap por execução** (`:atomics`, `add_get/3`), chave sandbox, e **teste ExUnit que espera a recusa**; nenhum `@gmail.com` em fixture/seed/persona.

- [ ] Rotina agressiva de testes cross-tenant/priv-esc no CI (schematize-pentest); scaffold/auditoria por `/elixir-iam`.
