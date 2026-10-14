# Padrões de Código (Elixir) — limites, granularidade, `@doc`/`@spec` e MAPA

Piso normativo de **organização do código** para a skill **schematize-elixir**,
especializando a base agnóstica da casa (idêntica em `schematize-go`/`schematize-rust`)
para os idiomas de Elixir/OTP. É inegociável: vale para código humano e gerado por
IA. O gate `/elixir-review` (DoD) reprova o que violar isto. Os pisos de **número**
(750/500/300, uma unidade por arquivo, tudo documentado, MAPA exaustivo) são os
mesmos das skills irmãs — muda só a **forma** de cumprir em Elixir.

## 1. Tamanho de arquivo — teto de 750 linhas (≤ 500 de código útil + ~250 de comentário)

Regra **em camadas**: um teto duro generoso e um **flag** mais cedo que sinaliza
cheiro de módulo/função extensa. A ideia é dar espaço pra código bem documentado
(`@moduledoc`, `@doc`, `@spec`) sem soltar a mão da granularidade.

- **Teto DURO: 750 linhas por arquivo `.ex`/`.exs`** (sem contar o cabeçalho de
  `defmodule`/`use`/`import`/`alias` no topo). Desse orçamento, **~250 linhas são
  reservadas a `@moduledoc`/`@doc`/`@spec` e comentário** (§3) e **até ~500 são
  código útil**. Passou de **750 no total** — ou de **~500 de código útil** →
  **quebre em mais de um módulo/arquivo**, por coesão (uma responsabilidade por
  arquivo), nunca por corte arbitrário no meio de uma função ou cláusula. O gate
  `check-diff` (§6) **BLOQUEIA** acima do teto.
- **FLAG em > 300 linhas de código útil** (não bloqueia, mas **sempre sinaliza**):
  se o **código útil** — descontando `@doc`/comentário/linha em branco — passar de
  **300 linhas**, é **indício** de que o módulo/função está **muito extenso** e
  provavelmente **pede um contexto (bounded context) próprio ou um nível de
  abstração maior** (extrair um módulo de domínio, um `GenServer` dedicado, um
  `Ecto.Schema` separado). Não trava a entrega; o gate **flagueia sempre** e o
  ponto entra como **dívida técnica** (registre no archive/ADR). **Nunca engula o
  flag.**
- **Observabilidade tem folga natural (~400 úteis):** módulos dominados por
  instrumentação (`:telemetry` handlers, exporters OTel, structured logging) incham
  por natureza — ~400 linhas úteis é esperado. Pra esses, o flag só é significativo
  acima de **~400** de código útil (ainda assim registrado). O teto duro de 750/500
  continua valendo igual. Liga com `references/observabilidade.md`.
- **Escopo: código-fonte** (`.ex`, `.exs`, incluindo `.heex` com lógica). **Fora do
  escopo** (não disparam o gate): documentação e Markdown (references, README, ADR,
  archive, MAPA), config (`config/*.exs`, `mix.exs` de deps), `mix.lock`, migrations
  geradas e fixtures — bom senso de tamanho, mas o gate mede **código**, não texto.
- Quebrou um arquivo? Atualize o **MAPA** (§4) no mesmo PR.

## 2. Uma unidade lógica por arquivo/módulo

- Em Elixir a unidade é o **módulo**: **um módulo público por arquivo**, com nome do
  arquivo espelhando o nome do módulo (`lib/loja/pedido/finalizar.ex` →
  `Loja.Pedido.Finalizar`). O arquivo existe para entregar aquela responsabilidade;
  funções privadas (`defp`) e cláusulas da mesma unidade convivem, desde que sirvam
  só a ela e o arquivo siga o teto (§1).
- **Função com > 300 linhas de código útil dispara o flag** (§1). Em Elixir isso
  quase sempre significa: **`case`/`cond`/`if` aninhado profundo** que devia ser
  **pattern-matching em múltiplas cláusulas de função** ou um `with` de happy path;
  ou um `GenServer` acumulando responsabilidades que pedem módulos separados. Quebre
  em funções nomeadas com propósito único; mova pra seus arquivos quando puder.
- **Módulos coesos por contexto (Phoenix Context / DDD):** o agrupamento é por
  **bounded context** (`Loja.Contas`, `Loja.Pagamentos`), não por camada técnica.
  A API pública do contexto é a fronteira; o resto é privado ao contexto. Liga com
  `references/arquitetura.md`.
- Sem **módulo-balaio** (`Loja.Utils`, `Loja.Helpers`, `Loja.Commons`) que acumula
  funções sem relação. Nome do módulo/arquivo = o que ele faz.

## 3. Tudo documentado: `@moduledoc` + `@doc` + `@spec`

