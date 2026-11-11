--!strict
-- Public type contracts. Runtime values are intentionally empty; require this
-- module only for type imports from consumer code.

export type Primitive = nil | boolean | number | string
export type SerializableValue = Primitive | { [string | number]: SerializableValue }
export type CustomData = { [string | number]: SerializableValue }
export type EntityId = string | number
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

export type AttackInstanceOptions = {
	Id: EntityId?,
	CustomDataOverrides: CustomData?,
}

export type AttackInstance = {
	Id: EntityId,
	Attack: Attack,
	OffensiveProperties: OffensiveProperties,
	CustomDataOverrides: CustomData?,
	Priority: number,
	CanClash: boolean,
	State: string,
	Activate: (self: AttackInstance) -> AttackInstance,
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

export type World = {
	CreateEntity: (self: World) -> any,
	GetEntity: (self: World, id: EntityId) -> any?,
	CaptureCombatState: (self: World) -> any,
	RestoreCombatState: (self: World, snapshot: any, options: { [string]: any }?) -> (boolean, string?),
	HashCombatState: (self: World, snapshot: any?) -> string,
	Destroy: (self: World) -> boolean,
}

export type Simulation = {
	World: World,
	Frame: number,
	FixedDeltaTime: number,
	Step: (self: Simulation) -> (),
	Update: (self: Simulation, deltaTime: number) -> number,
	CaptureState: (self: Simulation) -> any,
}

return table.freeze({})
