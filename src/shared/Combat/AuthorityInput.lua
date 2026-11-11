local Input = {}
Input.__index = Input

function Input.new(data)
	assert(type(data) == "table", "AuthorityInput.new() expects a table")
	assert(type(data.SimulationFrame) == "number", "AuthorityInput SimulationFrame is required")
	assert(type(data.Inputs) == "table", "AuthorityInput Inputs are required")
	local inputs = {}
	for inputId, state in pairs(data.Inputs) do
		inputs[inputId] = state
	end
	return setmetatable({
		EntityId = data.EntityId,
		SimulationFrame = data.SimulationFrame,
		NetworkSequence = data.NetworkSequence,
		Inputs = inputs,
		Source = data.Source,
	}, Input)
end

return Input
