local StateSerializer = require(script.Parent.StateSerializer)
local FrameCommandBuffer = require(script.Parent.FrameCommandBuffer)
local DeterministicScheduler = require(script.Parent.DeterministicScheduler)

local SimulationState = {}
SimulationState.__index = SimulationState
SimulationState.Version = 1
local STATE_FIELDS = table.freeze({
	Version = true, Frame = true, FixedDeltaTime = true, MaxStepsPerUpdate = true,
	Accumulator = true, RNGState = true, Scheduler = true,
	DeterministicScheduler = true, FrameCommands = true,
})

local function hasOnlyKeys(value, allowed)
	for key in pairs(value) do
		if type(key) ~= "string" or not allowed[key] then return false end
	end
	return true
end

local function validInteger(value, minimum)
	return type(value) == "number" and value == value and value < math.huge
		and value % 1 == 0 and value >= minimum
end

local function validFinite(value)
	return StateSerializer.IsFiniteNumber(value)
end

function SimulationState.new(data)
	assert(type(data) == "table", "SimulationState.new() requires a data table")
	assert(getmetatable(data) == nil and hasOnlyKeys(data, STATE_FIELDS),
		"SimulationState must be a plain table with only schema fields")
	assert(data.Version == SimulationState.Version, "Unsupported SimulationState version")
	assert(validInteger(data.Frame, 0), "SimulationState frame must be a non-negative integer")
	assert(validFinite(data.FixedDeltaTime) and data.FixedDeltaTime > 0,
		"SimulationState FixedDeltaTime must be finite and positive")
	assert(validFinite(data.Frame * data.FixedDeltaTime), "SimulationState time exceeds the supported range")
	assert(validFinite(data.MaxStepsPerUpdate) and data.MaxStepsPerUpdate > 0
		and data.MaxStepsPerUpdate % 1 == 0, "SimulationState MaxStepsPerUpdate must be a positive integer")
	assert(validFinite(data.Accumulator) and data.Accumulator >= 0,
		"SimulationState accumulator must be finite and non-negative")
	assert(validFinite(data.Accumulator / data.FixedDeltaTime),
		"SimulationState backlog exceeds the supported range")
	assert(data.RNGState ~= nil, "SimulationState RNGState is required")
	assert(type(data.Scheduler) == "table" and getmetatable(data.Scheduler) == nil
		and hasOnlyKeys(data.Scheduler, { NextId = true, NextOrder = true })
		and validInteger(data.Scheduler.NextId, 0)
		and validInteger(data.Scheduler.NextOrder, 0)
		and data.Scheduler.NextId == 0 and data.Scheduler.NextOrder == 0,
		"SimulationState legacy Scheduler counters must be zero")
	assert(type(data.DeterministicScheduler) == "table" and type(data.FrameCommands) == "table",
		"SimulationState deterministic queues are required")
	local commandValidator = FrameCommandBuffer.new()
	local commandsValid, commandError = commandValidator:ValidateState(data.FrameCommands)
	assert(commandsValid, "SimulationState frame command state is invalid: " .. tostring(commandError))
	local schedulerState = data.DeterministicScheduler
	assert(type(schedulerState.Events) == "table", "SimulationState deterministic scheduler events are invalid")
	local schedulerValidator = DeterministicScheduler.new()
	for _, event in ipairs(schedulerState.Events) do
		if type(event) == "table" and type(event.Type) == "string"
			and schedulerValidator.Handlers[event.Type] == nil then
			schedulerValidator:RegisterHandler(event.Type, function() end)
		end
	end
	local schedulerValid, schedulerError = schedulerValidator:ValidateState(schedulerState)
	assert(schedulerValid, "SimulationState deterministic scheduler state is invalid: " .. tostring(schedulerError))
	assert(data.FrameCommands.LastConsumedFrame == data.Frame
		and schedulerState.CurrentFrame == data.Frame,
		"SimulationState queues must be aligned to the state frame")
	local copy = StateSerializer.CloneSerializable(data)
	return StateSerializer.Freeze(copy)
end

return table.freeze(SimulationState)
