return function()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CounterResolver = require(Shared.Combat.CounterResolver)

local function check(value, message)
    assert(value, message)
end

local resolver = CounterResolver.new()
local oldResult = { Type = "old-result" }
resolver.Results = { oldResult }
local snapshot = resolver:CaptureRollbackState()
check(resolver:ValidateRollbackState(snapshot), "Fresh counter resolver snapshot must validate")

local prepareTarget, targetError = resolver:PrepareRollbackRestore(snapshot, nil, nil, "Target")
check(type(prepareTarget) == "function", "Target restore should prepare")
resolver.Results = { { Type = "future-result" } }
prepareTarget()
check(#resolver.Results == 0, "Target restore must clear frame-local counter outputs")

resolver.Results = { oldResult }
local prepareCompensation, compensationError = resolver:PrepareRollbackRestore(snapshot, nil, nil, "Compensation")
check(type(prepareCompensation) == "function", "Compensation should prepare")
resolver.Results = { { Type = "intermediate-result" } }
prepareCompensation()
check(#resolver.Results == 1 and resolver.Results[1] == oldResult,
    "Compensation must preserve the exact prior result object")

local malformed = { Version = 1, Results = {} }
local valid = resolver:ValidateRollbackState(malformed)
check(valid == false, "Unknown snapshot fields must be rejected")
local wrongVersion = resolver:ValidateRollbackState({ Version = 2 })
check(wrongVersion == false, "Unsupported versions must be rejected")

print("CombatCounterRollbackIntegrationTest: PASS")

end
