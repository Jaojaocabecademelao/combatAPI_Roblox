return function()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core, Combat = Shared:WaitForChild("Core"), Shared:WaitForChild("Combat")
local SimulationFolder = Shared:WaitForChild("Simulation")

local Component = require(Core.Component)
local World = require(Core.World)
local Simulation = require(SimulationFolder.Simulation)
local RollbackProfile = require(Combat.RollbackProfile)
local RollbackResult = require(Combat.RollbackResult)
local RollbackState = require(Combat.RollbackState)
local RollbackEvent = require(Combat.RollbackEvent)
local RollbackSnapshot = require(Combat.RollbackSnapshot)
local RollbackHistory = require(Combat.RollbackHistory)
local RollbackComponent = require(Combat.RollbackComponent)
local InputComponent = require(Combat.InputComponent)
local Input = require(Combat.Input)
local InputState = require(Combat.InputState)
local PredictionProfile = require(Combat.PredictionProfile)
local PredictionState = require(Combat.PredictionState)

local assertions = 0
local function check(value, message)
	assert(value, message or ("Rollback assertion " .. tostring(assertions + 1) .. " failed"))
	assertions += 1
end

local Counter = {}
Counter.__index = Counter
Counter.RollbackKey = "Tests.Counter"
setmetatable(Counter, { __index = Component })

local failReplay = false
local nestedResult = nil
local externalSideEffects = 0

function Counter.new(value)
	local self = setmetatable(Component.new(), Counter)
	self.Value = value or 0
	self.Steps = 0
	self.Marker = "initial"
	self.LastRandom = 0
	return self
end

function Counter:CaptureRollbackState()
	return {
		Value = self.Value,
		Steps = self.Steps,
		Marker = self.Marker,
		LastRandom = self.LastRandom,
	}
end

function Counter:RestoreRollbackState(state)
	self.Value = state.Value
	self.Steps = state.Steps
	self.Marker = state.Marker
	self.LastRandom = state.LastRandom
	return true
end

local function makeCounterFromState(_, state)
	local component = Counter.new(state.Value)
	component.Steps = state.Steps
	component.Marker = state.Marker
	component.LastRandom = state.LastRandom
	return component
end

function Counter:Step()
	local world = self.Entity.World
	if failReplay and world:GetExecutionContext() == "Replay" then
		error("intentional rollback replay failure")
	end
	if world:GetExecutionContext() == "Replay" and nestedResult == nil then
		nestedResult = world:GetRollbackResolver():RequestRollback(world, 0, 0)
	end
	local randomValue = world:GetSimulation():GetRNG():NextInteger(1, 9)
	local inputState = world:GetInputResolver():GetInput(self.Entity, Input.Light)
	self.Value += randomValue + (inputState == InputState.Pressed and 100 or 0)
	self.LastRandom = randomValue
	self.Steps += 1
	self.Marker = "frame-" .. tostring(world.CurrentFrame + 1)
	if world:GetExecutionContext() == "Normal" then
		externalSideEffects += 1
	end
end

-- Plain, deterministic snapshot data is copied by value and rejects Instances/functions/cycles.
local validSnapshot = RollbackSnapshot.new({
	Frame = 12,
	Entities = { { Id = 1, State = "Alive", Components = {} } },
	Simulation = { Frame = 12, RNGState = 42, Accumulator = 0 },
	InputFrames = {},
	Confirmed = true,
})
check(validSnapshot.Frame == 12, "Snapshot preserves frame")
check(validSnapshot.Simulation.RNGState == 42, "Snapshot preserves RNG state")
check(validSnapshot.Confirmed, "Snapshot preserves caller-provided confirmation")
local sourceData = { Nested = { Value = 7 } }
local copied = RollbackSnapshot.CloneSerializable(sourceData)
sourceData.Nested.Value = 8
check(copied.Nested.Value == 7, "Serializable snapshots deep-copy nested values")
check(not pcall(function() RollbackSnapshot.CloneSerializable({ Value = function() end }) end),
	"Snapshots reject functions")
local cyclic = {}
cyclic.Self = cyclic
check(not pcall(function() RollbackSnapshot.CloneSerializable(cyclic) end), "Snapshots reject cycles")
check(not pcall(function() RollbackSnapshot.CloneSerializable({ Value = math.huge }) end),
	"Snapshots reject non-finite numbers")
check(not pcall(function()
	RollbackSnapshot.new({ Frame = -1, Entities = {}, Simulation = {}, InputFrames = {} })
end), "Snapshots reject negative frames")
check(not pcall(function()
	RollbackSnapshot.new({ Frame = 1.5, Entities = {}, Simulation = {}, InputFrames = {} })
end), "Snapshots reject fractional frames")

local defaultProfile = RollbackProfile.new()
check(defaultProfile.Enabled, "Rollback enables by default")
check(defaultProfile.MaxRollbackFrames == 120, "Default rollback distance is bounded")
check(defaultProfile.MaxReplayFrames == 120, "Default replay distance is bounded")
check(defaultProfile.HistorySize == 120, "Default rollback history is bounded")
check(not defaultProfile.AllowSameFrameRollback, "Same-frame rollback is opt-in")
check(defaultProfile.AbortOnMissingInput and defaultProfile.AbortOnMissingSnapshot,
	"Missing rollback data aborts by default")
check(not pcall(function() RollbackProfile.new({ MaxRollbackFrames = -1 }) end),
	"Negative rollback limit is invalid")
check(not pcall(function() RollbackProfile.new({ MaxReplayFrames = 1.5 }) end),
	"Fractional replay limit is invalid")
