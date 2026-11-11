local Component = require(script.Parent.RollbackComponent)
local Profile = require(script.Parent.RollbackProfile)
local State = require(script.Parent.RollbackState)
local Scope = require(script.Parent.RollbackScope)
local Snapshot = require(script.Parent.RollbackSnapshot)
local Frame = require(script.Parent.RollbackFrame)
local History = require(script.Parent.RollbackHistory)
local Request = require(script.Parent.RollbackRequest)
local Result = require(script.Parent.RollbackResult)
local Event = require(script.Parent.RollbackEvent)
local InputComponent = require(script.Parent.InputComponent)
local InputFrame = require(script.Parent.InputFrame)
local InputState = require(script.Parent.InputState)
local PredictionComponent = require(script.Parent.PredictionComponent)
local RollbackComponent = require(script.Parent.RollbackComponent)
local EntityState = require(script.Parent.Parent.Core.EntityState)

local Resolver = {}
Resolver.__index = Resolver

local function validFrame(frame)
	return type(frame) == "number" and frame == frame and frame >= 0
		and frame < math.huge and frame % 1 == 0
end

local function sameProfile(a, b)
	for _, key in ipairs({
		"Enabled", "MaxRollbackFrames", "MaxReplayFrames", "HistorySize",
		"MaxSnapshotEntries", "MaxSnapshotDepth",
		"AllowSameFrameRollback", "AbortOnMissingInput", "AbortOnMissingSnapshot",
		"RecordReplayFrames",
	}) do
		if a[key] ~= b[key] then return false end
	end
	return true
end

local function idOrder(a, b)
	if type(a) ~= type(b) then return type(a) < type(b) end
	if type(a) == "number" or type(a) == "string" then return a < b end
	return tostring(a) < tostring(b)
end

local function sortedEntities(world)
	local entities = world:GetEntities()
	table.sort(entities, function(a, b) return idOrder(a.Id, b.Id) end)
	return entities
end

local function normalizeProfile(profile, fallback)
	if profile == nil then return fallback end
	if getmetatable(profile) == Profile then return profile end
	if type(profile) ~= "table" then return nil end
	local ok, value = pcall(Profile.new, profile)
	return ok and value or nil
end

function Resolver.new(world, profile)
	local normalized = normalizeProfile(profile, Profile.new())
	assert(normalized, "RollbackResolver profile is invalid")
	return setmetatable({
		World = world,
		Profile = normalized,
		Components = {},
		History = History.new(normalized.HistorySize),
		Events = {},
		Results = {},
		Active = false,
		PendingRequest = nil,
		Metrics = {
			SnapshotsCaptured = 0,
			RollbacksStarted = 0,
			RollbacksCompleted = 0,
			RollbacksFailed = 0,
			ReplayFrames = 0,
		},
	}, Resolver)
end

function Resolver:_result(kind, data)
	data = data or {}
	data.Type = kind
	local result = Result.new(data)
	table.insert(self.Results, result)
	return result
end

function Resolver:_emit(kind, request, extra)
	local data = extra or {}
	data.Type = kind
	if request then
		data.FromFrame = request.FromFrame
		data.ToFrame = request.ToFrame
		data.Reason = request.Reason
		data.EntityId = request.EntityId
	end
	data.ExecutionContext = data.ExecutionContext or self.World:GetExecutionContext() or "Normal"
	local event = Event.new(data)
	table.insert(self.Events, event)
	return event
end

function Resolver:_world(worldOrEntity)
	if worldOrEntity == nil then return self.World end
	if worldOrEntity == self.World then return self.World end
	if type(worldOrEntity) == "table" and worldOrEntity.Id ~= nil then
		if worldOrEntity.World ~= self.World or self.World:GetEntity(worldOrEntity.Id) ~= worldOrEntity
			or worldOrEntity.Destroyed then
			return nil
		end
		return self.World
	end
	return nil
end

function Resolver:_hasEnabledComponent()
	for entityId, component in pairs(self.Components) do
		local entity = self.World:GetEntity(entityId)
		if entity and entity:GetComponent(Component) == component and component:IsEnabled() then
			return true
		end
	end
	return false
end

function Resolver:Enable(entityOrId, profile)
	if self.Active then return self:_result(Result.Type.RollbackAlreadyInProgress) end
	local entity = self:_currentEntity(entityOrId)
	if not entity or entity.Destroyed then
		return self:_result(Result.Type.InvalidEntity)
	end
	local normalized = normalizeProfile(profile, self.Profile)
	if not normalized then
		return self:_result(Result.Type.InvalidRequest, { EntityId = entity.Id, Detail = "Invalid profile" })
	end
	if not normalized.Enabled then
		return self:_result(Result.Type.Disabled, { EntityId = entity.Id })
	end
	if not sameProfile(self.Profile, normalized) and self.History:Count() > 0 then
		return self:_result(Result.Type.InvalidRequest, {
			EntityId = entity.Id, Detail = "Cannot change rollback profile while history is populated",
		})
	end
	local component = entity:GetComponent(Component)
	if component then
		component.Profile = normalized
		component:SetEnabled(true)
	else
		component = entity:AddComponent(Component.new(normalized))
	end
	self.Components[entity.Id] = component
	component.Resolver = self
	if not sameProfile(self.Profile, normalized) then
		self.Profile = normalized
		self.History = History.new(normalized.HistorySize)
	end
	return self:_result(Result.Type.Success, { EntityId = entity.Id })
