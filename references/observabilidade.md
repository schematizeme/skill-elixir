# Observabilidade, Healthchecks, Performance e FinOps — Elixir/OTP

> **PONTEIRO, não cópia.** O padrão (OpenTelemetry, Collector, sinais correlacionados, cardinalidade, SLO,
> alertas com runbook, dashboards como código, stack de referência) é da **`schematize-observability`**
> (`schematize-observability -> SKILL.md` e `references/`); o piso da base está em
> `schematize-engineering -> references/observabilidade.md`. Aqui fica **só o que muda na BEAM/OTP**:
> `:telemetry`, metadata do `Logger`, propagação de contexto entre processos, alertas de VM e diagnóstico.
> Onde divergir, a base e a `schematize-observability` mandam. Concorrência em `references/concorrencia.md`;
> versões das libs em `references/stack-versoes.md`; entrega da stack em `references/ops.md`.

## Índice
- 16. Observabilidade (BEAM)
- 17. Healthchecks
- 30. Performance — Metas Padrão (BEAM)
- 33. FinOps — Gestão de Custos

---

## 16. Observabilidade (BEAM)

Em Elixir a instrumentação é nativa: **`:telemetry`** é o barramento de eventos in-process e o
OpenTelemetry (`opentelemetry`, `opentelemetry_api`, `opentelemetry_exporter` por OTLP,
`opentelemetry_phoenix`, `opentelemetry_ecto`, `opentelemetry_oban`) exporta para o Collector
(`schematize-observability -> references/padrao-otel.md`). O serviço **anexa handlers** a eventos que a stack
já emite e não reinventa medição. O `MyApp.Telemetry` sobe na **árvore de supervisão**, não é `start` solto.

**Eventos `:telemetry` que a stack já emite:**
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

> **PromEx** (`prom_ex`) é o atalho quando o transporte é scrape Prometheus direto: plugins prontos (Phoenix, Ecto,
> Oban, BEAM), `/metrics` e dashboards Grafana versionados junto. Com OTLP puro, use o reporter OpenTelemetry.

### 16.1 Logs

- **`Logger` JSON** (ex.: `logger_json`) em produção; metadata estruturada, não interpolação:
  `Logger.metadata(trace_id: ..., tenant_id: ..., request_id: ...)` e `Logger.info("payment.captured", amount_cents: ...)`.
  O bridge do OpenTelemetry preenche `trace_id`/`span_id` no `Logger.metadata`, fechando a correlação log-trace.
- **`inspect/2` de struct inteiro despeja tudo:** use `@derive {Inspect, except: [...]}` nos structs sensíveis. O
  `filter_parameters` do Phoenix cobre os params de request, **não** o `inspect` manual no seu código.
- Regras gerais (o que nunca entra num log, nível em prd, VETADO logar body cru): `schematize-observability -> references/logs.md`.

```elixir
config :logger, :default_handler,
  formatter: {LoggerJSON.Formatters.Datadog, metadata: :all}

config :logger,
  level: :info,
  metadata: [:trace_id, :span_id, :request_id, :tenant_id, :user_id]
```

### 16.2 Métricas

- RED sai de `[:phoenix, :endpoint, :stop]` (`distribution`/`summary` do `telemetry_metrics`). Para a BEAM, via
  `telemetry_poller`: **run queue**, contagem de processos, memória por tipo (`:atom`, `:binary`, `:ets`, `:processes`),
  reductions, GC. Ecto: `queue_time`/`query_time`/`idle_time` do pool. Oban: fila crescendo e `[:oban, :job, :exception]`.
- Cardinalidade como orçamento: `schematize-observability -> references/metricas.md`.

### 16.3 Tracing

- `opentelemetry_phoenix` abre o span da request; `opentelemetry_ecto` cria o span filho da query.
- **Fronteira de processo:** o span context vive no process dictionary/`Logger.metadata`. Ao passar trabalho a outro
  processo (`Task`, `GenServer.cast`, job Oban), **propague o contexto explicitamente**, senão o trace quebra no
  salto (`references/concorrencia.md`).

### 16.4 SLOs e alertas

SLO, burn-rate e anatomia de alerta: `schematize-observability -> references/slo-alertas.md`. Alertas específicos da
BEAM, além do RED de API:
- `mailbox_len > N` sustentado em processo crítico: backpressure quebrada (§30).
- `oban_queue_depth` crescente / `oban.job.exception` acima do baseline: fila afogando.
- `run_queue_length` alto sustentado: saturação de scheduler.
- `ecto_pool_queue_time` alto: pool subdimensionado ou query travando conexão.
- nó saiu do cluster (`libcluster`): alerta imediato (perda de distribuição).

### 16.5 Métricas de negócio e auditoria

- Evento `:telemetry` próprio do domínio: `:telemetry.execute([:billing, :invoice, :paid], %{amount_cents: v}, meta)`,
  agregado via `telemetry_metrics`.
- Auditoria (trilha imutável, campos mínimos, regras em `schematize-observability -> references/logs.md`): a gravação
  entra no **mesmo `Ecto.Multi`** da operação auditada, para não existir ação sem trilha.

---

## 17. Healthchecks

Contrato liveness/readiness/startup: `schematize-observability -> references/healthchecks.md`. Em Phoenix, plug leve
**fora** do pipeline de auth; `/ready` checa `Ecto.Adapters.SQL.query(Repo, "SELECT 1")` com timeout curto.
Liveness que testa o banco derruba o pod à toa; separe-os. Em cluster BEAM, readiness considera se o nó entrou no
cluster (`libcluster`): nó órfão **não** está ready. `/metrics` via `PromEx` ou exporter a partir do `telemetry_metrics`.

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
