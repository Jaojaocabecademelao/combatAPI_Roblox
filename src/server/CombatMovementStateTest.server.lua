local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Core, Combat = Shared:WaitForChild("Core"), Shared:WaitForChild("Combat")
local World = require(Core.World)
local EntityState = require(Core.EntityState)
local MovementState = require(Combat.MovementState)
local MovementStateComponent = require(Combat.MovementStateComponent)
local MovementStateProfile = require(Combat.MovementStateProfile)
local MovementStateResult = require(Combat.MovementStateResult)
local MovementStateEvent = require(Combat.MovementStateEvent)

local cases = 0
local function check(condition, message)
	assert(condition, message or ("Movement state assertion " .. tostring(cases + 1) .. " failed"))
	cases += 1
end

local world = World.new()
local resolver = world:GetMovementStateResolver()
local entity = world:CreateEntity()
local component = entity:AddComponent(MovementStateComponent.new(resolver.Profile))

for _, state in ipairs({ MovementState.Idle, MovementState.Moving, MovementState.Crouching,
	MovementState.Dashing, MovementState.Jumping, MovementState.Falling }) do
	check(resolver.Profile:IsValidState(state), state .. " is an official movement state")
end
check(component:GetState() == MovementState.Idle, "New components start Idle")
check(component:GetPreviousState() == nil, "New components have no previous state")
check(component:GetStateStartFrame() == 0, "Initial state starts at frame zero")
check(component:GetLastTransitionFrame() == 0, "Initial transition frame is deterministic")
check(resolver:GetState(entity) == MovementState.Idle, "Resolver reads the component state")
check(resolver:IsState(entity, MovementState.Idle), "IsState recognizes Idle")
check(not resolver:IsMoving(entity), "Idle is not moving")
check(not resolver:IsCrouching(entity), "Idle is not crouching")
check(not resolver:IsDashing(entity), "Idle is not dashing")
check(not resolver:IsAirMovement(entity), "Idle is not air movement")
check(resolver:GetComponent(entity) == component, "Resolver exposes the attached component")
check(world:GetMovementStateResolver() == resolver, "World exposes the movement resolver")
check(component.Entity == entity and component:IsEnabled(), "Component follows lifecycle conventions")

local result = resolver:RequestTransition(entity, MovementState.Moving, { Frame = 10, Source = "Test" })
check(result.Type == MovementStateResult.Type.Transitioned, "Idle to Moving transitions")
check(result.Accepted and result.EntityId == entity.Id, "Transition result identifies the entity")
check(result.PreviousState == MovementState.Idle and result.CurrentState == MovementState.Moving,
	"Transition result preserves both states")
check(result.RequestedState == MovementState.Moving and result.Frame == 10, "Transition metadata is preserved")
check(resolver:GetState(entity) == MovementState.Moving, "Moving is queryable")
check(resolver:GetPreviousState(entity) == MovementState.Idle, "Previous state is queryable")
check(resolver:GetStateStartFrame(entity) == 10, "State start frame is updated")
check(component:GetLastTransitionFrame() == 10, "Last transition frame is updated")
check(component.TransitionCount == 1, "Transition count increments once")
check(resolver:IsMoving(entity), "Moving is classified as moving")
check(resolver:IsState(entity, MovementState.Moving), "Moving state query succeeds")
check(resolver:GetEvents()[1].Type == MovementStateEvent.Type.StateChanged, "StateChanged event is emitted")
check(resolver:GetEvents()[1].PreviousState == MovementState.Idle, "Event stores previous state")
check(resolver:GetEvents()[1].CurrentState == MovementState.Moving, "Event stores current state")
check(resolver:GetEvents()[1].Frame == 10, "Event stores simulation frame")

local already = resolver:RequestTransition(entity, MovementState.Moving, { Frame = 11 })
check(already.Type == MovementStateResult.Type.AlreadyInState, "Repeated state is rejected semantically")
check(not already.Accepted, "AlreadyInState is not accepted")
check(component.TransitionCount == 1, "Repeated state does not increment transitions")
check(component:GetStateStartFrame() == 10, "Repeated state does not reset start frame")
check(resolver:GetEvents()[2].Type == MovementStateEvent.Type.TransitionRejected, "Rejected event is emitted")

for frame, target in ipairs({ MovementState.Dashing, MovementState.Idle, MovementState.Crouching,
	MovementState.Idle, MovementState.Jumping, MovementState.Falling, MovementState.Idle }) do
	local accepted = resolver:RequestTransition(entity, target, { Frame = 20 + frame })
	check(accepted.Type == MovementStateResult.Type.Transitioned, "Configured transition " .. target .. " succeeds")
	check(accepted.Accepted and resolver:GetState(entity) == target, "Accepted target is applied")
