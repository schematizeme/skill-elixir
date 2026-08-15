# Testes — Execução, Pentest e Q.A.

> Parte da skill **schematize-elixir**. Continuação de `testes.md` (numeração **preservada**, §22.4+): padrão de script de teste, seeds/personas, integração com CI (`mix`), pentest (§22.7–22.8), fluxo de Q.A. plan-first (§22.9) e o Makefile/aliases `mix` (§23).

---

### 22.4 Padrão de script (`tests/<mode>/<name>.sh`)

Skeleton obrigatório (o bundlado `scripts/test-skeleton.sh` é o ponto de partida; copie pra `tests/<mode>/<name>.sh`). O script bate na **API HTTP viva** — é agnóstico do BEAM, o alvo é o deploy real, não o `mix test`:

```bash
#!/usr/bin/env bash
# <Categoria> · <Nome curto>
# Descrição clara do que cobre e o esperado.
# Esperado: status X em caso Y. Falha = significado Z.

set -uo pipefail
_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib.sh
source "$_DIR/lib.sh"

test_section "<Categoria> · <Nome>"

API="$(api_base)"

# Caso 1
assert_http_in "<descrição do caso>" "200|401" GET "$API/v1/<rota>"

# Caso 2 — body shape
http_call GET "$API/v1/<rota>"
if [[ "$HTTP_CODE" == "200" ]]; then
  if echo "$HTTP_BODY" | jq -e '.data | length > 0' >/dev/null 2>&1; then
    test_pass "<rota> retorna dados"
  else
    test_fail "<rota> sem 'data'" "$HTTP_BODY"
  fi
fi

# Caso 3 — assertion negativa (não vazou stack trace do Elixir)
if echo "$HTTP_BODY" | grep -qiE '\*\* \(|Ecto\.|RuntimeError|lib/.*\.ex|\<%='; then
  test_fail "<rota> vazou stack trace / template EEx não renderizado" "$HTTP_BODY"
else
  test_pass "<rota> sem vazamento de erro"
fi

test_summary "<categoria>/<nome>"
exit $TEST_EXIT_CODE
```

**MUST**
- Banner do `test_section` na primeira linha do output.
- Cada caso assertado vira uma linha `✓` ou `✗` ou `○ skip`.
- `test_summary` no fim agrega contadores pra o runner.
- Falhas incluem `HTTP_BODY` truncado nos primeiros 2000 chars (sem PII).
- **Nunca** deixar vazar `** (Elixir.…)`, `(Postgrex.Error)` ou caminho `lib/*.ex` no body de erro — em prod o `Phoenix` deve renderizar erro genérico; o teste negativo do skeleton caça exatamente isso.

---

### 22.5 Seeds e personas de teste

**MUST**
- Personas declaradas em `tests/seeds/test-*.sql` ou `tests/<mode>/*.json` — versionadas, reproduzíveis. Para o teste **por código**, use `ExMachina`/factories ou fixtures do próprio app, sempre dentro do `Ecto.Adapters.SQL.Sandbox` (transação revertida no fim do teste, sem lixo).
- Senhas test-only **explicitamente flagadas** (ex.: prefixo `SimTest!`) e **rejeitadas em produção** por validador de senha fraca (`validate_change` no changeset de user).
- Setup idempotente: `INSERT ... ON CONFLICT DO UPDATE` (ou `Repo.insert(..., on_conflict: :replace_all, conflict_target: ...)`) — re-rodar não duplica.
- Cleanup automático no fim de cada run do sistema vivo? **Não** — deixa lixo pra inspeção. Limpe via comando explícito (`<project> test clean-seeds`). No teste por código é o inverso: o Sandbox reverte tudo, cada teste nasce limpo.

**Personas mínimas pra cobrir RBAC/ReBAC + multi-tenancy**:

1. `superadmin` — platform role, vê tudo.
2. `tenant_admin_A` — escopo do tenant A.
3. `tenant_admin_B` — escopo do tenant B (pra testar isolamento).
4. `normal_user` — sem role, só dados próprios.
5. (Opcional) `viewer`, `editor`, `support` — combinações de roles dentro de A.

---

### 22.6 Integração com CI

