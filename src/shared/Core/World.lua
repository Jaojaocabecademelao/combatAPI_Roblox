local CombatEntity = require(script.Parent.CombatEntity)
local EntityRegistry = require(script.Parent.EntityRegistry)
local IdGenerator = require(script.Parent.IdGenerator)
local HitstopResolver = require(script.Parent.Parent.Combat.HitstopResolver)
local ProtectionResolver = require(script.Parent.Parent.Combat.ProtectionResolver)
local GuardResolver = require(script.Parent.Parent.Combat.GuardResolver)
local ArmorResolver = require(script.Parent.Parent.Combat.ArmorResolver)
local ComboResolver = require(script.Parent.Parent.Combat.ComboResolver)
local PluginResolver = require(script.Parent.Parent.Plugins.PluginResolver)
local JuggleResolver = require(script.Parent.Parent.Combat.JuggleResolver)
local MovementStateResolver = require(script.Parent.Parent.Combat.MovementStateResolver)
local CancelResolver = require(script.Parent.Parent.Combat.CancelResolver)
local InputResolver = require(script.Parent.Parent.Combat.InputResolver)
local CharacterResolver = require(script.Parent.Parent.Combat.CharacterResolver)
local RobloxCharacterAdapter = require(script.Parent.Parent.Combat.RobloxCharacterAdapter)
local AnimationResolver = require(script.Parent.Parent.Combat.AnimationResolver)
local NetworkResolver = require(script.Parent.Parent.Combat.NetworkResolver)
local PredictionResolver = require(script.Parent.Parent.Combat.PredictionResolver)
local ReconciliationResolver = require(script.Parent.Parent.Combat.ReconciliationResolver)
local RollbackResolver = require(script.Parent.Parent.Combat.RollbackResolver)
local AuthorityResolver = require(script.Parent.Parent.Combat.AuthorityResolver)
local CombatPipeline = require(script.Parent.Parent.Combat.CombatPipeline)
local CombatStateSchema = require(script.Parent.Parent.Combat.CombatStateSchema)
local APIContext = require(script.Parent.Parent.Events.APIContext)
local EventTypes = require(script.Parent.Parent.Events.EventTypes)
local ExternalEffectGate = require(script.Parent.Parent.Events.ExternalEffectGate)
local ExternalFactJournal = require(script.Parent.Parent.Events.ExternalFactJournal)
local HealthComponent = require(script.Parent.Parent.Combat.HealthComponent)
local DefenseComponent = require(script.Parent.Parent.Combat.DefenseComponent)
local HitstopComponent = require(script.Parent.Parent.Combat.HitstopComponent)
local ComboComponent = require(script.Parent.Parent.Combat.ComboComponent)
local JuggleComponent = require(script.Parent.Parent.Combat.JuggleComponent)
local MotionComponent = require(script.Parent.Parent.Combat.MotionComponent)
local MovementStateComponent = require(script.Parent.Parent.Combat.MovementStateComponent)
local OffensiveStateComponent = require(script.Parent.Parent.Combat.OffensiveStateComponent)
local ProtectionComponent = require(script.Parent.Parent.Combat.ProtectionComponent)
local InputComponent = require(script.Parent.Parent.Combat.InputComponent)
local CancelComponent = require(script.Parent.Parent.Combat.CancelComponent)
local ArmorComponent = require(script.Parent.Parent.Combat.ArmorComponent)
local GuardComponent = require(script.Parent.Parent.Combat.GuardComponent)
local RollbackComponent = require(script.Parent.Parent.Combat.RollbackComponent)
local StatusContainer = require(script.Parent.Parent.Combat.StatusContainer)
local StatusEffectResolver = require(script.Parent.Parent.Combat.StatusEffectResolver)
local ResourceComponent = require(script.Parent.Parent.Combat.ResourceComponent)

local World = {}
World.__index = World

local function registerDefaultComponentFactory(schema, component, constructor)
	if not schema.Factories[component.RollbackKey] then
		schema:RegisterComponent(component.RollbackKey, constructor)
	end
end

function World:_AssertNormalOperation(operation)
	if self.ExecutionContext ~= "Normal" then
		local entry = self.ForbiddenOperations[operation] or { Count = 0, LastContext = nil }
		entry.Count += 1
		entry.LastContext = self.ExecutionContext
		self.ForbiddenOperations[operation] = entry
		error(operation .. " is not allowed during " .. tostring(self.ExecutionContext))
	end
end

