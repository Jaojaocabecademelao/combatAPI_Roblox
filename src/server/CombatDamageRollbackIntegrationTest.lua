return function()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Core.World)
local Simulation = require(Shared.Simulation.Simulation)
local CombatStateSchema = require(Shared.Combat.CombatStateSchema)
local DamageResolver = require(Shared.Combat.DamageResolver)
local DamageRequest = require(Shared.Combat.DamageRequest)
local HealthComponent = require(Shared.Combat.HealthComponent)

local function check(value, message)
	assert(value, message)
end

local world = World.new()
Simulation.new(world)
local entity = world:CreateEntity()
local health = entity:AddComponent(HealthComponent.new({ MaxHealth = 100 }))
local entityId = entity.Id
local resolver = DamageResolver.new(world)
world.DamageResolver = resolver
local schema = CombatStateSchema.new()
schema:RegisterComponent(HealthComponent.RollbackKey, function()
	return HealthComponent.new()
end)
schema:RegisterStateProvider("combat.damage-resolver.v1", resolver)

local function hit(amount, frame)
	return resolver:Resolve(DamageRequest.new({
		Amount = amount, Target = world:GetEntity(entityId), Type = "Physical",
	}), frame, frame / 60)
end

hit(20, 0)
local snapshot = schema:Capture(world)
local savedId = entity.Id
local zeroHealthAliveSnapshot = table.clone(snapshot)
zeroHealthAliveSnapshot.Entities = table.clone(snapshot.Entities)
zeroHealthAliveSnapshot.Entities[1] = table.clone(snapshot.Entities[1])
zeroHealthAliveSnapshot.Entities[1].Components = table.clone(snapshot.Entities[1].Components)
zeroHealthAliveSnapshot.Entities[1].Components[1] = table.clone(snapshot.Entities[1].Components[1])
zeroHealthAliveSnapshot.Entities[1].Components[1].State = table.clone(snapshot.Entities[1].Components[1].State)
zeroHealthAliveSnapshot.Entities[1].Components[1].State.CurrentHealth = 0
local zeroHealthAccepted = schema:Validate(zeroHealthAliveSnapshot, world)
check(zeroHealthAccepted == false,
	"Schema must reject an Alive entity with zero health")

local positiveHealthDeadSnapshot = table.clone(snapshot)
positiveHealthDeadSnapshot.Entities = table.clone(snapshot.Entities)
positiveHealthDeadSnapshot.Entities[1] = table.clone(snapshot.Entities[1])
positiveHealthDeadSnapshot.Entities[1].State = "Dead"
local positiveHealthAccepted = schema:Validate(positiveHealthDeadSnapshot, world)
check(positiveHealthAccepted == false,
	"Schema must reject a Dead entity with positive health")

check(health:GetHealth() == 80 and #resolver:GetDamageEvents() == 1,
	"Initial damage should update health and populate resolver outputs")
local validHealthState = health:CaptureRollbackState()
local healthWithUnknownField = table.clone(validHealthState)
healthWithUnknownField.FutureField = true
check(health:ValidateRollbackState(healthWithUnknownField) == false,
	"HealthComponent must reject unknown rollback fields")
local invalidRoleCommit, invalidRoleError = resolver:PrepareRollbackRestore(
	resolver:CaptureRollbackState(), world, {}, "UnexpectedRole")
check(invalidRoleCommit == nil and string.find(tostring(invalidRoleError), "Unknown DamageResolver restore role", 1, true),
	"DamageResolver must reject unknown restore roles during preparation")

hit(10, 1)
check(health:GetHealth() == 70 and #resolver:GetDamageEvents() == 1,
	"Follow-up damage should mutate health and replace frame-local output")
local restored, restoreError = schema:Restore(world, snapshot)
check(restored, "Damage rollback failed: " .. tostring(restoreError))
local restoredEntity = world:GetEntity(savedId)
check(restoredEntity:GetComponent(HealthComponent):GetHealth() == 80,
	"HealthComponent state should restore the damage consequence")
check(#resolver:GetDamageRequests() == 0 and #resolver:GetDamageEvents() == 0
	and #resolver:GetHealthChangedEvents() == 0 and #resolver:GetDeathEvents() == 0,
	"Target restore should clear all DamageResolver frame-local outputs")

