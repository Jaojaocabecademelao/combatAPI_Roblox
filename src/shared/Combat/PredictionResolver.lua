local Component = require(script.Parent.PredictionComponent)
local Profile = require(script.Parent.PredictionProfile)
local Frame = require(script.Parent.PredictionFrame)
local State = require(script.Parent.PredictionState)
local InputFrame = require(script.Parent.InputFrame)
local InputState = require(script.Parent.InputState)
local Input = require(script.Parent.Input)
local PredictionSnapshot = require(script.Parent.PredictionSnapshot)
local Result = require(script.Parent.PredictionResult)
local Event = require(script.Parent.PredictionEvent)
local NetworkSnapshot = require(script.Parent.NetworkSnapshot)

local Resolver = {}
Resolver.__index = Resolver

local function validFrame(frame)
	return type(frame) == "number" and frame == frame and frame >= 0
		and frame < math.huge and frame % 1 == 0
end

local function entityIdOrder(a, b)
	local aType, bType = type(a), type(b)
	if aType ~= bType then return aType < bType end
	if aType == "number" then return a < b end
	return tostring(a) < tostring(b)
end

local function sortedEntityIds(states)
	local ids = {}
	for entityId in pairs(states) do table.insert(ids, entityId) end
	table.sort(ids, entityIdOrder)
	return ids
end

local function copyInputs(inputs)
	local copy = {}
	for inputId, state in pairs(inputs) do copy[inputId] = state end
	return copy
end

local validInputs, validStates = {}, {}
for _, inputId in pairs(Input) do validInputs[inputId] = true end
for _, inputState in pairs(InputState) do validStates[inputState] = true end

local function validInputFrame(inputFrame, entityId, frame)
	if type(inputFrame) ~= "table" or getmetatable(inputFrame) ~= InputFrame
		or inputFrame.Frame ~= frame or (inputFrame.EntityId ~= nil and inputFrame.EntityId ~= entityId)
		or type(inputFrame.Inputs) ~= "table" then
		return false
	end
	for inputId, inputState in pairs(inputFrame.Inputs) do
		if not validInputs[inputId] or not validStates[inputState] then return false end
	end
	return true
end

local function normalizeProfile(profile, fallback)
	if profile == nil then return fallback end
	if getmetatable(profile) == Profile then return profile end
	if type(profile) == "table" then
		local ok, normalized = pcall(Profile.new, profile)
		if ok then return normalized end
	end
	return nil
end

function Resolver.new(world, profile)
	local normalized = normalizeProfile(profile, Profile.new())
	assert(normalized, "PredictionResolver profile is invalid")
	return setmetatable({
		World = world,
		Profile = normalized,
		States = {},
		Events = {},
		Results = {},
	}, Resolver)
end

function Resolver:_result(kind, data)
	data = data or {}
	data.Type = kind
	local result = Result.new(data)
	table.insert(self.Results, result)
	return result
end

function Resolver:_emit(kind, data)
	data = data or {}
	data.Type = kind
	local event = Event.new(data)
	table.insert(self.Events, event)
	return event
end

function Resolver:_entity(entityOrId)
	if type(entityOrId) == "table" then
		if entityOrId.Id == nil or entityOrId.Destroyed then return nil end
		if self.World and self.World:GetEntity(entityOrId.Id) ~= entityOrId then return nil end
		return entityOrId
	end
	return self.World and self.World:GetEntity(entityOrId) or nil
end

function Resolver:_component(entity)
	return entity and entity:GetComponent(Component) or nil
end

function Resolver:RebindAfterWorldRestore()
	local reboundStates = {}
	for _, entity in ipairs(self.World:GetEntities()) do
		local component = self:_component(entity)
		if component and component.PredictionState then
			component.Resolver = self
			component.PredictionState.EntityId = entity.Id
			reboundStates[entity.Id] = component.PredictionState
		end
	end
	self.States = reboundStates
	return true
end

function Resolver:_state(entityOrId, requireEnabled)
	local entity = self:_entity(entityOrId)
	if not entity then return nil, nil, Result.Type.InvalidEntity end
	local component = self:_component(entity)
	local state = component and component.PredictionState
	if not component or not state or self.States[entity.Id] ~= state then
		return entity, nil, Result.Type.InvalidEntity
	end
	if requireEnabled and (not state.Enabled or not component:IsEnabled()) then
		return entity, state, Result.Type.AlreadyDisabled
	end
	return entity, state, nil
end

