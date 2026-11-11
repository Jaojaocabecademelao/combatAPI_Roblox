return function()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local SimulationFolder = Shared:WaitForChild("Simulation")

local Component = require(Core.Component)
local World = require(Core.World)
local Simulation = require(SimulationFolder.Simulation)
local FrameCommandBuffer = require(SimulationFolder.FrameCommandBuffer)
local DeterministicScheduler = require(SimulationFolder.DeterministicScheduler)
local StateSerializer = require(SimulationFolder.StateSerializer)
local StateHasher = require(SimulationFolder.StateHasher)
local SimulationState = require(SimulationFolder.SimulationState)

local assertions = 0
local function check(value, message)
	assert(value, message or ("Determinism assertion " .. tostring(assertions + 1) .. " failed"))
	assertions += 1
end

local function createCommand(commandId, entityId, sequence, amount)
	return {
		ProtocolVersion = FrameCommandBuffer.ProtocolVersion,
		CommandId = commandId,
		SessionId = "test-session",
		EntityId = entityId,
		Frame = 1,
		Sequence = sequence,
		Type = "Add",
		Payload = { Amount = amount, Nested = { Enabled = true } },
	}
end

-- Canonical serialization is independent of table insertion order and rejects unsupported data.
local first = { Z = 3, A = { Y = true, X = "value" }, [2] = "two", [1] = "one" }
local second = { [1] = "one", A = { X = "value", Y = true }, Z = 3, [2] = "two" }
local canonical = StateSerializer.Serialize(first)
check(canonical == StateSerializer.Serialize(second), "Canonical serialization ignores insertion order")
check(StateHasher.Hash(first) == StateHasher.Hash(second), "Equivalent states have identical hashes")
check(string.sub(StateHasher.Hash(first), 1, 9) == "state-v1:", "State hash has a versioned prefix")
local copy = StateSerializer.CloneSerializable(first)
first.A.X = "changed"
check(copy.A.X == "value", "Serializable clone does not alias source tables")
local cycle = {}; cycle.Self = cycle
check(not pcall(StateSerializer.Serialize, cycle), "Serializer rejects cyclic tables")
check(not pcall(StateSerializer.Serialize, { Callback = function() end }), "Serializer rejects functions")
check(not pcall(StateSerializer.Serialize, { Number = math.huge }), "Serializer rejects non-finite numbers")
check(not pcall(StateSerializer.Serialize, setmetatable({}, {})), "Serializer rejects metatable-backed tables")

-- Frame command buffer validates protocol data, deduplicates IDs and sorts stably.
local commandBuffer = FrameCommandBuffer.new({ HistorySize = 4 })
check(not pcall(function() FrameCommandBuffer.new(false) end), "Command buffer rejects a non-table options value")
check(not pcall(function() FrameCommandBuffer.new({ MaxCommandsPerFrame = false }) end),
	"Command buffer rejects false capacity rather than silently defaulting")
check(not pcall(function() FrameCommandBuffer.new({ HistorySize = false }) end),
	"Command buffer rejects false history size rather than silently defaulting")
local commandTwo = createCommand("cmd-2", 2, 2, 20)
local acceptedTwo, wasAcceptedTwo = commandBuffer:Push(commandTwo)
check(acceptedTwo ~= nil and wasAcceptedTwo == true, "Valid command is accepted")
local commandOne = createCommand("cmd-1", 1, 1, 10)
local acceptedOne, wasAcceptedOne = commandBuffer:Push(commandOne)
check(acceptedOne ~= nil and wasAcceptedOne == true, "Second valid command is accepted")
local commandEarlier = createCommand("cmd-0", 1, 0, 5)
local acceptedEarlier, wasAcceptedEarlier = commandBuffer:Push(commandEarlier)
check(acceptedEarlier ~= nil and wasAcceptedEarlier == true, "Zero sequence number is valid")
local duplicate, duplicateAccepted, duplicateCode = commandBuffer:Push(createCommand("cmd-1", 1, 1, 10))
check(duplicate ~= nil and duplicateAccepted == false and duplicateCode == "Duplicate",
	"Exact command retransmission is deduplicated")
