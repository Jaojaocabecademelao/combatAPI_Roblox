local StatusEvent = {}
StatusEvent.__index = StatusEvent

function StatusEvent.new(eventType, entity, status, reason)
	return setmetatable({
		Type = eventType,
		Entity = entity,
		Status = status,
		StatusName = status.Name,
		Reason = reason,
	}, StatusEvent)
end

return StatusEvent
