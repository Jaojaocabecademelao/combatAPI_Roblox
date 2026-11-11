local IdGenerator = {}
IdGenerator.__index = IdGenerator

function IdGenerator.new(startingId)
	if startingId == nil then
		startingId = 0
	end

	assert(
		type(startingId) == "number" and startingId % 1 == 0,
		"IdGenerator.new() expects an integer starting ID or nil"
	)

	local self = setmetatable({}, IdGenerator)
	self.LastId = startingId

	return self
end

function IdGenerator:Next()
	self.LastId += 1
	return self.LastId
end

return IdGenerator