check(not pcall(function() RollbackProfile.new({ HistorySize = 0 }) end),
	"Empty rollback history is invalid")
check(not pcall(function() RollbackProfile.new({ MaxSnapshotEntries = 0 }) end),
	"Snapshot entry budget must be positive")
check(not pcall(function() RollbackProfile.new({ MaxSnapshotDepth = 0 }) end),
	"Snapshot nesting budget must be positive")
check(not pcall(function() RollbackProfile.new({ RecordReplayFrames = 1 }) end),
	"Replay debug flag must be boolean")
check(not pcall(function() RollbackProfile.new({ Enabled = 1 }) end),
	"Non-boolean enabled option is invalid")
check(RollbackState.Idle == "Idle" and RollbackState.Requested == "Requested"
	and RollbackState.Restoring == "Restoring" and RollbackState.Replaying == "Replaying"
	and RollbackState.Completed == "Completed" and RollbackState.Failed == "Failed",
	"Rollback state enum exposes the lifecycle")
check(RollbackEvent.Type.Requested == "RollbackRequested"
	and RollbackEvent.Type.Completed == "RollbackCompleted",
	"Rollback event enum exposes lifecycle events")

local history = RollbackHistory.new(3)
check(history:Count() == 0, "Rollback history starts empty")
history:Put(3, "frame-3")
history:Put(1, "frame-1")
history:Put(2, "frame-2")
check(history:Count() == 3, "Rollback history stores up to capacity")
check(history:Get(1) == "frame-1" and history:Get(2) == "frame-2"
	and history:Get(3) == "frame-3", "Rollback history retrieves frame-indexed values")
history:Put(2, "replacement")
check(history:Count() == 3 and history:Get(2) == "replacement",
	"Replacing a frame does not consume capacity")
history:Put(4, "frame-4")
check(history:Count() == 3 and history:Get(1) == nil and history:Get(4) == "frame-4",
	"Rollback history evicts oldest frames")
history:Clear()
check(history:Count() == 0 and history:Get(4) == nil, "Rollback history clears")

-- Multi-entity snapshots restore every opt-in component in deterministic entity order.
local snapshotWorld = World.new({ RollbackProfile = {
	HistorySize = 4, AllowSameFrameRollback = true,
}, ComponentFactories = {
	["Tests.Counter"] = function(_, state)
		local component = Counter.new(state.Value)
		component.Steps = state.Steps
		component.Marker = state.Marker
		component.LastRandom = state.LastRandom
		return component
	end,
} })
local snapshotSimulation = Simulation.new(snapshotWorld, { Seed = 817 })
local snapshotEntities = {}
for index = 1, 48 do
	local entity = snapshotWorld:CreateEntity()
	local state = entity:AddComponent(Counter.new(index * 3))
	state.Steps = index
	state.Marker = "saved-" .. tostring(index)
	state.LastRandom = index % 9 + 1
	table.insert(snapshotEntities, { Entity = entity, Component = state, Index = index })
end
local snapshotResolver = snapshotWorld:GetRollbackResolver()
check(snapshotResolver == snapshotWorld:GetRollbackResolver(), "World exposes one stable rollback resolver")
check(snapshotResolver:Enable(snapshotEntities[1].Entity).Accepted, "Rollback can be enabled on a world anchor")
local initialSnapshotResult = snapshotResolver:RecordFrame(snapshotWorld, { Confirmed = true })
check(initialSnapshotResult.Accepted,
	"Initial multi-entity confirmed snapshot records: "
		.. tostring(initialSnapshotResult.Type) .. " "
		.. tostring(initialSnapshotResult.Detail))
local savedRngState = snapshotSimulation:GetRNG():GetState()
for _, item in ipairs(snapshotEntities) do
	item.Component.Value = -item.Index
	item.Component.Steps = 999
	item.Component.Marker = "mutated"
	item.Component.LastRandom = 0
end
snapshotSimulation:GetRNG():NextInteger(1, 50)
check(snapshotResolver:RestoreFrame(snapshotWorld, 0).Accepted, "World snapshot restores")
check(snapshotSimulation:GetRNG():GetState() == savedRngState, "Restore reinstates deterministic RNG state")
check(snapshotSimulation.GameTime:GetFrame() == 0 and snapshotWorld.CurrentFrame == 0,
	"Restore reinstates Simulation and World frame")
for _, item in ipairs(snapshotEntities) do
	local index = item.Index
	local restoredEntity = snapshotWorld:GetEntity(item.Entity.Id)
	local state = restoredEntity and restoredEntity:GetComponent(Counter)
	check(restoredEntity ~= item.Entity, "Restore replaces entity instances " .. index)
	check(state ~= nil, "Restore reattaches entity components " .. index)
	check(state.Value == index * 3, "Restored entity component value " .. index)
	check(state.Steps == index, "Restored entity component step counter " .. index)
	check(state.Marker == "saved-" .. tostring(index), "Restored entity component marker " .. index)
	check(state.LastRandom == index % 9 + 1, "Restored entity component random result " .. index)
	check(restoredEntity.State == "Alive", "Restored entity lifecycle state " .. index)
	if index == 1 then
		check(restoredEntity:GetComponent(RollbackComponent) ~= nil,
			"Restore retains the resolver-owned rollback component")
		check(restoredEntity:GetComponent(RollbackComponent).Resolver == snapshotResolver,
			"Restore rebinds the rollback resolver to the reconstructed component")
	end
