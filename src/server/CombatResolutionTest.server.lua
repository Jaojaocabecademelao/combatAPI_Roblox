local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local Combat = Shared:WaitForChild("Combat")

local World = require(Core.World)
local Attack = require(Combat.Attack)
local AttackInstance = require(Combat.AttackInstance)
local CombatResolver = require(Combat.CombatResolver)
local CombatResolutionResult = require(Combat.CombatResolutionResult)
local CollisionWorld = require(Combat.CollisionWorld)
local HealthComponent = require(Combat.HealthComponent)
local HitEvent = require(Combat.HitEvent)
local Hitbox = require(Combat.Hitbox)
local Hurtbox = require(Combat.Hurtbox)

local function fakeHit(instance, attackerId, targetId, attacker, target, frame)
	return HitEvent.new({
		AttackInstance = instance,
		AttackInstanceId = instance.Id,
		Attacker = attacker,
		Target = target,
		AttackerEntityId = attackerId,
		TargetEntityId = targetId,
		Frame = frame or 1,
		OffensiveProperties = instance.OffensiveProperties,
	})
end

local function fakePair(priorityA, priorityB, canClashA, canClashB, ids)
	local world = World.new()
	local entityA, entityB = world:CreateEntity(), world:CreateEntity()
	local instanceA = AttackInstance.new(Attack.new({
		Priority = priorityA,
		CanClash = canClashA,
	}), entityA)
	local instanceB = AttackInstance.new(Attack.new({
		Priority = priorityB,
		CanClash = canClashB,
	}), entityB)
	if ids then
		instanceA.Id, instanceB.Id = ids[1], ids[2]
	end
	local eventA = fakeHit(instanceA, entityA.Id, entityB.Id, entityA, entityB)
	local eventB = fakeHit(instanceB, entityB.Id, entityA.Id, entityB, entityA)
	return world, instanceA, instanceB, eventA, eventB
end

local resolver = CombatResolver.new()
local _, instanceA, instanceB, hitA, hitB = fakePair(4, 4)
assert(instanceA.OffensiveProperties.CanClash == true,
	"CanClash should default to true for ordinary attacks")
local survivors = resolver:Process({ hitA, hitB })
local result = resolver:GetResolutionEvents()[1]
assert(#survivors == 0 and result.Outcome == CombatResolutionResult.Clash
	and result.PriorityA == 4 and result.PriorityB == 4
	and result.AttackInstanceA == instanceA and result.AttackInstanceB == instanceB,
	"Equal-priority reciprocal attacks should produce one Clash and suppress both hits")
assert(#resolver:GetResolutionEvents() == 1,
	"A reciprocal AttackInstance pair must be resolved only once")

-- Event input order and instance creation order do not decide outcomes or event identity.
local _, _, _, orderedA, orderedB = fakePair(4, 4, true, true, { 800, 300 })
resolver:Process({ orderedA, orderedB })
local orderedResult = resolver:GetResolutionEvents()[1]
local firstId = orderedResult.Id
resolver:Process({ orderedB, orderedA })
local reversedResult = resolver:GetResolutionEvents()[1]
local secondId = reversedResult.Id
assert(firstId == secondId and reversedResult.AttackInstanceIdA == 300
	and reversedResult.AttackInstanceIdB == 800,
	"Pair identity and canonical ordering should be independent of HitEvent order")

local _, _, _, highEvent, lowEvent = fakePair(10, 2)
survivors = resolver:Process({ lowEvent, highEvent })
result = resolver:GetResolutionEvents()[1]
assert(result.Outcome == CombatResolutionResult.PriorityWin
	and result.Winner == highEvent and result.Loser == lowEvent
	and #resolver:GetResolutionEventsForResult(CombatResolutionResult.PriorityLoss) == 1
	and #survivors == 1 and survivors[1] == highEvent,
	"Higher Priority should win; the loser is withheld while the winner can continue")

local _, _, _, ordinaryA, ordinaryB = fakePair(0, 0, true, false)
survivors = resolver:Process({ ordinaryA, ordinaryB })
assert(#resolver:GetResolutionEvents() == 2 and #survivors == 2,
	"A non-clashable attack should leave both hits as ordinary interactions")
assert(resolver:GetResolutionEventsForResult(CombatResolutionResult.Normal)
	and #resolver:GetResolutionEventsForResult(CombatResolutionResult.Normal) == 2,
	"Unpaired hits should have explicit Normal resolution results")

local selfWorld = World.new()
local selfEntity = selfWorld:CreateEntity()
local selfInstanceA = AttackInstance.new(Attack.new({}), selfEntity)
local selfInstanceB = AttackInstance.new(Attack.new({}), selfEntity)
local selfHitA = fakeHit(selfInstanceA, selfEntity.Id, 99, selfEntity, {}, 1)
local selfHitB = fakeHit(selfInstanceB, selfEntity.Id, 99, selfEntity, {}, 1)
assert(#resolver:Process({ selfHitA, selfHitB }) == 2
	and #resolver:GetResolutionEventsForResult(CombatResolutionResult.Clash) == 0,
	"Attacks from one entity should not Clash with each other")