**Toda função pública** (`def`, e as macros públicas) carrega **`@doc` + `@spec`** —
não é opcional. Todo módulo carrega **`@moduledoc`** (ou `@moduledoc false` explícito
quando é interno/privado por design, com uma linha de motivo). O par `@doc`/`@spec`
é o **contrato** e alimenta o índice de microfunções (§39). O `@doc` responde, no
mínimo:

- **Por quê existe** — o problema que resolve / a decisão que encapsula.
- **Como se espera que funcione** — o passo-a-passo em uma frase; pré-condições e
  invariantes; **qual cláusula casa com o quê** quando há pattern-matching.
- **Entradas** — cada parâmetro: o que é, faixa/validação; struct/tipo esperado.
- **Saídas** — o **`@spec`** é a fonte da verdade do tipo de retorno. Em Elixir o
  retorno esperado é **tupla `{:ok, valor}` / `{:error, motivo}`** pra fluxo previsto
  (§5); documente cada `motivo` possível e quando ocorre.
- **Efeitos colaterais** — I/O, rede, Ecto/banco, envio de mensagem a processo
  (`send`/`GenServer.cast`), publicação em `Phoenix.PubSub`, mutação de ETS/estado
  de processo. Se **envia mensagem a outro processo/nó**, diga a quem e o formato.
- **Fluxo do dado (começo → meio → fim)** — **de onde vem** (qual origem/serviço/
  fila/tabela/tópico PubSub; se vem de **outra aplicação/nó BEAM**, nomeie qual e o
  contrato/evento), **o que é feito** (a transformação/decisão), e **pra onde vai**
  (destino: qual processo/tópico/tabela/resposta). Toda função que **cruza fronteira
  de aplicação, contexto ou processo** diz isso explicitamente.

`@doc` que só repete a assinatura não conta. Quem chama entende a função **sem ler o
corpo**. O índice de microfunções (`/elixir-index`) é **gerado** desses `@doc`/`@spec`
e falha o CI se achar função pública sem contrato. **Toda funcionalidade é mapeada**
(§4): busca burra que torra token e tempo é sintoma de mapa incompleto, não de falta
de busca.

## 4. MAPA da aplicação (arquivo-guia obrigatório)

Todo projeto que segue esta skill mantém um **`MAPA.md`** em
**`<projeto>_archive/index/MAPA.md`** (template em `assets/MAPA.md`) — **nunca no root
do projeto**. Todo MD **gerado** (MAPA, índices, planos, relatórios, handoffs) mora no
archive; o root fica limpo (só código, config e os poucos MDs mantidos à mão: README,
`CLAUDE.md`, LICENSE). Layout canônico do archive em `references/operacao.md` (§28). É
parte da entrega, atualizado **no mesmo PR** que mexe no código. Lista, para **cada**
função — pública e privada (`def`/`defp`), **sem exceção** (uma entrada por função):

- **Onde está** — caminho do arquivo e `Modulo.funcao/aridade`.
- **Para que serve** — propósito em uma linha.
- **Dependências** — o que chama (funções/módulos/contextos/serviços/processos).
- **Auxiliares** — quem a apoia / quem depende dela (chamadores).
- **Entrada e saída** — de onde vêm os dados e pra onde vão (args/retorno, rota,
  tópico PubSub, fila Oban, mensagem de processo, tabela Ecto).

O MAPA tem duas camadas:

- **Global** (mantido à mão): aplicações OTP, `lib/`, contextos, **árvore de
  supervisão** (quem supervisiona quem — liga com `references/concorrencia.md`),
  pontos de entrada (rotas Phoenix/Channels/jobs Oban/`mix` tasks) e de saída
  (banco/PubSub/nó remoto/API externa).
- **Microfunções** (gerado por `/elixir-index` a partir dos `@doc`/`@spec` §3).

O índice de microfunções é **exaustivo e conferível por contagem**: **uma entrada por
função** de cada app/contexto — `nº entradas == nº funções` do código. Menos que isso
é **falha**, não "resumo". E o MAPA é um **grafo**, não uma lista — traz o **grafo de
processos/serviços** (quem chama/notifica quem, quem supervisiona quem) e o **grafo de
chamadas** por função, como **Mermaid + adjacência**. Contrato e gate:
`references/entrega.md` §39.

Sem MAPA atualizado, o PR não passa na DoD.

## 5. Idiomas Elixir inegociáveis

Piso de estilo específico da linguagem. O gate `/elixir-review` e o Credo reprovam
desvio sem justificativa.

**MUST**
- **Pattern-matching na assinatura** — decompor entrada em cláusulas de função
  (múltiplos `def foo(%{status: :ativo})`) em vez de `case`/`if` no corpo. Guards
  (`when`) pra refinar. É o jeito idiomático de ramificar.
