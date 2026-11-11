local Sequence = {}
Sequence.__index = Sequence
function Sequence.new(value, modulus)
	modulus = modulus or 4294967296
	assert(type(modulus) == "number" and modulus > 1 and modulus % 1 == 0, "Invalid sequence modulus")
	value = value or 0
	assert(type(value) == "number" and value % 1 == 0, "Invalid sequence value")
	return setmetatable({ Value = value % modulus, Modulus = modulus }, Sequence)
end
function Sequence:Next() self.Value = (self.Value + 1) % self.Modulus; return self.Value end
function Sequence:Compare(other)
	local b = type(other) == "table" and other.Value or other
	local diff = (self.Value - b) % self.Modulus
	if diff == 0 then return 0 end
	return diff < self.Modulus / 2 and 1 or -1
end
function Sequence:IsNewer(other) return self:Compare(other) > 0 end
function Sequence:IsOlder(other) return self:Compare(other) < 0 end
return Sequence