function Resolver:Enable(entityOrId, profile)
	local entity = self:_entity(entityOrId)
	if not entity then return self:_result(Result.Type.InvalidEntity) end
	local normalized = normalizeProfile(profile, self.Profile)
	if not normalized then return self:_result(Result.Type.InvalidProfile, { EntityId = entity.Id }) end

	local component = self:_component(entity)
	if component then
		local state = component.PredictionState
		if self.States[entity.Id] == state and state.Enabled and component:IsEnabled() then
			return self:_result(Result.Type.AlreadyEnabled, { EntityId = entity.Id })
		end
		if state.Profile ~= normalized then
			state = State.new(entity.Id, normalized)
			component.Profile, component.PredictionState = normalized, state
			self.States[entity.Id] = state
		end
		state.Enabled = true
		component.Resolver = self
		component:SetEnabled(true)
		self.States[entity.Id] = state
	else
		component = entity:AddComponent(Component.new(normalized))
		component.Resolver = self
		self.States[entity.Id] = component.PredictionState
	end

	self:_emit(Event.Type.Enabled, { EntityId = entity.Id })
	return self:_result(Result.Type.Success, { EntityId = entity.Id })
end

function Resolver:Disable(entityOrId)
	local entity, state, failure = self:_state(entityOrId, false)
	if failure then return self:_result(failure) end
	if not state.Enabled then
		return self:_result(Result.Type.AlreadyDisabled, { EntityId = entity.Id })
	end
	state.Enabled = false
	entity:GetComponent(Component):SetEnabled(false)
	self:_emit(Event.Type.Disabled, { EntityId = entity.Id, Frame = state.CurrentFrame })
	return self:_result(Result.Type.Success, { EntityId = entity.Id, Frame = state.CurrentFrame })
end

function Resolver:Begin(entityOrId, frame, inputFrame)
	local entity, state, failure = self:_state(entityOrId, true)
	if failure then return self:_result(failure, { EntityId = entity and entity.Id }) end
	if not validFrame(frame) then
		return self:_result(Result.Type.InvalidFrame, { EntityId = entity.Id, Frame = frame })
	end
	if state.Started then
		return self:_result(Result.Type.AlreadyStarted, { EntityId = entity.Id, Frame = frame })
	end
	if inputFrame ~= nil and not validInputFrame(inputFrame, entity.Id, frame) then
		return self:_result(Result.Type.InvalidInput, { EntityId = entity.Id, Frame = frame })
	end
	if inputFrame == nil then
		inputFrame = InputFrame.new({ Frame = frame, EntityId = entity.Id, Inputs = {}, Source = "PredictionSeed" })
	end

	local predictionFrame = Frame.new({
		EntityId = entity.Id, Frame = frame, InputFrame = inputFrame,
		Predicted = false, Confirmed = true, PredictionIndex = 0,
	})
	state.Started, state.CurrentFrame, state.ConfirmedFrame = true, frame, frame
	state.PredictionFrameCount = 0
	state.History:Put(frame, predictionFrame)
	self:_emit(Event.Type.Began, { EntityId = entity.Id, Frame = frame })
	return self:_result(Result.Type.Success, { EntityId = entity.Id, Frame = frame })
end

function Resolver:_predictedInputs(state, frame)
	local previous = state.History:Get(state.CurrentFrame)
	local inputs = copyInputs(previous and previous.Inputs or {})
	if state.Profile.InputPolicy == Profile.InputPolicy.Neutral then
		for inputId in pairs(inputs) do inputs[inputId] = InputState.None end
	else
		for inputId, inputState in pairs(inputs) do
			if inputState == InputState.Pressed then
				inputs[inputId] = InputState.Held
			elseif inputState == InputState.Released then
				inputs[inputId] = InputState.None
			end
		end
	end
	return InputFrame.new({
		Frame = frame, EntityId = state.EntityId, Inputs = inputs, Source = "Prediction",
	})
end

