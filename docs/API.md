# CombatAPI and public API

## Entry point

`src/shared/CombatAPI.lua` returns a frozen module table. Current methods and exported types:

`CombatAPI.Version` remains the integer API generation (`1`) for existing
consumers. `CombatAPI.SemVer` reports the package release version (`0.1.4`),
while `CombatAPI.Contracts` exposes independently versioned serialized
contracts, including the attack catalog manifest and combat state schema.
See [PUBLIC_API.md](PUBLIC_API.md) for the compatibility boundary and
versioning/deprecation policy.

`world:GetCombatStateSchema()` includes the combat pipeline, hitstop, combo,
juggle, and cancel resolver providers by default. Collision-derived resolvers
are captured through the attached `CollisionWorld` participant. Additional
authoritative providers can be registered on the returned schema before
capturing a snapshot.
For the normal path, use `world:CaptureCombatState()` and
`world:RestoreCombatState(snapshot)`.
Restore rebuilds the entity roster, so reacquire entities and components by
stable ID after restoration; references held before restore are stale.
`world:HashCombatState(snapshot)` returns the deterministic `state-v1` hash of
a snapshot, or hashes a freshly captured state when no snapshot is supplied.
`world:CompareCombatStates(left, right)` performs canonical detailed comparison
and returns `Equal`, `LeftHash`, and `RightHash`.
`world:GetDiagnostics().ForbiddenOperations` records rejected mutating
operations attempted during rollback/replay.
`world:AssertDeterministicOperation(operation, details)` and
`world:GetDeterminismViolations()` expose the simulation determinism guard for
plugin and adapter code.
Use `world:RegisterGameplayEventHandler` and
`world:ScheduleGameplayEvent` for serializable gameplay timers.
`world:GetGameplayScheduler()` returns the data-only scheduler; the legacy
closure scheduler is available only through compatibility APIs.
For example, replace a closure timer with a registered event:

```lua
simulation:RegisterGameplayEventHandler("combat.cooldown.v1", function(event)
	-- Mutate only authoritative state using event.Parameters.
end)
simulation:ScheduleGameplayEventAfter(30, "combat.cooldown.v1", entityId, {
	Ability = "Dash",
})
```

Use `ScheduleGameplayEvent` when an absolute frame is already known, or
`ScheduleGameplayEventAfter` for a relative delay in simulation frames.
`World` exposes both methods as convenience wrappers.

`world:GetExternalFactJournal()` returns the generic, versioned history for
external data that affects gameplay. `Resolve(frame, queryId, adapterId,
adapterVersion, request, query)` records the serializable request and outcome
in `Normal`/`Authority`, then reads that exact record without calling `query`
in `Prediction`/`Replay`/`Rollback`. Missing or incompatible facts return
`nil, reason`. `Capture()` and `Import(snapshot)` are for the host's durable
replay/input record; journal history is intentionally not erased by restoring
a combat snapshot. See [Integration](Integration.md) for the adapter contract
and retention responsibilities.

`world:GetCombatStateSchema():RegisterMigration(fromVersion, migrate)` adds an
explicit one-version-at-a-time snapshot migration. The callback receives a
serializable copy and must return a new compatible table with `Version`
advanced by exactly one. `RestoreCombatState` applies registered migrations
before validating or mutating the World. No migration is built in for an old
snapshot whose omitted state cannot be reconstructed; without a complete
migration chain, restore rejects it without partial restoration.

`simulation:GetLegacyScheduler()` and `simulation:GetScheduler()` remain
available for migration and presentation-only compatibility. Their callbacks
are Lua closures and are not part of `Simulation:CaptureState()` or the
coordinated combat snapshot; pending legacy callbacks therefore cannot be
restored or replayed as authoritative gameplay state.
The rollback resolver stores the coordinated combat snapshot alongside its
legacy frame record, so configured collision and gameplay providers participate
in restore/replay. Snapshots imported without `CombatState` use the legacy
compatibility path and have its narrower limits.
When a `CollisionWorld` is attached, its collision-derived resolvers and
hit-history state are captured through the single collision participant. They
must not be registered again as independent state providers.
Use `world:RegisterCombatComponentFactory(key, factory)` and
`world:RegisterCombatStateProvider(key, provider)` when registering them after
world creation. Both operations are rejected during rollback/replay.

