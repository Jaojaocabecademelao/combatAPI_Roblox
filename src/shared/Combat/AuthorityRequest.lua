local Request = {}
Request.__index = Request

function Request.new(data)
	assert(type(data) == "table", "AuthorityRequest.new() expects a table")
	assert(type(data.SimulationFrame) == "number", "AuthorityRequest SimulationFrame is required")
	return setmetatable({
		PeerId = data.PeerId,
		EntityId = data.EntityId,
		SimulationFrame = data.SimulationFrame,
		NetworkSequence = data.NetworkSequence,
		Input = data.Input,
	}, Request)
end

return Request
