local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core, Combat = Shared:WaitForChild("Core"), Shared:WaitForChild("Combat")
local World = require(Core.World)
local EntityState = require(Core.EntityState)
local Attack = require(Combat.Attack)
local AttackInstance = require(Combat.AttackInstance)
local CollisionWorld = require(Combat.CollisionWorld)
local CounterResolver = require(Combat.CounterResolver)
local CounterResult = require(Combat.CounterResult)
local DefenseComponent = require(Combat.DefenseComponent)
local DefenseResult = require(Combat.DefenseResult)
local HealthComponent = require(Combat.HealthComponent)
local HitEvent = require(Combat.HitEvent)
local Hitbox = require(Combat.Hitbox)
local Hurtbox = require(Combat.Hurtbox)
local OffensiveStateComponent = require(Combat.OffensiveStateComponent)

local world = World.new()
local collision = CollisionWorld.new(world)
local attacker, target = world:CreateEntity(), world:CreateEntity()
local health = target:AddComponent(HealthComponent.new({ MaxHealth = 50 }))
local offense = target:AddComponent(OffensiveStateComponent.new())
local attack = Attack.new({ Damage = 7 })
local instanceA = AttackInstance.new(attack, attacker)
local instanceB = AttackInstance.new(attack, attacker)
local function hit(instance, frame, targetEntity)
	return HitEvent.new({ Attack = attack, AttackInstance = instance, AttackInstanceId = instance.Id,
		Attacker = attacker, AttackerEntityId = attacker.Id, Target = targetEntity or target,
		TargetEntityId = (targetEntity or target).Id, Frame = frame,
		HitboxId = 900 + instance.Id, HurtboxId = 700 + (targetEntity or target).Id })
end

local resolver = CounterResolver.new()
local ordinary = hit(instanceA, 1)
assert(#resolver:Process({ ordinary }) == 1
	and resolver:GetResults()[1].Type == CounterResult.Type.Normal,
	"An ordinary hit should resolve as Normal")
assert(offense:SetWindow(2, 2), "An offensive window should open")
local counter = hit(instanceA, 2)
local counterResults = resolver:Process({ counter })
assert(counterResults[1].Type == CounterResult.Type.CounterHit
	and counterResults[1].AttackInstance == instanceA and counterResults[1].Target == target,
	"A vulnerable offensive target should produce a CounterHit tied to its AttackInstance")
assert(resolver:Process({ hit(instanceA, 4) })[1].Type == CounterResult.Type.Normal,
	"An offensive window should expire after its inclusive end frame")
assert(offense:SetWindow(5, 1) and offense:EndWindow()
	and not offense:IsVulnerable(5), "An offensive window should end manually")
assert(offense:SetWindow(6, 2) and offense:IsVulnerable(6), "A new window should open after cleanup")

-- Instance identity and stable sorting are independent from the incoming event order.
local multiA, multiB = hit(instanceA, 6), hit(instanceB, 6)
local first = resolver:Process({ multiB, multiA })
local second = resolver:Process({ multiA, multiB })
assert(#first == 2 and #second == 2 and first[1].AttackInstanceId == second[1].AttackInstanceId
	and first[2].AttackInstanceId == second[2].AttackInstanceId,
	"Distinct attack executions should resolve independently in stable order")
assert(#resolver:Process({ multiA, multiA }) == 1,
	"A repeated contact should not create duplicate CounterResults")
local noHealthTarget = world:CreateEntity()
local noHealthOffense = noHealthTarget:AddComponent(OffensiveStateComponent.new())
noHealthOffense:SetWindow(6, 1)
local healthlessHit = hit(instanceA, 6, noHealthTarget)
assert(resolver:Process({ healthlessHit })[1].Type == CounterResult.Type.CounterHit
	and noHealthTarget:GetComponent(HealthComponent) == nil,
	"CounterHit must work without HealthComponent")

local defense = target:AddComponent(DefenseComponent.new())
local blocked = hit(instanceA, 6)
local defenseEvents = { { HitEvent = blocked, Result = DefenseResult.Blocked } }
assert(#resolver:Process({ blocked }, defenseEvents) == 0,
	"Blocked contacts should be excluded from Counter resolution")
