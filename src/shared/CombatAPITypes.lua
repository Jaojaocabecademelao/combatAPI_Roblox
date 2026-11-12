--!strict
-- Public type contracts. Runtime values are intentionally empty; consumers
-- import these definitions with `type Types = require(path.CombatAPITypes)`.

export type Primitive = nil | boolean | number | string
export type SerializableValue = Primitive | { [string | number]: SerializableValue }
export type CustomData = { [string | number]: SerializableValue }
export type EntityId = string | number
export type IdGenerator = {
	Next: (self: any) -> number,
}
export type CombatEntity = {
	Id: EntityId,
	World: { IdGenerator: IdGenerator }?,
}
export type Damage = number | { Amount: number, Type: string? }
export type Defense = { CanBlock: boolean?, CanParry: boolean? }
export type ResolvedDefense = { CanBlock: boolean, CanParry: boolean }

export type OffensiveProperties = {
	Damage: Damage?,
	Hitstun: number,
	HitstunFrames: number,
	HasHitstun: boolean,
	Defense: ResolvedDefense,
	Priority: number,
	CanClash: boolean,
	CustomData: CustomData?,
}

export type OffensivePropertiesOptions = {
	Damage: Damage?,
	CustomData: CustomData?,
	Hitstun: number?,
	HasHitstun: boolean?,
	Defense: Defense?,
	CanBlock: boolean?,
	CanParry: boolean?,
	Priority: number?,
	CanClash: boolean?,
}

export type OffensivePropertiesConstructor = {
	new: (options: OffensivePropertiesOptions?) -> OffensiveProperties,
	WithCustomData: (properties: OffensiveProperties, customData: CustomData?) -> OffensiveProperties,
}

export type AttackOptions = {
	Id: EntityId?,
	Damage: Damage?,
	Hitstun: number?,
	Priority: number?,
	CanClash: boolean?,
	Defense: Defense?,
	CanBlock: boolean?,
	CanParry: boolean?,
	CustomData: CustomData?,
	HitPolicy: string?,
	HitScope: string?,
	CanHit: ((any, any) -> boolean)?,
}

export type Attack = {
	Id: EntityId,
	HitPolicy: string,
	HitScope: string,
	OffensiveProperties: OffensiveProperties,
	Priority: number,
	CanClash: boolean,
	CustomData: CustomData?,
	Damage: Damage?,
	Hitstun: number?,
	Defense: ResolvedDefense,
	CanHit: ((any, any) -> boolean)?,
}

export type AttackConstructor = {
	new: (options: AttackOptions?) -> Attack,
}

export type AttackInstanceOptions = {
	Id: EntityId?,
	CustomDataOverrides: CustomData?,
}

-- The fourth constructor argument accepts either the legacy explicit ID or
-- the options record. This preserves AttackInstance.new(..., 42) callers.
export type AttackInstanceConstructorOptions = EntityId | AttackInstanceOptions

export type AttackInstance = {
	Id: EntityId,
	Attack: Attack,
	OwnerEntity: CombatEntity?,
	OffensiveProperties: OffensiveProperties,
	CustomDataOverrides: CustomData?,
	Priority: number,
	CanClash: boolean,
	State: string,
	GetOffensiveProperties: (self: AttackInstance) -> OffensiveProperties,
	Activate: (self: AttackInstance) -> AttackInstance,
	GetOffensiveProperties: (self: AttackInstance) -> OffensiveProperties,
	Finish: (self: AttackInstance) -> boolean,
	Destroy: (self: AttackInstance) -> boolean,
}

export type AttackInstanceConstructor = {
	new: (
		attack: Attack,
		ownerEntity: CombatEntity?,
		idGenerator: IdGenerator?,
		options: (AttackInstanceOptions | EntityId)?
	) -> AttackInstance,
}

export type APIErrorCode =
	"InvalidArgument" | "InvalidEntity" | "InvalidOperation" | "NotFound"
	| "AlreadyExists" | "NotInitialized" | "Disabled" | "PermissionDenied"
	| "InternalError" | "Destroyed"

export type APIError = {
	Code: APIErrorCode,
	Message: string,
	System: string?,
	Frame: number?,
	Context: { [string]: any }?,
}

export type APIResult<T> =
	{ Success: true, Value: T?, Error: nil }
	| { Success: false, Value: T?, Error: APIError }

export type ResolverFailure = {
	Success: false,
	Code: string,
	PluginId: string?,
	Details: any?,
}

