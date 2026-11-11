local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Core.World)
local NetworkSnapshot = require(Shared.Combat.NetworkSnapshot)
local ReconciliationResult = require(Shared.Combat.ReconciliationResult)
local Input = require(Shared.Combat.Input)
local InputState = require(Shared.Combat.InputState)

local assertions = 0
local function check(value, message)
	assert(value, message)
	assertions += 1
end

local applied = 0
local world = World.new({
	Reconciliation = {
		ApplySnapshot = function(snapshot, divergences)
			check(snapshot.SimulationFrame == 2 and #divergences > 0,
				"Adapter receives the authoritative divergence")
			applied += 1
			return true
		end,
	},
})
local entity = world:CreateEntity()
local prediction = world:GetPredictionResolver()
check(prediction:Enable(entity).Accepted, "Prediction enables for reconciliation")
check(prediction:Begin(entity, 1).Accepted, "Prediction begins")
check(prediction:Advance(entity, 2, nil).Accepted, "Prediction advances")

local snapshot = NetworkSnapshot.new({
	SimulationFrame = 2,
	Sequence = 7,
	Components = {
		Prediction = {
			[entity.Id] = {
				Frame = 2,
				Inputs = { [Input.Light] = InputState.Pressed },
			},
		},
	},
})
local resolver = world:GetReconciliationResolver()
local appliedResult = resolver:Reconcile(snapshot)
check(appliedResult.Type == ReconciliationResult.Type.Applied and applied == 1,
	"Divergent authoritative snapshot is applied through the adapter")
local duplicate = resolver:Reconcile(snapshot)
check(duplicate.Type == ReconciliationResult.Type.Duplicate,
	"Authoritative snapshots are deduplicated by sequence")

local matchedWorld = World.new()
local matchedEntity = matchedWorld:CreateEntity()
local matchedPrediction = matchedWorld:GetPredictionResolver()
check(matchedPrediction:Enable(matchedEntity).Accepted, "Matching prediction enables")
check(matchedPrediction:Begin(matchedEntity, 3).Accepted, "Matching prediction begins")
local matched = matchedWorld:GetReconciliationResolver():Reconcile(NetworkSnapshot.new({
	SimulationFrame = 3,
	Sequence = 1,
	Components = { Prediction = {
		[matchedEntity.Id] = { Frame = 3, Inputs = {} },
	} },
}))
check(matched.Type == ReconciliationResult.Type.Matched,
	"Matching authoritative snapshot does not invoke an adapter")

local retryCount = 0
local retryWorld = World.new({
	Reconciliation = {
		ApplySnapshot = function()
			retryCount += 1
			return retryCount > 1
		end,
	},
})
local retryEntity = retryWorld:CreateEntity()
local retryPrediction = retryWorld:GetPredictionResolver()
check(retryPrediction:Enable(retryEntity).Accepted, "Retry prediction enables")
check(retryPrediction:Begin(retryEntity, 4).Accepted, "Retry prediction begins")
local retrySnapshot = NetworkSnapshot.new({
	SimulationFrame = 4,
	Sequence = 1,
	Components = { Prediction = {
		[retryEntity.Id] = { Frame = 4, Inputs = { [Input.Light] = InputState.Pressed } },
	} },
})
local failedApply = retryWorld:GetReconciliationResolver():Reconcile(retrySnapshot)
check(failedApply.Type == ReconciliationResult.Type.AdapterFailed,
	"Failed application is reported explicitly")
local retriedApply = retryWorld:GetReconciliationResolver():Reconcile(retrySnapshot)
check(retriedApply.Type == ReconciliationResult.Type.Applied,
	"Failed snapshots remain available for retry")

world:Destroy()
matchedWorld:Destroy()
retryWorld:Destroy()
print(("CombatReconciliationTest: PASS (%d assertions)"):format(assertions))
