# Observabilidade, Healthchecks, Performance e FinOps

> Parte da skill **schematize-elixir**. Especializa para a BEAM/OTP o piso comum de `schematize-engineering`. Concorrência/processos em profundidade em `references/concorrencia.md`; versões pinadas das libs de telemetria em `references/stack-versoes.md`; entrega da stack de observabilidade junto do serviço operada pelo `references/ops.md`.

## Índice
- 16. Observabilidade
- 17. Healthchecks
- 30. Performance — Metas Padrão (BEAM)
- 33. FinOps — Gestão de Custos

---

## 16. Observabilidade

**Stack obrigatória (LGTM+):** toda ferramenta/serviço criado ou atualizado — **inclusive o `<projeto>_ops`** — nasce com observabilidade **integrada de ponta a ponta**, nunca como extra depois. Em Elixir a instrumentação é nativa: **`:telemetry`** é o barramento de eventos in-process, e **OpenTelemetry** exporta traces/métricas/logs correlacionados para a stack LGTM da casa.

- **Instrumentação base — `:telemetry`:** Phoenix, Ecto, Oban, Broadway e Finch **já emitem** eventos `:telemetry` (`[:phoenix, :endpoint, :stop]`, `[:my_app, :repo, :query]`, `[:oban, :job, :stop]`, ...). O serviço **anexa handlers** e não reinventa medição.
- **Métricas — `telemetry_metrics` + `telemetry_poller`:** definir as métricas declarativamente (`Telemetry.Metrics.counter/distribution/last_value/summary`) num módulo `MyApp.Telemetry`; `telemetry_poller` amostra periodicamente VM/processo (memória, run queue, contagem de processos).
- **Exporte via OpenTelemetry:** libs `opentelemetry`, `opentelemetry_api`, `opentelemetry_exporter` (OTLP), `opentelemetry_ecto`, `opentelemetry_phoenix` (e `opentelemetry_oban`/`opentelemetry_cowboy` quando aplicável). Traces, métricas e logs saem por **OTLP** para o coletor.
- **Coleta:** Grafana Alloy (coletor/agente OTel) recebe o OTLP.
- **Backends (LGTM):** **Loki** (logs), **Tempo** (traces), **Prometheus** (scrape) + **Mimir** (métricas long-term, HA, multi-tenant); **SHOULD** Pyroscope (profiling contínuo — casa com `eflame`/`:recon` do BEAM).
- **Visualização e alerta:** Grafana — dashboards e regras de alerta **versionados como código**, entregues junto do serviço.
- **Deploy:** **Helm chart** versionado por serviço — o repo entrega chart + dashboards + alertas com o código.
- Um serviço só é "pronto" se expõe `/metrics`, emite logs estruturados e traces, e sobe com dashboard + alertas + chart (§35). O `MyApp.Telemetry` sobe na **árvore de supervisão** da aplicação, não é `start` solto.

**Eventos `:telemetry` que a stack já emite (anexar handler, não reinventar):**

| Origem | Evento | Mede |
|---|---|---|
| Phoenix | `[:phoenix, :endpoint, :stop]` | duração da request (RED) |
| Phoenix | `[:phoenix, :router_dispatch, :stop]` | duração por rota |
| Ecto | `[:my_app, :repo, :query]` | `query_time`, `queue_time`, `idle_time`, `decode_time` |
| Oban | `[:oban, :job, :stop]` / `[:oban, :job, :exception]` | duração e falha de job |
| Broadway | `[:broadway, :processor, :message, :stop]` | throughput/latência do pipeline |
| Finch/Req | `[:finch, :request, :stop]` | latência de chamada HTTP de saída |
| VM (poller) | `[:vm, :memory]`, `[:vm, :total_run_queue_lengths]` | memória e saturação de scheduler |

**`MyApp.Telemetry` (esqueleto real, na árvore de supervisão):**

```elixir
defmodule MyApp.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg), do: Supervisor.start_link(__MODULE__, arg, name: __MODULE__)

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic(), period: 10_000}
      # + reporter OTLP / PromEx conforme o transporte da casa
    ]
    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # RED do endpoint
      distribution("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}, tags: [:route]),
      counter("phoenix.endpoint.stop.count", tags: [:status]),
      # Ecto
      distribution("my_app.repo.query.total_time", unit: {:native, :millisecond}),
      # Oban
      counter("oban.job.exception.count", tags: [:queue, :worker]),
      # VM / BEAM
      last_value("vm.memory.total", unit: {:byte, :megabyte}),
      last_value("vm.total_run_queue_lengths.total")
    ]
  end

  defp periodic, do: [{:process_info, ...}]  # amostragem de processo crítico
end
```

