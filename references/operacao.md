# operacao — recorte Elixir/OTP

> **PONTEIRO, não cópia.** A normativa deste tema é da base: **`schematize-engineering`** →
> `references/operacao.md`. Leia lá primeiro; aqui fica **só o que muda em Elixir/OTP**.
>
> **Onde este arquivo divergir da base, a BASE MANDA** (`SKILL.md` §"Precedência e herança").
> Este arquivo era um clone com **68%** de conteúdo
> idêntico à base — deriva por cópia foi o achado da Classe C da vistoria de 2026-08-21, e ela
> já tinha atingido piso de segurança (o `argon2id-only` da casa virou "ou PBKDF2" numa skill,
> o rol de 6 linguagens virou "só Go e Rust" em três). Manter uma cópia é manter a próxima deriva.
## Índice

- 20. Configuração — runtime, nunca compilada

- 21. Infraestrutura e Deploy — `mix release` (release OTP)

## 20. Configuração

**Princípio Elixir: config de runtime, NUNCA compilada.**

- **`config/runtime.exs` é a fonte de config em produção.** Roda **no boot da release**, no servidor, lendo `System.get_env/1`/`System.fetch_env!/1`. É onde entram URL de banco, segredos, portas, hosts. Piso 12-factor.

- **`config/config.exs`, `config/dev.exs`, `config/test.exs`, `config/prod.exs` são compilados** — valem só para o que não muda entre ambientes (ex.: qual adapter, qual logger backend). **VETADO** colocar segredo ou valor de ambiente aqui: fica embutido no `.beam` e vaza no artefato. Segredo em config compilada é violação (§37).

- **Validação tipada no boot — falha rápido (fail fast).** `System.fetch_env!/1` lança se faltar env obrigatória; a release **não sobe** sem a config mínima. Use `NimbleOptions`/schema explícito para validar shape e faixa. Sem `System.get_env` silencioso caindo em `nil`.

- **Sem hardcode.** Nada de URL, credencial, host ou flag chumbada no módulo.

- **Defaults seguros (fail closed):** ausência de flag = comportamento restrito, não permissivo. Feature nova nasce desligada (§31).

- **`releases.exs` legado não se usa** — foi substituído por `config/runtime.exs` (Elixir ≥ 1.11). Ver `references/stack-versoes.md`.

- **`RELEASE_*` e `env.sh.eex`:** variáveis específicas da release (cookie, nome do node, `RELEASE_DISTRIBUTION`, `RELEASE_NODE`) entram por `rel/env.sh.eex` gerado no `mix release.init` — nunca chumbadas. O seed global (`/<app>/.env`, `references/ops.md` §2) alimenta tudo isso.

## 21. Infraestrutura e Deploy

- **Artefato = release OTP (`mix release`).** O deploy **nunca** é código-fonte + `mix` no servidor; é a **release imutável** montada no CI a partir do commit SHA. `MIX_ENV=prod mix release` produz `_build/prod/rel/<app>/` com o ERTS embutido (ou `include_erts: false` quando o host tem a mesma OTP). O binário de entrada é `bin/<app>`.

- **Comandos da release (o que o ops chama — `references/ops.md`):**
  - `bin/<app> start` — sobe em foreground (o systemd usa isto, ver `references/ops.md` §3);
  - `bin/<app> daemon` — sobe destacado (não é o padrão da casa; preferimos foreground sob systemd);
  - `bin/<app> eval "Mod.fun()"` — roda função numa VM efêmera, **sem** subir a aplicação inteira (usado para migration, ver §21.3);
  - `bin/<app> remote` — conecta um IEx remoto ao node vivo (diagnóstico, §26);
  - `bin/<app> rpc "expr"` — executa expressão no node vivo e retorna;
  - `bin/<app> stop` / `restart` / `pid` / `versions`.

- **Config de runtime aplicada no boot** (`config/runtime.exs`, §20) — a release não carrega config compilada de ambiente.

- Container/host **non-root e read-only** (ver `references/ops.md` §3 para o systemd hardening; em contêiner, `USER` não-root, `readOnlyRootFilesystem`, ERTS e release em camada imutável).

- IaC: Terraform ou OpenTofu. CI/CD: GitHub Actions (monta a release, roda `mix test`/`credo`/`dialyzer`, publica o artefato).

- Promoção entre ambientes por **artefato imutável** (a mesma release, commit SHA rastreável). A release montada para hml é **exatamente** a promovida para prd — não se remonta.

- **VETADO editar código direto no servidor (hml/prd).** O servidor é **imutável por edição manual** — recebe só a release promovida do git. **VETADO** rodar `mix` à mão em prd (o `mix` nem existe na release — só o `bin/<app>`). Precauções: filesystem read-only, **drift detection** (recusa/alerta divergência com o git), acesso de escrita = break-glass auditado. Hotfix segue o mesmo fluxo, acelerado. Detalhe e o control plane em **`references/ops.md`**.

### 21.1 Estratégia de Deploy

- Rollback automatizado quando healthcheck falhar pós-deploy (volta à release anterior — `bin/<app> versions` lista as instaladas).

- Healthcheck gating: tráfego só vai pro node quando o endpoint de readiness (ex.: `/healthz` do Phoenix, `references/observabilidade.md`) responder ready — o que inclui supervisor de topo iniciado e pool do Ecto conectado.

- Janela de validação (drain de conexões abertas, LiveView/WebSocket incluídos) antes de declarar deploy bem-sucedido e derrubar a release antiga.