local conflict, conflictCode = commandBuffer:Push(createCommand("cmd-1", 1, 1, 11))
check(conflict == nil and conflictCode == "CommandIdConflict", "Conflicting reuse of a command ID is rejected")
local ordered = commandBuffer:GetFrame(1)
check(#ordered == 3 and ordered[1].CommandId == "cmd-0" and ordered[2].CommandId == "cmd-1"
	and ordered[3].EntityId == 2, "Commands are sorted by entity ID, sequence, then command ID")
check(not pcall(function() acceptedOne.Payload.Nested.Enabled = false end),
	"Accepted commands and nested payloads are immutable")
commandBuffer:ConsumeFrame(1)
check(commandBuffer:GetPendingCount() == 0 and #commandBuffer:GetFrame(1) == 3,
	"Consumed commands remain in the bounded replay history")
local savedBuffer = commandBuffer:CaptureState()
local restoredBuffer = FrameCommandBuffer.new()
check(restoredBuffer:RestoreState(savedBuffer), "Command buffer state restores")
check(#restoredBuffer:GetFrame(1) == 3 and restoredBuffer:GetAcceptedCount() == 3,
	"Command history survives a round trip")
check(restoredBuffer:RewindConsumption(0), "Command buffer can rewind within retained history")
check(#restoredBuffer:ConsumeFrame(1) == 3, "Replayed frame returns its original commands")
local invalidCommand, invalidCommandCode = commandBuffer:Push({ Type = "Damage", Amount = 100 })
check(invalidCommand == nil and invalidCommandCode == "InvalidCommand", "Unversioned commands are rejected")
local removalBuffer = FrameCommandBuffer.new()
removalBuffer:Push(createCommand("remove-me", 1, 5, 5))
check(removalBuffer:Remove("remove-me") and removalBuffer:GetAcceptedCount() == 1,
	"Removing a command does not erase the lifetime rollback-safety record")
removalBuffer:Clear()
check(removalBuffer:GetAcceptedCount() == 1 and removalBuffer.LastConsumedFrame == 0,
	"Clearing retained commands preserves lifetime acceptance and frame cursor")
local clearedHistoryBuffer = FrameCommandBuffer.new()
clearedHistoryBuffer:Push(createCommand("cleared-history", 1, 1, 1))
clearedHistoryBuffer:ConsumeFrame(1)
clearedHistoryBuffer:Clear()
check(not clearedHistoryBuffer:RewindConsumption(0) and clearedHistoryBuffer:CanReplayFrom(1),
	"Clearing consumed commands advances the earliest replayable frame")
local retainedWorld = World.new()
local retainedEntity = retainedWorld:CreateEntity()
local retainedSimulation = Simulation.new(retainedWorld, { FrameCommandBuffer = { HistorySize = 1 } })
retainedSimulation:RegisterCommandHandler("Add", function() end)
retainedSimulation:QueueCommand(createCommand("pruned-command", retainedEntity.Id, 1, 1))
retainedSimulation:Step(); retainedSimulation:Step()
check(#retainedSimulation:GetFrameCommandBuffer():GetHistoryCommands() == 0
	and not retainedSimulation:CanRestoreRollbackFrame(),
	"Legacy rollback remains conservatively disabled after command history is pruned")

-- Registered data events sort by target frame then insertion order and survive a snapshot.
local schedulerTrace = {}
local scheduler = DeterministicScheduler.new()
check(not pcall(function() DeterministicScheduler.new(false) end), "Scheduler rejects a non-table options value")
check(not pcall(function() DeterministicScheduler.new({ CurrentFrame = false }) end),
	"Scheduler rejects false CurrentFrame rather than silently defaulting")
check(not pcall(function() DeterministicScheduler.new({ MaxEvents = false }) end),
	"Scheduler rejects false MaxEvents rather than silently defaulting")
local function registerTraceHandler(target, trace)
	return target:RegisterHandler("Trace", function(event)
		table.insert(trace, event.Parameters.Label .. "@" .. tostring(event.Frame))
	end)
end
check(registerTraceHandler(scheduler, schedulerTrace), "Trace event handler registers")
scheduler:Schedule(2, "Trace", 1, { Label = "first" })
scheduler:Schedule(2, "Trace", 1, { Label = "second" })
scheduler:Schedule(1, "Trace", 2, { Label = "repeat" }, 2)
scheduler:Step(1)
check(table.concat(schedulerTrace, ",") == "repeat@1", "Periodic data event runs on its target frame")
local schedulerState = scheduler:CaptureState()
table.clear(schedulerTrace)
local restoredScheduler = DeterministicScheduler.new()
local restoredTrace = {}
check(registerTraceHandler(restoredScheduler, restoredTrace), "Restored trace handler registers")
check(restoredScheduler:RestoreState(schedulerState), "Deterministic scheduler restores registered events")
scheduler:Step(2); restoredScheduler:Step(2)
scheduler:Step(3); restoredScheduler:Step(3)
check(table.concat(schedulerTrace, ",") == "first@2,second@2,repeat@3"
	and table.concat(restoredTrace, ",") == table.concat(schedulerTrace, ","),
	"Event ordering and periodic rescheduling replay identically after restore")
local unregisteredScheduler = DeterministicScheduler.new()
local unregisteredOk = unregisteredScheduler:RestoreState(schedulerState)
check(unregisteredOk == false, "Scheduler restore rejects missing handler registrations")

local Counter = {}
Counter.__index = Counter
setmetatable(Counter, { __index = Component })
function Counter.new(trace)
	local self = setmetatable(Component.new(), Counter)
	self.Value = 0
	self.Trace = trace
	return self
end
function Counter:Step()
	table.insert(self.Trace, "World")
end

local function createScenario()
	local trace = {}
	local world = World.new()
	local entity = world:CreateEntity()
	local counter = entity:AddComponent(Counter.new(trace))
	local simulation = Simulation.new(world, { FixedDeltaTime = 0.1, Seed = 511 })
	check(simulation:RegisterCommandHandler("Add", function(_, command)
		table.insert(trace, "Command")
		counter.Value += command.Payload.Amount
	end), "Command handler registers")
	check(simulation:RegisterScheduledHandler("Add", function(event)
		table.insert(trace, "DataEvent")
		counter.Value += event.Parameters.Amount
	end), "Deterministic event handler registers")
	local queued = simulation:QueueCommand(createCommand("scenario-command", entity.Id, 1, 4))
	check(queued ~= nil, "Simulation accepts a command for a future frame")
	simulation:ScheduleEvent(2, "Add", entity.Id, { Amount = 3 })
	return simulation, world, counter, trace
end

local firstSimulation, _, firstCounter, firstTrace = createScenario()
local secondSimulation, _, secondCounter, secondTrace = createScenario()
firstSimulation:Step()
secondSimulation:Step()
check(firstCounter.Value == 4 and secondCounter.Value == 4, "Frame-one command executes in both scenarios")
check(table.concat(firstTrace, ",") == "Command,World", "Frame commands execute before World:Step")
local kernelSnapshot = firstSimulation:CaptureState()
local snapshotHash = StateHasher.Hash(kernelSnapshot)
local malformedKernelState = StateSerializer.CloneSerializable(kernelSnapshot)
malformedKernelState.DeterministicScheduler = {}
check(not pcall(SimulationState.new, malformedKernelState),
	"SimulationState constructor rejects malformed deterministic substate")
check(firstSimulation:GetPendingStepCount() == 0, "Manual fixed step does not use the accumulator")
firstSimulation:Step()
secondSimulation:Step()
check(firstCounter.Value == 7 and secondCounter.Value == 7, "Registered data event executes at its target frame")
check(table.concat(firstTrace, ",") == "Command,World,DataEvent,World",
	"Data scheduler runs after commands and before World:Step")
check(firstSimulation:GetKernelStateHash() == secondSimulation:GetKernelStateHash(),
	"Equivalent command/event traces produce identical kernel state hashes")

-- Snapshot restores the Simulation kernel (not World Components) and requires matching handler registries.
local restoreWorld = World.new()
restoreWorld:CreateEntity()
local restoredSimulation = Simulation.new(restoreWorld, { FixedDeltaTime = 0.1, Seed = 1 })
restoredSimulation:RegisterCommandHandler("Add", function() end)
restoredSimulation:RegisterScheduledHandler("Add", function() end)
check(restoredSimulation:RestoreState(kernelSnapshot), "Versioned SimulationState restores")
check(restoredSimulation:GetKernelStateHash() == snapshotHash,
	"Restored kernel state has the same canonical hash")
local mismatchWorld = World.new()
mismatchWorld:CreateEntity()
local mismatchSimulation = Simulation.new(mismatchWorld, { FixedDeltaTime = 0.1, Seed = 1 })
local mismatchOk = mismatchSimulation:RestoreState(kernelSnapshot)
check(mismatchOk == false, "Restore rejects unregistered command and event handlers")
local limitMismatchWorld = World.new()
local limitMismatchSimulation = Simulation.new(limitMismatchWorld, {
	FixedDeltaTime = 0.1, FrameCommandBuffer = { HistorySize = 4 },
})
check(limitMismatchSimulation:RestoreState(kernelSnapshot) == false,
	"Restore rejects queue-capacity configuration mismatches")
check(not pcall(function()
	Simulation.new({ Step = function() end }, { DeterministicScheduler = { CurrentFrame = 10 } })
end), "Simulation rejects a non-zero scheduler start frame")
check(not pcall(function() Simulation.new({ Step = function() end }, false) end),
	"Simulation rejects a non-table options value")

-- The old closure Scheduler remains compatible but is explicitly excluded from rollback-safe state.
local legacyWorld = World.new()
local legacySimulation = Simulation.new(legacyWorld, { FixedDeltaTime = 0.1 })
legacySimulation:GetScheduler():After(1, function() end)
check(not legacySimulation:CanRestoreRollbackFrame(), "Legacy closure timers disable legacy rollback restore")
check(not pcall(function() legacySimulation:CaptureState() end),
	"SimulationState refuses to omit legacy callback state")
local completedLegacyWorld = World.new()
local completedLegacySimulation = Simulation.new(completedLegacyWorld, { FixedDeltaTime = 0.1 })
local legacyCallbackRan = false
completedLegacySimulation:GetScheduler():After(0.01, function() legacyCallbackRan = true end)
completedLegacySimulation:Step()
check(legacyCallbackRan and not completedLegacySimulation:GetScheduler():HasPendingEvents()
	and not completedLegacySimulation:CanRestoreRollbackFrame(),
	"Executed closure history remains outside rollback even after the queue empties")

-- The guard is an explicit instrumentation boundary, not a VM-wide interception mechanism.
local guardWorld = World.new()
local guardSimulation = Simulation.new(guardWorld)
local guard = guardSimulation:GetDeterminismGuard()
check(guard:Check("WallClock"), "Normal execution permits external wall-clock reads")
guardSimulation:SetExecutionContext("Replay")
local allowed, violation = guard:Check("WallClock", "test read")
check(not allowed and violation.Operation == "WallClock" and violation.Context == "Replay",
	"Replay guard records a forbidden operation")
local replayEvent, replayScheduleCode = guardSimulation:ScheduleEvent(1, "NotRegistered", 1, {})
check(replayEvent == nil and replayScheduleCode == "InvalidExecutionContext",
	"Simulation rejects data-event scheduling during legacy replay")
check(not pcall(function()
	guardSimulation:GetDeterministicScheduler():Schedule(1, "NotRegistered", 1, {})
end), "Direct Scheduler access cannot bypass the replay scheduling guard")
check(not pcall(function() guardSimulation:AssertDeterministicOperation("IrreversibleSideEffect") end),
	"Replay guard can reject forbidden operations explicitly")
check(guard:Check("SeededSimulationRNG"), "Unclassified deterministic operations remain allowed")
guardSimulation:SetExecutionContext("Normal")
guardWorld:Destroy(); legacyWorld:Destroy(); mismatchWorld:Destroy(); restoreWorld:Destroy()
limitMismatchWorld:Destroy(); completedLegacyWorld:Destroy(); retainedWorld:Destroy()

print("Combat deterministic kernel tests passed (" .. tostring(assertions) .. " assertions)")

end