export type APIErrorConstructor = {
	Code: { [string]: APIErrorCode },
	new: (
		code: APIErrorCode,
		message: string,
		system: string?,
		frame: number?,
		context: { [string]: any }?
	) -> APIError,
	isCode: (value: any) -> boolean,
	fromResolverResult: (
		result: ResolverFailure,
		system: string?,
		frame: number?
	) -> APIError,
}

export type APIResultConstructor = {
	new: <T>(success: boolean, value: T?, error: APIError?) -> APIResult<T>,
	is: (value: any) -> boolean,
}

export type EventType =
	"EntityCreated" | "EntityDestroyed" | "EntityRespawned" | "HitConfirmed"
	| "HitRejected" | "DamageApplied" | "HealApplied" | "StatusEffectApplied"
	| "Death" | "Block" | "Parry" | "GuardBreak" | "ComboStarted" | "ComboUpdated"
	| "ComboEnded" | "JuggleStarted" | "JuggleEnded" | "MovementStateChanged"
	| "CancelAllowed" | "CancelRejected" | "InputPressed" | "InputReleased"
	| "PredictionDiverged" | "FrameConfirmed" | "RollbackStarted" | "RollbackCompleted"
	| "RollbackFailed" | "AuthorityInputAccepted" | "AuthorityInputRejected"
	| "AuthoritySnapshotPublished" | "Clash" | "ArmorApplied" | "MotionApplied"
	| "HitstopStarted" | "HitstopEnded" | "CounterHit" | "ProtectionApplied"
	| "PluginRegistered" | "PluginInitializing" | "PluginStarted" | "PluginStopping"
	| "PluginStopped" | "PluginFailed" | "PluginEnabled" | "PluginDisabled"
	| "PluginDependencyFailed" | "PluginCapabilityRegistered"
	| "PluginCapabilityUnregistered"

export type EventTypes = { [string]: EventType }

export type HitConfirmedPayload = {
	AttackerId: EntityId?,
	DefenderId: EntityId?,
	AttackInstanceId: EntityId?,
	HitboxId: number?,
	HurtboxId: number?,
	CustomData: CustomData?,
}

export type DamageAppliedPayload = {
	AttackerId: EntityId?,
	DefenderId: EntityId?,
	Amount: number,
	RequestedAmount: number?,
	AttackInstanceId: EntityId?,
	CustomData: CustomData?,
}

export type AttackCatalog = {
	Register: (self: AttackCatalog, attack: Attack, version: string | number) -> Attack,
	Get: (self: AttackCatalog, id: EntityId) -> Attack?,
	GetVersion: (self: AttackCatalog, id: EntityId) -> (string | number)?,
	Resolve: (self: AttackCatalog, id: EntityId, expectedVersion: (string | number)?) -> (Attack?, any?),
	Seal: (self: AttackCatalog) -> AttackCatalog,
	CaptureManifest: (self: AttackCatalog) -> any,
	ValidateManifest: (self: AttackCatalog, manifest: any) -> (boolean, string?),
}

export type AttackCatalogConstructor = {
	new: () -> AttackCatalog,
}

export type CollisionShape = "Box" | "Sphere"

export type CollisionRegionOptions = {
	Owner: CombatEntity?,
	Shape: CollisionShape?,
	Position: Vector3?,
	Rotation: CFrame | Vector3?,
	Orientation: CFrame | Vector3?,
	Size: Vector3?,
	Radius: number?,
	Enabled: boolean?,
	TopologyDefinitionId: string?,
	TopologyDefinitionVersion: string | number?,
	IdGenerator: IdGenerator?,
}

export type HitboxOptions = CollisionRegionOptions & {
	Id: number?,
	AttackId: EntityId?,
	Priority: number?,
	ClashGroup: string?,
	Damage: Damage?,
	Hitstun: number?,
	HitPolicy: string?,
	HitScope: string?,
	CanHit: ((any, any) -> boolean)?,
}

export type HurtboxOptions = CollisionRegionOptions & {
	Id: number?,
}

export type Hitbox = HitboxOptions & {
	Id: number?,
	CombatRegionType: "Hitbox",
	Shape: CollisionShape,
	Position: Vector3,
	Rotation: CFrame,
	Enabled: boolean,
	Size: Vector3,
	Radius: number?,
	AttackInstance: AttackInstance?,
	AttackId: EntityId?,
	PriorityOverride: number?,
	Priority: number,
	ClashGroup: string?,
	Damage: Damage?,
	Hitstun: number?,
	HitPolicy: string?,
	HitScope: string?,
	CanHit: ((any, any) -> boolean)?,
}

