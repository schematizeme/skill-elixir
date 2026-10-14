# Eventos, Banco de Dados, Cache, APIs, Resiliência e Jobs

> Parte da skill **schematize-elixir**. Especializa para a BEAM/OTP o piso comum de `schematize-engineering`. As referências cruzadas (§N) apontam para seções do corpo completo desta skill; concorrência/backpressure em profundidade vivem em `references/concorrencia.md`, versões pinadas em `references/stack-versoes.md`, e o fluxo de operação/migração destrutiva em `references/ops.md`.

## Índice
- 9. Eventos e Mensageria
- 10. Banco de Dados (Ecto + Postgres)
- 11. Cache
- 12. APIs (Phoenix)
- 18. Resiliência
- 19. Jobs e Workers (Oban)

---

## 9. Eventos e Mensageria

**MUST — produção e consumo**
- Eventos são **imutáveis e versionados** (`v1`, `v2`) — carregam o número no nome do struct/tópico ou num campo `schema_version`.
- Consumidores **idempotentes**: deduplicação por `event_id` (UUIDv7) persistida — tabela `processed_events` com `unique_index`, ou `Oban.Job` com `unique`. Reprocesso não pode corromper.
- Suporte a **replay** a partir de um offset/timestamp durável.

**MUST — compatibilidade evolutiva**
- Novos campos são **opcionais**, com default seguro no `defstruct`/schema.
- Nunca remover nem renomear campo sem **nova versão** do evento.
- Consumidores **ignoram campos desconhecidos** (forward compatible) — em Elixir isso é natural com pattern match parcial (`%{"type" => t} = payload`), nunca casar o mapa inteiro fechado.
- Coexistência de versões durante a janela de migração **documentada** no archive.

**MUST — entrega (Outbox é piso)**
- **Transactional Outbox** para publicação de eventos: o intento é gravado na tabela `outbox` **dentro do mesmo `Ecto.Multi`** que muda o estado de domínio; um relay (Broadway/GenStage ou job Oban) lê a outbox e publica. **Dual-write (banco + broker no mesmo fluxo, sem transação) é VETADO** (§37) — publicar no broker e o commit falhar depois deixa evento fantasma.
- **DLQ** (dead letter queue) configurada para todo consumidor. Em Oban, isso é a fila de descarte após `max_attempts`; em Broadway, o `handle_failed/2` roteia para tópico/tabela morta.
- **Retry infinito é proibido.** Política explícita com limite e backoff (ver §18/§19).

**MUST — backpressure**
- Consumidores com limites explícitos de concorrência e prefetch. **Broadway** dá isso de fábrica: `concurrency`, `batch_size`, `batch_timeout` e demanda GenStage puxada (pull), nunca push que estoura a mailbox. **Mailbox de processo crescendo sem parar é o sinal de backpressure quebrada** (ver `references/observabilidade.md` e `references/concorrencia.md`).
- Throttling no produtor quando o broker sinaliza pressão; `Broadway.RateLimiting` quando a fonte exige.

**Stack de streaming/eventos na casa**

| Cenário | Stack Elixir |
|---|---|
| Streaming com backpressure, batching, ack, DLQ | **Broadway** (produtores para SQS, Kafka, RabbitMQ, Google PubSub) |
| Pipeline de dados custom com demanda explícita | **GenStage** (producer/consumer) |
| Pub/sub in-cluster, distribuição de mensagem entre nós | **Phoenix.PubSub** (backend PG2/Redis) |
| Eventos leves, baixa latência entre serviços | **NATS** (via `gnat`) |
| Alto throughput, retenção, replay | **Kafka** (via `brod`/Broadway) |

> Phoenix.PubSub é para **notificação in-cluster** (LiveView, presence, invalidação de cache), **não** é durável — não substitui outbox/broker para evento de negócio que não pode se perder.

**Convenção de nome:** `<dominio>.<entidade>.<evento>` no passado. Exemplos: `catalog.product.created`, `billing.invoice.paid`.

---

## 10. Banco de Dados (Ecto + Postgres)

| Caso | Stack |
|---|---|
| Relacional (padrão) | **PostgreSQL** via **Ecto** (`Ecto.Repo` + `postgrex`) |
| Cache | Redis (via `redix`) / Cachex (§11) |
| Busca textual | OpenSearch, ou `pg_trgm`/`tsvector` no próprio Postgres |
| Analytics / eventos | ClickHouse |

**MUST — Ecto e schema**
- Acesso a dados **só pelo `Repo`**. Nada de SQL cru espalhado; queries são `Ecto.Query` compostas.
- **Toda escrita passa por `changeset`**: `cast/3` com allowlist explícita de campos + `validate_*` + `unique_constraint`/`foreign_key_constraint`/`check_constraint` mapeando o constraint do banco para erro de changeset. **`cast/3` com lista de campos derivada da entrada do usuário é VETADO** — mass-assignment (§37). O banco é a última linha: constraint no banco **sempre**, não só validação no changeset.
- **Toda query com input externo é parametrizada.** Ecto já parametriza; se cair em `Ecto.Adapters.SQL.query/4` ou `fragment/1`, os valores vão como `?`/`^binding`, **nunca** interpolados em string. Concatenar SQL é **VETADO** (§37).
- **Timestamps em UTC, sempre** (`:utc_datetime_usec`, `timestamps(type: :utc_datetime_usec)`). Conversão de timezone só na borda (render). Para lógica com fuso, `DateTime` + `tzdata`.
- **IDs:** UUIDv7/ULID por padrão (`Ecto.UUID` + gerador v7, ou `:binary_id`). Sequenciais só com justificativa (ordenação natural do domínio).