local parried = hit(instanceB, 6)
defenseEvents = { { HitEvent = parried, Result = DefenseResult.Parried } }
assert(#resolver:Process({ parried }, defenseEvents) == 0,
	"Parried contacts should be excluded from Counter resolution")
assert(health:GetHealth() == 50, "Counter resolution must not apply damage or alter HP")

-- Pipeline integration: collision, combat resolution, defense, Counter, then ordinary damage.
local integratedWorld = World.new()
local integratedCollision = CollisionWorld.new(integratedWorld)
local source, vulnerable = integratedWorld:CreateEntity(), integratedWorld:CreateEntity()
local vulnerableHealth = vulnerable:AddComponent(HealthComponent.new({ MaxHealth = 30 }))
local vulnerableOffense = vulnerable:AddComponent(OffensiveStateComponent.new())
vulnerable:AddComponent(Hurtbox.new({ Shape = "Sphere", Radius = 1 }))
local execution = AttackInstance.new(Attack.new({ Damage = 5 }), source):Activate()
local hitbox = execution:AddHitbox(Hitbox.new({ Shape = "Sphere", Radius = 1 }))
source:AddComponent(hitbox)
vulnerableOffense:SetWindow(1, 1)
integratedWorld:Step(1 / 60, 1, 1 / 60)
local results = integratedWorld:GetCounterResults()
assert(#results == 1 and results[1].Type == CounterResult.Type.CounterHit
	and results[1].AttackInstance == execution and vulnerableHealth:GetHealth() == 25,
	"Collision through Defense and Counter should record a CounterHit and leave damage to DamageResolver")

-- Block suppresses Counter but retains the regular defense behavior.
vulnerableOffense:SetWindow(2, 2)
local blockComponent = vulnerable:AddComponent(DefenseComponent.new())
blockComponent:SetBlocking(true)
local blockedSource = integratedWorld:CreateEntity()
local blockedExecution = AttackInstance.new(Attack.new({ Damage = 5 }), blockedSource):Activate()
blockedSource:AddComponent(blockedExecution:AddHitbox(Hitbox.new({ Shape = "Sphere", Radius = 1 })))
integratedWorld:Step(1 / 60, 2, 2 / 60)
assert(#integratedWorld:GetCounterResults() == 0 and vulnerableHealth:GetHealth() == 25,
	"A blocked contact must not Counter and must not damage")

local dead = integratedWorld:CreateEntity()
dead:SetState(EntityState.Dead)
local deadOffense = dead:AddComponent(OffensiveStateComponent.new())
local ok = pcall(function() deadOffense:SetWindow(3, 2) end)
assert(not ok, "Starting a window on a dead entity must be rejected")
assert(offense:SetWindow(7, 1), "Living entities can open another window")
target:SetState(EntityState.Dead)
assert(not offense.Active and not offense:IsVulnerable(7), "Dead entities must immediately clear vulnerability")
local deadHit = hit(instanceA, 7, dead)
assert(#resolver:Process({ deadHit }) == 0, "Dead entities cannot generate Counter results")
attacker:SetState(EntityState.Dead)
noHealthOffense:SetWindow(7, 1)
assert(#resolver:Process({ hit(instanceA, 7, noHealthTarget) }) == 0,
	"A dead attacker cannot generate a CounterHit")

local cleanupEntity = world:CreateEntity()
local cleanup = cleanupEntity:AddComponent(OffensiveStateComponent.new())
cleanup:SetWindow(10, 5)
cleanupEntity:RemoveComponent(OffensiveStateComponent)
assert(not cleanup:IsVulnerable(10) and cleanup.Entity == nil,
	"Removing the component must clear its offensive window")
cleanupEntity:AddComponent(OffensiveStateComponent.new()):SetWindow(10, 1)
world:DestroyEntity(cleanupEntity)
assert(not cleanup:IsVulnerable(10), "Entity destruction must detach and clear offensive state")

print("Combat counter tests passed")