For providers that must be present from world creation, pass
`World.new({ StateProviders = { ["feature.state.v1"] = provider } })`. Providers
must implement `CaptureRollbackState`, `ValidateRollbackState`, and
`PrepareRollbackRestore`.

Component factories required by those snapshots can be installed with
`World.new({ ComponentFactories = { ["feature.component.v1"] = factory } })`.
Factories receive `(entity, state, context)` and must return a compatible
rollback component.
The world also registers default factories for core health, defense, hitstop,
combo, juggle, motion, movement, offensive, protection, input, cancel,
armor, guard, rollback, and status-container components. Custom factories with
the same keys take precedence.
`ResourceComponent` provides deterministic named resources with bounded
consume/restore operations and is also registered by default.
Action definitions may declare `Requirements.Resources` and
`Costs.Resources`; they may also require `RequiredStatusTags`, exclude
`ForbiddenStatusTags`, and restrict `MovementStates`. The pipeline validates
all declared requirements before starting and consumes costs only after they
pass. Movement-gated actions report `MissingMovementState` when the entity has
no `MovementStateComponent`, and `MovementStateRequirementFailed` when its
current state is outside the declared set.
`DurationModel` supports `Phased` (the default Startup/Active/Recovery cycle),
`Instant` (one simulation frame), and `Persistent` (active until cancelled).
For content that must be validated and pinned across rollback, register
definitions with `CombatAPI.CombatActionCatalog`, assign a positive integer
content version, seal the catalog, and pass it to
`world:GetCombatPipeline():RegisterCatalog(catalog)`. Catalog-backed pipeline
snapshots include the action manifest and reject missing or incompatible
content. `MigrateDefinitionData(id, fromVersion, toVersion, data)` only runs
explicitly registered, one-way migration callbacks; it does not guess how to
repair missing or incompatible fields.

`CombatAPI.ReplayRecording` stores a content fingerprint, initial serializable
state, optional external-fact journal, contiguous frame inputs, optional
per-frame facts, and a caller-provided state hash for each frame. Load it with
`ReplayRecording.FromSnapshot(snapshot, migrations)`; old versions require
explicit one-version migration callbacks. `FindFirstDivergence(other)` reports
the first initial-state, input, per-frame fact, or state-hash mismatch. The
host still owns simulation execution, hash calculation, retention/privacy
policy, and loading the external-fact journal into the World before replay.

Statuses may declare `Tags` and finite numeric `Modifiers`. A
`StatusContainer` exposes `HasTag`, `GetModifier`, and `RemoveByTag`; modifiers
from active enabled statuses are summed, including stacked statuses. Consumers
decide how tags and modifiers affect their rules. `Status.new` also accepts
`PeriodicEffects` entries with a stable `Id`, `Type` (`DamageOverTime` or
`HealingOverTime`), positive `Amount`, and `IntervalFrames`. Periodic effects
advance on simulation frames (and pause with the existing status hitstop
behavior), restore their elapsed intervals, and resolve through
`DamageResolver`. Add the status only after its entity has a `HealthComponent`
and the World has an attached `CollisionWorld`/`DamageResolver`. These direct
effects do not run collision, defense, armor, or hitstun rules; implement a
custom versioned status/resolver if a game needs different semantics.
Refresh and Extend reapplication reset the existing status's periodic
intervals; Stack creates an independent timer set for the new instance.

`world:RespawnEntity(entityOrId, options)` replaces an entity while preserving
its stable ID, clears resolver references through the normal destruction path,
and publishes lifecycle events.

`world:DisconnectPeer(peerId, { DestroyOwnedEntities = true })` disconnects the
network peer, releases authority ownership, and optionally destroys its owned
entities through the normal lifecycle path.