function World.new(options)
	options = options or {}
	assert(type(options) == "table", "World.new() expects an options table or nil")

	local self = setmetatable({}, World)
	self.IdGenerator = options.IdGenerator or IdGenerator.new()
	self.EntityRegistry = EntityRegistry.new()
	self.CurrentFrame = 0
	self.CollisionWorld = nil
	self.DamageResolver = nil
	self.ReactionResolver = nil
	self.DefenseResolver = nil
	self.CombatResolver = nil
	self.CounterResolver = nil
	self.HitstopResolver = HitstopResolver.new(self)
	self.StatusEffectResolver = StatusEffectResolver.new(self)
	self.ProtectionResolver = ProtectionResolver.new(self)
	self.GuardResolver = GuardResolver.new(self)
	self.MotionResolver = nil
	self.ArmorResolver = ArmorResolver.new(self)
	self.ComboResolver = ComboResolver.new(self, options.ComboProfile)
	self.JuggleResolver = JuggleResolver.new(self, options.JuggleProfile)
	self.MovementStateResolver = MovementStateResolver.new(self, options.MovementStateProfile)
	self.CancelResolver = CancelResolver.new(self, options.CancelProfile)
	self.InputResolver = InputResolver.new(self, options.InputProfile)
	self.CharacterResolver = CharacterResolver.new(self, options.Character)
	if not self.CharacterResolver:GetAdapterDefinition("RobloxHumanoid") then
		self.CharacterResolver:RegisterAdapter("RobloxHumanoid", RobloxCharacterAdapter.new())
	end
	self.AnimationResolver = AnimationResolver.new(self, options.Animation)
	self.NetworkResolver = NetworkResolver.new(self, options.Network)
	self.PredictionResolver = PredictionResolver.new(self, options.PredictionProfile)
	self.ReconciliationResolver = ReconciliationResolver.new(self, options.Reconciliation)
	self.RollbackResolver = RollbackResolver.new(self, options.RollbackProfile)
	self.AuthorityResolver = AuthorityResolver.new(self, options.Authority)
	self.CombatPipeline = CombatPipeline.new(self)
	self.CombatStateSchema = CombatStateSchema.new()
	self.CombatStateSchema:RegisterStateProvider("combat.pipeline", self.CombatPipeline)
	self.CombatStateSchema:RegisterStateProvider("combat.combo-resolver.v1", self.ComboResolver)
	self.CombatStateSchema:RegisterStateProvider("combat.juggle-resolver.v1", self.JuggleResolver)
	self.CombatStateSchema:RegisterStateProvider("combat.cancel-resolver.v1", self.CancelResolver)
	self.CombatStateSchema:RegisterStateProvider("combat.hitstop-resolver.v1", self.HitstopResolver)
	if options.ComponentFactories ~= nil then
		assert(type(options.ComponentFactories) == "table", "World.ComponentFactories must be a table")
		for key, factory in pairs(options.ComponentFactories) do
			self.CombatStateSchema:RegisterComponent(key, factory)
		end
	end
	registerDefaultComponentFactory(self.CombatStateSchema, HealthComponent,
		function(_, state) return HealthComponent.new({ MaxHealth = state.MaxHealth, CurrentHealth = state.CurrentHealth }) end)
	registerDefaultComponentFactory(self.CombatStateSchema, DefenseComponent,
		function() return DefenseComponent.new() end)
	registerDefaultComponentFactory(self.CombatStateSchema, HitstopComponent,
		function() return HitstopComponent.new() end)
	registerDefaultComponentFactory(self.CombatStateSchema, ComboComponent,
		function() return ComboComponent.new() end)
	registerDefaultComponentFactory(self.CombatStateSchema, JuggleComponent,
		function() return JuggleComponent.new() end)
	registerDefaultComponentFactory(self.CombatStateSchema, MotionComponent,
		function() return MotionComponent.new() end)
	registerDefaultComponentFactory(self.CombatStateSchema, MovementStateComponent,
		function() return MovementStateComponent.new() end)
	registerDefaultComponentFactory(self.CombatStateSchema, OffensiveStateComponent,
		function() return OffensiveStateComponent.new() end)
	registerDefaultComponentFactory(self.CombatStateSchema, ProtectionComponent,
		function() return ProtectionComponent.new() end)
	registerDefaultComponentFactory(self.CombatStateSchema, InputComponent,
		function() return InputComponent.new() end)
	registerDefaultComponentFactory(self.CombatStateSchema, CancelComponent,
		function() return CancelComponent.new() end)
	registerDefaultComponentFactory(self.CombatStateSchema, ArmorComponent,
		function() return ArmorComponent.new() end)
	registerDefaultComponentFactory(self.CombatStateSchema, GuardComponent,
		function(_, state)
			return GuardComponent.new({
				MaxGuard = state.MaxGuard,
				Guard = state.Guard,
				ChipMultiplier = state.Profile and state.Profile.ChipMultiplier,
				GuardDamageMultiplier = state.Profile and state.Profile.GuardDamageMultiplier,
				BlockstunMultiplier = state.Profile and state.Profile.BlockstunMultiplier,
				GuardBreakFrames = state.Profile and state.Profile.GuardBreakFrames,
				DefaultGuardDamage = state.Profile and state.Profile.DefaultGuardDamage,
				Name = state.Profile and state.Profile.Name,
			})
		end)
	registerDefaultComponentFactory(self.CombatStateSchema, RollbackComponent,
		function() return RollbackComponent.new() end)
	registerDefaultComponentFactory(self.CombatStateSchema, StatusContainer,
		function() return StatusContainer.new() end)
	registerDefaultComponentFactory(self.CombatStateSchema, ResourceComponent,
		function(_, state)
			local resources = {}
			for _, resource in ipairs(state.Resources or {}) do
				resources[resource.Name] = {
					Max = resource.Max,
					Current = resource.Current,
				}
			end
			return ResourceComponent.new({ Resources = resources })
		end)
	if options.StateProviders ~= nil then
		assert(type(options.StateProviders) == "table", "World.StateProviders must be a table")
		for key, provider in pairs(options.StateProviders) do
			self.CombatStateSchema:RegisterStateProvider(key, provider)
		end
	end
	self.Simulation = nil
	self.ExecutionContext = "Normal"
	self.ForbiddenOperations = {}
	self.EventSequence = 0
	self.PublishedInternalEvents = {}
	self.APIContext = APIContext.new(self)
	self.EventBus = self.APIContext:GetEvents()
	self.ExternalEffectGate = ExternalEffectGate.new(self)
	self.ExternalFactJournal = ExternalFactJournal.new(self, options.ExternalFacts)
	self.PluginResolver = PluginResolver.new(self)
	self.Destroyed = false

	return self
end

function World:CreateEntity()
	assert(not self.Destroyed and not self.Destroying, "Cannot create an entity in a stopping World")
	self:_AssertNormalOperation("CreateEntity")
	local id = self.IdGenerator:Next()
	local entity = CombatEntity.new(id)
	entity.World = self

	self.EntityRegistry:Register(entity)
	self:_PublishPublicEvent(EventTypes.EntityCreated, { EntityId = entity.Id }, "Core", self.CurrentFrame, entity.Id)

	return entity
end

function World:GetEntity(id)
	return self.EntityRegistry:Get(id)
end

function World:GetExternalEffectGate()
	return self.ExternalEffectGate
end

function World:GetExternalFactJournal()
	return self.ExternalFactJournal
end

