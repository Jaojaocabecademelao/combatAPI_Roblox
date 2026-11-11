-- Verifies that absent collision regions and attack instances can be reconstructed from versioned factories.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local World = require(Shared.Core.World)
local CollisionWorld = require(Shared.Combat.CollisionWorld)
local Hitbox = require(Shared.Combat.Hitbox)
local Hurtbox = require(Shared.Combat.Hurtbox)
local Attack = require(Shared.Combat.Attack)
local AttackInstance = require(Shared.Combat.AttackInstance)
local AttackCatalog = require(Shared.Combat.AttackCatalog)
local TopologyCatalog = require(Shared.Combat.CollisionTopologyCatalog)

local world = World.new()
local collision = CollisionWorld.new(world)
local attacker, target = world:CreateEntity(), world:CreateEntity()
local attackCatalog = AttackCatalog.new()
local definition = Attack.new({ Id = "topology-test.attack", Damage = 4, Hitstun = 6 })
attackCatalog:Register(definition, 1)
attackCatalog:Seal()
collision:SetAttackCatalog(attackCatalog)

local topology = TopologyCatalog.new()
topology:Register("test.hitbox", 1, function(saved, owner)
 return Hitbox.new({ Id = saved.Id, Owner = owner, Shape = saved.Shape, Size = Vector3.new(2,2,2),
  Position = Vector3.new(0,0,0), Enabled = saved.Enabled, TopologyDefinitionId = "test.hitbox", TopologyDefinitionVersion = 1 })
end)
topology:Register("test.hurtbox", 1, function(saved, owner)
 return Hurtbox.new({ Id = saved.Id, Owner = owner, Shape = saved.Shape, Size = Vector3.new(2,2,2),
  Position = Vector3.new(0,0,0), Enabled = saved.Enabled, TopologyDefinitionId = "test.hurtbox", TopologyDefinitionVersion = 1 })
end)
topology:Seal()
collision:SetTopologyCatalog(topology)

local hitbox = Hitbox.new({ Id = 5001, Owner = attacker, Shape = "Box", Size = Vector3.new(2,2,2),
 TopologyDefinitionId = "test.hitbox", TopologyDefinitionVersion = 1 })
local hurtbox = Hurtbox.new({ Id = 5002, Owner = target, Shape = "Box", Size = Vector3.new(2,2,2),
 TopologyDefinitionId = "test.hurtbox", TopologyDefinitionVersion = 1 })
collision:RegisterHitbox(hitbox); collision:RegisterHurtbox(hurtbox)
local instance = AttackInstance.new(definition, attacker, world.IdGenerator)
instance:Activate(); instance:AddHitbox(hitbox)
collision:Step(1/60, 1, 1/60)
local snapshot = collision:CaptureRollbackState()
assert(snapshot.Hitboxes[1].TopologyDefinitionId == "test.hitbox", "Hitbox topology definition was not captured")

collision:RemoveHitbox(hitbox)
collision:RemoveHurtbox(hurtbox)
instance:Finish()
local commit, reason = collision:PrepareTopologyRebuild(snapshot)
assert(type(commit) == "function", "Topology rebuild preparation failed: " .. tostring(reason))
assert(next(collision.Hitboxes) == nil and next(collision.Hurtboxes) == nil, "Preparation mutated live topology")
commit()
assert(collision.Hitboxes[5001] and collision.Hurtboxes[5002], "Missing regions were not reconstructed")
local restored = collision.Hitboxes[5001].AttackInstance
assert(restored and restored.Id == snapshot.AttackInstances[1].Id and restored.State == "Active", "AttackInstance was not reconstructed")
assert(collision.Hitboxes[5001] ~= hitbox and collision.Hurtboxes[5002] ~= hurtbox, "Reconstruction should create fresh region objects")
assert(collision.Frame == snapshot.Frame and #collision:GetResults() == 0, "Frame/output buffers were not restored safely")

local bad = table.clone(snapshot)
bad.Hitboxes = table.clone(snapshot.Hitboxes)
bad.Hitboxes[1] = table.clone(snapshot.Hitboxes[1])
bad.Hitboxes[1].TopologyDefinitionVersion = 99
local badCommit = collision:PrepareTopologyRebuild(bad)
assert(badCommit == nil, "Mismatched topology version must be rejected")
world:Destroy()
print("CombatTopologyRebuildRollbackTest: PASS")
