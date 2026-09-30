# Índice Global da Aplicação — <projeto>

> **Fonte da verdade** do que existe e onde (§39). Consulte ANTES de criar algo
> (anti-duplicação). Atualizado no MESMO PR que muda funcionalidade.
> Local: `<projeto>_archive/index/INDEX_GLOBAL.md`. Última atualização: <data>.

## Repositórios / Serviços

| Repo/Serviço | Bounded context | O que faz (1 linha) | Linguagem | Owner |
|---|---|---|---|---|
| educe_catalog_ex | catalog | API de catálogo de cursos (Phoenix) | Elixir | squad-x |
| ... | ... | ... | ... | ... |

## Mapa de comunicação

> Quem chama quem; eventos publicados/consumidos; contratos.

| Origem | Destino | Como | Contrato |
|---|---|---|---|
| educe_catalog_ex | billing | evento `catalog.order.created` | Broadway/Kafka, v1 |
| ... | ... | ... | ... |

## Estrutura por repo

### <repo>
| Pasta top-level | Responsabilidade | Onde detalhar |
|---|---|---|
| `domain/` | entidades, value-objects, regras | INDEX_FUNCTIONS.md |
| `application/` | use-cases, dto | INDEX_FUNCTIONS.md |
| `infrastructure/` | persistência, mensageria, external | — |
| `interface/` | http, grpc, cli | OpenAPI |

## Links de verdade
- OpenAPI: `/docs/openapi.yaml`
- SLO: `/docs/slo.md`
- Runbook: `/docs/runbook.md`
- ADRs: `/docs/adr/`
