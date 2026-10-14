# Concorrência e OTP (Elixir/BEAM)

> Parte da skill **schematize-elixir**. É por isto que Elixir é sancionado na casa:
> realtime, alta concorrência **tolerante a falha**, distribuído, streaming, pub-sub.
> Os erros mais caros de um sistema BEAM não são de compilação — são de **desenho de
> processo**: bloquear o scheduler, supervisão errada, fila ilimitada que estoura a
> memória, e assumir que "distribuído é grátis". Esta reference é o piso de
> concorrência. Liga com `references/dados-eventos.md` (resiliência, jobs, eventos),
> `references/observabilidade.md` (`:telemetry`) e `references/stack-versoes.md`
> (versões de OTP/Elixir/libs).

**Princípio-mãe do BEAM:** **mensageria não é memória compartilhada.** Cada processo
é isolado, tem seu próprio heap, e a única forma de interação é **mensagem**. Não há
lock nem race sobre estado — há **contenção de mailbox** e **acoplamento de
protocolo**. Projete o sistema como uma **árvore de processos supervisionados**, não
como um monólito de funções que compartilham variáveis.

## Índice
- A1. Processos e isolamento (actor model)
- A2. GenServer — estado, `call`/`cast`/`info`, contenção
- A3. Supervisão e "let it crash"
- A4. DynamicSupervisor + Registry
- A5. Task, Task.Supervisor e Agent
- A6. Não bloquear o scheduler
- A7. Backpressure real (GenStage/Broadway/Oban)
- A8. Distribuição e PubSub
- A9. Idempotência, cancelamento e graceful shutdown

---

## A1. Processos e isolamento (actor model)

Processo BEAM é barato (milhares/milhões coexistem), pré-emptivo e isolado. O crash
de um **não** corrompe outro — só derruba o próprio estado, que a supervisão
reinicia limpo.

**MUST**
- **Um processo por unidade de estado/vida** com dono claro. Estado mutável vive
  **dentro** de um processo (GenServer/Agent), acessado só por mensagem.
- **Protocolo de mensagem explícito e versionado** entre processos — o formato da
  mensagem é contrato, documentado no `@doc` (ver `padroes-codigo.md` §3).
- **Estado compartilhado só read-mostly** vai em **ETS** (tabela concorrente), não em
  um GenServer que vira gargalo de leitura. ETS pra cache/lookup; processo pra
  decisão/serialização.

**VETADO**
- Simular memória compartilhada com um processo global que todo mundo consulta em
  série — vira ponto único de contenção (ver A2).
- Vazar `pid` cru como "endereço estável": pid morre no restart. Use **Registry**
  ou nome registrado.

**SHOULD**
- Modelar o domínio como processos quando há **estado vivo + concorrência + falha**
  (sessão, conexão, worker, saga). Cálculo puro sem estado é **função**, não
  processo — não crie GenServer por moda.

---

## A2. GenServer — estado, `call`/`cast`/`info`, contenção

`GenServer` serializa o acesso ao estado: mensagens processadas **uma por vez**.
Isso dá consistência de graça e **contenção** como preço.

**MUST**
- **`handle_call` (síncrono) quando o chamador precisa da resposta / de backpressure**
  — o chamador espera, então o produtor não corre à frente do servidor. **`handle_cast`
  (assíncrono) só quando o resultado não importa** e a perda em crash é aceitável;
  cast **não** dá backpressure e a mailbox pode crescer sem limite (ver A7).
- **`handle_info` trata mensagens fora do protocolo** (timeouts, `:DOWN` de monitor,
  mensagens de sistema). Sempre ter cláusula catch-all de `handle_info` que **loga e
  ignora** o inesperado, senão a mailbox entope.
- **Timeout explícito em `GenServer.call/3`** — o default de 5s existe, mas defina o
  seu. Trabalho longo dentro do `handle_call` **bloqueia o servidor inteiro**: mova
  pra uma `Task` e responda depois (`{:noreply, ...}` + `GenServer.reply/2`), ou use
  `handle_continue` pra pós-inicialização.
- **`init/1` leve.** Trabalho pesado no `init` bloqueia o supervisor no boot; use
  `{:ok, state, {:continue, :setup}}` e faça o pesado em `handle_continue`.

