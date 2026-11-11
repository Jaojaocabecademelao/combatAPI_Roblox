local Component = require(script.Parent.Parent.Core.Component)

local CancelComponent = setmetatable({}, Component)
CancelComponent.RollbackKey = "Combat.CancelComponent"
CancelComponent.__index = CancelComponent

function CancelComponent.new(profile)
	local self = setmetatable(Component.new(), CancelComponent)
	self.Profile = profile
	self.CurrentAction = nil
	self.ActionStartFrame = nil
	self.ActionEndFrame = nil
	self.ConsumedRules = {}
	self.LastCancelFrame = nil
	self.CancelCount = 0
	return self
end

function CancelComponent:BeginAction(actionId, frame, endFrame)
	assert(type(actionId) == "string" and actionId ~= "", "CancelComponent actionId is required")
	self.CurrentAction = actionId
	self.ActionStartFrame = frame
	self.ActionEndFrame = endFrame
	self.ConsumedRules = {}
	self.LastCancelFrame = nil
	return self
end
function CancelComponent:EndAction(frame)
	self.CurrentAction = nil
	self.ActionStartFrame = nil
	self.ActionEndFrame = frame
	self.ConsumedRules = {}
	return self
end
function CancelComponent:GetCurrentAction() return self.CurrentAction end
function CancelComponent:Reset()
	self.CurrentAction = nil
	self.ActionStartFrame = nil
	self.ActionEndFrame = nil
	self.ConsumedRules = {}
	self.LastCancelFrame = nil
	self.CancelCount = 0
	return self
end
function CancelComponent:Destroy() self:Reset() end
function CancelComponent:OnEntityStateChanged(state)
	if state == "Dead" then self:Reset() end
end

local function finiteFrameOrNil(value)
	return value == nil or (type(value) == "number" and value == value
		and value >= 0 and value < math.huge and value % 1 == 0)
end

function CancelComponent:CaptureRollbackState()
	return {
		Version = 2,
		CurrentAction = self.CurrentAction,
		ActionStartFrame = self.ActionStartFrame,
		ActionEndFrame = self.ActionEndFrame,
		ConsumedRules = table.clone(self.ConsumedRules),
		LastCancelFrame = self.LastCancelFrame,
		CancelCount = self.CancelCount,
		ProfileManifest = self.Profile and self.Profile:GetRollbackManifest() or nil,
	}
end

function CancelComponent:ValidateRollbackState(state)
	if type(state) ~= "table" or getmetatable(state) ~= nil or state.Version ~= 2 then
		return false, "Invalid CancelComponent state version"
	end
	local allowedFields = { Version = true, CurrentAction = true, ActionStartFrame = true,
		ActionEndFrame = true, ConsumedRules = true, LastCancelFrame = true,
		CancelCount = true, ProfileManifest = true }
	for key in pairs(state) do
		if not allowedFields[key] then return false, "Unknown CancelComponent state field: " .. tostring(key) end
	end
	if state.CurrentAction ~= nil and (type(state.CurrentAction) ~= "string" or state.CurrentAction == "") then
		return false, "CurrentAction must be a non-empty string or nil"
	end
	for _, key in ipairs({ "ActionStartFrame", "ActionEndFrame", "LastCancelFrame" }) do
		if not finiteFrameOrNil(state[key]) then return false, key .. " must be a frame or nil" end
	end
	if state.CurrentAction ~= nil and state.ActionStartFrame == nil then
		return false, "An active action requires ActionStartFrame"
	end
	if state.ActionStartFrame ~= nil and state.ActionEndFrame ~= nil and state.ActionEndFrame < state.ActionStartFrame then
		return false, "ActionEndFrame precedes ActionStartFrame"
	end
	if type(state.CancelCount) ~= "number" or state.CancelCount < 0 or state.CancelCount % 1 ~= 0
		or state.CancelCount ~= state.CancelCount or state.CancelCount == math.huge then
		return false, "CancelCount must be a non-negative integer"
	end
	if type(state.ConsumedRules) ~= "table" or getmetatable(state.ConsumedRules) ~= nil then
		return false, "ConsumedRules must be a plain table"
	end
	for ruleId, consumed in pairs(state.ConsumedRules) do
		if type(ruleId) ~= "string" or ruleId == "" or consumed ~= true then
			return false, "ConsumedRules contains an invalid entry"
		end
	end
	if not self.Profile then
		if state.ProfileManifest ~= nil then return false, "Snapshot requires a CancelProfile" end
	else
		local compatible, detail = self.Profile:ValidateRollbackManifest(state.ProfileManifest)
		if not compatible then return false, detail end
	end
	local registered = {}
	if self.Profile then
		for _, rule in ipairs(self.Profile:GetRules()) do registered[rule.RuleId] = true end
	end
	for ruleId in pairs(state.ConsumedRules) do
		if not registered[ruleId] then return false, "Consumed rule is absent from profile: " .. ruleId end
	end
	return true
end

function CancelComponent:RestoreRollbackState(state)
	local valid, reason = self:ValidateRollbackState(state)
	if not valid then return false, reason end
	self.CurrentAction = state.CurrentAction
	self.ActionStartFrame = state.ActionStartFrame
	self.ActionEndFrame = state.ActionEndFrame
	self.ConsumedRules = {}
	for ruleId, value in pairs(state.ConsumedRules) do self.ConsumedRules[ruleId] = value end
	self.LastCancelFrame = state.LastCancelFrame
	self.CancelCount = state.CancelCount
	return true
end

return CancelComponent
