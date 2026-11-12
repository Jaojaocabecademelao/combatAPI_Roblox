# Changelog

Este arquivo registra mudanças do contrato público e de formatos de estado. A versão pública declarada em `src/shared/CombatAPI.lua` permanece **CombatAPI 1**; a política de SemVer/depreciação está em [`PUBLIC_API.md`](PUBLIC_API.md). As versões de schema/manifest são internas aos respectivos formatos, independentes da versão SemVer do pacote.

## 0.3.0 — Catálogo público de topologia para rollback (2026-11-11)

### Adicionado

- Export de `CollisionTopologyCatalog` em `CombatAPI`, para registrar fábricas versionadas e reconstruir regiões em snapshots com topologia não vazia.
- O teste e o exemplo consumidor usam o catálogo público para restaurar o World e reacquire a Hitbox recriada.
- Documentação da necessidade de factories versionadas ao restaurar snapshots com regiões de colisão.
- Tipos públicos Luau ampliados com construtores para consumidores, catálogo de ataques, opções de região, snapshots/fábricas de topologia e operações do `CollisionWorld`. O contrato representa IDs opcionais antes do registro e IDs garantidos depois do registro.
- Tipos compartilhados ampliados com contratos de eventos, `APIContext`, `APIResult`, `APIError` e da fachada `CombatAPI`.
- Falhas do PluginResolver agora são mapeadas para categorias estáveis de `APIError.Code`, preservando o código específico e detalhes em `Error.Context`.

### Limites

- O usuário confirmou sem erros a suíte atual de 62 módulos, incluindo as verificações de superfície pública; o log final não foi anexado e a análise Luau segue pendente.
- Os testes do novo mapeamento de erro foram adicionados após a confirmação da suíte e ainda precisam de execução no Studio.

## 0.2.0 — Simulation pública para consumidores (2026-11-11)

### Adicionado

- Export de `Simulation` em `CombatAPI`, para que consumidores possam inicializar o pipeline público antes de capturar/restaurar estado de combate.
- Exemplo e teste consumidor atualizados para criar uma Simulation usando apenas o facade público.
- `CombatPublicSurfaceTest` agora verifica a construção e associação de uma Simulation ao World.

### Limites

- A nova superfície e o consumidor ainda precisam ser executados no Roblox Studio; a execução anterior cobriu 61 módulos, antes da adição do teste consumidor.

## CombatAPI 1 — suporte a `CustomData` em ataques (2026-11-11)

### Adicionado

- `CustomData` opcional em `Attack` e `OffensiveProperties`, com cópia defensiva, validação de dados serializáveis, limite de 256 entradas/profundidade 8, normalização de tabela vazia para `nil` e congelamento recursivo.
- `CustomDataOverrides` por `AttackInstance`, recebido como tabela de opções no quarto argumento; merge raso preserva a definição original. Chamadas legadas com ID escalar explícito continuam suportadas.
- Propagação de `CustomData` no fallback de propriedades do hitbox e nos payloads públicos `HitConfirmed` e `DamageApplied`.
- Captura de overrides nos snapshots de colisão; restauração in-place reaplica o override salvo e a restauração por reconstrução cria a instância com o mesmo override.
- Verificação do conteúdo das definições pelo manifest do catálogo.
- Migração do `CombatStateSchema` v2 para v3; a nova versão evita que consumidores antigos ignorem silenciosamente overrides.
- Contratos em [`API.md`](API.md), [`Rollback.md`](Rollback.md), [`Conventions.md`](Conventions.md) e [`CUSTOMDATA.md`](CUSTOMDATA.md).

### Compatibilidade

- Manifest do `AttackCatalog` passa da versão 1 para 2. Manifest v1 permanece aceito somente quando as definições atuais não usam `CustomData`.
- Hashes/snapshots sem overrides mantêm o campo de override omitido.
- A cobertura inclui testes focados de validação/merge, manifest v2, migração de schema, rollback in-place e comparação de replay/hash com overrides derivados de frames. A execução da suíte completa e do benchmark em runtime Roblox/Studio não foi realizada neste ambiente; esta entrada não afirma validação de ponta a ponta.


## CombatAPI 0.1.0 — superfície pública e infraestrutura (2026-11-11)

### Adicionado

