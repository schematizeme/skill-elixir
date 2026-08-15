# Operação: Config, Deploy, Git, Archive, ADR, IA e Anexos

> **Dividida:** §29+ (templates, feature flags, IA assistida, DoD §35, evolução, índice §39) estão em `references/entrega.md`. A numeração de seções é contínua entre os dois arquivos.

> Parte da skill **schematize-elixir**. As referências cruzadas (§N) apontam para seções do corpo completo — todas presentes no conjunto de references desta skill. Concorrência/BEAM: `references/concorrencia.md`. Base agnóstica de linguagem: `schematize-engineering`. Teste de segurança: `schematize-pentest`.

## Índice
- 20. Configuração — runtime, nunca compilada
- 21. Infraestrutura e Deploy — `mix release` (release OTP)
- 24. Qualidade e Git
- 25. Ownership
- 26. Runbooks e Incidentes
- 27. ADR — Architecture Decision Records
- 28. Archive de Conversas e Tarefas — INEGOCIÁVEL
- 29. Templates
- 31. Feature Flags
- 34. Uso de IA Assistida
- 35. Definition of Done
- 36. Evolução
- 39. Índice de Funcionalidades (fonte da verdade viva)
- Anexo A — Versões Correntes
- Anexo B — Glossário Mínimo

---

## 20. Configuração

**Princípio Elixir: config de runtime, NUNCA compilada.**

- **`config/runtime.exs` é a fonte de config em produção.** Roda **no boot da release**, no servidor, lendo `System.get_env/1`/`System.fetch_env!/1`. É onde entram URL de banco, segredos, portas, hosts. Piso 12-factor.
- **`config/config.exs`, `config/dev.exs`, `config/test.exs`, `config/prod.exs` são compilados** — valem só para o que não muda entre ambientes (ex.: qual adapter, qual logger backend). **VETADO** colocar segredo ou valor de ambiente aqui: fica embutido no `.beam` e vaza no artefato. Segredo em config compilada é violação (§37).
- **Validação tipada no boot — falha rápido (fail fast).** `System.fetch_env!/1` lança se faltar env obrigatória; a release **não sobe** sem a config mínima. Use `NimbleOptions`/schema explícito para validar shape e faixa. Sem `System.get_env` silencioso caindo em `nil`.
- **Sem hardcode.** Nada de URL, credencial, host ou flag chumbada no módulo.
- **Defaults seguros (fail closed):** ausência de flag = comportamento restrito, não permissivo. Feature nova nasce desligada (§31).
- **`releases.exs` legado não se usa** — foi substituído por `config/runtime.exs` (Elixir ≥ 1.11). Ver `references/stack-versoes.md`.
- **`RELEASE_*` e `env.sh.eex`:** variáveis específicas da release (cookie, nome do node, `RELEASE_DISTRIBUTION`, `RELEASE_NODE`) entram por `rel/env.sh.eex` gerado no `mix release.init` — nunca chumbadas. O seed global (`/<app>/.env`, `references/ops.md` §2) alimenta tudo isso.

---

---

## 21. Infraestrutura e Deploy

**MUST**
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
- Ambientes isolados: `dev` (local), `hml`/`staging` (homologação), `production`/`prd`.
- Promoção entre ambientes por **artefato imutável** (a mesma release, commit SHA rastreável). A release montada para hml é **exatamente** a promovida para prd — não se remonta.
- **Fluxo de promoção fixo, sem atalho:** `desenvolvimento local → teste local (verde) → GitHub → hml → prd`. Nada pula etapa; **nada vai direto pra hml/prd**.
- **VETADO editar código direto no servidor (hml/prd).** O servidor é **imutável por edição manual** — recebe só a release promovida do git. **VETADO** rodar `mix` à mão em prd (o `mix` nem existe na release — só o `bin/<app>`). Precauções: filesystem read-only, **drift detection** (recusa/alerta divergência com o git), acesso de escrita = break-glass auditado. Hotfix segue o mesmo fluxo, acelerado. Detalhe e o control plane em **`references/ops.md`**.
- **Toda operação no servidor passa pelo `<projeto>_ops`** (§2, `references/ops.md`): install/update/config/migrate/rollback/troubleshoot — nunca à mão. Instalação **paralela por padrão** (= `nproc`); falha no paralelo = serviços não independentes → corrigir a independência é prioridade máxima (piso 10).

