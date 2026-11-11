local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local Combat = Shared:WaitForChild("Combat")
local SimulationModules = Shared:WaitForChild("Simulation")

local EntityState = require(Core.EntityState)
local World = require(Core.World)
local Simulation = require(SimulationModules.Simulation)
local Attack = require(Combat.Attack)
local AttackInstance = require(Combat.AttackInstance)
local Damage = require(Combat.Damage)
local HealthComponent = require(Combat.HealthComponent)
local StatusContainer = require(Combat.StatusContainer)
local DefenseComponent = require(Combat.DefenseComponent)
local DefenseResult = require(Combat.DefenseResult)
local Hitbox = require(Combat.Hitbox)
local Hurtbox = require(Combat.Hurtbox)
local CollisionWorld = require(Combat.CollisionWorld)

local function createImpact(options)
	local world = World.new()
	local collisionWorld = CollisionWorld.new(world)
	local simulation = Simulation.new(world, { FixedDeltaTime = 0.1 })
	local attacker = world:CreateEntity()
	local target = world:CreateEntity()
	local health
	if options.Health ~= false then
		health = target:AddComponent(HealthComponent.new({ MaxHealth = 100 }))
	end
	local statuses = target:AddComponent(StatusContainer.new())
	local defense = target:AddComponent(DefenseComponent.new())
	target:AddComponent(Hurtbox.new({ Shape = "Sphere", Radius = 1 }))
	if options.Block then
		defense:SetBlocking(true)
	end
	if options.ParryFrames then
		defense:OpenParryWindow(1, options.ParryFrames)
	end

	local attack = Attack.new({
		Id = options.Id or "PropertyTest",
		Damage = options.Damage,
		Hitstun = options.Hitstun,
		Defense = options.Defense,
		Priority = options.Priority,
	})
	local instance = AttackInstance.new(attack, attacker):Activate()
	local hitbox = Hitbox.new({ Shape = "Sphere", Radius = 1 })
	instance:AddHitbox(hitbox)
	attacker:AddComponent(hitbox)
	simulation:Step()

	return {
		World = world,
		CollisionWorld = collisionWorld,
		Simulation = simulation,
		Attacker = attacker,
		Target = target,
		Health = health,
		Statuses = statuses,
		Defense = defense,
		Attack = attack,
		Instance = instance,
		Hitbox = hitbox,
		HitEvent = collisionWorld:GetHitEvents()[1],
		DefenseEvent = world:GetDefenseEvents()[1],
		DamageRequests = world:GetDamageRequests(),
		DamageEvents = world:GetDamageEvents(),
	}
end

-- Optional properties have documented defaults; omitted Damage remains absent.
local emptyAttack = Attack.new({})
assert(emptyAttack.Id == "Attack" and emptyAttack.Damage == nil
	and emptyAttack.OffensiveProperties.Hitstun == 0
	and emptyAttack.OffensiveProperties.Defense.CanBlock == true
	and emptyAttack.OffensiveProperties.Defense.CanParry == true
	and emptyAttack.OffensiveProperties.CanClash == true
	and emptyAttack.Priority == 0,
	"An empty Attack should use safe defaults without inventing a Damage payload")

local sharedDamage = Damage.new({ Amount = 10, Type = "Physical" })
local configuredAttack = Attack.new({
	Id = "Configured",
	Damage = sharedDamage,
	Hitstun = 12,
	Defense = { CanBlock = false, CanParry = true },
	Priority = 7,
})
local numericDamage = Attack.new({ Id = "NumericDamage", Damage = 5 })
local hitstunOnly = Attack.new({ Id = "HitstunOnly", Hitstun = 10 })
local defenseOnly = Attack.new({ Id = "DefenseOnly", Defense = { CanBlock = false } })
assert(configuredAttack.OffensiveProperties.Damage == sharedDamage
	and configuredAttack.OffensiveProperties.Hitstun == 12
	and configuredAttack.OffensiveProperties.Defense.CanBlock == false
	and configuredAttack.OffensiveProperties.Defense.CanParry == true
	and configuredAttack.OffensiveProperties.Priority == 7,
	"Attack should normalize its offensive properties into one configuration object")
assert(numericDamage.Damage.Amount == 5 and hitstunOnly.OffensiveProperties.Hitstun == 10
	and defenseOnly.OffensiveProperties.Defense.CanBlock == false,
	"Damage-only, Hitstun-only, and Defense-only attacks should be valid")
