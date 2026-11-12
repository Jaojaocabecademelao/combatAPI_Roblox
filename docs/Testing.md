# Testing

## Execução

Os testes automatizados do projeto são módulos `*Test.lua` em `src/server/`.
No Roblox Studio, `CombatTestRunner.server.lua` descobre esses módulos, executa
suas funções em ordem alfabética, aplica timeout de 30 segundos por teste e
imprime um resultado estruturado por módulo. O runner impede inicialização
repetida na mesma sessão e deduplica módulos com o mesmo nome, emitindo um aviso
no Output. Uma falha é reportada no Output e no final da execução; timeout
interrompe a suíte para evitar continuar com um teste possivelmente ainda ativo.

A suíte cobre módulos isolados e integrações entre World, Simulation, combate,
colisão, eventos, rollback, determinismo e replay. `CombatDocumentationTest`
também verifica se o inventário documentado corresponde aos módulos presentes.
O script `scripts/validate_test_inventory.py` faz a mesma checagem sem Roblox e é
executado pela CI antes do build Rojo.

`CombatMultiplayerSmokeTest.server.lua` permanece fora do runner: exige dois
clientes e só inicia quando o atributo `CombatMultiplayerSmokeTest` em
`ReplicatedStorage` é definido como `true`. Execute-o separadamente num servidor
de teste com dois clientes.

## Superfície pública e consumidor de referência

- `CombatAPITypesTest.lua`: valida por análise Luau e execução os contratos de `CombatAPI`, `APIContext`, `AttackOptions`, `Attack` e `AttackInstanceOptions`.
- `CombatPublicSurfaceTest.lua`: verifica exports públicos, versão SemVer,
  versões de manifest/schema, uso público de `AttackCatalog` e uma restauração
  de snapshot com `CustomDataOverrides`/geometria via `CollisionWorld`.
- `CombatAPIPublicContractTest.lua`: verifica o registro de códigos estáveis,
  imutabilidade de `APIError`/`APIResult` e invariantes de sucesso/falha.
- `CombatPluginErrorMappingTest.lua`: provoca falhas reais do `PluginResolver` pelo facade `CombatAPI` e pelo `APIContext` e verifica o `APIError.Code` mapeado, a preservação de `Context.ResolverCode`, `System` e `Frame`, a imutabilidade do erro e o fallback para `InvalidOperation`.
- `examples/CustomDataConsumer.server.lua`: exemplo executável em um place de
  teste. Cria o World, catálogo, ataque, override derivado de frames, hitbox e
  snapshot/restore usando apenas exports públicos. Após restore, reacquire a
  entidade pelo ID, pois referências anteriores podem ficar obsoletas.

## Cobertura de `CustomData`

- `CombatAttackCustomDataTest.lua`: validação, limites, cópia defensiva,
  congelamento recursivo, normalização de `{}`, merge raso, compartilhamento sem
  override e compatibilidade das assinaturas legadas de `AttackInstance.new`.
- `CombatAttackPropertiesTest.lua`: integração de propriedades ofensivas
  no caminho de processamento de hit, incluindo fallback de propriedades.
- `CombatAttackCatalogRollbackTest.lua`: manifest v2, comparação canônica
  e rejeição de manifest v1 quando definições usam `CustomData`.
- `CombatCollisionRollbackTest.lua`: captura, validação e restauração
  in-place de overrides distintos em duas instâncias da mesma definição.
- `CombatTopologyRebuildRollbackTest.lua`: reconstrução de instâncias e
  rejeição de overrides inválidos no caminho de rebuild da topologia.
- `CombatStateSchemaTest.lua`: migração de schema 2 para 3 e rejeição de
  versões sem migração ou futuras.
- `CombatCustomDataReplayTest.lua`: calcula overrides a partir de contadores
  de frame, compara hashes canônicos entre execuções equivalentes e verifica que
  um override divergente é identificado pelo comparador de replay. O teste também
  usa o manifest do catálogo como fingerprint de conteúdo.
- `CombatReplayRecordingTest.lua` e `CombatDeterminismTest.lua`:
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


O inventário documentado inclui `CombatPublicSurfaceTest.lua`.

O andamento por fase e as validações ainda pendentes estão registrados em
[IMPLEMENTATION_STATUS](IMPLEMENTATION_STATUS.md).


## Validação automatizada no GitHub Actions

O workflow `Validate CombatAPI` executa validação do JSON, consistência do
inventário, build Rojo e publica o `.rbxlx` como artefato por sete dias para
abrir no Roblox Studio. O artefato é um place de validação, não um resultado de
testes aprovados.

Há também uma análise Luau consultiva dos módulos de contrato e facade marcados com
`--!strict` (`CombatAPITypes`, `APIError`, `APIResult`, `APIContext` e `CombatAPI`). Ela é temporariamente consultiva (`continue-on-error`) enquanto o
projeto estabelece e revisa uma linha de base de diagnósticos. As definições
globais Roblox são baixadas do repositório `luau-lsp`; portanto, essa etapa não substitui a análise integrada do Roblox Studio nem a execução dos scripts de
teste.


## Registro reproduzível da execução

Gere um modelo com uma linha para cada módulo automatizado e teste manual:

```sh
python3 scripts/create_test_report.py --output combatapi-studio-test-report.md
```

Abra o place de validação no Roblox Studio e inicie uma sessão de teste. O
`CombatTestRunner.server.lua` executa os módulos `*Test.lua` e registra cada
resultado no Output. O smoke multiplayer fica separado e requer a configuração
descrita acima. Registre no modelo os resultados observados, a versão do Studio,
o commit e eventuais erros do Output. Não marque um teste como aprovado apenas
porque o place abriu ou foi compilado pelo Rojo.

A CI anexa o modelo ao artefato `combatapi-studio-validation-place`. A análise
Luau consultiva também publica o log completo e o código de saída em
`combatapi-luau-analysis`; um diagnóstico do analisador não é um teste de runtime.


## Pacote Wally (prévia privada)

O repositório inclui um manifesto Wally para preparar a distribuição da superfície compartilhada. `src/init.lua` é o entrypoint do pacote e retorna o mesmo facade público de `CombatAPI`. A inclusão está limitada a `/src/init.lua` e `/src/shared/**`; scripts de teste e implementação exclusiva do servidor não devem ser distribuídos nesse pacote compartilhado.

Validar localmente:

```sh
python3 scripts/validate_wally_package.py
wally package --output combatapi-wally-package.zip
```

O manifesto permanece `private = true`. Não publique até confirmar a disponibilidade/posse do escopo Wally, concluir os critérios de contrato público e executar a validação de runtime num place consumidor.

## Limite do runner central

A suíte automatizada usa um contrato comum: cada `*Test.lua` retorna uma função,
e o runner executa uma função por vez com isolamento de falha e timeout. A CI
valida o inventário e compila o place, mas não executa módulos Roblox; a aprovação
de runtime continua dependendo da execução no Studio. O smoke multiplayer é um
teste separado porque depende de dois clientes conectados.


## Static type analysis

The public type contracts live in `src/shared/CombatAPITypes.lua`. The public
entry module is typed against `CombatTypes.CombatAPI`, and `APIContext.lua` is
annotated with `--!strict`. Run the repository's pinned `luau-lsp` through
Aftman after generating the Rojo sourcemap for the target place; do not treat a
Rojo build or runtime test pass as a substitute for type analysis. Record the
`luau-lsp` version, exact command, diagnostics, and any intentionally dynamic
resolver boundaries in the test report.
