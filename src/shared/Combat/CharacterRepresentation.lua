local Representation = {}
Representation.__index = Representation

function Representation.new(value, representationType)
	return setmetatable({
		Value = value,
		Type = representationType or "Custom",
	}, Representation)
end

function Representation:IsValid()
	return self.Value ~= nil
end

function Representation:GetValue()
	return self.Value
end

return Representation
