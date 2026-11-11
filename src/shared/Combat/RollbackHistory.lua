local History = {}
History.__index = History

function History.new(capacity)
	assert(type(capacity) == "number" and capacity >= 1 and capacity < math.huge
		and capacity % 1 == 0, "RollbackHistory capacity must be a positive integer")
	return setmetatable({ Capacity = capacity, Frames = {}, Order = {} }, History)
end

function History:Put(frame, value)
	assert(type(frame) == "number" and frame >= 0 and frame < math.huge and frame % 1 == 0,
		"RollbackHistory frame is invalid")
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

function History:Count()
	return #self.Order
end

function History:Clear()
	self.Frames, self.Order = {}, {}
	return self
end

return History
