local Component = require(script.Parent.Parent.Core.Component)
local EntityState = require(script.Parent.Parent.Core.EntityState)
local GuardProfile = require(script.Parent.GuardProfile)

local GuardComponent = setmetatable({}, Component)
GuardComponent.__index = GuardComponent
GuardComponent.RollbackKey = "Combat.GuardComponent"

local function finite(value)
	return type(value) == "number" and value == value
		and value > -math.huge and value < math.huge
end

local function clamp(value, minimum, maximum)
	if value < minimum then return minimum end
	if value > maximum then return maximum end
	return value
end

function GuardComponent.new(options)
	options = options or {}
	assert(type(options) == "table", "GuardComponent.new() expects an options table or nil")

	local profile = options.Profile
	if profile == nil then
		profile = GuardProfile.new(options)
	elseif getmetatable(profile) ~= GuardProfile then
		profile = GuardProfile.new(profile)
	end

	local maxGuard = options.MaxGuard or profile.MaxGuard
	assert(finite(maxGuard) and maxGuard > 0 and maxGuard % 1 == 0,
		"GuardComponent MaxGuard must be a finite positive integer")
	local currentGuard = options.Guard
	if currentGuard == nil then
		currentGuard = maxGuard
	end
	assert(finite(currentGuard) and currentGuard >= 0 and currentGuard % 1 == 0,
		"GuardComponent Guard must be a finite non-negative integer")
	currentGuard = clamp(currentGuard, 0, maxGuard)

	local self = setmetatable(Component.new(), GuardComponent)
	self.Profile = profile
	self.MaxGuard = maxGuard
	self.Guard = currentGuard
	self.GuardBroken = false
	self.GuardBreakFrames = options.GuardBreakFrames or profile.GuardBreakFrames or 30
	self.GuardBreakRemaining = 0
	return self
end

function GuardComponent:_canUseGuard()
	return self:IsEnabled() and self.Entity ~= nil and not self.Entity.Destroyed
		and self.Entity:GetState() ~= EntityState.Dead
end

function GuardComponent:GetGuard()
	return self.Guard
end

function GuardComponent:GetMaxGuard()
	return self.MaxGuard
end

function GuardComponent:SetGuard(value)
	assert(finite(value) and value >= 0 and value % 1 == 0,
		"GuardComponent:SetGuard() expects a finite non-negative integer")
	if not self:_canUseGuard() then
		return false, "EntityUnavailable"
	end
	self.Guard = clamp(value, 0, self.MaxGuard)
	self.GuardBroken = self.Guard <= 0
	if self.GuardBroken then
		self.GuardBreakRemaining = self.GuardBreakFrames
	end
	return self.Guard
end

function GuardComponent:Drain(amount)
	assert(finite(amount) and amount >= 0,
		"GuardComponent:Drain() expects a finite non-negative number")
	if not self:_canUseGuard() then
		return false, "EntityUnavailable"
	end
	if amount <= 0 then
		return self.Guard
	end
	self.Guard = math.max(0, self.Guard - amount)
	self.GuardBroken = self.Guard <= 0
	if self.GuardBroken then
		self.GuardBreakRemaining = self.GuardBreakFrames
	end
	return self.Guard
end

function GuardComponent:Restore(amount)
	assert(finite(amount) and amount >= 0,
		"GuardComponent:Restore() expects a finite non-negative number")
	if not self:_canUseGuard() then
		return false, "EntityUnavailable"
	end
	if amount <= 0 then
		return self.Guard
	end
	self.Guard = math.min(self.MaxGuard, self.Guard + amount)
	self.GuardBroken = self.Guard <= 0
	if self.Guard > 0 then
		self.GuardBreakRemaining = 0
	end
	return self.Guard
end

function GuardComponent:IsGuardBroken()
	return self:_canUseGuard() and self.GuardBroken or false
end

