---
description: schematize-elixir — lista todos os comandos disponíveis e o que cada um faz
---

Mostre ao usuário a lista de comandos do conjunto **schematize-elixir**, em formato
de tabela legível, exatamente com este conteúdo (ajuste se houver comandos novos
instalados em `.claude/commands/`):

| Comando | O que faz |
|---|---|
| `/elixir-help` | Lista todos os comandos do schematize-elixir (este). |
| `/elixir-load` | **Carrega à força TODO o corpo normativo** (DDD/arquitetura, clean code Elixir, segurança, dados, testes, operação, OTP/concorrência) no contexto e passa a aplicá-lo no projeto como regra inegociável. |
| `/elixir-claude` | Cria ou **atualiza (sobrescreve)** o `CLAUDE.md` da raiz com a versão atual da skill (backup se houver customização local). |
| `/elixir-cc` | Context compact: gera `context.md` + `checklist.md` em `<projeto>_archive/context/` e roda `/compact`. |
| `/elixir-handoff` | Gera o handoff (`context.md` + `checklist.md`) **sem** compactar — ideal pra fim de sessão ou troca de tarefa. |
| `/elixir-qa` | Fluxo de Q.A. plan-first (§22.9): planeja tudo, gera MD de passo a passo, pede aprovação, e roda faseado/assistido ou de uma vez (`mix test`). |
| `/elixir-review` | Roda o gate da Definition of Done e dos anti-padrões (§35, §37): `mix format`/Credo/Dialyzer, arquivo >750 linhas bloqueia / >300 úteis flag, função pública sem `@doc`/`@spec`, índice desatualizado, macaquices de segurança. |
| `/elixir-iam` | Força/audita/scaffolda o IAM da casa (identidade≠email, ≥2 fatores, ReBAC multi-tenant deny-default, sessão longa/logout irreversível) como microserviço Elixir separado em `auth.<domain>`, ou porta um auth legado (prioridade 0). |
| `/elixir-index` | (Re)gera o índice de microfunções (§39) a partir dos `@doc`/`@spec` das funções. |
| `/elixir-ops` | Audita/scaffolda o `<projeto>_ops` (interface única): fluxo de ambientes, instalação paralela (`nproc`), independência dos serviços, deploy via `mix release`. |

Depois da tabela, diga em uma linha que o detalhe normativo está na skill
`schematize-elixir` (referências em `references/`) e que o site é `skills.schematize.me/elixir`.
