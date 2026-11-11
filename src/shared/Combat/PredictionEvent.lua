local Event = {}
Event.__index = Event

Event.Type = table.freeze({
	Enabled = "PredictionEnabled",
	Disabled = "PredictionDisabled",
	Began = "PredictionBegan",
	Advanced = "PredictionAdvanced",
	Confirmed = "PredictionConfirmed",
	Divergence = "PredictionDivergence",
	Removed = "PredictionRemoved",
})

function Event.new(data)
	assert(type(data) == "table", "PredictionEvent.new() expects data")
	return setmetatable({
		Type = data.Type,
		EntityId = data.EntityId,
		Frame = data.Frame,
		Predicted = data.Predicted == true,
		PredictionIndex = data.PredictionIndex,
		Divergences = data.Divergences,
		Reason = data.Reason,
	}, Event)
end

return Event
