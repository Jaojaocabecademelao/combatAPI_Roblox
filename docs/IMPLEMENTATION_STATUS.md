# Status da implementação — CustomData

Data da revisão: 2026-11-11

Este relatório acompanha o plano `combatapi-customdata-plano.md`. Ele distingue a
presença estática de código/testes da aprovação em runtime. Nenhuma fase que
depende da execução no Roblox Studio é marcada como integralmente aprovada sem
os resultados dessa execução.

| Fase | Estado nesta revisão | Evidência / pendência |
|---|---|---|
| 0 — Preparação | Parcial | A suíte completa mais recente foi confirmada sem erros no Roblox Studio. Há uma medição registrada abaixo, mas não existe benchmark pré-CustomData comparável; a linha de base de performance ainda está pendente. |
| 1 — Núcleo do dado | Testes de runtime passaram | `CombatAttackCustomDataTest` e a suíte completa passaram na execução Studio mais recente, confirmada pelo usuário. |
| 2 — Instância e acerto | Testes de runtime passaram | A suíte completa passou na execução Studio mais recente, confirmada pelo usuário. |
| 3 e 4 — Catálogo, snapshot e schema | Testes de runtime passaram | A suíte completa, incluindo catálogo, migração, rollback de colisão e rebuild de topologia, passou na execução Studio mais recente, confirmada pelo usuário. |
| 5 — Eventos públicos | Testes de runtime passaram | A suíte completa, incluindo `CombatEventAPITest`, passou na execução Studio mais recente, confirmada pelo usuário. |
| 6 — Determinismo, replay e performance | Replay passou; benchmark medido sem baseline comparável | A suíte completa passou. O benchmark coletou tempos e tamanho de snapshot com/sem overrides; ainda não há medição pré-CustomData para avaliar regressão. |
| 7 — Documentação e changelog | Testes de runtime passaram | `CombatDocumentationTest` e `CombatDocumentationExamplesTest` passaram na execução Studio mais recente, confirmada pelo usuário. |

## Verificações estáticas realizadas

- O inventário documentado contém exatamente os módulos automatizados `*Test.lua`; o smoke multiplayer permanece registrado separadamente como Script.
- Os pontos centrais de `CustomData` estão presentes: normalização, merge raso,
  fallback do `HitProcessor`, manifest v2, migração do schema v3, snapshots e
  encaminhamento aos eventos públicos.
- O teste novo de replay está incluído no inventário de documentação.

## Última execução no Roblox Studio — 2026-11-11

- O usuário confirmou que a suíte completa do código atual terminou sem erros.
  O inventário vigente contém 62 módulos automatizados; o log final com a
  contagem não foi anexado. Execuções anteriores registraram falhas no
  `CombatCustomDataConsumerTest`, resolvidas pelo uso de factories versionadas
  de `CollisionTopologyCatalog`. A confirmação mais recente inclui as
  verificações de registro/consulta de regiões acrescentadas a
  `CombatPublicSurfaceTest`.
- O place continha duas cópias de cada módulo automatizado. O runner emitiu 61
  avisos de duplicação e executou uma cópia por nome. Uma segunda inicialização
  do runner foi bloqueada como esperado. A causa da duplicação no place não foi
  identificada nesta revisão.
- Em logs anteriores, o Output registrou duas falhas ao carregar
  `rbxassetid://203785492` por incompatibilidade de tipo do asset; não são
  resultados de `TEST FAIL`. A confirmação mais recente do usuário reporta
  uma execução sem erros.
- O smoke multiplayer continua pendente: logs anteriores registraram zero
  clientes no início e um cliente conectado, sem resultado de conclusão.

Benchmark reportado com `entities=32`, `volumes=64`, `attackInstances=32`,
`frames=30`, `repetitions=3`:

| Métrica | Resultado |
|---|---:|
| Snapshot com overrides | 52 305 bytes |
| Snapshot sem overrides | 51 253 bytes |
| Bytes atribuídos aos overrides | 1 052 (16 overrides) |
| Captura (média) | 0,001396 s |
| Serialização (média) | 0,000639 s |
| Validação de colisão (média) | 0,000286 s |
| Preparação/restauração (média) | 0,000389 s |
| Step (média) | 0,032872 s |
| Restore/replay (média) | 0,040454 s |

Uma execução anterior no mesmo log de trabalho usou a mesma configuração, mas
também não é uma linha de base pré-CustomData. Diferenças pequenas de tempo entre
essas duas execuções não são suficientes para concluir regressão ou ganho.

## Pendências para fechar as fases

A correção da Simulation pública foi confirmada por `CombatPublicSurfaceTest`,
e o usuário confirmou que a suíte completa do código atual terminou sem erros.
O teste e o exemplo registram uma factory versionada pela
`CollisionTopologyCatalog` pública, necessária para reconstruir a Hitbox durante
o rollback. Para fechar a validação geral, investigar a duplicação no place,
executar
`CombatMultiplayerSmokeTest.server.lua` com dois clientes e obter uma linha de
base pré-CustomData do `CombatStabilizationBenchmark.server.lua` com os mesmos
atributos e ambiente.


