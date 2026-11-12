# Status da implementação — CustomData

Data da revisão: 2026-11-12

Este relatório acompanha o plano `combatapi-customdata-plano.md`. Ele distingue a
presença estática de código/testes da aprovação em runtime. Nenhuma fase que
depende da execução no Roblox Studio é marcada como integralmente aprovada sem
os resultados dessa execução.

| Fase | Estado nesta revisão | Evidência / pendência |
|---|---|---|
| 0 — Preparação | Parcial | Os contratos e migrações estão na árvore ativa e a suíte foi executada no Studio. Há uma medição registrada abaixo, mas não existe benchmark pré-CustomData comparável; a linha de base de performance ainda está pendente. |
| 1 — Núcleo do dado | Testes de runtime passaram | `CombatAttackCustomDataTest` e os demais módulos passaram na execução Studio de 2026-11-11. |
| 2 — Instância e acerto | Testes de runtime passaram | A suíte Studio completa passou; inclui validação de propriedades e fallback do hit processor. |
| 3 e 4 — Catálogo, snapshot e schema | Testes de runtime passaram | A suíte Studio completa passou, incluindo catálogo, migração, rollback de colisão e rebuild de topologia. |
| 5 — Eventos públicos | Testes de runtime passaram | A suíte Studio completa passou; `CombatEventAPITest` está incluído nos 61 módulos aprovados. |
| 6 — Determinismo, replay e performance | Replay passou; benchmark medido sem baseline comparável | `CombatCustomDataReplayTest` passou. O benchmark coletou tempos e tamanho de snapshot com/sem overrides; ainda não há medição pré-CustomData para avaliar regressão. |
| 7 — Documentação e changelog | Testes de runtime passaram | A suíte Studio completa passou, incluindo `CombatDocumentationTest` e `CombatDocumentationExamplesTest`. |

## Verificações estáticas realizadas

- O inventário documentado contém exatamente os módulos automatizados `*Test.lua`; o smoke multiplayer permanece registrado separadamente como Script.
- Os pontos centrais de `CustomData` estão presentes: normalização, merge raso,
  fallback do `HitProcessor`, manifest v2, migração do schema v3, snapshots e
  encaminhamento aos eventos públicos.
- O teste novo de replay está incluído no inventário de documentação.

## Última execução no Roblox Studio — 2026-11-11

- `CombatTestRunner: PASS (61 tests)`; 61 resultados `TEST PASS` distintos e
  nenhum `TEST FAIL`. A lista incluiu `CombatDocumentationTest`,
  `CombatDocumentationExamplesTest`, `CombatCustomDataReplayTest` e
  `CombatAPIPublicContractTest`.
- O place continha duas cópias de cada módulo automatizado. O runner emitiu 61
  avisos de duplicação e executou uma cópia por nome. Uma segunda inicialização
  do runner foi bloqueada como esperado. A causa da duplicação no place não foi
  identificada nesta revisão.
- O Output também registrou duas falhas ao carregar
  `rbxassetid://203785492` por incompatibilidade de tipo do asset; não são
  resultados de `TEST FAIL`, mas impedem considerar o Output inteiro sem erros.
- O smoke multiplayer registrou zero clientes no início e apenas um cliente
  conectado; não há resultado de conclusão. Ele continua pendente até ser
  executado com dois clientes.

Benchmark reportado com `entities=32`, `volumes=64`, `attackInstances=32`,
`frames=30`, `repetitions=3`:

| Métrica | Resultado |
|---|---:|
| Snapshot com overrides | 52 305 bytes |
| Snapshot sem overrides | 51 253 bytes |
| Bytes atribuídos aos overrides | 1 052 (16 overrides) |
| Captura (média) | 0,001735 s |
| Serialização (média) | 0,000445 s |
| Validação de colisão (média) | 0,000289 s |
| Preparação/restauração (média) | 0,000417 s |
| Step (média) | 0,034920 s |
| Restore/replay (média) | 0,043680 s |

Uma execução anterior no mesmo log de trabalho usou a mesma configuração, mas
também não é uma linha de base pré-CustomData. Diferenças pequenas de tempo entre
essas duas execuções não são suficientes para concluir regressão ou ganho.

## Pendências para fechar as fases

A suíte automatizada já passou no Roblox Studio. Para fechar a validação geral,
investigar a duplicação no place e os avisos de asset, executar
`CombatMultiplayerSmokeTest.server.lua` com dois clientes e obter uma linha de
base pré-CustomData do `CombatStabilizationBenchmark.server.lua` com os mesmos
atributos e ambiente.