- **Pipe `|>` pra transformação encadeada** — dado que flui por uma sequência de
  funções, com o dado como **primeiro argumento**. Nada de pipe que quebra em pedaço
  ilegível; se ficou confuso, extraia funções nomeadas.
- **`with` pro happy path** — encadear operações que retornam `{:ok, _}`/`{:error, _}`
  com um `else` único pra os erros. Substitui a pirâmide de `case` aninhado.
- **Tuplas `{:ok, _}` / `{:error, motivo}` pra fluxo esperado**, não exceção. Exceção
  é pra o **excepcional** (bug, invariante violada) — e, no BEAM, muitas vezes o certo
  é **deixar crashar** (ver `references/concorrencia.md`), não `rescue` defensivo.
- **`mix format` obrigatório** — formatação não é opinião; CI reprova diff não
  formatado. **Credo** como linter (com config versionada), reprovando o build no
  modo estrito.
- **`snake_case`** pra funções/variáveis/átomos; **`CamelCase`** pra módulos;
  **`?`** em predicados (`ativo?/1`), **`!`** só em fronteira controlada (ver abaixo).

**SHOULD**
- **Typespecs (`@spec`/`@type`) + Dialyzer (Dialyxir)** no **domínio crítico** —
  contratos de contexto, fronteiras de aplicação, dados que cruzam processo/nó.
  Dialyzer no CI pra esses caminhos; não precisa ser 100% do código, mas o núcleo
  sim.
- **Funções pequenas e puras** onde der — separe a decisão (pura, testável) do efeito
  (I/O, envio de mensagem). Facilita teste sem mock.

**VETADO**
- **`case`/`if`/`cond` aninhado profundo** (> 2 níveis) quando pattern-matching de
  cláusula ou `with` resolve. É o principal cheiro que dispara o flag §2.
- **`!`-bang fora de fronteira controlada.** `Repo.get!`, `Repo.insert!`, `File.read!`, `Jason.decode!`
  e afins **crasham** em vez de retornar `{:error, _}` — só onde o crash é o comportamento desejado
  (ex.: seed, script, fronteira que já validou). No fluxo de negócio, use a variante que retorna
  tupla. *(Cuidado com o exemplo: **`String.to_atom!` não existe** — ✔ verificado em 2026-08-21,
  `function String.to_atom!/1 is undefined`. O par real é `String.to_atom/1`, que é o perigoso, e
  `String.to_existing_atom/1`, que é o seguro — ver o item abaixo.)
- **`String.to_atom/1` sobre entrada externa** — átomos **não são coletados pelo GC** e a tabela
  tem teto (`+t`, ~1M por default): é DoS por esgotamento, e quando ela estoura a VM **morre
  inteira**, não a request. Use **`String.to_existing_atom/1`** (levanta `ArgumentError` se o átomo
  não existe — que é o comportamento desejado) e garanta que o átomo esperado já exista, senão
  ele nunca vai existir em runtime. O mesmo vale para `List.to_atom/1`,
  `:erlang.binary_to_atom/2` e para `Jason.decode(..., keys: :atoms)` — este último é o que passa
  despercebido, porque parece só uma opção de parsing. Liga com `references/seguranca.md`.
- **Módulo-balaio, `@doc`/`@spec` ausente em função pública, código não formatado.**

## Checklist (entra na Definition of Done)

- [ ] Nenhum arquivo `.ex`/`.exs` > 750 linhas (nem > ~500 de código útil) — teto duro.
- [ ] Arquivo/função com > 300 linhas de código útil (~400 em observabilidade) **flagueado** e registrado como dívida (não bloqueia, mas nunca silenciado).
- [ ] Um módulo/unidade lógica por arquivo; agrupamento por contexto, sem módulo-balaio.
- [ ] Toda função pública com `@doc` + `@spec`; todo módulo com `@moduledoc` (ou `@moduledoc false` justificado).
- [ ] Idiomas: pattern-matching na assinatura, `|>`, `with` no happy path, tuplas `{:ok,_}`/`{:error,_}`; sem `case`/`if` aninhado profundo; sem `!`-bang fora de fronteira.
- [ ] `mix format` limpo e **Credo** sem violação; **Dialyzer** verde no domínio crítico.
- [ ] `MAPA.md` atualizado no mesmo PR, em **`<projeto>_archive/index/`** — camada global (com árvore de supervisão) à mão + microfunções gerada.
- [ ] Índice de microfunções **exaustivo**: uma entrada por função, `nº entradas == nº funções` (`/elixir-index` **reprova** se faltar); nenhuma órfã.
- [ ] **Grafo** presente: processos/supervisão (quem supervisiona/notifica quem) + chamadas por função (Mermaid + adjacência).
