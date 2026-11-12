# Rollback

Rollback means restore a prior confirmed frame and replay retained inputs. It is distinct from Prediction, which executes speculative frames before confirmation. `World:GetRollbackResolver()` exposes the current World resolver; the caller requests/records snapshots and rollback operations explicitly.

Modules include `RollbackComponent`, `RollbackProfile`, `RollbackState`, `RollbackScope`, `RollbackSnapshot`, `RollbackFrame`, `RollbackHistory`, `RollbackRequest`, `RollbackResolver`, `RollbackResult`, and `RollbackEvent`.

Snapshots are bounded plain serializable values. Stateful Components must implement `CaptureRollbackState()` and `RestoreRollbackState(state)` correctly. RNG and Simulation frame metadata are retained. Replay uses the existing `Simulation:Step` path; there is no parallel loop. World/Simulation expose execution context so game code can suppress irreversible side effects.

## Current support limit

The current implementation does **not** claim complete combat rollback. It rejects unsupported mutable combat state rather than restoring a partial snapshot. CollisionWorld, active combo state, legacy closure callbacks, new deterministic command/event history, and Components without the explicit rollback contract can make capture/restore unavailable. Built-in Damage, collision/contact history, guard, armor, hitstop, motion, and other mutable system state are not all represented by complete reversible hooks. `AuthorityProfile.PastInputPolicy.Rollback` accepts a late input only when a confirmed snapshot immediately before the input frame, complete input history, compatible rollback components, and configured rollback/replay limits are available; otherwise it returns `RollbackUnsupported` without consuming the input sequence.

Direct `RestoreFrame()` refuses to run while a rollback request is pending. After a successful direct restore or replay that ends before the former current frame, PredictionResolver history is truncated to the restored frame; if a participant has no prediction baseline at that exact frame, its prediction state is reset and must be begun again by the caller. This prevents future prediction frames from remaining attached to an older World state.

Read `ROLLBACK_SYSTEM_CHANGES.md` for the recorded implementation boundary and use `CombatRollbackTest.lua` for concrete accepted/rejected cases. Do not interpret a local successful rollback of a supported test World as production-ready match rollback.

`RollbackResolver:GetMetrics()` exposes counters for captured snapshots,
started/completed/failed rollbacks, replayed frames, and current history
occupancy. These counters are intended for diagnostics and benchmark output;
they do not add timing calls to the authoritative simulation path.

The coordinated `CombatStateSchema` path is the supported route for restoring
the entity roster and compatible `CollisionWorld` topology. It does not widen
the legacy `RollbackResolver` contract: unsupported resolvers, callbacks and
components still fail explicitly rather than being partially restored.
An empty collision snapshot can be restored without a `CollisionTopologyCatalog`
only when both the snapshot and current collision topology are empty. Any
non-empty topology still requires a matching, versioned catalog.

`CombatStateSchema:RegisterMigration(fromVersion, migrate)` can register an
explicit migration for each prior schema version. `Restore` applies the chain
to isolated serializable copies before validating the current schema or
staging any live state. Each migration must advance exactly one version. No
historical migration is assumed: when a migration cannot reconstruct state
that an older snapshot never captured, that version must remain rejected.

External environment facts use a separate history from combat snapshots.
Capture that history with `World:GetExternalFactJournal():Capture()` as part of
the host's replay/input archive and retain it across restore. The journal
reuses exact frame/request/adapter matches in `Replay` and `Rollback`; it does
not invoke `Workspace` or restore Roblox physics. See [Integration](Integration.md).

`CombatAPI.ReplayRecording` can package a content fingerprint, initial state,
frame inputs, per-frame external facts and state hashes with a caller-provided
external-fact journal snapshot. It validates contiguous frame numbering,
supports only explicit one-version migrations, and reports the first
input, external-fact, initial-state, or state-hash divergence. It records and compares data; it does not run the
simulation or make an incomplete World rollback-safe.

Snapshots also reject capture while the standalone `MotionResolver` request
queue is pending. That resolver queue has no serializable owner/reconstruction
contract; requests intended to survive a snapshot must be queued on a
rollback-enabled `MotionComponent`, or the standalone queue must be processed
before capture.


## `CustomData` de ataques e compatibilidade

O snapshot do `CollisionWorld` registra somente `CustomDataOverrides` por instância ativa, omitindo o campo quando não há override. Na restauração, o override é aplicado à definição resolvida pelo `AttackCatalog`; o manifest v2 inclui a representação canônica de `CustomData` das definições, permitindo detectar mudança de conteúdo mesmo quando a versão declarada da definição não foi incrementada. Manifests v1 são aceitos somente quando nenhuma definição viva possui `CustomData`; caso contrário, não é possível comprovar equivalência e a validação rejeita o snapshot.

A versão atual de `CombatStateSchema` é **3**. Snapshots v2 são migrados para v3 sem alterar conteúdo (campo de override ausente significa sem override); versões futuras são rejeitadas. Um consumidor antigo não deve tentar restaurar snapshots v3, pois versões anteriores podem ignorar o novo campo. Overrides são validados antes da restauração e obedecem aos limites de 256 valores (a tabela raiz conta)/profundidade 8.

O estado de replay depende de os overrides serem calculados apenas a partir de inputs/estado determinístico. Relógio real e aleatoriedade não determinística não devem influenciar os dados. O fingerprint de conteúdo de uma gravação deve incluir o manifest do `AttackCatalog`, incluindo `CustomDataCanonical`. Este contrato não torna por si só um jogo ou resolver arbitrário rollback-safe; permanecem aplicáveis os limites descritos em [CUSTOMDATA](CUSTOMDATA.md) e neste documento.
