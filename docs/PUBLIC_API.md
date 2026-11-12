# Public API boundary

This document defines the compatibility boundary for the CombatAPI `0.3.x` development line.

## Stable public surface

The following entry points are public and covered by the package's compatibility policy:

- `CombatAPI.CreateWorld`, `GetContext`, `GetAPIContext`, and `IsWorld`.
- `CombatAPI.APIContext` methods documented in `API.md`, including entity operations, events, feature discovery, and named system lookup.
- `CombatAPI.APIResult`, `APIError`, `EventTypes`, plugin contracts, action definitions/catalogs, replay recordings, and the exported constructors listed below.
- `CombatAPI.Simulation`, `Attack`, `AttackInstance`, `AttackCatalog`, `CollisionTopologyCatalog`, `CollisionWorld`, `Hitbox`, `Hurtbox`, and `OffensiveProperties`.
- World methods explicitly listed in the World accessors section of `API.md`.
- Luau type contracts for the facade, APIContext, events, errors/results, attack properties, collision, rollback, and simulation values are provided by `CombatAPITypes.lua` and re-exported by their public modules. These type exports describe supported consumer shapes; internal resolver objects remain outside the stable boundary or intentionally opaque until their contracts are completed.

The public constructor exports are provided so a consumer can create a World and Simulation, build an attack definition, create per-execution overrides, register collision regions and their versioned rollback factories, and capture/restore combat state without requiring modules from `src/shared/Combat` or `src/shared/Simulation` directly.

## Advanced resolver access

`APIContext:GetSystem(name)` and the named resolver getters return live resolver objects. They are an advanced integration/escape hatch, not an abstraction boundary: resolver methods, internal tables, and concrete implementation details may change in a minor release when they are not separately documented in `API.md` as public contracts.

Prefer, in order:

1. `APIContext` methods and events;
2. documented `World` convenience methods;
3. explicitly exported definition/catalog/region constructors;
4. raw resolvers only when the documented facade does not yet cover a required operation.

A resolver's presence in `GetSystem` does not imply every field or method on that resolver is public. Do not mutate resolver-owned tables directly.

## Internal surface

Modules under `src/shared/Core`, `src/shared/Combat`, `src/shared/Simulation`, `src/shared/Events`, and `src/shared/Plugins` are internal by default unless explicitly exported from `CombatAPI` or documented as a public contract in `API.md` and this document. File paths and `require`-ability are not promises of compatibility.

## Versioning policy

- `CombatAPI.Version` remains the integer API generation for compatibility with existing code.
- `CombatAPI.SemVer` is the package release version. The current development baseline is `0.3.0`.
- **MAJOR**: remove/rename a public member, change its meaning incompatibly, or change a serialized contract without a compatible migration.
- **MINOR**: add a backward-compatible public member, capability, or optional field.
- **PATCH**: backward-compatible bug fixes and documentation corrections.
- Serialized formats are versioned independently in `CombatAPI.Contracts`; a package version bump does not replace schema/manifest migrations.
- Before `1.0.0`, public contracts may still evolve; breaking changes must be documented in `CHANGELOG.md` and migration notes must be provided when practical.
- Deprecation requires at least one documented minor release with a replacement before removal after `1.0.0`, except for security or data-integrity issues.

## Error contract

Public operations that return `APIResult` use:

- `Success`: whether the operation succeeded;
- `Value`: the successful value, or operation-specific failure value;
- `Error`: `nil` on success, otherwise an immutable `APIError` with `Code`, `Message`, `System`, optional `Frame`, and optional `Context`.

`APIError.Code` values are stable identifiers, not user-facing prose. Consumers should branch on `Code`, not `Message`. Messages may become more descriptive between compatible releases. Plugin resolver failures map to the stable API categories: missing plugins/dependencies to `NotFound`, duplicate or conflicting registrations to `AlreadyExists`, disabled plugins to `Disabled`, invalid plugin data to `InvalidArgument`, permission failures to `PermissionDenied`, destroyed Worlds to `Destroyed`, initialization/runtime/stop failures to `InternalError`, and other lifecycle/dependency failures to `InvalidOperation`. The original resolver code remains available in `Error.Context.ResolverCode`; dependency and resolver details are preserved in that context. Unrecognized resolver codes map to `InvalidOperation`.

The recognized `APIError.Code` values are `InvalidArgument`, `InvalidEntity`, `InvalidOperation`, `NotFound`, `AlreadyExists`, `NotInitialized`, `Disabled`, `PermissionDenied`, `InternalError`, and `Destroyed`. `APIError.isCode(value)` can be used to check a code before branching on it. `APIError` and `APIResult` records are shallow-frozen; `Context` is not deep-frozen and must be treated as read-only by consumers. `APIError.fromResolverResult()` copies resolver details into a new context table.
