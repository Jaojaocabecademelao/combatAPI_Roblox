local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local SimulationFolder = Shared:WaitForChild("Simulation")

local Component = require(Core.Component)
local World = require(Core.World)
local Simulation = require(SimulationFolder.Simulation)
local GameTime = require(SimulationFolder.GameTime)
local Scheduler = require(SimulationFolder.Scheduler)
local DeterministicRNG = require(SimulationFolder.DeterministicRNG)

local function createRecordingWorld()
	local fakeWorld = { Steps = {} }
	function fakeWorld:Step(deltaTime)
		table.insert(self.Steps, deltaTime)
	end
	return fakeWorld
end

local function approximatelyEqual(actual, expected)
	return math.abs(actual - expected) < 1e-9
end

local fixedDeltaTime = 1 / 60

local gameTime = GameTime.new(fixedDeltaTime)
assert(gameTime:GetFrame() == 0, "GameTime frame should start at zero")
assert(gameTime:GetTime() == 0 and gameTime:GetDeltaTime() == 0,
	"GameTime should start at time zero with no previous delta")
assert(gameTime:GetFixedDeltaTime() == fixedDeltaTime, "GameTime should retain FixedDeltaTime")
for _ = 1, 3 do
	gameTime:Advance()
end
assert(gameTime:GetFrame() == 3, "GameTime should count fixed advances")
assert(gameTime:GetDeltaTime() == fixedDeltaTime, "GameTime delta should equal the fixed delta")
assert(approximatelyEqual(gameTime:GetTime(), 3 * fixedDeltaTime), "GameTime should track simulated time")
gameTime:Reset()
assert(gameTime:GetFrame() == 0 and gameTime:GetTime() == 0 and gameTime:GetDeltaTime() == 0,
	"GameTime:Reset() should restore its initial state")

local recordingWorld = createRecordingWorld()
local simulation = Simulation.new(recordingWorld, {
	FixedDeltaTime = fixedDeltaTime,
	MaxStepsPerUpdate = 5,
})

