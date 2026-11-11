# Contributing to CombatAPI

## Before opening a change

1. Read `README.md`, `docs/PUBLIC_API.md`, `docs/Conventions.md`, and the relevant contract document.
2. Keep authoritative gameplay state serializable and deterministic. Do not introduce wall-clock reads or uncontrolled randomness into simulation paths.
3. Preserve the public API boundary. Internal modules are not automatically public because they can be required by path.
4. For snapshot, replay, network, or catalog changes, update the corresponding contract version/migration and tests in the same change.
5. Add or update a focused `*Test.lua` ModuleScript that returns a test function,
   then update `docs/Testing.md` and the inventory in `CombatDocumentationTest.lua`.

## Local validation

Install the pinned Rojo version using Aftman, then run:

```sh
aftman install
rojo build default.project.json -o /tmp/combatapi.rbxlx
python3 scripts/validate_test_inventory.py
python3 scripts/create_test_report.py --output /tmp/combatapi-studio-test-report.md
python3 scripts/validate_wally_package.py
wally package --output /tmp/combatapi-wally-package.zip
```

A CI também gera um place `.rbxlx`, um modelo de relatório e uma prévia privada
do pacote Wally como artefatos. O pacote Wally inclui somente a entrada pública
e a árvore compartilhada; ele ainda não foi publicado no registry. A análise `luau-lsp` dos módulos de contrato estritos
está em fase consultiva; os diagnósticos completos são preservados em um artefato
separado e devem ser revisados antes de torná-la bloqueante.

Open the generated place in Roblox Studio. `CombatTestRunner.server.lua`
executes the `*Test.lua` modules sequentially; `CombatMultiplayerSmokeTest.server.lua`
is run separately with two clients. The suite uses Roblox runtime APIs and is
not executable as a standalone command-line test suite. Do not report Studio
tests as passing unless they were actually run.

## Change requirements

- Keep changes focused and preserve existing call signatures where possible.
- Add migration notes for public or serialized contract changes.
- Update `docs/CHANGELOG.md` using Added/Changed/Fixed/Deprecated/Removed headings as appropriate.
- Include reproduction steps and relevant Studio output when reporting a bug.
- Do not commit generated `.rbxlx` files, credentials, local environment files, or unrelated assets.

## Pull request checklist

- [ ] Rojo build succeeds.
- [ ] Relevant Studio tests pass, or unexecuted tests are explicitly identified.
- [ ] Public API and serialized-contract changes are documented.
- [ ] Rollback/replay behavior is covered when authoritative state changes.
- [ ] No unrelated generated files or secrets are included.
