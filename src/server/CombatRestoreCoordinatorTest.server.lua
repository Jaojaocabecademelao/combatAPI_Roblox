-- Exercises prepare-before-commit, validation rejection, and reverse compensation.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Coordinator = require(Shared.Combat.CombatRestoreCoordinator)

local function participant(initialValue)
	local item = { Value = initialValue }
	function item:CaptureRollbackState() return { Value = self.Value } end
	function item:ValidateRollbackState(state)
		return type(state) == "table" and type(state.Value) == "number", "Value must be numeric"
	end
	function item:PrepareRollbackRestore(state)
		if type(state.Value) ~= "number" then return nil, "invalid value" end
		return function() self.Value = state.Value end
	end
	return item
end

local first, second = participant(10), participant(20)
local coordinator = Coordinator.new()
coordinator:Register("first", first, 1)
coordinator:Register("second", second, 2)
local snapshot = coordinator:Capture()
first.Value, second.Value = 100, 200
local transaction, prepareError = coordinator:Prepare(snapshot)
assert(transaction, "Preparation should succeed: " .. tostring(prepareError))
assert(first.Value == 100 and second.Value == 200, "Prepare must not mutate live state")
local committed, commitError = transaction:Commit()
assert(committed, "Commit should succeed: " .. tostring(commitError))
assert(first.Value == 10 and second.Value == 20, "Commit did not restore all participant states")
assert(not transaction:Commit(), "Transaction must be single-use")

local malformed = {
	Version = Coordinator.Version,
	Participants = { first = { Value = "invalid" }, second = { Value = 20 } },
}
first.Value, second.Value = 30, 40
local rejected, validationError = coordinator:Prepare(malformed)
assert(rejected == nil and validationError, "Invalid snapshot should be rejected")
assert(first.Value == 30 and second.Value == 40, "Rejected snapshot mutated live state")

local rollbackFirst, rollbackSecond = participant(1), participant(2)
local failing = Coordinator.new()
failing:Register("a", rollbackFirst, 1)
local broken = participant(2)
function broken:PrepareRollbackRestore(state)
	if state.Value == 99 then
		return function() self.Value = 99; error("injected commit failure") end
	end
	return function() self.Value = state.Value end
end
failing:Register("b", broken, 2)
local failureSnapshot = { Version = Coordinator.Version, Participants = { a = { Value = 10 }, b = { Value = 99 } } }
local failureTransaction, failurePrepareError = failing:Prepare(failureSnapshot)
assert(failureTransaction, "Failure transaction should prepare: " .. tostring(failurePrepareError))
local failureCommitted, failureMessage = failureTransaction:Commit()
assert(not failureCommitted and string.find(failureMessage, "compensated", 1, true), "Commit failure should report compensation")
assert(rollbackFirst.Value == 1 and broken.Value == 2, "Compensation did not restore pre-commit values")

print("CombatRestoreCoordinatorTest: PASS")
