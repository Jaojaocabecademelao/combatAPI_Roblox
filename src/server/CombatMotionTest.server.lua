local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local Combat = Shared:WaitForChild("Combat")

local EntityState = require(Core.EntityState)
local World = require(Core.World)
local MotionType = require(Combat.MotionType)
local MotionRequest = require(Combat.MotionRequest)
local MotionResult = require(Combat.MotionResult)
local MotionResolver = require(Combat.MotionResolver)
local MotionComponent = require(Combat.MotionComponent)
local MotionAdapter = require(Combat.MotionAdapter)
local CollisionWorld = require(Combat.CollisionWorld)

local function hasValue(tableValue, value)
	for _, entry in ipairs(tableValue) do
		if entry == value then
			return true
		end
	end
	return false
end

local function assertValid(condition, message)
	assert(condition, message)
end

local motionTypes = {
	MotionType.Knockback,
	MotionType.Impulse,
	MotionType.Push,
	MotionType.Pull,
	MotionType.Launch,
}
assertValid(#motionTypes == 5, "MotionType should expose the required five motion kinds")
assertValid(hasValue(motionTypes, MotionType.Knockback), "Knockback should exist")
assertValid(hasValue(motionTypes, MotionType.Impulse), "Impulse should exist")
assertValid(hasValue(motionTypes, MotionType.Push), "Push should exist")
assertValid(hasValue(motionTypes, MotionType.Pull), "Pull should exist")
assertValid(hasValue(motionTypes, MotionType.Launch), "Launch should exist")

local request = MotionRequest.new({
	Source = { Id = 1 },
	Target = { Id = 2 },
	Type = MotionType.Knockback,
	Direction = Vector3.new(1, 0, 0),
	Magnitude = 12,
	Duration = 3,
	Priority = 7,
	Frame = 5,
})
assertValid(request.Type == MotionType.Knockback, "MotionRequest should preserve the configured motion type")
assertValid(request.Direction == Vector3.new(1, 0, 0), "MotionRequest should normalize a Vector3 direction")
assertValid(request.Magnitude == 12, "MotionRequest should preserve magnitude")
assertValid(request.Duration == 3, "MotionRequest should preserve duration")
assertValid(request.Priority == 7, "MotionRequest should preserve priority")
assertValid(request.Frame == 5, "MotionRequest should preserve frame metadata")

local tableDirection = MotionRequest.new({
	Source = { Id = 11 },
	Target = { Id = 12 },
	Type = MotionType.Push,
	Direction = { 0, 1, 0 },
	Magnitude = 5,
})
assertValid(tableDirection.Direction == Vector3.new(0, 1, 0), "Table-based direction arrays should normalize into Vector3")

local result = MotionResult.new(request, 7)
assertValid(result.Target.Id == 2, "MotionResult should copy the target ID")
assertValid(result.Direction == Vector3.new(1, 0, 0), "MotionResult should retain direction")
assertValid(result.Magnitude == 12, "MotionResult should retain magnitude")
assertValid(result.Priority == 7, "MotionResult should retain priority")
assertValid(result.Frame == 7, "MotionResult should use the supplied frame")

assertValid(pcall(function()
	MotionRequest.new({
		Source = { Id = 1 },
		Target = { Id = 2 },
		Type = MotionType.Knockback,
		Direction = nil,
		Magnitude = 1,
	})
end) == false, "A missing direction should be rejected")
assertValid(pcall(function()
	MotionRequest.new({
		Source = { Id = 1 },
		Target = { Id = 2 },
		Type = MotionType.Knockback,
		Direction = Vector3.new(),
		Magnitude = -1,
	})
end) == false, "Negative motion magnitude should be rejected")
assertValid(pcall(function()
	MotionRequest.new({
		Source = { Id = 1 },
		Target = { Id = 2 },
		Type = "Invalid",
		Direction = Vector3.new(1, 0, 0),
		Magnitude = 1,
	})
end) == false, "Unsupported motion types should be rejected")

local resolver = MotionResolver.new()
local low = MotionRequest.new({
	Source = { Id = 10 },
	Target = { Id = 20 },
	Type = MotionType.Knockback,
	Direction = Vector3.new(1, 0, 0),
	Magnitude = 4,
	Priority = 2,
})
local high = MotionRequest.new({
	Source = { Id = 11 },
	Target = { Id = 20 },
	Type = MotionType.Push,
	Direction = Vector3.new(0, 1, 0),
	Magnitude = 7,
	Priority = 5,
})
local tie = MotionRequest.new({
	Source = { Id = 12 },
	Target = { Id = 20 },
	Type = MotionType.Pull,
	Direction = Vector3.new(0, 0, 1),
	Magnitude = 7,
	Priority = 5,
})
local results = resolver:Process({ low, high, tie }, 11)
assertValid(#results == 1, "Only a single winning motion should remain per target")
assertValid(results[1].Type == MotionType.Pull, "Tie-breaking should favor the later lexical motion type")
assertValid(results[1].Priority == 5, "Winning request should preserve its priority")
assertValid(results[1].Magnitude == 7, "Winning request should preserve the highest magnitude")
assertValid(resolver:GetResults()[1].Type == MotionType.Pull, "Resolver should expose a copy of its results")

local sameTargetLower = MotionRequest.new({
	Source = { Id = 13 },
	Target = { Id = 21 },
	Type = MotionType.Impulse,
	Direction = Vector3.new(1, 1, 0),
	Magnitude = 2,
	Priority = 1,
})
local sameTargetHigher = MotionRequest.new({
	Source = { Id = 14 },
	Target = { Id = 21 },
	Type = MotionType.Launch,
	Direction = Vector3.new(0, 0, -1),
	Magnitude = 9,
	Priority = 6,
})
local multiResults = resolver:Process({ sameTargetLower, sameTargetHigher }, 12)
assertValid(#multiResults == 1 and multiResults[1].Type == MotionType.Launch, "A higher-priority same-target request should replace the weaker one")

local deadTarget = { Id = 25, Destroyed = false, State = EntityState.Dead }
local deadRequest = MotionRequest.new({
	Source = { Id = 40 },
	Target = deadTarget,
	Type = MotionType.Knockback,
	Direction = Vector3.new(0, -1, 0),
	Magnitude = 3,
	Priority = 1,
})
assertValid(resolver:QueueRequest(deadRequest) == nil, "Dead targets should be rejected before queuing")
assertValid(#resolver:GetPendingRequests() == 0, "Rejected targets should not remain in pending queue")

local component = MotionComponent.new()
local entity = World.new():CreateEntity()
entity:AddComponent(component)
assertValid(component:ApplyRequest({
	Source = 50,
	Target = entity,
	Type = MotionType.Impulse,
	Direction = Vector3.new(0, 1, 0),
	Magnitude = 10,
	Priority = 4,
}) ~= nil, "MotionComponent should accept valid requests")
assertValid(#component:GetPendingRequests() == 1, "MotionComponent should record queued requests")
assertValid(#component.MotionResolver:GetPendingRequests() == 0,
	"MotionComponent must not duplicate authoritative requests into the resolver queue")
local pendingMotionSnapshot = component:CaptureRollbackState()
component.PendingRequests = {}
local restoredPendingMotion, restoreMotionError = component:RestoreRollbackState(pendingMotionSnapshot, {
	EntitiesById = { [entity.Id] = entity },
})
assertValid(restoredPendingMotion == true, "MotionComponent should restore queued requests: " .. tostring(restoreMotionError))
assertValid(#component:GetPendingRequests() == 1, "Restored MotionComponent should retain its pending request")
assertValid(#component.MotionResolver:GetPendingRequests() == 0,
	"Restoring MotionComponent must not populate the resolver's independent queue")

-- Missing entity references must reject restoration before mutating live state.
local beforeInvalidRestore = component:GetPendingRequests()
local missingTargetSnapshot = component:CaptureRollbackState()
missingTargetSnapshot.PendingRequests[1].TargetId = "missing-target"
local missingTargetOk = component:RestoreRollbackState(missingTargetSnapshot, {
	EntitiesById = { [entity.Id] = entity },
})
assertValid(missingTargetOk == false, "Restore must reject a missing target entity")
assertValid(#component:GetPendingRequests() == #beforeInvalidRestore,
	"Rejected target restoration must preserve the existing pending queue")

local missingSourceSnapshot = component:CaptureRollbackState()
missingSourceSnapshot.PendingRequests[1].SourceIsEntity = true
missingSourceSnapshot.PendingRequests[1].SourceId = "missing-source"
local missingSourceOk = component:RestoreRollbackState(missingSourceSnapshot, {
	EntitiesById = { [entity.Id] = entity },
})
assertValid(missingSourceOk == false, "Restore must reject a missing source entity")
assertValid(#component:GetPendingRequests() == #beforeInvalidRestore,
	"Rejected source restoration must preserve the existing pending queue")

local processed = component:Process(13)
assertValid(#processed == 1, "MotionComponent should resolve pending requests")
assertValid(processed[1].Target == entity, "Resolved motion should reference the owning entity")
assertValid(#component:GetPendingRequests() == 0, "Processed motion requests should clear from the queue")

local deadEntity = World.new():CreateEntity()
local deadMotion = MotionComponent.new()
deadEntity:AddComponent(deadMotion)
deadEntity:SetState(EntityState.Dead)
assertValid(deadMotion:ApplyRequest({
	Source = { Id = 90 },
	Target = deadEntity,
	Type = MotionType.Knockback,
	Direction = Vector3.new(1, 0, 0),
	Magnitude = 1,
	Priority = 1,
}) == nil, "MotionComponent should reject requests while the entity is dead")
assertValid(#deadMotion:Process(14) == 0, "Dead entities should not produce motion results")

local adapter = MotionAdapter.new({
	Resolve = function(self, request)
		return request.Direction * request.Magnitude
	end,
})
local adapted = adapter:Resolve(MotionRequest.new({
	Source = { Id = 100 },
	Target = { Id = 101 },
	Type = MotionType.Push,
	Direction = Vector3.new(1, 0, 0),
	Magnitude = 3,
	Priority = 2,
}))
assertValid(adapted == Vector3.new(3, 0, 0), "MotionAdapter should proxy a resolution request through its adapter")
adapter:Apply(result)
assertValid(adapter.LastResult == result, "MotionAdapter should retain the last applied result")

local world = World.new()
local collision = CollisionWorld.new(world)
local worldMotion = MotionResolver.new()
world.MotionResolver = worldMotion
local motionEntityA = world:CreateEntity()
local motionEntityB = world:CreateEntity()
local requested = MotionRequest.new({
	Source = motionEntityA,
	Target = motionEntityB,
	Type = MotionType.Knockback,
	Direction = Vector3.new(1, 0, 0),
	Magnitude = 8,
	Priority = 3,
})
worldMotion:QueueRequest(requested)
local worldResults = worldMotion:Process(worldMotion:GetPendingRequests(), 20)
assertValid(#worldResults == 1 and worldResults[1].Target == motionEntityB, "World-linked MotionResolver should process queued motion requests")
assertValid(#world:GetMotionResults() == 1, "World getter should forward MotionResolver results")
assertValid(world:GetMotionResolver() == worldMotion, "World should expose the configured MotionResolver")

local independentResolver = MotionResolver.new()
local first = MotionRequest.new({ Source = { Id = 1 }, Target = { Id = 30 }, Type = MotionType.Knockback, Direction = Vector3.new(0, 1, 0), Magnitude = 2, Priority = 1 })
local second = MotionRequest.new({ Source = { Id = 2 }, Target = { Id = 31 }, Type = MotionType.Impulse, Direction = Vector3.new(0, 0, 1), Magnitude = 4, Priority = 2 })
local third = MotionRequest.new({ Source = { Id = 3 }, Target = { Id = 32 }, Type = MotionType.Push, Direction = Vector3.new(-1, 0, 0), Magnitude = 1, Priority = 0 })
independentResolver:QueueRequest(first)
independentResolver:QueueRequest(second)
independentResolver:QueueRequest(third)
local independentResults = independentResolver:Process(independentResolver:GetPendingRequests(), 21)
assertValid(#independentResults == 3, "Resolver should keep all unique targets as separate results")
assertValid(independentResults[1].Priority >= independentResults[2].Priority, "Resolver should order results by descending priority")
assertValid(independentResults[2].Priority >= independentResults[3].Priority, "Resolver should preserve priority ordering across results")

local redraw = MotionRequest.new({
	Source = { Id = 444 },
	Target = { Id = 555 },
	Type = MotionType.Launch,
	Direction = Vector3.new(0, 2, 0),
	Magnitude = 10,
	Priority = 7,
	Frame = 8,
})
assertValid(redraw.Direction.Y == 2, "Direction should maintain axis components exactly")
assertValid(redraw.Type == MotionType.Launch, "Launch should be accepted as a valid motion type")

local function captureBlockedRequest()
	return MotionRequest.new({
		Source = { Id = 700 },
		Target = { Id = 701 },
		Type = MotionType.Push,
		Direction = { 1, 0, 0 },
		Magnitude = 3.5,
		Priority = 2,
	})
end
local blocked = captureBlockedRequest()
assertValid(blocked.Magnitude == 3.5, "Requests with fractional magnitudes should remain valid when finite")

local defaultPriority = MotionRequest.new({
	Source = { Id = 800 },
	Target = { Id = 801 },
	Type = MotionType.Knockback,
	Direction = Vector3.new(0, 0, 1),
	Magnitude = 1,
})
assertValid(defaultPriority.Priority == 0, "Undefined priority should default to zero")
assertValid(defaultPriority.Duration == 0, "Undefined duration should default to zero")

assertValid(pcall(function()
	MotionRequest.new({
		Source = { Id = 1 },
		Target = { Id = 2 },
		Type = MotionType.Knockback,
		Direction = Vector3.new(1, 0, 0),
		Magnitude = 1,
		Duration = 1.5,
	})
end) == false, "Non-integer duration frames should be rejected")
assertValid(pcall(function()
	MotionRequest.new({
		Source = { Id = 1 },
		Target = { Id = 2 },
		Type = MotionType.Knockback,
		Direction = Vector3.new(1, 0, 0),
		Magnitude = 1,
		Priority = math.huge,
	})
end) == false, "Infinite priorities should be rejected")

local queued = MotionResolver.new()
queued:QueueRequest(MotionRequest.new({
	Source = { Id = 500 },
	Target = { Id = 600 },
	Type = MotionType.Impulse,
	Direction = Vector3.new(-1, 0, 0),
	Magnitude = 2,
	Priority = 1,
}))
queued:QueueRequest(MotionRequest.new({
	Source = { Id = 501 },
	Target = { Id = 601 },
	Type = MotionType.Push,
	Direction = Vector3.new(0, -1, 0),
	Magnitude = 5,
	Priority = 2,
}))
assertValid(#queued:GetPendingRequests() == 2, "Resolver should maintain pending motion request order until processed")
queued:Clear()
assertValid(#queued:GetPendingRequests() == 0 and #queued:GetResults() == 0, "Clear should reset pending and result state")

local emptyResolver = MotionResolver.new()
assertValid(#emptyResolver:Process({}, 99) == 0, "An empty motion batch should resolve to no results")

local finalEntity = World.new():CreateEntity()
finalEntity:SetState(EntityState.Alive)
local finalMotion = MotionComponent.new()
finalEntity:AddComponent(finalMotion)
finalMotion:ApplyRequest({
	Source = { Id = 111 },
	Target = finalEntity,
	Type = MotionType.Pull,
	Direction = Vector3.new(0, 0, -1),
	Magnitude = 6,
	Priority = 3,
})
assertValid(#finalMotion:Process(30) == 1 and finalMotion:GetMotionResults()[1].Type == MotionType.Pull,
	"Component processing should deliver the winning motion result for living entities")

print("Combat motion tests passed")