end
check(assertions >= 200, "Rollback suite has at least 200 meaningful assertions")

local restoreLimitWorld = World.new({
	RollbackProfile = {
		HistorySize = 4, MaxRollbackFrames = 1, AllowSameFrameRollback = true,
	},
	ComponentFactories = { ["Tests.Counter"] = makeCounterFromState },
})
local restoreLimitSimulation = Simulation.new(restoreLimitWorld)
local restoreLimitEntity = restoreLimitWorld:CreateEntity()
restoreLimitEntity:AddComponent(Counter.new())
local restoreLimitResolver = restoreLimitWorld:GetRollbackResolver()
check(restoreLimitResolver:Enable(restoreLimitEntity).Accepted, "Direct-restore limit world enables")
check(restoreLimitResolver:RecordFrame(restoreLimitWorld, { Confirmed = true }).Accepted,
	"Direct-restore baseline records")
restoreLimitSimulation:Step()
check(restoreLimitResolver:RecordFrame(restoreLimitWorld, { Confirmed = true }).Accepted,
	"Direct-restore frame one records as confirmed")
restoreLimitSimulation:Step()
check(restoreLimitResolver:RecordFrame(restoreLimitWorld).Accepted, "Direct-restore frame two records")
check(restoreLimitResolver:RestoreFrame(restoreLimitWorld, 0).Type == RollbackResult.Type.RollbackTooLarge,
	"Direct restore cannot bypass maximum rollback distance")
check(restoreLimitResolver:RestoreFrame(restoreLimitWorld, 3).Type == RollbackResult.Type.InvalidFrame,
	"Direct restore rejects future frames")
check(restoreLimitResolver:RestoreFrame(restoreLimitWorld, 1).Accepted,
	"Direct restore permits a confirmed snapshot at the configured distance")
check(restoreLimitWorld.CurrentFrame == 1 and restoreLimitSimulation.GameTime:GetFrame() == 1,
	"Direct restore keeps World and Simulation frames aligned")

local ReentrantRestore = {}
ReentrantRestore.__index = ReentrantRestore
ReentrantRestore.RollbackKey = "Tests.ReentrantRestore"
setmetatable(ReentrantRestore, { __index = Component })
function ReentrantRestore.new()
	local self = setmetatable(Component.new(), ReentrantRestore)
	self.Value = 0
	self.NestedResult = nil
	return self
end
function ReentrantRestore:CaptureRollbackState()
	return { Value = self.Value }
end
function ReentrantRestore:RestoreRollbackState(state)
	self.Value = state.Value
	local world = self.World or (self.Entity and self.Entity.World)
	self.NestedResult = world:GetRollbackResolver():RequestRollback(world, 0, 0)
	return true
end
local reentrantWorld
reentrantWorld = World.new({
	RollbackProfile = { AllowSameFrameRollback = true },
	ComponentFactories = {
		["Tests.ReentrantRestore"] = function()
			local component = ReentrantRestore.new()
			component.World = reentrantWorld
			return component
		end,
	},
})
local reentrantSimulation = Simulation.new(reentrantWorld)
local reentrantEntity = reentrantWorld:CreateEntity()
local reentrantComponent = reentrantEntity:AddComponent(ReentrantRestore.new())
local reentrantResolver = reentrantWorld:GetRollbackResolver()
check(reentrantResolver:Enable(reentrantEntity).Accepted, "Direct-restore reentrancy world enables")
check(reentrantResolver:RecordFrame(reentrantWorld, { Confirmed = true }).Accepted,
	"Direct-restore reentrancy snapshot records")
reentrantComponent.Value = 9
check(reentrantResolver:RestoreFrame(reentrantWorld, 0).Accepted, "Direct restore completes transactionally")
local restoredReentrantEntity = reentrantWorld:GetEntity(reentrantEntity.Id)
local restoredReentrantComponent = restoredReentrantEntity
	and restoredReentrantEntity:GetComponent(ReentrantRestore)
check(restoredReentrantComponent ~= nil
	and restoredReentrantComponent.Value == 0
	and restoredReentrantComponent.NestedResult
	and restoredReentrantComponent.NestedResult.Type == RollbackResult.Type.RollbackAlreadyInProgress,
	"RestoreFrame blocks nested rollback requests from component adapters")
check(reentrantResolver:RequestRollback(reentrantWorld, 0, 0).Accepted,
	"A valid rollback request can be queued before direct restore")
check(reentrantResolver:RestoreFrame(reentrantWorld, 0).Type == RollbackResult.Type.RollbackAlreadyInProgress,
	"Direct restore refuses to leave a pending rollback request stale")
check(reentrantResolver:CancelRollback().Accepted, "Pending request remains cancellable after direct restore is refused")
reentrantWorld:Destroy()

local CustomRNG = {}
CustomRNG.__index = CustomRNG
function CustomRNG:NextNumber() return 0.5 end
function CustomRNG:NextInteger(minimum) return minimum end
function CustomRNG:GetState() return self.State end
function CustomRNG:SetState(state)
	assert(type(state) == "string")
	self.State = state
end
local customRng = setmetatable({ State = "rng-seed" }, CustomRNG)
local customRngWorld = World.new({
	RollbackProfile = { AllowSameFrameRollback = true },
	ComponentFactories = { ["Tests.Counter"] = makeCounterFromState },
})
local customRngSimulation = Simulation.new(customRngWorld, { RNG = customRng })
local customRngEntity = customRngWorld:CreateEntity()
customRngEntity:AddComponent(Counter.new())
local customRngResolver = customRngWorld:GetRollbackResolver()
check(customRngResolver:Enable(customRngEntity).Accepted, "Custom-RNG rollback world enables")
check(customRngResolver:RecordFrame(customRngWorld, { Confirmed = true }).Accepted,
	"Serializable custom RNG state can be captured")
