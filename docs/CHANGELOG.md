# Changelog

Este arquivo registra mudanças do contrato público e de formatos de estado. A versão pública declarada em `src/shared/CombatAPI.lua` permanece **CombatAPI 1**, enquanto `CombatAPI.SemVer` identifica a versão do pacote. A política SemVer e de depreciação está definida em [`PUBLIC_API.md`](PUBLIC_API.md); as versões de schema/manifest abaixo são versões internas dos respectivos formatos, não números de release.

## Não lançado

### Adicionado

- `CombatAPI.CombatActionDefinition` como export público tipado, com efeitos
  declarativos `GameplayEvents` limitados a frames e payloads serializáveis.
- `World:RegisterGameplayActionEventHandler` registra handlers separados dos
  eventos agendados, sem alterar o contrato preexistente do scheduler.
- O `CombatPipeline` valida handlers antes de registrar definições/catálogos e
  despacha eventos imutáveis na timeline; efeitos são reproduzidos ao atravessar
  novamente seus frames após rollback.
- `CombatActionCatalog` manifest v2 fixa eventos declarados e ainda aceita
  manifest v1 apenas para conteúdo sem eventos.
- Contratos Luau explícitos para perfil, dependências, implementação, estado, contexto e capacidade de plugins; os métodos de registro e ciclo de vida agora retornam `APIResult<PluginResolverResult>` em vez de `any`, e `CombatAPI` exporta `PluginCapability` e `PluginContext` para o fluxo do plugin.
- A superfície tipada de plugins agora inclui a vista de registry, assinaturas de callbacks de lifecycle/eventos e códigos de falha de capabilities.
- `PluginContext:GetEventBus()` e `APIContext:GetEvents()` agora usam o contrato público tipado de `EventBus`, incluindo operações de inscrição, dispatch, consulta de erros e teardown.
- `CombatAPITypesTest` verifica a construção, registro, consulta, início, capability, erros de registro, invalidação do contexto e limpeza de inscrição pela API pública.
- `APIContext:GetPlugin` agora retorna `InvalidArgument` para IDs vazios e `Destroyed` após o descarte do contexto, em vez de classificar esses casos como `NotFound`.
- O contrato de `PluginContext:Subscribe` explicita os códigos de erro locais (`InvalidContext` e `InvalidArgument`) além dos erros retornados pelo EventBus.
- Validação e comparação de versões de plugins e capabilities foram centralizadas em `Plugins/PluginVersion`; componentes numéricos são comparados sem arredondamento de ponto flutuante, e versões inválidas de capability retornam `InvalidCapabilityVersion`.
- Contratos Luau públicos ampliados para `CombatAPI`, `APIContext`, eventos,
  inscrições, opções de eventos e construtores de `Attack`/`AttackInstance`.
- `CombatAPI` e `APIContext` agora declaram assinaturas tipadas; os métodos de
  facade e a superfície pública dos construtores têm contratos explícitos.
- `CombatAPITypesTest` verifica a compatibilidade estrutural do facade com os
  tipos públicos e exercita os construtores tipados de ataque/instância.
- `CombatAPI.Simulation` é um construtor público tipado para inicializar a
  simulação do World antes de capturar ou restaurar snapshots.
- `CombatAPI.CollisionTopologyCatalog` é exportado e tipado para registrar
  fábricas versionadas necessárias à reconstrução de hitboxes/hurtboxes em
  snapshots não vazios.
- Os contratos públicos da `Simulation` agora descrevem as opções reais do
  construtor (RNG, buffer de comandos e scheduler determinístico), eventos
  agendados, ciclo de vida de snapshots e operações determinísticas.
- A análise Luau consultiva da CI inclui a fachada, os contratos públicos, os
  módulos de eventos e `OffensiveProperties`.
- Os módulos de evento e `OffensiveProperties` agora têm contratos Luau
  explícitos; filtros de inscrição aceitam opções tipadas e a fachada tipa o
  construtor de propriedades ofensivas.
- Documentação de importação dos tipos e exemplo tipado de `AttackOptions` e
  `AttackInstanceOptions`.

### Limites

- Os getters de resolvers continuam tipados como `any` intencionalmente, pois
  são pontos avançados de escape e os contratos concretos dos resolvers ainda
  não foram estabilizados. Isso não representa tipagem estrita completa de
  toda a implementação.
- A análise `luau-lsp` desta alteração ainda precisa ser executada na CI e
  revisada; testes de runtime no Roblox Studio também permanecem pendentes para
  esta revisão.
- Os handlers de eventos de ações continuam sendo código do jogo e precisam
  obedecer às regras de determinismo e rollback documentadas.


### Corrigido

- O consumidor de referência de `CustomData` anexava `Hitbox` como componente genérico da entidade, embora o estado rollback da hitbox seja gerenciado por `CollisionWorld`. O exemplo agora registra a região diretamente no `CollisionWorld`; `CombatPublicSurfaceTest` cobre a captura/restauração do override e da geometria pela superfície pública.
- `CombatPublicSurfaceTest` capturava o snapshot sem inicializar uma `Simulation`; o teste e o exemplo agora criam `CombatAPI.Simulation` pelo facade público antes de usar snapshots.
- A restauração do snapshot público falhava porque havia geometria registrada sem um `CollisionTopologyCatalog`. O teste e o exemplo agora registram uma fábrica versionada, atribuem os metadados da topologia à hitbox e associam o catálogo ao `CollisionWorld`.