export type Hurtbox = HurtboxOptions & {
	Id: number?,
	CombatRegionType: "Hurtbox",
	Position: Vector3,
	Rotation: CFrame,
	Enabled: boolean,
	Shape: CollisionShape,
	Size: Vector3,
	Radius: number?,
}

export type RegisteredHitbox = Hitbox & {
	Id: number,
}

export type RegisteredHurtbox = Hurtbox & {
	Id: number,
}

export type CollisionRegionSnapshotBase = {
	Id: number,
	OwnerEntityId: EntityId?,
	CombatRegionType: "Hitbox" | "Hurtbox",
	TopologyDefinitionId: string,
	TopologyDefinitionVersion: string | number,
	Position: { number },
	Rotation: { number },
	Enabled: boolean,
	PriorityOverride: number?,
	Priority: number?,
	ClashGroup: string?,
	Damage: Damage?,
	Hitstun: number?,
	HitPolicy: string?,
	HitScope: string?,
	HasCanHitCallback: boolean,
	AttackInstanceId: EntityId?,
}

export type CollisionBoxSnapshot = CollisionRegionSnapshotBase & {
	Shape: "Box",
	Size: { number },
}

export type CollisionSphereSnapshot = CollisionRegionSnapshotBase & {
	Shape: "Sphere",
	Radius: number,
}

export type CollisionRegionSnapshot = CollisionBoxSnapshot | CollisionSphereSnapshot

export type CollisionTopologyFactory = (
	saved: CollisionRegionSnapshot,
	owner: CombatEntity?
) -> Hitbox | Hurtbox

export type CollisionTopologyCatalog = {
	Register: (
		self: CollisionTopologyCatalog,
		id: string,
		version: string | number,
		factory: CollisionTopologyFactory
	) -> CollisionTopologyCatalog,
	Resolve: (
		self: CollisionTopologyCatalog,
		id: string,
		version: (string | number)?
	) -> (CollisionTopologyFactory?, any?),
	CreateRegion: (
		self: CollisionTopologyCatalog,
		saved: CollisionRegionSnapshot,
		owner: CombatEntity?
	) -> ((Hitbox | Hurtbox)?, string?),
	Seal: (self: CollisionTopologyCatalog) -> CollisionTopologyCatalog,
	CaptureManifest: (self: CollisionTopologyCatalog) -> any,
	ValidateManifest: (self: CollisionTopologyCatalog, manifest: any) -> (boolean, string?),
}

export type CollisionTopologyCatalogConstructor = {
	new: () -> CollisionTopologyCatalog,
}

export type CollisionWorld = {
	SetAttackCatalog: (self: CollisionWorld, catalog: AttackCatalog?) -> CollisionWorld,
	SetTopologyCatalog: (self: CollisionWorld, catalog: CollisionTopologyCatalog?) -> CollisionWorld,
	RegisterHitbox: (self: CollisionWorld, hitbox: Hitbox) -> RegisteredHitbox,
	RegisterHurtbox: (self: CollisionWorld, hurtbox: Hurtbox) -> RegisteredHurtbox,
	RemoveHitbox: (self: CollisionWorld, hitbox: Hitbox | number) -> boolean,
	RemoveHurtbox: (self: CollisionWorld, hurtbox: Hurtbox | number) -> boolean,
	GetHitboxes: (self: CollisionWorld) -> { RegisteredHitbox },
	GetHurtboxes: (self: CollisionWorld) -> { RegisteredHurtbox },
}

export type EventFilterOptions = {
	Priority: number?,
	Filter: { [string]: any }?,
	EntityId: EntityId?,
	SourceSystem: string?,
	AttackerId: EntityId?,
	DefenderId: EntityId?,
	Predicate: ((Event) -> boolean)?,
}

export type Event = {
	Type: string,
	SimulationFrame: number?,
	Frame: number?,
	SourceSystem: string,
	EntityId: EntityId?,
	Version: number,
	Sequence: number?,
	EventId: string?,
	ExecutionMode: string,
	Payload: { [string]: any },
	Context: APIContext?,
	CustomData: CustomData?,
	[string]: any,
}

export type EventFilter = EventFilterOptions & {
	Matches: (self: EventFilter, event: Event) -> boolean,
}

export type EventCallback = (event: Event, context: any) -> ()
export type EventSubscription = {
	Disconnect: (self: EventSubscription) -> boolean,
	IsConnected: (self: EventSubscription) -> boolean,
	GetId: (self: EventSubscription) -> number,
}
export type EventSubscriptionOptions = EventFilterOptions & {
	Priority: number?,
	Filter: EventFilterOptions?,
}

