local GameTime = {}
GameTime.__index = GameTime

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

function GameTime.new(fixedDeltaTime)
	assert(isFiniteNumber(fixedDeltaTime) and fixedDeltaTime > 0,
		"GameTime.new() expects a finite positive FixedDeltaTime")

	local self = setmetatable({}, GameTime)
	self.FixedDeltaTime = fixedDeltaTime
	self.Frame = 0
	self.DeltaTime = 0
	self.Time = 0

	return self
end

function GameTime:Advance()
	self.Frame += 1
	self.DeltaTime = self.FixedDeltaTime
	self.Time = self.Frame * self.FixedDeltaTime
	return self
end

function GameTime:GetFrame()
	return self.Frame
end

function GameTime:GetDeltaTime()
	return self.DeltaTime
end

function GameTime:GetTime()
	return self.Time
end

function GameTime:GetFixedDeltaTime()
	return self.FixedDeltaTime
end

function GameTime:Reset()
	self.Frame = 0
	self.DeltaTime = 0
	self.Time = 0
end

function GameTime:RestoreFrame(frame)
	assert(type(frame) == "number" and frame == frame and frame >= 0
		and frame < math.huge and frame % 1 == 0,
		"GameTime:RestoreFrame() expects a non-negative integer frame")
	self.Frame = frame
	self.DeltaTime = frame == 0 and 0 or self.FixedDeltaTime
	self.Time = frame * self.FixedDeltaTime
	return self
end

return GameTime
