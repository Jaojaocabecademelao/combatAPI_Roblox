local CharacterComponent = require(script.Parent.CharacterComponent)
local CharacterProfile = require(script.Parent.CharacterProfile)
local CharacterResult = require(script.Parent.CharacterResult)
local CharacterEvent = require(script.Parent.CharacterEvent)
local CharacterRepresentation = require(script.Parent.CharacterRepresentation)
local EntityState = require(script.Parent.Parent.Core.EntityState)

local Resolver = {}
Resolver.__index = Resolver

local function validFrame(frame)
	return type(frame) == "number" and frame == frame and frame >= 0
		and frame < math.huge and frame % 1 == 0
end

function Resolver.new(world, options)
	options = options or {}
	local self = setmetatable({
		World = world, Profiles = {}, Adapters = {}, Components = {},
		Events = {}, Results = {}, Listeners = {},
	}, Resolver)
	for _, profile in ipairs(options.Profiles or {}) do self:RegisterProfile(profile) end
	for id, adapter in pairs(options.Adapters or {}) do self:RegisterAdapter(id, adapter) end
	return self
end

function Resolver:_frame(options)
	local frame = options and options.Frame
	if frame == nil then frame = self.World.CurrentFrame end
	return validFrame(frame) and frame or nil
end

function Resolver:_entity(entityOrId)
	if type(entityOrId) == "table" then return entityOrId end
	return self.World and self.World:GetEntity(entityOrId) or nil
end

function Resolver:_component(entityOrId)
	local entity = self:_entity(entityOrId)
	if not entity or entity.Destroyed then return nil, entity end
	local component = entity:GetComponent(CharacterComponent)
	if not component then
		component = entity:AddComponent(CharacterComponent.new())
	end
	return component, entity
end

function Resolver:_result(kind, entity, frame, data)
	data = data or {}
	data.Type, data.EntityId, data.Frame = kind, entity and entity.Id, frame
	data.Accepted = kind == CharacterResult.Type.Success
	local result = CharacterResult.new(data)
	table.insert(self.Results, result)
	return result
end

function Resolver:_emit(eventType, data)
	data.Type = eventType
	local event = CharacterEvent.new(data)
	table.insert(self.Events, event)
	for _, callback in ipairs(self.Listeners[eventType] or {}) do callback(event) end
	return event
end

function Resolver:On(eventType, callback)
	assert(type(eventType) == "string" and type(callback) == "function", "Character listener is invalid")
	self.Listeners[eventType] = self.Listeners[eventType] or {}
	table.insert(self.Listeners[eventType], callback)
	return callback
end

function Resolver:RegisterProfile(profile)
	if getmetatable(profile) ~= CharacterProfile then return false end
	self.Profiles[profile.CharacterId] = profile
	return true
end
function Resolver:GetProfile(characterId) return self.Profiles[characterId] end
function Resolver:RemoveProfile(characterId) self.Profiles[characterId] = nil; return true end
function Resolver:RegisterAdapter(adapterId, adapter)
	if type(adapterId) ~= "string" or type(adapter) ~= "table"
		or type(adapter.Validate) ~= "function" then return false end
	self.Adapters[adapterId] = adapter
	return true
end
function Resolver:GetAdapterDefinition(adapterId) return self.Adapters[adapterId] end
function Resolver:RemoveAdapter(adapterId) self.Adapters[adapterId] = nil; return true end

function Resolver:_prepare(entity, representation, options)
	if representation == nil then return nil, CharacterResult.Type.InvalidRepresentation end
	local profile = options and options.Profile or self.Profiles[options and options.CharacterId]
	if not profile and options and options.CharacterProfile then profile = options.CharacterProfile end
	if getmetatable(profile) ~= CharacterProfile then return nil, CharacterResult.Type.InvalidProfile end
	local adapter = options.Adapter or self.Adapters[profile.AdapterId]
	if not adapter then return nil, CharacterResult.Type.InvalidAdapter end
	if not adapter:Validate(representation, { EntityId = entity.Id, Profile = profile }) then
		return nil, CharacterResult.Type.AdapterRejected
	end
	return { Profile = profile, Adapter = adapter }
end