Character lifecycle can use `world:AttachCharacter`, `world:DetachCharacter`,
and `world:ReattachCharacter`; these delegate to the configured character
resolver and reject mutation during rollback/replay.
`world:GetCharacterRoot(entityOrId)` and
`world:GetCharacterPart(entityOrId, partName)` expose presentation lookups
through the active adapter.
The default `RobloxHumanoid` adapter validates Roblox `Model` instances with a
`Humanoid` and exposes root/body-part lookup without putting Instances in
authoritative snapshots.
`CombatAPI.RobloxRemoteEventAdapter` adapts a Roblox `RemoteEvent` to the
network resolver. Configure `Role`, `GetPlayer` (server), `GetPeerId`, and
`OnReceive`, call `Start`, and register its transport with the resolver.
Plugin profiles use `Scope = "Gameplay"` (default) or `Scope =
"Presentation"`. Use `ListPluginsByScope` to keep authoritative state
providers separate from presentation adapters.

```lua
CombatAPI.CreateWorld(options)
CombatAPI.GetContext(world)
CombatAPI.GetAPIContext(world)
CombatAPI.IsWorld(value)
CombatAPI.GetPluginResolver(world)
CombatAPI.RegisterPlugin(world, plugin, implementation)
CombatAPI.StartPlugin(world, id)
CombatAPI.StopPlugin(world, id)
CombatAPI.EnablePlugin(world, id)
CombatAPI.DisablePlugin(world, id)
CombatAPI.UnregisterPlugin(world, id)
```

The module exports `APIContext`, `EventTypes`, `APIResult`, `APIError`, `Plugin`,
`PluginCapability`, `PluginContext`, `PluginProfile`, `PluginState`,
`Simulation`, `CombatActionProfiles`, `CombatActionCatalog`, `ReplayRecording`, `Attack`,
`AttackInstance`, `AttackCatalog`, `CollisionWorld`, `Hitbox`, `Hurtbox`, and
`OffensiveProperties`. The profiles expose definition-only `Melee()`,
`Projectile()`, and `AreaOfEffect()` examples for the shared action pipeline.
Create a simulation with `CombatAPI.Simulation.new(world)` before capturing or
restoring combat snapshots; this associates the simulation clock with the World.
Its options include `FixedDeltaTime`, `MaxStepsPerUpdate`, and `Seed`.
Collision snapshots containing hitboxes or hurtboxes also require a sealed
`CollisionTopologyCatalog` attached with `collisionWorld:SetTopologyCatalog`.
Register a versioned factory for each region definition and set the matching
`TopologyDefinitionId` and `TopologyDefinitionVersion` on each region; these
factories let restore rebuild missing regions deterministically.
Plugin callbacks receive `PluginContext`, which exposes `GetCapability` and
`RegisterCapability` for extension-owned capabilities keyed by identifier; the
capability record includes `Id`, `Version`, `Implementation`, and
`OwnerPluginId`. `GetRegistry()` returns a read-only query view with plugin and
capability lookup/list operations. `RegisterCapability` returns two values:
the capability on success, or a stable code such as `CapabilityConflict`,
`CapabilityNotDeclared`, `InvalidCapabilityId`, `InvalidCapabilityVersion`,
or `InvalidContext` on failure.
Plugin, dependency, and capability versions use the numeric `major.minor.patch`
form; malformed capability versions are returned as `InvalidCapabilityVersion`.
`GetEventBus()` returns the World's shared EventBus; the public Luau contract
describes its subscription, dispatch, error-query, and teardown methods.
The context and its registry view become invalid when the plugin stops; a
retained registry view then returns empty/false results rather than accessing
the destroyed resolver, and context-owned subscriptions/capabilities are
released. `CombatAPITypes.lua` is a sibling type-only module; import its types
with `type CombatTypes = require(ReplicatedStorage.Shared.CombatAPITypes)`.
The module exports the `CombatAPI`, `APIContext`, `World`, `APIResult<T>`,
`APIError`, `Event`, `Attack`, `AttackOptions`, `AttackInstance`,
`AttackInstanceOptions`, `OffensiveProperties`, and `CustomData` contracts.
The public entry module is cast to `CombatTypes.CombatAPI`, so consumers using
Luau type checking receive signatures for the public constructors and facade.