export type EventBus = {
	Subscribe: (self: EventBus, eventType: string, callback: EventCallback, options: EventSubscriptionOptions?) -> (EventSubscription?, APIError?),
	Unsubscribe: (self: EventBus, id: number) -> boolean,
	Dispatch: (self: EventBus, eventType: string, payload: { [string]: any }?, context: { [string]: any }?) -> (Event?, APIError?),
	GetErrors: (self: EventBus) -> { APIError },
	ClearErrors: (self: EventBus) -> EventBus,
	Destroy: (self: EventBus) -> boolean,
}

export type PluginDependency = string | {
	PluginId: string,
	MinVersion: string?,
	Optional: boolean?,
}

export type PluginProfileOptions = {
	Id: string,
	Name: string,
	Version: string,
	Dependencies: { PluginDependency }?,
	Capabilities: { string }?,
	AutoStart: boolean?,
	Priority: number?,
	Scope: ("Gameplay" | "Presentation")?,
}

export type PluginProfile = {
	Id: string,
	Name: string,
	Version: string,
	Dependencies: { { PluginId: string, MinVersion: string?, Optional: boolean } },
	Capabilities: { string },
	AutoStart: boolean,
	Priority: number,
	Scope: "Gameplay" | "Presentation",
}

export type PluginLifecycleState =
	"Registered" | "Initializing" | "Active" | "Stopping" | "Stopped" | "Failed"

export type Plugin = {
	Profile: PluginProfile,
	Id: string,
	Name: string,
	Version: string,
	Scope: "Gameplay" | "Presentation",
	State: PluginLifecycleState,
	Enabled: boolean?,
	Failure: string?,
	Context: PluginContext?,
}

export type PluginImplementation = {
	Initialize: ((context: PluginContext, plugin: Plugin) -> boolean?)?,
	Start: ((context: PluginContext, plugin: Plugin) -> boolean?)?,
	Stop: ((context: PluginContext, plugin: Plugin) -> boolean?)?,
}

export type PluginCapability = {
	Id: string,
	Version: string,
	Implementation: any?,
	OwnerPluginId: string,
}

export type PluginRegistryView = {
	Get: (self: PluginRegistryView, id: string) -> Plugin?,
	Has: (self: PluginRegistryView, id: string) -> boolean,
	List: (self: PluginRegistryView) -> { Plugin },
	HasCapability: (self: PluginRegistryView, id: string) -> boolean,
	GetCapability: (self: PluginRegistryView, id: string) -> PluginCapability?,
	ListCapabilities: (self: PluginRegistryView) -> { PluginCapability },
}

export type PluginContextErrorCode =
	"InvalidContext"
	| "InvalidArgument"
	| "InvalidCapabilityId"
	| "InvalidCapabilityVersion"
	| "CapabilityNotDeclared"
	| "CapabilityConflict"
	| "UnsupportedExtensionKind"

export type PluginContext = {
	GetWorld: (self: PluginContext) -> World?,
	GetAPI: (self: PluginContext) -> APIContext?,
	GetEventBus: (self: PluginContext) -> EventBus?,
	GetRegistry: (self: PluginContext) -> PluginRegistryView?,
	GetCapability: (self: PluginContext, id: string) -> PluginCapability?,
	RegisterCapability: (self: PluginContext, id: string, implementation: any?, version: string?) -> (PluginCapability?, PluginContextErrorCode?),
	Subscribe: (self: PluginContext, eventType: string, callback: (Event, APIContext, PluginContext) -> (), options: EventSubscriptionOptions?) -> (EventSubscription?, APIError | PluginContextErrorCode?),
	Register: (self: PluginContext, kind: string, id: string, implementation: any?, version: string?) -> (PluginCapability?, PluginContextErrorCode?),
	IsValid: (self: PluginContext) -> boolean,
}

export type PluginResolverResult = {
	Success: boolean,
	Code: string,
	PluginId: string?,
	Value: Plugin?,
	Details: (string | { [string]: any })?,
}

export type SystemName =
	"Simulation" | "Input" | "Collision" | "Damage" | "Defense"
	| "CombatResolution" | "Motion" | "Guard" | "Combo" | "Juggle"
	| "MovementState" | "Cancel" | "Character" | "Animation" | "Networking"
	| "Prediction" | "Rollback" | "Authority" | "Armor" | "Protection" | "Hitstop" | "Plugins"

