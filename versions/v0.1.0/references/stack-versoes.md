# Stack e versões — Elixir, Erlang/OTP, Phoenix e política de deps

> Parte da skill **schematize-elixir**. Define **quais versões** de Elixir, Erlang/OTP e Phoenix a casa suporta, a **matriz de compatibilidade**, como a versão é **fixada e reproduzível**, a **política de bump** e a **escolha de libs núcleo**. Toolchain/lints do dia a dia: `references/padroes-codigo.md`. Deploy da release: `operacao.md` §21. Concorrência/BEAM: `references/concorrencia.md`. Cadeia de suprimentos (SBOM, scan, pin): `references/cadeia-suprimentos.md`. Base agnóstica: `schematize-engineering`.

## 1. Piso de versões — linha suportada, sem EOL

**Regra inegociável:** o projeto roda numa **linha estável ainda suportada** de Elixir e Erlang/OTP; **nada de versão EOL** (end-of-life), nem "presa numa antiga porque migrar dá trabalho". Ficar em EOL é dívida de segurança (§37) — vira prioridade de correção, não "depois".

- **Elixir:** linha estável recente. Referência de calibração (2026): **1.16 / 1.17 / 1.18** aceitas; alvo preferido é a **penúltima ou última estável**. Abaixo da linha suportada → bump (§4).
- **Erlang/OTP:** linha estável recente. Referência: **OTP 26 / 27**. OTP tem janela de suporte própria (as ~3 releases majors mais recentes recebem correção) — a casa acompanha e **não** roda OTP fora dessa janela.
- **Phoenix:** **1.7.x** como piso quando há web; acompanhar minors estáveis. LiveView na linha correspondente suportada.
- **Ecto:** **3.x** corrente.

> As versões numéricas acima são **calibração**, não trava eterna. O **piso normativo é "linha suportada, sem EOL"** — quando a linha avança, o alvo avança junto (§4). Não fixe a skill a um número; fixe ao **estar suportado**.

## 2. Matriz de compatibilidade Elixir ↔ OTP

Elixir roda **sobre** a BEAM: cada versão de Elixir declara a faixa de OTP com que compila e roda. **Cruzar errado quebra o build** ou introduz comportamento sutil. Sempre confira a faixa oficial da versão de Elixir escolhida antes de fixar o OTP.

| Elixir | Erlang/OTP compatível (faixa oficial) | Observação |
|---|---|---|
| 1.18 | OTP 25 – 27 (28 conforme release) | Alvo preferido corrente |
| 1.17 | OTP 25 – 27 | Estável, suportada |
| 1.16 | OTP 24 – 26 | Piso aceitável; planejar bump |
| ≤ 1.15 | faixas antigas | **Evitar** — fora do alvo; migrar |

**Piso operacional:**
- **Rodar sempre num par (Elixir, OTP) que a documentação oficial da versão de Elixir lista como suportado** — não improvisar combinação.
- **A OTP do CI, do dev e do servidor é a MESMA.** Divergência de OTP entre montar a release e rodá-la é fonte de bug de runtime. A release (`operacao.md` §21) embute o ERTS **ou** o host garante a OTP idêntica — decidido em ADR, nunca ao acaso.
- Ao subir Elixir, **verificar** se a OTP-alvo está na faixa **antes** de mexer.

## 3. Versão fixada e reproduzível

A versão da linguagem **não** é "a que estava na máquina". É **declarada, commitada e idêntica** em dev, CI e servidor.

- **`.tool-versions` commitado (asdf ou mise).** Fixa `elixir` e `erlang` (e `nodejs` se houver assets front). É a fonte da verdade do runtime local e do CI:

  ```
  erlang 27.2
  elixir 1.18.1-otp-27
  ```

  O sufixo `-otp-NN` do Elixir **tem que casar** com o major de OTP declarado — precompilado errado é bug silencioso.
- **`mix.exs` declara o requirement da linguagem:**

  ```elixir
  def project do
    [
      app: :my_app,
      version: "0.1.0",
      elixir: "~> 1.18",
      # ...
    ]
  end
  ```

  `elixir: "~> 1.18"` faz o `mix` **recusar** compilar em versão abaixo do piso — trava explícita, não confiança.
- **CI usa a mesma matriz** (ex.: `erlef/setup-beam` lendo `.tool-versions` ou pinado ao mesmo par) e falha se divergir. O par (Elixir, OTP) do CI é o mesmo que monta a release promovida (`operacao.md` §21).
- **Lockfile `mix.lock` commitado, sempre** — reprodutibilidade de deps (`references/cadeia-suprimentos.md`). `mix deps.get` num commit dá **sempre** a mesma árvore.

## 4. Política de bump

Subir versão é rotina saudável, feita **de propósito e registrada**, não deriva acidental.

- **Patch/minor de dep** (`mix.lock`): pela regra escoteiro/higiene contínua; entra no PR, CI verde (`mix test`/`credo`/`dialyzer`), sem cerimônia extra além do diff do lock revisado.
- **Minor de Elixir/OTP/Phoenix:** planejado, com CI rodando o par novo antes de promover; changelog lido (deprecations viram warning → resolver no mesmo PR, não deixar acumular).
- **MAJOR de Elixir, OTP, Phoenix, Ecto, ou troca de lib núcleo → ADR obrigatório (`operacao.md` §27).** O ADR registra: o par (Elixir, OTP) alvo, o que quebra, o plano de migração, quem é dono, e a janela. Bump de major sem ADR é desvio (§37).
- **Nunca EOL.** Entrar em janela de fim de suporte de Elixir/OTP dispara task de bump com prioridade — não espera "sobrar tempo".
- **Deprecation não se ignora.** Warning de deprecation na compilação é dívida com prazo; `credo`/CI podem tratar como falha para forçar a limpeza.

