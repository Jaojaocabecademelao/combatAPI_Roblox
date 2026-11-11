return function()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Combat = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Combat")

local HealthComponent = require(Combat.HealthComponent)
local DefenseComponent = require(Combat.DefenseComponent)
local GuardComponent = require(Combat.GuardComponent)
local JuggleComponent = require(Combat.JuggleComponent)
local CancelComponent = require(Combat.CancelComponent)
local CancelProfile = require(Combat.CancelProfile)
local CancelRule = require(Combat.CancelRule)
local AirState = require(Combat.AirState)
local CombatEntity = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Core"):WaitForChild("CombatEntity"))
local ArmorComponent = require(Combat.ArmorComponent)
local ArmorProfile = require(Combat.ArmorProfile)
local ArmorCatalog = require(Combat.ArmorCatalog)
local ProtectionComponent = require(Combat.ProtectionComponent)

local function check(value, message)
	assert(value, message)
end

-- Health: current and maximum health are mutable gameplay state.
local health = HealthComponent.new({ MaxHealth = 150, CurrentHealth = 93 })
local healthState = health:CaptureRollbackState()
health._maxHealth, health._currentHealth = 80, 12
check(health:RestoreRollbackState(healthState), "Health restore failed")
check(health:GetMaxHealth() == 150 and health:GetHealth() == 93, "Health round-trip mismatch")
local invalidHealth = { Version = 1, MaxHealth = 50, CurrentHealth = 51 }
check(health:ValidateRollbackState(invalidHealth) == false, "Invalid health state was accepted")

-- Defense: block state and parry window are frame-sensitive.
local defense = DefenseComponent.new()
defense.Blocking = true
defense.ParryStartFrame, defense.ParryEndFrame = 20, 24
local defenseState = defense:CaptureRollbackState()
defense.Blocking = false
defense:CloseParryWindow()
check(defense:RestoreRollbackState(defenseState), "Defense restore failed")
check(defense.Blocking and defense.ParryStartFrame == 20 and defense.ParryEndFrame == 24,
	"Defense round-trip mismatch")
check(defense:ValidateRollbackState({ Version = 1, Blocking = false, ParryStartFrame = 10 }) == false,
	"Incomplete parry window was accepted")

-- Guard: dynamic resource state is restorable only under the same profile/configuration.
local guard = GuardComponent.new()
guard.Guard = 62
guard.GuardBroken = false
guard.GuardBreakRemaining = 0
local guardState = guard:CaptureRollbackState()
guard.Guard = 0
guard.GuardBroken = true
guard.GuardBreakRemaining = 12
check(guard:RestoreRollbackState(guardState), "Guard restore failed")
check(guard.Guard == 62 and not guard.GuardBroken and guard.GuardBreakRemaining == 0,
	"Guard round-trip mismatch")
local mismatchedGuard = table.clone(guardState)
mismatchedGuard.Profile = table.clone(guardState.Profile)
mismatchedGuard.Profile.ChipMultiplier += 1
check(guard:ValidateRollbackState(mismatchedGuard) == false, "Guard profile mismatch was accepted")

-- Juggle: counters and recovery frames influence subsequent hit resolution.
local juggle = JuggleComponent.new()
juggle.Active = true
juggle.AttackerId = 1234
juggle.AirState = AirState.Juggled
juggle.JuggleCount = 3
juggle.ReJuggleCount = 1
juggle.LaunchFrame = 30
juggle.LastJuggleHitFrame = 34
juggle.RecoveryRemaining = 7
local juggleState = juggle:CaptureRollbackState()
juggle:Reset()
check(juggle:RestoreRollbackState(juggleState), "Juggle restore failed")
check(juggle.Active and juggle.AirState == AirState.Juggled and juggle.JuggleCount == 3
	and juggle.ReJuggleCount == 1 and juggle.LaunchFrame == 30
	and juggle.LastJuggleHitFrame == 34 and juggle.RecoveryRemaining == 7,
	"Juggle round-trip mismatch")

