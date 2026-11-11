return function()
-- Phase 3: validates reversible collision geometry and active contact state for a stable topology.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Core.World)
local Hitbox = require(Shared.Combat.Hitbox)
local Hurtbox = require(Shared.Combat.Hurtbox)
local CollisionWorld = require(Shared.Combat.CollisionWorld)
local Attack = require(Shared.Combat.Attack)
local AttackInstance = require(Shared.Combat.AttackInstance)
local AttackCatalog = require(Shared.Combat.AttackCatalog)

local world = World.new()
local collision = CollisionWorld.new(world)
local attackCatalog = AttackCatalog.new()
local attackDefinition = Attack.new({
	Id = "rollback-test-light", Damage = 5, Hitstun = 8,
	CustomData = { Radius = 2, Mode = "Charge" },
})
attackCatalog:Register(attackDefinition, 1)
collision:SetAttackCatalog(attackCatalog)
local attacker = world:CreateEntity()
local target = world:CreateEntity()
local hitbox = Hitbox.new({ Shape = "Box", Position = Vector3.new(0, 0, 0), Size = Vector3.new(2, 2, 2) })
local secondHitbox = Hitbox.new({ Shape = "Box", Position = Vector3.new(1000, 0, 0), Size = Vector3.new(2, 2, 2) })
local hurtbox = Hurtbox.new({ Shape = "Box", Position = Vector3.new(1, 0, 0), Size = Vector3.new(2, 2, 2) })
local attackInstance = AttackInstance.new(attackDefinition, attacker, world.IdGenerator, {
	CustomDataOverrides = { Radius = 5 },
})
local secondInstance = AttackInstance.new(attackDefinition, attacker, world.IdGenerator, {
	CustomDataOverrides = { Radius = 8, Mode = "Burst" },
})
attackInstance:Activate()
secondInstance:Activate()
attackInstance:AddHitbox(hitbox)
secondInstance:AddHitbox(secondHitbox)
attacker:AddComponent(hitbox)
attacker:AddComponent(secondHitbox)
target:AddComponent(hurtbox)

collision:Step(1 / 60, 1, 1 / 60)
assert(#collision:GetResults() == 1, "Test setup should produce one contact")
local snapshot = collision:CaptureRollbackState()
local savedOverridesById = {}
for _, savedAttack in ipairs(snapshot.AttackInstances) do
	savedOverridesById[savedAttack.Id] = savedAttack.CustomDataOverrides
end
assert(savedOverridesById[attackInstance.Id] and savedOverridesById[attackInstance.Id].Radius == 5
	and savedOverridesById[secondInstance.Id] and savedOverridesById[secondInstance.Id].Radius == 8,
	"Collision snapshot must preserve different overrides for two instances of the same definition")
local valid, validationError = collision:ValidateRollbackState(snapshot)
assert(valid, "Captured collision snapshot must validate: " .. tostring(validationError))

-- Simulate a later state with a different per-instance override. Rollback must
-- restore both the override record and the effective immutable properties.
local laterInstance = AttackInstance.new(attackDefinition, attacker, world.IdGenerator, {
	CustomDataOverrides = { Radius = 9 },
})
attackInstance.CustomDataOverrides = laterInstance.CustomDataOverrides
attackInstance.OffensiveProperties = laterInstance.OffensiveProperties
local secondLaterInstance = AttackInstance.new(attackDefinition, attacker, world.IdGenerator, {
	CustomDataOverrides = { Radius = 11, Mode = "Later" },
})
secondInstance.CustomDataOverrides = secondLaterInstance.CustomDataOverrides
secondInstance.OffensiveProperties = secondLaterInstance.OffensiveProperties
hitbox.Position = Vector3.new(100, 0, 0)
collision:Step(1 / 60, 2, 2 / 60)
assert(#collision:GetResults() == 0, "Mutated test setup should no longer produce contact")

local commit, prepareError = collision:PrepareRollbackRestore(snapshot)
assert(type(commit) == "function", "Collision restore preparation failed: " .. tostring(prepareError))
commit()
assert(hitbox.Position == Vector3.new(0, 0, 0), "Hitbox position was not restored")
assert(hurtbox.Position == Vector3.new(1, 0, 0), "Hurtbox position was not restored")
assert(collision.Frame == 1, "Collision frame was not restored")
assert(attackInstance.CustomDataOverrides.Radius == 5
	and attackInstance.OffensiveProperties.CustomData.Radius == 5
	and attackInstance.OffensiveProperties.CustomData.Mode == "Charge",
	"In-place rollback must restore the first saved override and effective CustomData")
assert(secondInstance.CustomDataOverrides.Radius == 8
	and secondInstance.OffensiveProperties.CustomData.Radius == 8
	and secondInstance.OffensiveProperties.CustomData.Mode == "Burst",
	"Rollback must independently restore a second instance of the same definition")
assert(snapshot.AttackCatalogManifest and snapshot.AttackInstances[1].DefinitionVersion == 1,
	"Collision snapshot must include versioned attack definition compatibility")
assert(collision.ActivePairs[hitbox] and collision.ActivePairs[hitbox][hurtbox], "Active contact pair was not restored")
assert(#collision:GetResults() == 0 and #collision:GetHitEvents() == 0,
	"Restore must clear output buffers to prevent replaying external effects")

local invalidSnapshot = table.clone(snapshot)
invalidSnapshot.AttackInstances = table.clone(snapshot.AttackInstances)
invalidSnapshot.AttackInstances[1] = table.clone(snapshot.AttackInstances[1])
invalidSnapshot.AttackInstances[1].CustomDataOverrides = { Invalid = function() end }
local invalidAccepted, invalidReason = collision:ValidateRollbackState(invalidSnapshot)
assert(not invalidAccepted and string.find(tostring(invalidReason), "CustomDataOverrides", 1, true),
	"Invalid overrides must be rejected during validation before restore")

local removed = collision:RemoveHitbox(hitbox)
assert(removed, "Test setup failed to remove hitbox")
local accepted = collision:ValidateRollbackState(snapshot)
assert(not accepted, "Snapshot must reject collision topology mismatch")

world:Destroy()
print("CombatCollisionRollbackTest: PASS")

end