function Resolver:Advance(entityOrId, frame, inputFrame)
	local entity, state, failure = self:_state(entityOrId, true)
	if failure then return self:_result(failure, { EntityId = entity and entity.Id, Frame = frame }) end
	if not state.Started then
		return self:_result(Result.Type.NotStarted, { EntityId = entity.Id, Frame = frame })
	end
	if not validFrame(frame) then
		return self:_result(Result.Type.InvalidFrame, { EntityId = entity.Id, Frame = frame })
	end
	if frame ~= state.CurrentFrame + 1 then
		return self:_result(Result.Type.OutOfOrder, { EntityId = entity.Id, Frame = frame })
	end

	if inputFrame == nil and self.World and self.World:GetInputResolver() then
		inputFrame = self.World:GetInputResolver():GetInputFrame(entity, frame)
	end
	local predicted = inputFrame == nil
	if predicted then
		if state.PredictionFrameCount >= state.Profile.MaxPredictionFrames then
			return self:_result(Result.Type.MaxPredictionFrames, { EntityId = entity.Id, Frame = frame })
		end
		inputFrame = self:_predictedInputs(state, frame)
	elseif not validInputFrame(inputFrame, entity.Id, frame) then
		return self:_result(Result.Type.InvalidInput, { EntityId = entity.Id, Frame = frame })
	end

	local predictionIndex = predicted and state.PredictionFrameCount + 1 or 0
	local predictionFrame = Frame.new({
		EntityId = entity.Id, Frame = frame, InputFrame = inputFrame,
		Predicted = predicted, Confirmed = false, PredictionIndex = predictionIndex,
	})
	state.CurrentFrame = frame
	if predicted then state.PredictionFrameCount += 1 end
	state.History:Put(frame, predictionFrame)
	self:_emit(Event.Type.Advanced, {
		EntityId = entity.Id, Frame = frame, Predicted = predicted,
		PredictionIndex = predictionIndex,
	})
	return self:_result(Result.Type.Success, {
		EntityId = entity.Id, Frame = frame, Predicted = predicted,
		PredictionIndex = predictionIndex,
	})
end

function Resolver:AdvanceAll(frame, inputFrames)
	if inputFrames == nil then inputFrames = {} end
	local results = {}
	if type(inputFrames) ~= "table" then
		table.insert(results, self:_result(Result.Type.InvalidInput, { Frame = frame }))
		return results
	end
	for _, entityId in ipairs(sortedEntityIds(self.States)) do
		local state = self.States[entityId]
		if state.Enabled and state.Started then
			table.insert(results, self:Advance(entityId, frame, inputFrames[entityId]))
		end
	end
	return results
end

function Resolver:Confirm(entityOrId, frame)
	local entity, state, failure = self:_state(entityOrId, true)
	if failure then return self:_result(failure, { EntityId = entity and entity.Id, Frame = frame }) end
	if not state.Started then
		return self:_result(Result.Type.NotStarted, { EntityId = entity.Id, Frame = frame })
	end
	if not validFrame(frame) then
		return self:_result(Result.Type.InvalidFrame, { EntityId = entity.Id, Frame = frame })
	end
	if frame > state.CurrentFrame or not state.History:Has(frame) then
		return self:_result(Result.Type.UnknownFrame, { EntityId = entity.Id, Frame = frame })
	end
	if frame < state.ConfirmedFrame then
		return self:_result(Result.Type.OutOfOrder, { EntityId = entity.Id, Frame = frame })
	end

	for _, predictionFrame in ipairs(state.History:GetWindow(0, frame)) do
		predictionFrame.Confirmed = true
	end
	state.ConfirmedFrame = frame
	state.PredictionFrameCount = 0
	for _, predictionFrame in ipairs(state.History:GetWindow(frame + 1, state.CurrentFrame)) do
		if predictionFrame.Predicted then state.PredictionFrameCount += 1 end
	end
	local confirmed = state.History:Get(frame)
	self:_emit(Event.Type.Confirmed, { EntityId = entity.Id, Frame = frame })
	return self:_result(Result.Type.Success, {
		EntityId = entity.Id, Frame = frame,
		Predicted = confirmed.Predicted, PredictionIndex = confirmed.PredictionIndex,
	})
end

function Resolver:CompareSnapshot(networkSnapshot)
	if type(networkSnapshot) ~= "table" or getmetatable(networkSnapshot) ~= NetworkSnapshot
		or not validFrame(networkSnapshot.SimulationFrame)
		or type(networkSnapshot.Entities) ~= "table"
		or type(networkSnapshot.Components) ~= "table" then
		return self:_result(Result.Type.InvalidSnapshot)
	end
	local snapshot = PredictionSnapshot.new(networkSnapshot)
	local divergences = {}
	for _, entityId in ipairs(sortedEntityIds(self.States)) do
		local state = self.States[entityId]
		if state.Enabled then
			local predictionFrame = state.History:Get(snapshot.SimulationFrame)
			if predictionFrame then
				for _, divergence in ipairs(snapshot:CompareFrame(entityId, predictionFrame)) do
					table.insert(divergences, divergence)
				end
			end
		end
	end
	table.sort(divergences, function(a, b)
		if a.EntityId ~= b.EntityId then return entityIdOrder(a.EntityId, b.EntityId) end
		if a.Path ~= b.Path then return a.Path < b.Path end
		return a.Kind < b.Kind
	end)
	if #divergences > 0 then
		self:_emit(Event.Type.Divergence, {
			Frame = networkSnapshot.SimulationFrame, Divergences = divergences,
		})
	end
	return self:_result(Result.Type.Success, {
		Frame = networkSnapshot.SimulationFrame, Divergences = divergences,
	})
