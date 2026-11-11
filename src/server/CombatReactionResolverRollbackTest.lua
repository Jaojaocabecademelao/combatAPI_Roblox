return function()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatReactionResolver = require(Shared.Combat.CombatReactionResolver)

local function check(value, message) assert(value, message) end

local resolver = CombatReactionResolver.new(nil)
local snapshot = resolver:CaptureRollbackState()
check(resolver:ValidateRollbackState(snapshot) == true, "Fresh reaction resolver snapshot must validate")
local commit, detail = resolver:PrepareRollbackRestore(snapshot, nil, nil, "Target")
check(type(commit) == "function", "Target restore should prepare: " .. tostring(detail))
commit()
local compensation, compensationError = resolver:PrepareRollbackRestore(snapshot, nil, nil, "Compensation")
check(type(compensation) == "function", "Compensation should prepare: " .. tostring(compensationError))
compensation()
check(resolver:ValidateRollbackState({ Version = 2 }) == false, "Unsupported versions must be rejected")
check(resolver:ValidateRollbackState({ Version = 1, Results = {} }) == false, "Unknown fields must be rejected")
print("CombatReactionResolverRollbackTest: PASS")

end
