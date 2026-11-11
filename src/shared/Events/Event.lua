local Event = {}
Event.__index = Event
local function project(value, seen)
	local valueType = type(value)
	if valueType ~= "table" then return value end
	if value.Id ~= nil then return value.Id end
	if getmetatable(value) ~= nil then
		if value.ComboId ~= nil then return value.ComboId end
		return nil
	end
	seen = seen or {}
	if seen[value] then return "<cycle>" end
	seen[value] = true
	local result = {}
	for key, nested in pairs(value) do
		local projected = project(nested, seen)
		if projected ~= nil and type(projected) ~= "function" then result[key] = projected end
	end
	seen[value] = nil
	return table.freeze(result)
end
function Event.new(eventType, payload, context)
	assert(type(eventType) == "string" and eventType ~= "", "Event Type is required")
	payload = payload or {}
	assert(type(payload) == "table", "Event Payload must be a table")
	local safePayload = {}
	for key, value in pairs(payload) do
		if type(value) ~= "function" and key ~= "Callback" then safePayload[key] = project(value) end
	end
	local frame = context and (context.SimulationFrame or context.Frame) or safePayload.Frame
	local event = {
		Type = eventType, SimulationFrame = frame, Frame = frame,
		SourceSystem = context and context.SourceSystem or "Unknown",
		EntityId = context and context.EntityId or safePayload.EntityId,
		Version = context and context.Version or 1,
		Sequence = context and context.Sequence,
		EventId = context and context.EventId,
		ExecutionMode = context and context.ExecutionMode or "Normal",
		Payload = table.freeze(safePayload), Context = context and context.APIContext,
	}
	for key, value in pairs(safePayload) do
		if event[key] == nil then event[key] = value end
	end
	return table.freeze(setmetatable(event, Event))
end
return Event