export type World = {
	IdGenerator: IdGenerator,
	CreateEntity: (self: World) -> CombatEntity,
	GetEntity: (self: World, id: EntityId) -> CombatEntity?,
	DestroyEntity: (self: World, entityOrId: CombatEntity | EntityId) -> boolean,
	GetCombatAPI: (self: World) -> APIContext,
	GetAPIContext: (self: World) -> APIContext,
	CurrentFrame: number?,
	Destroying: boolean?,
	ExecutionContext: string?,
	Step: (self: World, deltaTime: number, frame: number?, time: number?) -> (),
	SetCollisionWorld: (self: World, collisionWorld: CollisionWorld) -> (),
	SetSimulation: (self: World, simulation: Simulation) -> Simulation,
	GetSimulation: (self: World) -> Simulation?,
	GetDeterminismViolations: (self: World) -> { DeterminismViolation },
	RegisterGameplayEventHandler: (self: World, typeId: string, handler: (ScheduledGameplayEvent) -> ()) -> (boolean, string?),
	RegisterGameplayActionEventHandler: (self: World, typeId: string, handler: (ActionGameplayEvent) -> ()) -> (boolean, string?),
	CaptureCombatState: (self: World) -> any,
	RestoreCombatState: (self: World, snapshot: any, options: { [string]: any }?) -> (boolean, string?),
	HashCombatState: (self: World, snapshot: any?) -> string,
	Destroy: (self: World) -> boolean,
	[string]: any,
}

export type DeterministicRNG = {
	NextNumber: (self: DeterministicRNG, minimum: number?, maximum: number?) -> number,
	NextInteger: (self: DeterministicRNG, minimum: number, maximum: number) -> number,
	GetState: (self: DeterministicRNG) -> any,
	SetState: (self: DeterministicRNG, state: any) -> (),
}

export type FrameCommandBufferOptions = {
	MaxCommandsPerFrame: number?,
	HistorySize: number?,
}

export type DeterministicSchedulerOptions = {
	CurrentFrame: number?,
	MaxEvents: number?,
}

export type SimulationOptions = {
	FixedDeltaTime: number?,
	MaxStepsPerUpdate: number?,
	Seed: number?,
	RNG: DeterministicRNG?,
	FrameCommandBuffer: FrameCommandBufferOptions?,
	DeterministicScheduler: DeterministicSchedulerOptions?,
}

export type SimulationExecutionContext = "Normal" | "Replay" | "Rollback"

export type DeterminismViolation = {
	Sequence: number,
	Frame: number?,
	Operation: string,
	Context: SimulationExecutionContext,
	Details: string?,
}

export type DeterminismGuard = {
	Check: (self: DeterminismGuard, operation: string, details: any?) -> (boolean, DeterminismViolation?),
	AssertAllowed: (self: DeterminismGuard, operation: string, details: any?) -> boolean,
	GetContext: (self: DeterminismGuard) -> SimulationExecutionContext,
	IsForbidden: (self: DeterminismGuard, operation: string) -> boolean,
	GetViolations: (self: DeterminismGuard) -> { DeterminismViolation },
	ClearViolations: (self: DeterminismGuard) -> (),
}

export type ReplayFrame = {
	Frame: number,
	Inputs: { [string]: any },
	StateHash: string,
	ExternalFacts: { [string]: any }?,
}

export type ReplayDivergence = {
	Reason: string,
	ExpectedHash: string?,
	ActualHash: string?,
	ExpectedState: { [string]: any }?,
	ActualState: { [string]: any }?,
	ExpectedInputs: { [string]: any }?,
	ActualInputs: { [string]: any }?,
	ExpectedExternalFacts: { [string]: any }?,
	ActualExternalFacts: { [string]: any }?,
	ExpectedFrame: ReplayFrame?,
	ActualFrame: ReplayFrame?,
}

export type ReplayRecordingOptions = {
	Metadata: { [string]: any },
	InitialState: { [string]: any },
	ExternalFacts: { [string]: any }?,
}

export type ReplayRecording = {
	Metadata: { [string]: any },
	InitialState: { [string]: any },
	ExternalFacts: { [string]: any }?,
	Frames: { ReplayFrame },
	AppendFrame: (self: ReplayRecording, frame: number, inputs: { [string]: any }?, stateHash: string, externalFacts: { [string]: any }?) -> ReplayFrame,
	Capture: (self: ReplayRecording) -> { [string]: any },
	GetFrame: (self: ReplayRecording, frame: number) -> (ReplayFrame?, string?),
	GetFrameRange: (self: ReplayRecording, firstFrame: number, lastFrame: number) -> ({ ReplayFrame }?, string?),
	FindFirstDivergence: (self: ReplayRecording, other: ReplayRecording) -> (number?, string | ReplayDivergence?),
}

