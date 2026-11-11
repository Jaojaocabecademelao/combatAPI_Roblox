local Component = require(script.Parent.Parent.Core.Component)

local HitstopComponent = setmetatable({}, Component)
HitstopComponent.__index = HitstopComponent
HitstopComponent.RollbackKey = "Combat.HitstopComponent"

function HitstopComponent.new()
	local self = setmetatable(Component.new(), HitstopComponent)
	self.RemainingFrames = 0
	self.Priority = nil
	self.Source = nil
	return self
end

function HitstopComponent:IsFrozen()
	return self:IsEnabled() and self.Entity ~= nil and not self.Entity.Destroyed
		and self.RemainingFrames > 0
end

function HitstopComponent:GetRemainingFrames()
	return self.RemainingFrames
end

function HitstopComponent:GetLocalDeltaTime(globalDeltaTime)
	assert(type(globalDeltaTime) == "number" and globalDeltaTime == globalDeltaTime
		and globalDeltaTime >= 0 and globalDeltaTime < math.huge,
		"HitstopComponent:GetLocalDeltaTime() expects a finite non-negative deltaTime")
	return self:IsFrozen() and 0 or globalDeltaTime
end

function HitstopComponent:Apply(frames, priority, source)
	assert(type(frames) == "number" and frames >= 0 and frames % 1 == 0
		and frames < math.huge, "HitstopComponent:Apply() expects non-negative integer frames")
	assert(type(priority) == "number" and priority == priority
		and priority > -math.huge and priority < math.huge,
		"HitstopComponent:Apply() expects a finite priority")
	if frames == 0 then
		return "ZeroFrames"
	end
	if self.RemainingFrames == 0 then
		self.RemainingFrames = frames
		self.Priority = priority
		self.Source = source
		return "Applied"
	elseif priority > self.Priority then
		self.RemainingFrames = frames
		self.Priority = priority
		self.Source = source
		return "Applied"
	elseif priority == self.Priority and frames > self.RemainingFrames then
		self.RemainingFrames = frames
		self.Source = source
		return "Extended"
	end
	return "Ignored"
end

function HitstopComponent:AdvanceStep()
	if self.RemainingFrames > 0 then
		self.RemainingFrames -= 1
		if self.RemainingFrames == 0 then
			self.Priority = nil
			self.Source = nil
		end
	end
end

function HitstopComponent:Clear()
	self.RemainingFrames = 0
	self.Priority = nil
	self.Source = nil
end

function HitstopComponent:Destroy()
	self:Clear()
end


local function finiteNumber(value)
	return type(value) == "number" and value == value
		and value > -math.huge and value < math.huge
end

-- Capture only deterministic state. Entity references are represented by stable IDs.
function HitstopComponent:CaptureRollbackState()
	local sourceId = self.Source and self.Source.Id or nil
	assert(self.Source == nil or sourceId ~= nil,
		"HitstopComponent Source must be nil or expose a stable entity Id")
	return {
		Version = 1,
		Enabled = self:IsEnabled(),
		RemainingFrames = self.RemainingFrames,
		Priority = self.Priority,
		SourceEntityId = sourceId,
	}
end

function HitstopComponent:ValidateRollbackState(state, context)
	if type(state) ~= "table" or getmetatable(state) ~= nil or state.Version ~= 1 then
		return false, "Invalid HitstopComponent state version"
	end
	if type(state.Enabled) ~= "boolean" then return false, "Invalid HitstopComponent Enabled flag" end
	if not finiteNumber(state.RemainingFrames) or state.RemainingFrames < 0
		or state.RemainingFrames % 1 ~= 0 then
		return false, "Invalid HitstopComponent RemainingFrames"
	end
	if state.RemainingFrames == 0 then
		if state.Priority ~= nil or state.SourceEntityId ~= nil then
			return false, "Inactive HitstopComponent cannot retain Priority or Source"
		end
	else
		if not finiteNumber(state.Priority) then return false, "Active HitstopComponent requires finite Priority" end
		if state.SourceEntityId ~= nil and type(state.SourceEntityId) ~= "number"
			and type(state.SourceEntityId) ~= "string" then
			return false, "Invalid HitstopComponent SourceEntityId"
		end
		if state.SourceEntityId ~= nil and context and context.EntitiesById
			and not context.EntitiesById[state.SourceEntityId] then
			return false, "Missing HitstopComponent source entity " .. tostring(state.SourceEntityId)
		end
	end
	return true
end

function HitstopComponent:RestoreRollbackState(state, context)
	local valid, reason = self:ValidateRollbackState(state, context)
	if not valid then return false, reason end
	local source
	if state.SourceEntityId ~= nil then
		source = context and context.EntitiesById and context.EntitiesById[state.SourceEntityId]
		if not source then return false, "HitstopComponent restore requires staged source entity " .. tostring(state.SourceEntityId) end
	end
	self.RemainingFrames = state.RemainingFrames
	self.Priority = state.Priority
	self.Source = source
	self:SetEnabled(state.Enabled)
	return true
end

function HitstopComponent:PrepareRollbackRestore(state, world)
	local valid, reason = self:ValidateRollbackState(state)
	if not valid then return nil, reason end
	local source
	if state.SourceEntityId ~= nil then
		if not world or type(world.GetEntity) ~= "function" then
			return nil, "HitstopComponent restore requires a World"
		end
		source = world:GetEntity(state.SourceEntityId)
		if not source or source.Destroyed then
			return nil, "Missing HitstopComponent source entity " .. tostring(state.SourceEntityId)
		end
	end
	local remaining, priority, enabled = state.RemainingFrames, state.Priority, state.Enabled
	return function()
		self.RemainingFrames = remaining
		self.Priority = priority
		self.Source = source
		self:SetEnabled(enabled)
	end
end

return HitstopComponent
