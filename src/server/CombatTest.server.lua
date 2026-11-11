local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local Combat = Shared:WaitForChild("Combat")
local SimulationModules = Shared:WaitForChild("Simulation")

local Component = require(Core.Component)
local EntityState = require(Core.EntityState)
local World = require(Core.World)
local Simulation = require(SimulationModules.Simulation)
local Hitbox = require(Combat.Hitbox)
local Hurtbox = require(Combat.Hurtbox)
local CollisionQuery = require(Combat.CollisionQuery)
local CollisionWorld = require(Combat.CollisionWorld)
local HitResolver = require(Combat.HitResolver)
local Damage = require(Combat.Damage)
local Attack = require(Combat.Attack)
local AttackInstance = require(Combat.AttackInstance)
local HitPolicy = require(Combat.HitPolicy)
local HitProcessor = require(Combat.HitProcessor)
local HealthComponent = require(Combat.HealthComponent)
local DamageRequest = require(Combat.DamageRequest)

local function position(x, y, z)
	return Vector3.new(x, y, z)
end

local function boxRegion(regionType, at, size, rotation)
	local constructor = regionType == "Hitbox" and Hitbox or Hurtbox
	return constructor.new({ Shape = "Box", Position = at, Size = size, Rotation = rotation })
end

local function sphereRegion(regionType, at, radius)
	local constructor = regionType == "Hitbox" and Hitbox or Hurtbox
	return constructor.new({ Shape = "Sphere", Position = at, Radius = radius })
end

local function containsReference(items, expected)
	for _, item in ipairs(items) do
		if item == expected then
			return true
		end
	end
	return false
end

-- Pure shape queries: overlap, separation, and inclusive tangency.
local origin = position(0, 0, 0)
local box = boxRegion("Hitbox", origin, position(2, 2, 2))
local overlappingBox = boxRegion("Hurtbox", position(1.5, 0, 0), position(2, 2, 2))
local touchingBox = boxRegion("Hurtbox", position(2, 0, 0), position(2, 2, 2))
local separatedBox = boxRegion("Hurtbox", position(2.01, 0, 0), position(2, 2, 2))
assert(CollisionQuery.BoxBox(box, overlappingBox), "BoxBox should detect overlap")
assert(CollisionQuery.BoxBox(box, touchingBox), "BoxBox should count touching faces as collision")
assert(not CollisionQuery.BoxBox(box, separatedBox), "BoxBox should reject separated boxes")
assert(CollisionQuery.Intersects(overlappingBox, box), "BoxBox detection should be symmetric")

local sphere = sphereRegion("Hitbox", origin, 1)
local overlappingSphere = sphereRegion("Hurtbox", position(1.5, 0, 0), 1)
local tangentSphere = sphereRegion("Hurtbox", position(2, 0, 0), 1)
local separatedSphere = sphereRegion("Hurtbox", position(2.01, 0, 0), 1)
assert(CollisionQuery.SphereSphere(sphere, overlappingSphere), "SphereSphere should detect overlap")
assert(CollisionQuery.SphereSphere(sphere, tangentSphere), "SphereSphere should include tangency")
assert(not CollisionQuery.SphereSphere(sphere, separatedSphere), "SphereSphere should reject separation")

local overlappingBoxSphere = sphereRegion("Hurtbox", position(1.4, 0, 0), 0.5)
local tangentBoxSphere = sphereRegion("Hurtbox", position(1.5, 0, 0), 0.5)
local separatedBoxSphere = sphereRegion("Hurtbox", position(1.51, 0, 0), 0.5)
assert(CollisionQuery.BoxSphere(box, overlappingBoxSphere), "BoxSphere should detect overlap")
assert(CollisionQuery.BoxSphere(box, tangentBoxSphere), "BoxSphere should include tangency")
assert(not CollisionQuery.BoxSphere(box, separatedBoxSphere), "BoxSphere should reject separation")
assert(CollisionQuery.SphereBox(overlappingBoxSphere, box), "SphereBox should detect the reverse query")
assert(CollisionQuery.Intersects(box, overlappingBoxSphere)
	== CollisionQuery.Intersects(overlappingBoxSphere, box), "BoxSphere results should be symmetric")

local rotatedBox = boxRegion("Hitbox", origin, position(4, 1, 1), CFrame.Angles(0, math.pi / 4, 0))
local rotatedOverlap = sphereRegion("Hurtbox", position(0, 0, -1), 0.5)
assert(CollisionQuery.Intersects(rotatedBox, rotatedOverlap), "Box queries should honor rotation")

-- CollisionWorld owns registration, contact state, and resolution; attached regions register automatically.
local world = World.new()
local collisionWorld = CollisionWorld.new(world)
assert(world:GetCollisionWorld() == collisionWorld, "World should expose its CollisionWorld")

local standaloneHitbox = Hitbox.new({ Shape = "Sphere", Radius = 1 })
local standaloneHurtbox = Hurtbox.new({ Shape = "Sphere", Radius = 1 })
collisionWorld:RegisterHitbox(standaloneHitbox)
collisionWorld:RegisterHurtbox(standaloneHurtbox)
assert(#collisionWorld:GetHitboxes() == 1 and #collisionWorld:GetHurtboxes() == 1,
	"CollisionWorld should register hitboxes and hurtboxes")
