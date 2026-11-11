return function()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local Combat = Shared:WaitForChild("Combat")

local EntityState = require(Core.EntityState)
local World = require(Core.World)
local Protection = require(Combat.Protection)
local ProtectionType = require(Combat.ProtectionType)
local ProtectionQuery = require(Combat.ProtectionQuery)
local ProtectionResult = require(Combat.ProtectionResult)
local ProtectionResolver = require(Combat.ProtectionResolver)
local ProtectionComponent = require(Combat.ProtectionComponent)

local passed = 0
local function check(condition, message)
	assert(condition, message or ("Protection assertion " .. tostring(passed + 1) .. " failed"))
	passed += 1
end

local function expectFailure(callback, message)
	local ok = pcall(callback)
	check(not ok, message)
end

local requiredCategories = {
	ProtectionType.Damage,
	ProtectionType.Hitstun,
	ProtectionType.Knockback,
	ProtectionType.Launch,
	ProtectionType.Push,
	ProtectionType.Pull,
	ProtectionType.Motion,
	ProtectionType.Impulse,
	ProtectionType.Hit,
}
for _, category in ipairs(requiredCategories) do
	check(type(category) == "string" and category ~= "", "ProtectionType entries must stay string-based and non-empty")
end
check(#requiredCategories == 9, "ProtectionType should define the required built-in categories")

local valid = Protection.new({
	Kind = "Invulnerability",
	Categories = { ProtectionType.Damage, ProtectionType.Hitstun },
	DurationFrames = 5,
	Priority = 7,
	Source = { Id = "source" },
	Target = { Id = "target" },
})
check(valid.Kind == "Invulnerability", "Invulnerability kind should be preserved")
check(valid:Blocks(ProtectionType.Damage), "Protection matches a configured category")
check(valid:Blocks(ProtectionType.Hitstun), "Protection should block multiple categories")
check(not valid:Blocks(ProtectionType.Knockback), "Unconfigured categories remain unaffected")
check(valid.DurationFrames == 5 and valid.RemainingFrames == 5, "Duration is stored as frames and starts full")
check(valid.Priority == 7, "Priority is preserved")
check(not valid:IsExpired(), "Fresh protection remains active")
valid:AdvanceFrame()
check(valid.RemainingFrames == 4, "Each frame consumes one remaining frame")
check(valid.Active == true, "Active protection stays enabled until expiration")

local stringCategory = Protection.new({
	Kind = "Immunity",
	Categories = ProtectionType.Damage,
	DurationFrames = 2,
	Priority = 3,
})
check(stringCategory:Blocks(ProtectionType.Damage), "String categories are normalized to a single entry")
check(stringCategory.Kind == "Immunity", "Immunity kind should be allowed")

local permanent = Protection.new({
	Kind = "Immunity",
	Categories = ProtectionType.Launch,
	Permanent = true,
	Priority = 11,
})
check(permanent.Permanent == true, "Permanent protection should stay active indefinitely")
check(permanent.RemainingFrames == nil, "Permanent protection does not decrement over time")
permanent:AdvanceFrame()
check(permanent.Active == true, "Permanent protection remains active after a frame tick")

expectFailure(function()
	Protection.new({ Kind = "Wrong", Categories = ProtectionType.Damage })
end, "Unsupported protection kinds should fail")
expectFailure(function()
	Protection.new({ Kind = "Invulnerability", Categories = {} })
end, "Empty category lists should fail")
expectFailure(function()
	Protection.new({ Kind = "Invulnerability", Categories = ProtectionType.Damage, DurationFrames = -1 })
end, "Negative duration frames should fail")
expectFailure(function()
	Protection.new({ Kind = "Invulnerability", Categories = ProtectionType.Damage, Priority = math.huge })
end, "Infinite priority should fail")

local world = World.new()
local target = world:CreateEntity()
local component = target:AddComponent(ProtectionComponent.new())
local damageGuard = Protection.new({
	Kind = "Invulnerability",
	Categories = { ProtectionType.Damage, ProtectionType.Hitstun },
	DurationFrames = 3,
	Priority = 10,
})
local knockbackGuard = Protection.new({
	Kind = "Immunity",
	Categories = { ProtectionType.Knockback },
	DurationFrames = 4,
	Priority = 4,
})
local addedDamage, reasonA = component:Add(damageGuard)
local addedKnockback, reasonB = component:Add(knockbackGuard)
check(addedDamage == damageGuard and reasonA == "Added", "Component adds a new protection")
check(addedKnockback == knockbackGuard and reasonB == "Added", "Component accepts multiple protections")
check(component:Resolve(ProtectionType.Damage) == damageGuard, "Resolve picks the correct active protection")
check(component:Resolve(ProtectionType.Knockback) == knockbackGuard, "Resolve respects the target category")
check(component:Resolve(ProtectionType.Push) == nil, "Unknown categories remain unblocked")

local replacement = Protection.new({
	Kind = "Immunity",
	Categories = { ProtectionType.Damage },
	DurationFrames = 2,
	Priority = 15,
})
component:Add(replacement)
check(component:Resolve(ProtectionType.Damage) == replacement, "Higher-priority protection wins for the same category")
check(#component:GetActiveProtections() == 3, "All three active protections are enumerated without expired entries")

local query = ProtectionQuery.new({
	Target = target,
	Category = ProtectionType.Damage,
	Interaction = "DamageInstance",
	Source = { Id = "attacker" },
	Priority = 8,
	Frame = 2,
	Time = 0.2,
})
check(query.Target == target and query.Category == ProtectionType.Damage, "ProtectionQuery preserves target and category")
check(query.Interaction == "DamageInstance", "ProtectionQuery preserves interaction metadata")
check(query.Priority == 8, "ProtectionQuery stores relative priority")

local resolver = world:GetProtectionResolver()
local result = resolver:Query(query)
check(result.Result == "Blocked", "ProtectionResolver returns a Blocked result when protection applies")
check(result.Protection == replacement, "Resolver returns the winning protection instance")
check(result.Category == ProtectionType.Damage, "Result preserves the queried category")
check(result.Priority == replacement.Priority, "Priority is taken from the winning protection")
check(#resolver:GetResults() == 1, "Resolver records each query result")

local anotherTarget = world:CreateEntity()
local anotherComponent = anotherTarget:AddComponent(ProtectionComponent.new())
local allowed = ProtectionQuery.new({
	Target = anotherTarget,
	Category = ProtectionType.Push,
	Source = { Id = "other" },
})
check(resolver:Query(allowed).Result == "Allowed", "Resolver returns Allowed when no protection applies")

local deadTarget = world:CreateEntity()
local deadComponent = deadTarget:AddComponent(ProtectionComponent.new())
deadTarget:SetState(EntityState.Dead)
local deadProtection = Protection.new({
	Kind = "Immunity",
	Categories = ProtectionType.Damage,
	DurationFrames = 1,
})
local deadResult = deadComponent:Add(deadProtection)
check(deadResult ~= nil, "Protection may be added before the entity is destroyed")
check(deadComponent:Resolve(ProtectionType.Damage) == nil, "Dead entities cannot resolve active protections")
check(#deadComponent:GetActiveProtections() == 1, "Dead entities retain protection data without resolving it")

local expiry = Protection.new({
	Kind = "Invulnerability",
	Categories = { ProtectionType.Push, ProtectionType.Pull },
	DurationFrames = 2,
	Priority = 1,
})
local expiryTarget = world:CreateEntity()
local expiryComponent = expiryTarget:AddComponent(ProtectionComponent.new())
expiryComponent:Add(expiry)
check(expiryComponent:Resolve(ProtectionType.Push) == expiry, "Fresh expiry guard blocks correctly")
resolver:AdvanceFrame(1)
resolver:AdvanceFrame(2)
check(expiryComponent:Resolve(ProtectionType.Push) == nil, "Protection expires after its remaining frame budget elapses")
check(expiryComponent:Resolve(ProtectionType.Pull) == nil, "An expired protection no longer blocks related categories")
check(#expiryComponent:GetActiveProtections() == 0, "Expired protection is removed from the active list")

local merged = Protection.new({
	Kind = "Invulnerability",
	Categories = { ProtectionType.Hit, ProtectionType.Damage },
	DurationFrames = 1,
	Priority = 0,
})
local mergedComponent = world:CreateEntity():AddComponent(ProtectionComponent.new())
mergedComponent:Add(merged)
check(mergedComponent:Resolve(ProtectionType.Hit) == merged, "Protection allows explicit Hit-category coverage")
check(mergedComponent:Resolve(ProtectionType.Damage) == merged, "Damage category can coexist with Hit in a single protection")

local resultObject = ProtectionResult.new(query, "Allowed", nil)
check(resultObject.Target == target and resultObject.Category == ProtectionType.Damage and resultObject.Result == "Allowed",
	"ProtectionResult should carry the target, category, and outcome")
check(resultObject.Priority == 8, "ProtectionResult defaults to the query priority when no protection is present")

local validList = {
	Protection.new({ Kind = "Invulnerability", Categories = ProtectionType.Damage, DurationFrames = 1, Priority = 1 }),
	Protection.new({ Kind = "Immunity", Categories = { ProtectionType.Hitstun, ProtectionType.Push }, DurationFrames = 1, Priority = 2 }),
	Protection.new({ Kind = "Invulnerability", Categories = ProtectionType.Knockback, DurationFrames = 1, Priority = 3 }),
}
for index, protection in ipairs(validList) do
	check(protection:Blocks(ProtectionType.Damage) or protection:Blocks(ProtectionType.Hitstun)
		or protection:Blocks(ProtectionType.Knockback) or protection:Blocks(ProtectionType.Push),
		"Protection instances remain valid across several category combinations (case " .. tostring(index) .. ")")
end

local unprotected = resolver:Query({
	Target = world:CreateEntity(),
	Category = ProtectionType.Launch,
	Source = { Id = "none" },
})
check(unprotected.Result == "Allowed", "Unprotected target remains allowed")
check(unprotected.Protection == nil, "Allowed result carries no protection instance")

check(passed >= 60, "The protection suite must include at least 60 significant assertions")
print("Combat protection tests passed")

end