function World:GetDiagnostics()
	local forbidden = {}
	for operation, entry in pairs(self.ForbiddenOperations) do
		forbidden[operation] = { Count = entry.Count, LastContext = entry.LastContext }
	end
	return {
		Frame = self.CurrentFrame,
		Rollback = self.RollbackResolver:GetMetrics(),
		Network = self.NetworkResolver:GetMetrics(),
		ForbiddenOperations = forbidden,
		DeterminismViolations = self:GetDeterminismViolations(),
	}
end

function World:AssertDeterministicOperation(operation, details)
	assert(type(operation) == "string" and operation ~= "", "Deterministic operation is required")
	if self.Simulation and type(self.Simulation.AssertDeterministicOperation) == "function" then
		return self.Simulation:AssertDeterministicOperation(operation, details)
	end
	return true
end

function World:GetDeterminismViolations()
	if self.Simulation and type(self.Simulation.GetDeterminismGuard) == "function" then
		return self.Simulation:GetDeterminismGuard():GetViolations()
	end
	return {}
end

function World:HasEntity(entityOrId)
	return self.EntityRegistry:Has(entityOrId)
end

function World:DestroyEntity(entityOrId)
	self:_AssertNormalOperation("DestroyEntity")
	local entity

	if type(entityOrId) == "table" then
		entity = self.EntityRegistry:Get(entityOrId.Id)
		if entity ~= entityOrId then
			return false
		end
	else
		entity = self.EntityRegistry:Get(entityOrId)
	end

	if not entity then
		return false
	end
	if entity.Destroying then return false end
	entity.Destroying = true
	if self.CharacterResolver and self.CharacterResolver:IsAttached(entity) then
		self.CharacterResolver:Detach(entity, { Frame = self.CurrentFrame })
	end
	if self.ComboResolver then self.ComboResolver:BreakEntity(entity, "InvalidTarget", self.CurrentFrame) end
	if self.PredictionResolver then self.PredictionResolver:RemoveEntity(entity) end

	self.EntityRegistry:Remove(entity.Id)
	entity:Destroy()
	if self.DamageResolver and type(self.DamageResolver.RemoveEntity) == "function" then
		self.DamageResolver:RemoveEntity(entity)
	end
	if self.CollisionWorld and type(self.CollisionWorld.RemoveEntity) == "function" then
		self.CollisionWorld:RemoveEntity(entity)
	end
	entity.World = nil
	self:_PublishPublicEvent(EventTypes.EntityDestroyed, { EntityId = entity.Id }, "Core", self.CurrentFrame, entity.Id)

	return true
end

function World:RespawnEntity(entityOrId, options)
	self:_AssertNormalOperation("RespawnEntity")
	options = options or {}
	assert(type(options) == "table", "World:RespawnEntity() expects an options table or nil")
	local previous = type(entityOrId) == "table" and entityOrId or self.EntityRegistry:Get(entityOrId)
	if not previous or self.EntityRegistry:Get(previous.Id) ~= previous then return false end
	local id, instance = previous.Id, options.Instance
	if not self:DestroyEntity(previous) then return false end
	local entity = CombatEntity.new(id)
	entity.World = self
	if instance ~= nil then entity:BindInstance(instance) end
	self.EntityRegistry:Register(entity)
	self:_PublishPublicEvent(EventTypes.EntityCreated, { EntityId = id, Respawn = true },
		"Core", self.CurrentFrame, id)
	self:_PublishPublicEvent(EventTypes.EntityRespawned, { EntityId = id, PreviousEntityId = id },
		"Core", self.CurrentFrame, id)
	return entity
end

function World:DisconnectPeer(peerId, options)
	assert(not self.Destroyed and self.ExecutionContext == "Normal",
		"Peer disconnection can only run during normal execution")
	options = options or {}
	assert(type(options) == "table", "World:DisconnectPeer() expects an options table or nil")
	local network = self.NetworkResolver
	local authority = self.AuthorityResolver
	local peer = network and network:GetPeer(peerId)
	if not peer then return false, "UnknownPeer" end
	local owned = authority:GetOwnedEntities(peerId)
	local disconnected = network:Disconnect(peerId, options)
	if not disconnected.Accepted and peer.State ~= "Disconnected" then
		return false, disconnected.Type
	end
	local unregistered = authority:UnregisterPeer(peerId)
	if not unregistered.Accepted then return false, unregistered.Type end
	if options.DestroyOwnedEntities == true then
		for _, entity in ipairs(owned) do self:DestroyEntity(entity) end
	end
	return true, {
		PeerId = peerId,
		ReleasedEntityCount = #owned,
		DestroyedEntityCount = options.DestroyOwnedEntities == true and #owned or 0,
	}
end

function World:GetEntities()
	return self.EntityRegistry:GetAll()
end

function World:GetEvents() return self.EventBus end
function World:GetCombatAPI() return self.APIContext end
function World:GetAPIContext() return self.APIContext end

function World:_PublishPublicEvent(eventType, payload, sourceSystem, frame, entityId, eventId)
	if self.Destroyed or not self.EventBus then return nil end
	self.EventSequence += 1
	local executionMode = self:GetEventExecutionMode()
	return self.EventBus:Dispatch(eventType, payload, {
		SimulationFrame = frame == nil and self.CurrentFrame or frame,
		SourceSystem = sourceSystem or "World", EntityId = entityId,
		Sequence = self.EventSequence, EventId = eventId, ExecutionMode = executionMode,
		APIContext = self.APIContext,
	})
end

function World:GetEventExecutionMode()
	local executionMode = self.ExecutionContext
	if executionMode == "Normal" then
		if self.Simulation and self.Simulation:GetExecutionContext() == "Replay" then executionMode = "Replay"
		elseif self.RollbackResolver and self.RollbackResolver.Active then executionMode = "Replay"
		elseif self.AuthorityResolver and self.AuthorityResolver.Processing then executionMode = "Authority" end
	end
	return executionMode
end

local function getId(value)
	if type(value) == "table" then return value.Id end
	return value
end

