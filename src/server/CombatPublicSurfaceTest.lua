return function()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatAPI = require(ReplicatedStorage.Shared.CombatAPI)

local function check(condition, message)
    if not condition then error("CombatPublicSurfaceTest: " .. message, 2) end
end

check(CombatAPI.Version == 1, "legacy numeric API version changed")
check(type(CombatAPI.SemVer) == "string", "SemVer release field is missing")
check(type(CombatAPI.Simulation) == "table" and type(CombatAPI.Simulation.new) == "function",
	"Simulation constructor is not public")
check(type(CombatAPI.Attack) == "table" and type(CombatAPI.Attack.new) == "function", "Attack constructor is not public")
check(type(CombatAPI.AttackInstance) == "table" and type(CombatAPI.AttackInstance.new) == "function", "AttackInstance constructor is not public")
check(type(CombatAPI.AttackCatalog) == "table" and type(CombatAPI.AttackCatalog.new) == "function", "AttackCatalog constructor is not public")
check(type(CombatAPI.CollisionTopologyCatalog) == "table"
	and type(CombatAPI.CollisionTopologyCatalog.new) == "function",
	"CollisionTopologyCatalog constructor is not public")
check(type(CombatAPI.CollisionWorld) == "table" and type(CombatAPI.CollisionWorld.new) == "function", "CollisionWorld constructor is not public")
check(type(CombatAPI.Hitbox) == "table" and type(CombatAPI.Hitbox.new) == "function", "Hitbox constructor is not public")
check(type(CombatAPI.Hurtbox) == "table" and type(CombatAPI.Hurtbox.new) == "function", "Hurtbox constructor is not public")
check(type(CombatAPI.OffensiveProperties) == "table", "OffensiveProperties is not public")
local typeContracts = require(ReplicatedStorage.Shared.CombatAPITypes)
check(type(typeContracts) == "table", "type contract module cannot be required")
check(CombatAPI.Contracts.AttackCatalogManifest == 2, "attack manifest contract version is incorrect")
check(CombatAPI.Contracts.CombatStateSchema == 3, "combat state schema contract version is incorrect")
local simulationWorld = CombatAPI.CreateWorld()
local simulation = CombatAPI.Simulation.new(simulationWorld, { Seed = 17 })
check(simulationWorld:GetSimulation() == simulation,
	"Public Simulation constructor must associate itself with the supplied World")
local collisionWorld = CombatAPI.CollisionWorld.new(simulationWorld)
check(type(collisionWorld.SetTopologyCatalog) == "function"
	and type(collisionWorld.RegisterHitbox) == "function"
	and type(collisionWorld.RegisterHurtbox) == "function"
	and type(collisionWorld.GetHitboxes) == "function"
	and type(collisionWorld.GetHurtboxes) == "function",
	"Public CollisionWorld region and topology methods are incomplete")
local publicHitbox = CombatAPI.Hitbox.new({
	Shape = "Box",
	Size = Vector3.new(2, 2, 2),
	TopologyDefinitionId = "public-surface-test.hitbox",
	TopologyDefinitionVersion = 1,
})
check(publicHitbox.Id == nil, "Unregistered Hitbox should not require an ID")
local registeredHitbox = collisionWorld:RegisterHitbox(publicHitbox)
check(registeredHitbox == publicHitbox
	and type(registeredHitbox.Id) == "number"
	and collisionWorld:GetHitboxes()[1] == registeredHitbox,
	"Public CollisionWorld must register and return a Hitbox")
simulationWorld:Destroy()

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

local topologyCatalog = CombatAPI.CollisionTopologyCatalog.new()
topologyCatalog:Register("public-surface-test.hitbox", 1, function(saved, owner)
	return CombatAPI.Hitbox.new({
		Id = saved.Id,
		Owner = owner,
		Shape = saved.Shape,
		Size = Vector3.new(saved.Size[1], saved.Size[2], saved.Size[3]),
		TopologyDefinitionId = "public-surface-test.hitbox",
		TopologyDefinitionVersion = 1,
	})
end)
topologyCatalog:Seal()
check(topologyCatalog:ValidateManifest(topologyCatalog:CaptureManifest()) == true,
	"Public CollisionTopologyCatalog rejected its own manifest")

print("CombatPublicSurfaceTest passed")

end
