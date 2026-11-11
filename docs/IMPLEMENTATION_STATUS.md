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

- O inventário documentado contém exatamente os 60 scripts `*Test.server.lua` existentes.
- Os pontos centrais de `CustomData` estão presentes: normalização, merge raso,
  fallback do `HitProcessor`, manifest v2, migração do schema v3, snapshots e
  encaminhamento aos eventos públicos.
- O teste novo de replay está incluído no inventário de documentação.

## Critério para fechar as fases

Executar no Roblox Studio a suíte completa de scripts `*Test.server.lua`, incluindo
`CombatDocumentationTest`, `CombatDocumentationExamplesTest` e
`CombatCustomDataReplayTest`. Em seguida, executar
`CombatStabilizationBenchmark.server.lua` com os mesmos atributos e ambiente da
linha de base, guardar os relatórios e investigar regressões antes de declarar
as Fases 0 e 6 aprovadas.

A revisão estática não substitui essa execução: este pacote não afirma que os
testes passaram no Roblox Studio.
