-- Phase 3: attack definitions must resolve by stable ID and compatible version before replay.
local Shared = game:GetService("ReplicatedStorage").Shared
local Attack = require(Shared.Combat.Attack)
local AttackCatalog = require(Shared.Combat.AttackCatalog)

local catalog = AttackCatalog.new()
local light = Attack.new({ Id = "light.v1", Damage = 5, Hitstun = 8, Priority = 1 })
catalog:Register(light, 1)

local resolved, version = catalog:Resolve("light.v1", 1)
assert(resolved == light and version == 1, "Versioned attack resolution failed")

local manifest = catalog:CaptureManifest()
local valid, reason = catalog:ValidateManifest(manifest)
assert(valid, "Matching attack manifest rejected: " .. tostring(reason))

local customCatalog = AttackCatalog.new()
local customDefinition = Attack.new({ Id = "custom.v1", CustomData = { Radius = 3 } })
customCatalog:Register(customDefinition, 1)
local customManifest = customCatalog:CaptureManifest()
assert(customManifest.Version == 2 and customManifest.Entries[1].CustomDataCanonical ~= nil
	and customCatalog:ValidateManifest(customManifest), "Manifest v2 should include canonical CustomData")
local changedCustomManifest = table.clone(customManifest)
changedCustomManifest.Entries = table.clone(customManifest.Entries)
changedCustomManifest.Entries[1] = table.clone(customManifest.Entries[1])
changedCustomManifest.Entries[1].CustomDataCanonical = "changed"
assert(not customCatalog:ValidateManifest(changedCustomManifest), "Manifest validation must detect changed CustomData")
local oldManifest = { Version = 1, Entries = { {
	Id = "custom.v1", Version = 1, Priority = 0, CanClash = true,
	HitPolicy = customDefinition.HitPolicy, HitScope = customDefinition.HitScope,
	Damage = nil, Hitstun = 0, HasCanHitCallback = false,
} } }
assert(not customCatalog:ValidateManifest(oldManifest), "Manifest v1 must reject definitions with CustomData")

local mismatch = {
	Version = 1,
	Entries = {
		{
			Id = "light.v1", Version = 2, Priority = 1, CanClash = false,
			HitPolicy = light.HitPolicy, HitScope = light.HitScope,
			Damage = light.OffensiveProperties.Damage,
			Hitstun = light.OffensiveProperties.Hitstun,
			HasCanHitCallback = false,
		},
	},
}
local mismatchValid = catalog:ValidateManifest(mismatch)
assert(not mismatchValid, "Changed attack version must reject restoration")

local duplicateCatalog = AttackCatalog.new()
duplicateCatalog:Register(Attack.new({ Id = "heavy.v1", Damage = 12 }), "rev-a")
local duplicateOk = pcall(function()
	duplicateCatalog:Register(Attack.new({ Id = "heavy.v1", Damage = 14 }), "rev-b")
end)
assert(not duplicateOk, "Duplicate attack IDs must be rejected")

catalog:Seal()
local sealedOk = pcall(function()
	catalog:Register(Attack.new({ Id = "new.v1" }), 1)
end)
assert(not sealedOk, "Sealed catalog must reject late registrations")

print("CombatAttackCatalogRollbackTest: PASS")
