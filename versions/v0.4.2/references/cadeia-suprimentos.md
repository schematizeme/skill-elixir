# Cadeia de Suprimentos de Software (supply chain)

> Piso de **segurança da cadeia de suprimentos** especializado para **Elixir/Mix/Hex** —
> consolida num só lugar o que antes ficava espalhado (higiene de dependência em
> `seguranca.md`, imagem/deploy em `operacao.md`/`ops.md`). O ataque hoje raramente é
> no seu código: é numa dependência do Hex, numa imagem base ou no pipeline. Trate build
> e dependências como superfície de ataque de primeira classe. Versões pinadas do runtime
> (Erlang/OTP + Elixir) em `references/stack-versoes.md`.

## Índice
- S1. Dependências (Hex + mix.lock)
- S2. SBOM e vulnerabilidades
- S3. Imagem de container (release OTP)
- S4. Pipeline e proveniência (SLSA)
- S5. Segredos no build

---

## S1. Dependências (Hex + mix.lock)

**MUST**
- **`mix.lock` commitado — o lockfile é piso.** O build de produção resolve **a partir do lock**, não re-resolve versões. `mix.exs` declara requisitos; `mix.lock` fixa a árvore exata **com hash de cada pacote** (o Hex grava o checksum no lock — é a defesa contra pacote adulterado no espelho). Sem range frouxo (`>= 0.0.0`, `~> 1.0` largo demais) em dependência sensível; prefira `~> x.y` fechado.
- **Verificar nome e licença de toda dependência nova do Hex.** **Typosquatting de pacote Hex é real** — nome quase igual ao popular (`plug` vs `p1ug`, `poison` vs `poizon`). Confira o pacote no hex.pm: dono, downloads, repositório de origem, atividade. Dependência de git (`github:`) só com **`ref:` fixo num commit SHA**, nunca por branch (`branch: "main"`). Licença na allowlist (MIT/Apache-2.0/BSD/MPL-2.0/ISC ok; GPL/AGPL/SSPL/proprietária só com ADR).
- **`mix deps.unlock --check-unused` no CI** — trava entrada órfã no `mix.lock` (dependência que saiu do `mix.exs` mas ficou fixada no lock). Lock sujo é código morto que ainda é superfície de ataque.
- **Minimizar superfície:** menos dependência transitiva é menos risco. `mix deps.tree` para ver o que cada lib arrasta; avalie peso e manutenção antes de adicionar; corte o que não usa. Cuidado com lib que puxa NIF/porta (código nativo) — amplia o blast radius para fora da BEAM.

**SHOULD**
- `mix hex.outdated` na rotina para não acumular defasagem (patch de segurança perdido é dívida).
- Atualização automatizada (Dependabot/Renovate suportam `mix`) com CI verde como gate.
- Espelho/proxy de Hex (self-hosted) para build crítico não depender de `repo.hex.pm` no ar; `HEX_MIRROR`/repo privado para pacote interno.

**VETADO**
- Instalar de fonte não confiável / `curl | sh` de origem não verificada no build.
- Fixar dependência por branch (`main`/`master`) em produção — sempre `ref:` SHA.
- `mix deps.get` num build de produção que **re-resolve e reescreve** o lock. O lock é fonte da verdade; o build o **respeita**, não o regenera.

---

## S2. SBOM e vulnerabilidades

**MUST**
- **`mix hex.audit` no CI, travando o merge.** Detecta dependência **retirada (retired)** do Hex — pacote que o autor marcou como inseguro/depreciado/inválido. Pacote retirado em produção é alerta vermelho: corrige ou registra ADR de aceite com prazo.
- **Scan de vulnerabilidade que TRAVA o CI** em `high`/`critical` sem ADR: **`mix deps.audit`** (do `mix_audit`, cruza o `mix.lock` com advisories do ecossistema Elixir/Erlang) como gate obrigatório. `sobelow` para varredura estática de segurança de app Phoenix (SQLi via `fragment`, XSS, CSRF, config insegura) também travando. Scan **também na imagem** (`grype`/`trivy`) para pegar CVE do OTP/OpenSSL da base.
- **Gerar SBOM** (CycloneDX/SPDX) no build e **versioná-lo junto ao artefato** — inventário do que foi de fato embarcado. `sbom` (mix task CycloneDX para Elixir) a partir do `mix.lock`, ou `syft` sobre a release. **A SBOM inclui as apps OTP/Erlang embarcadas na release, não só as deps Hex** — o `mix release` empacota o ERTS e apps do OTP; elas entram no inventário.
- Vulnerabilidade aceita conscientemente vira **ADR com prazo de correção**, não silêncio.

**SHOULD**
- Rodar `sobelow --config` versionado no repo, com exceções justificadas (não desligado global).
- `mix hex.outdated --within-requirements` para ver o que dá pra atualizar sem quebrar requisito.

**Gates de CI da cadeia (todos travam o merge):**

| Comando | Trava em |
|---|---|
| `mix deps.get --check-locked` | lock divergente do `mix.exs` (build não re-resolve) |
| `mix deps.unlock --check-unused` | entrada órfã no `mix.lock` |
| `mix hex.audit` | dependência retirada (retired) do Hex |
| `mix deps.audit` (`mix_audit`) | advisory conhecido em dep no lock |
| `sobelow --exit` | vuln estática de app Phoenix (SQLi/XSS/CSRF/config) |
| `grype`/`trivy` na imagem | CVE de OTP/OpenSSL/base |
| `gitleaks`/`trufflehog` | segredo no diff |

---

## S3. Imagem de container (release OTP)