customRng.State = "changed"
check(customRngResolver:RestoreFrame(customRngWorld, 0).Accepted and customRng.State == "rng-seed",
	"Rollback restores a custom serializable RNG state")
customRngWorld:Destroy()

local replayProfile = RollbackProfile.new({
	HistorySize = 8, MaxRollbackFrames = 7, MaxReplayFrames = 7, RecordReplayFrames = true,
})
local world = World.new({
	RollbackProfile = replayProfile,
	ComponentFactories = { ["Tests.Counter"] = makeCounterFromState },
})
local simulation = Simulation.new(world, { Seed = 14573 })
local rollback = world:GetRollbackResolver()
local attacker, defender, projectile = world:CreateEntity(), world:CreateEntity(), world:CreateEntity()
local attackerState = attacker:AddComponent(Counter.new(0))
local defenderState = defender:AddComponent(Counter.new(0))
local projectileState = projectile:AddComponent(Counter.new(0))
local inputProfile = world:GetInputResolver().Profile
attacker:AddComponent(InputComponent.new(inputProfile))
defender:AddComponent(InputComponent.new(inputProfile))
check(rollback:Enable(attacker).Accepted, "World rollback service enables")
check(rollback:Enable(defender).Accepted, "World rollback supports multiple rollback participants")
check(rollback:Enable(projectile).Accepted, "Projectile participates in world rollback")
check(rollback:GetRollbackState(attacker) == RollbackState.Idle, "Rollback component starts idle")
check(attacker:GetComponent(RollbackComponent) ~= nil, "Enable attaches runtime rollback component")
check(world:GetPredictionResolver():Enable(attacker, PredictionProfile.new({ MaxPredictionFrames = 8 })).Accepted,
	"Prediction integration enabled for attacker")
check(world:GetPredictionResolver():Enable(defender, PredictionProfile.new({ MaxPredictionFrames = 8 })).Accepted,
	"Prediction integration enabled for defender")
local prediction = world:GetPredictionResolver()
check(prediction:Begin(attacker, 0).Accepted and prediction:Begin(defender, 0).Accepted,
	"Prediction histories begin at the confirmed seed")
check(prediction:GetFrame(attacker.Id, 0).Confirmed and prediction:GetFrame(defender.Id, 0).Confirmed,
	"Confirmed prediction seed is retained")
check(rollback:RecordFrame(world, { Confirmed = true }).Accepted,
	"Frame zero confirmed snapshot records for the full world")

local inputResolver = world:GetInputResolver()
for frame = 1, 3 do
	check(prediction:Advance(attacker, frame).Accepted, "Attacker prediction advances at " .. frame)
	check(prediction:Advance(defender, frame).Accepted, "Defender prediction advances at " .. frame)
	if frame == 1 then
		check(inputResolver:SetInput(attacker, Input.Light, InputState.Pressed, frame) ~= nil,
			"Frame one attacker press is recorded")
		check(inputResolver:AdvanceFrame(defender, frame) ~= nil, "Frame one defender neutral input is recorded")
	else
		check(inputResolver:AdvanceFrame(attacker, frame) ~= nil, "Attacker input is recorded at frame " .. frame)
		check(inputResolver:AdvanceFrame(defender, frame) ~= nil, "Defender input is recorded at frame " .. frame)
	end
	simulation:Step()
	check(world.CurrentFrame == frame and simulation.GameTime:GetFrame() == frame,
		"Simulation advances the shared world frame " .. frame)
	check(rollback:RecordFrame(world).Accepted, "Input and state history records frame " .. frame)
end
check(prediction:GetFrame(attacker.Id, 1).Predicted and prediction:GetFrame(attacker.Id, 2).Predicted
	and prediction:GetFrame(attacker.Id, 3).Predicted,
	"Original future frames remain marked predicted")
check(prediction:GetState(attacker.Id).ConfirmedFrame == 0, "Future replay frames are not confirmed")
check(rollback:GetFrame(1).Snapshot.Confirmed == false, "Predicted frame snapshots stay unconfirmed")
check(rollback:CanRollback(world, 1, 3) == false, "Unconfirmed snapshots cannot become restore authority")
check(rollback:ExecuteRollback(world, 1, 3).Type == RollbackResult.Type.UnconfirmedSnapshot,
	"Unconfirmed restore point is explicitly rejected")
check(rollback:StoreSnapshot(world, rollback:GetFrame(0).Snapshot).Accepted,
	"Externally delivered serializable snapshot can be registered without choosing authority")
local externalBaseSnapshot = rollback:GetFrame(0).Snapshot
local malformedSchedulerState = {}
for key, value in pairs(externalBaseSnapshot.Simulation) do
	malformedSchedulerState[key] = value
end
malformedSchedulerState.SchedulerNextId = 1
malformedSchedulerState.SchedulerNextOrder = 1
local malformedLegacySnapshot = RollbackSnapshot.new({
	Frame = externalBaseSnapshot.Frame,
	Entities = externalBaseSnapshot.Entities,
	Simulation = malformedSchedulerState,
	InputFrames = externalBaseSnapshot.InputFrames,
	Confirmed = externalBaseSnapshot.Confirmed,
})
check(rollback:StoreSnapshot(world, malformedLegacySnapshot).Type == RollbackResult.Type.UnsupportedComponent,
	"External snapshots cannot invent non-zero legacy Scheduler history")

