return function()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local Combat = Shared:WaitForChild("Combat")
local SimulationModules = Shared:WaitForChild("Simulation")

local EntityState = require(Core.EntityState)
local World = require(Core.World)
local Simulation = require(SimulationModules.Simulation)
local HealthComponent = require(Combat.HealthComponent)
local Status = require(Combat.Status)
local StatusContainer = require(Combat.StatusContainer)
local Hitstun = require(Combat.Hitstun)
local Attack = require(Combat.Attack)
local AttackInstance = require(Combat.AttackInstance)
local Damage = require(Combat.Damage)
local Hitbox = require(Combat.Hitbox)
local Hurtbox = require(Combat.Hurtbox)
local CollisionWorld = require(Combat.CollisionWorld)

local function createCombatWorld(fixedDeltaTime)
	local world = World.new()
	local collisionWorld = CollisionWorld.new(world)
	local simulation = Simulation.new(world, { FixedDeltaTime = fixedDeltaTime or 0.1 })
	return world, collisionWorld, simulation
end

-- Generic statuses use the Component-backed container and expose stable lifecycle data.
local world, _, simulation = createCombatWorld()
local entity = world:CreateEntity()
local statuses = entity:AddComponent(StatusContainer.new())
local generic = Status.new({ Name = "TestEffect", DurationFrames = 2 })
local added, addResult = statuses:AddStatus(generic)
assert(added == generic and addResult == "Added", "StatusContainer should accept a new status")
assert(statuses:HasStatus("TestEffect") and statuses:GetStatus("TestEffect") == generic,
	"StatusContainer should query and return active statuses")
simulation:Step()
assert(generic:GetRemainingFrames() == 1, "Status duration should decrease by one simulation frame")
simulation:Step()
assert(not statuses:HasStatus("TestEffect") and generic.Active == false,
	"Finite statuses should expire and be removed deterministically")