**VETADO**
- **Um GenServer "singleton" no caminho quente** por onde passa todo request — é
  gargalo serial que desperdiça o BEAM. Particione (um processo por chave/tenant via
  Registry — A4) ou use ETS pra leitura.
- **Chamada bloqueante (I/O, `:timer.sleep`, HTTP síncrono) dentro de `handle_call`/
  `handle_cast`** — trava o processo e enfileira todo mundo atrás.

**SHOULD**
- Emitir `:telemetry` de tamanho de mailbox e latência de `handle_*` pra flagrar
  contenção antes de virar incidente (liga com `references/observabilidade.md`).

---

## A3. Supervisão e "let it crash"

Supervisor não faz trabalho — **observa filhos e reinicia** conforme a estratégia.
A filosofia é **deixar crashar**: em vez de blindar cada função com `try/rescue`, deixe
o processo morrer no estado ruim e **renascer limpo** a partir de um estado conhecido.

**MUST**
- **Toda parte com estado vive sob um Supervisor** — nada de processo solto
  (`spawn`/`start_link` sem árvore). O boot da aplicação é uma árvore
  (`Application.start/2` → supervisor raiz).
- **Escolha a estratégia pelo acoplamento dos filhos:**
  - **`:one_for_one`** — filhos independentes; só o que caiu reinicia. **Default.**
  - **`:rest_for_one`** — filhos em cadeia de dependência (B/C dependem de A); se A
    cai, A e os iniciados **depois** dele reiniciam, na ordem.
  - **`:one_for_all`** — filhos fortemente acoplados que só fazem sentido juntos; se
    um cai, **todos** reiniciam.
- **`max_restarts`/`max_seconds` calibrados** — se um filho reinicia em loop, o
  supervisor **desiste e propaga o crash pra cima** (escalada). Isso é feature: um
  serviço que não estabiliza deve falhar visível, não flapar em silêncio.

**VETADO**
- **`try/rescue` pra mascarar erro** e "seguir em frente" com estado corrompido — é o
  oposto do modelo. `rescue` é pra **fronteira controlada** (traduzir exceção de lib
  externa em `{:error, _}`), não pra engolir bug do domínio.
- **`Process.flag(:trap_exit, true)` "pra não morrer"** sem tratar o exit — vira
  processo zumbi que sobrevive corrompido. Trap só quando você **precisa** limpar
  recurso no `terminate/2` (A9).

**SHOULD**
- Estado que **precisa sobreviver ao restart** não fica na memória do processo:
  persista (banco/ETS externo/`:persistent_term`) e rehidrate no `init`/`continue`.

---

## A4. DynamicSupervisor + Registry

Pra quantidade **dinâmica** de processos iguais (uma sessão por usuário, um worker
por tarefa, um processo por chave de negócio).

**MUST**
- **`DynamicSupervisor`** pra iniciar/parar filhos em runtime (não `Supervisor` de
  lista estática). Cada filho supervisionado, com a mesma política de restart.
- **`Registry` pra endereçar por chave**, não por pid. `{:via, Registry, {Reg, chave}}`
  dá nome estável que sobrevive ao restart (o novo processo se re-registra). Garante
  também **unicidade** (um processo por chave).
- **Partition o Registry** (`:partitions`) sob alta concorrência de registro/lookup,
  pra não serializar no próprio Registry.

**VETADO**
- Manter um `Map pid => dado` num GenServer central pra "achar" processos — reinventa
  o Registry pior e vira gargalo. Use Registry.
- Iniciar filho dinâmico **fora** do DynamicSupervisor (`start_link` solto) — fica
  órfão, sem restart.

**SHOULD**
- Limite superior de processos dinâmicos (`max_children`) quando a entrada é externa —
  senão é DoS por criação ilimitada de processo.

---

## A5. Task, Task.Supervisor e Agent

- **`Task`** — computação assíncrona pontual (fan-out, chamada paralela). `Task.async`
  + `Task.await` (com **timeout** e cláusula de estouro), ou `Task.async_stream/3`
  com **`max_concurrency`** pra concorrência limitada (backpressure natural — A7).
