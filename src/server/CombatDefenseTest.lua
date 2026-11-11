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
local DefenseComponent = require(Combat.DefenseComponent)
local DefenseResult = require(Combat.DefenseResult)
local DefenseResolver = require(Combat.DefenseResolver)
local Attack = require(Combat.Attack)
local AttackInstance = require(Combat.AttackInstance)
local Damage = require(Combat.Damage)
local Hitbox = require(Combat.Hitbox)
local Hurtbox = require(Combat.Hurtbox)
local CollisionWorld = require(Combat.CollisionWorld)

local function createWorld()
	local world = World.new()
	local collisionWorld = CollisionWorld.new(world)
	local simulation = Simulation.new(world, { FixedDeltaTime = 1 / 60 })
	return world, collisionWorld, simulation
end

-- The component starts neutral and can be used without Player, input, or character objects.
local world, collisionWorld, simulation = createWorld()
local attacker = world:CreateEntity()
local defender = world:CreateEntity()
local health = defender:AddComponent(HealthComponent.new({ MaxHealth = 40 }))
local defense = defender:AddComponent(DefenseComponent.new())
defender:AddComponent(Hurtbox.new({ Shape = "Sphere", Radius = 1 }))
assert(defender:GetComponent(DefenseComponent) == defense and not defense:IsBlocking()
	and not defense:IsParryActive(1), "DefenseComponent should begin with no active defense")

-- Block is resolved before DamageRequest creation, while retaining the HitEvent.
local blockAttack = Attack.new({ Id = "BlockCheck", Damage = Damage.new({ Amount = 10 }) })
local blockInstance = AttackInstance.new(blockAttack, attacker):Activate()
local blockHitbox = Hitbox.new({ Shape = "Sphere", Radius = 1 })
blockInstance:AddHitbox(blockHitbox)
attacker:AddComponent(blockHitbox)
assert(defense:SetBlocking(true) and defense:IsBlocking(), "Block intent should activate")
simulation:Step()
local blockHits = collisionWorld:GetHitEvents()
local blockEvents = world:GetDefenseEvents()
assert(#blockHits == 1 and #blockEvents == 1 and blockEvents[1].Result == DefenseResult.Blocked
	and blockEvents[1].HitEvent == blockHits[1] and blockEvents[1].Attacker == attacker
	and blockEvents[1].Defender == defender and blockEvents[1].AttackInstance == blockInstance,
	"DefenseEvent should preserve the blocked interaction and source context")
assert(#world:GetDamageRequests() == 0 and #world:GetDamageEvents() == 0
	and health:GetHealth() == 40 and defender:GetState() == EntityState.Alive,
	"Blocked attacks should remain visible but cause no DamageRequest or health change")

-- With defense inactive, Normal is recorded and the existing damage path proceeds.
defense:SetBlocking(false)
local normalAttack = Attack.new({ Id = "NormalCheck", Damage = Damage.new({ Amount = 6 }) })
local normalInstance = AttackInstance.new(normalAttack, attacker):Activate()
local normalHitbox = Hitbox.new({ Shape = "Sphere", Radius = 1 })
local normalCarrier = world:CreateEntity()
normalInstance:AddHitbox(normalHitbox)
normalCarrier:AddComponent(normalHitbox)
simulation:Step()
local normalEvents = world:GetDefenseEvents()
assert(#normalEvents == 1 and normalEvents[1].Result == DefenseResult.Normal
	and normalEvents[1].AttackInstance == normalInstance,
	"An undefended hit should produce a Normal DefenseEvent")
assert(#world:GetDamageRequests() == 1 and #world:GetDamageEvents() == 1
	and health:GetHealth() == 34,
	"Normal attacks should continue through the existing Damage and Health systems")

-- Parry works with an attack that has no Damage and a defender with no HealthComponent.
local parryWorld, parryCollisionWorld, parrySimulation = createWorld()
local parryAttacker = parryWorld:CreateEntity()
local parryTarget = parryWorld:CreateEntity()
local parryDefense = parryTarget:AddComponent(DefenseComponent.new())
parryTarget:AddComponent(Hurtbox.new({ Shape = "Sphere", Radius = 1 }))
local parryAttack = Attack.new({ Id = "NoDamageParry" })
local parryInstance = AttackInstance.new(parryAttack, parryAttacker):Activate()
local parryHitbox = Hitbox.new({ Shape = "Sphere", Radius = 1 })
parryInstance:AddHitbox(parryHitbox)
parryAttacker:AddComponent(parryHitbox)
assert(parryDefense:OpenParryWindow(1, 2), "Parry window should open on the requested simulation frame")
parrySimulation:Step()
local parryHits = parryCollisionWorld:GetHitEvents()
local parryEvents = parryWorld:GetDefenseEvents()
assert(#parryHits == 1 and #parryEvents == 1 and parryEvents[1].Result == DefenseResult.Parried
	and parryEvents[1].HitEvent == parryHits[1],
	"A no-damage HitEvent can still be Parried")
