local AnimationComponent = require(script.Parent.AnimationComponent)
local AnimationDefinition = require(script.Parent.AnimationDefinition)
local AnimationProfile = require(script.Parent.AnimationProfile)
local AnimationTrack = require(script.Parent.AnimationTrack)
local AnimationResult = require(script.Parent.AnimationResult)
local AnimationEvent = require(script.Parent.AnimationEvent)
local CharacterComponent = require(script.Parent.CharacterComponent)
local EntityState = require(script.Parent.Parent.Core.EntityState)

local Resolver = {}
Resolver.__index = Resolver
local function frameOf(world, options)
	local frame = options and options.Frame
	if frame == nil then frame = world.CurrentFrame end
	if type(frame) ~= "number" or frame < 0 or frame % 1 ~= 0 or frame == math.huge then return nil end
	return frame
end

function Resolver.new(world, options)
	options = options or {}
	local self = setmetatable({ World = world, Profiles = {}, Definitions = {}, Adapters = {},
		Events = {}, Results = {}, Listeners = {}, NextTrackId = 0 }, Resolver)
	self.Profile = options.Profile
	if self.Profile then self:RegisterProfile(self.Profile) end
	for _, definition in ipairs(options.Definitions or {}) do self:RegisterAnimation(definition) end
	for id, adapter in pairs(options.Adapters or {}) do self:RegisterAdapter(id, adapter) end
	return self
end
function Resolver:_entity(value) if type(value) == "table" then return value end; return self.World:GetEntity(value) end
function Resolver:_component(value, create)
	local entity = self:_entity(value)
	if not entity or entity.Destroyed then return nil, entity end
	local component = entity:GetComponent(AnimationComponent)
	if not component and create then component = entity:AddComponent(AnimationComponent.new()) end
	return component, entity
end
function Resolver:_result(kind, entity, frame, data)
	data = data or {}; data.Type, data.EntityId, data.Frame, data.Accepted = kind, entity and entity.Id, frame, kind == "Success"
	local result = AnimationResult.new(data); table.insert(self.Results, result); return result
end
function Resolver:_emit(kind, data)
	data.Type = kind
	local event = AnimationEvent.new(data); table.insert(self.Events, event)
	for _, callback in ipairs(self.Listeners[kind] or {}) do callback(event) end
	return event
end
function Resolver:On(kind, callback)
	assert(type(kind) == "string" and type(callback) == "function", "Animation listener is invalid")
	self.Listeners[kind] = self.Listeners[kind] or {}; table.insert(self.Listeners[kind], callback); return callback
end
function Resolver:RegisterProfile(profile)
	if getmetatable(profile) ~= AnimationProfile then return false end
	self.Profiles[profile.Id] = profile
	for id, definition in pairs(profile.Definitions) do self.Definitions[id] = definition end
	return true
end
function Resolver:GetProfile(id) return self.Profiles[id] end
function Resolver:RegisterAnimation(definition)
	if getmetatable(definition) ~= AnimationDefinition then return false end
	self.Definitions[definition.Id] = definition; return true
end
function Resolver:GetAnimation(id) return self.Definitions[id] end
function Resolver:RemoveAnimation(id) self.Definitions[id] = nil; return true end
function Resolver:RegisterAdapter(id, adapter)
	if type(id) ~= "string" or type(adapter) ~= "table" or type(adapter.Validate) ~= "function" then return false end
	self.Adapters[id] = adapter; return true
end
function Resolver:GetAdapterDefinition(id) return self.Adapters[id] end
function Resolver:RemoveAdapter(id) self.Adapters[id] = nil; return true end
function Resolver:_findTrack(trackId)
	for _, component in pairs(self.Components or {}) do
		if component.CurrentTracks[trackId] then return component, component.CurrentTracks[trackId] end
	end
	for _, entity in ipairs(self.World:GetEntities()) do
		local component = entity:GetComponent(AnimationComponent)
		if component and component.CurrentTracks[trackId] then return component, component.CurrentTracks[trackId] end
	end
	return nil
end
function Resolver:_character(entity)
	local characterResolver = self.World:GetCharacterResolver()
	local component = characterResolver and characterResolver:GetCharacter(entity)
	return component and component.Attached and component or nil