-- A later provider failure must restore the exact pre-transaction output objects.
hit(5, 2)
local previousRequests = resolver:GetDamageRequests()
local previousDamage = resolver:GetDamageEvents()
local previousHealth = resolver:GetHealthChangedEvents()
local probe = { FailTarget = false }
function probe:CaptureRollbackState() return { Version = 1 } end
function probe:ValidateRollbackState(state) return type(state) == "table" and state.Version == 1 end
function probe:PrepareRollbackRestore(state, restoreWorld, context, role)
	return function()
		if role == "Target" and self.FailTarget then
			self.FailTarget = false
			error("Injected post-damage commit failure")
		end
	end
end
schema:RegisterStateProvider("zz.test.failure.v1", probe)
local failureSnapshot = schema:Capture(world)
hit(7, 3)
previousRequests = resolver:GetDamageRequests()
previousDamage = resolver:GetDamageEvents()
previousHealth = resolver:GetHealthChangedEvents()
probe.FailTarget = true
local failed, detail = schema:Restore(world, failureSnapshot)
check(failed == false and string.find(tostring(detail), "Injected post-damage commit failure", 1, true),
	"Injected later failure should abort the restore")
local afterRequests = resolver:GetDamageRequests()
local afterDamage = resolver:GetDamageEvents()
local afterHealth = resolver:GetHealthChangedEvents()
check(#afterRequests == #previousRequests and #afterDamage == #previousDamage
	and #afterHealth == #previousHealth, "Compensation should restore resolver output lengths")
for index, value in ipairs(previousRequests) do check(afterRequests[index] == value, "Request identity changed on compensation") end
for index, value in ipairs(previousDamage) do check(afterDamage[index] == value, "Damage event identity changed on compensation") end
for index, value in ipairs(previousHealth) do check(afterHealth[index] == value, "Health event identity changed on compensation") end

-- Death is deterministic gameplay state: rewinding to an alive snapshot must restore both
-- the health value and the entity lifecycle state, and must not republish stale death events.
local currentEntity = world:GetEntity(entityId)
local currentHealth = currentEntity:GetComponent(HealthComponent)
local lethalEvent = resolver:Resolve(DamageRequest.new({
	Amount = currentHealth:GetHealth() + 1,
	Target = currentEntity,
	Type = "Physical",
}), 4, 4 / 60)
check(lethalEvent ~= nil and currentEntity:IsDead() and currentHealth:GetHealth() == 0,
	"Lethal damage must set health to zero and transition the entity to Dead")
check(#resolver:GetDeathEvents() == 1 and resolver:GetDeathEvents()[1].Entity == currentEntity,
	"A lethal damage resolution must produce exactly one DeathEvent")

local deathRewindOk, deathRewindError = schema:Restore(world, failureSnapshot)
check(deathRewindOk, "Rewinding a death must succeed: " .. tostring(deathRewindError))
local aliveAfterRewind = world:GetEntity(entityId)
local healthAfterRewind = aliveAfterRewind:GetComponent(HealthComponent)
check(aliveAfterRewind:IsAlive() and healthAfterRewind:GetHealth() == 75,
	"Rewinding before death must restore Alive state and the saved health")
check(#resolver:GetDeathEvents() == 0 and #resolver:GetDamageEvents() == 0
	and #resolver:GetHealthChangedEvents() == 0 and #resolver:GetDamageRequests() == 0,
	"Death rewind must clear stale frame-local damage and death outputs")

local repeatedLethal = resolver:Resolve(DamageRequest.new({
	Amount = 1000,
	Target = aliveAfterRewind,
	Type = "Physical",
}), 5, 5 / 60)
check(repeatedLethal ~= nil and aliveAfterRewind:IsDead(),
	"The entity must be able to die again after a successful rewind")
check(#resolver:GetDeathEvents() == 1,
	"Replaying lethal damage after rewind must emit one fresh DeathEvent, not stale duplicates")
local duplicateAfterDeath = resolver:Resolve(DamageRequest.new({
	Amount = 1000,
	Target = aliveAfterRewind,
	Type = "Physical",
}), 5, 5 / 60)
check(duplicateAfterDeath == nil and #resolver:GetDeathEvents() == 1,
	"Damage against an already-dead entity must not emit a duplicate DeathEvent")

world:Destroy()
print("CombatDamageRollbackIntegrationTest: PASS")

end