local function stableValue(value, seen)
	local valueType = type(value)
	if value == nil then return "nil" end
	if valueType == "boolean" or valueType == "number" or valueType == "string" then
		local text = tostring(value)
		return valueType .. "#" .. tostring(#text) .. ":" .. text
	end
	if valueType ~= "table" then return valueType end
	if value.Id ~= nil then return "entity#" .. stableValue(value.Id, seen) end
	seen = seen or {}
	if seen[value] then return "<cycle>" end
	seen[value] = true
	local keys = {}
	for key in pairs(value) do
		local keyType = type(key)
		if keyType == "string" or keyType == "number" then table.insert(keys, key) end
	end
	table.sort(keys, function(a, b)
		if type(a) == type(b) then return a < b end
		return type(a) < type(b)
	end)
	local parts = { "table{" }
	for _, key in ipairs(keys) do
		table.insert(parts, stableValue(key, seen))
		table.insert(parts, "=")
		table.insert(parts, stableValue(value[key], seen))
		table.insert(parts, ";")
	end
	seen[value] = nil
	table.insert(parts, "}")
	return table.concat(parts)
end

function World:_PublishInternalEvents(source, events, mapper)
	if not events or #events == 0 then return end
	local executionMode = self:GetEventExecutionMode()

	-- Identity is derived from event content, not its position in a resolver array.
	-- The occurrence suffix distinguishes repeated events with identical payloads;
	-- unrelated insertions/reordering therefore cannot renumber other events.
	local occurrences = {}
	for _, sourceEvent in ipairs(events or {}) do
		if type(sourceEvent) == "table" then
			local publicType, payload, frame, entityId = mapper(sourceEvent)
			if publicType then
				frame = frame or sourceEvent.Frame or self.CurrentFrame
				local fingerprint = table.concat({ stableValue(source), stableValue(frame),
					stableValue(publicType), stableValue(payload or {}) }, "|")
				local occurrence = (occurrences[fingerprint] or 0) + 1
				occurrences[fingerprint] = occurrence
				local stableEventId = fingerprint .. "|occurrence=" .. tostring(occurrence)
				local publishedKey = stableEventId .. ":" .. tostring(executionMode)
				if self.PublishedInternalEvents[publishedKey] == nil then
					self.PublishedInternalEvents[publishedKey] = frame
					self:_PublishPublicEvent(publicType, payload or {}, source, frame, entityId, stableEventId)
				end
			end
		end
	end
end

function World:FlushEvents()
	local rollbackProfile = self.RollbackResolver and self.RollbackResolver.Profile
	local retention = math.max(rollbackProfile and rollbackProfile.MaxRollbackFrames or 120,
		rollbackProfile and rollbackProfile.HistorySize or 120) + 2
	local oldestRetainedFrame = self.CurrentFrame - retention
	for eventId, publishedFrame in pairs(self.PublishedInternalEvents) do
		if publishedFrame < oldestRetainedFrame then self.PublishedInternalEvents[eventId] = nil end
	end

	local function publish(source, events, map) self:_PublishInternalEvents(source, events, map) end
	local function basic(kind, fields)
		return function(value)
			local payload = {}
			for _, field in ipairs(fields) do
				local item = value[field]
				if item ~= nil then payload[field] = item end
			end
			local target = value.Target or value.Defender or value.EntityId or value.TargetId
			local attacker = value.Attacker or value.Source or value.AttackerId
			payload.AttackerId = getId(attacker)
			payload.DefenderId = getId(target)
			payload.TargetId = getId(target)
			if value.AttackInstanceId ~= nil then payload.AttackInstanceId = value.AttackInstanceId end
			return kind, payload, value.Frame, getId(target)
		end
	end
	publish("CombatResolution", self:GetCombatResolutionEvents(), function(event)
		if event.Outcome == "Clash" then return EventTypes.Clash, event, event.Frame,
			event.AttackerEntityIdA or event.TargetEntityIdA end
	end)
	publish("Protection", self.ProtectionResolver:GetResults(), function(result)
		if result.Result == "Blocked" and result.Category == "Hit" then
			return EventTypes.HitRejected, { DefenderId = getId(result.Target), Category = result.Category,
				Reason = result.Kind, Source = result.Source }, result.Frame, getId(result.Target)
		end
	end)
	publish("Defense", self:GetDefenseEvents(), function(event)
		local kind = event.Result == "Blocked" and EventTypes.Block or event.Result == "Parried" and EventTypes.Parry
		if kind then return kind, { Result = event.Result, AttackerId = getId(event.Attacker),
			DefenderId = getId(event.Defender), AttackInstanceId = event.AttackInstanceId },
			event.Frame, getId(event.Defender) end
	end)
	if self.CollisionWorld then
		publish("HitProcessing", self.LastResolvedHitEvents or {}, function(hit)
			return EventTypes.HitConfirmed, { AttackerId = getId(hit.Attacker), DefenderId = getId(hit.Target),
				AttackInstanceId = hit.AttackInstanceId, HitboxId = hit.HitboxId or (hit.Hitbox and hit.Hitbox.Id),
				HurtboxId = hit.HurtboxId or (hit.Hurtbox and hit.Hurtbox.Id),
				CustomData = hit.OffensiveProperties and hit.OffensiveProperties.CustomData }, hit.Frame, getId(hit.Target)
		end)
	end
	publish("Counter", self:GetCounterResults(), function(event)
		if event.Type == "CounterHit" then return EventTypes.CounterHit, event, event.Frame, getId(event.Target) end
	end)
	publish("Damage", self:GetDamageEvents(), function(event)
		if (event.AppliedAmount or event.Amount or 0) > 0 then
			return EventTypes.DamageApplied, { AttackerId = getId(event.Source), DefenderId = getId(event.Target),
				Amount = event.AppliedAmount or event.Amount, RequestedAmount = event.RequestedAmount,
				AttackInstanceId = event.AttackInstance and event.AttackInstance.Id,
				CustomData = event.OffensiveProperties and event.OffensiveProperties.CustomData }, event.Frame, getId(event.Target)
		end
	end)
	publish("StatusEffect", self.StatusEffectResolver:GetEvents(), function(event)
		return EventTypes.StatusEffectApplied, {
			EffectType = event.Type, StatusName = event.StatusName, EffectId = event.EffectId,
			SourceId = getId(event.Source), TargetId = getId(event.Target),
			Amount = event.Amount, AppliedAmount = event.AppliedAmount,
		}, event.Frame, getId(event.Target)
	end)
	publish("Health", self:GetHealthChangedEvents(), function(event)
		if event.Reason == "StatusEffect" then
			return EventTypes.HealApplied, {
				SourceId = getId(event.Source), TargetId = getId(event.Entity),
				Amount = event.Delta, StatusName = event.StatusName, EffectId = event.EffectId,
			}, event.Frame, getId(event.Entity)
		end
	end)
	publish("Damage", self:GetDeathEvents(), function(event)
		return EventTypes.Death, { EntityId = getId(event.Entity or event.Target), Frame = event.Frame,
			Source = event.Source }, event.Frame, getId(event.Entity or event.Target)
	end)
	publish("Guard", self:GetGuardEvents(), function(event)
		if event.GuardBroken then return EventTypes.GuardBreak, { GuardDamage = event.GuardDamage,
			RemainingGuard = event.RemainingGuard, AttackerId = getId(event.Attacker),
			DefenderId = getId(event.Defender), AttackInstanceId = event.AttackInstanceId },
			event.Frame, getId(event.Defender) end
	end)
	publish("Protection", self.ProtectionResolver:GetResults(), function(result)
		if result.Result == "Blocked" and result.Category ~= "Hit" then
			return EventTypes.ProtectionApplied, { DefenderId = getId(result.Target), Category = result.Category,
				Reason = result.Kind, Source = result.Source, Result = result.Result }, result.Frame, getId(result.Target)
		end
	end)
	publish("Armor", self.ArmorResolver:GetResults(), function(event)
		if event.Found then return EventTypes.ArmorApplied, event, event.Frame, getId(event.Entity or event.Target) end
	end)
	publish("Motion", self:GetMotionResults(), basic(EventTypes.MotionApplied,
		{ "Type", "Frame", "Applied", "RequestId" }))
	publish("Hitstop", self.HitstopResolver:GetResults(), function(event)
		local kind = event.Outcome == "Applied" and EventTypes.HitstopStarted or event.Type == "Ended" and EventTypes.HitstopEnded
		if kind then return kind, event, event.Frame, getId(event.Entity or event.Target) end
	end)
	publish("Combo", self:GetComboEvents(), function(event)
		local kind = event.Type == "ComboStarted" and EventTypes.ComboStarted
			or event.Type == "ComboHit" and EventTypes.ComboUpdated
			or (event.Type == "ComboEnded" or event.Type == "ComboBroken") and EventTypes.ComboEnded
		if kind then return kind, event, event.Frame, getId(event.Defender) end
	end)
	publish("Juggle", self:GetJuggleEvents(), function(event)
		local kind = event.Type == "JuggleStarted" and EventTypes.JuggleStarted
			or (event.Type == "JuggleEnded" or event.Type == "JuggleBroken") and EventTypes.JuggleEnded
		if kind then return kind, event, event.Frame, event.EntityId end
	end)
	publish("MovementState", self.MovementStateResolver and self.MovementStateResolver:GetEvents() or {}, function(event)
		if event.Type == "StateChanged" then
			return EventTypes.MovementStateChanged, { EntityId = event.EntityId, PreviousState = event.PreviousState,
				CurrentState = event.CurrentState, Frame = event.Frame }, event.Frame, event.EntityId
		end
	end)
	publish("Cancel", self:GetCancelEvents(), function(event)
		local kind = event.Type == "CancelAllowed" and EventTypes.CancelAllowed
			or event.Type == "CancelRejected" and EventTypes.CancelRejected
		if kind then return kind, event, event.Frame, event.EntityId end
	end)
	publish("Input", self:GetInputEvents(), function(event)
		local kind = (event.Type == "Pressed" or event.Type == "InputPressed") and EventTypes.InputPressed or EventTypes.InputReleased
		return kind, event, event.Frame, event.EntityId
	end)
	publish("Prediction", self:GetPredictionEvents(), function(event)
		local kind = event.Type == "PredictionDiverged" and EventTypes.PredictionDiverged
			or event.Type == "FrameConfirmed" and EventTypes.FrameConfirmed
		if kind then return kind, event, event.Frame, event.EntityId end
	end)
	publish("Rollback", self:GetRollbackEvents(), function(event)
		local map = { RollbackStarted = EventTypes.RollbackStarted, RollbackCompleted = EventTypes.RollbackCompleted,
			RollbackFailed = EventTypes.RollbackFailed }
		local kind = map[event.Type]
		if kind then return kind, event, event.Frame, event.EntityId end
	end)
	publish("Authority", self:GetAuthorityEvents(), function(event)
		local map = { InputAccepted = EventTypes.AuthorityInputAccepted, InputRejected = EventTypes.AuthorityInputRejected,
			SnapshotPublished = EventTypes.AuthoritySnapshotPublished,
			AuthorityInputAccepted = EventTypes.AuthorityInputAccepted,
			AuthorityInputRejected = EventTypes.AuthorityInputRejected,
			AuthoritySnapshotPublished = EventTypes.AuthoritySnapshotPublished }
		local kind = map[event.Type]
		if kind then return kind, event, event.Frame, event.EntityId end
	end)
	return self.EventSequence
end

function World:Clear()
	local entities = self.EntityRegistry:GetAll()

	for _, entity in ipairs(entities) do
		self:DestroyEntity(entity)
	end
end

function World:Destroy()
	if self.Destroyed or self.Destroying then return false end
	self.Destroying = true
	self.ExecutionContext = "Normal"
	if self.Simulation then
		self.Simulation:SetExecutionContext("Normal")
	end
	if self.PluginResolver then self.PluginResolver:Destroy() end
	self:Clear()
	self.Destroyed = true
	self.Destroying = false
	if self.APIContext then self.APIContext:Destroy() end
	if self.ExternalFactJournal then self.ExternalFactJournal:Clear() end
	self.EventBus = nil
	table.clear(self.PublishedInternalEvents)
	return true
end

function World:GetPluginResolver()
	return self.PluginResolver
end

function World:SetCollisionWorld(collisionWorld)
	assert(collisionWorld and type(collisionWorld.Step) == "function"
		and type(collisionWorld.RegisterHitbox) == "function"
		and type(collisionWorld.RegisterHurtbox) == "function",
		"World:SetCollisionWorld() expects a compatible CollisionWorld")
	assert(self.CollisionWorld == nil or self.CollisionWorld == collisionWorld,
		"World already has a CollisionWorld")

	self.CollisionWorld = collisionWorld
	if collisionWorld.DamageResolver then
		self.DamageResolver = collisionWorld.DamageResolver
		self.DamageResolver:SetWorld(self)
	end
	if collisionWorld.ReactionResolver then
		self.ReactionResolver = collisionWorld.ReactionResolver
		self.ReactionResolver:SetWorld(self)
	end
	if collisionWorld.DefenseResolver then
		self.DefenseResolver = collisionWorld.DefenseResolver
	end
	if collisionWorld.CombatResolver then
		self.CombatResolver = collisionWorld.CombatResolver
	end
	if collisionWorld.CounterResolver then
		self.CounterResolver = collisionWorld.CounterResolver
	end
	if collisionWorld.MotionResolver then
		self.MotionResolver = collisionWorld.MotionResolver
	end

	for _, entity in ipairs(self.EntityRegistry:GetAll()) do
		for _, component in pairs(entity.Components) do
			if component.CombatRegionType == "Hitbox" then
				collisionWorld:RegisterHitbox(component)
			elseif component.CombatRegionType == "Hurtbox" then
				collisionWorld:RegisterHurtbox(component)
			end
		end
	end

	return collisionWorld
end

function World:GetCollisionWorld()
	return self.CollisionWorld
end

function World:GetDamageResolver()
	return self.DamageResolver
end

function World:GetStatusEffectResolver()
	return self.StatusEffectResolver
end

function World:GetReactionResolver()
	return self.ReactionResolver
end

function World:GetDefenseResolver()
	return self.DefenseResolver
end

function World:GetCombatResolver()
	return self.CombatResolver
end

function World:GetCombatResolutionEvents()
	return self.CombatResolver and self.CombatResolver:GetResolutionEvents() or {}
end

function World:GetMotionResolver()
	return self.MotionResolver
end

function World:GetCounterResults()
	return self.CounterResolver and self.CounterResolver:GetResults() or {}
end

function World:GetHitstopResolver()
	return self.HitstopResolver
end

function World:GetProtectionResolver()
	return self.ProtectionResolver
end

function World:GetTimeEffectResults()
	return self.HitstopResolver:GetResults()
end

function World:GetProtectionResults()
	return self.ProtectionResolver:GetResults()
end

function World:GetGuardResolver()
	return self.GuardResolver
end

function World:GetGuardEvents()
	return self.GuardResolver and self.GuardResolver:GetEvents() or {}
end

function World:GetGuardResults()
	return self.GuardResolver and self.GuardResolver:GetResults() or {}
end

function World:GetArmorResolver()
	return self.ArmorResolver
end

function World:GetArmorResults()
	return self.ArmorResolver:GetResults()
end

function World:GetComboResolver()
	return self.ComboResolver
end

function World:GetComboEvents()
	return self.ComboResolver and self.ComboResolver:GetEvents() or {}
end

function World:GetComboResults()
	return self.ComboResolver and self.ComboResolver:GetResults() or {}
end

function World:GetJuggleResolver()
	return self.JuggleResolver
end

function World:GetJuggleEvents()
	return self.JuggleResolver and self.JuggleResolver:GetEvents() or {}
end

function World:GetJuggleResults()
	return self.JuggleResolver and self.JuggleResolver:GetResults() or {}
end

function World:GetMovementStateResolver()
	return self.MovementStateResolver
end

function World:GetCancelResolver()
	return self.CancelResolver
end

function World:GetCancelEvents()
	return self.CancelResolver and self.CancelResolver:GetEvents() or {}
end

function World:GetCancelResults()
	return self.CancelResolver and self.CancelResolver:GetResults() or {}
end

function World:GetInputResolver()
	return self.InputResolver
end

function World:GetInputEvents()
	return self.InputResolver and self.InputResolver:GetEvents() or {}
end

function World:GetCharacterResolver()
	return self.CharacterResolver
end
function World:AttachCharacter(entityOrId, representation, options)
	assert(not self.Destroyed and self.ExecutionContext == "Normal",
		"Character attachment can only run during normal execution")
	return self.CharacterResolver:Attach(entityOrId, representation, options)
end
function World:DetachCharacter(entityOrId, options)
	assert(not self.Destroyed and self.ExecutionContext == "Normal",
		"Character detachment can only run during normal execution")
	return self.CharacterResolver:Detach(entityOrId, options)
end
function World:ReattachCharacter(entityOrId, representation, options)
	assert(not self.Destroyed and self.ExecutionContext == "Normal",
		"Character reattachment can only run during normal execution")
	return self.CharacterResolver:Reattach(entityOrId, representation, options)
end
function World:GetCharacterRoot(entityOrId)
	local adapter = self.CharacterResolver:GetAdapter(entityOrId)
	local representation = self.CharacterResolver:GetRepresentation(entityOrId)
	return adapter and adapter:GetRoot(representation, { World = self, EntityId = type(entityOrId) == "table" and entityOrId.Id or entityOrId })
end
function World:GetCharacterPart(entityOrId, partName)
	assert(type(partName) == "string" and partName ~= "", "Character part name is required")
	local adapter = self.CharacterResolver:GetAdapter(entityOrId)
	local representation = self.CharacterResolver:GetRepresentation(entityOrId)
	return adapter and adapter:GetPart(representation, partName, {
		World = self, EntityId = type(entityOrId) == "table" and entityOrId.Id or entityOrId,
	})
end
function World:GetCharacterEvents()
	return self.CharacterResolver and self.CharacterResolver:GetEvents() or {}
end

function World:GetCharacterResults()
	return self.CharacterResolver and self.CharacterResolver:GetResults() or {}
end

function World:GetAnimationResolver()
	return self.AnimationResolver
end

function World:GetAnimationEvents()
	return self.AnimationResolver and self.AnimationResolver:GetEvents() or {}
end

function World:GetAnimationResults()
	return self.AnimationResolver and self.AnimationResolver:GetResults() or {}
end

function World:GetNetworkResolver()
	return self.NetworkResolver
end

function World:GetNetworkEvents()
	return self.NetworkResolver and self.NetworkResolver:GetEvents() or {}
end

function World:GetNetworkResults()
	return self.NetworkResolver and self.NetworkResolver:GetResults() or {}
end

function World:GetPredictionResolver()
	return self.PredictionResolver
end

function World:GetPredictionEvents()
	return self.PredictionResolver and self.PredictionResolver:GetEvents() or {}
end

function World:GetPredictionResults()
	return self.PredictionResolver and self.PredictionResolver:GetResults() or {}
end

function World:GetReconciliationResolver()
	return self.ReconciliationResolver
end

function World:GetReconciliationResults()
	return self.ReconciliationResolver and self.ReconciliationResolver:GetResults() or {}
end

function World:GetRollbackResolver()
	return self.RollbackResolver
end

function World:GetAuthorityResolver()
	return self.AuthorityResolver
end

function World:GetAuthorityEvents()
	return self.AuthorityResolver and self.AuthorityResolver:GetEvents() or {}
end

function World:GetAuthorityResults()
	return self.AuthorityResolver and self.AuthorityResolver:GetResults() or {}
end

function World:GetRollbackEvents()
	return self.RollbackResolver and self.RollbackResolver:GetEvents() or {}
end

function World:GetRollbackResults()
	return self.RollbackResolver and self.RollbackResolver:GetResults() or {}
end

function World:GetCombatPipeline() return self.CombatPipeline end
function World:GetCombatStateSchema() return self.CombatStateSchema end
function World:GetGameplayScheduler()
	return self.Simulation and self.Simulation:GetGameplayScheduler() or nil
end
function World:RegisterCombatComponentFactory(key, factory)
	assert(not self.Destroyed and self.ExecutionContext == "Normal",
		"Component factories can only be registered during normal execution")
	self.CombatStateSchema:RegisterComponent(key, factory)
	return self
end
function World:RegisterCombatStateProvider(key, provider)
	assert(not self.Destroyed and self.ExecutionContext == "Normal",
		"State providers can only be registered during normal execution")
	self.CombatStateSchema:RegisterStateProvider(key, provider)
	return self
end
function World:CaptureCombatState()
	assert(not self.Destroyed, "Cannot capture state from a destroyed World")
	return self.CombatStateSchema:Capture(self)
end
function World:RestoreCombatState(snapshot, options)
	assert(not self.Destroyed, "Cannot restore state into a destroyed World")
	return self.CombatStateSchema:Restore(self, snapshot, options)
end
function World:HashCombatState(snapshot)
	return self.CombatStateSchema:Hash(snapshot or self:CaptureCombatState())
end
function World:CompareCombatStates(left, right)
	return self.CombatStateSchema:Compare(left, right)
end
function World:GetCombatActionEvents() return self.CombatPipeline:GetEvents() end
function World:GetCombatActionResults() return self.CombatPipeline:GetResults() end

function World:SetSimulation(simulation)
	assert(simulation and simulation:GetWorld() == self, "Simulation belongs to a different World")
	assert(self.Simulation == nil or self.Simulation == simulation, "World already has a Simulation")
	self.Simulation = simulation
	return simulation
end

function World:GetSimulation()
	return self.Simulation
end
function World:RegisterGameplayEventHandler(typeId, handler)
	assert(self.Simulation, "World has no Simulation")
	return self.Simulation:RegisterGameplayEventHandler(typeId, handler)
end
function World:RegisterGameplayActionEventHandler(typeId, handler)
	assert(self.Simulation, "World has no Simulation")
	return self.Simulation:RegisterGameplayActionEventHandler(typeId, handler)
end
function World:ScheduleGameplayEvent(frame, typeId, ownerId, parameters, intervalFrames)
	assert(self.Simulation, "World has no Simulation")
	return self.Simulation:ScheduleGameplayEvent(frame, typeId, ownerId, parameters, intervalFrames)
end
function World:ScheduleGameplayEventAfter(delayFrames, typeId, ownerId, parameters, intervalFrames)
	assert(self.Simulation, "World has no Simulation")
	return self.Simulation:ScheduleGameplayEventAfter(
		delayFrames, typeId, ownerId, parameters, intervalFrames)
end

function World:GetExecutionContext()
	return self.ExecutionContext
end

function World:SetExecutionContext(context)
	assert(context == "Normal" or context == "Prediction" or context == "Replay"
		or context == "Rollback" or context == "Authority",
		"World execution context is invalid")
	self.ExecutionContext = context
	return self
end

function World:GetDefenseEvents()
	return self.DefenseResolver and self.DefenseResolver:GetDefenseEvents() or {}
end

function World:GetMotionResults()
	return self.MotionResolver and self.MotionResolver:GetResults() or {}
end

function World:GetDamageRequests()
	return self.DamageResolver and self.DamageResolver:GetDamageRequests() or {}
end

function World:GetDamageEvents()
	return self.DamageResolver and self.DamageResolver:GetDamageEvents() or {}
end

function World:GetHealthChangedEvents()
	return self.DamageResolver and self.DamageResolver:GetHealthChangedEvents() or {}
end

function World:GetDeathEvents()
	return self.DamageResolver and self.DamageResolver:GetDeathEvents() or {}
end

local function updateEntities(self, methodName, deltaTime)
	local entities = self.EntityRegistry:GetAll()

	for _, entity in ipairs(entities) do
		if self.EntityRegistry:Get(entity.Id) == entity and not entity.Destroyed then
			entity[methodName](entity, deltaTime)
		end
	end
end

function World:Update(deltaTime)
	updateEntities(self, "Update", deltaTime)
end

function World:Step(deltaTime, frame, time)
	assert(not self.Destroyed, "Cannot step a destroyed World")
	self.LastResolvedHitEvents = nil
	local resolvedFrame = frame or (self.HitstopResolver.Frame + 1)
	self.CurrentFrame = resolvedFrame
	self.ProtectionResolver:Clear()
	self.ArmorResolver:Clear()
	self.CombatPipeline:Step(resolvedFrame)
	-- Requests are applied before component steps; frames are consumed after the full World step.
	self.HitstopResolver:Process(resolvedFrame)
	updateEntities(self, "Step", deltaTime)
	local statusEffectRequests = {}
	for _, entity in ipairs(self.EntityRegistry:GetAll()) do
		local container = entity:GetComponent(StatusContainer)
		if container then
			for _, request in ipairs(container:DrainEffectRequests()) do
				table.insert(statusEffectRequests, request)
			end
		end
	end

	if self.CollisionWorld then
		-- Order: component Step, collision/HitEvent, combat resolution, Protection(Hit),
		-- Defense, Counter, Armor, Protection(Damage/Hitstun), Damage, status effects,
		-- Reactions, Motion.
		self.CollisionWorld:Step(deltaTime, frame, time)
		resolvedFrame = frame or self.CollisionWorld.Frame
		local hitEvents = self.CollisionWorld:GetHitEvents()
		if self.CombatResolver then
			hitEvents = self.CombatResolver:Process(hitEvents)
		end
		hitEvents = self.ProtectionResolver:FilterHitEvents(hitEvents, "Hit", resolvedFrame, time)

		-- Defense and Counter are semantic combat stages; neither requires Health.
		if self.DefenseResolver then
			hitEvents = self.DefenseResolver:Process(hitEvents, resolvedFrame)
		end
		self.LastResolvedHitEvents = hitEvents
		if self.CounterResolver then
			self.CounterResolver:Process(hitEvents)
		end
		local armorResults = self.ArmorResolver:Process(hitEvents)
		if self.GuardResolver then
			self.GuardResolver:Process(self.DefenseResolver and self.DefenseResolver:GetDefenseEvents() or hitEvents, resolvedFrame, time)
		end
		local damageHitEvents = self.ArmorResolver:FilterHitEvents(hitEvents, "Damage")
		damageHitEvents = self.ProtectionResolver:FilterHitEvents(
			damageHitEvents, "Damage", resolvedFrame, time)
		local reactionHitEvents = self.ProtectionResolver:FilterHitEvents(
			hitEvents, "Hitstun", resolvedFrame, time)

		if self.DamageResolver then
			local resolvedTime = time
			if resolvedTime == nil then
				resolvedTime = resolvedFrame * deltaTime
			end
			self.DamageResolver:Process(damageHitEvents, resolvedFrame, resolvedTime, armorResults)
			self.StatusEffectResolver:Process(statusEffectRequests, resolvedFrame, resolvedTime)
			if self.ReactionResolver then
				self.ReactionResolver:Process(self.DamageResolver:GetDamageEvents(), armorResults,
					reactionHitEvents, self.ProtectionResolver, resolvedFrame, resolvedTime)
			end
		else
			local resolvedTime = time or resolvedFrame * deltaTime
			self.StatusEffectResolver:Process(statusEffectRequests, resolvedFrame, resolvedTime)
		end

		if self.MotionResolver then
			local motionRequests = self.ArmorResolver:FilterMotionRequests(
				self.MotionResolver:GetPendingRequests(), armorResults)
			self.MotionResolver:Process(motionRequests, resolvedFrame)
		end
		self.ComboResolver:Process(hitEvents, self.DefenseResolver and self.DefenseResolver:GetDefenseEvents() or {},
			self.DamageResolver and self.DamageResolver:GetDamageEvents() or {},
			self.CounterResolver and self.CounterResolver:GetResults() or {}, resolvedFrame,
			self.DamageResolver and self.DamageResolver:GetDeathEvents() or {},
			self.GuardResolver and self.GuardResolver:GetEvents() or {}, armorResults, reactionHitEvents)
		self.JuggleResolver:Process(hitEvents, self.MotionResolver and self.MotionResolver:GetResults() or {},
			self.DefenseResolver and self.DefenseResolver:GetDefenseEvents() or {}, resolvedFrame)
	elseif self.DamageResolver then
		local resolvedFrame = frame or 0
		local resolvedTime = time or 0
		self.DamageResolver:Process({}, resolvedFrame, resolvedTime)
		self.StatusEffectResolver:Process(statusEffectRequests, resolvedFrame, resolvedTime)
		if self.ReactionResolver then
			self.ReactionResolver:Process(self.DamageResolver:GetDamageEvents())
		end
		self.ComboResolver:Process({}, {}, self.DamageResolver:GetDamageEvents(), {}, resolvedFrame,
			self.DamageResolver:GetDeathEvents())
		self.JuggleResolver:Process({}, self.MotionResolver and self.MotionResolver:GetResults() or {}, {}, resolvedFrame)
	else
		self.StatusEffectResolver:Process(statusEffectRequests, resolvedFrame, time or 0)
		self.ComboResolver:Process({}, {}, {}, {}, resolvedFrame)
		self.JuggleResolver:Process({}, self.MotionResolver and self.MotionResolver:GetResults() or {}, {}, resolvedFrame)
	end
	self:FlushEvents()
	self.ArmorResolver:AdvanceStep()
	self.ProtectionResolver:AdvanceFrame(resolvedFrame)
	self.HitstopResolver:AdvanceStep()
end

return World
