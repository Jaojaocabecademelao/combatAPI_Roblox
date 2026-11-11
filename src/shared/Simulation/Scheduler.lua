local Scheduler = {}
Scheduler.__index = Scheduler
Scheduler.IsLegacyClosureScheduler = true

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

function Scheduler.new(gameTime)
	assert(gameTime and type(gameTime.GetTime) == "function",
		"Scheduler.new() requires a GameTime with GetTime()")

	local self = setmetatable({}, Scheduler)
	self.GameTime = gameTime
	self.Events = {}
	self.NextId = 0
	self.NextOrder = 0

	return self
end

function Scheduler:_Add(time, callback, tag, interval, originTime)
	if self.IsReplay and self:IsReplay() then
		error("Scheduler events cannot be created during rollback replay")
	end
	assert(isFiniteNumber(time) and time >= 0, "Scheduler event time must be finite and non-negative")
	assert(type(callback) == "function", "Scheduler callback must be a function")

	self.NextId += 1
	self.NextOrder += 1
	local event = {
		Id = self.NextId,
		Order = self.NextOrder,
		Time = time,
		Callback = callback,
		Tag = tag,
		Interval = interval,
		OriginTime = originTime,
		Occurrence = interval and 1 or nil,
	}
	self.Events[event.Id] = event

	return event.Id
end

function Scheduler:After(delay, callback, tag)
	assert(isFiniteNumber(delay) and delay >= 0, "Scheduler:After() delay must be finite and non-negative")
	return self:_Add(self.GameTime:GetTime() + delay, callback, tag)
end

function Scheduler:At(time, callback, tag)
	return self:_Add(time, callback, tag)
end

function Scheduler:Every(interval, callback, tag)
	assert(isFiniteNumber(interval) and interval > 0,
		"Scheduler:Every() interval must be finite and positive")
	local originTime = self.GameTime:GetTime()
	return self:_Add(originTime + interval, callback, tag, interval, originTime)
end

function Scheduler:Cancel(id)
	if not self.Events[id] then
		return false
	end

	self.Events[id] = nil
	return true
end

function Scheduler:CancelTag(tag)
	assert(tag ~= nil, "Scheduler:CancelTag() requires a tag")

	local cancelled = 0
	for id, event in pairs(self.Events) do
		if event.Tag == tag then
			self.Events[id] = nil
			cancelled += 1
		end
	end

	return cancelled
end

function Scheduler:Clear()
	table.clear(self.Events)
end

function Scheduler:HasPendingEvents()
	return next(self.Events) ~= nil
end

function Scheduler:Step()
	local currentTime = self.GameTime:GetTime()
	local dueEvents = {}

	for _, event in pairs(self.Events) do
		if event.Time <= currentTime then
			table.insert(dueEvents, event)
		end
	end

	table.sort(dueEvents, function(left, right)
		if left.Time == right.Time then
			return left.Order < right.Order
		end
		return left.Time < right.Time
	end)

	for _, event in ipairs(dueEvents) do
		if self.Events[event.Id] == event and event.Time <= currentTime then
			if event.Interval == nil then
				self.Events[event.Id] = nil
			end

			event.Callback()

			if event.Interval ~= nil and self.Events[event.Id] == event then
				event.Occurrence += 1
				event.Time = event.OriginTime + event.Occurrence * event.Interval
				self.NextOrder += 1
				event.Order = self.NextOrder
			end
		end
	end
end

return Scheduler