**MUST**
- Toolchain pinado por `.tool-versions` (asdf/mise): Elixir + Erlang/OTP exatos. CI usa a mesma versão do dev — divergência de OTP é fonte silenciosa de flake.
- **Ordem canônica do CI Elixir** (falha em qualquer passo trava o merge):
  1. `mix deps.get --check-locked` (lockfile íntegro).
  2. `mix format --check-formatted` (formatação é gate, não sugestão).
  3. `mix credo --strict` (lint/estilo/complexidade).
  4. `mix compile --warnings-as-errors` (warning é erro no CI).
  5. `mix deps.audit` (MixAudit) + `mix hex.audit` (deps retiradas).
  6. `mix dialyzer` (análise estática de tipos via PLT; PLT cacheado entre runs).
  7. `mix coveralls.json` (ExUnit + cobertura; `minimum_coverage` do `coveralls.json` é o piso da §22).
- PR check (sistema vivo): `<project> test smoke + security + authz + hardening` (rápido — ~3min total).
- Pré-deploy: `<project> test all` (full minus chaos+unit — ~6min).
- Nightly: `<project> test full` (inclui chaos + unit + `mix coveralls` completo por app).
- Bloqueio de merge: fail no `summary.json` (`.totals.fail > 0`) **ou** em qualquer passo `mix` acima trava merge.

**Dashboards**
- `summary.json` é parseado por job de métricas pra empurrar `tests_pass_total`, `tests_fail_total`, `tests_duration_seconds_bucket` pra Prometheus.
- Falha em smoke pós-deploy dispara rollback automático.

> **Dialyzer e Credo são gate, não enfeite.** Dialyzer pega o `{:error, _}` que o `@spec` promete mas o código não devolve, e a discrepância de tipo que o pattern-match esconde até o runtime. Credo pega complexidade ciclomática, função longa (liga com padrões-codigo §1) e nesting profundo. Warning suprimido "pra passar" é dívida registrada em ADR, não `# credo:disable` solto.

---

### 22.7 Pentest leve via ferramentas externas (complementar)

