# Contrato atual: `CustomData` em ataques

**Versão documentada:** CombatStateSchema **3**; manifest do AttackCatalog **2**. Este documento descreve a implementação atualmente presente em `src/`; não é uma proposta futura.

## Uso

`Attack.new({ CustomData = { ... } })` associa dados livres à definição do ataque. Para variar os dados em uma execução específica, passe no quarto argumento de `AttackInstance.new` uma tabela de opções: `AttackInstance.new(attack, owner, idGenerator, { CustomDataOverrides = { Radius = 4 } })`. O quarto argumento escalar continua reservado ao ID explícito legado.

O valor efetivo da instância é um **merge raso**: as chaves do override substituem as chaves correspondentes da definição, e as demais são herdadas. Tabelas aninhadas são substituídas como valores inteiros; não há merge profundo. Sem override, a instância compartilha as propriedades imutáveis do `Attack`, sem criar cópia. `CustomDataOverrides` guarda somente o override.

## Validação e imutabilidade

`CustomData` e `CustomDataOverrides` aceitam `nil` ou uma tabela simples serializável pelo `StateSerializer`: sem metatable, ciclos, funções, `Instance`/userdata, NaN/infinito ou chaves incompatíveis com o serializador. O limite é **256 entradas e profundidade 8 por campo**. Tabela vazia é normalizada para `nil`. A API copia e congela recursivamente os dados, incluindo os valores aninhados; alterações posteriores na tabela de entrada não afetam a definição nem a instância.

O dado é opaco: a API não interpreta seus campos. Código de gameplay deve acessar chaves conhecidas e não depender da ordem de `pairs`; se a iteração for necessária para lógica determinística, ordene as chaves. Valores usados para calcular overrides devem vir de inputs/contadores determinísticos (por exemplo, frames de carga), nunca do relógio real ou de aleatoriedade não determinística.

## Hit, eventos e rollback

`HitProcessor` preserva `CustomData` inclusive quando completa propriedades ausentes usando os dados da hitbox. Os eventos públicos `HitConfirmed` e `DamageApplied` publicam `CustomData` a partir das propriedades ofensivas; o valor é a referência congelada e pode ser `nil`. O envelope público preserva especificamente essa referência opaca (inclusive uma chave chamada `Id`), em vez de projetá-la como uma referência de entidade.

Snapshots do `CollisionWorld` guardam somente `CustomDataOverrides`, omitindo a chave quando não há override. Tanto a restauração in-place quanto a reconstrução de topologia reaplicam o override salvo; a validação rejeita dados inválidos antes de qualquer mutação do estado vivo. O catálogo incorpora a serialização canônica do `CustomData` das definições ao manifest v2; uma alteração é detectada na validação de rollback. Manifests v1 são aceitos apenas quando as definições atuais não têm `CustomData`. O schema de estado é v3 e migra snapshots v2 para v3; leitores anteriores devem rejeitar snapshots v3 em vez de ignorar overrides. Como em qualquer replay, os overrides devem ser reproduzidos a partir dos mesmos dados determinísticos.

O fingerprint de conteúdo mantido pela aplicação que grava replay deve incluir o manifest do AttackCatalog, inclusive `CustomDataCanonical`.

## Compatibilidade e testes

Chamadas legadas `AttackInstance.new(attack, owner, idGenerator)` e `AttackInstance.new(attack, owner, idGenerator, explicitId)` permanecem válidas. A cobertura específica está em `src/server/CombatAttackCustomDataTest.server.lua`, `CombatAttackPropertiesTest.server.lua`, `CombatAttackCatalogRollbackTest.server.lua` e `CombatCollisionRollbackTest.server.lua`; a execução depende do runtime Roblox/Studio.