assert(table.isfrozen(configuredAttack) and table.isfrozen(configuredAttack.OffensiveProperties)
	and table.isfrozen(configuredAttack.OffensiveProperties.Defense)
	and table.isfrozen(sharedDamage), "Attack definitions and their nested properties should be immutable")

-- Invalid offensive values are rejected at definition creation.
local invalidCases = {
	function() Attack.new({ Damage = -1 }) end,
	function() Attack.new({ Hitstun = -1 }) end,
	function() Attack.new({ Priority = math.huge }) end,
	function() Attack.new({ Priority = 0 / 0 }) end,
	function() Attack.new({ Priority = "high" }) end,
	function() Attack.new({ CanClash = "yes" }) end,
	function() Attack.new({ Defense = { CanBlock = 1 } }) end,
}
for _, createInvalid in ipairs(invalidCases) do
	assert(not pcall(createInvalid), "Invalid Attack property values should fail deterministically")
end

-- CustomData is copied, serializable, recursively frozen, and supports shallow instance overrides.
local sourceData = { Radius = 2, Nested = { Enabled = true } }
local customAttack = Attack.new({ Id = "CustomData", Damage = 1, CustomData = sourceData })
sourceData.Radius = 99
assert(customAttack.CustomData == customAttack.OffensiveProperties.CustomData
	and customAttack.CustomData.Radius == 2 and table.isfrozen(customAttack.CustomData)
	and table.isfrozen(customAttack.CustomData.Nested), "CustomData should be defensively copied and recursively frozen")
assert(Attack.new({ CustomData = {} }).CustomData == nil, "Empty CustomData should normalize to nil")
assert(not pcall(function() Attack.new({ CustomData = { Bad = function() end } }) end),
	"CustomData must reject non-serializable values")
local customOwner = World.new():CreateEntity()
local overridden = AttackInstance.new(customAttack, customOwner, nil, { CustomDataOverrides = { Radius = 5, Extra = "charge" } })
assert(overridden.OffensiveProperties.CustomData.Radius == 5
	and overridden.OffensiveProperties.CustomData.Nested == customAttack.CustomData.Nested
	and overridden.CustomDataOverrides.Radius == 5
	and overridden.Attack.CustomData.Radius == 2,
	"Instance overrides should shallow-merge without mutating the Attack definition")
assert(AttackInstance.new(customAttack, customOwner).OffensiveProperties == customAttack.OffensiveProperties,
	"Instances without overrides should share the frozen offensive properties")

-- Runtime state belongs to each AttackInstance; both hold the same immutable definition snapshot.
local instanceWorld = World.new()
local owner = instanceWorld:CreateEntity()
local instanceA = AttackInstance.new(configuredAttack, owner)
local instanceB = AttackInstance.new(configuredAttack, owner)
assert(instanceA.Id ~= instanceB.Id and instanceA.Attack == configuredAttack
	and instanceA.OffensiveProperties == configuredAttack.OffensiveProperties
	and instanceB.OffensiveProperties == configuredAttack.OffensiveProperties,
	"AttackInstances should have unique runtime identity and capture immutable properties")
instanceA:Activate()
assert(instanceA.State == "Active" and instanceB.State == "Created"
	and instanceB.OffensiveProperties.Damage.Amount == 10,
	"Changing one instance lifecycle must not affect another instance or its properties")
assert(not pcall(function()
	configuredAttack.OffensiveProperties.Priority = 99
end), "An existing definition snapshot must not be mutable")

-- Default Blockable + normal damage runs through HitEvent, defense, damage, health, and reactions.
local normal = createImpact({ Damage = 10, Hitstun = 3 })
assert(normal.HitEvent.OffensiveProperties == normal.Instance.OffensiveProperties
	and normal.HitEvent.OffensiveProperties.Damage.Amount == 10
	and normal.HitEvent.OffensiveProperties.Hitstun == 3
	and normal.HitEvent.Priority == 0,
	"HitEvent should expose the AttackInstance's single offensive-property snapshot")
assert(normal.DefenseEvent.Result == DefenseResult.Normal and #normal.DamageRequests == 1
	and #normal.DamageEvents == 1 and normal.Health:GetHealth() == 90
	and normal.Statuses:HasStatus("Hitstun")
	and normal.DamageEvents[1].OffensiveProperties == normal.HitEvent.OffensiveProperties,
	"Normal hits should apply Damage and the configured Hitstun reaction")
assert(normal.Target:GetState() == EntityState.Alive,
	"Offensive property processing should not alter the target's Core state")