- **`Task.Supervisor`** — pra Task que pode falhar sem derrubar o chamador, ou
  **fire-and-forget** supervisionado (`Task.Supervisor.start_child`). Task não
  supervisionada que falha pode matar quem a criou.
- **`Agent`** — estado simples atrás de um processo, sem protocolo custom. **Só pra
  estado trivial e de baixa contenção.**

**MUST**
- Fan-out concorrente usa **`Task.async_stream` com `max_concurrency` definido** e
  `timeout`/`on_timeout: :kill_task` — nunca disparar N tasks ilimitadas contra um
  upstream (é o mesmo pecado da fila ilimitada — A7).
- `Task.await` **sempre com timeout** e tratamento do estouro; sem isso, trava.

**VETADO**
- **`Agent` como banco de dados / cache primário / fila.** Agent é estado em memória
  de **um** processo: não persiste, não escala horizontalmente, é ponto único de
  contenção e some no restart. Precisa persistir → banco (Ecto); cache concorrente →
  ETS; fila com garantia → Oban (`references/dados-eventos.md`).
- `Task.async` sem `await`/supervisão pra trabalho fire-and-forget — use
  `Task.Supervisor`.

**SHOULD**
- Preferir `Task.async_stream` a montar pool de GenServer na mão pra paralelizar
  trabalho homogêneo — mais simples, com backpressure embutido.

---

## A6. Não bloquear o scheduler

O BEAM tem N schedulers (≈ núcleos) que multiplexam milhões de processos por
pré-empção **cooperativa em reduções**. Código nativo que não devolve o controle
**congela um scheduler inteiro** — e a latência de tudo desaba.

**MUST**
- **NIF longo é proibido no scheduler normal.** NIF que roda > ~1ms deve ir pra
  **dirty scheduler** (`:dirty_cpu`/`:dirty_io`) ou ser fatiado. NIF que trava o
  scheduler é o pior bug de latência do BEAM.
- **Espera é `Process.send_after`/`:timer.send_interval`**, nunca `:timer.sleep` num
  processo crítico — `sleep` **bloqueia o processo** e, se for do caminho quente,
  segura mailbox atrás dele. `sleep` só em teste/script.
- **Chamada bloqueante de sistema (porta, driver, FFI síncrono, DNS lento)** vai por
  **Port**/processo dedicado ou dirty IO — não crua no caminho quente.
- **CPU pesado** (criptografia, compressão, parsing gigante) roda com consciência do
  custo em reduções; se segura o scheduler, isole em processo/dirty scheduler e emita
  métrica.

**VETADO**
- `receive` sem `after` num processo que também precisa responder a outras mensagens
  (bloqueia até chegar exatamente aquela mensagem).
- `:timer.sleep` pra "dar um tempo" dentro de GenServer no caminho de request.

**SHOULD**
- Medir `run_queue`/scheduler utilization (`:telemetry`/`:observer`); scheduler
  saturado com CPU baixa = NIF/BIF bloqueante escondido.

---

## A7. Backpressure real (GenStage/Broadway/Oban)

O BEAM não te salva de **fila ilimitada**: mailbox de processo e canal sem limite
crescem até o **OOM**. Backpressure é **desenho**, não sorte.

**MUST**
- **Toda fila/pipeline é limitada.** Ingestão de stream/eventos → **GenStage**
  (demand-driven: consumidor puxa, produtor respeita) ou **Broadway** (fonte
  SQS/Kafka/RabbitMQ com `concurrency`, `batch`, e backpressure embutido).
- **Job assíncrono com garantia → Oban** com **concorrência limitada por fila**
  (`queues: [default: 10, ...]`), retries, unicidade e dead-letter. Persistido no
  Postgres — sobrevive a restart (liga com `references/dados-eventos.md` §19).
- **Produtor mais rápido que consumidor tem que ESPERAR** (ou descartar com métrica,
  ou rejeitar) — política **explícita**, decidida, não acidental.

**VETADO**
- **Fila/pipeline ilimitada de qualquer forma:** `handle_cast` em rajada sem limite,
  `send` em loop pra um processo lento, `Task.async` em cima de lista de entrada
  externa sem `max_concurrency`, consumir tópico sem controlar demanda. Tudo isso é
  **OOM esperando carga**.
- Usar mailbox de GenServer como fila de trabalho ilimitada.

