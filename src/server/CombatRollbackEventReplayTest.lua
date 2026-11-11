return function()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Core.World)
local DamageResolver = require(Shared.Combat.DamageResolver)
local DamageRequest = require(Shared.Combat.DamageRequest)
local HealthComponent = require(Shared.Combat.HealthComponent)
local EventTypes = require(Shared.Events.EventTypes)

local function check(value, message)
	assert(value, message)
end

local world = World.new()
local entity = world:CreateEntity()
entity:AddComponent(HealthComponent.new({ MaxHealth = 25 }))
local resolver = DamageResolver.new(world)
world.DamageResolver = resolver

local observed = { NormalDamage = 0, ReplayDamage = 0, NormalDeath = 0, ReplayDeath = 0,
	NormalDamageId = nil, ReplayDamageId = nil, NormalDeathId = nil, ReplayDeathId = nil }
local subscriptions = {}
subscriptions[#subscriptions + 1] = world:GetEvents():Subscribe(EventTypes.DamageApplied, function(event)
	if event.ExecutionMode == "Normal" then observed.NormalDamage += 1; observed.NormalDamageId = event.EventId end
	if event.ExecutionMode == "Replay" then observed.ReplayDamage += 1; observed.ReplayDamageId = event.EventId end
end)
subscriptions[#subscriptions + 1] = world:GetEvents():Subscribe(EventTypes.Death, function(event)
	if event.ExecutionMode == "Normal" then observed.NormalDeath += 1; observed.NormalDeathId = event.EventId end
	if event.ExecutionMode == "Replay" then observed.ReplayDeath += 1; observed.ReplayDeathId = event.EventId end
end)

resolver:Resolve(DamageRequest.new({ Amount = 25, Target = entity, Type = "Test" }), 1, 1 / 60)
check(entity:IsDead(), "Lethal damage should transition the entity before event publication")
world:FlushEvents()
world:FlushEvents()
check(observed.NormalDamage == 1 and observed.NormalDeath == 1,
	"Repeated FlushEvents in Normal mode must not duplicate a source event")

-- Re-publishing the same source event under Replay is intentional: consumers can
-- observe deterministic replay while irreversible consumers filter that mode out.
world:SetExecutionContext("Replay")
world:FlushEvents()
world:FlushEvents()
check(observed.NormalDamage == 1 and observed.NormalDeath == 1,
	"Replay publication must not be mislabeled as Normal")
check(observed.ReplayDamage == 1 and observed.ReplayDeath == 1,
	"Replay consumers should receive one replay-tagged copy of each source event")
check(type(observed.NormalDamageId) == "string" and observed.NormalDamageId ~= "",
	"Normal events must expose a stable EventId")
check(observed.NormalDamageId == observed.ReplayDamageId,
	"A regenerated damage event must retain its identity across Normal and Replay")
check(observed.NormalDeathId == observed.ReplayDeathId,
	"A regenerated death event must retain its identity across Normal and Replay")


-- Event identity must not depend on the position of unrelated events in a resolver buffer.
local function collectIds(events)
	local probe = World.new()
	local ids = {}
	local subscription = probe:GetEvents():Subscribe(EventTypes.DamageApplied, function(event)
		ids[event.Payload.Marker] = event.EventId
	end)
	probe.CurrentFrame = 9
	probe:_PublishInternalEvents("IdentityProbe", events, function(value)
		return EventTypes.DamageApplied, { Marker = value.Marker, Amount = value.Amount }, value.Frame, value.EntityId
	end)
	subscription:Disconnect()
	probe:Destroy()
	return ids
end
local firstOrder = collectIds({
	{ Marker = "A", Amount = 10, Frame = 9, EntityId = 1 },
	{ Marker = "B", Amount = 20, Frame = 9, EntityId = 2 },
})
local reversedOrder = collectIds({
	{ Marker = "B", Amount = 20, Frame = 9, EntityId = 2 },
	{ Marker = "A", Amount = 10, Frame = 9, EntityId = 1 },
})
check(firstOrder.A == reversedOrder.A and firstOrder.B == reversedOrder.B,
	"Event identity must remain stable when unrelated source events are reordered")

for _, subscription in ipairs(subscriptions) do subscription:Disconnect() end
world:Destroy()
print("CombatRollbackEventReplayTest: PASS")

end