assert(parryTarget:GetComponent(HealthComponent) == nil
	and #parryWorld:GetDamageRequests() == 0 and #parryWorld:GetDamageEvents() == 0,
	"Defense must not require Health or create damage for Parry")

-- Parry frames are inclusive at both ends; afterward resolution falls through to Block or Normal.
local resolver = DefenseResolver.new()
local syntheticAttacker = { Id = 10 }
local function syntheticHit(frame, attackInstanceId)
	return {
		Frame = frame,
		Target = parryTarget,
		Attacker = syntheticAttacker,
		Attack = { Id = "Frame" .. tostring(frame) },
		AttackInstance = { Id = attackInstanceId },
		AttackInstanceId = attackInstanceId,
	}
end

assert(parryDefense:OpenParryWindow(10, 3), "A three-frame parry window should open")
local firstFrame = resolver:Process({ syntheticHit(10, 1) }, 10)
assert(#firstFrame == 0 and resolver:GetDefenseEvents()[1].Result == DefenseResult.Parried,
	"The first parry frame should be active")
resolver:Process({ syntheticHit(12, 2) }, 12)
assert(resolver:GetDefenseEvents()[1].Result == DefenseResult.Parried,
	"The final inclusive parry frame should be active")
resolver:Process({ syntheticHit(13, 3) }, 13)
assert(resolver:GetDefenseEvents()[1].Result == DefenseResult.Normal,
	"A hit after the parry window should resolve as Normal when not Blocking")

-- Parry has explicit priority over Block; Block has priority over Normal.
assert(parryDefense:SetBlocking(true), "Block may be enabled while the parry window is configured")
assert(parryDefense:OpenParryWindow(14, 1), "One-frame parry window should open")
resolver:Process({ syntheticHit(14, 4) }, 14)
assert(resolver:GetDefenseEvents()[1].Result == DefenseResult.Parried,
	"Parry should take precedence when Block is also active")
parryDefense:CloseParryWindow()
resolver:Process({ syntheticHit(15, 5) }, 15)
assert(resolver:GetDefenseEvents()[1].Result == DefenseResult.Blocked,
	"Blocking without active Parry should produce Blocked")
parryDefense:SetBlocking(false)
resolver:Process({ syntheticHit(16, 6) }, 16)
assert(resolver:GetDefenseEvents()[1].Result == DefenseResult.Normal,
	"With both defenses inactive the result should be Normal")

-- Multiple same-frame outcomes preserve HitProcessor's stable AttackInstance order.
assert(parryDefense:SetBlocking(true), "Block should be available for simultaneous hits")
local multiple = { syntheticHit(20, 10), syntheticHit(20, 20), syntheticHit(20, 30) }
resolver:Process(multiple, 20)
local simultaneous = resolver:GetDefenseEvents()
assert(#simultaneous == 3 and simultaneous[1].AttackInstanceId == 10
	and simultaneous[2].AttackInstanceId == 20 and simultaneous[3].AttackInstanceId == 30,
	"DefenseResolver should preserve the already-deterministic HitEvent order")
for _, event in ipairs(simultaneous) do
	assert(event.Result == DefenseResult.Blocked, "All simultaneous hits should use the same active Block intent")
end

-- Dead entities cannot start defenses and do not resolve as Blocked or Parried.
parryTarget:SetState(EntityState.Dead)
local blockAccepted = parryDefense:SetBlocking(true)
local parryAccepted = parryDefense:OpenParryWindow(21, 2)
assert(not blockAccepted and not parryAccepted and not parryDefense:IsBlocking()
	and not parryDefense:IsParryActive(21), "Dead entities must not activate defense intents")
resolver:Process({ syntheticHit(21, 40) }, 21)
assert(resolver:GetDefenseEvents()[1].Result == DefenseResult.Normal,
	"Dead targets should not produce a valid Block or Parry result")

-- Equivalent frame inputs produce the same ordered defense trace.
local function defenseTrace()
	local traceResolver = DefenseResolver.new()
	local traceWorld = World.new()
	local traceEntity = traceWorld:CreateEntity()
	local traceDefense = traceEntity:AddComponent(DefenseComponent.new())
	traceDefense:SetBlocking(true)
	local trace = {}
	for frame = 1, 3 do
		local events = traceResolver:Process({ {
			Frame = frame,
			Target = traceEntity,
			AttackInstanceId = frame,
			AttackInstance = { Id = frame },
		} }, frame)
		assert(#events == 0, "Blocked interactions should never pass into the damageable hit list")
		table.insert(trace, traceResolver:GetDefenseEvents()[1].Result .. ":" .. tostring(frame))
	end
	return trace
end

local traceA = defenseTrace()
local traceB = defenseTrace()
assert(#traceA == #traceB, "Equivalent defense traces should have equal length")
for index, entry in ipairs(traceA) do
	assert(entry == traceB[index], "Equivalent defense inputs should reproduce the same results")
end

print("Combat defense tests passed")

end