simulation:Update(fixedDeltaTime * 0.5)
assert(#recordingWorld.Steps == 0, "Simulation should not step before one fixed interval")
assert(approximatelyEqual(simulation:GetAlpha(), 0.5), "Alpha should reflect the fractional accumulator")

simulation:Update(fixedDeltaTime * 0.5)
assert(#recordingWorld.Steps == 1, "One fixed interval should produce one step")
assert(recordingWorld.Steps[1] == fixedDeltaTime, "World:Step() should receive FixedDeltaTime")
assert(simulation:GetGameTime():GetFrame() == 1, "Simulation should advance GameTime per fixed step")
assert(approximatelyEqual(simulation:GetAlpha(), 0), "Accumulator should be empty after one exact step")

simulation:Update(fixedDeltaTime * 3.25)
assert(#recordingWorld.Steps == 4, "Three fixed intervals should produce three additional steps")
for _, stepDeltaTime in ipairs(recordingWorld.Steps) do
	assert(stepDeltaTime == fixedDeltaTime, "Every step should use the same FixedDeltaTime")
end
assert(approximatelyEqual(simulation:GetAlpha(), 0.25), "Simulation should preserve fractional remaining time")
assert(simulation:GetGameTime():GetFrame() == 4, "GameTime frame should match executed fixed steps")
assert(simulation:GetWorld() == recordingWorld, "Simulation should expose its World")
assert(simulation:GetScheduler() ~= nil and simulation:GetRNG() ~= nil,
	"Simulation should expose its Scheduler and RNG")
assert(simulation:GetGameplayScheduler() == simulation.DeterministicScheduler,
	"Simulation should expose the deterministic gameplay scheduler")
assert(simulation:GetLegacyScheduler() == simulation:GetScheduler(),
	"Simulation should expose the legacy scheduler only through its compatibility getter")

local gameplayEvents = {}
local gameplaySimulation = Simulation.new(createRecordingWorld())
assert(gameplaySimulation:RegisterGameplayEventHandler("test.delay", function(event)
	table.insert(gameplayEvents, event.Parameters.Label)
end), "Gameplay event handler should register")
local gameplayEventId = gameplaySimulation:ScheduleGameplayEventAfter(
	2, "test.delay", 7, { Label = "delayed" })
assert(type(gameplayEventId) == "number", "Relative gameplay event should return an ID")
gameplaySimulation:Step()
assert(#gameplayEvents == 0, "Relative gameplay event should not execute early")
gameplaySimulation:Step()
assert(gameplayEvents[1] == "delayed", "Relative gameplay event should execute at its frame")

local cappedWorld = createRecordingWorld()
local cappedSimulation = Simulation.new(cappedWorld, {
	FixedDeltaTime = 0.1,
	MaxStepsPerUpdate = 2,
})
cappedSimulation:Update(0.55)
assert(#cappedWorld.Steps == 2, "Simulation should not exceed MaxStepsPerUpdate")
assert(cappedSimulation:GetPendingStepCount() == 3,
	"Simulation should retain overdue whole steps after the per-update work limit")
assert(approximatelyEqual(cappedSimulation:GetAlpha(), 0.5),
	"Interpolation alpha should use only the fractional accumulator remainder")
cappedSimulation:Update(0)
assert(#cappedWorld.Steps == 4 and cappedSimulation:GetPendingStepCount() == 1,
	"A later update should continue processing retained overdue steps")
cappedSimulation:Update(0)
assert(#cappedWorld.Steps == 5 and cappedSimulation:GetPendingStepCount() == 0,
	"Simulation should drain retained steps without discarding authoritative frames")
assert(approximatelyEqual(cappedSimulation:GetAlpha(), 0.5),
	"Interpolation alpha should use only the fractional accumulator remainder")

local precisionWorld = createRecordingWorld()
local precisionSimulation = Simulation.new(precisionWorld, { FixedDeltaTime = 0.1 })
precisionSimulation:Update(0.3)
assert(#precisionWorld.Steps == 3 and precisionSimulation:GetPendingStepCount() == 0,
	"Binary floating-point rounding must not drop an exact 0.3 / 0.1 frame")
for _ = 1, 30 do precisionSimulation:Update(0.1) end
assert(#precisionWorld.Steps == 33 and precisionSimulation:GetPendingStepCount() == 0,
	"Repeated decimal fixed steps must preserve every authoritative frame")

local invalidWorld = createRecordingWorld()
local invalidDeltaSimulation = Simulation.new(invalidWorld, { FixedDeltaTime = fixedDeltaTime })
local invalidValues = { -1, math.huge, math.huge - math.huge }
for _, invalidDeltaTime in ipairs(invalidValues) do
	local succeeded = pcall(function()
		invalidDeltaSimulation:Update(invalidDeltaTime)
	end)
	assert(not succeeded, "Negative, infinite, and NaN deltaTime values should be rejected")
end
local nilSucceeded = pcall(function()
	invalidDeltaSimulation:Update(nil)
end)
assert(not nilSucceeded, "nil deltaTime should be rejected")
assert(#invalidWorld.Steps == 0 and invalidDeltaSimulation:GetAlpha() == 0,
	"Invalid deltaTime should not modify the accumulator or step the world")

local StepCounter = {}
StepCounter.__index = StepCounter
setmetatable(StepCounter, { __index = Component })

function StepCounter.new(onStep)
	local self = Component.new()
	self.StepCount = 0
	self.UpdateCount = 0
	self.StepDeltaTimes = {}
	self.OnStep = onStep
	return setmetatable(self, StepCounter)
end

function StepCounter:Step(deltaTime)
	self.StepCount += 1
	table.insert(self.StepDeltaTimes, deltaTime)
	if self.OnStep then
		self.OnStep(deltaTime)
	end
end

function StepCounter:Update()
	self.UpdateCount += 1
end

local world = World.new()
local entity = world:CreateEntity()
local stepCounter = entity:AddComponent(StepCounter.new())
local integratedSimulation = Simulation.new(world, {
	FixedDeltaTime = fixedDeltaTime,
	MaxStepsPerUpdate = 5,
})

integratedSimulation:Update(fixedDeltaTime * 3)
assert(stepCounter.StepCount == 3, "Simulation should step World through Entity to Component")
assert(stepCounter.UpdateCount == 0, "Simulation should not automatically call World:Update()")
for _, stepDeltaTime in ipairs(stepCounter.StepDeltaTimes) do
	assert(stepDeltaTime == fixedDeltaTime, "Integrated component should receive fixed deltaTime")
end

local schedulerSimulation = Simulation.new(createRecordingWorld(), { FixedDeltaTime = 0.1 })
local scheduler = schedulerSimulation:GetScheduler()
assert(getmetatable(scheduler) == Scheduler, "Simulation should own a Scheduler instance")
local schedulerOrder = {}
local cancelledEventId = scheduler:At(0.1, function()
	table.insert(schedulerOrder, "cancelled")
end)
assert(scheduler:Cancel(cancelledEventId), "Scheduler:Cancel() should cancel by ID")

local periodicCount = 0
local periodicId = scheduler:Every(0.1, function()
	periodicCount += 1
	table.insert(schedulerOrder, "every")
end, "Periodic")
scheduler:After(0.2, function()
	table.insert(schedulerOrder, "after-first")
end)
scheduler:At(0.2, function()
	table.insert(schedulerOrder, "at")
end)
scheduler:After(0.2, function()
	table.insert(schedulerOrder, "after-second")
end)
assert(scheduler:CancelTag("Missing") == 0, "CancelTag() should report no unmatched events")
local taggedOne = scheduler:At(0.3, function()
	error("Cancelled tagged event should not run")
end, "Attack")
local taggedTwo = scheduler:After(0.3, function()
	error("Cancelled tagged event should not run")
end, "Attack")
assert(scheduler:CancelTag("Attack") == 2, "CancelTag() should cancel all events with a matching tag")
assert(not scheduler:Cancel(taggedOne) and not scheduler:Cancel(taggedTwo),
	"Tagged events should no longer be cancellable after removal")

schedulerSimulation:Step()
assert(#schedulerOrder == 1 and schedulerOrder[1] == "every",
	"Scheduler should use simulation time for deadlines")
schedulerSimulation:Step()
local expectedSchedulerOrder = { "every", "after-first", "at", "after-second", "every" }
assert(#schedulerOrder == #expectedSchedulerOrder, "All due Scheduler callbacks should run")
for index, expectedEvent in ipairs(expectedSchedulerOrder) do
	assert(schedulerOrder[index] == expectedEvent,
		"Callbacks with the same execution time should run in insertion order")
end
assert(periodicCount == 2, "Every() should run on each due simulation step")
assert(scheduler:Cancel(periodicId), "Every() should be cancellable by ID")
schedulerSimulation:Step()
assert(periodicCount == 2, "Cancelled Every() should stop running")

local mutationSimulation = Simulation.new(createRecordingWorld(), { FixedDeltaTime = 0.1 })
local mutationScheduler = mutationSimulation:GetScheduler()
local mutationOrder = {}
local cancelledDuringDispatchId
mutationScheduler:At(0.1, function()
	mutationScheduler:Cancel(cancelledDuringDispatchId)
	mutationScheduler:At(0.1, function()
		table.insert(mutationOrder, "created")
	end)
end)
cancelledDuringDispatchId = mutationScheduler:At(0.1, function()
	table.insert(mutationOrder, "cancelled")
end)
mutationSimulation:Step()
assert(#mutationOrder == 0, "A callback scheduled during dispatch should wait for the next step")
mutationSimulation:Step()
assert(#mutationOrder == 1 and mutationOrder[1] == "created",
	"Callbacks should be able to cancel pending events during dispatch")
mutationScheduler:At(0.3, function()
	error("Cleared event should not run")
end)
mutationScheduler:Clear()
mutationSimulation:Step()

local rngA = DeterministicRNG.new(12345)
local rngB = DeterministicRNG.new(12345)
local rngDifferentSeed = DeterministicRNG.new(54321)
local sequenceA = {}
local sequenceB = {}
local differentSeedSequence = {}
for _ = 1, 5 do
	table.insert(sequenceA, rngA:NextNumber())
	table.insert(sequenceB, rngB:NextNumber())
	table.insert(differentSeedSequence, rngDifferentSeed:NextNumber())
end

local equalSeedSequencesMatch = true
local differentSeedSequencesMatch = true
for index, value in ipairs(sequenceA) do
	if value ~= sequenceB[index] then
		equalSeedSequencesMatch = false
	end
	if value ~= differentSeedSequence[index] then
		differentSeedSequencesMatch = false
	end
	assert(value >= 0 and value < 1, "NextNumber() should return a value in [0, 1)")
end
assert(equalSeedSequencesMatch, "Equal seeds should produce identical RNG sequences")
assert(not differentSeedSequencesMatch,
	"Different seeds should produce different sequences for the selected seeds")

local stateRng = DeterministicRNG.new(998)
local savedState = stateRng:GetState()
local expectedAfterRestore = stateRng:NextInteger(1, 100)
stateRng:SetState(savedState)
assert(stateRng:NextInteger(1, 100) == expectedAfterRestore,
	"Restoring RNG state should restore the sequence")
local rangedNumber = stateRng:NextNumber(-2, 3)
assert(rangedNumber >= -2 and rangedNumber < 3, "Ranged NextNumber() should stay within bounds")
for _ = 1, 20 do
	local integer = stateRng:NextInteger(4, 9)
	assert(integer >= 4 and integer <= 9 and integer % 1 == 0,
		"NextInteger() should return an inclusive integer")
end

local customRng = DeterministicRNG.new(789)
local customRngSimulation = Simulation.new(createRecordingWorld(), { RNG = customRng })
assert(customRngSimulation:GetRNG() == customRng, "Simulation should accept a custom RNG instance")

local integrationOrder = {}
local integrationWorld = World.new()
local integrationEntity = integrationWorld:CreateEntity()
local integrationComponent = integrationEntity:AddComponent(StepCounter.new(function(deltaTime)
	assert(deltaTime == fixedDeltaTime, "Integrated component should receive FixedDeltaTime")
	table.insert(integrationOrder, "world")
end))
local integrationSimulation = Simulation.new(integrationWorld, {
	FixedDeltaTime = fixedDeltaTime,
	MaxStepsPerUpdate = 5,
	Seed = 123,
})
assert(integrationSimulation:GetWorld() == integrationWorld, "Simulation should expose its World")
integrationSimulation:GetScheduler():At(fixedDeltaTime, function()
	assert(integrationSimulation:GetGameTime():GetFrame() == 1,
		"GameTime should advance before Scheduler callbacks")
	assert(integrationSimulation:GetGameTime():GetTime() == fixedDeltaTime,
		"Scheduler should see the current simulated time")
	table.insert(integrationOrder, "scheduler")
end)

integrationSimulation:Step()
assert(#integrationOrder == 2 and integrationOrder[1] == "scheduler" and integrationOrder[2] == "world",
	"Fixed step order should be GameTime, Scheduler, then World")
assert(integrationSimulation:GetGameTime():GetFrame() == 1,
	"Manual Step() should advance exactly one GameTime frame")
assert(integrationSimulation:GetAlpha() == 0, "Manual Step() should not use the accumulator")
assert(integrationSimulation:GetRNG():NextInteger(1, 10) >= 1,
	"Simulation should expose its deterministic RNG")
integrationSimulation:Update(fixedDeltaTime * 2)
assert(integrationComponent.StepCount == 3, "Manual Step() and Update() should both step the World")
assert(integrationComponent.UpdateCount == 0, "Simulation should not call World:Update()")

local function createReplaySimulation()
	local replay = { Events = {}, ScheduledValues = {} }
	replay.World = World.new()
	replay.Entity = replay.World:CreateEntity()
	replay.Component = replay.Entity:AddComponent(StepCounter.new())
	replay.Simulation = Simulation.new(replay.World, {
		FixedDeltaTime = 0.1,
		MaxStepsPerUpdate = 5,
		Seed = 98765,
	})
	replay.Simulation:GetScheduler():At(0.2, function()
		table.insert(replay.Events, "at")
		table.insert(replay.ScheduledValues, replay.Simulation:GetRNG():NextInteger(1, 100000))
	end)
	replay.Simulation:GetScheduler():Every(0.1, function()
		table.insert(replay.Events, "every")
		table.insert(replay.ScheduledValues, replay.Simulation:GetRNG():NextInteger(1, 100000))
	end)
	return replay
end

local replayA = createReplaySimulation()
local replayB = createReplaySimulation()
assert(replayA.Entity.Id == replayB.Entity.Id, "Replay Worlds should begin in equivalent states")
for _ = 1, 5 do
	replayA.Simulation:Step()
	replayB.Simulation:Step()
end
assert(replayA.Simulation:GetGameTime():GetFrame() == replayB.Simulation:GetGameTime():GetFrame(),
	"Matching replays should end on the same GameTime frame")
assert(replayA.Simulation:GetGameTime():GetTime() == replayB.Simulation:GetGameTime():GetTime(),
	"Matching replays should end at the same simulated time")
assert(replayA.Simulation:GetGameTime():GetDeltaTime() == replayB.Simulation:GetGameTime():GetDeltaTime()
	and replayA.Simulation:GetGameTime():GetFixedDeltaTime()
		== replayB.Simulation:GetGameTime():GetFixedDeltaTime(),
	"Matching replays should end with the same GameTime deltas")
assert(#replayA.Events == #replayB.Events, "Matching replays should execute the same number of events")
for index, event in ipairs(replayA.Events) do
	assert(event == replayB.Events[index], "Matching replays should execute the same Scheduler events")
end
assert(#replayA.ScheduledValues == #replayB.ScheduledValues,
	"Matching replays should generate the same number of scheduled RNG values")
for index, value in ipairs(replayA.ScheduledValues) do
	assert(value == replayB.ScheduledValues[index], "Matching replays should produce identical RNG values")
end
assert(replayA.Simulation:GetRNG():GetState() == replayB.Simulation:GetRNG():GetState(),
	"Matching replays should end with the same RNG state")
assert(replayA.Component.StepCount == replayB.Component.StepCount and replayA.Component.StepCount == 5,
	"Matching replay Worlds should step their components equally")

print("Simulation infrastructure tests passed")