end
check(resolver:IsCrouching(entity) == false, "Final Idle is not crouching")
check(resolver:IsAirMovement(entity) == false, "Final Idle is not airborne movement")
check(component.TransitionCount == 8, "Transition count reflects accepted transitions only")
check(component:GetPreviousState() == MovementState.Falling, "Previous state tracks the last transition")
check(component:GetLastTransitionFrame() == 27, "Last transition frame remains deterministic")

local invalidState = resolver:RequestTransition(entity, "Flying", { Frame = 30 })
check(invalidState.Type == MovementStateResult.Type.InvalidState, "Unknown states are rejected")
check(resolver:GetState(entity) == MovementState.Idle, "Invalid state does not mutate current state")
local invalidEntity = resolver:RequestTransition(999999, MovementState.Dashing, { Frame = 30 })
check(invalidEntity.Type == MovementStateResult.Type.InvalidEntity, "Unknown entities are rejected")
check(resolver:GetState(999999) == nil, "Unknown entity queries return nil")
check(resolver:CanTransition(999999, MovementState.Dashing) == false, "Unknown entity cannot transition")

entity:SetState(EntityState.Dead)
local deadResult = resolver:RequestTransition(entity, MovementState.Dashing, { Frame = 31 })
check(deadResult.Type == MovementStateResult.Type.Rejected, "Dead entities cannot transition")
check(deadResult.Reason == "DeadEntity", "Dead rejection reason is explicit")
check(entity:GetState() == EntityState.Dead, "Movement does not alter Core entity state")
check(resolver:GetState(entity) == MovementState.Idle, "Dead callback resets movement state")
entity:SetState(EntityState.Alive)
check(resolver:RequestTransition(entity, MovementState.Moving, { Frame = 32 }).Accepted,
	"Alive entities can transition after external revival")

local validator = function(_, from, to)
	return not (from == MovementState.Moving and to == MovementState.Dashing), "ExternalRule"
end
resolver:AddValidator(validator)
local blocked = resolver:RequestTransition(entity, MovementState.Dashing, { Frame = 33 })
check(blocked.Type == MovementStateResult.Type.Rejected, "External validator can reject a transition")
check(blocked.Reason == "ExternalRule", "External rejection reason is preserved")
check(resolver:RemoveValidator(validator), "External validator can be removed")
check(resolver:RequestTransition(entity, MovementState.Dashing, { Frame = 34 }).Accepted,
	"Transition works after validator removal")

local profile = MovementStateProfile.new({
	InitialState = MovementState.Crouching,
	AllowedTransitions = {
		Crouching = { Idle = true },
		Idle = { Crouching = true },
	},
	StateDurations = { Crouching = { MinFrames = 3 } },
})
local second = world:CreateEntity()
local secondComponent = second:AddComponent(MovementStateComponent.new(profile))
check(secondComponent:GetState() == MovementState.Crouching, "Custom initial state is honored")
local secondResolver = require(Combat.MovementStateResolver).new(world, profile)
check(secondResolver:CanTransition(second, MovementState.Idle, { Frame = 1 }) == false,
	"Minimum duration rejects an early transition")
check(secondResolver:RequestTransition(second, MovementState.Idle, { Frame = 3 }).Accepted,
	"Minimum duration allows the boundary frame")
check(secondResolver:RequestTransition(second, MovementState.Crouching, { Frame = 4 }).Accepted,
	"Custom profile allows only configured transitions")
local denied = secondResolver:RequestTransition(second, MovementState.Dashing, { Frame = 5 })
check(denied.Type == MovementStateResult.Type.Rejected, "Custom profile rejects unconfigured transitions")
check(secondResolver:Reset(second, 12), "Resolver reset succeeds")
check(secondResolver:GetState(second) == MovementState.Crouching, "Reset restores profile initial state")
check(secondComponent:GetStateStartFrame() == 12, "Reset stores its explicit frame")

resolver:Reset(entity, 40)
check(resolver:GetState(entity) == MovementState.Idle, "Default reset restores Idle")
check(component:GetPreviousState() == nil, "Reset clears previous state")
check(component:GetStateStartFrame() == 40, "Reset uses simulation frame")
check(component:GetLastTransitionFrame() == 40, "Reset updates last transition frame")
check(component.TransitionCount == 0, "Reset clears transition count")
check(entity:GetState() == EntityState.Alive, "Movement reset preserves Core state")
check(#resolver:GetResults() > 0 and #resolver:GetEvents() > 0, "Results and events remain queryable")
resolver:Clear()
check(#resolver:GetResults() == 0 and #resolver:GetEvents() == 0, "Clear removes transient resolver output")

print("Combat movement state tests passed (" .. tostring(cases) .. " cases)")
