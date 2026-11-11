-- Phase 3: HitHistory state must survive capture/restore without serializing object references.
local HitHistory = require(game:GetService("ReplicatedStorage").Shared.Combat.HitHistory)
local HitPolicy = require(game:GetService("ReplicatedStorage").Shared.Combat.HitPolicy)

local history = HitHistory.new()
local attacker = { Id = 10 }
local target = { Id = 20 }
local attackInstance = { Id = 100, OwnerEntity = attacker, State = "Active" }
local hitbox = { Id = 200 }
local hurtbox = { Id = 300 }
history:Record(attackInstance, target, hitbox, hurtbox, HitPolicy.Scope.AttackInstance, 7)

local snapshot = history:CaptureRollbackState()
assert(snapshot.Version == 1 and #snapshot.Entries == 1, "HitHistory capture failed")
assert(snapshot.Entries[1].AttackInstanceId == 100, "AttackInstance stable ID was not captured")
assert(snapshot.Entries[1].TargetEntityId == 20, "Target stable ID was not captured")

local context = {
	RequireReferences = true,
	AttackInstancesById = { [100] = attackInstance },
	EntitiesById = { [10] = attacker, [20] = target },
	HitboxesById = { [200] = hitbox },
	HurtboxesById = { [300] = hurtbox },
}
local valid, reason = history:ValidateRollbackState(snapshot, context)
assert(valid, "Valid HitHistory snapshot rejected: " .. tostring(reason))

history:Record(attackInstance, { Id = 21 }, hitbox, hurtbox, HitPolicy.Scope.AttackInstance, 8)
local commit, prepareError = history:PrepareRollbackRestore(snapshot, context)
assert(type(commit) == "function", "HitHistory restore preparation failed: " .. tostring(prepareError))
commit()
assert(history:CanRecord(attackInstance, target, hitbox, HitPolicy.Scope.AttackInstance, HitPolicy.Once, 8) == false,
	"Restored Once-policy history should prevent a duplicate hit")
assert(history:CanRecord(attackInstance, { Id = 21 }, hitbox, HitPolicy.Scope.AttackInstance, HitPolicy.Once, 8) == true,
	"Post-snapshot target should not remain in restored history")

local invalid = { Version = 1, Entries = { {
	AttackInstanceId = 999, ScopeType = "AttackInstance", TargetIsNil = false,
	TargetEntityId = 20, Frame = 7,
} } }
local invalidOk = history:ValidateRollbackState(invalid, context)
assert(not invalidOk, "Missing AttackInstance reference should reject the snapshot")

print("CombatHitHistoryRollbackTest: PASS")
