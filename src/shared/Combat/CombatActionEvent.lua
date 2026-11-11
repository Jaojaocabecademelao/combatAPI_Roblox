local Event = {}
Event.__index = Event
Event.Type = table.freeze({
	Started = "ActionStarted", PhaseChanged = "ActionPhaseChanged",
	Cancelled = "ActionCancelled", Completed = "ActionCompleted",
})
function Event.new(data) return setmetatable(data, Event) end
return Event