### 21.1 Estratégia de Deploy

| Estratégia | Quando usar |
|---|---|
| Rolling restart | Default para serviços comuns — sobe a release nova, drena a antiga |
| Blue/green | Serviços críticos, rollback instantâneo necessário |
| Canary | Mudanças de alto impacto, rollouts graduais |

**MUST**
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

**SHOULD**
- PRs em serviços principais geram ambiente efêmero automaticamente (release montada do branch, node com cookie/nome isolados).
- Destruído ao merge ou após X dias de inatividade.

---

---

## 24. Qualidade e Git

**Commits:** Conventional Commits.
**Versionamento:** SemVer (o `version:` do `mix.exs` acompanha).

**Branches — trunk-based como padrão**

```
main      → produção (protegida, linear history)

feature/<ticket>-<slug>
fix/<ticket>-<slug>
hotfix/<ticket>-<slug>
```

GitFlow (`develop`) é opcional e exige justificativa — só vale a pena em times com release cadenciado pesado.

**Pull Requests**
- Tamanho alvo: ≤ 400 linhas alteradas.
- ≥ 1 reviewer (≥ 2 para contexto de domínio, schema/migration, segurança).
- **CODEOWNERS obrigatório.**
- CI verde obrigatório: `mix test`, `mix format --check-formatted`, `mix credo --strict`, `mix dialyzer`, `mix deps.audit`/`mix hex.audit` (`references/stack-versoes.md`).
- Squash merge na `main`.
- **Merge direto na `main` é VETADO.** Force push em branch protegida idem (§37).

---

---

## 25. Ownership

**MUST**
- Cada serviço (release/app OTP) tem **owner explícito** (squad ou pessoa).
- `CODEOWNERS` configurado.
- Documentação de **oncall** definida.
- Contato de escalação documentado no README.

---

---

## 26. Runbooks e Incidentes

### 26.1 Runbooks

**MUST**
- Serviços críticos têm runbook em `/docs/runbook.md`.
- Conteúdo mínimo Elixir: como abrir console remoto seguro (`bin/<app> remote` — read-mostly, ação de escrita só com registro), dashboards de `:telemetry`/Phoenix LiveDashboard, como inspecionar supervisão e mailbox (`:observer`/`:recon` em ambiente controlado, ver `references/concorrencia.md`), como ler `crash dump` (`erl_crash.dump`), como forçar rollback de release, contatos.
- **Console remoto é gated:** `bin/<app> remote`/`rpc` em prd é break-glass auditado (o mesmo regime de exceção de `references/ops.md` §1) — abre-se para diagnosticar, não para operar. Operar é pelo ops.
- Incidentes recorrentes atualizam o runbook.

### 26.2 Incidentes

**MUST**
- Postmortem **blameless** para todo incidente Sev1/Sev2.
- RCA (root cause analysis) documentado — na BEAM, inclua a árvore de supervisão envolvida, se houve *restart storm*/`max_restarts` estourado, mailbox crescente ou processo travado (ver `references/concorrencia.md`).
- Ações preventivas rastreáveis (issue/task) com prazo.
- Repositório central de postmortems acessível ao time.

---

---

## 27. ADR — Architecture Decision Records

Toda decisão arquitetural relevante vira ADR.

```
/docs/adr/
  0001-use-postgresql.md
  0002-oban-vs-broadway-para-ingestao.md
  0003-hot-upgrade-no-servico-de-voz.md
```

Formato MADR. Status: `proposed`, `accepted`, `deprecated`, `superseded by NNNN`.

