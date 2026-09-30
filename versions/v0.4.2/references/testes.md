# Testes — recorte Elixir/OTP

> **PONTEIRO, não cópia.** A **disciplina de teste** da casa é da **`schematize-qa`**: a pirâmide,
> teste de COMPORTAMENTO (não "renderizou"), o "verde de verdade" (smoke com asserção de conteúdo +
> assertion negativa + self-check que força uma falha conhecida), cobertura útil, a11y, regressão
> visual, contrato/dados, **flaky** (quarentena com prazo e dono), o fluxo **plan-first**
> (`/qa-plan` → `/qa-run`) e os **gates de CI que travam o merge**. Leia
> `schematize-qa` → `references/estrategia.md`, `references/categorias.md`,
> `references/execucao.md` e `references/flaky.md`.
>
> **Segurança ofensiva** (rejeição rota a rota, injeção/coerção, IDOR/BOLA, cross-tenant) é a
> **`schematize-pentest`** — não é Q.A. e não mora aqui.
>
> Aqui fica **só o que muda em Elixir/OTP**: o runner, a sintaxe, e as armadilhas do dialeto.
>
> *(Este arquivo e a antiga reference *testes-execucao* eram, juntos, ~450 linhas por skill — 66% já
> duplicado na `schematize-qa`, 23% que pertence à `schematize-pentest` e ~2% idiomático de
> verdade. Deriva por cópia foi o achado da Classe C/D da vistoria de 2026-08-21.)*

## O runner e o comando

```bash
mix test                               # suíte
mix test --seed 0 --trace              # determinístico e verboso
mix test --cover                       # cobertura
mix test --only integration            # tags
```

## O que muda de forma em Elixir/OTP

- **`async: true` só quando o caso NÃO toca estado global** (ETS nomeada, `:persistent_term`,
  `Application.put_env`, o mesmo registry). Marcar tudo como async é a origem clássica de flaky no
  BEAM — e o sintoma é "falha só no CI, que tem mais cores".
- **Ecto `SQL.Sandbox`**: `:manual` + `checkout` por teste. Processo que você **spawna** precisa de
  `allow/3`, senão ele vê um banco vazio e o teste passa por engano.
- **Teste de OTP é sobre a ÁRVORE, não sobre a função.** Prove que o supervisor **reinicia** o
  filho (mate com `Process.exit(pid, :kill)` e assere o novo pid) e que a estratégia de restart é a
  declarada — supervisão que ninguém testou é supervisão que ninguém tem.
- **`assert_receive` com timeout explícito** em vez de `Process.sleep`; e `refute_receive` para
  provar que a mensagem **não** vem.
- **`start_supervised!/1`** em vez de `start_link` no setup: o ExUnit derruba o processo no fim,
  sem vazar entre testes.
- **`Mox`** com contrato verificado (`verify_on_exit!`) — mock sem contrato é `:meck` disfarçado.
- **Property-based:** `stream_data` (`property/1` nativo do ExUnit).
- **`mix test --cover` não mede macro**: código gerado por macro aparece como não coberto; não
  baixe a régua por causa disso, marque a exceção.

## Onde divergir da base, a base manda

O piso é o mesmo: teste é **visto falhar no vermelho** antes de valer; cobertura é **contrato**
(não se baixa a régua para passar o CI); **teste nunca dispara efeito externo real** — endereço no
domínio de teste em rota nula, provider = sink, cap por execução, e a caixa se confere **lendo do
sink** (`references/iam.md` §3.1 desta skill; normativa em `schematize-engineering` →
`references/efeitos-externos.md`); e **gate não se desliga "por enquanto"**.
