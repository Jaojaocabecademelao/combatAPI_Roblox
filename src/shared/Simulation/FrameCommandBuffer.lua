local StateSerializer = require(script.Parent.StateSerializer)

local FrameCommandBuffer = {}
FrameCommandBuffer.__index = FrameCommandBuffer

local VERSION = 1
local DEFAULT_MAX_COMMANDS_PER_FRAME = 4096
local DEFAULT_HISTORY_SIZE = 120
local COMMAND_FIELDS = table.freeze({
	ProtocolVersion = true, CommandId = true, SessionId = true, EntityId = true,
	Frame = true, Sequence = true, Type = true, Payload = true,
})
local STATE_FIELDS = table.freeze({
	Version = true, MaxCommandsPerFrame = true, HistorySize = true,
	LastConsumedFrame = true, OldestRetainedFrame = true, AcceptedCount = true, Commands = true,
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

local function validEntityId(value)
	return (type(value) == "string" and #value > 0 and #value <= 128)
		or StateSerializer.IsFiniteNumber(value)
end

local function idLess(left, right)
	local leftType, rightType = type(left), type(right)
	if leftType ~= rightType then return leftType < rightType end
	if leftType == "number" or leftType == "string" then return left < right end
	return false
end

local function commandLess(left, right)
	if left.EntityId ~= right.EntityId then return idLess(left.EntityId, right.EntityId) end
	if left.Sequence ~= right.Sequence then return left.Sequence < right.Sequence end
	return left.CommandId < right.CommandId
end

local function normalize(data)
	assert(type(data) == "table", "Frame command must be a table")
	assert(getmetatable(data) == nil, "Frame command must be a plain table")
	assert(hasOnlyKeys(data, COMMAND_FIELDS), "Frame command contains an unknown field")
	assert(data.ProtocolVersion == VERSION, "Unsupported frame command protocol version")
	assert(type(data.CommandId) == "string" and #data.CommandId > 0 and #data.CommandId <= 128,
		"Frame command CommandId must be a non-empty string of at most 128 bytes")
	assert(type(data.SessionId) == "string" and #data.SessionId > 0 and #data.SessionId <= 128,
		"Frame command SessionId must be a non-empty string of at most 128 bytes")
	assert(validEntityId(data.EntityId), "Frame command EntityId must be a stable string or finite number")
	assert(validInteger(data.Frame, 1), "Frame command Frame must be a positive integer")
	assert(validInteger(data.Sequence, 0), "Frame command Sequence must be a non-negative integer")
	assert(type(data.Type) == "string" and #data.Type > 0 and #data.Type <= 96,
		"Frame command Type must be a non-empty string of at most 96 bytes")
	assert(data.Payload == nil or type(data.Payload) == "table",
		"Frame command Payload must be a serializable table or nil")
	local command = {
		ProtocolVersion = VERSION,
		CommandId = data.CommandId,
		SessionId = data.SessionId,
		EntityId = data.EntityId,
		Frame = data.Frame,
		Sequence = data.Sequence,
		Type = data.Type,
		Payload = StateSerializer.CloneSerializable(data.Payload or {}),
	}
	return StateSerializer.Freeze(command)
end

local function makeFrameCopy(records)
	local commands = {}
	for _, record in ipairs(records or {}) do table.insert(commands, record.Command) end
	table.sort(commands, commandLess)
	return table.freeze(commands)
end

local function insertRecord(target, command)
	local ok, canonical = pcall(StateSerializer.Serialize, command)
	if not ok then return false, tostring(canonical) end
	local existing = target.ById[command.CommandId]
	if existing then
		if existing.Canonical == canonical then return false, "Duplicate command ID" end
		return false, "Conflicting command ID"
	end
	local records = target.CommandsByFrame[command.Frame]
	if not records then
		records = {}
		target.CommandsByFrame[command.Frame] = records
	end
	if #records >= target.MaxCommandsPerFrame then return false, "Per-frame command limit exceeded" end
	local record = { Command = command, Canonical = canonical }
	table.insert(records, record)
	target.ById[command.CommandId] = record
	return true
end

local function buildState(state)
	local arrayCount = 0
	for key in pairs(state.Commands) do
		if not validInteger(key, 1) then return nil, "Frame command state must be a dense array" end
		arrayCount += 1
	end
	if arrayCount ~= #state.Commands then return nil, "Frame command state must be a dense array" end
	for index = 1, arrayCount do
		if state.Commands[index] == nil then return nil, "Frame command state contains a hole" end
	end
	local temporary = FrameCommandBuffer.new({
		MaxCommandsPerFrame = state.MaxCommandsPerFrame,
		HistorySize = state.HistorySize,
	})
	temporary.LastConsumedFrame = state.LastConsumedFrame
	temporary.OldestRetainedFrame = state.OldestRetainedFrame
	for _, rawCommand in ipairs(state.Commands) do
		local ok, command = pcall(normalize, rawCommand)
		if not ok then return nil, tostring(command) end
		if command.Frame < state.OldestRetainedFrame then return nil, "Command precedes retained history" end
		local inserted, detail = insertRecord(temporary, command)
		if not inserted then return nil, detail end
		temporary.AcceptedCount += 1
	end
	if temporary.AcceptedCount > state.AcceptedCount then return nil, "Command count is inconsistent" end
	return temporary
end

function FrameCommandBuffer.new(options)
	if options == nil then options = {} end
	assert(type(options) == "table", "FrameCommandBuffer options must be a table")
	local maximum = options.MaxCommandsPerFrame
	if maximum == nil then maximum = DEFAULT_MAX_COMMANDS_PER_FRAME end
	local historySize = options.HistorySize
	if historySize == nil then historySize = DEFAULT_HISTORY_SIZE end
	assert(validInteger(maximum, 1), "MaxCommandsPerFrame must be a positive integer")
	assert(validInteger(historySize, 1), "HistorySize must be a positive integer")
	return setmetatable({
		MaxCommandsPerFrame = maximum,
		HistorySize = historySize,
		CommandsByFrame = {},
		ById = {},
		LastConsumedFrame = 0,
		OldestRetainedFrame = 1,
		AcceptedCount = 0,
	}, FrameCommandBuffer)
end

function FrameCommandBuffer:Push(data)
	local ok, commandOrError = pcall(normalize, data)
	if not ok then return nil, "InvalidCommand", tostring(commandOrError) end
	local command = commandOrError
	local serialized, canonical = pcall(StateSerializer.Serialize, command)
	if not serialized then return nil, "InvalidCommand", tostring(canonical) end
	local existing = self.ById[command.CommandId]
	if existing then
		if existing.Canonical == canonical then return existing.Command, false, "Duplicate" end
		return nil, "CommandIdConflict", "CommandId already belongs to different command data"
	end
	if command.Frame <= self.LastConsumedFrame then
		return nil, "FrameAlreadyConsumed", "Late commands require the rollback input path"
	end
	local frameRecords = self.CommandsByFrame[command.Frame]
	if not frameRecords then
		frameRecords = {}
		self.CommandsByFrame[command.Frame] = frameRecords
	end
	if #frameRecords >= self.MaxCommandsPerFrame then
		return nil, "FrameCapacityExceeded", "Frame command limit reached"
	end
	local record = { Command = command, Canonical = canonical }
	table.insert(frameRecords, record)
	self.ById[command.CommandId] = record
	self.AcceptedCount += 1
	return command, true
end

function FrameCommandBuffer:GetFrame(frame)
	assert(validInteger(frame, 0), "FrameCommandBuffer:GetFrame() expects a non-negative integer")
	return makeFrameCopy(self.CommandsByFrame[frame])
end

function FrameCommandBuffer:ConsumeFrame(frame)
	assert(validInteger(frame, 1) and frame == self.LastConsumedFrame + 1,
		"FrameCommandBuffer:ConsumeFrame() requires the next sequential frame")
	local commands = self:GetFrame(frame)
	self.LastConsumedFrame = frame
	local firstRetained = math.max(1, frame - self.HistorySize + 1)
	self:PruneBeforeFrame(firstRetained)
	return commands
end

function FrameCommandBuffer:Remove(commandId)
	local record = self.ById[commandId]
	if not record then return false end
	local frame = record.Command.Frame
	if frame <= self.LastConsumedFrame then return false end
	local records = self.CommandsByFrame[frame]
	for index, candidate in ipairs(records) do
		if candidate == record then table.remove(records, index); break end
	end
	if #records == 0 then self.CommandsByFrame[frame] = nil end
	self.ById[commandId] = nil
	return true
end

local function collectCommands(self, pendingOnly)
	local frames = {}
	for frame in pairs(self.CommandsByFrame) do
		if not pendingOnly or frame > self.LastConsumedFrame then table.insert(frames, frame) end
	end
	table.sort(frames)
	local commands = {}
	for _, frame in ipairs(frames) do
		for _, command in ipairs(self:GetFrame(frame)) do table.insert(commands, command) end
	end
	return table.freeze(commands)
end

function FrameCommandBuffer:GetPendingCommands()
	return collectCommands(self, true)
end

function FrameCommandBuffer:GetHistoryCommands()
	return collectCommands(self, false)
end

function FrameCommandBuffer:GetPendingCount()
	local count = 0
	for frame, records in pairs(self.CommandsByFrame) do
		if frame > self.LastConsumedFrame then count += #records end
	end
	return count
end

function FrameCommandBuffer:GetAcceptedCount()
	return self.AcceptedCount
end

function FrameCommandBuffer:CanReplayFrom(frame)
	return validInteger(frame, 0) and frame >= self.OldestRetainedFrame - 1
end

function FrameCommandBuffer:PruneBeforeFrame(firstFrameToKeep)
	assert(validInteger(firstFrameToKeep, 1), "PruneBeforeFrame() expects a positive frame")
	if firstFrameToKeep <= self.OldestRetainedFrame then return 0 end
	local removed = 0
	for frame, records in pairs(self.CommandsByFrame) do
		if frame < firstFrameToKeep then
			for _, record in ipairs(records) do
				self.ById[record.Command.CommandId] = nil
				removed += 1
			end
			self.CommandsByFrame[frame] = nil
		end
	end
	self.OldestRetainedFrame = firstFrameToKeep
	return removed
end

function FrameCommandBuffer:RewindConsumption(frame)
	assert(validInteger(frame, 0) and frame <= self.LastConsumedFrame,
		"RewindConsumption() expects a prior consumed frame")
	if not self:CanReplayFrom(frame) then
		return false
	end
	self.LastConsumedFrame = frame
	return true
end

function FrameCommandBuffer:ResetFrame(frame)
	assert(validInteger(frame, 0), "ResetFrame() expects a non-negative integer")
	assert(self.AcceptedCount == 0 and next(self.CommandsByFrame) == nil,
		"Cannot reset frame while command history exists")
	self.LastConsumedFrame = frame
	self.OldestRetainedFrame = math.max(1, frame + 1)
	return true
end

function FrameCommandBuffer:Clear()
	table.clear(self.CommandsByFrame)
	table.clear(self.ById)
	self.OldestRetainedFrame = math.max(1, self.LastConsumedFrame + 1)
	-- Keep the frame cursor and lifetime acceptance counter for Simulation alignment/rollback safety.
end

function FrameCommandBuffer:CaptureState()
	local commands = {}
	for _, command in ipairs(self:GetHistoryCommands()) do
		table.insert(commands, StateSerializer.CloneSerializable(command))
	end
	return {
		Version = VERSION,
		MaxCommandsPerFrame = self.MaxCommandsPerFrame,
		HistorySize = self.HistorySize,
		LastConsumedFrame = self.LastConsumedFrame,
		OldestRetainedFrame = self.OldestRetainedFrame,
		AcceptedCount = self.AcceptedCount,
		Commands = commands,
	}
end

function FrameCommandBuffer:ValidateState(state)
	if type(state) ~= "table" or getmetatable(state) ~= nil or not hasOnlyKeys(state, STATE_FIELDS)
		or state.Version ~= VERSION
		or not validInteger(state.MaxCommandsPerFrame, 1)
		or not validInteger(state.HistorySize, 1)
		or not validInteger(state.LastConsumedFrame, 0)
			or not validInteger(state.OldestRetainedFrame, 1)
			or not validInteger(state.AcceptedCount, 0)
			or type(state.Commands) ~= "table" or getmetatable(state.Commands) ~= nil then
		return false, "Invalid frame command buffer state"
	end
	if state.OldestRetainedFrame > state.LastConsumedFrame + 1 then
		return false, "Frame command history boundary is invalid"
	end
	local temporary, detail = buildState(state)
	if not temporary then return false, detail end
	if temporary.AcceptedCount > state.AcceptedCount then return false, "Command count is inconsistent" end
	local count = 0
	for _, records in pairs(temporary.CommandsByFrame) do count += #records end
	if count ~= #state.Commands then return false, "Frame command state contains non-array entries" end
	return true
end

function FrameCommandBuffer:RestoreState(state)
	local valid, detail = self:ValidateState(state)
	if not valid then return false, detail end
	local temporary, buildError = buildState(state)
	if not temporary then return false, buildError end
	temporary.AcceptedCount = state.AcceptedCount
	self.MaxCommandsPerFrame = temporary.MaxCommandsPerFrame
	self.HistorySize = temporary.HistorySize
	self.CommandsByFrame = temporary.CommandsByFrame
	self.ById = temporary.ById
	self.LastConsumedFrame = temporary.LastConsumedFrame
	self.OldestRetainedFrame = temporary.OldestRetainedFrame
	self.AcceptedCount = temporary.AcceptedCount
	return true
end

FrameCommandBuffer.ProtocolVersion = VERSION
FrameCommandBuffer.StateVersion = VERSION
return table.freeze(FrameCommandBuffer)