**SHOULD**
- Instrumentar profundidade de fila/lag do consumidor e alertar (liga com
  `references/observabilidade.md`); lag crescente é o sinal antecipado de saturação.

---

## A8. Distribuição e PubSub

Vários nós BEAM formam um cluster e trocam mensagem "transparente". **Distribuído não
é grátis:** a rede **particiona, atrasa e mente**. Transparência de sintaxe não é
transparência de falha.

**MUST**
- **Toda chamada entre nós tem timeout e trata indisponibilidade** — nó remoto pode
  estar particionado. Não há entrega garantida: mensagem entre nós pode se perder.
- **Nomes globais com cuidado:** `:global` serializa registro no cluster e sofre em
  partição (split-brain → conflito de nome). Pra registro local escalável use
  **`Registry`**; pra distribuído prefira uma lib de CRDT/consistência
  (ex.: `Horde`, `libcluster` pra formação) com política de conflito **explícita**.
- **Particionamento por chave** (consistent hashing) pra localizar o processo dono de
  uma entidade sem broadcast — e defina o que acontece quando o nó dono cai.
- **`Phoenix.PubSub`** pra fan-out de eventos (realtime, LiveView, Channels); é
  best-effort dentro do cluster — **não** é fila durável. Evento que **não pode
  perder** vai por Oban/Outbox (`references/dados-eventos.md`), não por PubSub.
- **`Phoenix.Presence`** (CRDT) pra estado de presença convergente entre nós — assuma
  convergência **eventual**, não instantânea.

**VETADO**
- Assumir entrega/ordem/atomicidade entre nós. Sem idempotência (A9), replay duplica.
- Tratar o cluster como um "computador só": chamada remota síncrona no caminho de
  request sem timeout/fallback trava o request quando a rede engasga.

**SHOULD**
- "Distribua só o que precisa": muita coisa que parece exigir cluster resolve com um
  nó robusto + Postgres/Oban. Cluster entra por realtime/escala horizontal real, com
  ADR registrando o custo.

---

## A9. Idempotência, cancelamento e graceful shutdown

**MUST**
- **Idempotência** em todo consumidor/handler que pode reprocessar (retry de Oban,
  redelivery de broker, reenvio entre nós): dedup por id de evento/chave natural. Sem
  isso, "pelo menos uma vez" vira cobrança/efeito duplicado (liga com
  `references/dados-eventos.md`).
- **Cancelamento propagado, não abortado no escuro:** trabalho longo escuta um sinal
  de parada (mensagem/`shutdown`) e encerra limpo, sem deixar invariante quebrada
  (transação semi-aberta, lock de negócio preso).
- **Graceful shutdown / drain no SIGTERM:** ao receber o sinal, **parar de aceitar**
  novo trabalho (fechar endpoint/consumidor), **drenar** o que está em voo com
  timeout, e só então sair. Supervisor propaga `shutdown` aos filhos com o timeout
  configurado (`shutdown:` do child spec).
- **`terminate/2` NÃO é garantido** — não roda em `:brutal_kill`, em crash do BEAM,
  ou se o processo não faz `trap_exit`. **Nunca** dependa de `terminate/2` pra
  correção (ex.: "salvo no shutdown"). Persistência crítica é feita **no fluxo**, não
  na despedida. `terminate/2` serve pra best-effort de limpeza (fechar conexão, flush
  de buffer), com `Process.flag(:trap_exit, true)` quando precisa recebê-lo.

**VETADO**
- Depender de `terminate/2` pra não perder dado; confiar em ordem/tempo de shutdown
  entre processos sem coordenar via supervisor.

**SHOULD**
- Testar shutdown de verdade (SIGTERM em staging, drain sob carga) — a maioria dos
  vazamentos de conexão/trabalho perdido só aparece no drain real.

---

> **Regra de bolso:** **um processo por estado vivo, tudo sob supervisor, deixe
> crashar em vez de blindar, não bloqueie o scheduler, limite TODA fila (VETADO fila
> ilimitada), e trate distribuído como rede que falha — mensageria não é memória
> compartilhada.** O BEAM te dá isolamento e tolerância a falha de graça; concorrência
> correta (backpressure, idempotência, drain) é com você.