## Continuação do roadmap (Etapas A a C)

| Etapa | Estado | Evidência / pendência |
|---|---|---|
| A — Consumidor de referência | Parcial, exemplo revisado e regressão adicionada | `docs/examples/CustomDataConsumer.server.lua` usa exports públicos para definir ataque, override, catálogo, hitbox e snapshot/restore. A revisão encontrou e corrigiu o uso incorreto de `owner:AddComponent(hitbox)`: `Hitbox` é estado de `CollisionWorld`, não um componente genérico com contrato próprio de snapshot. O exemplo agora usa `CollisionWorld:RegisterHitbox`; `CombatPublicSurfaceTest` cobre captura/restauração pública de override e geometria. Ainda precisa ser executado em Studio como script independente. |
| B — Contrato estável | Parcial, contrato documentado | `docs/PUBLIC_API.md`, `CombatAPI.SemVer`, `CombatAPITypes`, exports públicos e `CombatPublicSurfaceTest` adicionados. Tipagem estrita completa (`--!strict` em toda a superfície), política pós-1.0.0 validada e mapeamento específico de todos os códigos de erro ainda não estão concluídos. |
| C — Infraestrutura | Runner executado com sucesso; pendências de ambiente | 61 módulos passaram após correção da colisão e do inventário. O runner deduplica módulos e bloqueia inicialização repetida. O place ainda contém cópias duplicadas; o smoke de dois clientes e a análise da origem dessas duplicatas seguem pendentes. |

A prioridade da Etapa D permanece pendente (decisão D8). As Etapas A e B continuam pré-requisitos antes de iniciar novas capacidades.


## Continuação — contrato público (11 nov 2026)

| Item | Estado | Evidência / pendência |
|---|---|---|
| Tipos públicos Luau | Ampliado | `CombatAPITypes.lua` agora descreve CustomData, Attack, AttackInstance, OffensiveProperties, APIError, APIResult e World; ainda requer análise Luau/Studio. |
| Códigos de erro | Implementado | União documentada, registro congelado, `APIError.isCode` e validação de argumentos. |
| Invariantes de resultado | Implementado | Sucesso não aceita Error; falha exige Error; `APIResult.is` disponível. |
| Testes de contrato | Passaram em Studio | `CombatAPIPublicContractTest.lua` passou com 36 assertions na execução de 2026-11-11. |

O mapeamento de falhas do facade de plugins agora preserva o código interno em `Error.Context.ResolverCode`. A tipagem estática foi ampliada, mas ainda não é correto declarar `--!strict` em toda a superfície pública: os módulos de implementação e os tipos de sistemas/resolvers precisam ser tipados por partes para evitar falsos contratos ou uma migração que apenas silencie erros com `any`.


## Continuação — infraestrutura de validação (11 nov 2026)

- `luau-lsp` foi adicionado à toolchain Aftman em versão fixa (`1.37.0`).
- O workflow gera `sourcemap.json` e analisa os módulos de contrato que já usam
  `--!strict`, com definições globais Roblox. A etapa permanece consultiva para
  evitar transformar diagnósticos ainda não revisados em bloqueio de CI.
- O build Rojo agora é publicado como artefato `combatapi-studio-validation-place`
  por sete dias, facilitando abrir a árvore gerada no Studio e executar a suíte.
- Nenhum teste de runtime é declarado aprovado por essas etapas.


## Continuação — evidências de testes e diagnósticos (11 nov 2026)

- `scripts/create_test_report.py` gera um relatório em Markdown com uma linha
  para cada módulo automatizado e inclui o smoke multiplayer manual.
- O artefato `combatapi-studio-validation-place` agora inclui o place Rojo e o
  modelo de relatório, permitindo registrar resultados reais por script.
- O job de análise Luau não baixa mais um arquivo global externo: o `luau-lsp`
  fornece definições Roblox para projetos Rojo. O log completo e o código de
  saída são publicados em `combatapi-luau-analysis`.
- O analisador continua consultivo; seu job não bloqueia o build e não representa
  aprovação de tipos. A suíte Roblox ainda precisa ser executada no Studio.
- A versão de desenvolvimento passou para `0.1.3`.


## Continuação — empacotamento Wally em prévia (11 nov 2026)

