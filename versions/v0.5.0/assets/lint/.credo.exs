# schematize-elixir — config do Credo (linter) da casa.
# Copie para .credo.exs na raiz do projeto Elixir. Rode com `mix credo --strict`.
# Ver references/padroes-codigo.md (limites/idiomas) e references/arquitetura.md (§4 camadas).
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "src/", "test/", "apps/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      # `strict: true` — no gate, Credo roda em modo estrito e ofensa nova bloqueia (§35).
      strict: true,
      checks: %{
        enabled: [
          # §6 / padroes-codigo: complexidade e tamanho.
          {Credo.Check.Refactor.CyclomaticComplexity, [max_complexity: 15]},
          {Credo.Check.Refactor.LongQuoteBlocks, []},
          {Credo.Check.Refactor.Nesting, [max_nesting: 3]},
          {Credo.Check.Refactor.FunctionArity, [max_arity: 5]},
          # Idiomas Elixir (padroes-codigo §5): pipe, with, sem case aninhado profundo.
          {Credo.Check.Refactor.PipeChainStart, []},
          {Credo.Check.Refactor.WithClauses, []},
          # Segurança / anti-padrões (§37): evitar armadilhas comuns.
          {Credo.Check.Warning.UnusedEnumOperation, []},
          {Credo.Check.Warning.UnusedStringOperation, []},
          {Credo.Check.Warning.RaiseInsideRescue, []},
          {Credo.Check.Warning.Dbg, []},
          {Credo.Check.Warning.IoInspect, []},
          # `@doc`/`@spec` alimentam o índice (§39). Docs em módulo público são exigidas.
          {Credo.Check.Readability.ModuleDoc, []},
          {Credo.Check.Readability.Specs, [included: ["lib/"]]}
        ],
        disabled: []
      }
    }
  ]
}
