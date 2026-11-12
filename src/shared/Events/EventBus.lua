--!strict

local Types = require(script.Parent.Parent.CombatAPITypes)
local Event = require(script.Parent.Event)
local EventFilter = require(script.Parent.EventFilter)
local EventSubscription = require(script.Parent.EventSubscription)
local APIError = require(script.Parent.APIError)

type APIErrorType = Types.APIError
type EventType = Types.Event
type EventBusType = Types.EventBus
type EventCallback = Types.EventCallback
type EventFilterInstance = Types.EventFilter
type EventFilterOptions = Types.EventFilterOptions
type EventSubscriptionOptions = Types.EventSubscriptionOptions
type EventSubscriptionType = Types.EventSubscription
type EventSubscriptionConnection = EventSubscription.Connection

type Listener = {
	Id: number,
	Order: number,
	Priority: number,
	Callback: EventCallback,
	Filter: EventFilterInstance,
	Connected: boolean,
	EventType: string,
}

type Bus = EventBusType & {
	Context: any,
	Listeners: { [number]: Listener },
	ByType: { [string]: { Listener } },
	NextId: number,
	NextOrder: number,
	Errors: { APIErrorType },
	Destroyed: boolean,
	DispatchDepth: number,
	_Disconnect: (self: Bus, id: number) -> boolean,
}

local EventBus = {}
EventBus.__index = EventBus

export type Instance = Bus

local function listenerOrder(a: Listener, b: Listener): boolean
	if a.Priority ~= b.Priority then return a.Priority > b.Priority end
	return a.Order < b.Order
end

function EventBus.new(context: any): Bus
	return setmetatable({
		Context = context,
		Listeners = {},
		ByType = {},
		NextId = 0,
		NextOrder = 0,
		Errors = {},
		Destroyed = false,
		DispatchDepth = 0,
	}, EventBus) :: Bus
end

function EventBus.Subscribe(
	self: Bus,
	eventType: string,
	callback: EventCallback,
	options: EventSubscriptionOptions?
): (EventSubscriptionType?, APIErrorType?)
	if self.Destroyed then
		return nil, APIError.new(APIError.Code.Destroyed, "EventBus is destroyed", "Events")
	end
	if type(eventType) ~= "string" or eventType == "" or type(callback) ~= "function" then
		return nil, APIError.new(APIError.Code.InvalidArgument, "Subscribe requires an event type and callback", "Events")
	end
	options = options or {}
	if type(options) ~= "table" or (options.Priority ~= nil and (type(options.Priority) ~= "number"
		or options.Priority ~= options.Priority or options.Priority == math.huge or options.Priority == -math.huge)) then
		return nil, APIError.new(APIError.Code.InvalidArgument, "Subscription options are invalid", "Events")
	end
	local filterOptions: EventFilterOptions = options.Filter or options
	local ok, filterResult = pcall(EventFilter.new, filterOptions)
	if not ok then
		return nil, APIError.new(APIError.Code.InvalidArgument, tostring(filterResult), "Events")
	end
	local filter: EventFilterInstance = filterResult

	self.NextId += 1
	self.NextOrder += 1
	local entry: Listener = {
		Id = self.NextId,
		Order = self.NextOrder,
		Priority = options.Priority or 0,
		Callback = callback,
		Filter = filter,
		Connected = true,
		EventType = eventType,
	}
	self.Listeners[entry.Id] = entry
	local list = self.ByType[eventType]
	if not list then
		list = {}
		self.ByType[eventType] = list
	end
	table.insert(list, entry)
	table.sort(list, listenerOrder)
	return EventSubscription.new(self, entry.Id)
end

function EventBus._Disconnect(self: Bus, id: number): boolean
	local entry = self.Listeners[id]
	if not entry then return false end
	entry.Connected = false
	self.Listeners[id] = nil
	local list = self.ByType[entry.EventType]
	if list then
		for index, registered in ipairs(list) do
			if registered == entry then
				table.remove(list, index)
				break
			end
		end
		if #list == 0 then self.ByType[entry.EventType] = nil end
	end
	return true
end

function EventBus.Unsubscribe(self: Bus, id: any): boolean
	if type(id) ~= "number" then return false end
	return self:_Disconnect(id)
end

function EventBus.Dispatch(
	self: Bus,
	eventType: string,
	payload: { [string]: any }?,
	context: { [string]: any }?
): (EventType?, APIErrorType?)
	if self.Destroyed then
		return nil, APIError.new(APIError.Code.Destroyed, "EventBus is destroyed", "Events")
	end
	local event = Event.new(eventType, payload, context)
	local registered = self.ByType[eventType]
	if not registered then return event end
	local listeners = table.clone(registered)
	self.DispatchDepth += 1
	for _, entry in ipairs(listeners) do
		if entry.Connected and self.Listeners[entry.Id] == entry and entry.Filter:Matches(event) then
			local ok, failure = pcall(entry.Callback, event, self.Context)
			if not ok then
				table.insert(self.Errors, APIError.new(
					APIError.Code.InternalError,
					tostring(failure),
					"Events",
					event.Frame,
					{ ListenerId = entry.Id, EventType = eventType }
				))
			end
		end
	end
	self.DispatchDepth -= 1
	return event
end

function EventBus.GetErrors(self: Bus): { APIErrorType }
	local result: { APIErrorType } = {}
	for _, err in ipairs(self.Errors) do table.insert(result, err) end
	return result
end

function EventBus.ClearErrors(self: Bus): Bus
	table.clear(self.Errors)
	return self
end

function EventBus.Destroy(self: Bus): boolean
	if self.Destroyed then return false end
	self.Destroyed = true
	for _, entry in pairs(self.Listeners) do entry.Connected = false end
	table.clear(self.Listeners)
	table.clear(self.ByType)
	table.clear(self.Errors)
	return true
end

return EventBus