local function finalState()
	local parts = { tostring(simulation:GetRNG():GetState()) }
	for _, entity in ipairs(world:GetEntities()) do
		local state = entity:GetComponent(Counter)
		table.insert(parts, table.concat({
			tostring(entity.Id), tostring(state.Value), tostring(state.Steps),
			state.Marker, tostring(state.LastRandom),
		}, ":"))
	end
	return table.concat(parts, "|")
end
local originalFinalState = finalState()
local oldSideEffects = externalSideEffects
local requested = rollback:RequestRollback(world, 0, 3, "PredictionDivergence")
check(requested.Accepted and requested.Request.Reason == "PredictionDivergence",
	"Structured divergence request is accepted")
check(rollback:GetRollbackState(attacker) == RollbackState.Requested, "Request updates runtime state")
check(rollback:ExecuteRollback(world).Accepted, "Rollback replays through the existing Simulation")
check(finalState() == originalFinalState, "Snapshot, inputs, RNG and Simulation reproduce identical world state")
check(rollback:GetLastRollbackFrame(attacker) == 0 and rollback:GetRollbackCount(attacker) == 1,
	"Rollback records restore frame and count")
check(rollback:GetRollbackState(attacker) == RollbackState.Completed, "Successful rollback completes")
check(world:GetExecutionContext() == "Normal" and simulation:GetExecutionContext() == "Normal",
	"Replay execution context is cleared")
check(externalSideEffects == oldSideEffects, "Replay-aware side effects are not duplicated")
check(nestedResult and nestedResult.Type == RollbackResult.Type.RollbackAlreadyInProgress,
	"Nested rollback request is rejected")
check(prediction:GetFrame(attacker.Id, 0).Confirmed and prediction:GetFrame(attacker.Id, 0).Frame == 0,
	"Confirmed seed frame remains confirmed")
check(prediction:GetState(attacker.Id).ConfirmedFrame == 0, "Replay does not advance confirmation")
check(prediction:GetFrame(attacker.Id, 1).Predicted and prediction:GetFrame(attacker.Id, 2).Predicted
	and prediction:GetFrame(attacker.Id, 3).Predicted,
	"Replayed prediction frames preserve predicted status")
check(prediction:GetFrame(attacker.Id, 1).Inputs[Input.Light] == InputState.Pressed,
	"Prediction history replaces frame one with the replayed input")
check(prediction:GetFrame(attacker.Id, 2).Inputs[Input.Light] == InputState.Held,
	"Prediction history replaces frame two with the replayed input")
check(rollback:GetFrame(3).InputFrames[attacker.Id].Inputs[Input.Light] == nil,
	"Frame three stores sparse unchanged input")
check(world:GetInputResolver():GetInput(attacker.Id, Input.Light) == InputState.Held,
	"Replay retains held input across a sparse frame")
check(rollback:GetFrame(1).Replayed and rollback:GetFrame(2).Replayed and rollback:GetFrame(3).Replayed,
	"Successful replay replaces prior rollback frame records")
local rollbackMetrics = rollback:GetMetrics()
check(rollbackMetrics.RollbacksStarted == 1 and rollbackMetrics.RollbacksCompleted == 1
	and rollbackMetrics.RollbacksFailed == 0 and rollbackMetrics.ReplayFrames == 3
	and rollbackMetrics.HistoryFrames >= 4,
	"Rollback metrics report completed replay and retained history")
local eventTypes = {}
local eventContexts = {}
for _, event in ipairs(world:GetRollbackEvents()) do eventTypes[event.Type] = true end
for _, event in ipairs(world:GetRollbackEvents()) do eventContexts[event.Type] = event.ExecutionContext end
check(eventTypes[RollbackEvent.Type.Requested], "Requested event is emitted")
check(eventTypes[RollbackEvent.Type.Started], "Started event is emitted")
check(eventTypes[RollbackEvent.Type.Restoring], "Restoring event is emitted")
check(eventTypes[RollbackEvent.Type.ReplayStarted], "Replay-started event is emitted")
check(eventTypes[RollbackEvent.Type.ReplayFrame], "Optional replay-frame event is emitted")
check(eventTypes[RollbackEvent.Type.Completed], "Completed event is emitted")
check(eventContexts[RollbackEvent.Type.Requested] == "Normal", "Request event carries normal context")
check(eventContexts[RollbackEvent.Type.ReplayStarted] == "Replay", "Replay event carries replay context")

local replayA = finalState()
check(rollback:ExecuteRollback(world, 0, 3).Accepted, "Repeated replay succeeds")
local replayB = finalState()
check(replayA == replayB, "Repeated rollback produces byte-for-byte equal deterministic state")
check(rollback:GetRollbackCount(attacker) == 2, "Repeated rollback increments count")
check(prediction:GetState(attacker.Id).ConfirmedFrame == 0, "Repeated rollback still preserves confirmed frame")
check(world:GetEntity(attacker.Id):GetComponent(Counter).Value
	+ world:GetEntity(defender.Id):GetComponent(Counter).Value
	+ world:GetEntity(projectile.Id):GetComponent(Counter).Value > 0,
	"Attacker, defender and projectile all resimulate")

local missingInputRecord = rollback:GetFrame(1)
local defenderInput = missingInputRecord.InputFrames[defender.Id]
missingInputRecord.InputFrames[defender.Id] = false
local canMissingInput, missingInputReason = rollback:CanRollback(world, 0, 3)
check(not canMissingInput and missingInputReason == RollbackResult.Type.MissingInput,
	"Missing input is rejected before restoration")
