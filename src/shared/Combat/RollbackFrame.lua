local Frame = {}
Frame.__index = Frame

function Frame.new(data)
	assert(type(data) == "table" and type(data.Frame) == "number"
		and data.Frame >= 0 and data.Frame < math.huge and data.Frame % 1 == 0,
		"RollbackFrame frame is invalid")
	assert(type(data.InputFrames) == "table", "RollbackFrame requires input history")
	return setmetatable({
		Frame = data.Frame,
		Snapshot = data.Snapshot,
		InputFrames = data.InputFrames,
		Replayed = data.Replayed == true,
	}, Frame)
end

return Frame