## Continuação do roadmap (Etapas A a C)

| Etapa | Estado | Evidência / pendência |
|---|---|---|
| A — Consumidor de referência | Aprovado pelo usuário no Studio | `docs/examples/CustomDataConsumer.server.lua` e `CombatCustomDataConsumerTest.lua` usam somente o facade `CombatAPI`, incluindo o `CollisionTopologyCatalog` versionado para restauração. O usuário confirmou que a suíte completa do código atual terminou sem erros; a cópia do teste anexada nesta conversa é anterior a essa implementação. |
| B — Contrato estável | Parcial, em andamento | Política SemVer/depreciação, fronteira público/interno e superfície da API documentadas. Tipos públicos agora descrevem construtores de consumidor, eventos, APIContext, resultados/erros, colisão e rollback; os módulos de fachada exportam aliases dos contratos compartilhados. O mapeamento de falhas de plugins para códigos estáveis também foi implementado. Ainda faltam a análise Luau, fechar contratos sem `any` para todos os módulos exportados e executar os novos testes de mapeamento de erro no Studio. |
| C — Infraestrutura | Suíte completa aprovada pelo usuário; pendências de ambiente | O usuário confirmou a execução sem erros da suíte completa atual. O runner deduplica módulos e bloqueia inicialização repetida. O smoke de dois clientes e a análise da origem de módulos duplicados seguem pendentes. |

A prioridade da Etapa D permanece pendente (decisão D8). As Etapas A e B continuam pré-requisitos antes de iniciar novas capacidades.


## Continuação — contrato público (11 nov 2026)

| Item | Estado | Evidência / pendência |
|---|---|---|
| Tipos públicos Luau | Ampliado, análise pendente | `CombatAPITypes.lua` cobre entidades, construtores, `APIContext`, envelopes/payloads públicos de eventos, `APIResult`, `APIError`, catálogo de ataques, colisão e rollback. `CombatAPI`, `APIContext`, `Event`, `EventTypes` e `OffensiveProperties` exportam aliases de tipos. `Hitbox.Id`/`Hurtbox.Id` são opcionais antes do registro; os retornos de registro garantem ID numérico. `luau-lsp` não está instalado como alias local, e `aftman install` não pode atualizar aliases enquanto `rojo.exe` está em execução. Os módulos não foram declarados integralmente `--!strict` sem validar os diagnósticos. |
| Códigos de erro | Implementado, testes novos pendentes | União documentada, registro congelado, `APIError.isCode` e validação de argumentos. Falhas conhecidas do PluginResolver são mapeadas a categorias estáveis; códigos desconhecidos usam `InvalidOperation`, preservando o código original em `Error.Context.ResolverCode`. |
| Invariantes de resultado | Implementado | Sucesso não aceita Error; falha exige Error; `APIResult.is` disponível. |
| Testes de contrato | Parte confirmada; testes do mapeamento pendentes | `CombatAPIPublicContractTest.lua` passou com 36 assertions na execução de 2026-11-11, e o usuário confirmou sem erros a suíte de 62 módulos, incluindo o registro/consulta de regiões em `CombatPublicSurfaceTest`. Novas assertions de mapeamento de erros foram adicionadas após essa confirmação e precisam de execução no Studio. |

As falhas de plugins agora mantêm o código específico no resultado do resolver e o expõem como `Error.Context.ResolverCode`, além de mapear a categoria pública para `APIError.Code`. A tipagem estática foi ampliada, mas ainda não é correto declarar `--!strict` em toda a superfície pública: faltam tipos específicos para alguns módulos/sistemas exportados, e os contratos usam `any` onde esses valores ainda não foram modelados.


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
  aprovação de tipos. A validação Studio foi confirmada posteriormente pelo
  usuário para os 62 módulos automatizados; o smoke multiplayer permanece
  separado e não concluído.
- A versão de desenvolvimento passou para `0.1.3`.


## Continuação — empacotamento Wally em prévia (11 nov 2026)

- Adicionado `wally.toml` com metadados SemVer alinhados a `CombatAPI.SemVer` (`0.1.4`).
- Adicionado `src/init.lua` como entrypoint que retorna o facade público `shared.CombatAPI`.
- A lista de inclusão limita o pacote a `/src/init.lua` e `/src/shared/**`; os scripts de teste e o código de servidor não fazem parte do pacote compartilhado.
- O pacote está marcado como `private = true`. Isso permite validar a estrutura sem publicar nem presumir que o escopo Wally esteja reservado ao proprietário.
- CI gera um ZIP de prévia com `wally package`; isso valida o empacotamento, não a instalação num jogo consumidor nem a publicação no registry.
- O runner central executa os módulos `*Test.lua` sequencialmente no Studio. `CombatMultiplayerSmokeTest.server.lua` permanece manual e separado por exigir dois clientes. O usuário confirmou a suíte de 62 módulos sem erros; CI não executa nem declara testes de runtime aprovados.