- Adicionado `wally.toml` com metadados SemVer alinhados a `CombatAPI.SemVer` (`0.1.4`).
- Adicionado `src/init.lua` como entrypoint que retorna o facade público `shared.CombatAPI`.
- A lista de inclusão limita o pacote a `/src/init.lua` e `/src/shared/**`; os scripts de teste e o código de servidor não fazem parte do pacote compartilhado.
- O pacote está marcado como `private = true`. Isso permite validar a estrutura sem publicar nem presumir que o escopo Wally esteja reservado ao proprietário.
- CI gera um ZIP de prévia com `wally package`; isso valida o empacotamento, não a instalação num jogo consumidor nem a publicação no registry.
- O runner central já executa os módulos `*Test.lua` sequencialmente no Studio. `CombatMultiplayerSmokeTest.server.lua` permanece manual e separado por exigir dois clientes. O runner e a suíte ainda precisam de validação real no Roblox Studio; CI não declara os testes de runtime aprovados.


## Revisão posterior — limites e canônico do catálogo (sem execução no Studio)

Alterações desta revisão: `OffensiveProperties.CustomDataLimits` e `OffensiveProperties.NormalizeCustomData` passam a ser a fonte única de limites/normalização (reutilizada por `AttackInstance`, `AttackCatalog` e `CollisionWorld`); `AttackCatalog:Register` passa a usar `OffensiveProperties.CanonicalizeCustomData`, corrigindo a rejeição de `CustomData` com 128 a 255 chaves planas aceito por `Attack.new`; testes de fronteira foram adicionados a `CombatAttackCustomDataTest` e `CombatAttackCatalogRollbackTest`.

Verificação realizada fora do Studio: 58 dos 61 módulos `*Test.lua` passaram num harness Luau com stubs mínimos de `Vector3`/`CFrame`, com o mesmo resultado antes e depois da alteração. `CombatAuthorityTest`, `CombatDocumentationTest` e `CombatTest` não rodam nesse harness (exigem `Instance.new`, a árvore do DataModel e APIs de `CFrame` não simuladas) e não foram avaliados. O novo teste do catálogo falha sem a correção e passa com ela. **A suíte completa precisa ser executada novamente no Roblox Studio antes de considerar esta revisão validada.**


## Revisão posterior — códigos de erro de plugin (sem execução no Studio)

Etapa B (mapeamento específico dos códigos de erro): falhas de plugin do facade `CombatAPI` e do `APIContext` deixam de ser sempre `InvalidOperation` e passam por `Events/ResolverErrorMap` (tabela em `docs/PUBLIC_API.md`; código original preservado em `Error.Context.ResolverCode`). Os códigos de capability (`CapabilityConflict`, `CapabilityNotFound`, `CapabilityNotDeclared`, `InvalidCapabilityId`, `InvalidCapabilityVersion`) estão mapeados, mas hoje só são devolvidos como pares `(valor, código)` pelo contexto do plugin; não foram exercitados via facade. Continuam pendentes nesta etapa a tipagem estrita completa da superfície pública e a política pós-1.0.0.

Verificação fora do Studio (harness Luau com stubs de `Vector3`/`CFrame`): 59 dos 62 módulos `*Test.lua` passaram, com o mesmo resultado de antes para os demais; os mesmos três módulos que o harness não executa (`CombatAuthorityTest`, `CombatDocumentationTest`, `CombatTest`) continuam fora da verificação. `CombatPluginErrorMappingTest` falha com o comportamento antigo (`got InvalidOperation`) e passa com o mapeamento. `scripts/validate_test_inventory.py` aceita o inventário de 62 módulos. **A suíte completa precisa ser executada novamente no Roblox Studio.** `CombatAPI.SemVer` não foi alterado.


## Continuação — consumidor de referência (12 nov 2026)

- Revisão estática de `docs/examples/CustomDataConsumer.server.lua` encontrou que anexar `Hitbox` com `owner:AddComponent(hitbox)` faz o `CombatStateSchema` tratá-la como componente de entidade, embora `Hitbox` não implemente `CaptureRollbackState`/`RestoreRollbackState`. Isso impediria a captura de snapshot do exemplo.
- O exemplo agora define `Owner`, associa a hitbox à `AttackInstance` e registra a região diretamente em `CollisionWorld`; também ativa a instância antes da captura.
- `CombatPublicSurfaceTest` ganhou uma regressão de integração pela superfície pública: registra ataque no catálogo, cria override, captura snapshot, altera a geometria, restaura e verifica o `CustomData` efetivo e a geometria recuperada.
- Validações executadas neste ambiente: inventário (62 módulos) válido, manifesto Wally válido e `git diff --check` sem problemas. Não há Rojo, Wally ou `luau-lsp` instalados neste ambiente; a regressão e o exemplo ainda precisam de execução no Roblox Studio.