**Quando criar:** escolha de banco/broker/lib núcleo (Phoenix/Ecto/Oban/Broadway/Bandit vs Cowboy — `references/stack-versoes.md`), padrão arquitetural (umbrella vs apps separados, CQRS), bump de major de Elixir/OTP/Phoenix, uso de `hot upgrade` (§21.2), uso de NIF/`unsafe`/porta nativa, mudança de contrato público, qualquer desvio deste documento (exceto itens VETADO, que não admitem exceção).

---

---

## 28. Archive de Conversas e Tarefas — INEGOCIÁVEL

> **Esta seção não tem modo "pula pra ir mais rápido".** O archive é parte da entrega, não um extra. Tarefa sem archive = tarefa não feita (§35). Gerar os `.md` é tão obrigatório quanto compilar a release.

**Princípio:** todo trabalho que produz código, decisão ou mudança de estado **gera registro em Markdown, TODA vez, sem exceção**. Não existe "depois eu documento". O `.md` nasce junto com o trabalho e é commitado junto.

### 28.0 Layout canônico — todo MD gerado no archive, root limpo (MUST)

**Todo `.md` gerado pela skill/agente mora em `<projeto>_archive/`, NUNCA no root do projeto.** Isso vale para MAPA, índices, planos, relatórios, handoffs, checkpoints — qualquer artefato gerado. O root do projeto fica **limpo**: só código, config e os poucos MDs de projeto mantidos à mão por humano (`README.md`, `CLAUDE.md`, `LICENSE`, e ADRs se o projeto os versiona em `docs/adr/`). Largar MAPA/índice/plano/relatório no root é **violação** (§37) e fere a contenção de workspace.

Subpastas canônicas (o archive **é versionado** — entra no PR):

```
<projeto>_archive/
  index/         # MAPA.md + INDEX_GLOBAL.md + INDEX_FUNCTIONS.md (ou INDEX_COMPONENTS.md) — regenerados no lugar
  context/       # handoff/checkpoint de contexto (§34.1)
  orchestration/ # plano + checkpoint de fan-out/paralelização (references/orquestracao.md)
  pentest/       # ENDPOINTS.md + relatórios (schematize-pentest)
  chat/          # §28.1
  task/          # §28.2
```

**Regra de bolso:** antes de gravar qualquer `.md`, o caminho começa com `<projeto>_archive/`. Se você ia escrever no root, pare e mova pro archive.

### 28.1 Chat Archive

**MUST — gerar SEMPRE** para conversas/sessões que produzem:
- Decisão arquitetural ou de segurança
- Mudança de contrato público
- Escolha de tecnologia (lib núcleo, adapter, servidor HTTP — `references/stack-versoes.md`)
- Resolução de incidente
- **Qualquer geração de código não trivial** (inclui código assistido por IA — §34)

**SHOULD** para tasks de implementação significativas.
**MAY** para o resto (troca trivial, dúvida pontual).

```
<project>_archive/chat/
  <YYYY-MM-DD-HH-MM-SS>-<contexto>.md
```

Conteúdo mínimo (todos os campos preenchidos, nunca placeholder vazio):
- Pergunta/objetivo original
- Entendimento do problema
- Resposta/decisão tomada
- Alternativas consideradas
- Riscos e trade-offs
- Próximos passos

### 28.2 Task Archive

**MUST — gerar SEMPRE** para toda task de implementação significativa.

```
<project>_archive/task/
  <task-name>.md
```

Conteúdo: contexto, objetivo, checklist, decisões, blockers, progresso. **Atualizar ao fim de cada sessão** — não acumular pra depois.

### 28.3 Garantias de processo

**MUST**
- O archive é **verificável**: PR sem o `.md` correspondente (quando a regra acima exige) **não passa no review** (item de checklist de §35).
- Gerar o archive é passo do fluxo, não tarefa separada que pode ser cortada por falta de tempo. **Falta de tempo não revoga a §28.**
- Assistente de IA que produz código nesta base **gera o `.md` do archive na mesma entrega** — pular isso é violação direta (§37, item 28).

> Registro indiscriminado de toda interação produz ruído. Registro seletivo do que importa produz contexto histórico útil. **Mas "seletivo" é sobre o quê registrar, nunca sobre se registrar quando a regra manda.**

---

---