### Alterado

- O pacote avança para `0.2.0` em `CombatAPI.SemVer` e `wally.toml`, refletindo
  a adição compatível do construtor público e da timeline declarativa.

- Falhas de plugin retornadas por `CombatAPI.RegisterPlugin`, `StartPlugin`, `StopPlugin`, `UnregisterPlugin`, `EnablePlugin` e `DisablePlugin`, e pelos métodos equivalentes de `APIContext`, passam a usar um `APIError.Code` específico (`NotFound`, `AlreadyExists`, `InvalidArgument`, `PermissionDenied`, `Disabled`, `Destroyed`, `InternalError` ou `InvalidOperation`) em vez de sempre `InvalidOperation`. O código original do resolver continua em `Error.Context.ResolverCode` e `Error.Message` mantém o mesmo valor. A tabela completa está em [`PUBLIC_API.md`](PUBLIC_API.md).
- A conversão de resultado de resolver em `APIError` passa a viver em um único módulo, `Events/ResolverErrorMap`, usado por `CombatAPI` e `APIContext` (antes havia duas cópias).

### Corrigido

- Os métodos `CombatAPI.*Plugin` não preenchiam `Error.Context.ResolverCode`, embora `PUBLIC_API.md` afirmasse isso; apenas `APIContext` o fazia.

### Compatibilidade

- Consumidores que comparavam `Error.Code == "InvalidOperation"` para qualquer falha de plugin precisam ramificar pelo novo código ou por `Context.ResolverCode`. A mudança é permitida antes de 1.0.0 (ver `PUBLIC_API.md`); a versão de pacote registrada nesta atualização é `0.2.0`.
- Códigos de resolver desconhecidos continuam mapeados para `InvalidOperation`.
- Cobertura: `CombatPluginErrorMappingTest` (falhas reais do resolver pelo facade e pelo `APIContext`).

## CombatAPI 1 — suporte a `CustomData` em ataques (2026-11-11)

### Adicionado

- `CustomData` opcional em `Attack` e `OffensiveProperties`, com cópia defensiva, validação de dados serializáveis, limite de 256 entradas/profundidade 8, normalização de tabela vazia para `nil` e congelamento recursivo.
- `CustomDataOverrides` por `AttackInstance`, recebido como tabela de opções no quarto argumento; merge raso preserva a definição original. Chamadas legadas com ID escalar explícito continuam suportadas.
- Propagação de `CustomData` no fallback de propriedades do hitbox e nos payloads públicos `HitConfirmed` e `DamageApplied`.
- Captura de overrides nos snapshots de colisão; restauração in-place reaplica o override salvo e a restauração por reconstrução cria a instância com o mesmo override.
- Verificação do conteúdo das definições pelo manifest do catálogo.
- Migração do `CombatStateSchema` v2 para v3; a nova versão evita que consumidores antigos ignorem silenciosamente overrides.
- Contratos em [`API.md`](API.md), [`Rollback.md`](Rollback.md), [`Conventions.md`](Conventions.md) e [`CUSTOMDATA.md`](CUSTOMDATA.md).

### Alterado

- Os limites de `CustomData` (256 entradas, profundidade 8) passam a ter uma única definição, `OffensiveProperties.CustomDataLimits`, usada por propriedades, instância, catálogo e validação de snapshot; `OffensiveProperties.NormalizeCustomData` centraliza a normalização reutilizada por `AttackInstance`. Sem mudança de comportamento.

### Corrigido

- `AttackCatalog:Register` rejeitava `CustomData` com 128 a 255 chaves planas (aceito por `Attack.new`) porque o canônico do manifest era serializado com o mesmo limite usado na validação, mas o serializador conta chaves e valores enquanto a validação conta só valores. O canônico passa a usar `OffensiveProperties.CanonicalizeCustomData`, com limite de entradas dobrado. A documentação do limite foi esclarecida: 256 valores, contando a tabela raiz (até 255 chaves em uma tabela plana).

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
- Package installation in a separate consumer place and the two-client multiplayer smoke test remain pending; the 61-module automated Studio suite passed.


## Infraestrutura de testes — runner sequencial

### Alterado

- Os testes automatizados em `*Test.server.lua` foram migrados para módulos `*Test.lua` com função de execução.
- `CombatTestRunner.server.lua` executa os módulos em ordem alfabética, captura falhas, aplica timeout por teste e interrompe a suíte em caso de timeout.
- O runner evita execução duplicada por sessão e executa apenas um módulo por nome quando o place contém cópias repetidas; o teste de rollback de colisão usa uma entidade distinta para a segunda hitbox.
- O smoke multiplayer continua separado, pois depende de dois clientes conectados.

### Limites

- A primeira execução completa no Roblox Studio passou nos 61 módulos automatizados; o smoke multiplayer ainda não foi concluído com dois clientes.
- O place de teste contém cópias duplicadas dos módulos; o runner deduplica por nome e impede uma segunda inicialização.
- O Output dessa execução também registrou duas falhas de carregamento do asset `rbxassetid://203785492`.
- A CI valida inventário/build, mas não afirma que testes Roblox de runtime passaram.