## Continuação — tipagem da superfície pública (12 nov 2026)

- `CombatAPITypes.lua` agora declara contratos para `CombatAPI`, `APIContext`,
  eventos, inscrições, opções de eventos e assinaturas dos construtores de
  `Attack` e `AttackInstance`, incluindo a compatibilidade do quarto argumento
  escalar legado com o novo registro de opções.
- `CombatAPI.lua` e `Events/APIContext.lua` receberam assinaturas explícitas e
  `--!strict`; o facade é associado ao contrato `CombatTypes.CombatAPI`.
- `CombatAPITypesTest.lua` foi adicionado como teste compile-time/runtime para
  verificar o contrato do facade e o uso tipado de ataques e overrides.
- A CI foi ampliada para analisar esses dois módulos além dos contratos
  `CombatAPITypes`, `APIError` e `APIResult`. A análise continua consultiva.
- Os getters crus de resolvers permanecem `any` por decisão explícita de
  fronteira: ainda não há contratos concretos e estáveis para todos eles.
- Inventário atualizado e validado: 63 módulos automatizados e um smoke test
  multiplayer separado. `scripts/validate_wally_package.py`, validação do JSON
  e `git diff --check` passaram.
- `luau-lsp`, Rojo e Aftman não estão instalados neste ambiente, então não foi
  possível executar a análise, o build Rojo ou os testes de runtime nesta rodada.
  O relatório `combatapi-studio-test-report.md` mantém os 63 resultados como
  pendentes. A Etapa B permanece parcial.


## Continuação — contratos tipados de plugins (12 nov 2026)

- Os tipos públicos agora descrevem perfis, dependências, implementações, estados
  e resultados de plugin. `CombatAPI` e `APIContext` tipam registro e ciclo de
  vida com `APIResult<PluginResolverResult>`, e a consulta de plugin retorna
  `APIResult<Plugin>`.
- `CombatAPITypesTest` cobre construção, registro, consulta e início de plugin
  pela superfície pública.
- A fronteira de acesso a resolvers continua intencionalmente dinâmica; os
  tipos de contexto de callback ainda deixam `any` para a API extensível do
  contexto de plugin. A tipagem estrita completa da implementação permanece
  pendente.
- Validação Luau e execução no Roblox Studio ainda precisam ser feitas; esta
  alteração não declara aprovação de runtime.


## Continuação — contratos e ciclo de vida de capabilities (12 nov 2026)

- `PluginContext:GetRegistry()` agora tem contrato tipado de consulta para
  plugins e capabilities; as assinaturas de `Initialize`, `Start`, `Stop` e
  `Subscribe` descrevem os contextos, eventos, inscrições e erros retornados.
- Os códigos de erro de `RegisterCapability` e `Register` estão enumerados nos
  tipos públicos, sem mudar o formato de retorno em dois valores.
- Corrigido `CombatAPITypesTest`: a chamada multi-retorno de
  `RegisterCapability` agora captura capability e erro em variáveis separadas,
  em vez de indexar incorretamente o registro retornado como tupla.
- O teste cobre conflitos, capabilities não declaradas, invalidação do contexto
  ao parar o plugin e segurança de uma vista de registry retida.
- Build Rojo e `git diff --check` passaram nesta revisão; a análise Luau e o
  runtime de Studio continuam pendentes.


## Continuação — erros consistentes na consulta de plugins (12 nov 2026)

- `APIContext:GetPlugin` valida o ID antes da consulta e distingue entrada
  inválida, plugin inexistente e contexto destruído com `InvalidArgument`,
  `NotFound` e `Destroyed`, respectivamente; a ausência inesperada do resolver
  é reportada como `NotInitialized`.
- `PluginContext:Subscribe` tipa tanto erros estruturados do EventBus quanto os
  códigos locais retornados para argumentos inválidos e contexto invalidado.
- Regressões adicionadas ao `CombatAPITypesTest` e ao `CombatPluginTest` para
  validar IDs vazios e consulta após destruição; os casos de Subscribe inválido
  também são exercitados no teste tipado.