- Exports públicos para `Attack`, `AttackInstance`, `AttackCatalog`, `CollisionWorld`, `Hitbox`, `Hurtbox` e `OffensiveProperties`, permitindo consumir o fluxo de `CustomData` sem exigir `require` direto de módulos internos.
- `CombatAPI.SemVer` e versões declaradas de `AttackCatalogManifest` e `CombatStateSchema` em `CombatAPI.Contracts`, mantendo `CombatAPI.Version` numérico por compatibilidade.
- Módulo de tipos Luau `CombatAPITypes` para `CustomData`, opções de ataque, `APIResult`, `APIError` e World.
- Exemplo de consumidor público em `docs/examples/CustomDataConsumer.server.lua` e teste de superfície pública.
- Política de fronteira pública, SemVer e depreciação em `docs/PUBLIC_API.md`; guia de contribuição e workflow de build Rojo no GitHub Actions.

### Limites

- O exemplo e o novo teste ainda precisam ser executados no Roblox Studio.
- CI valida JSON e build Rojo; não executa scripts `*Test.server.lua` nem substitui testes de runtime.
- Publicação Wally e análise estática Luau ficam adiadas até confirmar a estrutura de pacote e escolher/padronizar um linter/analisador.


## 0.1.1 — Public contract hardening

- Added strict Luau type exports for attacks, instances, offensive properties,
  serializable custom data, API errors, API results, and World.
- Added a stable `APIError.Code` union and `APIError.isCode`.
- Hardened `APIError.new` argument validation and froze the code registry and
  error records.
- Added `APIResult.is` and enforced the success/error invariant.
- Added `CombatAPIPublicContractTest.server.lua`.


## 0.1.2 — CI validation tooling (2026-11-11)

### Added

- Pinned `luau-lsp` in Aftman and introduced advisory analysis for the strict
  public-contract modules.
- GitHub Actions now uploads the Rojo-built place as a seven-day artifact for
  manual Roblox Studio validation.

### Notes

- Luau analysis remains advisory until its diagnostics are reviewed and a
  stable baseline is established. The workflow does not execute Roblox runtime
  tests and does not claim that the Studio suite passed.


## 0.1.3 — Test evidence and diagnostics (2026-11-11)

### Added

- Added `scripts/create_test_report.py`, which creates a Studio execution report
  containing every automated `*Test.lua` module, the manual smoke test, and
  benchmark fields.
- The Studio validation artifact now includes the generated report template.
- The Luau analysis job preserves its full output and exit code as a separate
  artifact instead of discarding advisory diagnostics.

### Changed

- Removed the manually downloaded global type definitions from the analysis job;
  `luau-lsp` provides Roblox definitions for Rojo projects by default.
- Bumped the package development baseline to `0.1.3`.

### Limits

- CI still does not execute Roblox runtime tests. The report is a blank evidence
  template, not proof that any test passed.
- Luau analysis remains advisory until its output is reviewed and a baseline is
  established.


## 0.1.4 — Wally package preview (2026-11-11)

### Added

- Added a Wally manifest and package entrypoint exposing the existing public facade.
- Restricted the shared package preview to `/src/init.lua` and `/src/shared/**`, excluding server tests.
- Added a manifest/entrypoint consistency check and a CI package-preview artifact.

### Limits

- The Wally package remains private and has not been published.
- Package installation in a separate consumer place and the two-client multiplayer smoke test remain pending. The 61-module Studio suite passed before the new public consumer test was added; run all 62 current modules in Studio for complete evidence.


## Infraestrutura de testes — runner sequencial

### Alterado

- Os testes automatizados em `*Test.server.lua` foram migrados para módulos `*Test.lua` com função de execução.
- `CombatTestRunner.server.lua` executa os módulos em ordem alfabética, captura falhas, aplica timeout por teste e interrompe a suíte em caso de timeout.
- O runner evita execução duplicada por sessão e executa apenas um módulo por nome quando o place contém cópias repetidas; o teste de rollback de colisão usa uma entidade distinta para a segunda hitbox.
- O smoke multiplayer continua separado, pois depende de dois clientes conectados.
- `CombatCustomDataConsumerTest.lua` exercita o consumidor de referência através somente do facade público, incluindo rollback/replay e gravação serializada.
- A referência de SemVer de `API.md` foi alinhada ao pacote `0.1.4`; `Conventions.md` aponta para a política de compatibilidade documentada.

### Limites

- A primeira execução completa no Roblox Studio passou nos 61 módulos automatizados; o smoke multiplayer ainda não foi concluído com dois clientes.
- O place de teste contém cópias duplicadas dos módulos; o runner deduplica por nome e impede uma segunda inicialização.
- O Output dessa execução também registrou duas falhas de carregamento do asset `rbxassetid://203785492`.
- A CI valida inventário/build, mas não afirma que testes Roblox de runtime passaram.
