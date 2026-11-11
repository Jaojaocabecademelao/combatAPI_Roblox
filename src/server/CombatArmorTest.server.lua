local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core, Combat = Shared:WaitForChild("Core"), Shared:WaitForChild("Combat")
local World = require(Core.World)
local EntityState = require(Core.EntityState)
local CollisionWorld = require(Combat.CollisionWorld)
local CombatResolver = require(Combat.CombatResolver)
local CombatResolutionResult = require(Combat.CombatResolutionResult)
local CounterResolver = require(Combat.CounterResolver)
local CounterResult = require(Combat.CounterResult)
local Attack = require(Combat.Attack)
local AttackInstance = require(Combat.AttackInstance)
local ArmorCategory = require(Combat.ArmorCategory)
local ArmorComponent = require(Combat.ArmorComponent)
local ArmorProfile = require(Combat.ArmorProfile)
local ArmorResolver = require(Combat.ArmorResolver)
local DefenseComponent = require(Combat.DefenseComponent)
local DefenseResult = require(Combat.DefenseResult)
local HealthComponent = require(Combat.HealthComponent)
local HitEvent = require(Combat.HitEvent)
local Hitbox = require(Combat.Hitbox)
local HitstopComponent = require(Combat.HitstopComponent)
local Hurtbox = require(Combat.Hurtbox)
local MotionComponent = require(Combat.MotionComponent)
local MotionRequest = require(Combat.MotionRequest)
local MotionType = require(Combat.MotionType)
local OffensiveStateComponent = require(Combat.OffensiveStateComponent)
local Protection = require(Combat.Protection)
local ProtectionComponent = require(Combat.ProtectionComponent)
local ProtectionResult = require(Combat.ProtectionResult)
local ProtectionType = require(Combat.ProtectionType)
local StatusContainer = require(Combat.StatusContainer)

local cases = 0
local function check(condition, message)
	assert(condition, message or ("Armor assertion " .. tostring(cases + 1) .. " failed"))
	cases += 1
end

local world = World.new()
local attacker, target = world:CreateEntity(), world:CreateEntity()
local armor = target:AddComponent(ArmorComponent.new())
local resolver = ArmorResolver.new(world)
local instance = { Id = 1001 }
local function makeHit(id, properties)
	return HitEvent.new({
		AttackInstance = instance,
		AttackInstanceId = id or instance.Id,
		Attacker = attacker,
		AttackerEntityId = attacker.Id,
		Target = target,
		TargetEntityId = target.Id,
		Frame = 1,
		Hitstun = 10,
		Damage = 20,
		OffensiveProperties = properties,
	})
end
local hit = makeHit()