local missingInputResult = rollback:ExecuteRollback(world, 0, 3)
check(missingInputResult.Type == RollbackResult.Type.MissingInput, "Missing input returns explicit result")
missingInputRecord.InputFrames[defender.Id] = defenderInput
check(rollback:ExecuteRollback(world, 0, 3).Accepted, "Restored input history allows the replay")
check(rollback:CanRollback(world, 99, 3) == false, "Future restore frame is rejected")
check(rollback:ExecuteRollback(world, 99, 3).Type == RollbackResult.Type.InvalidFrame,
	"Invalid restore frame has explicit result")
local restoreFrame = rollback:GetFrame(0)
local savedRestoreSnapshot = restoreFrame.Snapshot
restoreFrame.Snapshot = nil
check(rollback:ExecuteRollback(world, 0, 3).Type == RollbackResult.Type.MissingSnapshot,
	"Missing restore snapshot has explicit result")
restoreFrame.Snapshot = savedRestoreSnapshot
check(rollback:CanRollback(world, 0, 3, "Invalid") == false, "Invalid scope is rejected")
check(rollback:CanRollback(world, 0, 3, "Entity") == false, "Entity scope rejects multi-entity world")
check(rollback:ExecuteRollback(world, 3, 3).Type == RollbackResult.Type.AlreadyAtFrame,
	"Same-frame restore is rejected by default")
check(not rollback:RequestRollback(world, -1, 3).Accepted, "Negative frame request is rejected")
check(not rollback:RequestRollback(world, 1.5, 3).Accepted, "Fractional frame request is rejected")
check(not rollback:RequestRollback(world, 0, 3, "FreeformReason").Accepted,
	"Unknown request reason is rejected")
check(not rollback:RequestRollback(world, 0, 3, "Manual", "InvalidScope").Accepted,
	"Unknown request scope is rejected")
check(not rollback:RequestRollback({}, 0, 2).Accepted, "Foreign world/entity is rejected")
check(rollback:GetRollbackCount(defender) == rollback:GetRollbackCount(attacker),
	"World-level rollback updates all participants consistently")
check(rollback:GetRollbackState(projectile) == RollbackState.Completed,
	"Projectile runtime state follows world rollback")

-- A failing frame restores the exact pre-rollback world/clock/RNG and exits replay context.
local beforeFailure = finalState()
failReplay = true
local failedReplay = rollback:ExecuteRollback(world, 0, 3)
failReplay = false
check(failedReplay.Type == RollbackResult.Type.ReplayFailed, "Simulation step failure aborts replay")
local recoveredFailureState = finalState()
check(recoveredFailureState == beforeFailure,
	("Failed replay restores pre-rollback component and RNG state "
		.. "(before=%s, after=%s, detail=%s)")
		:format(beforeFailure, recoveredFailureState, tostring(failedReplay.Detail)))
check(simulation.GameTime:GetFrame() == 3 and world.CurrentFrame == 3,
	"Failed replay restores Simulation and World frame")
check(world:GetExecutionContext() == "Normal" and simulation:GetExecutionContext() == "Normal",
	"Failed replay clears execution context")
check(rollback:GetRollbackState(attacker) == RollbackState.Failed, "Failed replay state is exposed")
local failureEvent = false
for _, event in ipairs(world:GetRollbackEvents()) do
	if event.Type == RollbackEvent.Type.Failed then failureEvent = true end
end
check(failureEvent, "Replay failure event is emitted")

-- Explicitly unsupported component systems fail before any state is changed.
local unsupportedWorld = World.new()
local unsupportedSimulation = Simulation.new(unsupportedWorld)
local unsupportedEntity = unsupportedWorld:CreateEntity()
unsupportedEntity:AddComponent(Component.new())
local unsupportedRollback = unsupportedWorld:GetRollbackResolver()
check(unsupportedRollback:Enable(unsupportedEntity).Accepted, "Unsupported test rollback service enables")
local unsupported = unsupportedRollback:RecordFrame(unsupportedWorld)
check(unsupported.Type == RollbackResult.Type.UnsupportedComponent,
	"Components without explicit adapters are rejected")
check(unsupportedSimulation.GameTime:GetFrame() == 0 and unsupportedWorld.CurrentFrame == 0,
	"Unsupported snapshot rejection does not mutate Simulation")
check(not unsupportedRollback:RestoreFrame(unsupportedWorld, 0).Accepted,
	"Missing frame cannot be restored")

-- Rollback/replay limits and history capacity are profile-controlled, not hard-coded in execution.
local limitsWorld = World.new({ RollbackProfile = {
	MaxRollbackFrames = 1, MaxReplayFrames = 0, HistorySize = 2,
}, ComponentFactories = { ["Tests.Counter"] = makeCounterFromState } })
local limitsSimulation = Simulation.new(limitsWorld, { Seed = 89 })
local limitsEntity = limitsWorld:CreateEntity()
limitsEntity:AddComponent(Counter.new(0))
local limitsRollback = limitsWorld:GetRollbackResolver()
check(limitsRollback:Enable(limitsEntity).Accepted, "Limit test resolver enables")
check(limitsRollback:RecordFrame(limitsWorld, { Confirmed = true }).Accepted,
	"Limit history records confirmed frame zero")
limitsSimulation:Step()
check(limitsRollback:RecordFrame(limitsWorld, { Confirmed = true }).Accepted,
	"Limit history records confirmed frame one")
