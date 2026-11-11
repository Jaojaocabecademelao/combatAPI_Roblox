local InputFrame = require(script.Parent.InputFrame)

local Frame = {}
Frame.__index = Frame

function Frame.new(data)
	assert(type(data) == "table" and type(data.Frame) == "number"
		and type(data.InputFrame) == "table" and getmetatable(data.InputFrame) == InputFrame,
		"PredictionFrame data is invalid")
	assert(data.Frame == data.Frame and data.Frame >= 0 and data.Frame < math.huge
		and data.Frame % 1 == 0 and data.InputFrame.Frame == data.Frame,
		"PredictionFrame simulation frame is invalid")
	assert(data.EntityId == nil or data.InputFrame.EntityId == nil
		or data.InputFrame.EntityId == data.EntityId, "PredictionFrame entity does not match its input")
	assert(type(data.InputFrame.Inputs) == "table", "PredictionFrame inputs are invalid")

	local inputs = {}
	for inputId, state in pairs(data.InputFrame.Inputs) do
		inputs[inputId] = state
	end

	local inputFrame = InputFrame.new({
		Frame = data.Frame,
		EntityId = data.EntityId,
		Inputs = inputs,
		Source = data.InputFrame.Source,
	})

	return setmetatable({
		EntityId = data.EntityId,
		Frame = data.Frame,
		InputFrame = inputFrame,
		Inputs = inputs,
		Predicted = data.Predicted == true,
		Confirmed = data.Confirmed == true,
		PredictionIndex = data.PredictionIndex or 0,
	}, Frame)
end

return Frame
