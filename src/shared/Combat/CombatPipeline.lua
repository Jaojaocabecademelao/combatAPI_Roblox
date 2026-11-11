local Definition = require(script.Parent.CombatActionDefinition)
local Instance = require(script.Parent.CombatActionInstance)
local Result = require(script.Parent.CombatActionResult)
local Event = require(script.Parent.CombatActionEvent)
local EntityState = require(script.Parent.Parent.Core.EntityState)
local ResourceComponent = require(script.Parent.ResourceComponent)
local StatusContainer = require(script.Parent.StatusContainer)

local Pipeline = {}
Pipeline.__index = Pipeline

local function idLess(a, b)
	if type(a) ~= type(b) then return type(a) < type(b) end
	return a < b
end

function Pipeline.new(world)
	return setmetatable({ World = world, Definitions = {}, Active = {}, Events = {}, Results = {} }, Pipeline)
end

function Pipeline:RegisterDefinition(definition)
	if self.DefinitionCatalog then return false, "ActionCatalogIsRegistered" end
	assert(type(definition) == "table" and definition.Version == Definition.Version,
		"CombatPipeline requires a CombatActionDefinition")
	if self.Definitions[definition.Id] then return false, "ActionAlreadyRegistered" end
	self.Definitions[definition.Id] = definition
	return true
end

function Pipeline:RegisterCatalog(catalog)
	if self.DefinitionCatalog then return false, "ActionCatalogAlreadyRegistered" end
	if next(self.Definitions) ~= nil then return false, "DefinitionsAlreadyRegistered" end
	assert(type(catalog) == "table" and catalog.Sealed == true
		and type(catalog.GetDefinitions) == "function"
		and type(catalog.CaptureManifest) == "function"
		and type(catalog.ValidateManifest) == "function",
		"CombatPipeline requires a sealed CombatActionCatalog")
	local manifest = catalog:CaptureManifest()
	local valid, detail = catalog:ValidateManifest(manifest)
	if not valid then return false, detail end
	for _, definition in ipairs(catalog:GetDefinitions()) do
		self.Definitions[definition.Id] = definition
	end
	self.DefinitionCatalog = catalog
	return true
end

function Pipeline:GetDefinition(actionId) return self.Definitions[actionId] end
function Pipeline:GetAction(entityOrId)
	local id = type(entityOrId) == "table" and entityOrId.Id or entityOrId
	return self.Active[id]
end

function Pipeline:_result(kind, data)
	data = data or {}; data.Type = kind; data.Accepted = kind ~= Result.Type.Rejected
	local value = Result.new(data); table.insert(self.Results, value); return value
end

function Pipeline:_event(kind, action, phase)
	local value = Event.new({
		Type = kind, ActionId = action.Id, ActionDefinitionId = action.Definition.Id,
		EntityId = action.Owner.Id, Frame = action.CurrentFrame, Phase = phase,
	})
	table.insert(self.Events, value)
	return value
end

function Pipeline:_resourceComponent(entity)
	return entity:GetComponent(ResourceComponent)
end

function Pipeline:_checkRequirements(entity, definition)
	local requirements = definition.Requirements
	local resources = requirements.Resources
	local component = self:_resourceComponent(entity)
	for name, amount in pairs(resources) do
		if not component or component:Get(name) == nil or component:Get(name) < amount then
			return false, "InsufficientResource"
		end
	end
	local statuses = entity:GetComponent(StatusContainer)
	for _, tag in ipairs(requirements.RequiredStatusTags) do
		if not statuses or not statuses:HasTag(tag) then
			return false, "MissingRequiredStatusTag:" .. tag
		end
	end
	for _, tag in ipairs(requirements.ForbiddenStatusTags) do
		if statuses and statuses:HasTag(tag) then
			return false, "ForbiddenStatusTag:" .. tag
		end
	end
	if #requirements.MovementStates > 0 then
		local resolver = self.World.GetMovementStateResolver and self.World:GetMovementStateResolver()
		if not resolver then return false, "MissingMovementStateResolver" end
		local movementState = resolver:GetState(entity)
		if movementState == nil then return false, "MissingMovementState" end
		local allowed = false
		for _, required in ipairs(requirements.MovementStates) do
			if movementState == required then allowed = true; break end
		end
		if not allowed then return false, "MovementStateRequirementFailed" end
	end
	return true
end

function Pipeline:_applyCosts(entity, definition)
	local resources = definition.Costs.Resources
	local component = self:_resourceComponent(entity)
	for name, amount in pairs(resources) do
		if amount > 0 then
			if not component then return false, "MissingResourceComponent" end
			local value, reason = component:Consume(name, amount)
			if value == false then return false, reason end
		end
	end
	return true
end

function Pipeline:Start(entityOrId, actionId, frame)
	local entity = type(entityOrId) == "table" and entityOrId or self.World:GetEntity(entityOrId)
	frame = frame == nil and self.World.CurrentFrame or frame
	if not entity or entity.Destroyed or entity:GetState() == EntityState.Dead then
		return self:_result(Result.Type.InvalidEntity, { EntityId = entity and entity.Id })
	end
	if type(frame) ~= "number" or frame < self.World.CurrentFrame or frame % 1 ~= 0 then
		return self:_result(Result.Type.InvalidFrame, { Frame = frame })
	end
	local definition = self.Definitions[actionId]
	if not definition then return self:_result(Result.Type.UnknownAction, { EntityId = entity.Id, ActionDefinitionId = actionId }) end
	if self.Active[entity.Id] and not self.Active[entity.Id]:IsFinished() then
		return self:_result(Result.Type.AlreadyRunning, { EntityId = entity.Id })
	end
	local requirementsMet, requirementError = self:_checkRequirements(entity, definition)
	if not requirementsMet then
		return self:_result(Result.Type.Rejected, {
			EntityId = entity.Id, ActionDefinitionId = actionId, Reason = requirementError,
		})
	end
	local costsApplied, costError = self:_applyCosts(entity, definition)
	if not costsApplied then
		return self:_result(Result.Type.Rejected, {
			EntityId = entity.Id, ActionDefinitionId = actionId, Reason = costError,
		})
	end
	local action = Instance.new(definition, entity, self.World.IdGenerator:Next(), frame)
	self.Active[entity.Id] = action
	self:_event(Event.Type.Started, action, action.Phase)
	return self:_result(Result.Type.Started, { EntityId = entity.Id, ActionId = action.Id, ActionDefinitionId = actionId, Frame = frame })