end

function Resolver:Disable(entityOrId)
	if self.Active then return self:_result(Result.Type.RollbackAlreadyInProgress) end
	local entity = self:_currentEntity(entityOrId)
	local component = entity and entity:GetComponent(Component)
	if not component or self.Components[entity.Id] ~= component then
		return self:_result(Result.Type.InvalidEntity)
	end
	component:SetEnabled(false)
	return self:_result(Result.Type.Success, { EntityId = entity.Id })
end

local function componentRollbackKey(component)
	local componentType = getmetatable(component)
	return component.RollbackKey or (componentType and componentType.RollbackKey)
end

function Resolver:_capture(world, frame, confirmed)
	local simulation = world:GetSimulation()
	if not simulation or simulation:GetWorld() ~= world or simulation.GameTime:GetFrame() ~= frame
		or world.CurrentFrame ~= frame then
		return nil, Result.Type.InvalidSimulation, "World and Simulation frames must match"
	end
	local worldIdGenerator = world.IdGenerator
	if not worldIdGenerator or type(worldIdGenerator.LastId) ~= "number"
		or worldIdGenerator.LastId ~= worldIdGenerator.LastId
		or worldIdGenerator.LastId % 1 ~= 0 then
		return nil, Result.Type.UnsupportedWorld, "World ID generator has no rollback state contract"
	end
	local entities, inputFrames = {}, {}
	for _, entity in ipairs(sortedEntities(world)) do
		local components, seenKeys = {}, {}
		local componentTypes = {}
		for componentType in pairs(entity.Components) do table.insert(componentTypes, componentType) end
		table.sort(componentTypes, function(a, b)
			local ka, kb = tostring(a.RollbackKey or a), tostring(b.RollbackKey or b)
			return ka < kb
		end)
		for _, componentType in ipairs(componentTypes) do
			local component = entity.Components[componentType]
			if componentType ~= RollbackComponent and componentType ~= PredictionComponent then
				local key = componentRollbackKey(component)
				if type(key) ~= "string" or key == ""
					or seenKeys[key]
					or type(component.CaptureRollbackState) ~= "function"
					or type(component.RestoreRollbackState) ~= "function" then
					return nil, Result.Type.UnsupportedComponent,
						("Entity %s has a component without a unique rollback contract"):format(tostring(entity.Id))
				end
				seenKeys[key] = true
				local ok, componentState = pcall(component.CaptureRollbackState, component)
				if not ok then
					return nil, Result.Type.UnsupportedComponent,
						("Component %s capture failed: %s"):format(key, tostring(componentState))
				end
				local copiedOk, copied = pcall(Snapshot.CloneSerializable, componentState, self.Profile)
				if not copiedOk then
					return nil, Result.Type.UnsupportedComponent,
						("Component %s returned non-serializable state: %s"):format(key, tostring(copied))
				end
				table.insert(components, {
					Key = key,
					Enabled = component:IsEnabled(),
					State = copied,
				})
			end
		end
		table.insert(entities, {
			Id = entity.Id,
			State = entity.State,
			Components = components,
		})

		local inputComponent = entity:GetComponent(InputComponent)
		if inputComponent then
			local inputFrame = inputComponent.InputBuffer:Get(frame)
			if inputFrame then
				local inputs = {}
				for inputId, inputState in pairs(inputFrame.Inputs) do inputs[inputId] = inputState end
				inputFrames[entity.Id] = {
					Frame = frame, EntityId = entity.Id, Inputs = inputs,
				}
			else
				inputFrames[entity.Id] = false
			end
		else
			inputFrames[entity.Id] = { Frame = frame, EntityId = entity.Id, Inputs = {} }
		end
	end

	local combatStateOk, combatState = pcall(world.CaptureCombatState, world)
	if not combatStateOk then
		return nil, Result.Type.UnsupportedWorld, "Combat state capture failed: " .. tostring(combatState)
	end

	local simulationState = {
		Frame = frame,
		RNGState = simulation.RNG:GetState(),
		Accumulator = simulation.Accumulator,
		SchedulerNextId = simulation.Scheduler.NextId,
		SchedulerNextOrder = simulation.Scheduler.NextOrder,
		IdGeneratorState = worldIdGenerator.LastId,
	}
	if simulationState.RNGState == nil then
		return nil, Result.Type.UnsupportedWorld, "Simulation RNG did not expose a restorable state"
	end
	local ok, snapshot = pcall(Snapshot.new, {
		Frame = frame,
		Entities = entities,
		Simulation = simulationState,
		InputFrames = inputFrames,
		Confirmed = confirmed == true,
		CombatState = combatState,
	}, self.Profile)
	if not ok then return nil, Result.Type.UnsupportedComponent, tostring(snapshot) end
	return snapshot
end

