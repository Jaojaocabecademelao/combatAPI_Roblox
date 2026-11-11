local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Core.World)
local Simulation = require(Shared.Simulation.Simulation)

local assertions = 0
local function check(value, message)
	assert(value, message or ("Effect gate assertion " .. tostring(assertions + 1) .. " failed"))
	assertions += 1
end

local world = World.new()
Simulation.new(world)
local gate = world:GetExternalEffectGate()
local emitted = 0
local accepted, result = gate:Emit("hit:1", function() emitted += 1 end)
check(accepted and result.Emitted and emitted == 1, "First external effect is emitted")
accepted, result = gate:Emit("hit:1", function() emitted += 1 end)
check(accepted and result.Duplicate and emitted == 1, "Duplicate external effect is suppressed")
world:SetExecutionContext("Replay")
accepted, result = gate:Emit("hit:2", function() emitted += 1 end)
check(accepted and result.Suppressed and emitted == 1, "Replay external effect is suppressed")
check(#gate:GetSuppressedEffects() == 1
	and gate:GetSuppressedEffects()[1].EffectId == "hit:2",
	"Suppressed effects remain available for presentation reconciliation")
world:SetExecutionContext("Normal")
world:Destroy()
print(("CombatExternalEffectGateTest: PASS (%d assertions)"):format(assertions))