function GuardComponent:ResetGuard()
	if not self:_canUseGuard() then
		return false, "EntityUnavailable"
	end
	self.Guard = self.MaxGuard
	self.GuardBroken = false
	self.GuardBreakRemaining = 0
	return self.Guard
end

function GuardComponent:AdvanceFrame(frame)
	if not self:_canUseGuard() then
		return self
	end
	if self.GuardBroken then
		if frame ~= nil then
			self.GuardBreakRemaining = math.max(0, (self.GuardBreakRemaining or 0) - 1)
			if self.GuardBreakRemaining <= 0 then
				self.GuardBroken = false
				self.Guard = 0
			end
		end
	end
	return self
end

function GuardComponent:Destroy()
	self.Guard = 0
	self.GuardBroken = false
	self.GuardBreakRemaining = 0
end

function GuardComponent:CaptureRollbackState()
	return {
		Version = 1,
		MaxGuard = self.MaxGuard,
		Guard = self.Guard,
		GuardBroken = self.GuardBroken,
		GuardBreakFrames = self.GuardBreakFrames,
		GuardBreakRemaining = self.GuardBreakRemaining,
		Profile = {
			MaxGuard = self.Profile.MaxGuard,
			ChipMultiplier = self.Profile.ChipMultiplier,
			GuardDamageMultiplier = self.Profile.GuardDamageMultiplier,
			BlockstunMultiplier = self.Profile.BlockstunMultiplier,
			GuardBreakFrames = self.Profile.GuardBreakFrames,
			DefaultGuardDamage = self.Profile.DefaultGuardDamage,
			Name = self.Profile.Name,
		},
	}
end

function GuardComponent:ValidateRollbackState(state)
	if type(state) ~= "table" or getmetatable(state) ~= nil or state.Version ~= 1 then
		return false, "Invalid GuardComponent state version"
	end
	if not finite(state.MaxGuard) or state.MaxGuard <= 0 or state.MaxGuard % 1 ~= 0 then
		return false, "MaxGuard must be a positive integer"
	end
	if not finite(state.Guard) or state.Guard < 0 or state.Guard > state.MaxGuard or state.Guard % 1 ~= 0 then
		return false, "Guard is outside valid bounds"
	end
	if type(state.GuardBroken) ~= "boolean" then return false, "GuardBroken must be boolean" end
	if not finite(state.GuardBreakFrames) or state.GuardBreakFrames < 0 or state.GuardBreakFrames % 1 ~= 0 then
		return false, "GuardBreakFrames must be a non-negative integer"
	end
	if not finite(state.GuardBreakRemaining) or state.GuardBreakRemaining < 0 or state.GuardBreakRemaining % 1 ~= 0 then
		return false, "GuardBreakRemaining must be a non-negative integer"
	end
	if state.GuardBroken ~= (state.Guard <= 0) then return false, "GuardBroken disagrees with Guard" end
	if state.GuardBroken and state.GuardBreakRemaining > state.GuardBreakFrames then
		return false, "GuardBreakRemaining exceeds configured duration"
	end
	local profile = state.Profile
	if type(profile) ~= "table" or getmetatable(profile) ~= nil then return false, "Missing GuardProfile manifest" end
	local current = self.Profile
	for _, key in ipairs({ "MaxGuard", "ChipMultiplier", "GuardDamageMultiplier", "BlockstunMultiplier", "GuardBreakFrames", "DefaultGuardDamage", "Name" }) do
		if profile[key] ~= current[key] then return false, "GuardProfile mismatch: " .. key end
	end
	if state.MaxGuard ~= self.MaxGuard or state.GuardBreakFrames ~= self.GuardBreakFrames then
		return false, "GuardComponent configuration mismatch"
	end
	return true
end

function GuardComponent:RestoreRollbackState(state)
	local valid, reason = self:ValidateRollbackState(state)
	if not valid then return false, reason end
	self.Guard = state.Guard
	self.GuardBroken = state.GuardBroken
	self.GuardBreakRemaining = state.GuardBreakRemaining
	return true
end

return GuardComponent
