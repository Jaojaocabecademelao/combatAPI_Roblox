--!strict
-- Public type contracts. Runtime values are intentionally empty; consumers
-- import these definitions with `type Types = require(path.CombatAPITypes)`.

export type Primitive = nil | boolean | number | string
export type SerializableValue = Primitive | { [string | number]: SerializableValue }
export type CustomData = { [string | number]: SerializableValue }
export type EntityId = string | number
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
	OffensiveProperties: OffensiveProperties,
	CustomDataOverrides: CustomData?,
	Priority: number,
	CanClash: boolean,
	State: string,
	Activate: (self: AttackInstance) -> AttackInstance,
	GetOffensiveProperties: (self: AttackInstance) -> OffensiveProperties,
	Finish: (self: AttackInstance) -> boolean,
	Destroy: (self: AttackInstance) -> boolean,
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

export type APIResult<T> = {
	Success: boolean,
	Value: T?,
	Error: APIError?,
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
	Context: any?,
	[string]: any,
}

export type EventCallback = (event: Event, context: any) -> ()
export type EventSubscription = {
	Disconnect: (self: EventSubscription) -> boolean,
	IsConnected: (self: EventSubscription) -> boolean,
	GetId: (self: EventSubscription) -> number,
}
export type EventSubscriptionOptions = {
	Priority: number?,
	Filter: { [string]: any }?,
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
}

export type PluginImplementation = {
	Initialize: ((context: any, plugin: Plugin) -> boolean?)?,
	Start: ((context: any, plugin: Plugin) -> boolean?)?,
	Stop: ((context: any, plugin: Plugin) -> boolean?)?,
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
	[string]: any,
	CurrentFrame: number?,
	Destroying: boolean?,
	ExecutionContext: string?,
	CreateEntity: (self: World) -> any,
	GetEntity: (self: World, id: EntityId) -> any?,
	DestroyEntity: (self: World, entityOrId: any) -> boolean,
	GetCombatAPI: (self: World) -> any,
	CaptureCombatState: (self: World) -> any,
	RestoreCombatState: (self: World, snapshot: any, options: { [string]: any }?) -> (boolean, string?),
	HashCombatState: (self: World, snapshot: any?) -> string,
	Destroy: (self: World) -> boolean,
}

export type APIContext = {
	World: World?,
	Events: any,
	Destroyed: boolean,
	GetWorld: (self: APIContext) -> World?,
	GetEvents: (self: APIContext) -> any,
	Subscribe: (self: APIContext, eventType: string, callback: EventCallback, options: EventSubscriptionOptions?) -> (EventSubscription?, APIError?),
	On: (self: APIContext, eventType: string, callback: EventCallback, options: EventSubscriptionOptions?) -> (EventSubscription?, APIError?),
	GetEntity: (self: APIContext, id: EntityId) -> APIResult<any>,
	CreateEntity: (self: APIContext) -> APIResult<any>,
	DestroyEntity: (self: APIContext, entityOrId: any) -> APIResult<boolean>,
	GetSystem: (self: APIContext, name: SystemName) -> APIResult<any>,
	HasSystem: (self: APIContext, name: SystemName) -> boolean,
	HasFeature: (self: APIContext, name: string) -> boolean,
	GetInputResolver: (self: APIContext) -> any?,
	GetSimulation: (self: APIContext) -> any?,
	GetCollisionWorld: (self: APIContext) -> any?,
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

export type APIErrorModule = {
	Code: { [string]: APIErrorCode },
	isCode: (value: any) -> boolean,
	new: (code: APIErrorCode, message: string, system: string?, frame: number?, context: { [string]: any }?) -> APIError,
}

export type APIResultModule = {
	new: <T>(success: boolean, value: T?, err: APIError?) -> APIResult<T>,
	is: (value: any) -> boolean,
}

export type PluginModule = {
	new: (profile: PluginProfile | PluginProfileOptions, implementation: PluginImplementation?) -> Plugin,
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

export type AttackModule = {
	new: (options: AttackOptions?) -> Attack,
}

export type AttackInstanceModule = {
	new: (attack: Attack, ownerEntity: any?, idGenerator: any?, options: AttackInstanceConstructorOptions?) -> AttackInstance,
}

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
	APIContext: { new: (world: World) -> APIContext },
	EventTypes: { [string]: string },
	APIResult: APIResultModule,
	APIError: APIErrorModule,
	Plugin: PluginModule,
	PluginProfile: PluginProfileModule,
	PluginState: PluginStateModule,
	CombatActionProfiles: any,
	CombatActionCatalog: any,
	ReplayRecording: any,
	RobloxRemoteEventAdapter: any,
	Attack: AttackModule,
	AttackInstance: AttackInstanceModule,
	AttackCatalog: any,
	CollisionWorld: any,
	Hitbox: any,
	Hurtbox: any,
	OffensiveProperties: any,
}

return table.freeze({})