-- Cancel: consumed rule IDs are valid only if present in the same profile.
local profile = CancelProfile.new({ Rules = {
	CancelRule.new({ RuleId = "light-to-heavy", FromAction = "light", ToAction = "heavy", StartFrame = 3, EndFrame = 8 }),
} })
local cancel = CancelComponent.new(profile)
cancel:BeginAction("light", 40, 55)
cancel.ConsumedRules["light-to-heavy"] = true
cancel.LastCancelFrame = 44
cancel.CancelCount = 2
local cancelState = cancel:CaptureRollbackState()
cancel:Reset()
check(cancel:RestoreRollbackState(cancelState), "Cancel restore failed")
check(cancel.CurrentAction == "light" and cancel.ActionStartFrame == 40
	and cancel.ActionEndFrame == 55 and cancel.ConsumedRules["light-to-heavy"] == true
	and cancel.LastCancelFrame == 44 and cancel.CancelCount == 2,
	"Cancel round-trip mismatch")
local invalidCancel = table.clone(cancelState)
invalidCancel.ConsumedRules = { ["missing-rule"] = true }
check(cancel:ValidateRollbackState(invalidCancel) == false, "Unknown consumed cancel rule was accepted")


-- Armor: handles refer to versioned profiles and stable source entity IDs.
local armorCatalog = ArmorCatalog.new()
local armorProfile = ArmorProfile.new({
	Id = "rollback-test-armor", Name = "RollbackTestArmor", DurationFrames = 12,
	Priority = 3, Consequences = { Damage = false, Hitstun = true },
})
armorCatalog:Register(armorProfile, 1)
armorCatalog:Seal()
local armorOwner = CombatEntity.new(101)
local armorSource = CombatEntity.new(202)
local armor = ArmorComponent.new(armorCatalog)
armorOwner:AddComponent(armor)
local armorHandle = armor:Grant(armorProfile, nil, armorSource)
local armorState = armor:CaptureRollbackState()
armor:AdvanceStep(armorHandle.CreatedFrame + 5)
check(armor:RestoreRollbackState(armorState, { EntitiesById = { [101] = armorOwner, [202] = armorSource } }),
	"Armor restore failed")
check(#armor.Handles == 1 and armor.Handles[1].RemainingFrames == 12
	and armor.Handles[1].Source == armorSource and armor.Handles[1].Id == armorHandle.Id,
	"Armor handle round-trip mismatch")
local invalidArmor = table.clone(armorState)
invalidArmor.Handles = table.clone(armorState.Handles)
invalidArmor.Handles[1] = table.clone(armorState.Handles[1])
invalidArmor.Handles[1].ProfileVersion = 99
check(armor:ValidateRollbackState(invalidArmor) == false, "Unknown armor profile version was accepted")
check(armor:ValidateRollbackState(armorState, { EntitiesById = { [101] = armorOwner } }) == false,
	"Missing armor source entity was accepted")

-- Protection: categories, temporal fields and source references survive reconstruction.
local protectionOwner = CombatEntity.new(303)
local protectionSource = CombatEntity.new(404)
local protectionComponent = ProtectionComponent.new()
protectionOwner:AddComponent(protectionComponent)
protectionComponent:Grant({
	Kind = "Immunity", Categories = { "Damage", "Hitstun" }, DurationFrames = 9,
	Priority = 4, Source = protectionSource, StartFrame = 15, Frame = 15, CreatedAt = 15,
})
local protectionState = protectionComponent:CaptureRollbackState()
protectionComponent:AdvanceFrame(18)
check(protectionComponent:RestoreRollbackState(protectionState,
	{ EntitiesById = { [303] = protectionOwner, [404] = protectionSource } }), "Protection restore failed")
local restoredProtection = protectionComponent.Protections[1]
check(#protectionComponent.Protections == 1 and restoredProtection.RemainingFrames == 9
	and restoredProtection.Source == protectionSource and restoredProtection:Blocks("Damage")
	and restoredProtection:Blocks("Hitstun"), "Protection round-trip mismatch")
local invalidProtection = table.clone(protectionState)
invalidProtection.Protections = table.clone(protectionState.Protections)
invalidProtection.Protections[1] = table.clone(protectionState.Protections[1])
invalidProtection.Protections[1].Permanent = true
check(protectionComponent:ValidateRollbackState(invalidProtection) == false,
	"Inconsistent permanent protection state was accepted")
check(protectionComponent:ValidateRollbackState(protectionState,
	{ EntitiesById = { [303] = protectionOwner } }) == false, "Missing protection source entity was accepted")

print("CombatGameplayComponentsRollbackTest passed")

end
