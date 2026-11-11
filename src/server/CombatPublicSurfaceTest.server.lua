local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatAPI = require(ReplicatedStorage.Shared.CombatAPI)

local function check(condition, message)
    if not condition then error("CombatPublicSurfaceTest: " .. message, 2) end
end

check(CombatAPI.Version == 1, "legacy numeric API version changed")
check(type(CombatAPI.SemVer) == "string", "SemVer release field is missing")
check(type(CombatAPI.Attack) == "table" and type(CombatAPI.Attack.new) == "function", "Attack constructor is not public")
check(type(CombatAPI.AttackInstance) == "table" and type(CombatAPI.AttackInstance.new) == "function", "AttackInstance constructor is not public")
check(type(CombatAPI.AttackCatalog) == "table" and type(CombatAPI.AttackCatalog.new) == "function", "AttackCatalog constructor is not public")
check(type(CombatAPI.CollisionWorld) == "table" and type(CombatAPI.CollisionWorld.new) == "function", "CollisionWorld constructor is not public")
check(type(CombatAPI.Hitbox) == "table" and type(CombatAPI.Hitbox.new) == "function", "Hitbox constructor is not public")
check(type(CombatAPI.Hurtbox) == "table" and type(CombatAPI.Hurtbox.new) == "function", "Hurtbox constructor is not public")
check(type(CombatAPI.OffensiveProperties) == "table", "OffensiveProperties is not public")
local typeContracts = require(ReplicatedStorage.Shared.CombatAPITypes)
check(type(typeContracts) == "table", "type contract module cannot be required")
check(CombatAPI.Contracts.AttackCatalogManifest == 2, "attack manifest contract version is incorrect")
check(CombatAPI.Contracts.CombatStateSchema == 3, "combat state schema contract version is incorrect")

local attack = CombatAPI.Attack.new({
    Id = "public-surface-test",
    Damage = 5,
    CustomData = { Marker = "public" },
})
local catalog = CombatAPI.AttackCatalog.new()
catalog:Register(attack, 1)
catalog:Seal()
local manifest = catalog:CaptureManifest()
check(manifest.Version == 2, "public AttackCatalog did not emit manifest v2")
check(catalog:ValidateManifest(manifest) == true, "public AttackCatalog rejected its own manifest")

print("CombatPublicSurfaceTest passed")