Example:

```lua
local CombatAPI = require(ReplicatedStorage.Shared.CombatAPI)
type CombatTypes = require(ReplicatedStorage.Shared.CombatAPITypes)

local pluginProfile: CombatTypes.PluginProfileOptions = {
    Id = "gameplay.ai",
    Name = "Gameplay AI",
    Version = "1.0.0",
    Capabilities = { "gameplay.ai.retarget" },
}
local plugin: CombatTypes.Plugin = CombatAPI.Plugin.new(pluginProfile, {
    Initialize = function(context)
        local capability = context:RegisterCapability("gameplay.ai.retarget", {
            Retarget = function(target) return target end,
        }, "1.0.0")
        return capability ~= nil
    end,
})

local attackOptions: CombatTypes.AttackOptions = {
    Id = "ChargedStrike",
    Damage = 12,
    CustomData = { Radius = 2, Element = "Arcane" },
}
local attack: CombatTypes.Attack = CombatAPI.Attack.new(attackOptions)
local override: CombatTypes.AttackInstanceOptions = {
    CustomDataOverrides = { Radius = 5 },
}
```

Raw resolver getters intentionally return `any` in the public type contract:
they are advanced escape hatches, not the stable abstraction boundary. Prefer
`APIContext` methods and documented `World` methods for integrations.

A complete consumer-side example using only exported constructors is available
at [examples/CustomDataConsumer.server.lua](examples/CustomDataConsumer.server.lua).
`CombatAPI.Contracts` reports the versions of the network message, action
definition, action catalog manifest, and replay recording formats.

## Attacks: `CustomData` por definição e instância

`Attack.new({ CustomData = data })` aceita dados opcionais para consumidores de gameplay. O mesmo valor é exposto em `attack.CustomData` e `attack.OffensiveProperties.CustomData`. O conteúdo é opaco para a API: use tabelas simples serializáveis, sem metatables, ciclos, funções, Instances/userdata ou números não finitos. O limite é 256 valores (a tabela raiz conta, então até 255 chaves em uma tabela plana) e profundidade 8; `{}` é normalizado para `nil`. Os dados são copiados defensivamente e congelados recursivamente.

Para fornecer valores específicos para uma execução sem alterar a definição, use o quarto argumento em formato de opções:

```lua
local attack = Attack.new({ Id = "ChargedStrike", CustomData = { Radius = 2, Mode = "Arc" } })
local instance = AttackInstance.new(attack, owner, idGenerator, {
    CustomDataOverrides = { Radius = 5 },
})
-- CustomData efetivo da instância: { Radius = 5, Mode = "Arc" }
```

O merge é raso: chaves do override substituem as da definição; tabelas aninhadas são substituídas integralmente. Sem override, `AttackInstance.OffensiveProperties` compartilha as propriedades congeladas do ataque. O argumento escalar legado do quarto parâmetro continua sendo o ID explícito. `CustomDataOverrides` aceita as mesmas regras de serialização e limites.

`HitConfirmed` e `DamageApplied` incluem `CustomData` nas propriedades ofensivas do hit/dano. O valor é `nil` quando ausente e, quando presente, é a referência congelada. `HitProcessor` preserva o dado também ao completar propriedades com valores provenientes da hitbox. O override é preservado tanto no rollback in-place quanto na reconstrução da topologia. Veja [CUSTOMDATA](CUSTOMDATA.md) para o contrato completo de determinismo e compatibilidade.

## World accessors

The following accessors exist in `src/shared/Core/World.lua`:

| Area | Accessors |
|---|---|
| Entities / API | `CreateEntity`, `GetEntity`, `HasEntity`, `DestroyEntity`, `RespawnEntity`, `DisconnectPeer`, `AttachCharacter`, `DetachCharacter`, `ReattachCharacter`, `GetCharacterRoot`, `GetCharacterPart`, `GetEntities`, `GetCombatAPI`, `GetAPIContext`, `GetEvents`, `GetDiagnostics`, `GetDeterminismViolations`, `GetExecutionContext`, `GetExternalEffectGate`, `GetCombatStateSchema`, `RegisterCombatComponentFactory`, `RegisterCombatStateProvider`, `RegisterGameplayEventHandler`, `ScheduleGameplayEvent`, `ScheduleGameplayEventAfter`, `GetGameplayScheduler`, `CaptureCombatState`, `RestoreCombatState`, `HashCombatState`, `CompareCombatStates`, `SetCollisionWorld`, `GetCollisionWorld` |
| Simulation / collision | `GetSimulation`, `GetCollisionWorld`, `GetDamageResolver`, `GetStatusEffectResolver`, `GetReactionResolver`, `GetDefenseResolver`, `GetCombatResolver`, `GetMotionResolver` |
| Collision pipeline data | `GetCombatResolutionEvents`, `GetCounterResults`, `GetDamageRequests`, `GetDamageEvents`, `GetHealthChangedEvents`, `GetDeathEvents`, `GetDefenseEvents`, `GetMotionResults` |
| Protection / consequences | `GetProtectionResolver`, `GetProtectionResults`, `GetArmorResolver`, `GetArmorResults`, `GetGuardResolver`, `GetGuardEvents`, `GetGuardResults`, `GetHitstopResolver`, `GetTimeEffectResults` |
| Combo / Juggle | `GetComboResolver`, `GetComboEvents`, `GetComboResults`, `GetJuggleResolver`, `GetJuggleEvents`, `GetJuggleResults` |
| Input / state | `GetInputResolver`, `GetInputEvents`, `GetMovementStateResolver`, `GetCancelResolver`, `GetCancelEvents`, `GetCancelResults` |
| Integrations | `GetCharacterResolver`, `GetCharacterEvents`, `GetCharacterResults`, `GetAnimationResolver`, `GetAnimationEvents`, `GetAnimationResults` |
| Network / online | `GetNetworkResolver`, `GetNetworkEvents`, `GetNetworkResults`, `GetPredictionResolver`, `GetPredictionEvents`, `GetPredictionResults`, `GetReconciliationResolver`, `GetReconciliationResults`, `GetRollbackResolver`, `GetRollbackEvents`, `GetRollbackResults`, `GetAuthorityResolver`, `GetAuthorityEvents`, `GetAuthorityResults`, `GetPluginResolver` |
| Action pipeline | `GetCombatPipeline`, `GetCombatActionEvents`, `GetCombatActionResults` |

Some accessors return `nil` before an optional pipeline is supplied. In particular, `CollisionWorld`, Simulation, and collision-derived resolvers require setup; resolvers constructed by `World.new` are listed in [Architecture](Architecture.md).

## APIContext

`world:GetCombatAPI()` and `world:GetAPIContext()` return the same World-owned `APIContext`. It exposes guarded entity operations (`GetEntity`, `CreateEntity`, `DestroyEntity`), event access/subscription, system lookup (`GetSystem`, `HasSystem`, `HasFeature`), named resolver getters, and Plugin lifecycle convenience methods. Methods return `APIResult` where implemented; a failed result includes an `APIError`.

`APIContext:GetPlugin(id)` requires a non-empty string ID. It returns `InvalidArgument` for malformed IDs, `NotFound` for an unknown plugin, and `Destroyed` after the context is destroyed.

`APIResult` fields are `Success`, `Value`, and `Error`. `APIError` fields are `Code`, `Message`, `System`, `Frame`, and `Context`. Expected validation/operation failures are results; malformed constructors and programmer contract violations may still raise assertions.

## Public vs internal

The stable consumption surface is the exported `CombatAPI`, `World` public methods, system constructors/data types, named Resolver methods, Results, and EventBus contract documented here. Underscore-prefixed resolver helpers, internal tables, collision pair caches, rollback internals, and direct mutation of Resolver-owned collections are implementation details. Do not write to fields such as `World.EntityRegistry.Entities` or Resolver queues; use public methods and Results.

The World getter currently returns Resolver objects for direct use, so the boundary is a documented API convention rather than a security sandbox. Plugin code is trusted project code; `PluginContext` scopes extension ownership but does not sandbox arbitrary Lua modules.