export type ScheduledGameplayEvent = {
	Id: number,
	Frame: number,
	Type: string,
	OwnerId: EntityId?,
	Parameters: { [string]: any },
	Order: number,
	IntervalFrames: number?,
}

export type ActionGameplayEvent = {
	Type: string,
	Frame: number,
	OwnerId: EntityId,
	Parameters: { [string]: any },
	ActionId: EntityId,
	ActionDefinitionId: EntityId,
	EventIndex: number,
}

export type Simulation = {
	World: World,
	Frame: number,
	FixedDeltaTime: number,
	MaxStepsPerUpdate: number,
	Accumulator: number,
	LastCompletedFrame: number,
	ExecutionContext: SimulationExecutionContext,
	GetWorld: (self: Simulation) -> World,
	GetAlpha: (self: Simulation) -> number,
	GetPendingStepCount: (self: Simulation) -> number,
	GetGameTime: (self: Simulation) -> any,
	GetScheduler: (self: Simulation) -> any,
	GetDeterministicScheduler: (self: Simulation) -> any,
	GetFrameCommandBuffer: (self: Simulation) -> any,
	Step: (self: Simulation) -> (),
	Update: (self: Simulation, deltaTime: number) -> number,
	SetExecutionContext: (self: Simulation, context: SimulationExecutionContext) -> Simulation,
	RegisterCommandHandler: (self: Simulation, commandType: string, handler: (Simulation, any) -> ()) -> (boolean, string?),
	QueueCommand: (self: Simulation, command: { [string]: any }) -> (any?, boolean | string?, string?),
	RegisterScheduledHandler: (self: Simulation, typeId: string, handler: (ScheduledGameplayEvent) -> ()) -> (boolean, string?),
	RegisterGameplayEventHandler: (self: Simulation, typeId: string, handler: (ScheduledGameplayEvent) -> ()) -> (boolean, string?),
	RegisterGameplayActionEventHandler: (self: Simulation, typeId: string, handler: (ActionGameplayEvent) -> ()) -> (boolean, string?),
	ScheduleEvent: (self: Simulation, frame: number, typeId: string, ownerId: EntityId?, parameters: { [string]: any }?, intervalFrames: number?) -> (number?, string?),
	ScheduleGameplayEvent: (self: Simulation, frame: number, typeId: string, ownerId: EntityId?, parameters: { [string]: any }?, intervalFrames: number?) -> (number?, string?),
	ScheduleGameplayEventAfter: (self: Simulation, delayFrames: number, typeId: string, ownerId: EntityId?, parameters: { [string]: any }?, intervalFrames: number?) -> (number?, string?),
	GetGameplayScheduler: (self: Simulation) -> any,
	GetLegacyScheduler: (self: Simulation) -> any,
	GetDeterminismGuard: (self: Simulation) -> DeterminismGuard,
	GetRNG: (self: Simulation) -> DeterministicRNG,
	GetExecutionContext: (self: Simulation) -> SimulationExecutionContext,
	AssertDeterministicOperation: (self: Simulation, operation: string, details: any?) -> boolean,
	CanRestoreRollbackFrame: (self: Simulation) -> boolean,
	CaptureState: (self: Simulation) -> { [string]: any },
	RestoreState: (self: Simulation, snapshot: { [string]: any }) -> (boolean, string?),
	CaptureRecoveryState: (self: Simulation) -> { [string]: any },
	ValidateRecoveryState: (self: Simulation, state: any) -> (boolean, string?),
	RestoreRecoveryState: (self: Simulation, state: any) -> (boolean, string?),
	GetKernelStateHash: (self: Simulation) -> string,
	RestoreRollbackFrame: (self: Simulation, frame: number, rngState: any, accumulator: number?, schedulerNextId: number?, schedulerNextOrder: number?) -> boolean,
}

