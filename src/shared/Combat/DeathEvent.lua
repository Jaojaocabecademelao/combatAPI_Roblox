local DeathEvent = {}
DeathEvent.__index = DeathEvent

function DeathEvent.new(data)
	assert(type(data) == "table", "DeathEvent.new() expects an event data table")
	return setmetatable({
		Entity = data.Entity,
		Cause = data.Cause,
		Frame = data.Frame,
		Time = data.Time,
	}, DeathEvent)
end

return DeathEvent