**SHOULD** — em CI noturno, não a cada PR:
- **OWASP ZAP baseline** (`zap-baseline.py -t https://api.example.com`) — passive scan.
- **Nuclei** (`nuclei -u https://api.example.com -t cves,exposures,misconfiguration`).
- **Sobol/`mix deps.audit` (MixAudit)** + **`mix hex.audit`** sobre o lockfile pra CVE/retirada em deps Hex; **trivy fs**/**grype** sobre o repo + imagens Docker (base image do release Elixir).
- **Sobelow** — SAST específico de **Phoenix** (`mix sobelow --exit`): detecta `raw/1` sem sanitização, SQLi via `fragment`/interpolação, CSRF ausente, config insegura, `Code.eval_*`/`System.cmd` com input, XSS em template. É o SAST da casa pro app Elixir — roda em toda PR.

Resultados em PR comment ou dashboard, **não bloqueiam merge** por default (alto ruído) — mas qualquer **Critical** (inclusive `Sobelow` de confiança alta) sem ADR de aceite trava.

---

### 22.8 Diretrizes de Pentest (princípios, não só scripts)

Os scripts da §22.3 são a implementação; estes são os princípios que regem **como** se faz pentest interno e **o que conta como passar**. Aprofundamento em `schematize-pentest` (mapa de endpoints, matriz de autorização, arsenal por classe, OWASP Web/API/LLM Top 10).

**Postura**
- **Assume-breach / hostil por padrão.** Todo input vindo de fora (body, query, header, cookie, path, arquivo, webhook) é tratado como hostil até prova de validação — e passa por um `changeset` que **rejeita** o que não deve entrar. Não existe "campo interno confiável" exposto numa rota.
- **Cobrir a rota toda, não a amostra.** Pentest roda contra o inventário completo de rotas (`mix phx.routes`, mesmo catalog do `simulated`). Rota nova sem caso de pentest correspondente bloqueia (liga com §35).
- **Caixa-cinza.** O time tem o OpenAPI, os schemas Ecto e as roles — testa sabendo o que **deveria** acontecer, não no escuro. Pentest sem mapa vira teatro de "tentei o `' OR 1=1` e deu 403, tá seguro".

**Critério de resultado — o que é PASS / FAIL**
- **Nunca `500` por input malicioso.** Erro do servidor (5xx) diante de payload hostil é FALHA — significa que o input chegou fundo demais sem validação e estourou uma cláusula (`FunctionClauseError`, `Ecto.Query.CastError`, `ArgumentError` de binário). O esperado é `400`/`422` (input inválido) ou `401`/`403`/`404` (sem acesso).
- **Nunca eco sem escape.** XSS/template injection refletido no body/header sem encode = FALHA, mesmo com status 200 (caçar `raw/1` no HEEx).
- **Nunca coerção silenciosa.** Campo `:string` aceito como número, `""` virando `0`, `"true"` virando bool onde a semântica não permite = FALHA (liga com `type-confusion.sh`). O tipo do changeset é contrato — o cast do Ecto é intencional pra `"123"→123`, mas o resto é rejeição.
- **Nunca átomo dinâmico de input externo.** `String.to_atom/1` sobre chave/valor de request é FALHA de segurança do BEAM (esgota a tabela de átomos → derruba o nó). Só `String.to_existing_atom/1`.
- **Nunca vazamento entre tenants/usuários.** Qualquer `200` com dado de outro escopo = FALHA crítica, para o deploy na hora (§15) — query Ecto sem `tenant_id` no `where`.
- **Nunca diferença observável que ajude o atacante.** Mensagem de erro distinta pra "user existe" vs "senha errada", timing > 30% de variância (hash sempre roda — `Argon2.no_user_verify/0`), stack trace do Elixir no response = FALHA.
- **Idempotência sob ataque.** Replay, duplicação, race no mesmo recurso não corrompe estado (constraint no banco + `on_conflict`, não só checagem em memória do `GenServer`).

**Severidade e gate**
- Classificar todo achado: `Critical` / `High` / `Medium` / `Low` / `Info`.
- **`Critical` e `High` bloqueiam merge/deploy.** Sem exceção silenciosa — ou conserta, ou ADR de aceite de risco **com prazo de remediação e dono** (e mesmo assim `Critical` de auth/tenant/injeção **não aceita ADR** — é piso da §37).
- `Medium`/`Low` viram issue rastreável com prazo; acumular não é opção.

**Higiene**
- **Pentest roda só contra `dev`/`staging`** (ou alvo autorizado). Scripts destrutivos (`service-kill`, `db-disconnect`) gated por env var explícita (§22.3 chaos). Nunca contra produção sem autorização formal e janela.
- **Evidência sempre.** Todo achado tem request/response reproduzível no `raw.jsonl` — "achei uma falha" sem repro não conta.
- **Falso-positivo é bug do teste.** Pentest que grita sem motivo treina o time a ignorar — calibra ou remove. Mas **na dúvida, FAIL** (vai pra `REVIEW`, olho humano decide), nunca silencia por padrão.

**Escopo mínimo coberto** (mapeia OWASP Top 10 + API Top 10): injeção (SQL via `fragment`/interpolação, command via `System.cmd`, template EEx), XSS (`raw/1`), validação de tipo e sanitização (§22.3), authz/IDOR/BOLA, broken auth (JWT, sessão, refresh), SSRF, mass assignment (cast do changeset), exposição excessiva de dados (`@derive Jason.Encoder`), atom-exhaustion (específico BEAM), misconfig (headers, CORS, paths expostos, LiveDashboard em prod), rate limiting, e abuso de recurso (payload gigante, ReDoS, billion-laughs, message-queue overflow).

> Pentest não "tenta hackear pra ver se acha algo". Ele **prova, rota por rota, campo por campo, que o sistema rejeita o que deve rejeitar.** Achado é evidência; ausência de achado só vale se a cobertura for total. Detalhe metodológico e arsenal: **`schematize-pentest`**.

---

### 22.9 Fluxo de execução de Q.A. (plan-first, aprovação obrigatória)

A malha de Q.A. inclui passos potencialmente destrutivos (chaos `service-kill`/`db-disconnect`, kill de processo BEAM, pentest, mutações). Por isso **nenhuma submissão de Q.A. roda às cegas**: toda submissão de um formulário/pedido de Q.A. passa por planejamento, aprovação humana e execução controlada. O fluxo plan-first é o mesmo da casa (definido em **`schematize-engineering`**); esta seção fixa a instância Elixir/`<project>_ops`.

**MUST — antes de executar qualquer coisa**

1. **Planejar tudo primeiro.** Ao receber a submissão, o agente **não executa nada ainda**. Levanta o escopo completo: quais modos vão rodar (smoke/integration/security/pentest/authz/hardening/chaos/simulated/unit), ambiente alvo, rotas e personas afetadas, ordem de execução, dependências entre passos, o que é **destrutivo/gated**, e os riscos.
2. **Gerar um MD de passo a passo detalhado** em `<project>_archive/qa/<YYYY-MM-DD-HH-MM-SS>-<contexto>.md` (liga com §28 — é archive obrigatório). Cada passo declara: objetivo, comando exato (`mix test ...`, `<project> test ...`), ambiente, resultado esperado, critério de pass/fail, e flag de **destrutivo** quando aplicável. O plano referencia o `summary.json` (§22.2) que será produzido.
3. **Pedir aprovação explícita do usuário.** Sem aprovação registrada, **nada roda**. O agente apresenta o plano e aguarda o "ok". Aprovação parcial (subconjunto de passos) é válida e vira o escopo efetivo.

**MUST — após aprovado**

4. **Oferecer a modalidade de execução.** O agente pergunta como rodar:
   - **Faseado e assistido** — executa por fase, **pausa entre fases** para revisão/confirmação, mostra resultado parcial e só segue com o "continuar". Default recomendado para staging sensível e para qualquer plano com passo destrutivo.
   - **De uma vez (autônomo)** — executa o plano inteiro sem parar.
5. **No modo "de uma vez":**
   - **Multiagentes para produção da execução** — paralelizar categorias independentes (ex.: `security`, `authz`, `hardening`, `pentest`, `simulated` em workers separados), respeitando dependências declaradas no plano e os limites de concorrência (§9 backpressure). A própria concorrência do ExUnit (`async: true`) só entra onde o isolamento do Sandbox está provado (§22.3 `unit`).
   - **Cron/watchdog de continuidade ininterrupta** — um agendador supervisiona a execução e a **retoma de checkpoint até concluir**, sem exigir intervenção manual se um worker cair. A "conclusão" é condição de parada explícita: todos os passos aprovados terminaram, **ou** uma falha bloqueante escalou para o humano. Checkpoints são **idempotentes** (§19) e a retomada não reexecuta passo já concluído.

**MUST — segurança do fluxo (herda do resto do §22)**

- Passo destrutivo (`service-kill`, kill de `GenServer`, `db-disconnect`, drop, mutação em massa) **só roda se constava no plano aprovado** e com o gate de ambiente ligado (ex.: `<PROJECT>_CHAOS_ALLOW=1` — §22.3). Aprovação do plano não dispensa o gate.
- Modo autônomo "de uma vez" roda por default só em `dev`/`staging`. Produção exige confirmação adicional explícita no momento da execução (alinha com §22.8 — alvo autorizado).
- **Sem retry infinito** no watchdog: a continuidade tem limite de tentativas por passo, backoff, e escala para humano ao estourar (§9, §18). "Ininterrupto até finalizar" é retomar até concluir, **não** repetir pra sempre.

**VETADO**

- Pular o plano ou a aprovação "pra ir mais rápido" — é macaquice na linha da §37 (atalho que troca segurança por velocidade). Q.A. sem plano aprovado registrado **não roda**.

> O plano aprovado é o contrato da execução. Multiagente e cron aceleram o *como*, nunca dispensam o *o quê foi autorizado*.

---

---

## 23. Makefile Padrão (aliases sobre `mix`)

O Makefile é fachada fina sobre `mix` — quem toca o app diretamente usa os `mix aliases` (definidos no `mix.exs`); o Makefile existe pra o `<project>_ops` e o CI terem uma interface uniforme entre repos de linguagens diferentes.

```bash
make dev              # iex -S mix phx.server (ambiente local)
make test             # mix test (unit + integration por código)
make test-unit        # mix test --only unit
make test-integration # mix test --only integration
make cover            # mix coveralls (ExCoveralls; falha abaixo do piso §22)
make lint             # mix credo --strict
make fmt              # mix format
make fmt-check        # mix format --check-formatted
make dialyzer         # mix dialyzer (PLT cacheado)
make build            # mix compile --warnings-as-errors
make release          # mix release (artefato OTP)
make run              # mix phx.server
make docker           # build da imagem do release
make migrate          # mix ecto.migrate
make seed             # mix run priv/repo/seeds.exs
make docs             # mix docs (ExDoc) + valida openapi
make security-scan    # mix sobelow --exit + mix deps.audit + mix hex.audit
make smoketest        # <project> test smoke
make pentest-light    # <project> test pentest + ferramentas externas (§22.7)
make ci               # tudo que o CI roda (ordem da §22.6)
make clean            # mix clean + rm -rf _build deps
```

**MUST**
- `mix aliases` no `mix.exs` espelham os alvos críticos (`test`, `ci`, `check`) — ex.: `check: ["format --check-formatted", "credo --strict", "dialyzer", "sobelow --exit", "coveralls"]`. O Makefile chama o alias, não reimplementa a sequência.
- `make ci` é o **mesmo** conjunto que roda no pipeline (§22.6) — dev consegue reproduzir o CI localmente com um comando.

---

---
