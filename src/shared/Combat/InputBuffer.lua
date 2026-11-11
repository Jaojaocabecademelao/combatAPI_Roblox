local InputBuffer = {}
InputBuffer.__index = InputBuffer

local function validFrame(frame)
	return type(frame) == "number" and frame == frame and frame >= 0
		and frame < math.huge and frame % 1 == 0
end

function InputBuffer.new(capacity)
	assert(type(capacity) == "number" and capacity >= 1 and capacity % 1 == 0,
		"InputBuffer capacity must be a positive integer")
	return setmetatable({
		Capacity = capacity,
		Frames = {},
		Order = {},
	}, InputBuffer)
end

function InputBuffer:Put(frame, value)
	assert(validFrame(frame), "InputBuffer frame is invalid")
	if not self.Frames[frame] then
		table.insert(self.Order, frame)
		table.sort(self.Order, function(a, b) return a < b end)
	end
	self.Frames[frame] = value
	while #self.Order > self.Capacity do
		self.Frames[table.remove(self.Order, 1)] = nil
	end
	return value
end

function InputBuffer:Get(frame)
	return self.Frames[frame]
end

function InputBuffer:Has(frame)
	return self.Frames[frame] ~= nil
end

function InputBuffer:GetWindow(startFrame, endFrame)
	assert(validFrame(startFrame) and validFrame(endFrame) and startFrame <= endFrame,
		"InputBuffer window is invalid")
	local result = {}
	for _, frame in ipairs(self.Order) do
		if frame >= startFrame and frame <= endFrame then
			table.insert(result, self.Frames[frame])
		end
	end
	return result
end

function InputBuffer:Count()
	return #self.Order
end

function InputBuffer:Clear()
	self.Frames, self.Order = {}, {}
	return self
end

return InputBuffer