-- Profile/component lifecycle, invalid configuration, component independence.
check(armor.Entity == target and armor:IsEnabled(), "ArmorComponent attaches as an optional component")
check(target:GetComponent(ArmorComponent) == armor, "Component is discoverable by type")
check(target:GetComponent(HealthComponent) == nil, "Armor works without Health")
check(target:GetInstance() == nil, "Armor works without a Model or Character")
local basic = ArmorProfile.new({ Name = "StaggerGuard", Consequences = { Hitstun = false } })
check(basic.Kind == "Armor" and basic:Allows("Damage"), "Armor defaults unspecified consequences to allowed")
check(not basic:Allows(ArmorCategory.Hitstun), "An explicit false blocks Hitstun")
check(armor:Grant(basic) ~= nil, "Permanent Armor can be granted without duration")
check(armor:Resolve(ArmorCategory.Hitstun, hit) ~= nil, "Granted Armor resolves its configured category")
check(armor:Resolve(ArmorCategory.Damage, hit) == nil, "Unconfigured categories remain allowed")
local permanentHandle = armor:GetHandles()[1]
check(permanentHandle.RemainingFrames == nil, "Missing duration means permanent Armor")
check(armor:Remove(permanentHandle), "Armor handle can be removed explicitly")
check(not permanentHandle.Active and #armor:GetHandles() == 0, "Removing a handle deactivates it")
check(not armor:Remove(permanentHandle), "Removing an Armor handle twice is safe")
local ok = pcall(function() ArmorProfile.new({ Consequences = { Damage = "no" } }) end)
check(not ok, "Consequence rules require explicit booleans")
ok = pcall(function() ArmorProfile.new({ DurationFrames = 0 }) end)
check(not ok, "Temporary Armor duration must be positive")
ok = pcall(function() ArmorProfile.new({ Priority = math.huge }) end)
check(not ok, "Armor priority must be finite")
ok = pcall(function() armor:Grant({}) end)
check(not ok, "Grant requires an ArmorProfile")
check(ArmorProfile.new({ DurationFrames = 4 }).DurationFrames == 4, "Profiles store fixed-step duration")

-- Supported categories and independent permission decisions.
local categoryRules = {
	Hitstun = false, Knockback = false, Launch = true, Push = false, Pull = true, Damage = true,
}
local categoryProfile = ArmorProfile.new({ Name = "Selective", Consequences = categoryRules })
armor:Grant(categoryProfile)
local categoryResult = resolver:Resolve(hit)
for _, category in ipairs({ "Hitstun", "Knockback", "Launch", "Push", "Pull", "Damage" }) do
	check(categoryResult:Allows(category) == categoryRules[category], "Independent rule for " .. category)
end
check(categoryResult:Blocks("Hitstun") and categoryResult:Blocks("Knockback"), "Blocked reactions are explicit")
check(categoryResult:Allows("Damage") and categoryResult:Allows("Launch"), "Allowed consequences remain explicit")
check(categoryResult:GetProfile("Hitstun") == categoryProfile, "Result identifies the selected profile")
check(categoryResult.SourceByCategory.Hitstun == nil, "Profile source is optional")
check(categoryResult.Type == "ArmorResult" and categoryResult.TargetId == target.Id, "ArmorResult identifies its entity")
check(categoryResult.AttackInstanceId == instance.Id, "ArmorResult identifies the execution")
check(categoryResult.HitEvent == hit, "ArmorResult retains the HitEvent")
check(categoryResult.Blocked.Damage ~= true and categoryResult.Allowed.Damage, "Allowed and blocked maps are separate")

-- SuperArmor is a preset over the same ArmorProfile/Resolver machinery.
local super = ArmorProfile.SuperArmor({ Name = "Super", DurationFrames = 5, Damage = true, Priority = 10 })
check(super.Kind == "SuperArmor", "SuperArmor has a semantic profile kind")
check(super:Allows("Damage"), "SuperArmor does not imply damage immunity")
for _, reaction in ipairs({ "Hitstun", "Knockback", "Launch", "Push", "Pull" }) do
	check(not super:Allows(reaction), "SuperArmor preset resists " .. reaction)
end
local overriddenSuper = ArmorProfile.SuperArmor({
	Name = "SuperLaunchable", Consequences = { Launch = true, Push = false },
})
check(overriddenSuper:Allows("Launch"), "SuperArmor can explicitly allow Launch")
check(not overriddenSuper:Allows("Push"), "SuperArmor can explicitly block Push")
check(overriddenSuper:Allows("Damage"), "SuperArmor leaves Damage allowed by default")
local superHandle = armor:Grant(super, 2, attacker)
check(superHandle.Source == attacker and superHandle.RemainingFrames == 2, "Grant can override duration and record origin")
check(resolver:Resolve(hit):GetProfile("Hitstun") == super, "SuperArmor resolves through shared Armor logic")

-- Priority and same-category reapplication are order-independent.
local priorityTarget = world:CreateEntity()
local priorityArmor = priorityTarget:AddComponent(ArmorComponent.new())
local low = ArmorProfile.new({ Id = "low", Consequences = { Hitstun = false }, Priority = 1 })
local high = ArmorProfile.new({ Id = "high", Consequences = { Hitstun = false }, Priority = 5 })
priorityArmor:Grant(low, 20)
priorityArmor:Grant(high, 3)
check(priorityArmor:Resolve("Hitstun", hit).Profile == high, "Higher Armor priority wins over longer lower-priority duration")
local samePriorityShort = ArmorProfile.new({ Id = "short", Consequences = { Push = false }, Priority = 2 })
local samePriorityLong = ArmorProfile.new({ Id = "long", Consequences = { Push = false }, Priority = 2 })
priorityArmor:Grant(samePriorityShort, 4)
priorityArmor:Grant(samePriorityLong, 8)
check(priorityArmor:Resolve("Push", hit).RemainingFrames == 8, "Equal-priority same-category rules use greatest remaining duration")
local reversedTarget = world:CreateEntity()
local reversedArmor = reversedTarget:AddComponent(ArmorComponent.new())
reversedArmor:Grant(samePriorityLong, 8)
reversedArmor:Grant(samePriorityShort, 4)
check(reversedArmor:Resolve("Push", hit).RemainingFrames == 8, "Reapplication result is independent of insertion order")
check(priorityArmor:Resolve("Knockback", hit) == nil, "Priority in one category does not affect another")
check(priorityArmor:Resolve("Hitstun", hit).Priority == 5, "Armor priority is independent of Attack priority")

-- Temporary Armor uses World steps; permanent Armor lasts until handle removal.
local timedWorld = World.new()
local timed = timedWorld:CreateEntity()
local timedArmor = timed:AddComponent(ArmorComponent.new())
local timedResolver = timedWorld:GetArmorResolver()
local timedProfile = ArmorProfile.new({ Name = "TwoSteps", DurationFrames = 2, Consequences = { Hitstun = false } })
local timedHandle = timedArmor:Grant(timedProfile)
check(timedHandle.RemainingFrames == 2, "Temporary Armor begins at its configured frame count")
check(timedArmor:Resolve("Hitstun", hit) == timedHandle, "Temporary Armor applies before the first step")
timedWorld:Step(1 / 60, 1, 1 / 60)
check(timedHandle.RemainingFrames == 1, "One World step consumes one Armor frame")
check(timedArmor:Resolve("Hitstun", hit) == timedHandle, "Armor remains during the first simulation frame")
timedWorld:Step(1 / 60, 2, 2 / 60)
check(not timedHandle.Active and #timedArmor:GetHandles() == 0, "Armor expires after two simulation steps")
check(timedArmor:Resolve("Hitstun", hit) == nil, "Expired Armor no longer modifies consequences")
local permanent = timedArmor:Grant(ArmorProfile.new({ Consequences = { Pull = false } }))
timedWorld:Step(1 / 60, 3, 3 / 60)
check(permanent.Active and permanent.RemainingFrames == nil, "Permanent Armor does not need a refresh loop")
check(timedArmor:Remove(permanent), "Permanent Armor ends by removing its handle")
check(timedArmor:Resolve("Pull", hit) == nil, "Removed permanent rule no longer resolves")

-- Disabled/detached/destroyed components cannot keep active Armor.
local lifecycleTarget = world:CreateEntity()
local lifecycleArmor = lifecycleTarget:AddComponent(ArmorComponent.new())
local lifecycleHandle = lifecycleArmor:Grant(ArmorProfile.new({ Consequences = { Damage = false } }))
check(lifecycleArmor:IsEnabled() and lifecycleArmor:Resolve("Damage", hit) ~= nil, "Enabled component provides Armor")
lifecycleArmor:SetEnabled(false)
check(not lifecycleArmor:IsEnabled() and lifecycleArmor:Resolve("Damage", hit) == nil, "Disabled component is ignored")
lifecycleArmor:SetEnabled(true)
check(lifecycleArmor:Resolve("Damage", hit) == lifecycleHandle, "Re-enable restores the still-active handle")
lifecycleTarget:RemoveComponent(ArmorComponent)
check(lifecycleArmor.Entity == nil and #lifecycleArmor:GetHandles() == 0, "Detach clears Armor state")
local destroyTarget = world:CreateEntity()
local destroyArmor = destroyTarget:AddComponent(ArmorComponent.new())
destroyArmor:Grant(basic)
world:DestroyEntity(destroyTarget)
check(destroyArmor.Entity == nil and #destroyArmor:GetHandles() == 0, "Entity destruction clears Armor")
check(target:GetComponent(ArmorComponent) == armor, "Armor does not replace other component contracts")

-- Conditions and report ordering are deterministic and remain data-only.
local conditional = ArmorProfile.new({
	Name = "Conditional", Consequences = { Pull = false },
	Condition = function(hitEvent) return hitEvent.Priority == 7 end,
})
local conditionalTarget = world:CreateEntity()
local conditionalArmor = conditionalTarget:AddComponent(ArmorComponent.new())
conditionalArmor:Grant(conditional)
local conditionalHit = HitEvent.new({ Target = conditionalTarget, TargetEntityId = conditionalTarget.Id, Priority = 7 })
local otherHit = HitEvent.new({ Target = conditionalTarget, TargetEntityId = conditionalTarget.Id, Priority = 1 })
check(conditionalArmor:Resolve("Pull", conditionalHit) ~= nil, "Armor condition can match a combat interaction")
check(conditionalArmor:Resolve("Pull", otherHit) == nil, "Unmatched Armor condition is allowed through")
local h1 = makeHit(30)
local h2 = makeHit(10)
local ordered = resolver:Process({ h1, h2 })
check(#ordered == 2 and ordered[1].AttackInstanceId == 10, "Armor results use stable AttackInstance ordering")
local reversed = resolver:Process({ h2, h1 })
check(ordered[1].AttackInstanceId == reversed[1].AttackInstanceId, "Input HitEvent order does not alter Armor result order")
check(resolver:GetResultForHit(h1) ~= nil, "Resolver can retrieve a result by its HitEvent")
check(#resolver:FilterHitEvents({ h1, h2 }, "Damage") == 2, "Allowed category retains the original HitEvents")
check(#resolver:FilterHitEvents({ h1, h2 }, "Hitstun") == 0, "Blocked category filters consequence consumers only")
check(h1.Target == target and h1.AttackInstanceId == 30, "Filtering never mutates or removes the original HitEvent")
local indexedResolver = ArmorResolver.new(world)
local indexedHits = {}
for index = 1, 128 do indexedHits[index] = makeHit(1000 + index) end
indexedResolver:Process(indexedHits)
for _, indexedHit in ipairs(indexedHits) do
	check(indexedResolver:GetResultForHit(indexedHit).HitEvent == indexedHit,
		"Armor results are indexed by HitEvent identity")
end
indexedResolver:Clear()
check(indexedResolver:GetResultForHit(indexedHits[1]) == nil,
	"Clearing Armor results also clears the HitEvent index")

-- Motion categories are filtered individually, and Damage remains unrelated to them.
local motionTarget = world:CreateEntity()
local motionArmor = motionTarget:AddComponent(ArmorComponent.new())
local motionProfile = ArmorProfile.new({ Consequences = { Knockback = false, Launch = true, Push = false, Pull = true } })
motionArmor:Grant(motionProfile)
local motionEvent = HitEvent.new({ Target = motionTarget, TargetEntityId = motionTarget.Id,
	AttackInstance = instance, AttackInstanceId = instance.Id })
local motionResult = resolver:Resolve(motionEvent)
local requests = {
	{ Target = motionTarget, Source = instance, Type = MotionType.Knockback },
	{ Target = motionTarget, Source = instance, Type = MotionType.Launch },
	{ Target = motionTarget, Source = instance, Type = MotionType.Push },
	{ Target = motionTarget, Source = instance, Type = MotionType.Pull },
	{ Target = motionTarget, Source = instance, Type = "Impulse" },
}
local filteredMotion = resolver:FilterMotionRequests(requests, { motionResult })
check(#filteredMotion == 2, "Motion Armor independently filters blocked request types")
check(filteredMotion[1].Type == MotionType.Launch and filteredMotion[2].Type == MotionType.Pull,
	"Launch and Pull continue when explicitly allowed")
check(motionResult:Blocks("Knockback") and motionResult:Blocks("Impulse"), "Impulse maps to Knockback Armor")
check(motionResult:Blocks("Push") and motionResult:Allows("Damage"), "Push Armor does not imply Damage Armor")
check(resolver:FilterMotionRequests({ requests[1] }, {})[1] == requests[1], "Unrelated motion source is not suppressed")

-- Independent systems can coexist on a pure CombatEntity.
local compositionWorld = World.new()
local composed = compositionWorld:CreateEntity()
local composedArmor = composed:AddComponent(ArmorComponent.new())
local composedProtection = composed:AddComponent(ProtectionComponent.new())
local composedDefense = composed:AddComponent(DefenseComponent.new())
local composedHitstop = composed:AddComponent(HitstopComponent.new())
local composedMotion = composed:AddComponent(MotionComponent.new())
local composedStatuses = composed:AddComponent(StatusContainer.new())
composedArmor:Grant(ArmorProfile.SuperArmor({ Name = "Composite" }))
check(composedProtection ~= nil and composedDefense ~= nil, "Protection and Defense remain separate components")
check(composedHitstop ~= nil and composedMotion ~= nil, "Hitstop and Motion remain separate components")
check(composedStatuses ~= nil and composed:GetComponent(ArmorComponent) == composedArmor,
	"Armor composes with reactions without a Character")
check(composed:IsAlive(), "Armor does not create an EntityState")
composed:SetState(EntityState.Dead)
check(composed:IsDead() and composedArmor:Resolve("Hitstun", hit) ~= nil, "Dead state remains independent of Armor")
check(composed:GetState() == EntityState.Dead, "Armor resolution never changes Alive/Dead")

-- Protection remains distinguishable from Armor and can be queried alongside it.
local protectedWorld = World.new()
local protected = protectedWorld:CreateEntity()
local protection = protected:AddComponent(ProtectionComponent.new())
local protectedArmor = protected:AddComponent(ArmorComponent.new())
local invulnerability = protection:Grant({ Kind = "Invulnerability", Categories = { "Damage" }, Permanent = true })
local immunity = protection:Grant({ Kind = "Immunity", Categories = { "Knockback" }, Permanent = true })
protectedArmor:Grant(ArmorProfile.new({ Consequences = { Hitstun = false, Knockback = false } }))
local protectionResolver = protectedWorld:GetProtectionResolver()
local invulResult = protectionResolver:Query({ Target = protected, Category = "Damage" })
local immuneResult = protectionResolver:Query({ Target = protected, Category = "Knockback" })
check(invulResult.Result == "Blocked" and invulResult.Kind == "Invulnerability", "Invulnerability result remains identifiable")
check(immuneResult.Result == "Blocked" and immuneResult.Kind == "Immunity", "Immunity result remains identifiable")
local protectedHit = HitEvent.new({ Target = protected, TargetEntityId = protected.Id, AttackInstance = instance, AttackInstanceId = instance.Id })
local bothLayers = protectedWorld:GetArmorResolver():Resolve(protectedHit)
check(bothLayers:Blocks("Hitstun") and bothLayers:Blocks("Knockback"), "Armor remains independently reported with Protection")
check(invulResult.Protection == invulnerability and immuneResult.Protection == immunity, "Protection data is not rewritten into Armor data")
check(protected:GetComponent(ProtectionComponent) == protection and protected:GetComponent(ArmorComponent) == protectedArmor,
	"Protection and Armor do not overwrite each other")

-- Hit, damage, reaction and motion integration: Armor never erases collision or HitHistory.
local integrated = World.new()
local collision = CollisionWorld.new(integrated)
local source, victim = integrated:CreateEntity(), integrated:CreateEntity()
local victimHealth = victim:AddComponent(HealthComponent.new({ MaxHealth = 100 }))
local victimStatuses = victim:AddComponent(StatusContainer.new())
local victimArmor = victim:AddComponent(ArmorComponent.new())
victim:AddComponent(Hurtbox.new({ Shape = "Sphere", Radius = 1 }))
local execution = AttackInstance.new(Attack.new({ Damage = 20, Hitstun = 12 }), source):Activate()
local hitbox = execution:AddHitbox(Hitbox.new({ Shape = "Sphere", Radius = 1 }))
source:AddComponent(hitbox)
victimArmor:Grant(ArmorProfile.SuperArmor({ Name = "StaggerArmor" }))
integrated:GetMotionResolver():QueueRequest(MotionRequest.new({
	Source = execution, Target = victim, Type = MotionType.Knockback,
	Direction = Vector3.new(0, 1, 0), Magnitude = 10,
}))
integrated:Step(1 / 60, 1, 1 / 60)
local integratedHitEvents = collision:GetHitEvents()
check(#integratedHitEvents == 1, "SuperArmor does not turn a collision into a miss")
check(integratedHitEvents[1].Target == victim, "Original HitEvent retains its target")
check(#integrated:GetArmorResults() == 1, "World resolves Armor after Defense")
check(integrated:GetArmorResults()[1]:Blocks("Hitstun"), "Integrated SuperArmor blocks Hitstun")
check(integrated:GetArmorResults()[1]:Allows("Damage"), "Integrated SuperArmor allows Damage")
check(victimHealth:GetHealth() == 80, "Damage is applied while Armor blocks Hitstun")
check(#integrated:GetDamageRequests() == 1 and #integrated:GetDamageEvents() == 1, "Allowed damage creates normal damage data")
check(not victimStatuses:HasStatus("Hitstun"), "Blocked Hitstun is not applied as a reaction")
check(#integrated:GetMotionResults() == 0, "SuperArmor can block tagged Knockback independently of Damage")
check(integrated:GetCounterResults()[1].Type == CounterResult.Type.Normal,
	"Armor does not automatically turn an ordinary hit into CounterHit")

-- Protection(Damage) and Armor(Knockback) independently suppress their own outcomes.
local protectedIntegration = World.new()
local protectionCollision = CollisionWorld.new(protectedIntegration)
local pSource, pTarget = protectedIntegration:CreateEntity(), protectedIntegration:CreateEntity()
local pHealth = pTarget:AddComponent(HealthComponent.new({ MaxHealth = 40 }))
local pStatuses = pTarget:AddComponent(StatusContainer.new())
local pProtection = pTarget:AddComponent(ProtectionComponent.new())
local pArmor = pTarget:AddComponent(ArmorComponent.new())
pProtection:Grant({ Kind = "Invulnerability", Categories = { "Damage" }, Permanent = true })
pArmor:Grant(ArmorProfile.new({ Name = "KnockbackArmor", Consequences = { Knockback = false, Hitstun = false } }))
pTarget:AddComponent(Hurtbox.new({ Shape = "Sphere", Radius = 1 }))
local pExecution = AttackInstance.new(Attack.new({ Damage = 9, Hitstun = 4 }), pSource):Activate()
pSource:AddComponent(pExecution:AddHitbox(Hitbox.new({ Shape = "Sphere", Radius = 1 })))
protectedIntegration:GetMotionResolver():QueueRequest(MotionRequest.new({
	Source = pExecution, Target = pTarget, Type = MotionType.Knockback,
	Direction = Vector3.new(1, 0, 0), Magnitude = 8,
}))
protectedIntegration:Step(1 / 60, 1, 1 / 60)
check(#protectionCollision:GetHitEvents() == 1, "Protection(Damage) still preserves HitEvent")
check(pHealth:GetHealth() == 40 and #protectedIntegration:GetDamageRequests() == 0,
	"Protected Damage creates no DamageRequest or false DamageEvent")
check(#protectedIntegration:GetDamageEvents() == 0, "Blocked Damage emits no DamageEvent")
check(protectedIntegration:GetProtectionResults()[2].Result == "Blocked", "Protection(Damage) is identified separately")
check(protectedIntegration:GetArmorResults()[1]:Blocks("Knockback"), "Armor(Knockback) is reported independently")
check(protectedIntegration:GetArmorResults()[1]:Allows("Damage"), "Damage permission remains allowed by Armor")
check(pProtection ~= nil and pArmor ~= nil, "Protection and Armor coexist on one target")
check(not pStatuses:HasStatus("Hitstun"), "Protection and Armor can independently block Damage and Hitstun")
check(#protectedIntegration:GetMotionResults() == 0, "Armor filters a tagged Knockback request without touching Protection(Damage)")

-- Armor that blocks Damage is also a distinct consequence result and does not lie about damage.
local damageArmorWorld = World.new()
local damageCollision = CollisionWorld.new(damageArmorWorld)
local dSource, dTarget = damageArmorWorld:CreateEntity(), damageArmorWorld:CreateEntity()
local dHealth = dTarget:AddComponent(HealthComponent.new({ MaxHealth = 30 }))
local dStatuses = dTarget:AddComponent(StatusContainer.new())
local dArmor = dTarget:AddComponent(ArmorComponent.new())
dArmor:Grant(ArmorProfile.new({ Name = "DamageGuard", Damage = false, Hitstun = true }))
dTarget:AddComponent(Hurtbox.new({ Shape = "Sphere", Radius = 1 }))
local dExecution = AttackInstance.new(Attack.new({ Damage = 10, Hitstun = 5 }), dSource):Activate()
dSource:AddComponent(dExecution:AddHitbox(Hitbox.new({ Shape = "Sphere", Radius = 1 })))
damageArmorWorld:Step(1 / 60, 1, 1 / 60)
check(#damageCollision:GetHitEvents() == 1, "Damage Armor does not erase the hit")
check(dHealth:GetHealth() == 30, "Armor can explicitly block Damage")
check(#damageArmorWorld:GetDamageEvents() == 0 and #damageArmorWorld:GetDamageRequests() == 0,
	"Damage blocked by Armor emits no applied DamageEvent or DamageRequest")
check(damageArmorWorld:GetArmorResults()[1]:Blocks("Damage"), "ArmorResult marks denied Damage")
check(damageArmorWorld:GetArmorResults()[1]:Allows("Hitstun"), "Other consequence can remain allowed")
check(dStatuses:HasStatus("Hitstun"), "Damage Armor can block Damage while allowing the Hitstun reaction")

-- Defense, Parry, Clash, Priority, Counter, and Hitstop remain separate systems.
local defenseWorld = World.new()
local defenseCollision = CollisionWorld.new(defenseWorld)
local fSource, fTarget = defenseWorld:CreateEntity(), defenseWorld:CreateEntity()
local fDefense = fTarget:AddComponent(DefenseComponent.new())
local fArmor = fTarget:AddComponent(ArmorComponent.new())
fArmor:Grant(ArmorProfile.SuperArmor({ Name = "DefenseCoexist" }))
fTarget:AddComponent(Hurtbox.new({ Shape = "Sphere", Radius = 1 }))
local fExecution = AttackInstance.new(Attack.new({ Damage = 2 }), fSource):Activate()
fSource:AddComponent(fExecution:AddHitbox(Hitbox.new({ Shape = "Sphere", Radius = 1 })))
fDefense:SetBlocking(true)
defenseWorld:Step(1 / 60, 1, 1 / 60)
check(defenseWorld:GetDefenseEvents()[1].Result == DefenseResult.Blocked, "Block remains Defense's responsibility")
check(#defenseWorld:GetArmorResults() == 0, "Blocked hits do not get reclassified by Armor")
check(fTarget:GetComponent(ArmorComponent) == fArmor, "Block does not replace Armor")
check(defenseCollision:GetHitEvents()[1] ~= nil, "Defense and Armor preserve collision evidence")
fDefense:SetBlocking(false)
fDefense:OpenParryWindow(2, 1)
local parrySource = defenseWorld:CreateEntity()
local parryExecution = AttackInstance.new(Attack.new({ Damage = 2 }), parrySource):Activate()
parrySource:AddComponent(parryExecution:AddHitbox(Hitbox.new({ Shape = "Sphere", Radius = 1 })))
defenseWorld:Step(1 / 60, 2, 2 / 60)
check(defenseWorld:GetDefenseEvents()[1].Result == DefenseResult.Parried, "Parry remains Defense's responsibility with Armor present")
check(#defenseWorld:GetArmorResults() == 0, "Parried hits do not become Armor outcomes")

local comboTarget = world:CreateEntity()
local comboArmor = comboTarget:AddComponent(ArmorComponent.new())
comboArmor:Grant(ArmorProfile.SuperArmor({ Name = "AllReaction", DurationFrames = 3 }))
comboTarget:AddComponent(HitstopComponent.new())
comboTarget:AddComponent(OffensiveStateComponent.new())
check(comboArmor:Resolve("Hitstun", hit) ~= nil, "SuperArmor does not depend on Hitstop")
check(comboTarget:GetComponent(HitstopComponent) ~= nil, "Hitstop remains its own component")
check(comboTarget:GetComponent(OffensiveStateComponent) ~= nil, "Armor does not create Counter state")
check(comboArmor:GetHandles()[1].Profile.Kind == "SuperArmor", "Counter/Hitstop do not rewrite Armor kind")
check(ProtectionType.Damage == "Damage" and ArmorCategory.Damage == "Damage", "Shared category names do not merge Protection with Armor")
check(MotionType.Launch == "Launch" and comboArmor:Resolve("Launch", hit) ~= nil, "Launch is an independent Armor consequence")
check(comboArmor:Resolve("Push", hit) ~= nil and comboArmor:Resolve("Pull", hit) ~= nil,
	"SuperArmor blocks its reaction categories without changing entity state")
local composedHitstop = comboTarget:GetComponent(HitstopComponent)
composedHitstop:Apply(2, 0, nil)
world:Step(1 / 60, 1, 1 / 60)
check(composedHitstop:IsFrozen() and comboArmor:Resolve("Hitstun", hit) ~= nil,
	"Hitstop and Armor can be active simultaneously without replacing each other")

-- Dead entities retain their state; temporary Armor still expires by steps.
local deadWorld = World.new()
local dead = deadWorld:CreateEntity()
local deadArmor = dead:AddComponent(ArmorComponent.new())
local deadHandle = deadArmor:Grant(ArmorProfile.new({ DurationFrames = 1, Consequences = { Hitstun = false } }))
dead:SetState(EntityState.Dead)
check(dead:IsDead() and deadArmor:Resolve("Hitstun", hit) == deadHandle, "Dead remains Dead while Armor exists")
deadWorld:Step(1 / 60, 1, 1 / 60)
check(dead:IsDead() and not deadHandle.Active, "Armor expiry does not revive a Dead entity")
check(dead:GetState() == EntityState.Dead, "Armor cannot change Core EntityState")

-- Resolver inputs, outputs, and category filters remain data-oriented.
local emptyResolver = ArmorResolver.new()
check(#emptyResolver:Process({}) == 0, "Empty resolution is supported")
local bareEntity = world:CreateEntity()
local bareHit = HitEvent.new({ Target = bareEntity, TargetEntityId = bareEntity.Id, AttackInstanceId = 999 })
local noArmorResult = emptyResolver:Resolve(bareHit)
check(noArmorResult:Allows("Damage") and noArmorResult:Allows("Hitstun"), "Missing component means consequences are allowed")
check(noArmorResult.ProfileByCategory.Damage == nil, "No Armor profile is reported when none applies")
check(noArmorResult.Priority == 0, "Uncontested result has neutral Armor priority")
check(#emptyResolver:FilterHitEvents({ bareHit }, "Damage") == 1, "No Armor does not filter Damage")
check(emptyResolver:GetResultForHit(bareHit) == nil, "Unprocessed hits do not fabricate stored results")
check(emptyResolver:Clear() == emptyResolver, "Resolver can clear its result buffer")
check(invulnerability.Kind ~= "Armor" and basic.Kind ~= "SuperArmor", "Protection, Armor, and SuperArmor keep distinct identities")
check(#ProtectionComponent.new().Protections == 0, "Protection component has its own independent storage")

-- Clash and Counter keep their own semantics even when Armor is active.
local clashWorld = World.new()
local clashA, clashB = clashWorld:CreateEntity(), clashWorld:CreateEntity()
local clashArmor = clashB:AddComponent(ArmorComponent.new())
clashArmor:Grant(ArmorProfile.SuperArmor({ Name = "ClashIndependent" }))
local clashInstanceA, clashInstanceB = { Id = 300 }, { Id = 200 }
local clashHitA = HitEvent.new({ AttackInstance = clashInstanceA, AttackInstanceId = 300,
	Attacker = clashA, AttackerEntityId = clashA.Id, Target = clashB, TargetEntityId = clashB.Id,
	Frame = 1, Priority = 1 })
local clashHitB = HitEvent.new({ AttackInstance = clashInstanceB, AttackInstanceId = 200,
	Attacker = clashB, AttackerEntityId = clashB.Id, Target = clashA, TargetEntityId = clashA.Id,
	Frame = 1, Priority = 1 })
local clashResolver = CombatResolver.new()
clashResolver:Process({ clashHitA, clashHitB })
check(clashResolver:GetResolutionEvents()[1].Outcome == CombatResolutionResult.Clash,
	"Armor does not change CombatResolution Clash")
check(clashArmor:Resolve("Hitstun", clashHitA) ~= nil, "Armor can coexist with an independent Clash result")
local priorityHitA = HitEvent.new({ AttackInstance = { Id = 501 }, AttackInstanceId = 501,
	Attacker = clashA, AttackerEntityId = clashA.Id, Target = clashB, TargetEntityId = clashB.Id,
	Frame = 2, Priority = 8 })
local priorityHitB = HitEvent.new({ AttackInstance = { Id = 502 }, AttackInstanceId = 502,
	Attacker = clashB, AttackerEntityId = clashB.Id, Target = clashA, TargetEntityId = clashA.Id,
	Frame = 2, Priority = 1 })
clashResolver:Process({ priorityHitB, priorityHitA })
check(clashResolver:GetResolutionEvents()[1].Outcome == CombatResolutionResult.PriorityWin
	and clashResolver:GetResolutionEvents()[1].WinnerAttackInstance.Id == 501,
	"Armor does not replace Priority resolution")

local counterWorld = World.new()
local counterAttacker, counterTarget = counterWorld:CreateEntity(), counterWorld:CreateEntity()
local counterTargetArmor = counterTarget:AddComponent(ArmorComponent.new())
counterTargetArmor:Grant(ArmorProfile.SuperArmor({ Name = "CounterIndependent" }))
local OffensiveStateComponent = require(Combat.OffensiveStateComponent)
local offensiveState = counterTarget:AddComponent(OffensiveStateComponent.new())
offensiveState:SetWindow(1, 1)
local counterInstance = { Id = 401 }
local counterHit = HitEvent.new({ AttackInstance = counterInstance, AttackInstanceId = 401,
	Attacker = counterAttacker, AttackerEntityId = counterAttacker.Id,
	Target = counterTarget, TargetEntityId = counterTarget.Id, Frame = 1 })
local counterResults = CounterResolver.new():Process({ counterHit })
check(counterResults[1].Type == CounterResult.Type.CounterHit,
	"Armor does not turn its target into a CounterHit or remove a valid Counter condition")
check(counterTargetArmor:Resolve("Hitstun", counterHit) ~= nil,
	"Counter and Armor can be reported for the same entity independently")

check(cases >= 70, "CombatArmorTest must include at least 70 significant cases")
print("Combat armor tests passed (" .. tostring(cases) .. " cases)")
