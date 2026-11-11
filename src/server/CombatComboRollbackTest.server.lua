local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core, Combat = Shared:WaitForChild("Core"), Shared:WaitForChild("Combat")
local World = require(Core.World)
local CombatEntity = require(Core.CombatEntity)
local ComboComponent = require(Combat.ComboComponent)
local ComboResolver = require(Combat.ComboResolver)
local HitEvent = require(Combat.HitEvent)

local function check(value, message)
	assert(value, message)
end

local world = World.new()
local attacker, defender = world:CreateEntity(), world:CreateEntity()
local attackerCombo = attacker:AddComponent(ComboComponent.new())
defender:AddComponent(ComboComponent.new())
local resolver = world:GetComboResolver()
local hit = HitEvent.new({
	AttackInstanceId = 9001,
	Attacker = attacker, Target = defender,
	AttackerEntityId = attacker.Id, TargetEntityId = defender.Id,
	HitboxId = 31, HurtboxId = 32, Frame = world.CurrentFrame,
	Damage = 10, Hitstun = 5,
	OffensiveProperties = { Damage = 10, Hitstun = 5 },
})
resolver:Process({ hit }, {}, {}, {}, world.CurrentFrame)
local savedComponent = attackerCombo:CaptureRollbackState()
local savedResolver = resolver:CaptureRollbackState()
check(#savedComponent.Combos == 1, "ComboComponent must capture the active combo")
check(#savedResolver.Active == 1, "ComboResolver must capture its active map")

resolver:Break(attacker, defender, "RollbackTest", world.CurrentFrame + 1)
check(#resolver:GetActiveCombos() == 0, "Mutation must end the live combo")

-- Stage a new entity roster as CombatStateSchema does; combo references must point at it.
local stagedAttacker, stagedDefender = CombatEntity.new(attacker.Id), CombatEntity.new(defender.Id)
local stagedById = { [attacker.Id] = stagedAttacker, [defender.Id] = stagedDefender }
local stagedComponent = stagedAttacker:AddComponent(ComboComponent.new())
stagedDefender:AddComponent(ComboComponent.new())
local restored, restoreError = stagedComponent:RestoreRollbackState(savedComponent, { EntitiesById = stagedById })
check(restored == true, "Staged ComboComponent restore failed: " .. tostring(restoreError))

local context = { TargetEntitiesById = stagedById, CurrentEntitiesById = { [attacker.Id] = attacker, [defender.Id] = defender } }
local commit, prepareError = resolver:PrepareRollbackRestore(savedResolver, world, context, "Target")
check(type(commit) == "function", "ComboResolver prepare failed: " .. tostring(prepareError))
commit()
local active = resolver:GetActiveCombos()
check(#active == 1, "Resolver must rebuild the active map")
check(active[1].Attacker == stagedAttacker and active[1].Defender == stagedDefender,
	"Restored combo references must target staged entities")
check(active[1].HitCount == 1 and active[1].HitRecords[1].AttackInstanceId == 9001,
	"Combo counters and hit history must survive restoration")
check(#resolver:GetEvents() == savedResolver.EventCount,
	"Restoration must discard events produced after the captured state")

local invalid = table.clone(savedComponent)
invalid.Combos = table.clone(savedComponent.Combos)
invalid.Combos[1] = table.clone(savedComponent.Combos[1])
invalid.Combos[1].HitCount += 1
check(stagedComponent:ValidateRollbackState(invalid, { EntitiesById = stagedById }) == false,
	"Inconsistent combo counters must be rejected")

world:Destroy()
print("CombatComboRollbackTest passed")