**MUST**
- **Multi-stage com `mix release`.** Estágio de build (imagem `hexpm/elixir:<ver>-erlang-<ver>-<os>` **pinada por digest**) compila e roda `MIX_ENV=prod mix release`; a imagem final carrega **só a release** (binário + ERTS + apps compiladas + shell scripts), sem Mix, sem Hex, sem toolchain, sem código-fonte. `mix release` com `include_erts: true` permite base runtime sem Erlang instalado.
- **Base mínima e pinada por digest** (`@sha256:...`), não por tag móvel (`latest`/`1.16`). Alvo: **distroless** ou **alpine** para a imagem final; menos pacote, menos CVE. Com `include_erts: true`, dá para chegar a base bem enxuta (só libc/openssl). Atenção: musl (alpine) vs glibc — casar a base de build e de runtime para NIF não quebrar.
- **Não-root, filesystem read-only**, sem capabilities desnecessárias (liga com o piso de container do `ops`/segurança). A release roda como user dedicado (casa com o isolamento por usuário do `references/ops.md`).
- ERTS e OpenSSL da imagem **pinados e escaneados** — CVE de OTP/OpenSSL é CVE seu.

**Multi-stage de referência (base pinada por digest, final não-root):**

```dockerfile
# --- build ---
FROM hexpm/elixir:1.16.2-erlang-26.2.5-debian-bookworm-20240513@sha256:<digest> AS build
ENV MIX_ENV=prod
WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod        # respeita o lock, não re-resolve
COPY config config
RUN mix deps.compile
COPY lib lib
COPY priv priv
RUN mix release                     # gera _build/prod/rel/my_app

# --- runtime (mínima, sem toolchain) ---
FROM gcr.io/distroless/base-debian12@sha256:<digest> AS app
WORKDIR /app
USER 65532:65532                    # nonroot, nunca root
COPY --from=build --chown=65532:65532 /app/_build/prod/rel/my_app ./
ENTRYPOINT ["/app/bin/my_app"]
CMD ["start"]
```

**SHOULD**
- Rebuild periódico para absorver patch da base (nova OTP/OpenSSL); rescan da imagem publicada.
- `RELEASE_COOKIE` **não** hardcoded na imagem — vem de segredo em runtime (cookie fraco/exposto = RCE via distribuição Erlang).

---

## S4. Pipeline e proveniência (SLSA)

**MUST**
- **Build só no CI** (não na máquina do dev para produção), a partir do código versionado; o pipeline é parte da TCB (base de confiança). `mix release` roda no CI, com `mix.lock` do commit.
- **Assinar o artefato/imagem** (cosign/sigstore) e **verificar a assinatura na admissão** (deploy só aceita imagem assinada por pipeline confiável). Assinar sem verificar não protege.
- **Proveniência:** emitir atestação de build (quem buildou, de qual commit, com qual SBOM) — alvo **SLSA** crescente. Tag da imagem inclui o commit SHA; a release carrega a versão + commit (`Application.spec/2` expõe versão).

**SHOULD**
- Permissões mínimas no CI (token escopado, sem segredo amplo); branch protegida e review obrigatório antes de buildar release.
- Cache de `deps`/`_build` no CI **chaveado pelo hash do `mix.lock`** — cache envenenado por chave frouxa contamina o build.

---

## S5. Segredos no build

**MUST**
- **Nenhum segredo no artefato/imagem** nem em layer intermediária (layer é inspecionável). Segredo de build via mecanismo efêmero (BuildKit secret mount), nunca `ARG`/`ENV` persistido nem `COPY .env`.
- **Config em runtime, não em compile-time.** Em Elixir a armadilha clássica: `config/config.exs` e `config/prod.exs` são **avaliados em COMPILE-TIME** e **congelam no artefato** — segredo lido ali via `System.get_env/1` na compilação vira valor embutido na release, inspecionável. Segredo e config de ambiente vão em **`config/runtime.exs`**, avaliado no **boot** da release, lendo `System.fetch_env!/1`. Regra: `runtime.exs` para tudo que muda por ambiente ou é sensível.

```elixir
# config/runtime.exs — avaliado no BOOT da release, nunca embarcado
import Config

if config_env() == :prod do
  config :my_app, MyApp.Repo,
    url: System.fetch_env!("DATABASE_URL"),      # falha alto se faltar
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))

  config :my_app, MyAppWeb.Endpoint,
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE")

  config :my_app, :release_cookie, System.fetch_env!("RELEASE_COOKIE")
end
```

> `fetch_env!` (não `get_env`) para segredo obrigatório: o boot **falha ruidosamente** se a variável faltar, em vez de subir inseguro/quebrado. O seed global do `references/ops.md` popula essas variáveis; o segredo real vem do secret manager referenciado pelo seed, nunca versionado.
- **Secret scan no pipeline** (gitleaks/trufflehog) travando vazamento antes do merge. `.env` real fora do git.

> Regra de bolso: **você entrega tudo que embarca.** `mix.lock` verificado + `mix hex.audit`/`mix deps.audit`/`sobelow` que travam + SBOM (deps Hex **e** apps OTP) + imagem mínima/pinada/assinada com `mix release` + config sensível só em `runtime.exs` + build no CI sem segredo no layer. Se não dá para dizer exatamente o que tem dentro da release e quem a produziu, a cadeia está aberta.

---

Cross-links: piso agnóstico em `schematize-engineering`; teste adversarial de dependência/build e abuso de pipeline em `schematize-pentest`; operação da imagem/release e redeploy em `references/ops.md`; runtime pinado em `references/stack-versoes.md`.
