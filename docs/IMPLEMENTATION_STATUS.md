# Status da implementação — CustomData

Data da revisão: 2026-11-11

Este relatório acompanha o plano `combatapi-customdata-plano.md`. Ele distingue a
presença estática de código/testes da aprovação em runtime. Nenhuma fase que
depende da execução no Roblox Studio é marcada como integralmente aprovada sem
os resultados dessa execução.

| Fase | Estado nesta revisão | Evidência / pendência |
|---|---|---|
| 0 — Preparação | Parcial | Os contratos `API.md`, `Conventions.md`, `Rollback.md` e `Testing.md` estão na árvore ativa; o registro de migração 2 → 3 está em `CombatStateSchema.new`. O benchmark contém cenário com instâncias com/sem override. Ainda faltam executar a suíte original e registrar números de linha de base no Roblox Studio. |
| 1 — Núcleo do dado | Implementação presente | `OffensiveProperties`, `Attack` e `CombatAttackCustomDataTest` cobrem validação, cópia, congelamento e espelhamento. Execução em Studio pendente. |
| 2 — Instância e acerto | Implementação presente | `AttackInstance` mantém o argumento escalar legado e aceita opções; `HitProcessor` repassa o dado no fallback. Testes de propriedades e instância estão presentes. Execução em Studio pendente. |
| 3 e 4 — Catálogo, snapshot e schema | Implementação presente | Manifest v2, schema v3/migração 2 → 3, captura/validação/restauração in-place e rebuild de topologia. O teste de colisão agora cobre dois overrides diferentes para duas instâncias da mesma definição. Execução em Studio pendente. |
| 5 — Eventos públicos | Implementação presente | `HitConfirmed` e `DamageApplied` encaminham a referência congelada; `CombatEventAPITest` verifica preservação de chave `Id` e identidade da referência. Execução em Studio pendente. |
| 6 — Determinismo, replay e performance | Parcial | Adicionado `CombatCustomDataReplayTest`: hashes equivalentes para overrides derivados de frames, divergência de hash para valor divergente e fingerprint baseado no manifest. O benchmark mede captura, serialização, validação, preparação/restauração e tamanho de snapshot com/sem overrides. Ainda faltam executar o teste e coletar/ comparar medições reais com a linha de base. |
| 7 — Documentação e changelog | Documentação presente | `API.md`, `Conventions.md`, `Rollback.md`, `Testing.md`, `CUSTOMDATA.md` e `CHANGELOG.md` descrevem o contrato. O inventário do `CombatDocumentationTest` foi atualizado para incluir o novo teste de replay. Execução em Studio pendente. |

## Verificações estáticas realizadas

- O inventário documentado contém exatamente os módulos automatizados `*Test.lua`; o smoke multiplayer permanece registrado separadamente como Script.
- Os pontos centrais de `CustomData` estão presentes: normalização, merge raso,
  fallback do `HitProcessor`, manifest v2, migração do schema v3, snapshots e
  encaminhamento aos eventos públicos.
- O teste novo de replay está incluído no inventário de documentação.

## Critério para fechar as fases

Executar no Roblox Studio a suíte completa de módulos `*Test.lua`, incluindo
`CombatDocumentationTest`, `CombatDocumentationExamplesTest` e
`CombatCustomDataReplayTest`. Em seguida, executar
`CombatStabilizationBenchmark.server.lua` com os mesmos atributos e ambiente da
linha de base, guardar os relatórios e investigar regressões antes de declarar
as Fases 0 e 6 aprovadas.

A revisão estática não substitui essa execução: este pacote não afirma que os
testes passaram no Roblox Studio.


## Continuação do roadmap (Etapas A a C)

| Etapa | Estado | Evidência / pendência |
|---|---|---|
| A — Consumidor de referência | Parcial, exemplo preparado | `docs/examples/CustomDataConsumer.server.lua` usa exports públicos para definir ataque, override, catálogo, hitbox e snapshot/restore. Precisa ser executado em Studio; lacunas encontradas devem ser registradas antes de declarar aceite. |
| B — Contrato estável | Parcial, contrato documentado | `docs/PUBLIC_API.md`, `CombatAPI.SemVer`, `CombatAPITypes`, exports públicos e `CombatPublicSurfaceTest` adicionados. Tipagem estrita completa (`--!strict` em toda a superfície), política pós-1.0.0 validada e mapeamento específico de todos os códigos de erro ainda não estão concluídos. |
| C — Infraestrutura | Runner implementado; validação Studio pendente | Os testes automatizados foram migrados para módulos executáveis sequencialmente pelo `CombatTestRunner.server.lua`, com timeout e resultado por módulo. CI valida o inventário, compila Rojo e o pacote Wally privado de prévia, publica artefatos e preserva diagnósticos consultivos. Execução real no Studio e publicação Wally continuam pendentes. |

A prioridade da Etapa D permanece pendente (decisão D8). As Etapas A e B continuam pré-requisitos antes de iniciar novas capacidades.


## Continuação — contrato público (11 nov 2026)

| Item | Estado | Evidência / pendência |
|---|---|---|
| Tipos públicos Luau | Ampliado | `CombatAPITypes.lua` agora descreve CustomData, Attack, AttackInstance, OffensiveProperties, APIError, APIResult e World; ainda requer análise Luau/Studio. |
| Códigos de erro | Implementado | União documentada, registro congelado, `APIError.isCode` e validação de argumentos. |
| Invariantes de resultado | Implementado | Sucesso não aceita Error; falha exige Error; `APIResult.is` disponível. |
| Testes de contrato | Preparados | `CombatAPIPublicContractTest.lua`; execução em Studio pendente. |

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