> **PromEx** (`prom_ex`) é o atalho da casa quando o transporte de métrica é scrape Prometheus direto: agrega plugins prontos (Phoenix, Ecto, Oban, BEAM), expõe `/metrics` e **entrega dashboards Grafana versionados** junto — casa com "dashboard como código". Quando o transporte é OTLP puro, o reporter OpenTelemetry no lugar do exporter Prometheus.

### 16.1 Logs

- **`Logger` estruturado, JSON** — formatter JSON (ex.: `logger_json`) em produção; nunca log de texto solto que não parseia no Loki.
- **Metadata estruturada, não interpolação:** `Logger.metadata(trace_id: ..., tenant_id: ..., user_id: ..., request_id: ...)` e `Logger.info("payment.captured", amount_cents: ...)`. Metadata configurada em `config :logger` para propagar em toda mensagem. `trace_id` vem do span OTel para correlacionar log↔trace.
- Níveis: `:debug`, `:info`, `:warning`, `:error`. Nível de produção via config, nunca `:debug` em prd por padrão.
- **Proibido logar:** senhas, tokens, JWT, PII (CPF, email, telefone), dados financeiros, payloads de pagamento. Mascaramento obrigatório — cuidado especial com **`inspect/2` de struct inteiro**, que despeja tudo; use `@derive {Inspect, except: [...]}` nos structs sensíveis (o `filter_parameters` do Phoenix cobre os params de request, mas **não** cobre `inspect` manual no seu código).
- **VETADO** logar request/response inteiros, headers ou body cru "pra debugar" (§37). Logue campos específicos, mascarados.

**Config de logger estruturado (`config/prod.exs` ou `runtime.exs`):**

```elixir
config :logger, :default_handler,
  formatter: {LoggerJSON.Formatters.Datadog, metadata: :all}

config :logger,
  level: :info,
  metadata: [:trace_id, :span_id, :request_id, :tenant_id, :user_id]
```

O `trace_id`/`span_id` são preenchidos pelo bridge do OpenTelemetry no `Logger.metadata`, fechando a correlação **log (Loki) ↔ trace (Tempo)** por um clique no Grafana.

### 16.2 Métricas

- **RED por endpoint/handler:** Rate, Errors, Duration — histograma p50/p95/p99 a partir de `[:phoenix, :endpoint, :stop]` (`distribution`/`summary` do `telemetry_metrics`).
- **USE para infra e BEAM:** Utilization, Saturation, Errors. Métricas de VM via `telemetry_poller`: **run queue length**, contagem de processos, memória total/por tipo (`:atom`, `:binary`, `:ets`, `:processes`), reductions, GC. Run queue alta e crescente = saturação de schedulers.
- Ecto: `queue_time`, `query_time`, `idle_time` do pool por `[:my_app, :repo, :query]`. Oban: fila crescendo, `[:oban, :job, :exception]`.

### 16.3 Tracing

- Toda chamada externa, fila, banco e fluxo crítico instrumentados — `opentelemetry_phoenix` abre o span da request, `opentelemetry_ecto` cria o span da query filho, propagação automática.
- **Propagação W3C Trace Context** (`traceparent`) — configurar o propagator OTel; injetar o header nas chamadas HTTP de saída e nas mensagens do broker, para o trace atravessar serviços.
- **Cuidado com fronteira de processo:** o span context vive no `Logger.metadata`/process dictionary; ao passar trabalho para outro processo (`Task`, `GenServer.cast`, job Oban), **propagar o contexto explicitamente** — senão o trace quebra no salto entre processos (detalhe em `references/concorrencia.md`).

### 16.4 SLOs

- Cada serviço define SLI/SLO em `/docs/slo.md`.
- Error budget consumido → freeze de features até recuperação.
- **Alerta como código:** regras Prometheus/Grafana versionadas no repo do serviço, entregues no Helm chart. Alertas mínimos específicos da BEAM, além do RED de API:
  - `mailbox_len > N` sustentado por processo crítico → backpressure quebrada (§30).
  - `oban_queue_depth` crescente / `oban.job.exception` acima do baseline → fila afogando.
  - `run_queue_length` alto sustentado → saturação de scheduler.
  - `ecto_pool_queue_time` alto → pool subdimensionado ou query travando conexão.
  - nó saiu do cluster (`libcluster`) → alerta imediato (perda de distribuição).

