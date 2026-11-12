--!strict
-- Public type contracts. Runtime values are intentionally empty; require this
-- module only for type imports from consumer code.

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

export type OffensiveProperties = {
	Damage: Damage?,
	Hitstun: number,
	HitstunFrames: number,
	HasHitstun: boolean,
	Defense: { CanBlock: boolean, CanParry: boolean },
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
	WithCustomData: (
		properties: OffensiveProperties,
		customData: CustomData?
	) -> OffensiveProperties,
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
	Defense: { CanBlock: boolean, CanParry: boolean },
	CanHit: ((any, any) -> boolean)?,
}

export type AttackConstructor = {
	new: (options: AttackOptions?) -> Attack,
}

export type AttackInstanceOptions = {
	Id: EntityId?,
	CustomDataOverrides: CustomData?,
}

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
}

export type EventSubscription = {
	Disconnect: (self: EventSubscription) -> boolean,
	IsConnected: (self: EventSubscription) -> boolean,
	GetId: (self: EventSubscription) -> number,
}

export type EventFilterOptions = {
	Priority: number?,
	Filter: { [string]: any }?,
}

export type EventBus = {
	Subscribe: (
		self: EventBus,
		eventType: string,
		callback: (event: Event, context: APIContext) -> (),
		options: EventFilterOptions?
	) -> (EventSubscription?, APIError?),
	Dispatch: (self: EventBus, eventType: string, payload: { [string]: any }?, context: { [string]: any }?) -> (Event?, APIError?),
	GetErrors: (self: EventBus) -> { APIError },
	ClearErrors: (self: EventBus) -> EventBus,
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

export type World = {
	IdGenerator: IdGenerator,
	CreateEntity: (self: World) -> CombatEntity,
	GetEntity: (self: World, id: EntityId) -> CombatEntity?,
	GetCombatAPI: (self: World) -> APIContext,
	GetAPIContext: (self: World) -> APIContext,
	Step: (self: World, deltaTime: number, frame: number, time: number) -> (),
	SetCollisionWorld: (self: World, collisionWorld: CollisionWorld) -> (),
	SetSimulation: (self: World, simulation: Simulation) -> Simulation,
	GetSimulation: (self: World) -> Simulation?,
	CaptureCombatState: (self: World) -> any,
	RestoreCombatState: (self: World, snapshot: any, options: { [string]: any }?) -> (boolean, string?),
	HashCombatState: (self: World, snapshot: any?) -> string,
	Destroy: (self: World) -> boolean,
}

export type PluginHandle = {
	Id: string,
}

export type PluginResolverResult = {
	Success: boolean,
	Code: string,
	PluginId: string?,
	Value: any?,
	Details: any?,
}

export type APIContext = {
	World: World?,
	Events: EventBus,
	Destroyed: boolean,
	GetWorld: (self: APIContext) -> World?,
	GetEvents: (self: APIContext) -> EventBus,
	Subscribe: (
		self: APIContext,
		eventType: string,
		callback: (event: Event, context: APIContext) -> (),
		options: EventFilterOptions?
	) -> (EventSubscription?, APIError?),
	On: (
		self: APIContext,
		eventType: string,
		callback: (event: Event, context: APIContext) -> (),
		options: EventFilterOptions?
	) -> (EventSubscription?, APIError?),
	GetEntity: (self: APIContext, id: EntityId) -> APIResult<CombatEntity>,
	CreateEntity: (self: APIContext) -> APIResult<CombatEntity>,
	DestroyEntity: (self: APIContext, entity: CombatEntity | EntityId) -> APIResult<boolean>,
	GetSystem: (self: APIContext, name: string) -> APIResult<any>,
	HasSystem: (self: APIContext, name: string) -> boolean,
	HasFeature: (self: APIContext, name: string) -> boolean,
	GetSimulation: (self: APIContext) -> Simulation?,
	GetCollisionWorld: (self: APIContext) -> CollisionWorld?,
	GetInputResolver: (self: APIContext) -> any?,
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
	RegisterPlugin: (
		self: APIContext,
		plugin: { [string]: any },
		implementation: { [string]: any }?
	) -> APIResult<PluginResolverResult>,
	GetPlugin: (self: APIContext, id: string) -> APIResult<PluginHandle>,
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

export type OpaquePublicModule = { [string]: any }

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
	RegisterPlugin: (
		world: World,
		plugin: { [string]: any },
		implementation: { [string]: any }?
	) -> APIResult<PluginResolverResult>,
	StartPlugin: (world: World, id: string) -> APIResult<PluginResolverResult>,
	StopPlugin: (world: World, id: string) -> APIResult<PluginResolverResult>,
	UnregisterPlugin: (world: World, id: string) -> APIResult<PluginResolverResult>,
	EnablePlugin: (world: World, id: string) -> APIResult<PluginResolverResult>,
	DisablePlugin: (world: World, id: string) -> APIResult<PluginResolverResult>,
	APIContext: APIContextConstructor,
	EventTypes: EventTypes,
	APIResult: APIResultConstructor,
	APIError: APIErrorConstructor,
	Simulation: SimulationConstructor,
	Attack: AttackConstructor,
	AttackInstance: AttackInstanceConstructor,
	AttackCatalog: AttackCatalogConstructor,
	CollisionTopologyCatalog: CollisionTopologyCatalogConstructor,
	CollisionWorld: CollisionWorldConstructor,
	Hitbox: HitboxConstructor,
	Hurtbox: HurtboxConstructor,
	OffensiveProperties: OffensivePropertiesConstructor,
	Plugin: OpaquePublicModule,
	PluginProfile: OpaquePublicModule,
	PluginState: OpaquePublicModule,
	CombatActionProfiles: OpaquePublicModule,
	CombatActionCatalog: OpaquePublicModule,
	ReplayRecording: OpaquePublicModule,
	RobloxRemoteEventAdapter: OpaquePublicModule,
}

export type CollisionWorldConstructor = {
	new: (world: World?) -> CollisionWorld,
}

export type HitboxConstructor = {
	new: (options: HitboxOptions?) -> Hitbox,
}

export type HurtboxConstructor = {
	new: (options: HurtboxOptions?) -> Hurtbox,
}

export type SimulationOptions = {
	Seed: number?,
	FixedDeltaTime: number?,
	MaxStepsPerUpdate: number?,
	RNG: { [string]: any }?,
	DeterministicScheduler: { [string]: any }?,
	FrameCommandBuffer: { [string]: any }?,
}

export type Simulation = {
	World: World,
	Frame: number,
	FixedDeltaTime: number,
	MaxStepsPerUpdate: number,
	Step: (self: Simulation) -> (),
	Update: (self: Simulation, deltaTime: number) -> number,
	CaptureState: (self: Simulation) -> any,
}

export type SimulationConstructor = {
	new: (world: World, options: SimulationOptions?) -> Simulation,
}

export type CustomDataConsumerAPI = CombatAPI

return table.freeze({})
