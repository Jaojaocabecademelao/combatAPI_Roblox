# CombatAPI

Framework modular de combate para Roblox, com simulação por frames, colisão,
catálogos versionados, eventos, rollback, replay e integração de rede.

## Requisitos

- Roblox Studio
- Rojo 7.7.1 (versão fixada em `aftman.toml`)
- Aftman para instalar a toolchain declarada (Rojo, luau-lsp e Wally)

## Começar

Na raiz do repositório:

```sh
aftman install
rojo serve default.project.json
```

No Roblox Studio, conecte o plugin Rojo ao servidor local. O mapeamento ativo é:

```text
ReplicatedStorage
└── Shared        <- src/shared
ServerScriptService
└── Server        <- src/server
```

Para gerar um place:

```sh
rojo build default.project.json -o combatapi.rbxlx
```

## Exemplo de `CustomData`

A API pública exporta `Attack`, `AttackInstance`, `AttackCatalog`,
`CollisionWorld`, `Hitbox` e `Hurtbox`. Veja
[`docs/examples/CustomDataConsumer.server.lua`](docs/examples/CustomDataConsumer.server.lua)
para um consumidor que cria overrides por instância e captura/restaura estado
sem importar módulos internos diretamente.

## Testes

Os módulos `*Test.lua` ficam em `src/server` e são executados em sequência pelo
`CombatTestRunner.server.lua` no Roblox Studio. Consulte
[`docs/Testing.md`](docs/Testing.md). A CI valida o JSON e o inventário, gera o place Rojo e uma prévia de pacote Wally
privado. Os artefatos incluem um modelo para registrar a execução manual no Studio.
A análise Luau dos módulos de contrato é consultiva e seus diagnósticos são
publicados separadamente como artefato; a CI ainda não executa os testes de runtime do Roblox.

## Contratos e contribuições

- [`docs/API.md`](docs/API.md): referência da API.
- [`docs/PUBLIC_API.md`](docs/PUBLIC_API.md): fronteira pública e versionamento.
- [`docs/Conventions.md`](docs/Conventions.md): convenções de determinismo.
- [`docs/Rollback.md`](docs/Rollback.md): snapshot e restauração.
- [`docs/CHANGELOG.md`](docs/CHANGELOG.md): histórico de mudanças.
- [`CONTRIBUTING.md`](CONTRIBUTING.md): validação e contribuições.

## Wally

O manifesto `wally.toml` e `src/init.lua` preparam uma prévia privada do pacote.
A distribuição ainda não está publicada no registry; veja as condições em
[`docs/Testing.md`](docs/Testing.md).

Licença: MIT. Consulte [`LICENSE`](LICENSE).