end
function Resolver:Play(entityOrId, animationId, options)
	options = options or {}
	local frame = frameOf(self.World, options)
	local component, entity = self:_component(entityOrId, true)
	if not frame then return self:_result(AnimationResult.Type.InvalidTrack, entity, frame) end
	if not entity then return self:_result(AnimationResult.Type.InvalidEntity, nil, frame) end
	if entity.State == EntityState.Dead then return self:_result(AnimationResult.Type.EntityDead, entity, frame) end
	local character = self:_character(entity)
	if not character then return self:_result(AnimationResult.Type.NotAttached, entity, frame) end
	local definition = self.Definitions[animationId]
	if not definition then return self:_result(AnimationResult.Type.InvalidAnimation, entity, frame) end
	local adapter = options.Adapter or self.Adapters[options.AdapterId or "Mock"] or self.Adapters[definition.AdapterId]
	if not adapter then return self:_result(AnimationResult.Type.InvalidAdapter, entity, frame) end
	if not adapter:Validate(entity, definition, { Character = character, Frame = frame }) then
		return self:_result(AnimationResult.Type.AdapterRejected, entity, frame)
	end
	for _, track in pairs(component.CurrentTracks) do
		if track.AnimationId == animationId and track.State == AnimationTrack.State.Playing then
			return self:_result(AnimationResult.Type.AlreadyPlaying, entity, frame, { TrackId = track.TrackId })
		end
	end
	self.NextTrackId += 1
	local track = AnimationTrack.new({ TrackId = self.NextTrackId, EntityId = entity.Id, AnimationId = animationId,
		Definition = definition, StartFrame = frame, Speed = options.Speed or definition.Speed,
		Weight = options.Weight or definition.Weight, Priority = options.Priority or definition.Priority, Adapter = adapter })
	if not adapter:Call("Play", track, entity, character) then
		return self:_result(AnimationResult.Type.PlayFailed, entity, frame)
	end
	component.CurrentTracks[track.TrackId], component.ActiveAnimations[track.AnimationId] = track, track.TrackId
	table.insert(component.TrackOrder, track.TrackId); component.CurrentFrame = frame
	local result = self:_result(AnimationResult.Type.Success, entity, frame, { TrackId = track.TrackId, AnimationId = animationId })
	self:_emit(AnimationEvent.Type.Started, { EntityId = entity.Id, TrackId = track.TrackId, AnimationId = animationId, Frame = frame, Result = result })
	return result
end
function Resolver:_operate(trackId, operation, state, failure, frame)
	local component, track = self:_findTrack(trackId)
	if not component or not track then return self:_result(AnimationResult.Type.InvalidTrack, nil, frame) end
	local entity = self.World:GetEntity(track.EntityId)
	if track.State == state then return self:_result(failure, entity, frame, { TrackId = trackId }) end
	if operation == "Pause" and track.State ~= AnimationTrack.State.Playing then return self:_result(AnimationResult.Type.NotPlaying, entity, frame, { TrackId = trackId }) end
	if operation == "Resume" and track.State ~= AnimationTrack.State.Paused then return self:_result(AnimationResult.Type.NotPaused, entity, frame, { TrackId = trackId }) end
	if operation == "Stop" and track.State == AnimationTrack.State.Stopped then return self:_result(AnimationResult.Type.AlreadyStopped, entity, frame, { TrackId = trackId }) end
	if not track.Adapter:Call(operation, track, entity, self:_character(entity)) then
		return self:_result(operation .. "Failed", entity, frame, { TrackId = trackId })
	end
	track.State = state; track.CurrentFrame = frame
	local result = self:_result(AnimationResult.Type.Success, entity, frame, { TrackId = trackId, AnimationId = track.AnimationId })
	local eventType = ({ Pause = AnimationEvent.Type.Paused, Resume = AnimationEvent.Type.Resumed, Stop = AnimationEvent.Type.Stopped })[operation]
	self:_emit(eventType, { EntityId = entity.Id, TrackId = trackId, AnimationId = track.AnimationId, Frame = frame, Result = result })
	return result
