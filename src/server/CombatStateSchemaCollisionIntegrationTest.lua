return function()
-- End-to-end test: restore entity roster and collision topology together from a schema snapshot.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Core.World)
local Simulation = require(Shared.Simulation.Simulation)
local CombatStateSchema = require(Shared.Combat.CombatStateSchema)
local CollisionWorld = require(Shared.Combat.CollisionWorld)
local Hitbox = require(Shared.Combat.Hitbox)
local Hurtbox = require(Shared.Combat.Hurtbox)
local Attack = require(Shared.Combat.Attack)
local AttackInstance = require(Shared.Combat.AttackInstance)
local AttackCatalog = require(Shared.Combat.AttackCatalog)
local TopologyCatalog = require(Shared.Combat.CollisionTopologyCatalog)
local MotionRequest = require(Shared.Combat.MotionRequest)

local world = World.new()
local simulation = Simulation.new(world)
local collision = CollisionWorld.new(world)
local schema = CombatStateSchema.new()

local attacker, target = world:CreateEntity(), world:CreateEntity()
local attackCatalog = AttackCatalog.new()
local definition = Attack.new({ Id = "schema-collision.attack", Damage = 7, Hitstun = 8 })
attackCatalog:Register(definition, 1)
attackCatalog:Seal()
collision:SetAttackCatalog(attackCatalog)

local topology = TopologyCatalog.new()
topology:Register("schema-collision.hitbox", 1, function(saved, owner)
	return Hitbox.new({ Id = saved.Id, Owner = owner, Shape = saved.Shape,
		Size = Vector3.new(2, 2, 2), Position = Vector3.new(0, 0, 0), Enabled = saved.Enabled,
		TopologyDefinitionId = "schema-collision.hitbox", TopologyDefinitionVersion = 1 })
end)
topology:Register("schema-collision.hurtbox", 1, function(saved, owner)
	return Hurtbox.new({ Id = saved.Id, Owner = owner, Shape = saved.Shape,
		Size = Vector3.new(2, 2, 2), Position = Vector3.new(0, 0, 0), Enabled = saved.Enabled,
		TopologyDefinitionId = "schema-collision.hurtbox", TopologyDefinitionVersion = 1 })
end)
topology:Seal()
collision:SetTopologyCatalog(topology)

local hitbox = Hitbox.new({ Id = 8101, Owner = attacker, Shape = "Box", Size = Vector3.new(2, 2, 2),
	TopologyDefinitionId = "schema-collision.hitbox", TopologyDefinitionVersion = 1 })
local hurtbox = Hurtbox.new({ Id = 8102, Owner = target, Shape = "Box", Size = Vector3.new(2, 2, 2),
	TopologyDefinitionId = "schema-collision.hurtbox", TopologyDefinitionVersion = 1 })
collision:RegisterHitbox(hitbox)
collision:RegisterHurtbox(hurtbox)
local attackInstance = AttackInstance.new(definition, attacker, world.IdGenerator)
attackInstance:Activate()
attackInstance:AddHitbox(hitbox)

local snapshot = schema:Capture(world)
assert(schema:Validate(snapshot, world), "Schema must validate integrated collision snapshot")

collision.MotionResolver:QueueRequest(MotionRequest.new({
	Target = target,
	Type = "Knockback",
	Direction = Vector3.new(1, 0, 0),
	Magnitude = 4,
}))
local pendingMotionCapture, pendingMotionError = pcall(schema.Capture, schema, world)
assert(not pendingMotionCapture
	and string.find(tostring(pendingMotionError), "standalone MotionResolver requests are pending", 1, true),
	"Snapshot must reject an untracked standalone motion queue")
collision.MotionResolver:Clear()

collision:RemoveHitbox(hitbox)
collision:RemoveHurtbox(hurtbox)
world:DestroyEntity(attacker)
world:DestroyEntity(target)
assert(next(collision.Hitboxes) == nil and next(collision.Hurtboxes) == nil, "Mutation should remove live topology")
assert(#world:GetEntities() == 0, "Mutation should remove live entities")

local restored, restoreError = schema:Restore(world, snapshot)
assert(restored, "Coordinated schema/collision restore failed: " .. tostring(restoreError))
assert(#world:GetEntities() == 2, "Entity roster was not restored")
local restoredAttacker = world:GetEntity(attacker.Id)
local restoredTarget = world:GetEntity(target.Id)
assert(restoredAttacker and restoredTarget, "Owner entities were not reconstructed")
local restoredHitbox = collision.Hitboxes[8101]
local restoredHurtbox = collision.Hurtboxes[8102]
assert(restoredHitbox and restoredHurtbox, "Collision topology was not reconstructed")
assert(restoredHitbox.Owner == restoredAttacker and restoredHurtbox.Owner == restoredTarget,
	"Restored collision regions must reference the restored entity instances")
assert(restoredHitbox.AttackInstance and restoredHitbox.AttackInstance.Id == attackInstance.Id,
	"Active AttackInstance was not reconstructed with its stable ID")
assert(collision.Frame == simulation.Frame and collision.Frame == world.CurrentFrame,
	"World, Simulation, and CollisionWorld frames must be aligned after restore")

world:Destroy()
print("CombatStateSchemaCollisionIntegrationTest: PASS")

end