- Build Rojo e `git diff --check` passaram; testes Roblox Studio e análise Luau
  continuam pendentes.


## Continuação — contrato do EventBus e validação de extensões (12 nov 2026)

- Adicionado o tipo público `EventBus` e aplicado a `APIContext.Events`,
  `APIContext:GetEvents()` e `PluginContext:GetEventBus()`.
- A assinatura de callback de `PluginContext:Subscribe` agora reflete o
  `APIContext` não nulo passado pelo EventBus do World.
- O teste tipado também verifica acesso ao EventBus compartilhado e a resposta
  `UnsupportedExtensionKind` da API genérica `PluginContext:Register`.
- Build Rojo e `git diff --check` passaram; a suíte Roblox Studio/análise Luau
  permanecem pendentes.


## Continuação — consistência de versões de plugins (12 nov 2026)

- `Plugins/PluginVersion` centraliza validação e comparação do formato
  numérico `major.minor.patch`, reutilizado por perfis, dependências e
  capabilities.
- A comparação decimal por componentes preserva exatidão para versões com
  componentes maiores que a precisão inteira dos números Luau.
- `PluginCapability.new` valida versão e proprietário; `RegisterCapability`
  converte versões malformadas em `InvalidCapabilityVersion` em vez de deixar
  uma asserção escapar durante o ciclo de vida do plugin.
- `CombatPluginTest` cobre versões inválidas, comparação de componentes muito
  grandes e dependências sem versão mínima; `CombatDocumentationTest` confirma
  que o novo módulo está empacotado e carregável.
- Build Rojo, validação do JSON e `git diff --check` passaram nesta rodada; os
  testes Roblox Studio e a análise Luau seguem pendentes.


## Debug do snapshot público — 12 nov 2026

- O log do Roblox Studio reportou 62 testes aprovados e uma falha em
  `CombatPublicSurfaceTest`: `World has no Simulation` durante
  `CaptureCombatState()`. A causa era o teste e o consumidor de referência
  capturarem/restaurarem snapshots sem inicializar o relógio de simulação
  exigido pelo schema.
- `CombatAPI.Simulation` agora é exportado e tipado; o teste de superfície e
  `CustomDataConsumer.server.lua` inicializam `Simulation.new(world)` antes
  de usar snapshots. `CombatAPITypesTest` e `CombatDocumentationTest` cobrem o
  novo contrato.
- O build Rojo e `git diff --check` passaram após a correção. A suíte precisa
  ser executada novamente no Roblox Studio; não há ainda evidência de que os
  63 testes passem juntos.
- Na execução seguinte do Studio, `CombatPublicSurfaceTest` avançou além da
  inicialização da Simulation, mas a restauração falhou porque o snapshot tinha
  geometria não vazia sem um `CollisionTopologyCatalog`. O facade agora expõe
  o catálogo; o teste e o exemplo configuram uma fábrica versionada. Build e
  execução da suíte ainda precisam ser repetidos para confirmar o resultado.


## Continuação — execução completa no Studio (12 nov 2026)

- O usuário confirmou `CombatTestRunner: PASS (63 tests)`, com todos os 63
  testes executados e nenhuma falha após a inclusão da `Simulation` e do
  `CollisionTopologyCatalog` na configuração do teste de superfície pública.
- O benchmark no mesmo Output reportou `restored=true`; para a configuração
  `entities=32`, `volumes=64`, `attackInstances=32`, `frames=30` e
  `repetitions=3`, mediu captura média de 0,007295 s, serialização de
  0,002893 s, validação de colisão de 0,001312 s, preparação de restore de
  0,001691 s, step de 0,184594 s e restore/replay de 0,176639 s. Continua sem
  baseline pré-CustomData comparável.
- O Output ainda contém avisos de incompatibilidade de tipo do asset
  `rbxassetid://203785492`; não foram falhas de teste. O smoke multiplayer
  com dois clientes estava pendente naquela execução.
- A cobertura tipada da `Simulation` foi ampliada para validar opções de
  configuração, captura/restauração do estado e hash. Build Rojo e análise
  Luau precisam ser repetidos após essas alterações.
- Atualização posterior: o usuário confirmou que o smoke test terminou sem
  erros. A pendência de execução do smoke está encerrada; não foram fornecidos
  detalhes adicionais sobre número de clientes ou métricas.
