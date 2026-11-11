local Component = require(script.Parent.Parent.Core.Component)
local EntityState = require(script.Parent.Parent.Core.EntityState)

local DefenseComponent = {}
DefenseComponent.__index = DefenseComponent
DefenseComponent.RollbackKey = "Combat.DefenseComponent"
setmetatable(DefenseComponent, { __index = Component })

local function validateFrame(frame, label)
	assert(type(frame) == "number" and frame >= 0 and frame < math.huge
		and frame == frame and frame % 1 == 0,
		label .. " must be a non-negative finite integer simulation frame")
end

function DefenseComponent.new()
	local self = Component.new()
	self.Blocking = false
	self.ParryStartFrame = nil
	self.ParryEndFrame = nil
	return setmetatable(self, DefenseComponent)
end

function DefenseComponent:_canDefend()
	return self:IsEnabled() and self.Entity ~= nil and not self.Entity.Destroyed
		and self.Entity:GetState() == EntityState.Alive
end

function DefenseComponent:SetBlocking(blocking)
	assert(type(blocking) == "boolean", "DefenseComponent:SetBlocking() expects a boolean")
	if blocking and not self:_canDefend() then
		return false, "EntityUnavailable"
	end
	self.Blocking = blocking
	return true
end

function DefenseComponent:IsBlocking()
	return self.Blocking and self:_canDefend()
end

function DefenseComponent:OpenParryWindow(startFrame, durationFrames)
	validateFrame(startFrame, "Parry start frame")
	assert(type(durationFrames) == "number" and durationFrames > 0
		and durationFrames < math.huge and durationFrames == durationFrames
		and durationFrames % 1 == 0,
		"Parry duration must be a positive finite integer number of frames")
	if not self:_canDefend() then
		return false, "EntityUnavailable"
	end
	self.ParryStartFrame = startFrame
	self.ParryEndFrame = startFrame + durationFrames - 1
	return true
end

function DefenseComponent:IsParryActive(frame)
	validateFrame(frame, "Parry query frame")
	return self:_canDefend() and self.ParryStartFrame ~= nil
		and frame >= self.ParryStartFrame and frame <= self.ParryEndFrame
end

function DefenseComponent:CloseParryWindow()
	self.ParryStartFrame = nil
	self.ParryEndFrame = nil
	return self
end

function DefenseComponent:GetParryWindow()
	if self.ParryStartFrame == nil then
		return nil
	end
	return {
		StartFrame = self.ParryStartFrame,
		EndFrame = self.ParryEndFrame,
	}
end

function DefenseComponent:Destroy()
	self.Blocking = false
	self:CloseParryWindow()
end

local function finiteIntegerOrNil(value)
	return value == nil or (type(value) == "number" and value == value
		and value >= 0 and value < math.huge and value % 1 == 0)
end

function DefenseComponent:CaptureRollbackState()
	return {
		Version = 1,
		Blocking = self.Blocking,
		ParryStartFrame = self.ParryStartFrame,
		ParryEndFrame = self.ParryEndFrame,
	}
end

function DefenseComponent:ValidateRollbackState(state)
	if type(state) ~= "table" or getmetatable(state) ~= nil or state.Version ~= 1 then
		return false, "Invalid DefenseComponent state version"
	end
	if type(state.Blocking) ~= "boolean" then return false, "Blocking must be boolean" end
	if not finiteIntegerOrNil(state.ParryStartFrame) or not finiteIntegerOrNil(state.ParryEndFrame) then
		return false, "Parry frames must be non-negative integers or nil"
	end
	if (state.ParryStartFrame == nil) ~= (state.ParryEndFrame == nil) then
		return false, "Parry window must have both endpoints or neither"
	end
	if state.ParryStartFrame ~= nil and state.ParryEndFrame < state.ParryStartFrame then
		return false, "Parry window end precedes its start"
	end
	return true
end

function DefenseComponent:RestoreRollbackState(state)
	local valid, reason = self:ValidateRollbackState(state)
	if not valid then return false, reason end
	self.Blocking = state.Blocking
	self.ParryStartFrame = state.ParryStartFrame
	self.ParryEndFrame = state.ParryEndFrame
	return true
end

return DefenseComponent