### 16.5 Business Observability

**SHOULD**
- Métricas de negócio expostas (pedidos/min, conversão, churn) — emitir evento `:telemetry` próprio do domínio (`:telemetry.execute([:billing, :invoice, :paid], %{amount_cents: v}, meta)`) e agregar via `telemetry_metrics`.
- Dashboards de negócio separados dos técnicos.
- KPIs principais instrumentados desde o dia 1.

### 16.6 Auditoria

**MUST**
- Operações sensíveis (mudança de permissão, transações financeiras, alteração de config, ações administrativas) em **trilha de auditoria imutável**.
- Campos mínimos: `actor_id`, `tenant_id`, `action`, `resource`, `timestamp`, `ip`, `user_agent`, `result`.
- Retenção mínima conforme regulação.
- Storage **append-only** (tabela dedicada, não a de domínio) — a gravação de auditoria entra no **mesmo `Ecto.Multi`** da operação auditada, para não existir ação sem trilha.

---

## 17. Healthchecks

Endpoints obrigatórios, servidos pelo endpoint Phoenix (plug leve, **fora** do pipeline de auth):
- `/health` — **liveness** (o processo/nó está vivo — responde sem tocar dependência).
- `/ready` — **readiness** (dependências OK, pronto pra tráfego): checa `Ecto.Adapters.SQL.query(Repo, "SELECT 1")` com timeout curto, Redis/Oban se críticos. **Liveness ≠ readiness:** liveness que testa o banco derruba o pod à toa quando o banco pisca; separe-os.
- `/metrics` — Prometheus (via `PromEx` ou exporter próprio a partir do `telemetry_metrics`).

> Em cluster BEAM, readiness também considera se o nó entrou no cluster (`libcluster`) quando o serviço depende de distribuição. Nó órfão que não formou cluster **não** está ready.

---

## 30. Performance — Metas Padrão (BEAM)

| Métrica | Alvo |
|---|---|
| API p95 | < 300 ms |
| API p99 | < 1 s |
| Startup (boot da release) | < 10 s |
| Imagem Docker (release OTP) | < 150 MB (Elixir, distroless/alpine) |

Metas específicas sobrescrevem, registradas no `/docs/slo.md`.

**Diagnóstico BEAM (ferramental próprio):**
- **`:observer`** (`:observer.start()`) em dev/hml — visão de processos, memória, ETS, aplicações, schedulers. **Não** em prd headless.
- **`:recon`** em produção (seguro para nó vivo): `:recon.proc_count(:memory, 10)` (top processos por memória), `:recon.proc_count(:message_queue_len, 10)` (top mailboxes), `:recon.bin_leak/1` (leak de binário refc). `:recon_alloc` para fragmentação de memória.
- **Sinais de alarme de processo:**
  - **Mailbox crescendo sem parar** = consumidor mais lento que o produtor → backpressure quebrada; o processo acumula mensagem, memória sobe, latência explode. Corrigir com Broadway/GenStage (demanda puxada), não aumentando `max_heap_size`.
  - **Run queue alta** = falta de scheduler/CPU ou processo que não cede (loop tight/NIF longo).
  - **Memória por processo subindo monotônica** = state acumulando ou binário refc não coletado.
- **Regra:** long-running com `handle_call` que faz IO pesado serializa tudo naquele processo — mova para `Task.Supervisor`/pool (ver `references/concorrencia.md`). Um `GenServer` gargalo é problema de design, não de máquina.

---

## 33. FinOps — Gestão de Custos

**SHOULD**
- Monitoramento de custo por serviço/squad/tenant.
- Budgets com alertas de threshold.
- Revisão de overprovisioning — a BEAM aproveita muito CPU/memória num nó; medir **densidade real** (processos/nó, memória por processo) antes de escalar horizontalmente. Frequentemente um nó bem dimensionado substitui vários subaproveitados.
- Tags de billing consistentes em IaC.
- Custo por request rastreado em serviço de alto volume; ligar métrica de negócio (§16.5) a custo de infra para custo-por-transação.

---