local statusEvents = statuses:GetEvents()
assert(statusEvents[#statusEvents].Type == "StatusExpired"
	and statusEvents[#statusEvents].Status == generic,
	"StatusContainer should record expiration as deterministic data")

local removable = Status.new({ Name = "Manual" })
statuses:AddStatus(removable)
assert(statuses:RemoveStatus("Manual") and not statuses:HasStatus("Manual"),
	"StatusContainer should remove a status by name")
assert(not statuses:RemoveStatus("Missing"), "Removing a missing status should be safe")

local extendable = Status.new({ Name = "Extendable", DurationFrames = 2, ReapplicationPolicy = "Extend" })
statuses:AddStatus(extendable)
local extended, extendResult = statuses:AddStatus(Status.new({
	Name = "Extendable", DurationFrames = 3, ReapplicationPolicy = "Extend",
}))
assert(extended == extendable and extendResult == "Extended"
	and extendable:GetRemainingFrames() == 5,
	"Alternative status policies should be configurable without changing StatusContainer")
statuses:RemoveStatus(extendable)

-- Hitstun is status data, never a Core EntityState. Reapplication defaults to Refresh.
local hitstun = Hitstun.new({ DurationFrames = 3 })
local activeHitstun = statuses:AddStatus(hitstun)
assert(activeHitstun == hitstun and entity:GetState() == EntityState.Alive
	and entity:GetState() ~= "Hitstun", "Hitstun must not replace the Core lifecycle state")
simulation:Step()
assert(hitstun:GetRemainingFrames() == 2, "Hitstun should count down in fixed simulation frames")
local refreshed, refreshResult = statuses:AddStatus(Hitstun.new({ DurationFrames = 5 }))
assert(refreshed == hitstun and refreshResult == "Refreshed"
	and hitstun:GetRemainingFrames() == 5,
	"The default Hitstun policy should refresh the existing duration")
for _ = 1, 5 do
	simulation:Step()
end
assert(not statuses:HasStatus("Hitstun"), "Refreshed Hitstun should expire after its frame duration")

-- Disabled containers pause status processing; re-enabling resumes fixed-frame countdown.
local pausedStatus = Status.new({ Name = "Paused", DurationFrames = 2 })
statuses:AddStatus(pausedStatus)
statuses:SetEnabled(false)
simulation:Step()
assert(pausedStatus:GetRemainingFrames() == 2, "Disabled StatusContainer should not process statuses")
statuses:SetEnabled(true)
simulation:Step()
assert(pausedStatus:GetRemainingFrames() == 1, "Re-enabled StatusContainer should resume processing")
simulation:Step()
assert(not statuses:HasStatus("Paused"), "Resumed status should expire normally")

local individuallyPaused = Status.new({ Name = "IndividuallyPaused", DurationFrames = 2, Enabled = false })
statuses:AddStatus(individuallyPaused)
simulation:Step()
assert(individuallyPaused:GetRemainingFrames() == 2,
	"Disabled statuses should not update or consume duration")
individuallyPaused:SetEnabled(true)
simulation:Step()
assert(individuallyPaused:GetRemainingFrames() == 1,
	"Re-enabled statuses should resume their duration")
statuses:RemoveStatus(individuallyPaused)

-- DamageEvent applies configured Hitstun during the same deterministic World step.
local reactionWorld, reactionCollisionWorld, reactionSimulation = createCombatWorld()
local attacker = reactionWorld:CreateEntity()
local target = reactionWorld:CreateEntity()
local targetHealth = target:AddComponent(HealthComponent.new({ MaxHealth = 30 }))
local targetStatuses = target:AddComponent(StatusContainer.new())
target:AddComponent(Hurtbox.new({ Shape = "Sphere", Radius = 1 }))
local attack = Attack.new({ Id = "Stunning", Damage = Damage.new({ Amount = 7 }), Hitstun = 4 })
local attackInstance = AttackInstance.new(attack, attacker):Activate()
local attackHitbox = Hitbox.new({ Shape = "Sphere", Radius = 1 })
attackInstance:AddHitbox(attackHitbox)
attacker:AddComponent(attackHitbox)
reactionSimulation:Step()

local hitEvents = reactionCollisionWorld:GetHitEvents()
local damageEvents = reactionWorld:GetDamageEvents()
local appliedHitstun = targetStatuses:GetStatus("Hitstun")
assert(#hitEvents == 1 and #damageEvents == 1 and damageEvents[1].HitstunFrames == 4,
	"Attack Hitstun should be preserved through HitEvent and DamageEvent")
assert(targetHealth:GetHealth() == 23 and appliedHitstun
	and appliedHitstun:GetRemainingFrames() == 4,
	"Damage should apply Hitstun in the same fixed step without decrementing its initial frame")
assert(appliedHitstun.Source == attacker and appliedHitstun.AttackInstance == attackInstance
	and appliedHitstun.HitEvent == hitEvents[1] and appliedHitstun.DamageEvent == damageEvents[1],
	"Hitstun should preserve source and attack context")
for _ = 1, 4 do
	reactionSimulation:Step()
end
assert(not targetStatuses:HasStatus("Hitstun"), "Integrated Hitstun should expire after four later steps")

-- Damage without a reaction remains valid and does not add a status implicitly.
local plainAttack = Attack.new({ Id = "PlainDamage", Damage = Damage.new({ Amount = 2 }) })
local plainInstance = AttackInstance.new(plainAttack, attacker):Activate()
local plainCarrier = reactionWorld:CreateEntity()
local plainHitbox = Hitbox.new({ Shape = "Sphere", Radius = 1 })
plainInstance:AddHitbox(plainHitbox)
plainCarrier:AddComponent(plainHitbox)
reactionSimulation:Step()
assert(#reactionWorld:GetDamageEvents() == 1 and not targetStatuses:HasStatus("Hitstun"),
	"An attack without Hitstun should damage without adding a reaction")

-- Several same-frame hits are consumed in stable HitEvent order; Refresh leaves the last event's duration.
local simultaneousWorld, _, simultaneousSimulation = createCombatWorld()
local simultaneousAttacker = simultaneousWorld:CreateEntity()
local simultaneousTarget = simultaneousWorld:CreateEntity()
local simultaneousCarrier = simultaneousWorld:CreateEntity()
local simultaneousHealth = simultaneousTarget:AddComponent(HealthComponent.new({ MaxHealth = 50 }))
local simultaneousStatuses = simultaneousTarget:AddComponent(StatusContainer.new())
simultaneousTarget:AddComponent(Hurtbox.new({ Shape = "Sphere", Radius = 1 }))
local firstAttack = Attack.new({ Id = "SimultaneousA", Damage = Damage.new({ Amount = 2 }), Hitstun = 3 })
local secondAttack = Attack.new({ Id = "SimultaneousB", Damage = Damage.new({ Amount = 4 }), Hitstun = 5 })
local firstInstance = AttackInstance.new(firstAttack, simultaneousAttacker):Activate()
local secondInstance = AttackInstance.new(secondAttack, simultaneousAttacker):Activate()
local firstHitbox = Hitbox.new({ Shape = "Sphere", Radius = 1 })
local secondHitbox = Hitbox.new({ Shape = "Sphere", Radius = 1 })
firstInstance:AddHitbox(firstHitbox)
secondInstance:AddHitbox(secondHitbox)
simultaneousAttacker:AddComponent(firstHitbox)
simultaneousCarrier:AddComponent(secondHitbox)
simultaneousSimulation:Step()
local simultaneousDamage = simultaneousWorld:GetDamageEvents()
local simultaneousHitstun = simultaneousStatuses:GetStatus("Hitstun")
assert(#simultaneousDamage == 2 and simultaneousDamage[1].AttackInstance.Id < simultaneousDamage[2].AttackInstance.Id
	and simultaneousHealth:GetHealth() == 44,
	"Same-frame damage should follow stable AttackInstance ordering")
assert(simultaneousHitstun and simultaneousHitstun:GetRemainingFrames() == 5
	and simultaneousHitstun.AttackInstance == secondInstance,
	"Same-frame Hitstun refreshes should resolve in that stable order")

-- Lethal damage clears current statuses and cannot apply the lethal attack's Hitstun.
local lethalWorld, _, lethalSimulation = createCombatWorld()
local lethalAttacker = lethalWorld:CreateEntity()
local lethalTarget = lethalWorld:CreateEntity()
lethalTarget:AddComponent(HealthComponent.new({ MaxHealth = 5 }))
local lethalStatuses = lethalTarget:AddComponent(StatusContainer.new())
lethalStatuses:AddStatus(Hitstun.new({ DurationFrames = 8 }))
lethalTarget:AddComponent(Hurtbox.new({ Shape = "Sphere", Radius = 1 }))
local lethalAttack = Attack.new({ Id = "Lethal", Damage = Damage.new({ Amount = 5 }), Hitstun = 9 })
local lethalInstance = AttackInstance.new(lethalAttack, lethalAttacker):Activate()
local lethalHitbox = Hitbox.new({ Shape = "Sphere", Radius = 1 })
lethalInstance:AddHitbox(lethalHitbox)
lethalAttacker:AddComponent(lethalHitbox)
lethalSimulation:Step()
assert(lethalTarget:IsDead() and not lethalTarget.Destroyed
	and not lethalStatuses:HasStatus("Hitstun"),
	"Death should clear existing statuses and prevent new Hitstun without destroying the entity")
local deadAddition, deadReason = lethalStatuses:AddStatus(Hitstun.new({ DurationFrames = 2 }))
assert(deadAddition == nil and deadReason == "EntityUnavailable",
	"Dead entities should reject new combat statuses")

-- A StatusContainer is optional and does not require HealthComponent.
local statusOnly = reactionWorld:CreateEntity()
local statusOnlyContainer = statusOnly:AddComponent(StatusContainer.new())
assert(statusOnly:GetComponent(HealthComponent) == nil,
	"Status-bearing entities must not acquire HealthComponent automatically")
assert(statusOnlyContainer:AddStatus(Hitstun.new({ DurationFrames = 1 })) ~= nil,
	"StatusContainer should work without HealthComponent")

-- Destroying the entity runs the container lifecycle and removes all active statuses.
local destroyWorld = World.new()
local destroyEntity = destroyWorld:CreateEntity()
local destroyContainer = destroyEntity:AddComponent(StatusContainer.new())
local destroyStatus = destroyContainer:AddStatus(Status.new({ Name = "Cleanup" }))
assert(destroyWorld:DestroyEntity(destroyEntity), "Status-bearing entity should be destroyable")
assert(destroyEntity.Destroyed and destroyStatus.Active == false and destroyStatus.Entity == nil
	and #destroyContainer:GetStatuses() == 0,
	"Destroying an entity should end and remove every active status")

-- Equal worlds, attacks, and fixed steps produce matching health and reaction state.
local function runDeterministicReaction()
	local replayWorld, _, replaySimulation = createCombatWorld(0.05)
	local replayAttacker = replayWorld:CreateEntity()
	local replayTarget = replayWorld:CreateEntity()
	local replayHealth = replayTarget:AddComponent(HealthComponent.new({ MaxHealth = 20 }))
	local replayStatuses = replayTarget:AddComponent(StatusContainer.new())
	replayTarget:AddComponent(Hurtbox.new({ Shape = "Sphere", Radius = 1 }))
	local replayAttack = Attack.new({ Id = "Replay", Damage = Damage.new({ Amount = 3 }), Hitstun = 3 })
	local replayInstance = AttackInstance.new(replayAttack, replayAttacker):Activate()
	local replayHitbox = Hitbox.new({ Shape = "Sphere", Radius = 1 })
	replayInstance:AddHitbox(replayHitbox)
	replayAttacker:AddComponent(replayHitbox)
	for _ = 1, 3 do
		replaySimulation:Step()
	end
	local active = replayStatuses:GetStatus("Hitstun")
	return {
		Health = replayHealth:GetHealth(),
		Frame = replaySimulation:GetGameTime():GetFrame(),
		HitstunFrames = active and active:GetRemainingFrames() or 0,
		State = replayTarget:GetState(),
	}
end

local traceA = runDeterministicReaction()
local traceB = runDeterministicReaction()
assert(traceA.Health == traceB.Health and traceA.Frame == traceB.Frame
	and traceA.HitstunFrames == traceB.HitstunFrames and traceA.State == traceB.State,
	"Identical combat inputs should reproduce health, frame, state, and Hitstun")

print("Combat reactions tests passed")

end