function Resolver:_matchSnapshot(world, snapshot)
	if getmetatable(snapshot) ~= Snapshot or not validFrame(snapshot.Frame) then
		return false, "Invalid snapshot"
	end
	if snapshot.CombatState ~= nil then
		local valid, detail = world:GetCombatStateSchema():Validate(snapshot.CombatState, world)
		if not valid then return false, detail end
		if snapshot.CombatState.Frame ~= snapshot.Frame then
			return false, "Combat state frame mismatch"
		end
		return self:_validInputHistory(world, snapshot)
	end
	local currentEntities = sortedEntities(world)
	if #currentEntities ~= #snapshot.Entities then return false, "World entity roster changed" end
	for index, entity in ipairs(currentEntities) do
		local saved = snapshot.Entities[index]
		if not saved or saved.Id ~= entity.Id or entity.Destroyed then
			return false, "World entity roster changed"
		end
		if saved.State ~= EntityState.Alive and saved.State ~= EntityState.Dead then
			return false, "Snapshot entity lifecycle state is invalid"
		end
		if type(saved.Components) ~= "table" then
			return false, "Snapshot component state is invalid"
		end
		local savedByKey = {}
		for _, entry in ipairs(saved.Components) do
			if type(entry.Key) ~= "string" or savedByKey[entry.Key] then
				return false, "Snapshot component keys are invalid or duplicated"
			end
			savedByKey[entry.Key] = entry
		end
		local currentByKey, count = {}, 0
		for componentType, component in pairs(entity.Components) do
			if componentType ~= RollbackComponent and componentType ~= PredictionComponent then
				local key = componentRollbackKey(component)
				if type(key) ~= "string" or key == "" or currentByKey[key] then
					return false, "Component rollback key changed"
				end
				currentByKey[key] = component
				count += 1
			end
		end
		if count ~= #saved.Components then return false, "Entity component roster changed" end
		for _, entry in ipairs(saved.Components) do
			local component = currentByKey[entry.Key]
			if not component or type(component.RestoreRollbackState) ~= "function" then
				return false, "Component rollback adapter is missing"
			end
		end
		for key in pairs(currentByKey) do
			if not savedByKey[key] then return false, "Snapshot component roster changed" end
		end
	end
	if type(snapshot.Simulation.IdGeneratorState) ~= "number"
		or snapshot.Simulation.IdGeneratorState ~= snapshot.Simulation.IdGeneratorState
		or snapshot.Simulation.IdGeneratorState % 1 ~= 0 then
		return false, "Snapshot world ID generator state is invalid"
	end
	if type(snapshot.Simulation.SchedulerNextId) ~= "number"
		or snapshot.Simulation.SchedulerNextId < 0
		or snapshot.Simulation.SchedulerNextId % 1 ~= 0
			or type(snapshot.Simulation.SchedulerNextOrder) ~= "number"
			or snapshot.Simulation.SchedulerNextOrder < 0
			or snapshot.Simulation.SchedulerNextOrder % 1 ~= 0
			or snapshot.Simulation.SchedulerNextId ~= 0
			or snapshot.Simulation.SchedulerNextOrder ~= 0 then
			return false, "Snapshot Scheduler state is invalid"
	end
	if snapshot.Simulation.Frame ~= snapshot.Frame
		or type(snapshot.Simulation.Accumulator) ~= "number"
		or snapshot.Simulation.Accumulator ~= snapshot.Simulation.Accumulator
		or snapshot.Simulation.Accumulator < 0
		or snapshot.Simulation.Accumulator >= math.huge then
		return false, "Snapshot Simulation state is invalid"
	end
	return true
end

function Resolver:_validInputHistory(world, snapshot)
	for _, entity in ipairs(sortedEntities(world)) do
		local record = snapshot.InputFrames[entity.Id]
		if record == false and entity:GetComponent(InputComponent) then
			-- The checkpoint input itself is not replayed; only subsequent frames are required.
			continue
		end
		if type(record) ~= "table" or record.Frame ~= snapshot.Frame
			or record.EntityId ~= entity.Id or type(record.Inputs) ~= "table" then
			return false
		end
		for inputId, inputState in pairs(record.Inputs) do
			if not world:GetInputResolver().Profile:IsValidInput(inputId)
				or not (inputState == InputState.None or inputState == InputState.Pressed
					or inputState == InputState.Held or inputState == InputState.Released) then
				return false
			end
		end
		if not entity:GetComponent(InputComponent) and next(record.Inputs) ~= nil then
			return false
		end
	end
	return true
end

