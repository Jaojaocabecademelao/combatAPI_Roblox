local Component = require(script.Parent.Parent.Core.Component)
local EntityState = require(script.Parent.Parent.Core.EntityState)

local OffensiveStateComponent = setmetatable({}, Component)
OffensiveStateComponent.__index = OffensiveStateComponent
OffensiveStateComponent.RollbackKey = "Combat.OffensiveStateComponent"

local function validFrame(value)
	return type(value) == "number" and value == value and value >= 0
		and value < math.huge and value % 1 == 0
end

function OffensiveStateComponent.new()
	local self = setmetatable(Component.new(), OffensiveStateComponent)
	self.Active = false
	self.StartFrame = nil
	self.EndFrame = nil
	return self
end

function OffensiveStateComponent:SetActive(active, startFrame, durationFrames)
	if active ~= true then
		return self:EndWindow()
	end
	assert(self.Entity and not self.Entity.Destroyed and not self.Entity:IsDead(),
		"A dead or detached entity cannot start an offensive window")
	assert(type(startFrame) == "number" and startFrame >= 0 and startFrame % 1 == 0,
		"Offensive window requires a non-negative start frame")
	assert(type(durationFrames) == "number" and durationFrames > 0 and durationFrames % 1 == 0,
		"Offensive window requires a positive integer duration")
	self.Active = true
	self.StartFrame = startFrame
	self.EndFrame = startFrame + durationFrames - 1
	return true
end

function OffensiveStateComponent:SetWindow(startFrame, durationFrames)
	return self:SetActive(true, startFrame, durationFrames)
end

function OffensiveStateComponent:EndWindow()
	local wasActive = self.Active
	self.Active = false
	self.StartFrame = nil
	self.EndFrame = nil
	return wasActive
end

function OffensiveStateComponent:SetEnabled(enabled)
	Component.SetEnabled(self, enabled)
	if not self.Enabled then
		self:EndWindow()
	end
end

function OffensiveStateComponent:IsVulnerable(frame)
	if not self.Active or not self:IsEnabled() then
		return false
	end
	if not self.Entity or self.Entity.Destroyed or self.Entity:IsDead() then
		self:EndWindow()
		return false
	end
	if frame ~= nil then
		assert(type(frame) == "number" and frame >= 0 and frame % 1 == 0,
			"OffensiveStateComponent:IsVulnerable() expects a non-negative frame")
		if frame > self.EndFrame then
			self:EndWindow()
			return false
		end
		return frame >= self.StartFrame
	end
	return true
end

function OffensiveStateComponent:Destroy()
	self:EndWindow()
end

function OffensiveStateComponent:OnEntityStateChanged(state)
	if state == EntityState.Dead then
		self:EndWindow()
	end
end

function OffensiveStateComponent:CaptureRollbackState()
	return {
		Version = 1,
		Active = self.Active,
		StartFrame = self.StartFrame,
		EndFrame = self.EndFrame,
	}
end

function OffensiveStateComponent:ValidateRollbackState(state)
	if type(state) ~= "table" or getmetatable(state) ~= nil or state.Version ~= 1 then
		return false, "Invalid OffensiveStateComponent state version"
	end
	for key in pairs(state) do
		if key ~= "Version" and key ~= "Active" and key ~= "StartFrame" and key ~= "EndFrame" then
			return false, "Unknown offensive state field: " .. tostring(key)
		end
	end
	if type(state.Active) ~= "boolean" then return false, "Offensive Active must be boolean" end
	if state.Active then
		if not validFrame(state.StartFrame) or not validFrame(state.EndFrame)
			or state.EndFrame < state.StartFrame then return false, "Active offensive window has invalid frame bounds" end
	elseif state.StartFrame ~= nil or state.EndFrame ~= nil then
		return false, "Inactive offensive window must not retain frame bounds"
	end
	return true
end

function OffensiveStateComponent:RestoreRollbackState(state)
	local valid, detail = self:ValidateRollbackState(state)
	if not valid then return false, detail end
	self.Active = state.Active
	self.StartFrame = state.StartFrame
	self.EndFrame = state.EndFrame
	return true
end

return OffensiveStateComponent
