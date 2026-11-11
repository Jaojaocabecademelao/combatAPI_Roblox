local MovementStateComponent = require(script.Parent.MovementStateComponent)
local MovementStateProfile = require(script.Parent.MovementStateProfile)
local MovementStateResult = require(script.Parent.MovementStateResult)
local MovementStateEvent = require(script.Parent.MovementStateEvent)
local EntityState = require(script.Parent.Parent.Core.EntityState)

local Resolver = {}
Resolver.__index = Resolver

local function copy(values)
	local result = {}
	for _, value in ipairs(values) do table.insert(result, value) end
	return result
end

function Resolver.new(world, profile)
	profile = profile or MovementStateProfile.new()
	if getmetatable(profile) ~= MovementStateProfile then profile = MovementStateProfile.new(profile) end
	return setmetatable({
		World = world, Profile = profile, Events = {}, Results = {}, Validators = {},
	}, Resolver)
end

function Resolver:_entity(entityOrId)
	if type(entityOrId) == "table" then return entityOrId end
	return self.World and self.World:GetEntity(entityOrId) or nil
end

function Resolver:_component(entityOrId)
	local entity = self:_entity(entityOrId)
	if not entity or entity.Destroyed then return nil, entity end
	return entity:GetComponent(MovementStateComponent), entity
end

function Resolver:_result(kind, entity, requested, frame, reason, accepted)
	local result = MovementStateResult.new({
		Type = kind, EntityId = entity and entity.Id, PreviousState = entity
			and entity:GetComponent(MovementStateComponent).CurrentState,
		CurrentState = entity and entity:GetComponent(MovementStateComponent).CurrentState,
		RequestedState = requested, Accepted = accepted == true, Reason = reason, Frame = frame,
	})
	table.insert(self.Results, result)
	return result
end

function Resolver:_event(eventType, entity, component, requested, frame, reason)
	local event = MovementStateEvent.new({
		Type = eventType, EntityId = entity and entity.Id, PreviousState = component and component.PreviousState,
		CurrentState = component and component.CurrentState, RequestedState = requested,
		Frame = frame, Reason = reason,
	})
	table.insert(self.Events, event)
	return event
end

function Resolver:GetComponent(entityOrId)
	local component = self:_component(entityOrId)
	return component
end

function Resolver:GetState(entityOrId)
	local component = self:_component(entityOrId)
	return component and component:GetState() or nil
end
function Resolver:GetPreviousState(entityOrId)
	local component = self:_component(entityOrId)
	return component and component:GetPreviousState() or nil
end
function Resolver:GetStateStartFrame(entityOrId)
	local component = self:_component(entityOrId)
	return component and component:GetStateStartFrame() or nil
end
function Resolver:IsState(entityOrId, state) return self:GetState(entityOrId) == state end
function Resolver:IsMoving(entityOrId) return self:IsState(entityOrId, "Moving") or self:IsState(entityOrId, "Dashing") end
function Resolver:IsCrouching(entityOrId) return self:IsState(entityOrId, "Crouching") end
function Resolver:IsDashing(entityOrId) return self:IsState(entityOrId, "Dashing") end
function Resolver:IsAirMovement(entityOrId)
	return self:IsState(entityOrId, "Jumping") or self:IsState(entityOrId, "Falling")
end

function Resolver:AddValidator(validator)
	assert(type(validator) == "function", "MovementStateResolver validator must be a function")
	table.insert(self.Validators, validator)
	return validator
end
function Resolver:RemoveValidator(validator)
	for index, current in ipairs(self.Validators) do
		if current == validator then table.remove(self.Validators, index); return true end
	end
	return false
end

function Resolver:CanTransition(entityOrId, targetState, context, frame)
	local component, entity = self:_component(entityOrId)
	if not entity or not component then return false, MovementStateResult.Type.InvalidEntity end
	if not self.Profile:IsValidState(targetState) then return false, MovementStateResult.Type.InvalidState end
	if entity:GetState() == EntityState.Dead then return false, "DeadEntity" end
	if component.CurrentState == targetState then return false, MovementStateResult.Type.AlreadyInState end
	if not self.Profile:Allows(component.CurrentState, targetState) then
		return false, "InvalidTransition"
	end
	local duration = self.Profile.StateDurations[component.CurrentState]
	local currentFrame = frame or (context and context.Frame) or (self.World and self.World.CurrentFrame) or 0
	if duration and duration.MinFrames and currentFrame - component.StateStartFrame < duration.MinFrames then
		return false, "MinimumDuration"
	end
	for _, validator in ipairs(self.Validators) do
		local allowed, reason = validator(entity, component.CurrentState, targetState, context, currentFrame)
		if allowed == false then return false, reason or "ExternalRule" end
	end
	return true
end

function Resolver:RequestTransition(entityOrId, targetState, context)
	context = context or {}
	local frame = context.Frame
	if frame == nil then frame = self.World and self.World.CurrentFrame or 0 end
	local component, entity = self:_component(entityOrId)
	if not entity or not component then
		local result = MovementStateResult.new({ Type = MovementStateResult.Type.InvalidEntity,
			EntityId = type(entityOrId) == "table" and entityOrId.Id or entityOrId,
			RequestedState = targetState, Accepted = false, Reason = "InvalidEntity", Frame = frame })
		table.insert(self.Results, result)
		return result
	end
	local allowed, reason = self:CanTransition(entity, targetState, context, frame)
	if not allowed then
		local kind = reason == MovementStateResult.Type.InvalidState and reason
			or reason == MovementStateResult.Type.AlreadyInState and reason
			or MovementStateResult.Type.Rejected
		local result = self:_result(kind, entity, targetState, frame, reason, false)
		self:_event(MovementStateEvent.Type.TransitionRejected, entity, component, targetState, frame, reason)
		return result
	end
	local previous = component.CurrentState
	component:SetState(targetState, frame)
	local result = MovementStateResult.new({
		Type = MovementStateResult.Type.Transitioned, EntityId = entity.Id,
		PreviousState = previous, CurrentState = targetState, RequestedState = targetState,
		Accepted = true, Reason = context.Reason, Frame = frame,
	})
	table.insert(self.Results, result)
	self:_event(MovementStateEvent.Type.StateChanged, entity, component, targetState, frame, context.Reason)
	return result
end

function Resolver:Reset(entityOrId, frame)
	local component, entity = self:_component(entityOrId)
	if not component then return false end
	component:Reset(frame or (self.World and self.World.CurrentFrame or 0))
	return true
end
function Resolver:GetEvents() return copy(self.Events) end
function Resolver:GetResults() return copy(self.Results) end
function Resolver:Clear() self.Events = {}; self.Results = {}; return self end

return Resolver
