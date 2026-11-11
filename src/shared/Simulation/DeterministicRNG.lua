local DeterministicRNG = {}
DeterministicRNG.__index = DeterministicRNG

local MODULUS = 2147483647
local STATE_RANGE = MODULUS - 1

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

function DeterministicRNG.new(seed)
	if seed == nil then
		seed = 1
	end
	assert(isFiniteNumber(seed) and seed % 1 == 0,
		"DeterministicRNG.new() expects a finite integer seed")

	local self = setmetatable({}, DeterministicRNG)
	self.State = (seed % STATE_RANGE) + 1

	return self
end

function DeterministicRNG:_NextState()
	self.State = (self.State * 48271) % MODULUS
	return self.State
end

function DeterministicRNG:NextNumber(minimum, maximum)
	if minimum == nil and maximum == nil then
		return (self:_NextState() - 1) / STATE_RANGE
	end

	assert(isFiniteNumber(minimum) and isFiniteNumber(maximum) and maximum >= minimum,
		"DeterministicRNG:NextNumber() expects finite min and max values with max >= min")
	local range = maximum - minimum
	assert(isFiniteNumber(range), "DeterministicRNG:NextNumber() range is too large")
	local unit = (self:_NextState() - 1) / STATE_RANGE
	return minimum + unit * range
end

function DeterministicRNG:NextInteger(minimum, maximum)
	assert(isFiniteNumber(minimum) and isFiniteNumber(maximum)
		and minimum % 1 == 0 and maximum % 1 == 0 and maximum >= minimum,
		"DeterministicRNG:NextInteger() expects integer min and max values with max >= min")

	local range = maximum - minimum + 1
	assert(range <= STATE_RANGE, "DeterministicRNG:NextInteger() range is too large")

	return minimum + math.floor(self:NextNumber() * range)
end

function DeterministicRNG:GetState()
	return self.State
end

function DeterministicRNG:SetState(state)
	assert(isFiniteNumber(state) and state % 1 == 0 and state >= 1 and state <= STATE_RANGE,
		"DeterministicRNG:SetState() expects a valid RNG state")
	self.State = state
end

return DeterministicRNG
