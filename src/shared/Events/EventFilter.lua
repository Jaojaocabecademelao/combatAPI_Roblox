local EventFilter = {}
EventFilter.__index = EventFilter
function EventFilter.new(options)
	options = options or {}
	assert(type(options) == "table", "EventFilter.new() expects options")
	assert(options.EntityId == nil or type(options.EntityId) == "number" or type(options.EntityId) == "string",
		"EventFilter EntityId must be a string, number, or nil")
	assert(options.SourceSystem == nil or type(options.SourceSystem) == "string", "SourceSystem must be a string")
	assert(options.AttackerId == nil or type(options.AttackerId) == "number" or type(options.AttackerId) == "string",
		"AttackerId must be a string, number, or nil")
	assert(options.DefenderId == nil or type(options.DefenderId) == "number" or type(options.DefenderId) == "string",
		"DefenderId must be a string, number, or nil")
	assert(options.Predicate == nil or type(options.Predicate) == "function", "Predicate must be a function")
	return setmetatable({ EntityId = options.EntityId, SourceSystem = options.SourceSystem,
		AttackerId = options.AttackerId, DefenderId = options.DefenderId, Predicate = options.Predicate }, EventFilter)
end
function EventFilter:Matches(event)
	if self.EntityId ~= nil and event.EntityId ~= self.EntityId then return false end
	if self.SourceSystem ~= nil and event.SourceSystem ~= self.SourceSystem then return false end
	local payload = event.Payload
	if self.AttackerId ~= nil and (not payload or payload.AttackerId ~= self.AttackerId) then return false end
	if self.DefenderId ~= nil and (not payload or payload.DefenderId ~= self.DefenderId) then return false end
	if self.Predicate ~= nil then
		local ok, matches = pcall(self.Predicate, event)
		return ok and matches == true
	end
	return true
end
return EventFilter
