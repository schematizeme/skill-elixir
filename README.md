# schematize-elixir

> Padrões normativos de engenharia da casa especializados para **Elixir** (Phoenix/Ecto/OTP sobre a BEAM) — arquitetura, concorrência/OTP, segurança, IAM, testes/pentest, dados, observabilidade, deploy e archive. Base agnóstica na `schematize-engineering`; frontend delega à `schematize-web`; teste de segurança na `schematize-pentest`.

Pacote de **skill normativa para [Claude Code](https://claude.com/claude-code)**.
Parte do catálogo **schematize skills** ([skills.schematize.me](https://skills.schematize.me)).

## Instalar

### Última versão (recomendado)

A partir de um clone do repositório:

```bash
git clone https://github.com/schematizeme/skill-elixir.git
cd skill-elixir && ./install.sh            # instala no projeto atual (diretório corrente)
# ./install.sh /caminho/do/projeto          # ou aponte para outro projeto
```

Ou baixe o `.zip` da última release e descompacte direto em `.claude/skills/`:

```bash
curl -L -o schematize-elixir.zip \
  https://github.com/schematizeme/skill-elixir/releases/latest/download/skill-elixir.zip
unzip schematize-elixir.zip -d .claude/skills/
```

### Uma versão específica

Cada versão tem três formas de obter: **(1)** um Release com `.zip` para baixar,
**(2)** uma pasta navegável em `versions/`, e **(3)** uma tag git.

| Versão | Data | Download (.zip) | Pasta navegável | Notas |
|---|---|---|---|---|
| **0.1.0** | 2026-08-15 | [release](https://github.com/schematizeme/skill-elixir/releases/download/v0.1.0/skill-elixir.zip) | [versions/v0.1.0/](versions/v0.1.0) | [CHANGELOG](CHANGELOG.md) |

```bash
# clonar uma versão exata pela tag:
git clone --branch v0.1.0 https://github.com/schematizeme/skill-elixir.git
```

> Todas as versões aparecem na página de **[Releases](https://github.com/schematizeme/skill-elixir/releases)**.

## Comandos

Todos prefixados por `elixir-` — **sem conflito** com as outras skills na mesma máquina.

| Comando | O que faz |
|---|---|
| `/elixir-help` | lista todos os comandos do schematize-elixir |
| `/elixir-cc` | context compact: gera context.md + checklist.md no archive e roda `/compact` |
| `/elixir-handoff` | gera o handoff (context.md + checklist.md) **sem** compactar |
| `/elixir-claude` | cria/atualiza o `CLAUDE.md` da raiz com a versão atual da skill |
| `/elixir-qa` | Q.A. plan-first: planeja, gera MD, pede aprovação, roda |
| `/elixir-review` | gate da DoD/§37 no diff (`mix format`, Credo, Dialyzer, limites, índice) |
| `/elixir-iam` | força/audita/scaffolda o IAM como microserviço Elixir separado em `auth.<domain>` |
| `/elixir-index` | (re)gera o índice de microfunções (§39) a partir dos `@doc`/`@spec` |
| `/elixir-ops` | audita/scaffolda o `<projeto>_ops` (interface única, `nproc`, independência) |
| `/elixir-load` | carrega à força TODO o corpo normativo e passa a aplicá-lo |

Digite `/elixir-help` dentro do Claude Code para ver a lista completa.

## Conteúdo da skill

- `SKILL.md` — porta de entrada e pisos inegociáveis.
- `references/` — corpo normativo fatiado por domínio (16 arquivos): `arquitetura.md`, `concorrencia.md`, `padroes-codigo.md`, `dados-eventos.md`, `seguranca.md`, `iam.md`, `cadeia-suprimentos.md`, `stack-versoes.md`, `testes.md`, `testes-execucao.md`, `observabilidade.md`, `operacao.md`, `ops.md`, `entrega.md`, `anti-padroes.md`, `contexto-claude-code.md`.
- `assets/` — templates (ADR/TASK/RUNBOOK/…), comandos, `CLAUDE.md`, CI, lint, hooks.
- `scripts/` — andaime de testes, índice e gestão de contexto.
- `skill.toml` — manifesto da skill (slug, nome, versão, descrições).

## Relação com a base e as skills irmãs

- [schematize-engineering](https://github.com/schematizeme/skill-engineering) — **a base agnóstica**: os pisos (segurança, IAM, testes, ops, observabilidade, archive/DoD/índice) são os mesmos em toda linguagem. Esta skill **especializa** a base para Elixir (mix/Hex, Phoenix/Ecto/OTP, ExUnit, Credo/Dialyzer, `mix release`) sem afrouxar o piso.
- [skill-go](https://github.com/schematizeme/skill-go) · [skill-rust](https://github.com/schematizeme/skill-rust) — outras linguagens do rol sancionado de backend.
- [skill-web](https://github.com/schematizeme/skill-web) — frontend / SEO / performance (a UI delega pra cá).
- [skill-pentest](https://github.com/schematizeme/skill-pentest) — teste de segurança (cross-tenant/priv-esc/AppSec).

Todas podem ficar habilitadas ao mesmo tempo: os comandos são namespaced por skill
(`elixir-*`, `go-*`, `rust-*`, `web-*`, `eng-*`, `pentest-*`).

## Licença

[MIT](LICENSE) © 2026 schematizeme.