-- Three simultaneous pairwise interactions are emitted in canonical pair order.
local multiWorld = World.new()
local a, b, c = multiWorld:CreateEntity(), multiWorld:CreateEntity(), multiWorld:CreateEntity()
local ia = AttackInstance.new(Attack.new({ Priority = 3 }), a)
local ib = AttackInstance.new(Attack.new({ Priority = 3 }), b)
local ic = AttackInstance.new(Attack.new({ Priority = 3 }), c)
ia.Id, ib.Id, ic.Id = 11, 22, 33
local ab1, ba1 = fakeHit(ia, a.Id, b.Id, a, b), fakeHit(ib, b.Id, a.Id, b, a)
local ac1, ca1 = fakeHit(ia, a.Id, c.Id, a, c), fakeHit(ic, c.Id, a.Id, c, a)
local bc1, cb1 = fakeHit(ib, b.Id, c.Id, b, c), fakeHit(ic, c.Id, b.Id, c, b)
resolver:Process({ cb1, ac1, ba1, bc1, ca1, ab1 })
local multiResults = resolver:GetResolutionEvents()
assert(#multiResults == 3 and multiResults[1].AttackInstanceIdA == 11
	and multiResults[1].AttackInstanceIdB == 22
	and multiResults[2].AttackInstanceIdA == 11
	and multiResults[2].AttackInstanceIdB == 33
	and multiResults[3].AttackInstanceIdA == 22
	and multiResults[3].AttackInstanceIdB == 33,
	"Multi-clashes should resolve once per pair in stable AttackInstance ID order")

local function makeReciprocalWorld(priorityA, priorityB, canClashA, canClashB)
	local world = World.new()
	local collision = CollisionWorld.new(world)
	local entityA, entityB = world:CreateEntity(), world:CreateEntity()
	local healthA = entityA:AddComponent(HealthComponent.new({ MaxHealth = 100 }))
	local healthB = entityB:AddComponent(HealthComponent.new({ MaxHealth = 100 }))
	entityA:AddComponent(Hurtbox.new({ Shape = "Sphere", Radius = 1 }))
	entityB:AddComponent(Hurtbox.new({ Shape = "Sphere", Radius = 1 }))
	local attackA = AttackInstance.new(Attack.new({
		Damage = 10,
		Hitstun = 5,
		Priority = priorityA,
		CanClash = canClashA,
	}), entityA):Activate()
	local attackB = AttackInstance.new(Attack.new({
		Damage = 10,
		Hitstun = 5,
		Priority = priorityB,
		CanClash = canClashB,
	}), entityB):Activate()
	local hitboxA = attackA:AddHitbox(Hitbox.new({ Shape = "Sphere", Radius = 1 }))
	local hitboxB = attackB:AddHitbox(Hitbox.new({ Shape = "Sphere", Radius = 1 }))
	entityA:AddComponent(hitboxA)
	entityB:AddComponent(hitboxB)
	world:Step(1 / 60, 1, 1 / 60)
	return world, collision, healthA, healthB
end

local equalWorld, equalCollision, equalHealthA, equalHealthB = makeReciprocalWorld(5, 5, true, true)
assert(#equalCollision:GetHitEvents() == 2
	and #equalWorld:GetCombatResolutionEvents() == 1
	and equalWorld:GetCombatResolutionEvents()[1].Outcome == CombatResolutionResult.Clash
	and #equalWorld:GetDefenseEvents() == 0 and #equalWorld:GetDamageRequests() == 0
	and equalHealthA:GetHealth() == 100 and equalHealthB:GetHealth() == 100,
	"An integrated Clash should be recorded once and prevent both hits reaching Defense/Damage")

local priorityWorld, _, priorityHealthA, priorityHealthB = makeReciprocalWorld(9, 1, true, true)
assert(#priorityWorld:GetCombatResolutionEvents() == 1
	and priorityWorld:GetCombatResolutionEvents()[1].Outcome == CombatResolutionResult.PriorityWin
	and #priorityWorld:GetDamageRequests() == 1
	and priorityHealthA:GetHealth() == 100 and priorityHealthB:GetHealth() == 90,
	"The priority winner's hit should continue through Defense/Damage; the loser must not")

local noClashWorld, _, noClashHealthA, noClashHealthB = makeReciprocalWorld(5, 5, true, false)
local noClashResults = noClashWorld:GetCombatResolutionEvents()
assert(#noClashResults == 2
	and #noClashWorld:GetCombatResolver():GetResolutionEventsForResult(CombatResolutionResult.Clash) == 0
	and #noClashWorld:GetDamageRequests() == 2
	and noClashHealthA:GetHealth() == 90 and noClashHealthB:GetHealth() == 90,
	"A non-clashable attack should leave reciprocal hits on the normal damage path")

-- If either side disables Clash, both reciprocal contacts remain Normal.
local _, _, _, noClashA, noClashB = fakePair(8, 2, false, true)
local noClashSurvivors = resolver:Process({ noClashB, noClashA })
assert(#noClashSurvivors == 2
	and #resolver:GetResolutionEventsForResult(CombatResolutionResult.Normal) == 2
	and #resolver:GetResolutionEventsForResult(CombatResolutionResult.Clash) == 0,
	"A reciprocal pair with either CanClash false should remain Normal regardless of Priority")
local _, _, _, deadEventA, deadEventB = fakePair(4, 4)
deadEventA.Attacker:SetState(require(Core.EntityState).Dead)
assert(#resolver:Process({ deadEventA, deadEventB }) == 0
	and #resolver:GetResolutionEvents() == 0,
	"Dead entities must not create new Combat Resolution outcomes")
local _, finishedInstance, finishedInstanceB, finishedEvent, reciprocalEvent = fakePair(4, 4)
finishedInstance:Finish()
finishedInstanceB:Finish()
assert(#resolver:Process({ finishedEvent, reciprocalEvent }) == 0
	and #resolver:GetResolutionEvents() == 0,
	"Finished AttackInstances must not participate in Combat Resolution")

print("Combat resolution tests passed")
