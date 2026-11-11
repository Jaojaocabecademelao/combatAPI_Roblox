local Event = {}
Event.__index = Event

Event.Type = table.freeze({
	Requested = "RollbackRequested",
	Started = "RollbackStarted",
	Restoring = "RollbackRestoring",
	ReplayStarted = "RollbackReplayStarted",
	ReplayFrame = "RollbackReplayFrame",
	Completed = "RollbackCompleted",
	Failed = "RollbackFailed",
	Cancelled = "RollbackCancelled",
})

function Event.new(data)
	assert(type(data) == "table", "RollbackEvent.new() expects a table")
	return setmetatable({
		Type = data.Type,
		Frame = data.Frame,
		FromFrame = data.FromFrame,
		ToFrame = data.ToFrame,
		EntityId = data.EntityId,
		Reason = data.Reason,
		Result = data.Result,
		ExecutionContext = data.ExecutionContext or "Rollback",
	}, Event)
end

return Event
