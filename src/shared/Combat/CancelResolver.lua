local CancelComponent = require(script.Parent.CancelComponent)
local CancelProfile = require(script.Parent.CancelProfile)
local CancelResult = require(script.Parent.CancelResult)
local CancelEvent = require(script.Parent.CancelEvent)
local MovementStateComponent = require(script.Parent.MovementStateComponent)
local EntityState = require(script.Parent.Parent.Core.EntityState)

local Resolver = {}
Resolver.__index = Resolver

local function id(value) return type(value) == "table" and value.Id or value end
local function finite(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end

function Resolver.new(world, profile)
	profile = profile or CancelProfile.new()
	if getmetatable(profile) ~= CancelProfile then profile = CancelProfile.new(profile) end
	return setmetatable({ World = world, Profile = profile, Events = {}, Results = {} }, Resolver)
end
function Resolver:_entity(value)
	if type(value) == "table" then return value end
	return self.World and self.World:GetEntity(value) or nil
end
function Resolver:_component(value)
	local entity = self:_entity(value)
	if not entity or entity.Destroyed then return nil, entity end
	return entity:GetComponent(CancelComponent), entity
end
function Resolver:_result(kind, entity, component, target, frame, reason, rule)
	local result = CancelResult.new({
		Type = kind, EntityId = entity and entity.Id, CurrentAction = component and component.CurrentAction,
		RequestedAction = target, CancelType = rule and rule.CancelType, Allowed = kind == CancelResult.Type.Allowed,
		Reason = reason, Frame = frame, RuleId = rule and rule.RuleId,
	})
	table.insert(self.Results, result)
	return result
end
function Resolver:_event(kind, entity, component, target, frame, reason, rule)
	local event = CancelEvent.new({
		Type = kind, EntityId = entity and entity.Id, FromAction = component and component.CurrentAction,
		ToAction = target, CancelType = rule and rule.CancelType, Frame = frame,
		RuleId = rule and rule.RuleId, Reason = reason,
	})
	table.insert(self.Events, event)
end
function Resolver:_rules(component, target, frame)
	local matches = {}
	for _, rule in ipairs(self.Profile.Rules) do
		if rule.FromAction == component.CurrentAction and rule.ToAction == target then
			local startFrame = rule.Relative and (component.ActionStartFrame or frame) + rule.StartFrame or rule.StartFrame
			local endFrame = rule.Relative and (component.ActionStartFrame or frame) + rule.EndFrame or rule.EndFrame
			if frame < startFrame or frame > endFrame then
				-- Keep the candidate so the caller can report OutsideWindow when appropriate.
			else
				table.insert(matches, rule)
			end
		end
	end
	table.sort(matches, function(a, b)
		if a.Priority ~= b.Priority then return a.Priority > b.Priority end
		return a.RuleId < b.RuleId
	end)
	return matches
end
function Resolver:_condition(rule, entity, context)
	if rule.RequiredMovementStates then
		local movement = entity:GetComponent(MovementStateComponent)
		local state = movement and movement:GetState()
		local allowed = false
		for _, value in ipairs(rule.RequiredMovementStates) do
			if value == state then allowed = true break end
		end
		if not allowed then return false, "ConditionFailed" end
	end
	if type(rule.Conditions) == "function" then
		local allowed, reason = rule.Conditions(entity, context)
		if allowed == false then return false, reason or "ConditionFailed" end
	end
	return true
end
function Resolver:_evaluate(entityOrId, target, context, requireComponent)
	context = context or {}
	local frame = context.Frame
	if frame == nil then frame = self.World and self.World.CurrentFrame or 0 end
	if not finite(frame) or frame < 0 or frame % 1 ~= 0 then
		return nil, nil, nil, frame, "InvalidFrame"
	end
	local component, entity = self:_component(entityOrId)
	if not entity or not component then return nil, entity, component, frame, CancelResult.Type.InvalidEntity end
	if entity:GetState() == EntityState.Dead then return nil, entity, component, frame, "DeadEntity" end
	if type(target) ~= "string" or target == "" then return nil, entity, component, frame, CancelResult.Type.InvalidAction end
	if not component.CurrentAction then return nil, entity, component, frame, CancelResult.Type.InvalidAction end
	local matches = self:_rules(component, target, frame)
	if #matches == 0 then return nil, entity, component, frame, "OutsideWindow" end
	for _, rule in ipairs(matches) do
		local allowed, reason = self:_condition(rule, entity, context)
		if allowed then
			if requireComponent and not rule.Repeatable and component.ConsumedRules[rule.RuleId] then
				return nil, entity, component, frame, CancelResult.Type.AlreadyCancelled
			end
			return rule, entity, component, frame, nil
		end
	end
	return nil, entity, component, frame, CancelResult.Type.ConditionFailed
end
function Resolver:BeginAction(entityOrId, actionId, frame, endFrame)
	local component, entity = self:_component(entityOrId)
	if not entity or not component then return self:_result(CancelResult.Type.InvalidEntity, entity, component, actionId, frame or 0, "InvalidEntity") end
	if type(actionId) ~= "string" or actionId == "" then return self:_result(CancelResult.Type.InvalidAction, entity, component, actionId, frame or 0, "InvalidAction") end
	component:BeginAction(actionId, frame or self.World.CurrentFrame or 0, endFrame)
	return self:_result(CancelResult.Type.Allowed, entity, component, actionId, frame or 0, "ActionStarted")
end
function Resolver:EndAction(entityOrId, frame)
	local component, entity = self:_component(entityOrId)
	if not entity or not component then return false end
	component:EndAction(frame or self.World.CurrentFrame or 0)
	return true
end
function Resolver:GetCurrentAction(entityOrId)
	local component = self:_component(entityOrId)
	return component and component:GetCurrentAction() or nil
end
function Resolver:CanCancel(entityOrId, target, context)
	local rule, entity, component, frame, reason = self:_evaluate(entityOrId, target, context, false)
	if rule then return true, rule end
	return false, reason
end
function Resolver:RequestCancel(entityOrId, target, context)
	local rule, entity, component, frame, reason = self:_evaluate(entityOrId, target, context, true)
	if not entity or not component then
		local result = self:_result(reason or CancelResult.Type.InvalidEntity, entity, component, target, frame, reason)
		if entity then self:_event(CancelEvent.Type.Rejected, entity, component, target, frame, reason) end
		return result
	end
	if not rule then
		local result = self:_result(reason == "OutsideWindow" and CancelResult.Type.OutsideWindow
			or reason == "DeadEntity" and CancelResult.Type.Rejected or reason, entity, component, target, frame, reason)
		self:_event(CancelEvent.Type.Rejected, entity, component, target, frame, reason)
		return result
	end
	if not rule.Repeatable then component.ConsumedRules[rule.RuleId] = true end
	component.LastCancelFrame, component.CancelCount = frame, component.CancelCount + 1
	local result = self:_result(CancelResult.Type.Allowed, entity, component, target, frame, nil, rule)
	self:_event(CancelEvent.Type.Allowed, entity, component, target, frame, nil, rule)
	return result
end
function Resolver:IsCancelWindowActive(entityOrId, target, context)
	return self:CanCancel(entityOrId, target, context)
end
function Resolver:Reset(entityOrId, frame)
	local component = self:_component(entityOrId)
	if not component then return false end
	component:Reset()
	return true
end
function Resolver:GetEvents() local result = {}; for _, value in ipairs(self.Events) do table.insert(result, value) end; return result end
function Resolver:GetResults() local result = {}; for _, value in ipairs(self.Results) do table.insert(result, value) end; return result end

-- Register explicitly with CombatStateSchema:RegisterStateProvider("combat.cancel-resolver.v1", resolver).
-- Events/results are frame-local outputs: target restore clears them so replay can regenerate them.
function Resolver:CaptureRollbackState()
	return { Version = 1, ProfileManifest = self.Profile:GetRollbackManifest() }
end

function Resolver:ValidateRollbackState(state)
	if type(state) ~= "table" or getmetatable(state) ~= nil or state.Version ~= 1 then
		return false, "Unsupported CancelResolver state"
	end
	for key in pairs(state) do
		if key ~= "Version" and key ~= "ProfileManifest" then
			return false, "Unknown CancelResolver state field: " .. tostring(key)
		end
	end
	local compatible, detail = self.Profile:ValidateRollbackManifest(state.ProfileManifest)
	if not compatible then return false, detail end
	return true
end

function Resolver:PrepareRollbackRestore(state, world, context, role)
	local valid, detail = self:ValidateRollbackState(state)
	if not valid then return nil, detail end
	local previousEvents, previousResults = {}, {}
	for _, event in ipairs(self.Events) do previousEvents[#previousEvents + 1] = event end
	for _, result in ipairs(self.Results) do previousResults[#previousResults + 1] = result end
	return function()
		if role == "Compensation" then
			table.clear(self.Events)
			for _, event in ipairs(previousEvents) do self.Events[#self.Events + 1] = event end
			table.clear(self.Results)
			for _, result in ipairs(previousResults) do self.Results[#self.Results + 1] = result end
		else
			table.clear(self.Events)
			table.clear(self.Results)
		end
	end
end

function Resolver:Clear() self.Events, self.Results = {}, {}; return self end

return Resolver
