local StateSerializer = require(script.Parent.StateSerializer)

local DeterministicScheduler = {}
DeterministicScheduler.__index = DeterministicScheduler

local STATE_VERSION = 1
local DEFAULT_MAX_EVENTS = 10000
local EVENT_FIELDS = table.freeze({
	Id = true, Frame = true, Type = true, OwnerId = true,
	Parameters = true, Order = true, IntervalFrames = true,
})
local STATE_FIELDS = table.freeze({
	Version = true, CurrentFrame = true, NextId = true, NextOrder = true,
	MaxEvents = true, Events = true,
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

local function validOwnerId(value)
	return value == nil or (type(value) == "string" and #value > 0 and #value <= 128)
		or StateSerializer.IsFiniteNumber(value)
end

local function eventLess(left, right)
	if left.Frame ~= right.Frame then return left.Frame < right.Frame end
	if left.Order ~= right.Order then return left.Order < right.Order end
	return left.Id < right.Id
end

local function freezeEvent(data)
	return StateSerializer.Freeze({
		Id = data.Id,
		Frame = data.Frame,
		Type = data.Type,
		OwnerId = data.OwnerId,
		Parameters = StateSerializer.CloneSerializable(data.Parameters or {}),
		Order = data.Order,
		IntervalFrames = data.IntervalFrames,
	})
end

function DeterministicScheduler.new(options)
	if options == nil then options = {} end
	assert(type(options) == "table", "DeterministicScheduler options must be a table")
	local currentFrame = options.CurrentFrame
	if currentFrame == nil then currentFrame = 0 end
	local maximum = options.MaxEvents
	if maximum == nil then maximum = DEFAULT_MAX_EVENTS end
	assert(validInteger(currentFrame, 0), "DeterministicScheduler CurrentFrame must be a non-negative integer")
	assert(validInteger(maximum, 1), "DeterministicScheduler MaxEvents must be a positive integer")
	return setmetatable({
		CurrentFrame = currentFrame,
		MaxEvents = maximum,
		NextId = 0,
		NextOrder = 0,
		Handlers = {},
		EventsById = {},
	}, DeterministicScheduler)
end

function DeterministicScheduler:RegisterHandler(typeId, handler)
	assert(type(typeId) == "string" and #typeId > 0 and #typeId <= 96,
		"DeterministicScheduler handler type must be a non-empty string")
	assert(type(handler) == "function", "DeterministicScheduler handler must be a function")
	if self.Handlers[typeId] then return false, "HandlerAlreadyRegistered" end
	self.Handlers[typeId] = handler
	return true
end

function DeterministicScheduler:Schedule(frame, typeId, ownerId, parameters, intervalFrames)
	if self.ScheduleGuard and not self.ScheduleGuard() then
		error("Deterministic Scheduler scheduling is unavailable outside Normal execution")
	end
	assert(validInteger(frame, self.CurrentFrame + 1),
		"DeterministicScheduler event frame must be after CurrentFrame")
	assert(type(typeId) == "string" and self.Handlers[typeId] ~= nil,
		"DeterministicScheduler event type must have a registered handler")
	assert(validOwnerId(ownerId), "DeterministicScheduler owner ID must be a stable string or finite number")
	assert(parameters == nil or type(parameters) == "table",
		"DeterministicScheduler parameters must be a table or nil")
	assert(intervalFrames == nil or validInteger(intervalFrames, 1),
		"DeterministicScheduler interval must be a positive integer number of frames")
	local copiedParameters = StateSerializer.CloneSerializable(parameters or {})
	StateSerializer.Serialize(copiedParameters)
	local count = 0
	for _ in pairs(self.EventsById) do count += 1 end
	assert(count < self.MaxEvents, "DeterministicScheduler event limit reached")
	self.NextId += 1
	self.NextOrder += 1
	local event = freezeEvent({
		Id = self.NextId,
		Frame = frame,
		Type = typeId,
		OwnerId = ownerId,
		Parameters = copiedParameters,
		Order = self.NextOrder,
		IntervalFrames = intervalFrames,
	})
	self.EventsById[event.Id] = event
	return event.Id
end

function DeterministicScheduler:Cancel(eventId)
	if not self.EventsById[eventId] then return false end
	self.EventsById[eventId] = nil
	return true
end

function DeterministicScheduler:CancelOwner(ownerId)
	assert(validOwnerId(ownerId) and ownerId ~= nil, "CancelOwner() requires an owner ID")
	local cancelled = 0
	for id, event in pairs(self.EventsById) do
		if event.OwnerId == ownerId then
			self.EventsById[id] = nil
			cancelled += 1
		end
	end
	return cancelled
end

function DeterministicScheduler:Clear()
	table.clear(self.EventsById)
end

function DeterministicScheduler:HasPendingEvents()
	return next(self.EventsById) ~= nil
end

function DeterministicScheduler:GetPendingEvents()
	local events = {}
	for _, event in pairs(self.EventsById) do table.insert(events, event) end
	table.sort(events, eventLess)
	return table.freeze(events)
end

function DeterministicScheduler:Step(frame)
	assert(validInteger(frame, 1) and frame == self.CurrentFrame + 1,
		"DeterministicScheduler:Step() requires the next sequential frame")
	self.CurrentFrame = frame
	local due = {}
	for _, event in pairs(self.EventsById) do
		if event.Frame <= frame then table.insert(due, event) end
	end
	table.sort(due, eventLess)
	for _, event in ipairs(due) do
		if self.EventsById[event.Id] == event then
			if event.IntervalFrames == nil then self.EventsById[event.Id] = nil end
			local handler = self.Handlers[event.Type]
			assert(handler, ("No deterministic scheduler handler registered for %s"):format(event.Type))
			handler(event)
			if event.IntervalFrames ~= nil and self.EventsById[event.Id] == event then
				self.NextOrder += 1
				self.EventsById[event.Id] = freezeEvent({
					Id = event.Id,
					Frame = event.Frame + event.IntervalFrames,
					Type = event.Type,
					OwnerId = event.OwnerId,
					Parameters = event.Parameters,
					Order = self.NextOrder,
					IntervalFrames = event.IntervalFrames,
				})
			end
		end
	end
	return #due
end

function DeterministicScheduler:ResetFrame(frame)
	assert(validInteger(frame, 0), "ResetFrame() expects a non-negative integer")
	assert(self.NextId == 0 and not self:HasPendingEvents(),
		"Cannot reset Scheduler frame after scheduling deterministic events")
	self.CurrentFrame = frame
	return true
end

function DeterministicScheduler:CaptureState()
	local events = {}
	for _, event in ipairs(self:GetPendingEvents()) do
		table.insert(events, StateSerializer.CloneSerializable(event))
	end
	return {
		Version = STATE_VERSION,
		CurrentFrame = self.CurrentFrame,
		NextId = self.NextId,
		NextOrder = self.NextOrder,
		MaxEvents = self.MaxEvents,
		Events = events,
	}
end

function DeterministicScheduler:ValidateState(state)
	if type(state) ~= "table" or getmetatable(state) ~= nil or not hasOnlyKeys(state, STATE_FIELDS)
		or state.Version ~= STATE_VERSION
		or not validInteger(state.CurrentFrame, 0)
		or not validInteger(state.NextId, 0)
			or not validInteger(state.NextOrder, 0)
			or not validInteger(state.MaxEvents, 1)
			or type(state.Events) ~= "table" or getmetatable(state.Events) ~= nil then
		return false, "Invalid deterministic scheduler state"
	end
	local eventCount = 0
	for key in pairs(state.Events) do
		if not validInteger(key, 1) then return false, "Scheduler events must be a dense array" end
		eventCount += 1
	end
	if eventCount ~= #state.Events then return false, "Scheduler events must be a dense array" end
	for index = 1, eventCount do
		if state.Events[index] == nil then return false, "Scheduler events contain a hole" end
	end
	if #state.Events > state.MaxEvents then return false, "Scheduler event limit exceeded" end
	if state.NextOrder < state.NextId then return false, "Scheduler counters are inconsistent" end
	local seenIds, seenOrders = {}, {}
	for _, event in ipairs(state.Events) do
		if type(event) ~= "table" or getmetatable(event) ~= nil or not hasOnlyKeys(event, EVENT_FIELDS)
			or not validInteger(event.Id, 1)
			or not validInteger(event.Frame, state.CurrentFrame + 1)
			or type(event.Type) ~= "string" or not self.Handlers[event.Type]
			or not validOwnerId(event.OwnerId)
			or not validInteger(event.Order, 1)
			or (event.IntervalFrames ~= nil and not validInteger(event.IntervalFrames, 1))
			or (event.Parameters ~= nil and type(event.Parameters) ~= "table") then
			return false, "Invalid or unregistered deterministic event"
		end
		if seenIds[event.Id] or seenOrders[event.Order] then return false, "Duplicate scheduler ID/order" end
		if event.Id > state.NextId or event.Order > state.NextOrder then
			return false, "Scheduler counters precede a pending event"
		end
		seenIds[event.Id], seenOrders[event.Order] = true, true
		local ok = pcall(StateSerializer.Serialize, event)
		if not ok then return false, "Scheduler event is not serializable" end
	end
	return true
end

function DeterministicScheduler:RestoreState(state)
	local valid, detail = self:ValidateState(state)
	if not valid then return false, detail end
	local replacement = {}
	for _, event in ipairs(state.Events) do replacement[event.Id] = freezeEvent(event) end
	self.CurrentFrame = state.CurrentFrame
	self.NextId = state.NextId
	self.NextOrder = state.NextOrder
	self.MaxEvents = state.MaxEvents
	self.EventsById = replacement
	return true
end

DeterministicScheduler.StateVersion = STATE_VERSION
return table.freeze(DeterministicScheduler)