function Resolver:_applySnapshot(world, snapshot)
	if snapshot.CombatState ~= nil then
		local trackedEntityIds = {}
		for entityId in pairs(self.Components) do
			trackedEntityIds[#trackedEntityIds + 1] = entityId
		end
		local restored, detail = world:RestoreCombatState(snapshot.CombatState, { AllowRollback = true })
		if not restored then return false, detail end
		for _, entityId in ipairs(trackedEntityIds) do
			local entity = world:GetEntity(entityId)
			local rebound = entity and entity:GetComponent(RollbackComponent)
			if rebound then
				self.Components[entityId] = rebound
				rebound.Resolver = self
				rebound.EntityId = entityId
			else
				self.Components[entityId] = nil
			end
		end
		return true
	end
	local matches, detail = self:_matchSnapshot(world, snapshot)
	if not matches then return false, detail end
	local entities = sortedEntities(world)
	for index, entity in ipairs(entities) do
		local saved = snapshot.Entities[index]
		entity.State = saved.State
		local componentsByKey = {}
		for _, component in pairs(entity.Components) do
			local key = componentRollbackKey(component)
			if key then componentsByKey[key] = component end
		end
		for _, entry in ipairs(saved.Components) do
			local component = componentsByKey[entry.Key]
			local ok, restored, restoreDetail = pcall(component.RestoreRollbackState, component,
				Snapshot.CloneSerializable(entry.State, self.Profile))
			if not ok or restored == false then
				return false, tostring(ok and restoreDetail or restored)
			end
			component.Enabled = entry.Enabled
		end
	end
	local simulation = world:GetSimulation()
	local ok, restoreError = pcall(simulation.RestoreRollbackFrame, simulation,
		snapshot.Frame, snapshot.Simulation.RNGState, snapshot.Simulation.Accumulator,
		snapshot.Simulation.SchedulerNextId, snapshot.Simulation.SchedulerNextOrder)
	if not ok then return false, tostring(restoreError) end
	world.HitstopResolver.Frame = snapshot.Frame
	world.IdGenerator.LastId = snapshot.Simulation.IdGeneratorState
	return true
end

function Resolver:RebindAfterWorldRestore(entityIds)
	local reboundComponents = {}
	for _, entityId in ipairs(entityIds) do
		local entity = self.World:GetEntity(entityId)
		local component = entity and entity:GetComponent(RollbackComponent)
		if component then
			component.Resolver = self
			component.EntityId = entityId
			reboundComponents[entityId] = component
		end
	end
	self.Components = reboundComponents
	return true
end

function Resolver:RecordFrame(worldOrEntity, options)
	local world = self:_world(worldOrEntity)
	if not world then return self:_result(Result.Type.InvalidEntity) end
	options = options or {}
	if type(options) ~= "table" or (options.Confirmed ~= nil and type(options.Confirmed) ~= "boolean") then
		return self:_result(Result.Type.InvalidRequest)
	end
	if not self.Profile.Enabled or not self:_hasEnabledComponent() then
		return self:_result(Result.Type.Disabled)
	end
	if self.Active then return self:_result(Result.Type.RollbackAlreadyInProgress) end
	local frame = world.CurrentFrame
	local snapshot, failure, detail = self:_capture(world, frame, options.Confirmed == true)
	if not snapshot then
		return self:_result(failure, { Frame = frame, Detail = detail })
	end
	local rollbackFrame = Frame.new({
		Frame = frame, Snapshot = snapshot, InputFrames = snapshot.InputFrames,
	})
	self.History:Put(frame, rollbackFrame)
	self.Metrics.SnapshotsCaptured += 1
	for entityId, component in pairs(self.Components) do
		if world:GetEntity(entityId) then component.CurrentFrame = frame end
	end
	return self:_result(Result.Type.Success, { Frame = frame })
end

function Resolver:StoreSnapshot(worldOrEntity, snapshot)
	local world = self:_world(worldOrEntity)
	if not world then return self:_result(Result.Type.InvalidEntity) end
	if self.Active then return self:_result(Result.Type.RollbackAlreadyInProgress) end
	if not world:GetSimulation() then return self:_result(Result.Type.InvalidSimulation) end
	if getmetatable(snapshot) ~= Snapshot or not validFrame(snapshot.Frame)
		or snapshot.Frame > world.CurrentFrame then
		return self:_result(Result.Type.InvalidRequest, { Frame = snapshot and snapshot.Frame })
	end
	local matches, detail = self:_matchSnapshot(world, snapshot)
	if not matches then return self:_result(Result.Type.UnsupportedComponent, { Detail = detail }) end
	if not self:_validInputHistory(world, snapshot) then
		return self:_result(Result.Type.InvalidRequest, {
			Frame = snapshot.Frame, Detail = "Snapshot input history is invalid",
		})
	end
	if type(snapshot.InputFrames) ~= "table" or snapshot.Simulation.RNGState == nil
		or snapshot.Simulation.Frame ~= snapshot.Frame then
		return self:_result(Result.Type.InvalidRequest, { Frame = snapshot.Frame })
	end
	local copiedOk, copied = pcall(Snapshot.new, {
		Frame = snapshot.Frame,
		Entities = snapshot.Entities,
		Simulation = snapshot.Simulation,
		InputFrames = snapshot.InputFrames,
		Confirmed = snapshot.Confirmed,
		CombatState = snapshot.CombatState,
	}, self.Profile)
	if not copiedOk then
		return self:_result(Result.Type.InvalidRequest, { Frame = snapshot.Frame, Detail = tostring(copied) })
	end
	self.History:Put(snapshot.Frame, Frame.new({
		Frame = snapshot.Frame, Snapshot = copied, InputFrames = copied.InputFrames,
	}))
	return self:_result(Result.Type.Success, { Frame = snapshot.Frame })
end

function Resolver:PrepareInputFrame(worldOrEntity, frame, entityId, inputs)
	local world = self:_world(worldOrEntity)
	if not world then return false, "Invalid entity" end
	if self.Active or self.PendingRequest then return false, "Rollback is already in progress" end
	if not validFrame(frame) or type(inputs) ~= "table" then
		return false, "Input frame is invalid"
	end
	local entity = world:GetEntity(entityId)
	if not entity then return false, "Input entity is missing" end
	if not entity:GetComponent(InputComponent) then
		return false, "Input entity has no InputComponent"
	end
	local inputProfile = world:GetInputResolver().Profile
	local copiedInputs = {}
	for inputId, inputState in pairs(inputs) do
		if not inputProfile:IsValidInput(inputId)
			or not (inputState == InputState.None or inputState == InputState.Pressed
				or inputState == InputState.Held or inputState == InputState.Released) then
			return false, "Input frame contains an invalid input"
		end
		copiedInputs[inputId] = inputState
	end
	local record = self.History:Get(frame)
	if not record or type(record.InputFrames) ~= "table" then
		return false, "Input history is unavailable for the requested frame"
	end
	local previous = record.InputFrames[entityId]
	local snapshotInputFrames = record.Snapshot and record.Snapshot.InputFrames
	local previousSnapshot = snapshotInputFrames and snapshotInputFrames[entityId]
	local replacement = {
		Frame = frame,
		EntityId = entityId,
		Inputs = copiedInputs,
	}
	record.InputFrames[entityId] = replacement
	if snapshotInputFrames then snapshotInputFrames[entityId] = replacement end
	return true, {
		Record = record,
		Frame = frame,
		EntityId = entityId,
		Previous = previous,
		PreviousSnapshot = previousSnapshot,
		SnapshotInputFrames = snapshotInputFrames,
	}
end

function Resolver:RestorePreparedInput(token)
	if type(token) ~= "table" or not token.Record then return false end
	local record = self.History:Get(token.Frame) or token.Record
	record.InputFrames[token.EntityId] = token.Previous
	local snapshotInputFrames = record.Snapshot and record.Snapshot.InputFrames
	if snapshotInputFrames then
		snapshotInputFrames[token.EntityId] = token.PreviousSnapshot
	end
	return true
end

function Resolver:GetFrame(frame)
	return self.History:Get(frame)
end

function Resolver:GetHistory()
	local frames = {}
	for _, frame in ipairs(self.History.Order) do table.insert(frames, self.History:Get(frame)) end
	return frames
end

function Resolver:_currentEntity(entityOrId)
	local entityId = type(entityOrId) == "table" and entityOrId.Id or entityOrId
	return entityId ~= nil and self.World:GetEntity(entityId) or nil
end

function Resolver:GetRollbackState(entityOrId)
	local entity = self:_currentEntity(entityOrId)
	local component = entity and entity:GetComponent(Component)
	return component and self.Components[entity.Id] == component and component.RollbackState or State.Idle
end

function Resolver:GetLastRollbackFrame(entityOrId)
	local entity = self:_currentEntity(entityOrId)
	local component = entity and entity:GetComponent(Component)
	return component and component.LastRollbackFrame or nil
end

function Resolver:GetRollbackCount(entityOrId)
	local entity = self:_currentEntity(entityOrId)
	local component = entity and entity:GetComponent(Component)
	return component and component.RollbackCount or 0
end

function Resolver:CanRollback(worldOrEntity, restoreFrame, endFrame, scope)
	local world = self:_world(worldOrEntity)
	if not world then return false, Result.Type.InvalidEntity end
	if not self.Profile.Enabled or not self:_hasEnabledComponent() then return false, Result.Type.Disabled end
	if not world:GetSimulation() then return false, Result.Type.InvalidSimulation end
	if not validFrame(restoreFrame) then return false, Result.Type.InvalidFrame end
	endFrame = endFrame or world.CurrentFrame
	scope = scope or Scope.World
	if scope ~= Scope.World and scope ~= Scope.Entity then return false, Result.Type.InvalidScope end
	if scope == Scope.Entity and #world:GetEntities() ~= 1 then return false, Result.Type.InvalidScope end
	if not validFrame(endFrame) or restoreFrame > endFrame or endFrame > world.CurrentFrame then
		return false, Result.Type.InvalidFrame
	end
	local distance = world.CurrentFrame - restoreFrame
	if distance > self.Profile.MaxRollbackFrames then return false, Result.Type.RollbackTooLarge end
	if endFrame - restoreFrame > self.Profile.MaxReplayFrames then return false, Result.Type.ReplayTooLarge end
	if restoreFrame == endFrame and not self.Profile.AllowSameFrameRollback then
		return false, Result.Type.AlreadyAtFrame
	end
	local rollbackFrame = self.History:Get(restoreFrame)
	if not rollbackFrame or not rollbackFrame.Snapshot then return false, Result.Type.MissingSnapshot end
	if not rollbackFrame.Snapshot.Confirmed then return false, Result.Type.UnconfirmedSnapshot end
	if self.Active then return false, Result.Type.RollbackAlreadyInProgress end
	for frame = restoreFrame + 1, endFrame do
		local record = self.History:Get(frame)
		if not record or type(record.InputFrames) ~= "table" then
			return false, Result.Type.MissingInput
		end
		if record.Snapshot == nil and self.Profile.AbortOnMissingSnapshot then
			return false, Result.Type.MissingSnapshot
		end
		if self.Profile.AbortOnMissingInput then
			for _, entity in ipairs(sortedEntities(world)) do
				local inputData = record.InputFrames[entity.Id]
				if inputData == nil or inputData == false or type(inputData) ~= "table"
					or inputData.Frame ~= frame or inputData.EntityId ~= entity.Id
					or type(inputData.Inputs) ~= "table" then
					return false, Result.Type.MissingInput
				end
				for inputId, inputState in pairs(inputData.Inputs) do
					if not world:GetInputResolver().Profile:IsValidInput(inputId)
						or not (inputState == InputState.None or inputState == InputState.Pressed
							or inputState == InputState.Held or inputState == InputState.Released) then
						return false, Result.Type.MissingInput
					end
				end
				if not entity:GetComponent(InputComponent) and next(inputData.Inputs) ~= nil then
					return false, Result.Type.MissingInput
				end
			end
		end
	end
	return true, Result.Type.Success
end

function Resolver:RequestRollback(worldOrEntity, restoreFrame, endFrame, reason, scope)
	local world = self:_world(worldOrEntity)
	if not world then return self:_result(Result.Type.InvalidEntity) end
	if self.Active or self.PendingRequest then
		return self:_result(Result.Type.RollbackAlreadyInProgress)
	end
	endFrame = endFrame or world.CurrentFrame
	if not validFrame(restoreFrame) or not validFrame(endFrame) then
		return self:_result(Result.Type.InvalidFrame, { FromFrame = restoreFrame, ToFrame = endFrame })
	end
	if restoreFrame > endFrame or endFrame > world.CurrentFrame then
		return self:_result(Result.Type.InvalidFrame, { FromFrame = restoreFrame, ToFrame = endFrame })
	end
	local requestOk, request = pcall(Request.new, {
		FromFrame = restoreFrame,
		ToFrame = endFrame,
		Reason = reason or Request.Reason.Manual,
		Scope = scope or Scope.World,
		EntityId = type(worldOrEntity) == "table" and worldOrEntity.Id or nil,
	})
	if not requestOk then
		return self:_result(Result.Type.InvalidRequest, { Detail = tostring(request) })
	end
	local canRollback, failure = self:CanRollback(world, request.FromFrame, request.ToFrame, request.Scope)
	if not canRollback then
		return self:_result(failure, { FromFrame = restoreFrame, ToFrame = endFrame })
	end
	self.PendingRequest = request
	for _, component in pairs(self.Components) do component.RollbackState = State.Requested end
	self:_emit(Event.Type.Requested, request)
	return self:_result(Result.Type.Success, { Request = request, FromFrame = restoreFrame, ToFrame = endFrame })
end

function Resolver:_setState(state)
	for entityId, component in pairs(self.Components) do
		if self.World:GetEntity(entityId) then component.RollbackState = state end
	end
end

function Resolver:_restoreBackup(backup)
	local ok, detail = self:_applySnapshot(self.World, backup)
	return ok, detail
end

function Resolver:ExecuteRollback(worldOrEntity, restoreFrame, endFrame, reason, scope)
	if restoreFrame ~= nil then
		local requested = self:RequestRollback(worldOrEntity, restoreFrame, endFrame, reason, scope)
		if not requested.Accepted then return requested end
	end
	local request = self.PendingRequest
	if not request then return self:_result(Result.Type.InvalidRequest) end
	if self.Active then return self:_result(Result.Type.RollbackAlreadyInProgress) end
	local simulation = self.World:GetSimulation()
	if not simulation then return self:_result(Result.Type.InvalidSimulation) end
	self.Active = true
	self.PendingRequest = nil
	self.Metrics.RollbacksStarted += 1
	self:_setState(State.Restoring)
	simulation:SetExecutionContext("Rollback")
	self.World:SetExecutionContext("Rollback")
	self:_emit(Event.Type.Started, request)
	self:_emit(Event.Type.Restoring, request, { Frame = request.FromFrame })

	local backup, backupFailure, backupDetail = self:_capture(self.World, self.World.CurrentFrame)
	local target = self.History:Get(request.FromFrame)
	if not backup or not target or not target.Snapshot then
		simulation:SetExecutionContext("Normal")
		self.World:SetExecutionContext("Normal")
		self.Active = false
		self.Metrics.RollbacksFailed += 1
		self:_setState(State.Failed)
		local kind = backup and Result.Type.MissingSnapshot or backupFailure
		local result = self:_result(kind, { FromFrame = request.FromFrame, ToFrame = request.ToFrame,
			Detail = backupDetail })
		self:_emit(Event.Type.Failed, request, { Result = result.Type })
		return result
	end

	local restored, restoreDetail = self:_applySnapshot(self.World, target.Snapshot)
	if not restored then
		local recovered, recoveryDetail = self:_restoreBackup(backup)
		simulation:SetExecutionContext("Normal")
		self.World:SetExecutionContext("Normal")
		self.Active = false
		self.Metrics.RollbacksFailed += 1
		self:_setState(State.Failed)
		local result = self:_result(Result.Type.RestoreFailed, {
			FromFrame = request.FromFrame, ToFrame = request.ToFrame,
			Detail = recovered and restoreDetail or (tostring(restoreDetail)
				.. "; recovery failed: " .. tostring(recoveryDetail)),
		})
		self:_emit(Event.Type.Failed, request, { Result = result.Type })
		return result
	end

	self:_setState(State.Replaying)
	self:_emit(Event.Type.ReplayStarted, request, {
		Frame = request.FromFrame, ExecutionContext = "Replay",
	})
	local staged = {}
	-- Accumulator is rendering/update cadence, not simulation state; retain its pre-rollback remainder.
	simulation.Accumulator = backup.Simulation.Accumulator
	local replayOk, replayDetail = true, nil
	simulation:SetExecutionContext("Replay")
	self.World:SetExecutionContext("Replay")
	for frame = request.FromFrame + 1, request.ToFrame do
		local record = self.History:Get(frame)
		local replayInputs = {}
		local frameOk, frameError = pcall(function()
		for _, entity in ipairs(sortedEntities(self.World)) do
			local inputData = record and record.InputFrames[entity.Id]
			local inputComponent = entity:GetComponent(InputComponent)
			if inputData == false or inputData == nil then
				if self.Profile.AbortOnMissingInput then
					replayOk, replayDetail = false, ("Input missing for entity %s at frame %d")
						:format(tostring(entity.Id), frame)
					break
				else
					local neutral = InputFrame.new({
						Frame = frame, EntityId = entity.Id, Inputs = {}, Source = "RollbackNeutral",
					})
					if inputComponent then
						local applied, applyError = self.World:GetInputResolver():ApplyInputFrame(entity, neutral)
						if not applied then
							replayOk, replayDetail = false, tostring(applyError)
							break
						end
					end
					replayInputs[entity.Id] = neutral
				end
			elseif inputComponent then
				local replayData = {
					Frame = inputData.Frame,
					EntityId = inputData.EntityId,
					Inputs = {},
					Source = inputData.Source,
				}
				for inputId, inputState in pairs(inputData.Inputs) do
					replayData.Inputs[inputId] = inputState
				end
				for inputId, currentState in pairs(inputComponent.CurrentInputs) do
					if replayData.Inputs[inputId] == nil then
						if currentState == InputState.Pressed then
							replayData.Inputs[inputId] = InputState.Held
						elseif currentState == InputState.Released then
							replayData.Inputs[inputId] = InputState.None
						end
					end
				end
				local frameCreated, inputFrame = pcall(InputFrame.new, replayData)
				if not frameCreated then
					replayOk, replayDetail = false, tostring(inputFrame)
					break
				end
				local applied, applyError = self.World:GetInputResolver():ApplyInputFrame(entity, inputFrame)
				if not applied then
					replayOk, replayDetail = false, tostring(applyError)
					break
				end
				replayInputs[entity.Id] = inputFrame
			elseif type(inputData) ~= "table" or type(inputData.Inputs) ~= "table" then
				replayOk, replayDetail = false, "Input history is malformed"
				break
			elseif next(inputData.Inputs) ~= nil then
				replayOk, replayDetail = false, "Input history has data for an entity without InputComponent"
				break
			else
				replayInputs[entity.Id] = InputFrame.new(inputData)
			end
		end
		if not replayOk then return end
		local stepOk, stepError = pcall(simulation.Step, simulation)
		if not stepOk or simulation.GameTime:GetFrame() ~= frame
			or self.World.CurrentFrame ~= frame then
			replayOk = false
			replayDetail = tostring(stepOk and "Simulation frame mismatch" or stepError)
			return
		end
		local snapshot, captureFailure, captureDetail = self:_capture(self.World, frame)
		if not snapshot then
			replayOk, replayDetail = false, captureDetail or captureFailure
			return
		end
		-- Replay may need explicit None states to clear a held input, but rollback
		-- history preserves the original sparse representation of that frame.
		for _, entity in ipairs(sortedEntities(self.World)) do
			local original = record and record.InputFrames[entity.Id]
			if type(original) == "table" and type(original.Inputs) == "table" then
				local sparse = {}
				for inputId, inputState in pairs(original.Inputs) do
					sparse[inputId] = inputState
				end
				snapshot.InputFrames[entity.Id] = {
					Frame = original.Frame,
					EntityId = original.EntityId,
					Inputs = sparse,
				}
			elseif original == false then
				snapshot.InputFrames[entity.Id] = false
			end
		end
		staged[frame] = Frame.new({
			Frame = frame, Snapshot = snapshot, InputFrames = snapshot.InputFrames, Replayed = true,
		})
		if self.Profile.RecordReplayFrames then
			self:_emit(Event.Type.ReplayFrame, request, { Frame = frame, ExecutionContext = "Replay" })
		end
		-- Prediction metadata is committed only after the entire replay succeeds.
		staged[frame].PredictionInputs = replayInputs
		end)
		if not frameOk then
			replayOk, replayDetail = false, tostring(frameError)
		end
		if not replayOk then break end
	end
	simulation:SetExecutionContext("Normal")
	self.World:SetExecutionContext("Normal")

	if not replayOk then
		local recovered, recoveryDetail = self:_restoreBackup(backup)
		self.Active = false
		self.Metrics.RollbacksFailed += 1
		self:_setState(State.Failed)
		local result = self:_result(Result.Type.ReplayFailed, {
			FromFrame = request.FromFrame, ToFrame = request.ToFrame,
			Detail = recovered and replayDetail or (tostring(replayDetail)
				.. "; recovery failed: " .. tostring(recoveryDetail)),
		})
		self:_emit(Event.Type.Failed, request, { Result = result.Type })
		return result
	end

	for frame = request.FromFrame + 1, request.ToFrame do
		local record = staged[frame]
		if not self.World:GetPredictionResolver():CanReplaceReplayedFrame(frame, record.PredictionInputs) then
			local recovered, recoveryDetail = self:_restoreBackup(backup)
			self.Active = false
			self.Metrics.RollbacksFailed += 1
			self:_setState(State.Failed)
			local result = self:_result(Result.Type.ReplayFailed, {
				FromFrame = request.FromFrame, ToFrame = request.ToFrame,
				Detail = recovered and "Prediction history prevalidation failed"
					or ("Prediction prevalidation and recovery failed: " .. tostring(recoveryDetail)),
			})
			self:_emit(Event.Type.Failed, request, { Result = result.Type })
			return result
		end
	end
	for frame = request.FromFrame + 1, request.ToFrame do
		local record = staged[frame]
		self.History:Put(frame, record)
		assert(self.World:GetPredictionResolver():ReplaceReplayedFrame(frame, record.PredictionInputs),
			"Prediction history changed after rollback prevalidation")
	end
	self.World:GetPredictionResolver():RewindToFrame(request.ToFrame)

	for entityId, component in pairs(self.Components) do
		if self.World:GetEntity(entityId) then
			component.CurrentFrame = self.World.CurrentFrame
			component.LastRestoredFrame = request.FromFrame
			component.LastRollbackFrame = request.FromFrame
			component.RollbackCount += 1
		end
	end
	self.Active = false
	self.Metrics.RollbacksCompleted += 1
	self.Metrics.ReplayFrames += request.ToFrame - request.FromFrame
	self:_setState(State.Completed)
	local result = self:_result(Result.Type.Success, {
		FromFrame = request.FromFrame, ToFrame = request.ToFrame,
		ReplayFrames = request.ToFrame - request.FromFrame,
		Reason = request.Reason,
	})
	self:_emit(Event.Type.Completed, request, { Frame = request.ToFrame, Result = result.Type })
	return result
end

function Resolver:GetMetrics()
	return {
		SnapshotsCaptured = self.Metrics.SnapshotsCaptured,
		RollbacksStarted = self.Metrics.RollbacksStarted,
		RollbacksCompleted = self.Metrics.RollbacksCompleted,
		RollbacksFailed = self.Metrics.RollbacksFailed,
		ReplayFrames = self.Metrics.ReplayFrames,
		HistoryFrames = self.History:Count(),
		HistoryCapacity = self.History.Capacity,
	}
end

function Resolver:RestoreFrame(worldOrEntity, frame)
	local world = self:_world(worldOrEntity)
	if not world then return self:_result(Result.Type.InvalidEntity) end
	if not self.Profile.Enabled or not self:_hasEnabledComponent() then
		return self:_result(Result.Type.Disabled)
	end
	if self.Active or self.PendingRequest then
		return self:_result(Result.Type.RollbackAlreadyInProgress)
	end
	if not validFrame(frame) then return self:_result(Result.Type.InvalidFrame) end
	if frame > world.CurrentFrame then
		return self:_result(Result.Type.InvalidFrame, { Frame = frame })
	end
	if world.CurrentFrame - frame > self.Profile.MaxRollbackFrames then
		return self:_result(Result.Type.RollbackTooLarge, { Frame = frame })
	end
	if frame == world.CurrentFrame and not self.Profile.AllowSameFrameRollback then
		return self:_result(Result.Type.AlreadyAtFrame, { Frame = frame })
	end
	local record = self.History:Get(frame)
	if not record or not record.Snapshot then return self:_result(Result.Type.MissingSnapshot, { Frame = frame }) end
	if not record.Snapshot.Confirmed then
		return self:_result(Result.Type.UnconfirmedSnapshot, { Frame = frame })
	end
	local backup, failure, detail = self:_capture(world, world.CurrentFrame)
	if not backup then return self:_result(failure, { Frame = frame, Detail = detail }) end
	self.Active = true
	self:_setState(State.Restoring)
	local simulation = world:GetSimulation()
	simulation:SetExecutionContext("Rollback")
	world:SetExecutionContext("Rollback")
	local callOk, restored, restoreDetail = pcall(self._applySnapshot, self, world, record.Snapshot)
	if not callOk then
		restoreDetail = restored
		restored = false
	end
	if not restored then
		local recoveryCallOk, recovered, recoveryDetail = pcall(self._restoreBackup, self, backup)
		if not recoveryCallOk then
			recoveryDetail = recovered
			recovered = false
		end
		simulation:SetExecutionContext("Normal")
		world:SetExecutionContext("Normal")
		self.Active = false
		self:_setState(State.Failed)
		local detail = tostring(restoreDetail)
		if not recovered then
			detail ..= "; backup recovery failed: " .. tostring(recoveryDetail)
				.. "; world may be partially restored"
		end
		return self:_result(Result.Type.RestoreFailed, { Frame = frame, Detail = detail })
	end
	simulation:SetExecutionContext("Normal")
	world:SetExecutionContext("Normal")
	local predictionResolver = world:GetPredictionResolver()
	if predictionResolver then predictionResolver:RewindToFrame(frame) end
	for _, component in pairs(self.Components) do
		component.CurrentFrame = frame
		component.LastRestoredFrame = frame
	end
	self.Active = false
	self:_setState(State.Completed)
	return self:_result(Result.Type.Success, { Frame = frame })
end

function Resolver:ReplayFromFrame(worldOrEntity, startFrame, endFrame)
	return self:ExecuteRollback(worldOrEntity, startFrame, endFrame)
end

function Resolver:CancelRollback()
	if self.Active then return self:_result(Result.Type.RollbackAlreadyInProgress) end
	if not self.PendingRequest then return self:_result(Result.Type.InvalidRequest) end
	local request = self.PendingRequest
	self.PendingRequest = nil
	self:_setState(State.Idle)
	self:_emit(Event.Type.Cancelled, request)
	return self:_result(Result.Type.Success, { Request = request })
end

function Resolver:_onComponentRemoved(component)
	if component.EntityId and self.Components[component.EntityId] == component then
		self.Components[component.EntityId] = nil
	end
end

function Resolver:GetEvents()
	return table.clone(self.Events)
end

function Resolver:GetResults()
	return table.clone(self.Results)
end

function Resolver:Clear()
	self.Events, self.Results = {}, {}
	return self
end

return Resolver