## 5. Libs núcleo — o que a casa usa (e quando NÃO adicionar dep)

A BEAM/OTP já entrega muito (supervisão, `GenServer`, ETS, `:timer`, `Task`, `Registry`) — **a primeira escolha é não adicionar dep**. Dep entra por necessidade real, com nome/licença/versão verificados (`references/cadeia-suprimentos.md`), nunca por reflexo.

| Papel | Escolha da casa | Nota |
|---|---|---|
| Web/HTTP framework | **Phoenix 1.7.x** | LiveView para UI reativa server-side; contexts como fronteira de domínio |
| Servidor HTTP (adapter) | **Bandit** (preferido, novos) · **Cowboy** (legado/consolidado) | Bandit é o default moderno do Phoenix; trocar exige ADR |
| Banco/ORM | **Ecto 3.x** | Queries parametrizadas **sempre**; `Ecto.Query`/changeset, nunca SQL concatenado (§37, `references/dados-eventos.md`) |
| Jobs/filas | **Oban** (Postgres-backed) | Job durável, retry, unicidade, cron; default para background job |
| Pipeline de ingestão/streaming | **Broadway** | Alto volume, back-pressure, conectores (SQS/Kafka/RabbitMQ) — quando Oban não é o encaixe |
| Auth/token | **Guardian** ou **Joken** (JWT) | O **IAM** da casa é app separada (`references/iam.md`) — estas libs são para verificar/assinar token dentro do serviço, não para virar o auth |
| Config validada | **NimbleOptions** | Valida shape/faixa da config de runtime (`operacao.md` §20) |
| HTTP client | **Req** (preferido) sobre Finch | Evitar múltiplos clients na mesma app |
| Telemetria | **:telemetry** + Phoenix LiveDashboard | `references/observabilidade.md` |
| Testes | **ExUnit** (nativo) + **Mox** (mocks por contrato) + **StreamData** (property-based) | `references/testes.md` |

**Quando NÃO adicionar dep:**
- Se OTP/stdlib resolve (um `GenServer`+`Registry`, um `Task.Supervisor`, ETS como cache) — resolve com OTP. Não puxe lib para o que a plataforma já faz bem.
- Se a dep é um wrapper fino que você manteria melhor inline, ou traz árvore transitiva desproporcional ao ganho.
- Dep abandonada (sem release recente, issues sem resposta), sem licença clara, ou de autor não verificável → **não entra**; se já está, vira dívida a remover.
- Cada dep nova é superfície de ataque e custo de manutenção — o ônus de justificar é de quem adiciona (ADR quando for lib núcleo ou decisão arquitetural).

## 6. Estrutura do projeto — umbrella vs apps separados

Duas formas de organizar múltiplos contextos; a escolha é **arquitetural e vai a ADR** quando não for o default.

- **Default da casa: apps/serviços separados** (repositórios/releases independentes por bounded context — `arquitetura.md`), alinhado ao layout `/<app>/<app>_<contexto>` do ops (`operacao.md`/`ops.md` §2) e à **independência de runtime** (piso 10). Cada serviço é sua própria release OTP, seu user, seu node.
- **Umbrella (`apps/` num repo):** agrupa apps OTP relacionadas sob um `mix.exs` raiz e deps compartilhadas. Útil quando os contextos são **fortemente coesos** e implantados **juntos**, com fronteira de módulo clara entre as apps. **Cuidado:** umbrella facilita acoplar contextos que deviam ser independentes — vira monólito distribuído disfarçado se as apps passam a depender do boot uma da outra (fere piso 6/10, `ops.md` §6). Escolher umbrella exige ADR justificando a coesão e o deploy conjunto.
- **Regra prática:** contextos que escalam, versionam ou falham **independentes** → serviços separados. Contextos que só existem juntos e sempre sobem juntos → umbrella é aceitável, com ADR. Na dúvida, **separado** (mais fácil separar depois do que desacoplar um umbrella acoplado).

## 7. Integração com o resto da casa

| Tema | Onde |
|---|---|
| Toolchain/lints (`format`/`credo`/`dialyzer`), limites de arquivo, MAPA | `references/padroes-codigo.md` |
| Config de runtime (`runtime.exs`), sem segredo em config compilada | `operacao.md` §20 |
| Release OTP, migration por `eval`, deploy, ADR de bump | `operacao.md` §21, §27 |
| Concorrência/BEAM, supervisão, OTP como primeira escolha | `references/concorrencia.md` |
| Cadeia de suprimentos: `mix.lock`, SBOM, `mix hex.audit`/`deps.audit`, pin | `references/cadeia-suprimentos.md` |
| Libs de auth vs o IAM da casa (app separada) | `references/iam.md` |
| Banco/eventos/jobs (Ecto, Oban, Broadway) | `references/dados-eventos.md` |
| Testes (ExUnit, Mox, StreamData) | `references/testes.md` |

> Regra de bolso: **linha suportada, nunca EOL; par (Elixir, OTP) oficial e idêntico em dev/CI/servidor; `.tool-versions` + `mix.exs elixir:` + `mix.lock` commitados; major = ADR; OTP primeiro, dep depois.**