-- Blockable attacks are blocked; non-blockable attacks bypass Block without changing Defense state.
local blocked = createImpact({ Damage = 20, Hitstun = 5, Block = true })
assert(blocked.DefenseEvent.Result == DefenseResult.Blocked and #blocked.DamageRequests == 0
	and #blocked.DamageEvents == 0 and blocked.Health:GetHealth() == 100
	and not blocked.Statuses:HasStatus("Hitstun"),
	"A blocked attack should create no damage or Hitstun")

local bypassBlock = createImpact({
	Damage = 4,
	Block = true,
	Defense = { CanBlock = false, CanParry = true },
})
assert(bypassBlock.DefenseEvent.Result == DefenseResult.Normal
	and #bypassBlock.DamageRequests == 1 and bypassBlock.Health:GetHealth() == 96,
	"CanBlock=false should let an attack pass through active Block")

-- Parryability is independent from Damage and Blockability; Parry > Block only when permitted.
local parried = createImpact({
	Damage = 12,
	Hitstun = 8,
	Block = true,
	ParryFrames = 1,
})
assert(parried.DefenseEvent.Result == DefenseResult.Parried and #parried.DamageRequests == 0
	and #parried.DamageEvents == 0 and parried.Health:GetHealth() == 100
	and not parried.Statuses:HasStatus("Hitstun"),
	"Parryable attacks should be Parried ahead of Block and skip damage and reactions")

local cannotParry = createImpact({
	Damage = 6,
	ParryFrames = 1,
	Defense = { CanParry = false },
})
assert(cannotParry.DefenseEvent.Result == DefenseResult.Normal
	and cannotParry.Health:GetHealth() == 94,
	"CanParry=false should disable Parry when Block is inactive")

local fallbackBlock = createImpact({
	Damage = 6,
	Block = true,
	ParryFrames = 1,
	Defense = { CanParry = false, CanBlock = true },
})
assert(fallbackBlock.DefenseEvent.Result == DefenseResult.Blocked
	and #fallbackBlock.DamageRequests == 0,
	"A non-parryable attack should fall through to Block when it can be blocked")

local bypassBoth = createImpact({
	Damage = 3,
	Block = true,
	ParryFrames = 1,
	Defense = { CanParry = false, CanBlock = false },
})
assert(bypassBoth.DefenseEvent.Result == DefenseResult.Normal
	and #bypassBoth.DamageRequests == 1 and bypassBoth.Health:GetHealth() == 97,
	"An attack that bypasses both defenses should resolve as Normal")

-- Attacks without damage still reach Defense; Defense does not require HealthComponent.
local noDamageParry = createImpact({ Health = false, ParryFrames = 1 })
assert(noDamageParry.HitEvent and noDamageParry.DefenseEvent.Result == DefenseResult.Parried
	and #noDamageParry.DamageRequests == 0 and noDamageParry.Target:GetComponent(HealthComponent) == nil,
	"A no-damage attack should still interact with Parry on an entity without Health")

local noHitstun = createImpact({ Damage = 2 })
assert(#noHitstun.DamageEvents == 1 and not noHitstun.Statuses:HasStatus("Hitstun"),
	"Damage without Hitstun should not apply a reaction")

-- Priority remains available as data and does not override defensive rules.
local lowPriorityBlocked = createImpact({ Damage = 1, Block = true, Priority = -2 })
local highPriorityBlocked = createImpact({ Damage = 1, Block = true, Priority = 100 })
assert(lowPriorityBlocked.Attack.OffensiveProperties.Priority == -2
	and highPriorityBlocked.HitEvent.OffensiveProperties.Priority == 100
	and lowPriorityBlocked.DefenseEvent.Result == DefenseResult.Blocked
	and highPriorityBlocked.DefenseEvent.Result == DefenseResult.Blocked,
	"Priority should be preserved without changing Block or Parry outcomes")

-- Repeating an equivalent interaction produces the same semantic trace.
local function getTrace()
	local impact = createImpact({
		Damage = 7,
		Hitstun = 4,
		Block = true,
		ParryFrames = 1,
		Priority = 12,
	})
	local defenseEvent = impact.DefenseEvent
	return table.concat({
		defenseEvent.Result,
		tostring(defenseEvent.AttackInstanceId),
		tostring(defenseEvent.OffensiveProperties.Priority),
		tostring(#impact.DamageRequests),
		tostring(impact.Health:GetHealth()),
	}, ":")
end
assert(getTrace() == getTrace(), "Equivalent attack properties and defense inputs should be deterministic")

print("Combat attack properties tests passed")
