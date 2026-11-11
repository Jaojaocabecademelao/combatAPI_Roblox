return function()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local Combat = Shared:WaitForChild("Combat")

local World = require(Core.World)
local EntityState = require(Core.EntityState)
local HealthComponent = require(Combat.HealthComponent)
local StatusContainer = require(Combat.StatusContainer)
local GuardComponent = require(Combat.GuardComponent)
local GuardProfile = require(Combat.GuardProfile)
local GuardResult = require(Combat.GuardResult)
local DamageResolver = require(Combat.DamageResolver)

local function check(condition, message)
	assert(condition, message or "Guard assertion failed")
end

local world = World.new()
world.DamageResolver = DamageResolver.new(world)

local attacker = world:CreateEntity()
local defender = world:CreateEntity()
local health = defender:AddComponent(HealthComponent.new({ MaxHealth = 100 }))
local statusContainer = defender:AddComponent(StatusContainer.new())
local profile = GuardProfile.new({
	MaxGuard = 50,
	ChipMultiplier = 0.5,
	DefaultGuardDamage = 30,
	GuardDamageMultiplier = 1,
	BlockstunMultiplier = 1,
	GuardBreakFrames = 4,
})
local guard = defender:AddComponent(GuardComponent.new({
	Profile = profile,
	Guard = 50,
}))
check(guard:GetGuard() == 50, "Guard starts at max value")
check(guard:GetMaxGuard() == 50, "Guard profile retains max value")

local hitEvent = {
	Frame = 1,
	Time = 0,
	Target = defender,
	Attacker = attacker,
	AttackInstance = { Id = "attack-1" },
	AttackInstanceId = "attack-1",
	Damage = 20,
	OffensiveProperties = {
		Damage = 20,
		GuardDamage = 35,
		Blockstun = 5,
		Hitstun = 6,
	},
}

local defenseEvent = {
	Result = "Blocked",
	Frame = 1,
	Time = 0,
	Target = defender,
	Defender = defender,
	Attacker = attacker,
	HitEvent = hitEvent,
	AttackInstance = hitEvent.AttackInstance,
	AttackInstanceId = hitEvent.AttackInstanceId,
}

local resolved = world:GetGuardResolver():Process({ defenseEvent }, 1, 0)
check(#resolved == 1, "Blocked hit produces one guard result")
check(resolved[1].Result == GuardResult.Blocked, "Blocked guard uses the contract result type")
check(resolved[1].GuardDamage == 35, "Guard damage is preserved in the result payload")
check(resolved[1].ChipDamage >= 0, "Chip damage stays non-negative")
check(resolved[1].RemainingGuard <= 50, "Remaining guard is clamped to the configured meter")
check(statusContainer:HasStatus("Blockstun") == true, "Blocked attacks apply Blockstun when the hit includes a blockstun window")

local guardAgain = defender:GetComponent(GuardComponent)
check(guardAgain:GetGuard() == 15, "Guard meter drains after a blocked hit")
check(guardAgain:IsGuardBroken() == false, "Guard remains intact while the meter still has remaining value")

local secondDefenseEvent = {
	Result = "Blocked",
	Frame = 2,
	Time = 0,
	Target = defender,
	Defender = defender,
	Attacker = attacker,
	HitEvent = {
		Frame = 2,
		Time = 0,
		Target = defender,
		Attacker = attacker,
		AttackInstance = { Id = "attack-2" },
		AttackInstanceId = "attack-2",
		Damage = 25,
		OffensiveProperties = {
			Damage = 25,
			GuardDamage = 40,
			Blockstun = 4,
		},
	},
	AttackInstance = { Id = "attack-2" },
	AttackInstanceId = "attack-2",
}

local breakResolved = world:GetGuardResolver():Process({ secondDefenseEvent }, 2, 0)
check(#breakResolved == 1, "Guard break still yields a single deterministic result")
check(breakResolved[1].GuardBroken == true and breakResolved[1].RemainingGuard == 0,
	"Guard break reports a broken state and zero remaining guard")
check(guardAgain:GetGuard() == 0 and guardAgain:IsGuardBroken(),
	"Guard break drains the guard meter and marks the guard as broken")
check(guardAgain.GuardBreakRemaining > 0, "Guard break records a remaining break window")

print("Guard tests passed")

end
