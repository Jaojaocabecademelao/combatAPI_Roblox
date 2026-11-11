local Frame = {}
Frame.__index = Frame
function Frame.new(data)
	assert(type(data) == "table" and type(data.Frame) == "number", "InputFrame requires a frame")
	return setmetatable({
		Frame = data.Frame, EntityId = data.EntityId, Inputs = data.Inputs or {}, Source = data.Source,
	}, Frame)
end
return Frame
