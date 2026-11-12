--!strict
-- Compile-time and runtime contract test for the consumer-facing Luau types.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatAPI = require(ReplicatedStorage.Shared.CombatAPI)
local CombatAPITypes = require(ReplicatedStorage.Shared.CombatAPITypes)

local function check(condition: boolean, message: string)
	assert(condition, "CombatAPITypesTest: " .. message)
end

return function()
	local publicAPI: CombatAPITypes.CombatAPI = CombatAPI
	local world: CombatAPITypes.World = publicAPI.CreateWorld()
	local context: CombatAPITypes.APIContext? = publicAPI.GetContext(world)
	assert(context ~= nil, "typed GetContext returns the World-owned APIContext")
	check(context:HasFeature("Events"), "typed APIContext exposes Events")

	local attackOptions: CombatAPITypes.AttackOptions = {
		Id = "types.contract.attack",
		Damage = 10,
		CustomData = { Radius = 3, Element = "Arcane" },
	}
	local attack: CombatAPITypes.Attack = publicAPI.Attack.new(attackOptions)
	local instanceOptions: CombatAPITypes.AttackInstanceOptions = {
		Id = "types.contract.instance",
		CustomDataOverrides = { Radius = 5 },
	}
	local instance: CombatAPITypes.AttackInstance = publicAPI.AttackInstance.new(
		attack,
		nil,
		nil,
		instanceOptions
	)

	local effectiveData = instance.OffensiveProperties.CustomData
	assert(effectiveData ~= nil, "typed instance retains effective CustomData")
	check(effectiveData.Radius == 5, "typed override replaces the base value")
	check(effectiveData.Element == "Arcane", "typed override inherits the base value")

	world:Destroy()
	print("[CombatAPITypesTest] PASS")
end