end

function Resolver:GetState(entityOrId)
	local _, state, failure = self:_state(entityOrId, false)
	if failure then return nil end
	return state
end

function Resolver:GetFrame(entityOrId, frame)
	local state = self:GetState(entityOrId)
	return state and state.History:Get(frame) or nil
end

function Resolver:CanReplaceReplayedFrame(frame, inputFrames)
	if not validFrame(frame) or type(inputFrames) ~= "table" then return false end
	for _, entityId in ipairs(sortedEntityIds(self.States)) do
		local state = self.States[entityId]
		local previous = state.History:Get(frame)
		local inputFrame = inputFrames[entityId]
		if state.Enabled and previous and inputFrame and not previous.Confirmed then
			if not validInputFrame(inputFrame, entityId, frame) then return false end
		end
	end
	return true
end

function Resolver:ReplaceReplayedFrame(frame, inputFrames)
	if not self:CanReplaceReplayedFrame(frame, inputFrames) then return false end
	local replacements = {}
	for _, entityId in ipairs(sortedEntityIds(self.States)) do
		local state = self.States[entityId]
		local previous = state.History:Get(frame)
		local inputFrame = inputFrames[entityId]
		if state.Enabled and previous and inputFrame and not previous.Confirmed then
			table.insert(replacements, { State = state, Frame = Frame.new({
				EntityId = entityId,
				Frame = frame,
				InputFrame = inputFrame,
				Predicted = previous.Predicted,
				Confirmed = false,
				PredictionIndex = previous.PredictionIndex,
			}) })
		end
	end
	for _, replacement in ipairs(replacements) do
		replacement.State.History:Put(frame, replacement.Frame)
	end
	return true
end

function Resolver:GetHistory(entityOrId, startFrame, endFrame)
	local state = self:GetState(entityOrId)
	if not state then return {} end
	if startFrame == nil then startFrame = state.History.Order[1] or 0 end
	if endFrame == nil then endFrame = state.CurrentFrame or startFrame end
	return state.History:GetWindow(startFrame, endFrame)
end

function Resolver:RewindToFrame(frame)
	if not validFrame(frame) then return false end
	for _, state in pairs(self.States) do
		if state.Started then
			state.History:RemoveAfter(frame)
			if state.History:Has(frame) then
				state.CurrentFrame = frame
				state.ConfirmedFrame = math.min(state.ConfirmedFrame, frame)
				state.PredictionFrameCount = 0
				for _, predictionFrame in ipairs(state.History:GetWindow(state.ConfirmedFrame + 1, frame)) do
					if predictionFrame.Predicted then state.PredictionFrameCount += 1 end
				end
			else
				state:Reset()
			end
		end
	end
	return true
end

function Resolver:RemoveEntity(entityOrId)
	local entity = self:_entity(entityOrId)
	if not entity then return false end
	local component = self:_component(entity)
	if not component then return false end
	self.States[entity.Id] = nil
	self:_emit(Event.Type.Removed, { EntityId = entity.Id, Frame = component.PredictionState.CurrentFrame })
	entity:RemoveComponent(Component)
	return true
end

function Resolver:_onComponentRemoved(component)
	local state = component.PredictionState
	if not state or self.States[component.EntityId] ~= state then return end
	self.States[component.EntityId] = nil
	self:_emit(Event.Type.Removed, { EntityId = component.EntityId, Frame = state.CurrentFrame })
end

function Resolver:GetEvents()
	local result = table.clone(self.Events)
	table.sort(result, function(a, b)
		if a.Frame ~= b.Frame then
			if a.Frame == nil then return true end
			if b.Frame == nil then return false end
			return a.Frame < b.Frame
		end
		if a.EntityId ~= b.EntityId then
			if a.EntityId == nil then return true end
			if b.EntityId == nil then return false end
			return entityIdOrder(a.EntityId, b.EntityId)
		end
		return a.Type < b.Type
	end)
	return result
end

function Resolver:GetResults()
	return table.clone(self.Results)
end

function Resolver:Clear()
	self.Events, self.Results = {}, {}
	return self
end

return Resolver