function Resolver:Attach(entityOrId, representation, options)
	options = options or {}
	local component, entity = self:_component(entityOrId)
	local frame = self:_frame(options)
	if not frame then return self:_result(CharacterResult.Type.InvalidOperation, entity, frame) end
	if not entity then return self:_result(CharacterResult.Type.InvalidEntity, nil, frame) end
	if representation == nil then return self:_result(CharacterResult.Type.InvalidRepresentation, entity, frame) end
	if entity.State == EntityState.Dead then return self:_result(CharacterResult.Type.EntityDead, entity, frame) end
	if component.Attached then return self:_result(CharacterResult.Type.AlreadyAttached, entity, frame) end
	local prepared, failure = self:_prepare(entity, representation, options)
	if not prepared then
		self:_emit(CharacterEvent.Type.AttachFailed, { EntityId = entity.Id, Frame = frame, Result = failure })
		return self:_result(failure, entity, frame)
	end
	local ok = prepared.Adapter:AttachRepresentation(entity.Id, representation, { Frame = frame, Profile = prepared.Profile })
	if not ok then
		self:_emit(CharacterEvent.Type.AttachFailed, { EntityId = entity.Id, Frame = frame, Result = CharacterResult.Type.AttachFailed })
		return self:_result(CharacterResult.Type.AttachFailed, entity, frame)
	end
	component.Profile, component.Adapter, component.Representation = prepared.Profile, prepared.Adapter, representation
	component.CharacterId, component.Attached, component.Lifecycle = prepared.Profile.CharacterId, true, "Attached"
	component.AttachedFrame, component.DetachedFrame = frame, nil
	local result = self:_result(CharacterResult.Type.Success, entity, frame, { CharacterId = component.CharacterId })
	self:_emit(CharacterEvent.Type.Attached, { EntityId = entity.Id, CharacterId = component.CharacterId, Frame = frame, NewRepresentation = representation, Result = result })
	return result
end

function Resolver:Detach(entityOrId, options)
	options = options or {}
	local component, entity = self:_component(entityOrId)
	local frame = self:_frame(options)
	if not entity then return self:_result(CharacterResult.Type.InvalidEntity, nil, frame) end
	if not frame then return self:_result(CharacterResult.Type.InvalidOperation, entity, frame) end
	if not component.Attached then return self:_result(CharacterResult.Type.NotAttached, entity, frame) end
	local previous = component.Representation
	if not component.Adapter:DetachRepresentation(entity.Id, previous, { Frame = frame }) then
		self:_emit(CharacterEvent.Type.DetachFailed, { EntityId = entity.Id, Frame = frame, Result = CharacterResult.Type.DetachFailed })
		return self:_result(CharacterResult.Type.DetachFailed, entity, frame)
	end
	local characterId = component.CharacterId
	component:Reset()
	component.DetachedFrame = frame
	local result = self:_result(CharacterResult.Type.Success, entity, frame, { CharacterId = characterId })
	self:_emit(CharacterEvent.Type.Detached, { EntityId = entity.Id, CharacterId = characterId, Frame = frame, PreviousRepresentation = previous, Result = result })
	return result
end

function Resolver:Reattach(entityOrId, representation, options)
	options = options or {}
	local component, entity = self:_component(entityOrId)
	local frame = self:_frame(options)
	if not entity then return self:_result(CharacterResult.Type.InvalidEntity, nil, frame) end
	if entity.State == EntityState.Dead then return self:_result(CharacterResult.Type.EntityDead, entity, frame) end
	if not component.Attached then return self:Attach(entity, representation, options) end
	local prepared, failure = self:_prepare(entity, representation, options)
	if not prepared then return self:_result(failure, entity, frame) end
	local oldRepresentation, oldAdapter, oldProfile = component.Representation, component.Adapter, component.Profile
	if not prepared.Adapter:AttachRepresentation(entity.Id, representation, { Frame = frame, Profile = prepared.Profile }) then
		return self:_result(CharacterResult.Type.AttachFailed, entity, frame)
	end
	if not oldAdapter:DetachRepresentation(entity.Id, oldRepresentation, { Frame = frame, Profile = oldProfile }) then
		prepared.Adapter:DetachRepresentation(entity.Id, representation, { Frame = frame, Profile = prepared.Profile })
		return self:_result(CharacterResult.Type.DetachFailed, entity, frame)
	end
	component.Profile, component.Adapter, component.Representation = prepared.Profile, prepared.Adapter, representation
	component.CharacterId, component.AttachedFrame, component.Attached, component.Lifecycle = prepared.Profile.CharacterId, frame, true, "Attached"
	local result = self:_result(CharacterResult.Type.Success, entity, frame, { CharacterId = component.CharacterId })
	self:_emit(CharacterEvent.Type.Reattached, { EntityId = entity.Id, CharacterId = component.CharacterId, Frame = frame, PreviousRepresentation = oldRepresentation, NewRepresentation = representation, Result = result })
	return result
end

function Resolver:IsAttached(entityOrId) local c = self:_component(entityOrId); return c ~= nil and c.Attached end
function Resolver:IsValid(entityOrId) local c, e = self:_component(entityOrId); return e ~= nil and c ~= nil end
function Resolver:GetCharacter(entityOrId)
	local component = self:_component(entityOrId)
	return component and (component.Attached or component.DetachedFrame ~= nil) and component or nil
end
function Resolver:GetCharacterId(entityOrId) local c = self:GetCharacter(entityOrId); return c and c.CharacterId end
function Resolver:GetRepresentation(entityOrId) local c = self:GetCharacter(entityOrId); return c and c.Representation end
function Resolver:GetAdapter(entityOrId) local c = self:GetCharacter(entityOrId); return c and c.Adapter end
function Resolver:GetEvents() return table.clone(self.Events) end
function Resolver:GetResults() return table.clone(self.Results) end
function Resolver:Clear() self.Events, self.Results = {}, {}; return self end

return Resolver
