--!strict

local Types = require(script.Parent.Parent.CombatAPITypes)

local Event = {}
Event.__index = Event

export type Envelope = Types.Event

local function isRecursivelyFrozen(value: any, seen: { [any]: boolean }?): boolean
	if type(value) ~= "table" then return true end
	if not table.isfrozen(value) then return false end
	seen = seen or {}
	if seen[value] then return true end
	seen[value] = true
	for key, nested in pairs(value) do
		if not isRecursivelyFrozen(key, seen) or not isRecursivelyFrozen(nested, seen) then
			return false
		end
	end
	return true
end

local function project(value: any, seen: { [any]: boolean }?): any
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

function Event.new(
	eventType: string,
	payload: { [string]: any }?,
	context: { [string]: any }?
): Envelope
	assert(type(eventType) == "string" and eventType ~= "", "Event Type is required")
	payload = payload or {}
	assert(type(payload) == "table", "Event Payload must be a table")
	local safePayload: { [string]: any } = {}
	for key, value in pairs(payload) do
		if type(value) ~= "function" and key ~= "Callback" then
			-- CustomData is an opaque API-owned value. Preserve its frozen reference
			-- instead of projecting keys such as "Id" as entity references.
			if key == "CustomData" and type(value) == "table" and isRecursivelyFrozen(value) then
				safePayload[key] = value
			else
				safePayload[key] = project(value)
			end
		end
	end
	local frame = context and (context.SimulationFrame or context.Frame) or safePayload.Frame
	local event: { [string]: any } = {
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
	return table.freeze(setmetatable(event, Event)) :: Envelope
end
return Event