### 21.2 Hot-code-upgrade — a casa NÃO usa em prod por padrão

A BEAM suporta *hot-code-upgrade* (trocar código no node vivo via `appup`/`relup`, sem derrubar). **A casa NÃO usa hot upgrade em produção por padrão.** O deploy é **rolling restart** da release (novo node sobe, antigo drena e sai), operado pelo ops.

- **Motivo:** `appup`/`relup` são de escrita e teste caros, frágeis a mudança de estado de processo, e o ganho (não perder o estado em memória) é desnecessário quando o estado durável está no banco/cache (piso: estado recuperável, `references/dados-eventos.md`) e a topologia tolera reinício (supervisores religam, filas re-processam).

- **Rolling restart é o padrão** porque é reprodutível, diffável, e casa com o deploy destrutivo por seed do ops (`references/ops.md` §2).

- **Exceção — só com ADR (§27).** Usar hot upgrade num serviço específico (ex.: componente de telefonia/soft-realtime onde derrubar o node custa sessões vivas irrecuperáveis) exige ADR registrando o motivo, o custo de manutenção do `relup`, o teste do upgrade **e** do downgrade, e quem é dono. Sem ADR, é rolling restart.

### 21.3 Migrations no deploy da release

Migration **não** roda com `mix ecto.migrate` em prd (não há `mix` na release). Roda por uma **função de release** invocada via `eval`, numa VM efêmera, **antes** do node de aplicação subir:

```
bin/<app> eval "MyApp.Release.migrate()"
```

- O módulo `MyApp.Release` (padrão do `mix phx.gen.release`) chama `Ecto.Migrator.run/4` para cada repo, carregando as apps sem iniciá-las (`Application.load/1`, não `ensure_all_started`). Isso evita subir a aplicação inteira só para migrar.

- **Migration reversível obrigatória** (`up`/`down` ou `change` reversível) — o ops preserva os dados no redeploy destrutivo (`references/ops.md` §2). Migration destrutiva de dados é gated, dev/hml, nunca automática.

- Ordem no ops: `migrate` (efêmero, `eval`) → sobe o node de aplicação → healthcheck. Serialização mínima e declarada (`references/ops.md` §5–§6).

### 21.4 Preview Environments

- PRs em serviços principais geram ambiente efêmero automaticamente (release montada do branch, node com cookie/nome isolados).

## 24. Qualidade e Git

- ≥ 1 reviewer (≥ 2 para contexto de domínio, schema/migration, segurança).

- CI verde obrigatório: `mix test`, `mix format --check-formatted`, `mix credo --strict`, `mix dialyzer`, `mix deps.audit`/`mix hex.audit` (`references/stack-versoes.md`).

## 25. Ownership

- Cada serviço (release/app OTP) tem **owner explícito** (squad ou pessoa).

## 26. Runbooks e Incidentes

### 26.1 Runbooks

- Conteúdo mínimo Elixir: como abrir console remoto seguro (`bin/<app> remote` — read-mostly, ação de escrita só com registro), dashboards de `:telemetry`/Phoenix LiveDashboard, como inspecionar supervisão e mailbox (`:observer`/`:recon` em ambiente controlado, ver `references/concorrencia.md`), como ler `crash dump` (`erl_crash.dump`), como forçar rollback de release, contatos.

- **Console remoto é gated:** `bin/<app> remote`/`rpc` em prd é break-glass auditado (o mesmo regime de exceção de `references/ops.md` §1) — abre-se para diagnosticar, não para operar. Operar é pelo ops.

### 26.2 Incidentes

- RCA (root cause analysis) documentado — na BEAM, inclua a árvore de supervisão envolvida, se houve *restart storm*/`max_restarts` estourado, mailbox crescente ou processo travado (ver `references/concorrencia.md`).

## 27. ADR — Architecture Decision Records

**Quando criar:** escolha de banco/broker/lib núcleo (Phoenix/Ecto/Oban/Broadway/Bandit vs Cowboy — `references/stack-versoes.md`), padrão arquitetural (umbrella vs apps separados, CQRS), bump de major de Elixir/OTP/Phoenix, uso de `hot upgrade` (§21.2), uso de NIF/`unsafe`/porta nativa, mudança de contrato público, qualquer desvio deste documento (exceto itens VETADO, que não admitem exceção).

## 28. Archive de Conversas e Tarefas — INEGOCIÁVEL

> **Esta seção não tem modo "pula pra ir mais rápido".** O archive é parte da entrega, não um extra. Tarefa sem archive = tarefa não feita (§35). Gerar os `.md` é tão obrigatório quanto compilar a release.

### 28.0 Layout canônico — todo MD gerado no archive, root limpo (MUST)

**Todo `.md` gerado pela skill/agente mora em `<projeto>_archive/`, NUNCA no root do projeto.** Isso vale para MAPA, índices, planos, relatórios, handoffs, checkpoints — qualquer artefato gerado. O root do projeto fica **limpo**: só código, config e os poucos MDs de projeto mantidos à mão por humano (`README.md`, `CLAUDE.md`, `LICENSE`, e o `CHANGELOG.md`). Largar MAPA/índice/plano/relatório no root é **violação** (§37) e fere a contenção de workspace.

Subpastas canônicas (o archive **é versionado** — entra no PR):

### 28.1 Chat Archive

- Escolha de tecnologia (lib núcleo, adapter, servidor HTTP — `references/stack-versoes.md`)