export type APIContext = {
	World: World?,
	Events: EventBus,
	Destroyed: boolean,
	GetWorld: (self: APIContext) -> World?,
	GetEvents: (self: APIContext) -> EventBus,
	Subscribe: (self: APIContext, eventType: string, callback: EventCallback, options: EventSubscriptionOptions?) -> (EventSubscription?, APIError?),
	On: (self: APIContext, eventType: string, callback: EventCallback, options: EventSubscriptionOptions?) -> (EventSubscription?, APIError?),
	GetEntity: (self: APIContext, id: EntityId) -> APIResult<CombatEntity>,
	CreateEntity: (self: APIContext) -> APIResult<CombatEntity>,
	DestroyEntity: (self: APIContext, entityOrId: CombatEntity | EntityId) -> APIResult<boolean>,
	GetSystem: (self: APIContext, name: SystemName) -> APIResult<any>,
	HasSystem: (self: APIContext, name: SystemName) -> boolean,
	HasFeature: (self: APIContext, name: string) -> boolean,
	GetInputResolver: (self: APIContext) -> any?,
	GetSimulation: (self: APIContext) -> Simulation?,
	GetCollisionWorld: (self: APIContext) -> CollisionWorld?,
	GetDamageResolver: (self: APIContext) -> any?,
	GetDefenseResolver: (self: APIContext) -> any?,
	GetCombatResolver: (self: APIContext) -> any?,
	GetProtectionResolver: (self: APIContext) -> any?,
	GetArmorResolver: (self: APIContext) -> any?,
	GetHitstopResolver: (self: APIContext) -> any?,
	GetMotionResolver: (self: APIContext) -> any?,
	GetGuardResolver: (self: APIContext) -> any?,
	GetComboResolver: (self: APIContext) -> any?,
	GetJuggleResolver: (self: APIContext) -> any?,
	GetMovementStateResolver: (self: APIContext) -> any?,
	GetCancelResolver: (self: APIContext) -> any?,
	GetCharacterResolver: (self: APIContext) -> any?,
	GetAnimationResolver: (self: APIContext) -> any?,
	GetNetworkResolver: (self: APIContext) -> any?,
	GetPredictionResolver: (self: APIContext) -> any?,
	GetRollbackResolver: (self: APIContext) -> any?,
	GetAuthorityResolver: (self: APIContext) -> any?,
	GetPluginResolver: (self: APIContext) -> any?,
	RegisterPlugin: (self: APIContext, plugin: Plugin | PluginProfile | PluginProfileOptions, implementation: PluginImplementation?) -> APIResult<PluginResolverResult>,
	GetPlugin: (self: APIContext, id: string) -> APIResult<Plugin>,
	StartPlugin: (self: APIContext, id: string) -> APIResult<PluginResolverResult>,
	StopPlugin: (self: APIContext, id: string) -> APIResult<PluginResolverResult>,
	UnregisterPlugin: (self: APIContext, id: string) -> APIResult<PluginResolverResult>,
	EnablePlugin: (self: APIContext, id: string) -> APIResult<PluginResolverResult>,
	DisablePlugin: (self: APIContext, id: string) -> APIResult<PluginResolverResult>,
	Destroy: (self: APIContext) -> boolean,
}

export type APIContextConstructor = {
	new: (world: World) -> APIContext,
}

export type APIErrorModule = {
	Code: { [string]: APIErrorCode },
	isCode: (value: any) -> boolean,
	new: (code: APIErrorCode, message: string, system: string?, frame: number?, context: { [string]: any }?) -> APIError,
	fromResolverResult: (result: PluginResolverResult, system: string?, frame: number?) -> APIError,
}

export type APIResultModule = {
	new: <T>(success: boolean, value: T?, err: APIError?) -> APIResult<T>,
	is: (value: any) -> boolean,
}

export type OffensivePropertiesModule = {
	CustomDataLimits: { MaxEntries: number, MaxDepth: number },
	NormalizeCustomData: (value: any, label: string) -> CustomData?,
	CanonicalizeCustomData: (customData: CustomData?) -> string?,
	new: (options: OffensivePropertiesOptions?) -> OffensiveProperties,
	WithCustomData: (properties: OffensiveProperties, customData: CustomData?) -> OffensiveProperties,
}

export type PluginModule = {
	new: (profile: PluginProfile | PluginProfileOptions, implementation: PluginImplementation?) -> Plugin,
}

export type PluginCapabilityModule = {
	new: (data: { Id: string, Version: string?, Implementation: any?, OwnerPluginId: string }) -> PluginCapability,
}

export type PluginContextModule = {
	new: (resolver: any, plugin: Plugin) -> PluginContext,
}

export type PluginProfileModule = {
	Scope: { Gameplay: "Gameplay", Presentation: "Presentation" },
	new: (data: PluginProfileOptions) -> PluginProfile,
}

export type PluginStateModule = {
	Registered: "Registered",
	Initializing: "Initializing",
	Active: "Active",
	Stopping: "Stopping",
	Stopped: "Stopped",
	Failed: "Failed",
}