**MUST — transação atômica com `Ecto.Multi`**
- Fluxo que toca 2+ tabelas (ou tabela + outbox) roda num **`Ecto.Multi`** único, um `Repo.transaction/1`. Cada passo nomeado; falha em qualquer passo → rollback de tudo. É o mecanismo padrão para consistência local; **não** simular transação com múltiplos `Repo.insert` soltos.
- Efeito colateral externo (publicar, chamar HTTP) **fora** da transação — dentro vai só a gravação na outbox. `Repo.transaction` que faz IO de rede segura conexão do pool e trava.

**MUST — migrations REVERSÍVEIS**
- Migration versionada em `priv/repo/migrations/`, **reversível**, automatizada no deploy pelo `ops` (`mix ecto.migrate`).
- Preferir `change/0` quando o Ecto sabe reverter (`create table`, `add`, `create index`). Quando a operação **não** é auto-reversível (mudança de dado, `execute`, backfill), **implementar `up/0` e `down/0` explícitos** — `down` que restaura o estado anterior. Migration com `execute/1` de uma via só, sem `down`, é **VETADA**: quebra o rollback do deploy.

```elixir
def up do
  alter table(:invoices) do
    add :status, :string, null: false, default: "pending"
  end
  create index(:invoices, [:status])
end

def down do
  drop index(:invoices, [:status])
  alter table(:invoices), do: remove(:status)
end
```

- **Índice em tabela grande com `create index(..., concurrently: true)`** + `@disable_ddl_transaction true` e `@disable_migration_lock true`, para não travar escrita em produção.
- **Migração de schema e migração de dado são migrations separadas.** Backfill pesado **não** vai na migration que roda no boot do deploy — vira **seed/tarefa idempotente** operada pelo `ops` (redeploy destrutivo semeia app, nunca dados — ver `references/ops.md`).

**SHOULD — alta escala**
- Réplica de leitura via segundo `Repo` (`MyApp.Repo.Replica`) quando o volume justificar; escrita sempre no primário.
- Revisão de índice e `EXPLAIN (ANALYZE)` nos endpoints críticos; `telemetry` de `[:my_app, :repo, :query]` para achar query lenta (ver observabilidade).
- Pool (`pool_size`) dimensionado e **menor** que `max_connections` do Postgres somado entre nós; particionamento para tabela de crescimento previsível.

---

## 11. Cache

| Camada | Stack |
|---|---|
| Cache local, in-node, por processo | **Cachex** (TTL, LRU, fallback, warming) ou `:persistent_term` para config imutável |
| Cache distribuído entre nós | **Redis** via **`redix`** (pool) |

**MUST**
- **TTL sempre explícito.** Sem TTL infinito sem ADR. Em Cachex, `ttl:` na escrita; em Redis, `EX`/`PX`.
- **Cache stampede mitigado:** `Cachex.fetch/4` (single-flight — só um processo recomputa, os demais esperam), lock ou jitter no TTL. Nunca N processos batendo no banco no mesmo miss.
- **Fallback seguro em miss** — degradação graciosa, nunca falha total.
- Invalidação documentada por chave.
- **Resposta autenticada tem chave segmentada por `user_id` e `tenant_id`** — cache cross-tenant é vazamento (§37). A chave inclui o tenant, sempre.

**MUST NOT**
- Cache como source of truth (ETS/Cachex somem no restart do processo/nó — são derivados).
- Cache de PII sensível sem criptografia.

> ETS direto (`:ets`) é aceitável para tabela quente própria, mas prefira Cachex pelo TTL/telemetry/fallback prontos. Estado de sessão **não** vai em ETS local num cluster multi-nó sem sticky/replicação — vai em Redis.

---

## 12. APIs (Phoenix)

**MUST**
- API HTTP em **Phoenix** (endpoint + router + controller, JSON via `Jason`). GraphQL, quando o domínio pedir, via **Absinthe** — schema versionado, resolver fino, complexidade limitada.
- **OpenAPI 3.1** como fonte da verdade em `/docs/openapi.yaml` (gerar com `open_api_spex`, que também valida o payload na borda pelo próprio spec).
- Versionamento na URL: `/api/v1`, `/api/v2` (scope no router).
- **Validação de payload na borda** — changeset/`open_api_spex`/`Ecto.Changeset` embedded antes de tocar o domínio. Nunca confiar no `params` cru.
- Erro padrão via `FallbackController` + `ErrorJSON`, compatível com RFC 7807:

```json
{
  "error": {
    "code": "PRODUCT_NOT_FOUND",
    "message": "Product not found",
    "trace_id": "01HXYZ...",
    "details": []
  }
}
```

- Escrita aceita `Idempotency-Key` **e o implementa de fato** (chave persistida + resposta memoizada; aceitar o header e ignorar é VETADO — §37). Casa com o dedup de eventos (§9).
- Quebra de contrato → nova versão + deprecação ≥ 90 dias com headers `Deprecation` e `Sunset`.
- Timestamps ISO-8601 com timezone explícito (`Z`).

**MUST — paginação**
- **Cursor pagination** é o padrão (cursor opaco sobre `id`/`inserted_at`).
- Offset só em lista pequena (< 10k) e estática.
- Resposta inclui `next_cursor` e `has_more`.

**MUST — rate limiting**
- Rate limiting **distribuído** (Redis via `hammer`/`ex_rated`, ou no gateway) — não só em ETS local, que não conta entre nós.
- Chave por `user_id`, API key e `tenant_id`.
- 429 com header `Retry-After`.

**SHOULD**
- Contratos consumer-driven (Pact) entre serviços.
- gRPC (`grpc-elixir`) para tráfego interno de alta performance; HTTP/JSON para externo.
- `Plug` de instrumentação injetando `trace_id` e propagando W3C Trace Context (ver observabilidade).

---

## 18. Resiliência

**MUST em chamadas externas:**
- **Timeout explícito** — HTTP com `Req`/`Finch`/`Tesla` com `receive_timeout`/`pool timeout` setado; nunca `:infinity`. `Task.await` com timeout finito. `GenServer.call` **nunca** com timeout implícito frouxo em chamada que faz IO.
- **Retry com backoff exponencial + jitter**, só sobre operação **idempotente**.
- **Circuit breaker** (`:fuse`) em dependência instável — abre o circuito e degrada em vez de martelar.
- **Bulkhead:** pool/`Task.Supervisor` dedicado por integração, para uma dependência lenta não esgotar o pool das outras. Detalhe de isolamento de processo em `references/concorrencia.md`.

**MUST — independência e falha de dependência (resiliência por design):**
- **Serviço sobe e opera sozinho.** Ausência/queda de outra dependência (serviço, broker, cache) **nunca** impede o boot nem derruba este serviço. Na árvore de supervisão, dependência externa fica atrás de client resiliente — **não** dá `raise` no `Application.start/2` porque o Redis não respondeu. Supervisor com estratégia sã degrada; não entra em crash-loop de boot. "O `ledger` não sobe sem o `core`" é bug de acoplamento (§2).
- **Falha ao chamar/notificar outro serviço não se perde nem trava a cadeia.** Ao não conseguir notificar B, o serviço A **obrigatoriamente**: (1) **persiste o intento em store durável** — outbox no mesmo `Ecto.Multi`, ou job Oban; **nunca só em memória de processo** (processo morre, mailbox some); (2) **loga com `trace_id`**; (3) **dispara alerta** (Grafana/alertmanager); (4) **retoma** com retry+backoff+jitter idempotente até o limite; estourou → **DLQ** + escala pro humano. Nunca falha em silêncio, nunca perde o dado, nunca deixa a cadeia parada sem sinal.

> "Let it crash" **não** é "perca o dado". Crash de processo é recuperação de estado inesperado — o dado crítico já está durável (outbox/Oban) **antes** de qualquer efeito colateral poder falhar.

---

## 19. Jobs e Workers (Oban)

**Padrão da casa para job persistido: Oban** (fila no próprio Postgres — mesma transação do domínio, visibilidade e retry de fábrica). Fire-and-forget com `Task`/`GenServer` **não** é job de negócio: some no restart.

**MUST**
- Jobs **idempotentes** (executar 2x não corrompe) — job carrega chave de negócio; efeito checa "já fiz isto?".
- **Enfileiramento na mesma transação do estado** que o originou: `Oban.insert/2` dentro do `Ecto.Multi`. Se o commit falhar, o job não existe — casa com o outbox (§9) e mata o dual-write.
- **Unique jobs** (`unique: [period: ..., fields: [...], keys: [...]]`) para não duplicar trabalho concorrente.
- **Timeout por job** (`@impl` com `timeout/1`).
- **Retry explícito com limite:** `max_attempts` finito + backoff (o `backoff/1` padrão do Oban é exponencial com jitter; sobrescrever quando o domínio exigir). **Sem retry infinito.**
- Progresso/estado persistido para job longo ou crítico (checkpoint no próprio registro).
- **DLQ:** job que estoura `max_attempts` vira `discarded` — monitorado e alertado, nunca ignorado silenciosamente.

**SHOULD**
- Job longo divisível em chunks com checkpoint (job que reenfileira o próximo passo).
- Cancelamento gracioso: respeitar sinal de shutdown; Oban drena a fila no `terminate`.
- Agendamento recorrente via `Oban.Plugins.Cron` — cron no banco, não `cron` do host.
- Telemetry de Oban (`[:oban, :job, :stop]`/`:exception`) ligada aos dashboards (ver `references/observabilidade.md`).

---