assert(collisionWorld:RemoveHitbox(standaloneHitbox), "CollisionWorld should remove hitboxes")
assert(collisionWorld:RemoveHurtbox(standaloneHurtbox.Id), "CollisionWorld should remove hurtboxes by ID")
assert(#collisionWorld:GetHitboxes() == 0 and #collisionWorld:GetHurtboxes() == 0,
	"Removed regions should no longer be registered")

local emptyEntity = world:CreateEntity()
world:Step(1 / 60)
assert(#collisionWorld:GetResults() == 0, "Entities without regions should not collide")

local damage = Damage.new({ Amount = 12, Type = "Normal" })
local attacker = world:CreateEntity()
local target = world:CreateEntity()
local hitbox = Hitbox.new({
	Shape = "Box",
	Position = origin,
	Size = position(2, 2, 2),
	AttackId = "jab-01",
	Priority = 3,
	ClashGroup = "strike",
	Damage = damage,
})
local hurtbox = boxRegion("Hurtbox", position(5, 0, 0), position(2, 2, 2))
attacker:AddComponent(hitbox)
target:AddComponent(hurtbox)
assert(hitbox.Owner == attacker and hurtbox.Owner == target, "Attached regions should inherit their entity owner")
assert(#collisionWorld:GetHitboxes() == 1 and #collisionWorld:GetHurtboxes() == 1,
	"Regions attached after CollisionWorld setup should auto-register")
assert(not CollisionQuery.Intersects(hitbox, hurtbox), "Integration regions should initially be separated")

world:Step(1 / 60)
assert(#collisionWorld:GetResults() == 0, "Separated entities should produce no collision")
hitbox.Position = position(3, 0, 0)
world:Step(1 / 60)
local firstResults = collisionWorld:GetResults()
assert(#firstResults == 1, "World:Step() should detect overlapping combat regions")
assert(firstResults[1].Attacker == attacker and firstResults[1].Target == target,
	"Collision results should identify attacker and target")
assert(firstResults[1].Hitbox == hitbox and firstResults[1].Hurtbox == hurtbox,
	"Collision results should identify both regions")
assert(firstResults[1].ContactType == "FirstContact" and firstResults[1].IsFirstContact,
	"First overlap should be marked as first contact")

local hitEvents = collisionWorld:GetHitEvents()
assert(#hitEvents == 1, "HitResolver should turn collisions into hit events")
assert(hitEvents[1].Attacker == attacker and hitEvents[1].Target == target,
	"HitEvent should preserve attacker and target")
assert(hitEvents[1].Hitbox == hitbox and hitEvents[1].Hurtbox == hurtbox,
	"HitEvent should preserve its source regions")
assert(hitEvents[1].AttackId == "jab-01" and hitEvents[1].Priority == 3
	and hitEvents[1].ClashGroup == "strike" and hitEvents[1].Damage == damage,
	"HitEvent should preserve attack data and Damage request")
assert(target.Health == nil, "HitResolver must not apply damage automatically")

world:Step(1 / 60)
local continuousResult = collisionWorld:GetResults()[1]
assert(continuousResult and continuousResult.ContactType == "Continuous" and continuousResult.IsContinuous,
	"Persistent overlap should be marked as continuous contact")

hitbox:SetEnabled(false)
world:Step(1 / 60)
assert(#collisionWorld:GetResults() == 0, "Disabled hitboxes should not collide")
hitbox:SetEnabled(true)
hurtbox:SetEnabled(false)
world:Step(1 / 60)
assert(#collisionWorld:GetResults() == 0, "Disabled hurtboxes should not collide")
hurtbox:SetEnabled(true)

local selfEntity = world:CreateEntity()
selfEntity:AddComponent(boxRegion("Hitbox", origin, position(2, 2, 2)))
selfEntity:AddComponent(boxRegion("Hurtbox", origin, position(2, 2, 2)))
world:Step(1 / 60)
for _, result in ipairs(collisionWorld:GetResults()) do
	assert(result.Attacker ~= result.Target, "An entity should not hit itself")
end

target:SetState(EntityState.Dead)
world:Step(1 / 60)
for _, result in ipairs(collisionWorld:GetResults()) do
	assert(result.Target ~= target, "Dead entities should not be hit")
end
target:SetState(EntityState.Alive)
attacker:SetState(EntityState.Dead)
world:Step(1 / 60)
for _, result in ipairs(collisionWorld:GetResults()) do
	assert(result.Attacker ~= attacker, "Dead entities should not generate hits")
end
attacker:SetState(EntityState.Alive)

assert(world:DestroyEntity(attacker), "World should destroy entities with hitboxes")
assert(not containsReference(collisionWorld:GetHitboxes(), hitbox),
	"Destroying an entity should unregister its hitbox")
assert(hitbox.Entity == nil and hitbox.Owner == nil, "Destroyed hitboxes should release entity references")
assert(world:DestroyEntity(target), "World should destroy entities with hurtboxes")
assert(not containsReference(collisionWorld:GetHurtboxes(), hurtbox),
	"Destroying an entity should unregister its hurtbox")
assert(hurtbox.Entity == nil and hurtbox.Owner == nil, "Destroyed hurtboxes should release entity references")

local directResolver = HitResolver.new()
local resolved = directResolver:Resolve({ {
	Hitbox = hitbox,
	Hurtbox = hurtbox,
	Attacker = attacker,
	Target = target,
	ContactType = "FirstContact",
	IsFirstContact = true,
	IsContinuous = false,
} })
assert(#resolved == 1 and resolved[1].Damage == damage, "HitResolver should preserve collision and damage data")
assert(target.Health == nil, "Resolving a HitEvent should not mutate target health")

-- Full Simulation -> World -> CollisionWorld flow: component motion is applied before collision detection.
local Mover = {}
Mover.__index = Mover
setmetatable(Mover, { __index = Component })
function Mover.new(region, destination)
	local self = Component.new()
	self.Region = region
	self.Destination = destination
	return setmetatable(self, Mover)
end
function Mover:Step()
	self.Region.Position = self.Destination
end

local simulationWorld = World.new()
local simulationCollisionWorld = CollisionWorld.new(simulationWorld)
local movingAttacker = simulationWorld:CreateEntity()
local movingTarget = simulationWorld:CreateEntity()
local movingHitbox = boxRegion("Hitbox", origin, position(2, 2, 2))
local movingHurtbox = boxRegion("Hurtbox", position(4, 0, 0), position(2, 2, 2))
movingAttacker:AddComponent(movingHitbox)
movingAttacker:AddComponent(Mover.new(movingHitbox, position(4, 0, 0)))
movingTarget:AddComponent(movingHurtbox)
assert(not CollisionQuery.Intersects(movingHitbox, movingHurtbox), "Simulation regions should start apart")

local simulation = Simulation.new(simulationWorld, { FixedDeltaTime = 1 / 60 })
simulation:Step()
assert(simulationCollisionWorld.LastStepDeltaTime == 1 / 60,
	"CollisionWorld should receive the Simulation fixed delta")
local integratedEvents = simulationCollisionWorld:GetHitEvents()
assert(#integratedEvents == 1 and integratedEvents[1].Attacker == movingAttacker
	and integratedEvents[1].Target == movingTarget,
	"Simulation should detect a hit after component movement in the same fixed step")

-- Equivalent independent worlds and identical fixed steps produce the same logical collision trace.
local function createReplay()
	local replay = { Trace = {}, HitEventTrace = {} }
	replay.World = World.new()
	replay.CollisionWorld = CollisionWorld.new(replay.World)
	replay.Attacker = replay.World:CreateEntity()
	replay.Target = replay.World:CreateEntity()
	replay.Hitbox = Hitbox.new({
		Shape = "Sphere", Position = origin, Radius = 0.75, AttackId = "replay-attack",
		Damage = Damage.new({ Amount = 5, Type = "Test" }),
	})
	replay.Attack = Attack.new({ Id = "replay-attack", HitPolicy = HitPolicy.Multi })
	replay.AttackInstance = AttackInstance.new(replay.Attack, replay.Attacker):Activate()
	replay.AttackInstance:AddHitbox(replay.Hitbox)
	replay.Hurtbox = Hurtbox.new({ Shape = "Sphere", Position = position(3, 0, 0), Radius = 0.75 })
	replay.Attacker:AddComponent(replay.Hitbox)
	replay.Attacker:AddComponent(Mover.new(replay.Hitbox, position(2, 0, 0)))
	replay.Target:AddComponent(replay.Hurtbox)
	replay.Simulation = Simulation.new(replay.World, { FixedDeltaTime = 0.1, Seed = 456 })
	return replay
end

local replayA = createReplay()
local replayB = createReplay()
assert(replayA.AttackInstance.Id == replayB.AttackInstance.Id
	and replayA.Hitbox.Id == replayB.Hitbox.Id and replayA.Hurtbox.Id == replayB.Hurtbox.Id,
	"Equivalent worlds should generate the same semantic IDs in the same construction sequence")
for _ = 1, 3 do
	replayA.Simulation:Step()
	replayB.Simulation:Step()
	local resultsA = replayA.CollisionWorld:GetResults()
	local resultsB = replayB.CollisionWorld:GetResults()
	assert(#resultsA == #resultsB, "Equivalent simulations should produce equal collision counts")
	for index, resultA in ipairs(resultsA) do
		local resultB = resultsB[index]
		assert(resultA.Attacker.Id == resultB.Attacker.Id and resultA.Target.Id == resultB.Target.Id
			and resultA.ContactType == resultB.ContactType,
			"Equivalent simulations should produce equivalent collision results")
		table.insert(replayA.Trace, resultA.Attacker.Id .. ":" .. resultA.Target.Id .. ":" .. resultA.ContactType)
		table.insert(replayB.Trace, resultB.Attacker.Id .. ":" .. resultB.Target.Id .. ":" .. resultB.ContactType)
	end
	for _, event in ipairs(replayA.CollisionWorld:GetHitEvents()) do
		table.insert(replayA.HitEventTrace, string.format("%d:%d:%d:%d:%d", event.AttackInstanceId,
			event.AttackerEntityId, event.TargetEntityId, event.HitboxId, event.Frame))
	end
	for _, event in ipairs(replayB.CollisionWorld:GetHitEvents()) do
		table.insert(replayB.HitEventTrace, string.format("%d:%d:%d:%d:%d", event.AttackInstanceId,
			event.AttackerEntityId, event.TargetEntityId, event.HitboxId, event.Frame))
	end
end
assert(#replayA.Trace == #replayB.Trace, "Equivalent collision traces should have the same length")
for index, entry in ipairs(replayA.Trace) do
	assert(entry == replayB.Trace[index], "Equivalent simulations should reproduce the same collision trace")
end
assert(#replayA.HitEventTrace == #replayB.HitEventTrace,
	"Equivalent simulations should produce the same semantic hit count")
for index, entry in ipairs(replayA.HitEventTrace) do
	assert(entry == replayB.HitEventTrace[index],
		"Equivalent simulations should reproduce semantic hit IDs and frames")
end

print("Combat collision tests passed")

-- Hit processing turns contacts into policy-filtered, frame-stamped semantic events.
local processingWorld = World.new()
local processingCollisionWorld = CollisionWorld.new(processingWorld)
local processingSimulation = Simulation.new(processingWorld, { FixedDeltaTime = 0.1 })
local processingAttacker = processingWorld:CreateEntity()
local processingTarget = processingWorld:CreateEntity()
local lightAttack = Attack.new({
	Id = "LightPunch",
	HitPolicy = HitPolicy.Once,
	Priority = 2,
	Damage = damage,
})
local firstInstance = AttackInstance.new(lightAttack, processingAttacker)
assert(firstInstance.State == "Created", "A new AttackInstance should begin in Created state")
firstInstance:Activate()
local secondInstance = AttackInstance.new(lightAttack, processingAttacker):Activate()
assert(firstInstance.Id ~= secondInstance.Id, "Attack executions should have distinct IDs")
assert(firstInstance.Attack == lightAttack and firstInstance.OwnerEntity == processingAttacker
	and firstInstance.State == "Active", "AttackInstance should retain definition, owner, and lifecycle")

local onceHitbox = Hitbox.new({ Shape = "Sphere", Radius = 1 })
local onceHurtbox = Hurtbox.new({ Shape = "Sphere", Radius = 1 })
firstInstance:AddHitbox(onceHitbox)
processingAttacker:AddComponent(onceHitbox)
processingTarget:AddComponent(onceHurtbox)
processingSimulation:Step()
local onceEvents = processingCollisionWorld:GetHitEvents()
assert(#onceEvents == 1, "An active AttackInstance should produce one semantic HitEvent")
local onceEvent = onceEvents[1]
assert(onceEvent.AttackInstance == firstInstance and onceEvent.Attack == lightAttack
	and onceEvent.AttackInstanceId == firstInstance.Id and onceEvent.AttackId == "LightPunch",
	"HitEvent should distinguish Attack and AttackInstance identities")
assert(onceEvent.Attacker == processingAttacker and onceEvent.Target == processingTarget
	and onceEvent.Hitbox == onceHitbox and onceEvent.Hurtbox == onceHurtbox,
	"HitEvent should preserve entity and region references")
assert(onceEvent.Frame == 1 and onceEvent.Time == 0.1 and onceEvent.Priority == 2
	and onceEvent.Damage == damage, "HitEvent should carry fixed-step timing and attack data")
assert(onceEvent.AttackerEntityId == processingAttacker.Id and onceEvent.TargetEntityId == processingTarget.Id
	and onceEvent.HitboxId == onceHitbox.Id and onceEvent.HurtboxId == onceHurtbox.Id,
	"HitEvent should keep entity and region IDs distinct")
assert(processingCollisionWorld.HitProcessor.HitHistory.Entries[firstInstance] ~= nil,
	"HitOnce should record the AttackInstance-to-target history")
processingSimulation:Step()
assert(#processingCollisionWorld:GetHitEvents() == 0,
	"HitOnce should suppress repeated contacts on later frames")
assert(processingTarget.Health == nil, "Hit processing must not apply damage")

-- Multi allows one event per target per frame, including when multiple hitboxes overlap.
local multiWorld = World.new()
local multiCollisionWorld = CollisionWorld.new(multiWorld)
local multiSimulation = Simulation.new(multiWorld, { FixedDeltaTime = 0.05 })
local multiAttacker = multiWorld:CreateEntity()
local multiTarget = multiWorld:CreateEntity()
local multiCarrier = multiWorld:CreateEntity()
local multiAttack = Attack.new({ Id = "Spin", HitPolicy = HitPolicy.Multi })
local multiInstance = AttackInstance.new(multiAttack, multiAttacker):Activate()
local multiHitboxA = Hitbox.new({ Shape = "Sphere", Radius = 1 })
local multiHitboxB = Hitbox.new({ Shape = "Sphere", Radius = 1 })
local multiHurtbox = Hurtbox.new({ Shape = "Sphere", Radius = 1 })
multiInstance:AddHitbox(multiHitboxA)
multiInstance:AddHitbox(multiHitboxB)
multiAttacker:AddComponent(multiHitboxA)
multiCarrier:AddComponent(multiHitboxB)
multiTarget:AddComponent(multiHurtbox)
multiSimulation:Step()
assert(#multiCollisionWorld:GetResults() == 2, "Both hitboxes should remain independent collision regions")
assert(#multiCollisionWorld:GetHitEvents() == 1,
	"Multi policy should deduplicate one AttackInstance-target pair within a frame")
multiSimulation:Step()
assert(#multiCollisionWorld:GetHitEvents() == 1
	and multiCollisionWorld:GetHitEvents()[1].Frame == 2,
	"Multi policy should allow another event on a later frame")

-- Separate AttackInstances may each hit the same target; higher priority is processed first.
local priorityWorld = World.new()
local priorityCollisionWorld = CollisionWorld.new(priorityWorld)
local prioritySimulation = Simulation.new(priorityWorld, { FixedDeltaTime = 0.1 })
local priorityAttacker = priorityWorld:CreateEntity()
local priorityCarrier = priorityWorld:CreateEntity()
local priorityTarget = priorityWorld:CreateEntity()
local lowAttack = Attack.new({ Id = "Low", Priority = 1 })
local highAttack = Attack.new({ Id = "High", Priority = 9 })
local lowInstance = AttackInstance.new(lowAttack, priorityAttacker):Activate()
local highInstance = AttackInstance.new(highAttack, priorityAttacker):Activate()
local lowHitbox = Hitbox.new({ Shape = "Sphere", Radius = 1 })
local highHitbox = Hitbox.new({ Shape = "Sphere", Radius = 1 })
lowInstance:AddHitbox(lowHitbox)
highInstance:AddHitbox(highHitbox)
priorityAttacker:AddComponent(lowHitbox)
priorityCarrier:AddComponent(highHitbox)
priorityTarget:AddComponent(Hurtbox.new({ Shape = "Sphere", Radius = 1 }))
prioritySimulation:Step()
local priorityEvents = priorityCollisionWorld:GetHitEvents()
assert(#priorityEvents == 2 and priorityEvents[1].Attack == highAttack
	and priorityEvents[2].Attack == lowAttack,
	"Events in one frame should sort by descending priority")

-- Filters, self-hit, dead entities, and disabled regions are checked before creating events.
local filterWorld = World.new()
local filterCollisionWorld = CollisionWorld.new(filterWorld)
local filterSimulation = Simulation.new(filterWorld, { FixedDeltaTime = 0.1 })
local filterAttacker = filterWorld:CreateEntity()
local allowedTarget = filterWorld:CreateEntity()
local deniedTarget = filterWorld:CreateEntity()
allowedTarget.Faction = "Blue"
deniedTarget.Faction = "Red"
local filteredAttack = Attack.new({
	Id = "FactionStrike",
	CanHit = function(_, target)
		return target.Faction == "Blue"
	end,
})
local filteredInstance = AttackInstance.new(filteredAttack, filterAttacker):Activate()
local filteredHitbox = Hitbox.new({ Shape = "Sphere", Radius = 4 })
filteredInstance:AddHitbox(filteredHitbox)
filterAttacker:AddComponent(filteredHitbox)
allowedTarget:AddComponent(Hurtbox.new({ Shape = "Sphere", Radius = 1 }))
deniedTarget:AddComponent(Hurtbox.new({ Shape = "Sphere", Radius = 1 }))
filterSimulation:Step()
local filteredEvents = filterCollisionWorld:GetHitEvents()
assert(#filteredEvents == 1 and filteredEvents[1].Target == allowedTarget,
	"Attack filters should reject targets that do not satisfy the custom rule")
local twoTargetInstance = AttackInstance.new(Attack.new({ Id = "WideStrike" }), filterAttacker):Activate()
local twoTargetCarrier = filterWorld:CreateEntity()
local twoTargetHitbox = Hitbox.new({ Shape = "Sphere", Radius = 4 })
twoTargetInstance:AddHitbox(twoTargetHitbox)
twoTargetCarrier:AddComponent(twoTargetHitbox)
filterSimulation:Step()
local distinctTargets = {}
for _, event in ipairs(filterCollisionWorld:GetHitEvents()) do
	if event.AttackInstance == twoTargetInstance then
		distinctTargets[event.Target] = true
	end
end
local distinctTargetCount = 0
for _ in pairs(distinctTargets) do
	distinctTargetCount += 1
end
assert(distinctTargetCount == 2, "One AttackInstance should be able to hit multiple targets")

local hitboxScopeWorld = World.new()
local hitboxScopeCollisionWorld = CollisionWorld.new(hitboxScopeWorld)
local hitboxScopeSimulation = Simulation.new(hitboxScopeWorld, { FixedDeltaTime = 0.1 })
local hitboxScopeAttacker = hitboxScopeWorld:CreateEntity()
local hitboxScopeCarrier = hitboxScopeWorld:CreateEntity()
local hitboxScopeTarget = hitboxScopeWorld:CreateEntity()
local hitboxScopeInstance = AttackInstance.new(Attack.new({
	Id = "PerRegion",
	HitPolicy = HitPolicy.Once,
	HitScope = HitPolicy.Scope.Hitbox,
}), hitboxScopeAttacker):Activate()
local scopedHitboxA = Hitbox.new({ Shape = "Sphere", Radius = 1 })
local scopedHitboxB = Hitbox.new({ Shape = "Sphere", Radius = 1 })
hitboxScopeInstance:AddHitbox(scopedHitboxA)
hitboxScopeInstance:AddHitbox(scopedHitboxB)
hitboxScopeAttacker:AddComponent(scopedHitboxA)
hitboxScopeCarrier:AddComponent(scopedHitboxB)
hitboxScopeTarget:AddComponent(Hurtbox.new({ Shape = "Sphere", Radius = 1 }))
hitboxScopeSimulation:Step()
local scopedEvents = hitboxScopeCollisionWorld:GetHitEvents()
assert(#scopedEvents == 2, "HitScope.Hitbox should keep independent target history per region")

local eligibilityWorld = World.new()
local eligibilityCollisionWorld = CollisionWorld.new(eligibilityWorld)
local eligibilitySimulation = Simulation.new(eligibilityWorld, { FixedDeltaTime = 0.1 })
local eligibilityAttacker = eligibilityWorld:CreateEntity()
local eligibilityTarget = eligibilityWorld:CreateEntity()
local eligibilityInstance = AttackInstance.new(Attack.new({ Id = "Eligibility" }), eligibilityAttacker):Activate()
local eligibilityHitbox = Hitbox.new({ Shape = "Sphere", Radius = 1 })
local eligibilityHurtbox = Hurtbox.new({ Shape = "Sphere", Radius = 1 })
eligibilityInstance:AddHitbox(eligibilityHitbox)
eligibilityAttacker:AddComponent(eligibilityHitbox)
eligibilityTarget:AddComponent(eligibilityHurtbox)
eligibilitySimulation:Step()
assert(#eligibilityCollisionWorld:GetHitEvents() == 1, "A living target should receive an eligible hit")
eligibilityTarget:SetState(EntityState.Dead)
eligibilitySimulation:Step()
assert(#eligibilityCollisionWorld:GetHitEvents() == 0, "Dead targets should not receive HitEvents")
eligibilityTarget:SetState(EntityState.Alive)
eligibilityAttacker:SetState(EntityState.Dead)
eligibilitySimulation:Step()
assert(#eligibilityCollisionWorld:GetHitEvents() == 0, "Dead attackers should not generate HitEvents")
eligibilityAttacker:SetState(EntityState.Alive)
eligibilityHitbox:SetEnabled(false)
eligibilitySimulation:Step()
assert(#eligibilityCollisionWorld:GetHitEvents() == 0, "Disabled hitboxes should not produce HitEvents")
eligibilityHitbox:SetEnabled(true)
eligibilityHurtbox:SetEnabled(false)
eligibilitySimulation:Step()
assert(#eligibilityCollisionWorld:GetHitEvents() == 0, "Disabled hurtboxes should not produce HitEvents")

local selfWorld = World.new()
local selfCollisionWorld = CollisionWorld.new(selfWorld)
local selfSimulation = Simulation.new(selfWorld, { FixedDeltaTime = 0.1 })
local selfEntity = selfWorld:CreateEntity()
local selfAttackInstance = AttackInstance.new(Attack.new({ Id = "SelfTest" }), selfEntity):Activate()
local selfHitbox = Hitbox.new({ Shape = "Sphere", Radius = 1 })
selfAttackInstance:AddHitbox(selfHitbox)
selfEntity:AddComponent(selfHitbox)
selfEntity:AddComponent(Hurtbox.new({ Shape = "Sphere", Radius = 1 }))
selfSimulation:Step()
assert(#selfCollisionWorld:GetHitEvents() == 0, "An entity should not produce self-hit events")

local hazardWorld = World.new()
local hazardCollisionWorld = CollisionWorld.new(hazardWorld)
local hazardSimulation = Simulation.new(hazardWorld, { FixedDeltaTime = 0.1 })
local hazardEntity = hazardWorld:CreateEntity()
local hazardTarget = hazardWorld:CreateEntity()
local hazardInstance = AttackInstance.new(
	Attack.new({ Id = "EnvironmentHazard" }), nil, hazardWorld.IdGenerator
)
hazardInstance:Activate()
local hazardHitbox = Hitbox.new({ Shape = "Sphere", Radius = 1 })
hazardInstance:AddHitbox(hazardHitbox)
hazardEntity:AddComponent(hazardHitbox)
hazardTarget:AddComponent(Hurtbox.new({ Shape = "Sphere", Radius = 1 }))
hazardSimulation:Step()
local hazardEvents = hazardCollisionWorld:GetHitEvents()
assert(#hazardEvents == 1 and hazardEvents[1].Attacker == nil
	and hazardEvents[1].Target == hazardTarget,
	"Ownerless environmental attacks should be able to hit without inventing an Attacker")

-- Finishing an attack and destroying a target both release their history.
assert(firstInstance:Finish(), "AttackInstance should transition to Finished")
assert(firstInstance.State == "Finished" and onceHitbox:IsEnabled() == false,
	"Finishing an attack should retire its associated hitboxes")
assert(processingCollisionWorld.HitProcessor.HitHistory.Entries[firstInstance] == nil,
	"Finishing an attack should clear its history immediately")

local historyWorld = World.new()
local historyCollisionWorld = CollisionWorld.new(historyWorld)
local historySimulation = Simulation.new(historyWorld, { FixedDeltaTime = 0.1 })
local historyAttacker = historyWorld:CreateEntity()
local historyTarget = historyWorld:CreateEntity()
local historyInstance = AttackInstance.new(Attack.new({ Id = "Cleanup" }), historyAttacker):Activate()
local historyHitbox = Hitbox.new({ Shape = "Sphere", Radius = 1 })
historyInstance:AddHitbox(historyHitbox)
historyAttacker:AddComponent(historyHitbox)
historyTarget:AddComponent(Hurtbox.new({ Shape = "Sphere", Radius = 1 }))
historySimulation:Step()
assert(historyCollisionWorld.HitProcessor.HitHistory.Entries[historyInstance] ~= nil,
	"A produced hit should create history before cleanup")
assert(historyWorld:DestroyEntity(historyTarget), "Target should be destroyable after receiving a hit")
assert(historyCollisionWorld.HitProcessor.HitHistory.Entries[historyInstance] == nil,
	"Destroying the target should clear its final history references")

-- Sorting uses only explicit IDs and priority, not the input table's iteration order.
local function buildOrderTrace(reverse)
	local processor = HitProcessor.new()
	local targetA = { Id = 20 }
	local targetB = { Id = 10 }
	local attack = Attack.new({ Id = "Ordering", Priority = 4 })
	local instanceA = { Id = 200, Attack = attack, OwnerEntity = { Id = 2 }, State = "Active" }
	local instanceB = { Id = 100, Attack = attack, OwnerEntity = { Id = 1 }, State = "Active" }
	local resultA = {
		Attacker = instanceA.OwnerEntity, Target = targetA,
		Hitbox = { Id = 2, AttackInstance = instanceA }, Hurtbox = { Id = 1 },
		ContactType = "FirstContact", IsFirstContact = true,
	}
	local resultB = {
		Attacker = instanceB.OwnerEntity, Target = targetB,
		Hitbox = { Id = 1, AttackInstance = instanceB }, Hurtbox = { Id = 2 },
		ContactType = "FirstContact", IsFirstContact = true,
	}
	local candidates = reverse and { resultB, resultA } or { resultA, resultB }
	local ordered = processor:Process(candidates, 7, 0.7)
	local trace = {}
	for _, event in ipairs(ordered) do
		table.insert(trace, string.format("%d:%d:%d:%d", event.AttackInstanceId,
			event.AttackerEntityId, event.TargetEntityId, event.HitboxId))
	end
	return trace
end

local orderTraceA = buildOrderTrace(false)
local orderTraceB = buildOrderTrace(true)
assert(#orderTraceA == #orderTraceB, "Reordering collision candidates should retain event count")
for index, traceEntry in ipairs(orderTraceA) do
	assert(traceEntry == orderTraceB[index], "HitEvent order must not depend on candidate table order")
end

print("Combat hit processing tests passed")

-- Health and damage are resolved from semantic HitEvents during World:Step.
local damageWorld = World.new()
local damageCollisionWorld = CollisionWorld.new(damageWorld)
local damageSimulation = Simulation.new(damageWorld, { FixedDeltaTime = 0.1 })
local damageAttacker = damageWorld:CreateEntity()
local damageTarget = damageWorld:CreateEntity()
local health = damageTarget:AddComponent(HealthComponent.new({ MaxHealth = 50 }))
local strike = Attack.new({
	Id = "HealthCheck",
	Damage = Damage.new({ Amount = 17, Type = "Physical" }),
})
local strikeInstance = AttackInstance.new(strike, damageAttacker):Activate()
local strikeHitbox = Hitbox.new({ Shape = "Sphere", Radius = 1 })
strikeInstance:AddHitbox(strikeHitbox)
damageAttacker:AddComponent(strikeHitbox)
damageTarget:AddComponent(Hurtbox.new({ Shape = "Sphere", Radius = 1 }))

assert(health:GetHealth() == 50 and health:GetMaxHealth() == 50
	and health:GetHealthRatio() == 1, "HealthComponent should initialize full health")
damageSimulation:Step()
assert(#damageCollisionWorld:GetHitEvents() == 1, "The integrated scenario should produce a HitEvent")
local damageEvents = damageWorld:GetDamageEvents()
local healthEvents = damageWorld:GetHealthChangedEvents()
assert(#damageEvents == 1 and health:GetHealth() == 33,
	"World should resolve attack damage through HealthComponent")
assert(damageEvents[1].Target == damageTarget and damageEvents[1].Source == damageAttacker
	and damageEvents[1].RequestedAmount == 17 and damageEvents[1].AppliedAmount == 17
	and damageEvents[1].Type == "Physical" and damageEvents[1].AttackInstance == strikeInstance,
	"DamageEvent should preserve amount, type, source, and attack context")
assert(#healthEvents == 1 and healthEvents[1].OldHealth == 50
	and healthEvents[1].NewHealth == 33 and healthEvents[1].Delta == -17
	and healthEvents[1].Frame == 1 and healthEvents[1].Time == 0.1,
	"HealthChangedEvent should expose the fixed-step health change")
assert(#damageWorld:GetDeathEvents() == 0 and damageTarget:IsAlive(),
	"Non-lethal damage should not create a DeathEvent")

local healEvent = health:Heal(100, { Frame = 2, Time = 0.2 })
assert(healEvent and healEvent.OldHealth == 33 and healEvent.NewHealth == 50
	and healEvent.Reason == "Heal", "Healing should clamp to MaxHealth and return a change event")
assert(health:Heal(1) == nil, "Healing at MaxHealth should not create a change event")
local maxHealthEvent = health:SetMaxHealth(40)
assert(maxHealthEvent and health:GetHealth() == 40 and health:GetMaxHealth() == 40,
	"Reducing MaxHealth should clamp current health")

-- Direct resolver requests are useful for non-hit sources and still use the same health rules.
local resolver = damageWorld:GetDamageResolver()
local finisher = Attack.new({ Id = "Finisher", Damage = Damage.new({ Amount = 100, Type = "Heavy" }) })
local finisherInstance = AttackInstance.new(finisher, damageAttacker):Activate()
local finisherHitbox = Hitbox.new({ Shape = "Sphere", Radius = 1 })
local finisherCarrier = damageWorld:CreateEntity()
finisherInstance:AddHitbox(finisherHitbox)
finisherCarrier:AddComponent(finisherHitbox)
damageSimulation:Step()
local lethalEvents = damageWorld:GetDamageEvents()
local lethalEvent = lethalEvents[1]
assert(#lethalEvents == 1 and lethalEvent and lethalEvent.RequestedAmount == 100
	and lethalEvent.AppliedAmount == 40 and health:GetHealth() == 0 and damageTarget:IsDead(),
	"A lethal HitEvent should resolve through World and clamp health at zero")
local deaths = resolver:GetDeathEvents()
assert(#deaths == 1 and deaths[1].Entity == damageTarget and deaths[1].Cause == lethalEvent
	and deaths[1].Frame == 2 and deaths[1].Time == 0.2,
	"Lethal damage should produce one contextual DeathEvent")
assert(health:Heal(5) == nil, "Dead entities should not be healed implicitly")

local overkillTarget = damageWorld:CreateEntity()
local overkillHealth = overkillTarget:AddComponent(HealthComponent.new({ MaxHealth = 10 }))
local directRequest = DamageRequest.new({ Amount = 100, Type = "Hazard", Target = overkillTarget })
local overkillEvent = resolver:Resolve(directRequest, 3, 0.3)
assert(overkillEvent and overkillEvent.RequestedAmount == 100 and overkillEvent.AppliedAmount == 10
	and overkillHealth:GetHealth() == 0 and overkillTarget:IsDead(),
	"Direct overkill damage should clamp health and transition the entity to Dead")
assert(resolver:Resolve(DamageRequest.new({ Amount = 2, Target = damageTarget }), 4, 0.4) == nil,
	"Dead entities should not receive more resolved damage")

local invalidDamageAccepted = pcall(function()
	DamageRequest.new({ Amount = -1, Target = damageTarget })
end)
assert(not invalidDamageAccepted, "Negative DamageRequest amounts should be rejected")
assert(damageWorld:DestroyEntity(damageTarget), "A damaged entity should remain destroyable")
assert(damageWorld:GetEntity(damageTarget.Id) == nil and damageTarget.Destroyed,
	"Destroying a damaged entity should unregister it and release its components")

-- A second attack proves that each fresh simulation step publishes only its frame events.
local noHealthTarget = damageWorld:CreateEntity()
local noHealthRequest = DamageRequest.new({ Amount = 3, Target = noHealthTarget })
local noHealthResult = resolver:Resolve(noHealthRequest, 5, 0.5)
assert(noHealthResult == nil, "Entities without HealthComponent should not receive implicit health")
assert(noHealthTarget:GetComponent(HealthComponent) == nil,
	"Damage resolution must not attach HealthComponent automatically")

print("Combat damage and health tests passed")