end

function Pipeline:Cancel(entityOrId, frame)
	local action = self:GetAction(entityOrId)
	if not action then return self:_result(Result.Type.Rejected, { Reason = "NoAction" }) end
	if not action.Definition.Cancelable then return self:_result(Result.Type.NotCancelable, { EntityId = action.Owner.Id, ActionId = action.Id }) end
	if not action:Cancel(frame or self.World.CurrentFrame) then return self:_result(Result.Type.Rejected, { EntityId = action.Owner.Id }) end
	self:_event(Event.Type.Cancelled, action, action.Phase)
	return self:_result(Result.Type.Cancelled, { EntityId = action.Owner.Id, ActionId = action.Id, Frame = action.CurrentFrame })
end

function Pipeline:Step(frame)
	local ids = {}
	for id in pairs(self.Active) do table.insert(ids, id) end
	table.sort(ids, idLess)
	for _, id in ipairs(ids) do
		local action = self.Active[id]
		local previous = action.Phase
		action:Advance(frame)
		if previous ~= action.Phase and not action:IsFinished() then self:_event(Event.Type.PhaseChanged, action, action.Phase) end
		if action.State == Instance.State.Finished then
			self:_event(Event.Type.Completed, action, action.Phase)
			self:_result(Result.Type.Completed, { EntityId = id, ActionId = action.Id, Frame = frame })
			self.Active[id] = nil
		end
	end
end

function Pipeline:GetEvents() return table.clone(self.Events) end
function Pipeline:GetResults() return table.clone(self.Results) end
function Pipeline:Clear() table.clear(self.Events); table.clear(self.Results); return self end

function Pipeline:CaptureRollbackState()
	local actions = {}
	local ids = {}
	for entityId in pairs(self.Active) do table.insert(ids, entityId) end
	table.sort(ids, idLess)
	for _, entityId in ipairs(ids) do
		local action = self.Active[entityId]
		table.insert(actions, {
			Id = action.Id,
			EntityId = action.Owner.Id,
			ActionDefinitionId = action.Definition.Id,
			DurationModel = action.Definition.DurationModel,
			StartFrame = action.StartFrame,
			CurrentFrame = action.CurrentFrame,
			Phase = action.Phase,
			State = action.State,
		})
	end
	local state = { Version = 1, Actions = actions }
	if self.DefinitionCatalog then
		state.CatalogManifest = self.DefinitionCatalog:CaptureManifest()
	end
	return state
end

function Pipeline:ValidateRollbackState(state, world)
	world = world and (world.World or world)
	assert(world and type(world.GetEntity) == "function",
		"CombatPipeline rollback validation requires a World context")
	if type(state) ~= "table" or state.Version ~= 1 or type(state.Actions) ~= "table" then
		return false, "Invalid CombatPipeline state"
	end
	if self.DefinitionCatalog then
		if state.CatalogManifest == nil then
			return false, "CombatPipeline state is missing its action catalog manifest"
		end
		local manifestValid, manifestError = self.DefinitionCatalog:ValidateManifest(state.CatalogManifest)
		if not manifestValid then return false, manifestError end
	elseif state.CatalogManifest ~= nil then
		return false, "CombatPipeline state requires its action catalog"
	end
	local seen = {}
	for _, saved in ipairs(state.Actions) do
		if type(saved) ~= "table" or saved.EntityId == nil or seen[saved.EntityId]
			or self.Definitions[saved.ActionDefinitionId] == nil
			or not world:GetEntity(saved.EntityId) then
			return false, "CombatPipeline action references an invalid entity or definition"
		end
		seen[saved.EntityId] = true
		if type(saved.StartFrame) ~= "number" or type(saved.CurrentFrame) ~= "number"
			or saved.CurrentFrame < saved.StartFrame
			or saved.DurationModel ~= self.Definitions[saved.ActionDefinitionId].DurationModel
			or saved.State == Instance.State.Finished or saved.State == Instance.State.Cancelled then
			return false, "CombatPipeline action state is invalid"
		end
	end
	return true
end

function Pipeline:PrepareRollbackRestore(state, world)
	world = world and (world.World or world)
	local valid, detail = self:ValidateRollbackState(state, world)
	if not valid then return nil, detail end
	local restored = {}
	for _, saved in ipairs(state.Actions) do
		local owner = world:GetEntity(saved.EntityId)
		local action = Instance.new(
			self.Definitions[saved.ActionDefinitionId], owner, saved.Id, saved.StartFrame)
		action.CurrentFrame = saved.CurrentFrame
		action.Phase = saved.Phase
		action.State = saved.State
		restored[saved.EntityId] = action
	end
	return function()
		self.Active = restored
		self.Events = {}
		self.Results = {}
		return true
	end
end

return Pipeline
