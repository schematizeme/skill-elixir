---
description: Roda o gate da Definition of Done e anti-padrões (§35, §37) no diff atual
argument-hint: "[ref git, ex: origin/main]"
---

Faça o **review de padrões** do diff atual (contra $ARGUMENTS ou `origin/main`),
combinando o checker determinístico com seu julgamento.

1. Rode `bash scripts/check-diff.sh ${ARGUMENTS:-origin/main}` e leia o resultado.
2. Rode os gates de linguagem Elixir e leia a saída:
   - `mix format --check-formatted` (formatação canônica; falha = bloqueia).
   - `mix credo --strict` (clean code / smells; achado sério = bloqueia).
   - `mix dialyzer` (typespecs coerentes; erro de type = bloqueia).
3. Some a isso a análise que o script NÃO faz bem sozinho:
   - **§37 (anti-padrões):** segredo no cliente, SQL/Ecto fragment concatenado, auth
     no client, `tenant_id`/`org_id` vindo do body/params, JWT sem validar,
     `:rand`/`Enum.random` pra token (use `:crypto.strong_rand_bytes`), `rescue`/`catch`
     que engole erro, `!`-bang que ignora `{:error, _}`, teste silenciado, etc.
   - **§6:** arquivo >750 linhas (ou >~500 úteis) → bloqueia; >300 úteis (~400 obs) → flag;
     função pública sem `@doc`/`@spec` (o quê + onde).
   - **§39:** o índice de funcionalidades foi atualizado no mesmo PR?
   - **Dados:** toda migration Ecto é reversível (`change`/`up`+`down` testados)?
   - **§3:** backend novo em Node/PHP? (proibido).
4. Produza um relatório com `BLOQUEIA` (viola piso/DoD) e `ATENÇÃO` (melhorar),
   citando arquivo:linha. Se houver qualquer `BLOQUEIA`, a task **não está pronta** (§35).

Seja específico e acionável — aponte o conserto, não só o problema.
