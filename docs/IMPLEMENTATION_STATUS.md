# Status da implementação — CustomData

Data da revisão: 2026-11-11

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
| A — Consumidor de referência | Parcial, exemplo preparado | `docs/examples/CustomDataConsumer.server.lua` usa exports públicos para definir ataque, override, catálogo, hitbox e snapshot/restore. Precisa ser executado em Studio; lacunas encontradas devem ser registradas antes de declarar aceite. |
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