end
function Resolver:Pause(trackId, options) local f = frameOf(self.World, options); return self:_operate(trackId, "Pause", AnimationTrack.State.Paused, AnimationResult.Type.AlreadyPaused, f) end
function Resolver:Resume(trackId, options) local f = frameOf(self.World, options); return self:_operate(trackId, "Resume", AnimationTrack.State.Playing, AnimationResult.Type.NotPaused, f) end
function Resolver:Stop(trackId, options) local f = frameOf(self.World, options); return self:_operate(trackId, "Stop", AnimationTrack.State.Stopped, AnimationResult.Type.AlreadyStopped, f) end
function Resolver:NotifyCompleted(trackId, frame)
	local component, track = self:_findTrack(trackId); local entity = track and self.World:GetEntity(track.EntityId)
	if not component or not track then return self:_result(AnimationResult.Type.InvalidTrack, nil, frame) end
	if track.Definition.Loop then track.CurrentFrame = frame; track.ElapsedFrames = (frame - track.StartFrame) % track.Definition.DurationFrames; return self:_result(AnimationResult.Type.Success, entity, frame, { TrackId = trackId }) end
	track.State = AnimationTrack.State.Completed; track.CurrentFrame = frame
	local result = self:_result(AnimationResult.Type.Completed, entity, frame, { TrackId = trackId, AnimationId = track.AnimationId })
	self:_emit(AnimationEvent.Type.Completed, { EntityId = entity.Id, TrackId = trackId, AnimationId = track.AnimationId, Frame = frame, Result = result }); return result
end
function Resolver:SetSpeed(trackId, speed, options)
	local component, track = self:_findTrack(trackId); local entity = track and self.World:GetEntity(track.EntityId); local f = frameOf(self.World, options)
	if not track or type(speed) ~= "number" or speed < 0 then return self:_result(AnimationResult.Type.InvalidTrack, entity, f) end
	if not track.Adapter:Call("SetSpeed", track, speed) then return self:_result(AnimationResult.Type.AdapterRejected, entity, f) end
	track.Speed = speed; return self:_result(AnimationResult.Type.Success, entity, f, { TrackId = trackId })
end
function Resolver:SetWeight(trackId, weight, options)
	local component, track = self:_findTrack(trackId); local entity = track and self.World:GetEntity(track.EntityId); local f = frameOf(self.World, options)
	if not track or type(weight) ~= "number" or weight < 0 then return self:_result(AnimationResult.Type.InvalidTrack, entity, f) end
	if not track.Adapter:Call("SetWeight", track, weight) then return self:_result(AnimationResult.Type.AdapterRejected, entity, f) end
	track.Weight = weight; return self:_result(AnimationResult.Type.Success, entity, f, { TrackId = trackId })
end
function Resolver:SetPriority(trackId, priority, options)
	local component, track = self:_findTrack(trackId); local entity = track and self.World:GetEntity(track.EntityId); local f = frameOf(self.World, options)
	if not track or (type(priority) ~= "string" and type(priority) ~= "number") then return self:_result(AnimationResult.Type.InvalidTrack, entity, f) end
	if not track.Adapter:Call("SetPriority", track, priority) then return self:_result(AnimationResult.Type.AdapterRejected, entity, f) end
	track.Priority = priority; return self:_result(AnimationResult.Type.Success, entity, f, { TrackId = trackId })
end
function Resolver:GetTrack(trackId) local _, track = self:_findTrack(trackId); return track end
function Resolver:GetTracks(entityOrId)
	local component = self:_component(entityOrId); local result = {}
	if component then for _, id in ipairs(component.TrackOrder) do if component.CurrentTracks[id] then table.insert(result, component.CurrentTracks[id]) end end end
	return result
end
function Resolver:IsPlaying(trackId) local t = self:GetTrack(trackId); return t ~= nil and t:IsPlaying() end
function Resolver:IsPaused(trackId) local t = self:GetTrack(trackId); return t ~= nil and t:IsPaused() end
function Resolver:IsStopped(trackId) local t = self:GetTrack(trackId); return t == nil or t:IsStopped() end
function Resolver:Advance(entityOrId, frame)
	local tracks = self:GetTracks(entityOrId); for _, track in ipairs(tracks) do track:Advance(frame) end
	return tracks
end
function Resolver:GetEvents() return table.clone(self.Events) end
function Resolver:GetResults() return table.clone(self.Results) end
function Resolver:Clear() self.Events, self.Results = {}, {}; return self end
return Resolver
