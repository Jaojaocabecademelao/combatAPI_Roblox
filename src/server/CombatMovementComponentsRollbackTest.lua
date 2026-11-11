return function()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Core.World)
local Simulation = require(Shared.Simulation.Simulation)
local CombatStateSchema = require(Shared.Combat.CombatStateSchema)
local MovementState = require(Shared.Combat.MovementState)
local MovementStateComponent = require(Shared.Combat.MovementStateComponent)
local MovementStateProfile = require(Shared.Combat.MovementStateProfile)
local OffensiveStateComponent = require(Shared.Combat.OffensiveStateComponent)
local MotionComponent = require(Shared.Combat.MotionComponent)

local function check(value, message)
	assert(value, message)
end

local profile = MovementStateProfile.new({
	InitialState = MovementState.Idle,
	AllowedTransitions = {
		Idle = { Moving = true },
		Moving = { Idle = true, Dashing = true },
		Dashing = { Idle = true },
	},
	StateDurations = { Dashing = { MinFrames = 2, MaxFrames = 12 } },
})
local world = World.new()
Simulation.new(world)
local entity = world:CreateEntity()
local motionTarget = world:CreateEntity()
local movement = entity:AddComponent(MovementStateComponent.new(profile))
local offense = entity:AddComponent(OffensiveStateComponent.new())
local motion = entity:AddComponent(MotionComponent.new())
movement:SetState(MovementState.Moving, 4)
offense:SetWindow(5, 3)
motion:ApplyRequest({ Source = entity, Target = motionTarget, Type = "Knockback",
	Direction = Vector3.new(1, 0, 0), Magnitude = 12, Duration = 3, Priority = 2 })

local schema = CombatStateSchema.new()
schema:RegisterComponent(MovementStateComponent.RollbackKey, function()
	return MovementStateComponent.new(profile)
end)
schema:RegisterComponent(OffensiveStateComponent.RollbackKey, function()
	return OffensiveStateComponent.new()
end)
schema:RegisterComponent(MotionComponent.RollbackKey, function()
	return MotionComponent.new()
end)
local snapshot = schema:Capture(world)
local savedId = entity.Id
local savedTargetId = motionTarget.Id
movement:SetState(MovementState.Dashing, 9)
offense:EndWindow()
motion:Process(9)
local restored, detail = schema:Restore(world, snapshot)
check(restored, "Movement/offensive component restore failed: " .. tostring(detail))
local restoredEntity = world:GetEntity(savedId)
local restoredMovement = restoredEntity:GetComponent(MovementStateComponent)
local restoredOffense = restoredEntity:GetComponent(OffensiveStateComponent)
local restoredMotion = restoredEntity:GetComponent(MotionComponent)
local restoredTarget = world:GetEntity(savedTargetId)
check(restoredMovement:GetState() == MovementState.Moving
	and restoredMovement:GetPreviousState() == MovementState.Idle
	and restoredMovement:GetStateStartFrame() == 4
	and restoredMovement:GetLastTransitionFrame() == 4
	and restoredMovement.TransitionCount == 1,
	"Movement state and temporal counters should restore exactly")
check(restoredOffense.Active and restoredOffense.StartFrame == 5 and restoredOffense.EndFrame == 7,
	"Offensive active window should restore its exact inclusive frame bounds")
local restoredRequests = restoredMotion:GetPendingRequests()
check(#restoredRequests == 1 and restoredRequests[1].Source == restoredEntity
	and restoredRequests[1].Target == restoredTarget and restoredRequests[1].Magnitude == 12
	and restoredRequests[1].Direction == Vector3.new(1, 0, 0)
	and #restoredMotion.MotionResolver:GetPendingRequests() == 1,
	"Pending motion must restore with references rebound to staged entities")

local unknownMovement = table.clone(movement:CaptureRollbackState())
unknownMovement.Unexpected = true
check(restoredMovement:ValidateRollbackState(unknownMovement) == false,
	"Movement component must reject unknown state fields")
local inconsistentOffense = { Version = 1, Active = false, StartFrame = 5, EndFrame = 7 }
check(restoredOffense:ValidateRollbackState(inconsistentOffense) == false,
	"Inactive offensive state must not retain window frames")
local changedProfile = MovementStateProfile.new({
	InitialState = MovementState.Idle,
	AllowedTransitions = { Idle = { Moving = true }, Moving = { Idle = true } },
})
check(MovementStateComponent.new(changedProfile):ValidateRollbackState(snapshot.Entities[1].Components[1].State) == false,
	"Movement snapshots must reject incompatible transition/duration profiles")

world:Destroy()
print("CombatMovementComponentsRollbackTest: PASS")

end
