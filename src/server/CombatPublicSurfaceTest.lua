return function()
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
check(type(CombatAPI.CollisionTopologyCatalog) == "table"
    and type(CombatAPI.CollisionTopologyCatalog.new) == "function",
    "CollisionTopologyCatalog constructor is not public")
check(type(CombatAPI.Hitbox) == "table" and type(CombatAPI.Hitbox.new) == "function", "Hitbox constructor is not public")
check(type(CombatAPI.Hurtbox) == "table" and type(CombatAPI.Hurtbox.new) == "function", "Hurtbox constructor is not public")
check(type(CombatAPI.OffensiveProperties) == "table", "OffensiveProperties is not public")
check(type(CombatAPI.APIContext) == "table" and type(CombatAPI.APIContext.new) == "function",
    "APIContext constructor is not public")
check(type(CombatAPI.APIResult) == "table" and type(CombatAPI.APIResult.new) == "function",
    "APIResult constructor is not public")
check(type(CombatAPI.APIError) == "table" and type(CombatAPI.APIError.new) == "function",
    "APIError constructor is not public")
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

-- The reference consumer must capture/restore collision-owned hitboxes without
-- attaching them as generic Entity components (Hitbox has a CollisionWorld contract).
local rollbackWorld = CombatAPI.CreateWorld()
local simulation = CombatAPI.Simulation.new(rollbackWorld)
check(simulation:GetWorld() == rollbackWorld and rollbackWorld:GetSimulation() == simulation,
    "public Simulation constructor associates rollback state with its World")
local publicContext = CombatAPI.GetContext(rollbackWorld)
check(publicContext ~= nil and publicContext == rollbackWorld:GetAPIContext(),
    "CombatAPI context helpers return the World-owned public context")
check(publicContext:HasFeature("Events"), "public API context exposes the Events feature")
local collisionWorld = CombatAPI.CollisionWorld.new(rollbackWorld)
local topologyCatalog = CombatAPI.CollisionTopologyCatalog.new()
topologyCatalog:Register("public-surface.hitbox", 1, function(saved, regionOwner)
    return CombatAPI.Hitbox.new({
        Id = saved.Id,
        Owner = regionOwner,
        Shape = saved.Shape,
        Size = Vector3.new(10, 4, 10),
        Damage = 8,
        TopologyDefinitionId = "public-surface.hitbox",
        TopologyDefinitionVersion = 1,
    })
end)
topologyCatalog:Seal()
collisionWorld:SetTopologyCatalog(topologyCatalog)
local rollbackAttack = CombatAPI.Attack.new({
    Id = "public-customdata-rollback",
    Damage = 8,
    CustomData = { BaseRadius = 2, Element = "Test" },
})
local rollbackCatalog = CombatAPI.AttackCatalog.new()
rollbackCatalog:Register(rollbackAttack, 1)
rollbackCatalog:Seal()
collisionWorld:SetAttackCatalog(rollbackCatalog)
local owner = rollbackWorld:CreateEntity()
local ownerId = owner.Id
local instance = CombatAPI.AttackInstance.new(rollbackAttack, owner, nil, {
    Id = "public-customdata-instance",
    CustomDataOverrides = { Radius = 5 },
})
instance:Activate()
local region = CombatAPI.Hitbox.new({
    Id = 7001,
    Owner = owner,
    AttackId = rollbackAttack.Id,
    Position = Vector3.new(0, 3, 0),
    Size = Vector3.new(10, 4, 10),
    Damage = 8,
    TopologyDefinitionId = "public-surface.hitbox",
    TopologyDefinitionVersion = 1,
})
instance:AddHitbox(region)
collisionWorld:RegisterHitbox(region)
local capturedState = rollbackWorld:CaptureCombatState()
check(capturedState.CollisionWorld.AttackInstances[1].CustomDataOverrides.Radius == 5,
    "public collision snapshot captures per-instance CustomDataOverrides")
region.Position = Vector3.new(99, 99, 99)
local restored, restoreError = rollbackWorld:RestoreCombatState(capturedState)
check(restored, "public collision snapshot restores: " .. tostring(restoreError))
local replayOwner = rollbackWorld:GetEntity(ownerId)
local restoredHitbox = collisionWorld:GetHitboxes()[1]
local replayedInstance = restoredHitbox and restoredHitbox.AttackInstance
check(replayOwner ~= nil and replayedInstance ~= nil,
    "public rollback rebuilds the owner and attack instance")
check(replayedInstance.OffensiveProperties.CustomData.Radius == 5
    and replayedInstance.OffensiveProperties.CustomData.Element == "Test",
    "public rollback reconstructs effective CustomData from definition and override")
check(restoredHitbox.Position == Vector3.new(0, 3, 0),
    "public rollback restores collision region geometry")
rollbackWorld:Destroy()

print("CombatPublicSurfaceTest passed")

end
