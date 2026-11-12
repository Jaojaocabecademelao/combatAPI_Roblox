# Public API boundary

This document defines the compatibility boundary for the CombatAPI `0.1.x` development line.

## Stable public surface

The following entry points are public and covered by the package's compatibility policy:

- `CombatAPI.CreateWorld`, `GetContext`, `GetAPIContext`, and `IsWorld`.
- `CombatAPI.APIContext` methods documented in `API.md`, including entity operations, events, feature discovery, and named system lookup.
- `CombatAPI.APIResult`, `APIError`, `EventTypes`, plugin contracts, action definitions/catalogs, replay recordings, and the exported constructors listed below.
- Plugin registration accepts typed `Plugin`, `PluginProfile`, or `PluginProfileOptions` values. Lifecycle results preserve the resolver result shape (`Success`, `Code`, optional `PluginId`, `Value`, and `Details`) inside `APIResult.Value`; `Code` there is a resolver code, distinct from the stable `APIError.Code`.
- `CombatAPI.Attack`, `AttackInstance`, `AttackCatalog`, `CollisionWorld`, `Hitbox`, `Hurtbox`, and `OffensiveProperties`.
- World methods explicitly listed in the World accessors section of `API.md`.

The public constructor exports are provided so a consumer can build an attack definition, create per-execution overrides, register collision regions, and capture/restore combat state without requiring modules from `src/shared/Combat` directly.

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
- `CombatAPI.SemVer` is the package release version. The current development baseline is `0.1.4`.
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

`APIError.Code` values are stable identifiers, not user-facing prose. Consumers should branch on `Code`, not `Message`. Messages may become more descriptive between compatible releases. Resolver-specific result codes remain distinct from `APIError.Code`; plugin facade methods (`CombatAPI.RegisterPlugin`, `StartPlugin`, `StopPlugin`, `UnregisterPlugin`, `EnablePlugin`, `DisablePlugin` and the equivalent `APIContext` methods) map them to the stable codes in the table below and preserve the original value in `Error.Context.ResolverCode`; `Error.Message` carries the same value.

The recognized `APIError.Code` values are `InvalidArgument`, `InvalidEntity`, `InvalidOperation`, `NotFound`, `AlreadyExists`, `NotInitialized`, `Disabled`, `PermissionDenied`, `InternalError`, and `Destroyed`. `APIError.isCode(value)` can be used to check a code before branching on it. `APIError` and `APIResult` records are shallow-frozen; the optional `Context` table is caller-provided and must be treated as read-only by consumers.

### Plugin result mapping

| `APIError.Code` | Resolver result codes |
|---|---|
| `NotFound` | `PluginNotFound`, `CapabilityNotFound`, `DependencyMissing` |
| `AlreadyExists` | `DuplicatePlugin`, `PluginAlreadyOwned`, `CapabilityConflict` |
| `InvalidArgument` | `InvalidPlugin`, `InvalidCapabilityId`, `InvalidCapabilityVersion` |
| `PermissionDenied` | `PermissionDenied`, `CapabilityNotDeclared` |
| `Disabled` | `PluginDisabled` |
| `Destroyed` | `WorldDestroyed` |
| `InternalError` | `InitializationFailed`, `PluginRuntimeFailed`, `StopFailed` (an exception escaped plugin-owned code) |
| `InvalidOperation` | `InvalidLifecycleState`, `PluginActive`, `ActiveDependents`, `DependencyCycle`, `DependencyVersionMismatch`, `DependencyFailed`, and any resolver code not listed here |

Capability codes are returned by plugin contexts as `(value, code)` pairs rather than as `APIResult`; they are included so every known resolver code has a defined mapping. A resolver code added in a future release maps to `InvalidOperation` until it is listed here.
