local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Attack = require(Shared.Combat.Attack)
local AttackInstance = require(Shared.Combat.AttackInstance)
local World = require(Shared.Core.World)

local assertions = 0
local function check(value, message)
	assert(value, message or ("CustomData assertion " .. tostring(assertions + 1) .. " failed"))
	assertions += 1
end

local function rejects(data)
	return not pcall(function()
		Attack.new({ CustomData = data })
	end)
end

local original = {
	Radius = 2,
	Mode = "Arc",
	Nested = { Enabled = true, Width = 4 },
}
local attack = Attack.new({ Id = "custom-data-test", CustomData = original })
original.Radius = 100
original.Nested.Width = 100
check(attack.CustomData.Radius == 2 and attack.CustomData.Nested.Width == 4,
	"Definition data must be defensively copied")
check(attack.CustomData == attack.OffensiveProperties.CustomData,
	"Attack must mirror OffensiveProperties.CustomData")
check(table.isfrozen(attack.CustomData) and table.isfrozen(attack.CustomData.Nested),
	"CustomData must be recursively frozen")
check(Attack.new({ CustomData = nil }).CustomData == nil
	and Attack.new({ CustomData = {} }).CustomData == nil,
	"Nil and empty data must normalize to nil")

check(rejects("not a table"), "Strings must not be accepted as CustomData")
check(rejects(setmetatable({ Value = 1 }, {})), "Metatables must be rejected")
check(rejects({ Callback = function() end }), "Functions must be rejected")
local cyclic = {}; cyclic.Self = cyclic
check(rejects(cyclic), "Cycles must be rejected")
check(rejects({ Value = 0 / 0 }), "NaN must be rejected")
check(rejects({ Value = math.huge }), "Infinity must be rejected")
check(rejects({ [true] = "invalid key" }), "Boolean keys must be rejected")
local tooDeep = { A = { B = { C = { D = { E = { F = { G = { H = { I = 1 } } } } } } } } }
check(rejects(tooDeep), "Depth above eight must be rejected")
local tooMany = {}
for index = 1, 257 do tooMany["K" .. tostring(index)] = index end
check(rejects(tooMany), "More than 256 entries must be rejected")

local world = World.new()
local owner = world:CreateEntity()
local noOverride = AttackInstance.new(attack, owner)
check(noOverride.OffensiveProperties == attack.OffensiveProperties,
	"No override must reuse the definition's frozen properties")
local overrideInput = { Radius = 5, Nested = { Enabled = false } }
local overridden = AttackInstance.new(attack, owner, nil, {
	CustomDataOverrides = overrideInput,
})
overrideInput.Radius = 999
check(overridden.OffensiveProperties.CustomData.Radius == 5
	and overridden.OffensiveProperties.CustomData.Mode == "Arc",
	"Override must replace selected keys and inherit the remaining base keys")
check(overridden.OffensiveProperties.CustomData.Nested.Enabled == false
	and overridden.OffensiveProperties.CustomData.Nested.Width == nil,
	"Merge must be shallow, replacing nested tables as a whole")
check(table.isfrozen(overridden.CustomDataOverrides)
	and table.isfrozen(overridden.OffensiveProperties.CustomData),
	"Override and effective data must be frozen")
check(attack.CustomData.Radius == 2,
	"Creating an override must not mutate the Attack definition")

local explicitId = AttackInstance.new(attack, owner, nil, 12345)
check(explicitId.Id == 12345, "Legacy scalar fourth argument must remain the explicit ID")
local generatedId = AttackInstance.new(attack, owner)
check(type(generatedId.Id) == "number" and generatedId.Id ~= explicitId.Id,
	"Legacy three-argument construction must remain supported")

local invalidOverride = pcall(function()
	AttackInstance.new(attack, owner, nil, { CustomDataOverrides = { Bad = function() end } })
end)
check(not invalidOverride, "Invalid instance overrides must be rejected")

world:Destroy()
print("CombatAttackCustomDataTest: PASS (" .. tostring(assertions) .. " assertions)")