limitsSimulation:Step()
check(limitsRollback:RecordFrame(limitsWorld).Accepted, "Limit history records frame two")
check(limitsRollback:GetFrame(0) == nil and limitsRollback:GetFrame(1) ~= nil
	and limitsRollback:GetFrame(2) ~= nil, "Configured HistorySize evicts old snapshots")
check(limitsRollback:CanRollback(limitsWorld, 1, 2) == false,
	"MaxReplayFrames is independently enforced")
local tooFar, tooFarReason = limitsRollback:CanRollback(limitsWorld, 0, 0)
check(not tooFar and tooFarReason == RollbackResult.Type.RollbackTooLarge,
	"MaxRollbackFrames independently bounds restore distance")
check(limitsRollback:ExecuteRollback(limitsWorld, 1, 2).Type == RollbackResult.Type.ReplayTooLarge,
	"Replay limit returns explicit result")

local noIntermediateSnapshotWorld = World.new({ RollbackProfile = {
	AbortOnMissingSnapshot = false, HistorySize = 4,
}, ComponentFactories = { ["Tests.Counter"] = makeCounterFromState } })
local noIntermediateSnapshotSimulation = Simulation.new(noIntermediateSnapshotWorld, { Seed = 207 })
local noIntermediateSnapshotEntity = noIntermediateSnapshotWorld:CreateEntity()
noIntermediateSnapshotEntity:AddComponent(Counter.new(0))
local noIntermediateSnapshotRollback = noIntermediateSnapshotWorld:GetRollbackResolver()
check(noIntermediateSnapshotRollback:Enable(noIntermediateSnapshotEntity).Accepted,
	"Explicit missing-intermediate-snapshot policy enables")
check(noIntermediateSnapshotRollback:RecordFrame(noIntermediateSnapshotWorld, { Confirmed = true }).Accepted,
	"Explicit missing-snapshot policy records restore point")
noIntermediateSnapshotSimulation:Step()
check(noIntermediateSnapshotRollback:RecordFrame(noIntermediateSnapshotWorld).Accepted,
	"Explicit missing-snapshot policy records replay input")
noIntermediateSnapshotRollback:GetFrame(1).Snapshot = nil
check(noIntermediateSnapshotRollback:CanRollback(noIntermediateSnapshotWorld, 0, 1),
	"Missing intermediate state snapshot is permitted only by explicit policy")
check(noIntermediateSnapshotRollback:ExecuteRollback(noIntermediateSnapshotWorld, 0, 1).Accepted,
	"Replay proceeds from retained input when intermediate snapshot policy permits it")

local disabledWorld = World.new({ RollbackProfile = { Enabled = false } })
local disabledEntity = disabledWorld:CreateEntity()
local disabledResult = disabledWorld:GetRollbackResolver():Enable(disabledEntity)
check(disabledResult.Type == RollbackResult.Type.Disabled, "Disabled profile cannot activate rollback")
check(disabledWorld:GetRollbackResolver():GetRollbackState(disabledEntity) == RollbackState.Idle,
	"Disabled rollback does not alter entity combat life state")
check(disabledEntity:IsAlive() and not disabledEntity:IsDead(), "Rollback state remains separate from Alive/Dead")
check(not disabledWorld:GetRollbackResolver():Enable({ Id = -1 }).Accepted, "Invalid entity enable is rejected")

local scheduledWorld = World.new()
local scheduledSimulation = Simulation.new(scheduledWorld)
local scheduledEntity = scheduledWorld:CreateEntity()
scheduledEntity:AddComponent(Counter.new(0))
local scheduledRollback = scheduledWorld:GetRollbackResolver()
scheduledRollback:Enable(scheduledEntity)
scheduledSimulation:GetScheduler():After(10, function() end, "unrestorable")
check(scheduledRollback:RecordFrame(scheduledWorld).Type == RollbackResult.Type.UnsupportedWorld,
	"Pending callbacks without a rollback contract are explicitly unsupported")

local collisionWorld = World.new()
local collisionSimulation = Simulation.new(collisionWorld)
local collisionEntity = collisionWorld:CreateEntity()
collisionEntity:AddComponent(Counter.new(0))
local collisionRollback = collisionWorld:GetRollbackResolver()
collisionRollback:Enable(collisionEntity)
collisionWorld.CollisionWorld = { Step = function() end }
check(collisionRollback:RecordFrame(collisionWorld).Type == RollbackResult.Type.UnsupportedWorld,
	"Collision system without reversible snapshot adapters is explicitly unsupported")
check(collisionSimulation.GameTime:GetFrame() == 0, "Unsupported collision rollback does not change frame")

local RestoreFailure = {}
RestoreFailure.__index = RestoreFailure
RestoreFailure.RollbackKey = "Tests.RestoreFailure"
setmetatable(RestoreFailure, { __index = Component })
local rejectSavedState = false
function RestoreFailure.new()
	local self = setmetatable(Component.new(), RestoreFailure)
	self.Value = 0
	return self
end
function RestoreFailure:CaptureRollbackState()
	return { Value = self.Value }
end
function RestoreFailure:RestoreRollbackState(state)
	if rejectSavedState and state.Value == 0 then error("intentional restore failure") end
	self.Value = state.Value
	return true