export type SimulationModule = {
	new: (world: World, options: SimulationOptions?) -> Simulation,
}

export type ReplayRecordingModule = {
	Version: number,
	new: (options: ReplayRecordingOptions) -> ReplayRecording,
	FromSnapshot: (snapshot: any, migrations: { [number]: (any) -> any }?) -> (ReplayRecording?, string?),
}

export type AttackModule = {
	new: (options: AttackOptions?) -> Attack,
}

export type AttackInstanceModule = {
	new: (attack: Attack, ownerEntity: any?, idGenerator: any?, options: AttackInstanceConstructorOptions?) -> AttackInstance,
}

export type CombatActionGameplayEventDefinition = {
	FrameOffset: number,
	Type: string,
	Parameters: { [string]: any },
}

export type CombatActionGameplayEventOptions = {
	FrameOffset: number,
	Type: string,
	Parameters: { [string]: any }?,
}

export type CombatActionDefinitionOptions = {
	Id: EntityId,
	StartupFrames: number?,
	ActiveFrames: number?,
	RecoveryFrames: number?,
	DurationModel: string?,
	Cancelable: boolean?,
	Tags: { string }?,
	Requirements: {
		Resources: { [string]: number }?,
		RequiredStatusTags: { string }?,
		ForbiddenStatusTags: { string }?,
		MovementStates: { string }?,
	}?,
	Costs: { Resources: { [string]: number } }?,
	GameplayEvents: { CombatActionGameplayEventOptions }?,
}

export type CombatActionDefinition = {
	Version: number,
	Id: EntityId,
	StartupFrames: number,
	ActiveFrames: number,
	RecoveryFrames: number,
	DurationModel: string,
	Cancelable: boolean,
	Tags: { string },
	Requirements: { [string]: any },
	Costs: { Resources: { [string]: number } },
	GameplayEvents: { CombatActionGameplayEventDefinition },
	GetTotalFrames: (self: CombatActionDefinition) -> number?,
}

export type CombatActionDefinitionModule = {
	Version: number,
	DurationModel: { [string]: string },
	new: (options: CombatActionDefinitionOptions?) -> CombatActionDefinition,
}

export type CollisionTopologyCatalogModule = CollisionTopologyCatalogConstructor

export type CombatAPI = {
	Name: string,
	Version: number,
	SemVer: string,
	Contracts: { [string]: number },
	CreateWorld: (options: { [string]: any }?) -> World,
	GetContext: (world: World) -> APIContext?,
	GetAPIContext: (world: World) -> APIContext?,
	IsWorld: (value: any) -> boolean,
	GetPluginResolver: (world: World) -> any?,
	RegisterPlugin: (world: World, plugin: Plugin | PluginProfile | PluginProfileOptions, implementation: PluginImplementation?) -> APIResult<PluginResolverResult>,
	StartPlugin: (world: World, id: string) -> APIResult<PluginResolverResult>,
	StopPlugin: (world: World, id: string) -> APIResult<PluginResolverResult>,
	UnregisterPlugin: (world: World, id: string) -> APIResult<PluginResolverResult>,
	EnablePlugin: (world: World, id: string) -> APIResult<PluginResolverResult>,
	DisablePlugin: (world: World, id: string) -> APIResult<PluginResolverResult>,
	APIContext: APIContextConstructor,
	EventTypes: EventTypes,
	APIResult: APIResultConstructor,
	APIError: APIErrorConstructor,
	Simulation: SimulationModule,
	Attack: AttackConstructor,
	AttackInstance: AttackInstanceConstructor,
	AttackCatalog: AttackCatalogConstructor,
	CollisionWorld: CollisionWorldConstructor,
	Hitbox: HitboxConstructor,
	Hurtbox: HurtboxConstructor,
	Plugin: PluginModule,
	PluginCapability: PluginCapabilityModule,
	PluginContext: PluginContextModule,
	PluginProfile: PluginProfileModule,
	PluginState: PluginStateModule,
	CombatActionProfiles: { [string]: any },
	CombatActionDefinition: CombatActionDefinitionModule,
	CombatActionCatalog: { [string]: any },
	ReplayRecording: ReplayRecordingModule,
	RobloxRemoteEventAdapter: { [string]: any },
	CollisionTopologyCatalog: CollisionTopologyCatalogModule,
	OffensiveProperties: OffensivePropertiesModule,
}

export type CustomDataConsumerAPI = CombatAPI

return table.freeze({})
