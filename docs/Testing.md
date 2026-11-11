# Testing

## Execução

Os testes automatizados do projeto são scripts `*Test.server.lua` em `src/server/`.
Eles devem ser executados no Roblox Studio, com a árvore Rojo montada conforme
`default.project.json`. Cada script encerra com uma mensagem `PASS` quando suas
asserções terminam sem erro.

A suíte cobre módulos isolados e integrações entre World, Simulation, combate,
colisão, eventos, rollback, determinismo e replay. `CombatDocumentationTest`
também verifica se o inventário documentado corresponde aos scripts presentes.

## Cobertura de `CustomData`

- `CombatAttackCustomDataTest.server.lua`: validação, limites, cópia defensiva,
  congelamento recursivo, normalização de `{}`, merge raso, compartilhamento sem
  override e compatibilidade das assinaturas legadas de `AttackInstance.new`.
- `CombatAttackPropertiesTest.server.lua`: integração de propriedades ofensivas
  no caminho de processamento de hit, incluindo fallback de propriedades.
- `CombatAttackCatalogRollbackTest.server.lua`: manifest v2, comparação canônica
  e rejeição de manifest v1 quando definições usam `CustomData`.
- `CombatCollisionRollbackTest.server.lua`: captura, validação e restauração
  in-place de `CustomDataOverrides` por instância.
- `CombatTopologyRebuildRollbackTest.server.lua`: reconstrução de instâncias e
  rejeição de overrides inválidos no caminho de rebuild da topologia.
- `CombatStateSchemaTest.server.lua`: migração de schema 2 para 3 e rejeição de
  versões sem migração ou futuras.
- `CombatReplayRecordingTest.server.lua` e `CombatDeterminismTest.server.lua`:
  infraestrutura geral de replay/determinismo. O consumidor deve garantir que
  overrides usados em gameplay derivem apenas de inputs e estado determinístico.

## Benchmark

`CombatStabilizationBenchmark.server.lua` fornece a linha de base geral e agora
inclui `AttackInstanceCount` (padrão 32, máximo 128). O relatório separa tempo de
captura, serialização, validação de colisão e preparação/restauração, além de
comparar o tamanho serializado do snapshot com e sem os overrides. Execute com
o atributo `RunBenchmark=true`. Os resultados precisam ser coletados no mesmo
ambiente e com a mesma quantidade de instâncias; este repositório não registra
números medidos neste ambiente de edição.
