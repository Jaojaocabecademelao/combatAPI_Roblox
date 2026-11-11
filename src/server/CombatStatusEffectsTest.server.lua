local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Core.World)
local Simulation = require(Shared.Simulation.Simulation)
local CollisionWorld = require(Shared.Combat.CollisionWorld)
local HealthComponent = require(Shared.Combat.HealthComponent)
local Status = require(Shared.Combat.Status)
local StatusCatalog = require(Shared.Combat.StatusCatalog)
local StatusContainer = require(Shared.Combat.StatusContainer)
local EventTypes = require(Shared.Events.EventTypes)

local assertions = 0
local function check(value, message)
	assert(value, message or ("Status effects assertion " .. tostring(assertions + 1) .. " failed"))
	assertions += 1
end

local Burn = {}
Burn.__index = Burn
Burn.RollbackTypeId = "Test.Burn"
Burn.RollbackVersion = 1
Burn.RollbackCustomStateContract = true
setmetatable(Burn, { __index = Status })
function Burn.new()
	return setmetatable(Status.new({
		Name = "Burn",
		DurationFrames = 5,
		PeriodicEffects = {
			{ Id = "burn.tick", Type = "DamageOverTime", Amount = 5, IntervalFrames = 2, DamageType = "Fire" },
		},
	}), Burn)
end

local Regeneration = {}
Regeneration.__index = Regeneration
Regeneration.RollbackTypeId = "Test.Regeneration"
Regeneration.RollbackVersion = 1
Regeneration.RollbackCustomStateContract = true
setmetatable(Regeneration, { __index = Status })
function Regeneration.new()
	return setmetatable(Status.new({
		Name = "Regeneration",
		DurationFrames = 4,
		PeriodicEffects = {
			{ Id = "regen.tick", Type = "HealingOverTime", Amount = 3, IntervalFrames = 1 },
		},
	}), Regeneration)
end

local catalog = StatusCatalog.new()
catalog:Register(Burn.RollbackTypeId, Burn.RollbackVersion, Burn.new)
catalog:Register(Regeneration.RollbackTypeId, Regeneration.RollbackVersion, Regeneration.new)
catalog:Seal()
local world = World.new({
	ComponentFactories = {
		[StatusContainer.RollbackKey] = function() return StatusContainer.new(catalog) end,
	},
})
local collision = CollisionWorld.new(world)
local simulation = Simulation.new(world, { FixedDeltaTime = 0.1 })
local statusEffectPublicEvents, healingPublicEvents = {}, {}
local statusSubscription = world:GetEvents():Subscribe(EventTypes.StatusEffectApplied, function(event)
	table.insert(statusEffectPublicEvents, event)
end)
local healingSubscription = world:GetEvents():Subscribe(EventTypes.HealApplied, function(event)
	table.insert(healingPublicEvents, event)
end)
check(statusSubscription ~= nil and healingSubscription ~= nil,
	"Public status-effect and healing event subscriptions are available")
local source = world:CreateEntity()
local target = world:CreateEntity()
target:AddComponent(HealthComponent.new({ MaxHealth = 20 }))
local statuses = target:AddComponent(StatusContainer.new(catalog))
local burn = Burn.new()
burn.Source = source
check(statuses:AddStatus(burn) ~= nil, "Periodic damage status is accepted with health and damage resolvers")

simulation:Step()
check(target:GetComponent(HealthComponent):GetHealth() == 20,
	"Periodic effects wait for their configured frame interval")
local snapshot = world:CaptureCombatState()
simulation:Step()
local damageEvents = world:GetDamageEvents()
check(target:GetComponent(HealthComponent):GetHealth() == 15
	and #damageEvents == 1 and damageEvents[1].Type == "Fire"
	and damageEvents[1].Source == source,
	"Damage-over-time applies through DamageResolver with source and damage type")
local effectEvents = world:GetStatusEffectResolver():GetEvents()
check(#effectEvents == 1 and effectEvents[1].Type == "DamageOverTime"
	and effectEvents[1].AppliedAmount == 5 and effectEvents[1].Frame == 2,
	"StatusEffectResolver exposes the periodic damage result")
check(#statusEffectPublicEvents == 1
	and statusEffectPublicEvents[1].Payload.EffectId == "burn.tick"
	and statusEffectPublicEvents[1].Frame == 2,
	"Periodic damage is published as a stable public status-effect event")

local restored, restoreError = world:RestoreCombatState(snapshot)
check(restored, tostring(restoreError))
local restoredSource = world:GetEntity(source.Id)
local restoredTarget = world:GetEntity(target.Id)
local restoredBurn = restoredTarget:GetComponent(StatusContainer):GetStatus("Burn")
check(restoredBurn.Source == restoredSource,
	"Status source and periodic timer restore from the coordinated snapshot")
simulation:Step()
check(restoredTarget:GetComponent(HealthComponent):GetHealth() == 15,
	"Restoring one frame before a tick reproduces the same damage on replay")

local healingTarget = world:CreateEntity()
healingTarget:AddComponent(HealthComponent.new({ MaxHealth = 100, CurrentHealth = 50 }))
local healingStatuses = healingTarget:AddComponent(StatusContainer.new(catalog))
check(healingStatuses:AddStatus(Regeneration.new()) ~= nil, "Periodic healing status is accepted")
simulation:Step()
local healingHealth = healingTarget:GetComponent(HealthComponent)
check(healingHealth:GetHealth() == 53,
	"Healing-over-time uses the same deterministic health resolver path")
local healingEvents = world:GetHealthChangedEvents()
local foundStatusHeal = false
for _, event in ipairs(healingEvents) do
	if event.Entity == healingTarget and event.Reason == "StatusEffect"
		and event.StatusName == "Regeneration" and event.Delta == 3 then
		foundStatusHeal = true
	end
end
check(foundStatusHeal, "Periodic healing is represented in health-change events")
check(#healingPublicEvents == 1
	and healingPublicEvents[1].Payload.StatusName == "Regeneration"
	and healingPublicEvents[1].Payload.Amount == 3,
	"Periodic healing is published as a public HealApplied event")

local noResolverWorld = World.new({
	ComponentFactories = {
		[StatusContainer.RollbackKey] = function() return StatusContainer.new(catalog) end,
	},
})
local noResolverTarget = noResolverWorld:CreateEntity()
noResolverTarget:AddComponent(HealthComponent.new())
local noResolverStatuses = noResolverTarget:AddComponent(StatusContainer.new(catalog))
local noResolverStatus, noResolverReason = noResolverStatuses:AddStatus(Burn.new())
check(noResolverStatus == nil and noResolverReason == "PeriodicStatusRequiresDamageResolver",
	"Periodic effects fail explicitly when the World has no DamageResolver")
noResolverWorld:Destroy()
world:Destroy()
print(("CombatStatusEffectsTest: PASS (%d assertions)"):format(assertions))
