local History = {}
History.__index = History

function History.new(capacity)
	assert(type(capacity) == "number" and capacity >= 1 and capacity < math.huge
		and capacity % 1 == 0, "PredictionHistory capacity must be a positive integer")
	return setmetatable({ Capacity = capacity, Frames = {}, Order = {} }, History)
end

function History:Put(frame, value)
	assert(type(frame) == "number" and frame == frame and frame >= 0
		and frame < math.huge and frame % 1 == 0, "PredictionHistory frame is invalid")
	if self.Frames[frame] == nil then
		table.insert(self.Order, frame)
		table.sort(self.Order, function(a, b) return a < b end)
	end
	self.Frames[frame] = value
	while #self.Order > self.Capacity do
		self.Frames[table.remove(self.Order, 1)] = nil
	end
	return value
end

function History:Get(frame)
	return self.Frames[frame]
end

function History:Has(frame)
	return self.Frames[frame] ~= nil
end

function History:GetWindow(startFrame, endFrame)
	local function validFrame(frame)
		return type(frame) == "number" and frame == frame and frame >= 0
			and frame < math.huge and frame % 1 == 0
	end
	assert(validFrame(startFrame) and validFrame(endFrame),
		"PredictionHistory window is invalid")
	local result = {}
	if startFrame > endFrame then
		return result
	end
	for _, frame in ipairs(self.Order) do
		if frame >= startFrame and frame <= endFrame then
			table.insert(result, self.Frames[frame])
		end
	end
	return result
end

function History:RemoveAfter(frame)
	assert(type(frame) == "number" and frame == frame and frame >= 0
		and frame < math.huge and frame % 1 == 0, "PredictionHistory frame is invalid")
	local removed = 0
	for index = #self.Order, 1, -1 do
		local candidate = self.Order[index]
		if candidate > frame then
			self.Frames[candidate] = nil
			table.remove(self.Order, index)
			removed += 1
		end
	end
	return removed
end

function History:Count()
	return #self.Order
end

function History:Clear()
	self.Frames, self.Order = {}, {}
	return self
end

return History