end
local restoreFailureWorld = World.new({
	RollbackProfile = { AllowSameFrameRollback = true },
	ComponentFactories = {
		["Tests.RestoreFailure"] = function() return RestoreFailure.new() end,
	},
})
local restoreFailureSimulation = Simulation.new(restoreFailureWorld)
local restoreFailureEntity = restoreFailureWorld:CreateEntity()
local restoreFailureComponent = restoreFailureEntity:AddComponent(RestoreFailure.new())
local restoreFailureResolver = restoreFailureWorld:GetRollbackResolver()
check(restoreFailureResolver:Enable(restoreFailureEntity).Accepted,
	"Restore-failure test enables rollback")
check(restoreFailureResolver:RecordFrame(restoreFailureWorld, { Confirmed = true }).Accepted,
	"Restore-failure test records a confirmed baseline")
restoreFailureComponent.Value = 9
rejectSavedState = true
local restoreFailureResult = restoreFailureResolver:RestoreFrame(restoreFailureWorld, 0)
rejectSavedState = false
check(restoreFailureResult.Type == RollbackResult.Type.RestoreFailed,
	"Restore adapter failure returns explicit failure")
check(restoreFailureComponent.Value == 9 and restoreFailureWorld.CurrentFrame == 0
	and restoreFailureSimulation.GameTime:GetFrame() == 0,
	"Failed component restore recovers the complete pre-restore state")

local invalidEntityResolver = world:GetRollbackResolver()
check(invalidEntityResolver:GetRollbackState(-999) == RollbackState.Idle,
	"Unknown entity has no rollback state")
check(invalidEntityResolver:GetRollbackCount(-999) == 0, "Unknown entity has zero rollback count")
check(invalidEntityResolver:RestoreFrame(world, -1).Type == RollbackResult.Type.InvalidFrame,
	"Restore rejects negative frames")
check(invalidEntityResolver:RestoreFrame(world, 1.25).Type == RollbackResult.Type.InvalidFrame,
	"Restore rejects fractional frames")
check(invalidEntityResolver:CanRollback(world, 0, -1) == false, "CanRollback rejects invalid end frame")
check(invalidEntityResolver:CancelRollback().Type == RollbackResult.Type.InvalidRequest,
	"Cancel without pending request is safe")
check(invalidEntityResolver:Disable(attacker).Accepted, "Rollback participant can be disabled")
check(invalidEntityResolver:Disable(defender).Accepted, "Second rollback participant can be disabled")
check(invalidEntityResolver:Disable(projectile).Accepted, "Third rollback participant can be disabled")
check(invalidEntityResolver:RecordFrame(world).Type == RollbackResult.Type.Disabled,
	"Disabled participants stop snapshot capture")
check(invalidEntityResolver:Enable(attacker, replayProfile).Accepted, "Rollback participant can re-enable")
check(invalidEntityResolver:RecordFrame(world).Accepted, "Re-enabled rollback captures the current frame")
check(invalidEntityResolver:RequestRollback(world, 0, 3).Accepted, "Pending rollback request can be cancelled")
check(invalidEntityResolver:CancelRollback().Accepted, "Safe pending rollback cancellation succeeds")
check(invalidEntityResolver:GetRollbackState(attacker) == RollbackState.Idle,
	"Cancellation returns lifecycle to idle")
check(#world:GetRollbackResults() == #world:GetRollbackResolver():GetResults(),
	"World exposes rollback results through its resolver")

local noSimulationWorld = World.new()
local noSimulationEntity = noSimulationWorld:CreateEntity()
noSimulationEntity:AddComponent(Counter.new(0))
local noSimulationRollback = noSimulationWorld:GetRollbackResolver()
check(noSimulationRollback:Enable(noSimulationEntity).Accepted, "No-Simulation rollback participant enables")
local canRollbackWithoutSimulation, noSimulationReason = noSimulationRollback:CanRollback(noSimulationWorld, 0, 0)
check(not canRollbackWithoutSimulation and noSimulationReason == RollbackResult.Type.InvalidSimulation,
	"CanRollback returns InvalidSimulation when the World has no Simulation")
check(noSimulationRollback:StoreSnapshot(noSimulationWorld, {}).Type == RollbackResult.Type.InvalidSimulation,
	"StoreSnapshot rejects a World without Simulation before inspecting external data")
check(noSimulationRollback:ExecuteRollback(noSimulationWorld, 0, 0).Type == RollbackResult.Type.InvalidSimulation,
	"ExecuteRollback returns InvalidSimulation instead of dereferencing nil")
noSimulationWorld:Destroy()

check(invalidEntityResolver:ExecuteRollback(world, 0, 1).Accepted,
	"Rollback may finish before the World's former current frame")
check(world.CurrentFrame == 1 and prediction:GetState(attacker.Id).CurrentFrame == 1
	and prediction:GetFrame(attacker.Id, 3) == nil,
	"Partial rollback truncates Prediction history and aligns its frame")
check(prediction:Advance(attacker.Id, 2).Accepted,
	"Prediction can advance immediately after a partial rollback")
check(invalidEntityResolver:RestoreFrame(world, 0).Accepted,
	"Direct restore rewinds the World after partial prediction replay")
check(prediction:GetState(attacker.Id).CurrentFrame == 0 and prediction:GetFrame(attacker.Id, 2) == nil,
	"Direct restore truncates future Prediction state")
check(prediction:Advance(attacker.Id, 1).Accepted, "Prediction advances from the directly restored frame")
simulation:Step()
check(world.CurrentFrame == 1 and prediction:GetState(attacker.Id).CurrentFrame == 1,
	"Simulation and Prediction realign after the restored frame is advanced")

check(assertions >= 250, "Rollback tests execute more than 250 meaningful assertions")
print("Combat rollback tests passed")

end
