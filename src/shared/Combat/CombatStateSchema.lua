-- Versioned, serializable World state schema with coordinated rollback restoration.
-- Component factories must be registered by stable RollbackKey and must be side-effect free.
local CombatEntity = require(script.Parent.Parent.Core.CombatEntity)
local EntityState = require(script.Parent.Parent.Core.EntityState)
local Serializer = require(script.Parent.Parent.Simulation.StateSerializer)
local StateHasher = require(script.Parent.Parent.Simulation.StateHasher)
local CombatRestoreCoordinator = require(script.Parent.CombatRestoreCoordinator)
local HealthComponent = require(script.Parent.HealthComponent)
local RollbackComponent = require(script.Parent.RollbackComponent)
local PredictionComponent = require(script.Parent.PredictionComponent)

local Schema = {}
Schema.__index = Schema
Schema.Version = 3

local function idLess(a, b)
	if type(a) ~= type(b) then return type(a) < type(b) end
	if type(a) == "number" or type(a) == "string" then return a < b end
	return tostring(a) < tostring(b)
end

local function keyFor(component)
	local mt = getmetatable(component)
	return component.RollbackKey or (mt and mt.RollbackKey)
end

local function isResolverOwnedComponent(component)
	return component == RollbackComponent
		or component == PredictionComponent
		or getmetatable(component) == RollbackComponent
		or getmetatable(component) == PredictionComponent
end

local function isDenseArray(value)
	if type(value) ~= "table" then return false end
	local count, maxIndex = 0, 0
	for key in pairs(value) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
		count += 1
		if key > maxIndex then maxIndex = key end
	end
	return count == maxIndex
end

function Schema.new(options)
	options = options or {}
	assert(type(options) == "table", "CombatStateSchema.new expects options")
	local schema = setmetatable({
		Factories = {},
		Providers = {},
		Migrations = {},
		MaxSnapshotEntries = options.MaxSnapshotEntries or 100000,
		MaxSnapshotDepth = options.MaxSnapshotDepth or 64,
	}, Schema)
	schema:RegisterMigration(2, function(snapshot) snapshot.Version = 3; return snapshot end)
	return schema
end

function Schema:RegisterMigration(fromVersion, migrate)
	assert(type(fromVersion) == "number" and fromVersion >= 1
		and fromVersion < Schema.Version and fromVersion % 1 == 0,
		"Combat state migration source version must be older than the current version")
	assert(type(migrate) == "function", "Combat state migration must be a function")
	assert(not self.Migrations[fromVersion],
		"Combat state migration already registered from version " .. tostring(fromVersion))
	self.Migrations[fromVersion] = migrate
	return self
end

function Schema:Migrate(snapshot)
	if type(snapshot) ~= "table" or getmetatable(snapshot) ~= nil
		or type(snapshot.Version) ~= "number" or snapshot.Version % 1 ~= 0 then
		return nil, "Invalid combat state snapshot version"
	end
	if snapshot.Version > Schema.Version then return nil, "Unsupported future CombatStateSchema version" end
	if snapshot.Version == Schema.Version then return snapshot end

	local ok, migrated = pcall(Serializer.CloneSerializable, snapshot, {
		MaxEntries = self.MaxSnapshotEntries,
		MaxDepth = self.MaxSnapshotDepth,
	})
	if not ok then return nil, "Combat state migration input is invalid: " .. tostring(migrated) end
	while migrated.Version < Schema.Version do
		local fromVersion = migrated.Version
		local migration = self.Migrations[fromVersion]
		if not migration then
			return nil, "Missing combat state migration from version " .. tostring(fromVersion)
		end
		local migrationOk, nextSnapshot = pcall(migration, Serializer.CloneSerializable(migrated, {
			MaxEntries = self.MaxSnapshotEntries,
			MaxDepth = self.MaxSnapshotDepth,
		}))
		if not migrationOk then
			return nil, "Combat state migration from version " .. tostring(fromVersion)
				.. " failed: " .. tostring(nextSnapshot)
		end
		if type(nextSnapshot) ~= "table" or getmetatable(nextSnapshot) ~= nil
			or nextSnapshot.Version ~= fromVersion + 1 then
			return nil, "Combat state migration must advance exactly one version"
		end
		local cloneOk, clone = pcall(Serializer.CloneSerializable, nextSnapshot, {
			MaxEntries = self.MaxSnapshotEntries,
			MaxDepth = self.MaxSnapshotDepth,
		})
		if not cloneOk then
			return nil, "Combat state migration produced invalid data: " .. tostring(clone)
		end
		migrated = clone
	end
	return migrated
end

function Schema:RegisterComponent(key, factory)
	assert(type(key) == "string" and key ~= "", "Component rollback key must be a non-empty string")
	assert(type(factory) == "function", "Component factory must be a function")
	assert(not self.Factories[key], "Component factory already registered: " .. key)
	self.Factories[key] = factory
	return self
end

-- Providers cover mutable subsystems outside entity components (for example, a plugin
-- with deterministic gameplay state). PrepareRollbackRestore must validate and prepare
-- without mutating live state; the returned commit function must be deterministic and
-- non-yielding. Providers are opt-in: unregistered mutable plugin state is not captured.
function Schema:RegisterStateProvider(key, provider)
	assert(type(key) == "string" and key ~= "", "State provider key must be a non-empty string")
	assert(type(provider) == "table", "State provider must be a table")
	assert(type(provider.CaptureRollbackState) == "function", "Provider must implement CaptureRollbackState")
	assert(type(provider.ValidateRollbackState) == "function", "Provider must implement ValidateRollbackState")
	assert(type(provider.PrepareRollbackRestore) == "function", "Provider must implement PrepareRollbackRestore")
	assert(not self.Providers[key], "State provider already registered: " .. key)
	self.Providers[key] = provider
	return self
end

function Schema:Capture(world)
	assert(world and type(world.GetEntities) == "function", "Capture requires a World")
	local simulation = world:GetSimulation()
	assert(simulation, "World has no Simulation")
	local simulationState = simulation:CaptureState()
	assert(world.CurrentFrame == simulationState.Frame, "World and Simulation frames are misaligned")
	local entities = {}
	for _, entity in ipairs(world:GetEntities()) do
		local components, seen, orderedTypes = {}, {}, {}
		for _, componentType in ipairs(entity.ComponentOrder) do
			local component = entity.Components[componentType]
			assert(component ~= nil, "Entity " .. tostring(entity.Id) .. " has a broken ComponentOrder entry")
			if isResolverOwnedComponent(component) then
				continue
			end
			local key = keyFor(component)
			assert(type(key) == "string" and key ~= "", "Entity " .. tostring(entity.Id) .. " has a component without RollbackKey")
			assert(not seen[key], "Duplicate component RollbackKey on entity " .. tostring(entity.Id) .. ": " .. key)
			assert(type(component.CaptureRollbackState) == "function"
				and type(component.RestoreRollbackState) == "function",
				"Component " .. key .. " does not implement the rollback state contract")
			assert(self.Factories[key], "No component factory registered for " .. key)
			seen[key] = true
			orderedTypes[componentType] = true
			local state = component:CaptureRollbackState()
			table.insert(components, {
				Key = key,
				Order = #components + 1,
				Enabled = component:IsEnabled(),
				State = Serializer.CloneSerializable(state, {
					MaxEntries = self.MaxSnapshotEntries,
					MaxDepth = self.MaxSnapshotDepth,
				}),
			})
		end

		local orderedCount = 0
		for componentType in pairs(entity.Components) do
			local component = entity.Components[componentType]
			if not isResolverOwnedComponent(component) then
				assert(orderedTypes[componentType],
					"Entity " .. tostring(entity.Id) .. " has a component missing from ComponentOrder")
				orderedCount += 1
			end
		end
		local capturedCount = 0
		for _, componentType in ipairs(entity.ComponentOrder) do
			if not isResolverOwnedComponent(entity.Components[componentType]) then
				capturedCount += 1
			end
		end
		assert(orderedCount == capturedCount,
			"Entity " .. tostring(entity.Id) .. " has inconsistent component metadata")
		table.insert(entities, { Id = entity.Id, State = entity.State, Components = components })
	end
	table.sort(entities, function(a, b) return idLess(a.Id, b.Id) end)
	local providers = {}
	local providerKeys = {}
	for key in pairs(self.Providers) do table.insert(providerKeys, key) end
	table.sort(providerKeys)
	for _, key in ipairs(providerKeys) do
		local provider = self.Providers[key]
		local state = provider:CaptureRollbackState(world)
		assert(type(state) == "table", "State provider " .. key .. " must capture a table")
		local valid, detail = provider:ValidateRollbackState(state, world)
		assert(valid == true, "State provider " .. key .. " rejected its captured state: " .. tostring(detail))
		providers[key] = Serializer.CloneSerializable(state, {
			MaxEntries = self.MaxSnapshotEntries,
			MaxDepth = self.MaxSnapshotDepth,
		})
	end
	local collisionState = nil
	if world.CollisionWorld then
		assert(world.CollisionWorld.Frame == simulationState.Frame,
			"World, Simulation, and CollisionWorld frames must be aligned before capture")
		collisionState = Serializer.CloneSerializable(world.CollisionWorld:CaptureRollbackState(), {
			MaxEntries = self.MaxSnapshotEntries, MaxDepth = self.MaxSnapshotDepth,
		})
	end
	local data = {
		Version = Schema.Version,
		Frame = simulationState.Frame,
		IdGeneratorState = world.IdGenerator.LastId,
		Simulation = Serializer.CloneSerializable(simulationState),
		Entities = entities,
		Providers = providers,
		CollisionWorld = collisionState,
	}
	return Serializer.Freeze(Serializer.CloneSerializable(data, {
		MaxEntries = self.MaxSnapshotEntries,
		MaxDepth = self.MaxSnapshotDepth,
	}))
end

function Schema:Hash(snapshot)
	assert(type(snapshot) == "table", "CombatStateSchema:Hash expects a snapshot")
	return StateHasher.Hash(snapshot, {
		MaxEntries = self.MaxSnapshotEntries,
		MaxDepth = self.MaxSnapshotDepth,
	})
end

function Schema:Compare(left, right)
	assert(type(left) == "table" and type(right) == "table",
		"CombatStateSchema:Compare expects two snapshots")
	local leftCanonical = Serializer.Serialize(left, {
		MaxEntries = self.MaxSnapshotEntries,
		MaxDepth = self.MaxSnapshotDepth,
	})
	local rightCanonical = Serializer.Serialize(right, {
		MaxEntries = self.MaxSnapshotEntries,
		MaxDepth = self.MaxSnapshotDepth,
	})
	return {
		Equal = leftCanonical == rightCanonical,
		LeftHash = self:Hash(left),
		RightHash = self:Hash(right),
	}
end

function Schema:Validate(snapshot, world)
	if type(snapshot) ~= "table" or getmetatable(snapshot) ~= nil then return false, "Snapshot must be a plain table" end
	if snapshot.Version ~= Schema.Version then return false, "Unsupported CombatStateSchema version" end
	if type(snapshot.Frame) ~= "number" or snapshot.Frame < 0 or snapshot.Frame % 1 ~= 0 then return false, "Invalid snapshot frame" end
	if type(snapshot.IdGeneratorState) ~= "number" or snapshot.IdGeneratorState < 0
		or snapshot.IdGeneratorState % 1 ~= 0 or snapshot.IdGeneratorState ~= snapshot.IdGeneratorState
		or snapshot.IdGeneratorState == math.huge then return false, "Invalid ID generator state" end
	if type(snapshot.Simulation) ~= "table" or snapshot.Simulation.Frame ~= snapshot.Frame then return false, "Simulation frame mismatch" end
	if not isDenseArray(snapshot.Entities) then return false, "Entities must be a dense array" end
	if type(snapshot.Providers) ~= "table" then return false, "Providers must be a table" end
	if world and world.CollisionWorld then
		if type(snapshot.CollisionWorld) ~= "table" then return false, "Snapshot is missing CollisionWorld state" end
		if snapshot.CollisionWorld.Version ~= 1 then return false, "Unsupported CollisionWorld snapshot version" end
		if snapshot.CollisionWorld.Frame ~= snapshot.Frame then return false, "CollisionWorld frame mismatch" end
	elseif snapshot.CollisionWorld ~= nil then
		return false, "Snapshot requires a CollisionWorld, but none is configured"
	end
	for key, provider in pairs(self.Providers) do
		if snapshot.Providers[key] == nil then return false, "Snapshot is missing state provider: " .. key end
		local ok, accepted, detail = pcall(provider.ValidateRollbackState, provider,
			snapshot.Providers[key], world)
		if not ok or accepted ~= true then
			return false, "State provider rejected snapshot " .. key .. ": " .. tostring(ok and detail or accepted)
		end
	end
	for key, providerState in pairs(snapshot.Providers) do
		if not self.Providers[key] then return false, "Snapshot contains an unregistered state provider: " .. tostring(key) end
		if type(providerState) ~= "table" then return false, "State provider payload must be a table: " .. tostring(key) end
	end
	local ids, previousId = {}, nil
	for _, entity in ipairs(snapshot.Entities) do
		if type(entity) ~= "table" or (type(entity.Id) ~= "number" and type(entity.Id) ~= "string")
			or (type(entity.Id) == "number" and (entity.Id ~= entity.Id or entity.Id == math.huge
				or entity.Id == -math.huge or entity.Id % 1 ~= 0))
			or entity.Id == "" or ids[entity.Id] then return false, "Invalid or duplicate entity ID" end
		if entity.State ~= EntityState.Alive and entity.State ~= EntityState.Dead then return false, "Invalid entity state" end
		if previousId ~= nil and not idLess(previousId, entity.Id) then return false, "Entity IDs are not in canonical order" end
		previousId, ids[entity.Id] = entity.Id, true
		if not isDenseArray(entity.Components) then return false, "Invalid component list" end
		local componentKeys = {}
		for componentIndex, component in ipairs(entity.Components) do
			if type(component) ~= "table" then return false, "Invalid component entry" end
			if type(component.Key) ~= "string" or component.Key == "" or componentKeys[component.Key]
				or component.Order ~= componentIndex then
				return false, "Invalid, duplicated, or non-canonical component entry"
			end
			if type(component.Enabled) ~= "boolean" then return false, "Invalid component Enabled flag" end
			if not self.Factories[component.Key] then return false, "Missing component factory: " .. component.Key end
			if type(component.State) ~= "table" then return false, "Component state must be a table" end
			componentKeys[component.Key] = true
			if component.Key == HealthComponent.RollbackKey and component.Enabled then
				local healthValid, healthDetail = HealthComponent.ValidateRollbackState(HealthComponent, component.State)
				if not healthValid then
					return false, "Invalid HealthComponent snapshot for entity " .. tostring(entity.Id) .. ": " .. tostring(healthDetail)
				end
				local healthIsZero = component.State.CurrentHealth == 0
				local entityIsDead = entity.State == EntityState.Dead
				if healthIsZero ~= entityIsDead then
					return false, "Health/lifecycle mismatch for entity " .. tostring(entity.Id)
				end
			end
		end
	end
	local ok, err = pcall(Serializer.CloneSerializable, snapshot, {
		MaxEntries = self.MaxSnapshotEntries, MaxDepth = self.MaxSnapshotDepth,
	})
	if not ok then return false, tostring(err) end
	return true
end

-- Restore coordinates the entity roster, registered state providers, Simulation, and configured
-- CollisionWorld through the two-phase coordinator. Resolver state is included only when its
-- provider has been explicitly registered with the schema.
function Schema:Restore(world, snapshot, options)
	assert(world and type(world.GetEntities) == "function", "Restore requires a World")
	options = options or {}
	local migratedSnapshot, migrationError = self:Migrate(snapshot)
	if not migratedSnapshot then return false, migrationError end
	snapshot = migratedSnapshot
	local valid, validationError = self:Validate(snapshot, world)
	if not valid then return false, validationError end
	local simulation = world:GetSimulation()
	if not simulation then return false, "World has no Simulation" end
	if world.ExecutionContext ~= "Normal" and not options.AllowRollback then
		return false, "Cannot restore while World is executing rollback/replay"
	end

	local oldEntities = world:GetEntities()
	local currentById = {}
	for _, entity in ipairs(oldEntities) do currentById[entity.Id] = entity end
	local rollbackEntityIds = {}
	for _, entity in ipairs(oldEntities) do
		if entity:GetComponent(RollbackComponent) then
			rollbackEntityIds[#rollbackEntityIds + 1] = entity.Id
		end
	end
	local stagedById = {}
	local stagedOk, stagedError = pcall(function()
		-- Allocate the complete staged roster first so components can resolve references
		-- to entities that appear later in canonical snapshot order.
		for _, saved in ipairs(snapshot.Entities) do
			local entity = CombatEntity.new(saved.Id)
			entity.State = saved.State
			stagedById[saved.Id] = entity
		end
		local componentContext = { World = world, EntitiesById = stagedById }
		for _, saved in ipairs(snapshot.Entities) do
			local entity = stagedById[saved.Id]
			for _, savedComponent in ipairs(saved.Components) do
				local stateCopy = Serializer.CloneSerializable(savedComponent.State)
				local component = self.Factories[savedComponent.Key](entity, stateCopy, componentContext)
				assert(component and type(component) == "table", "Factory returned invalid component: " .. savedComponent.Key)
				assert(keyFor(component) == savedComponent.Key, "Factory returned wrong RollbackKey: " .. savedComponent.Key)
				assert(type(component.RestoreRollbackState) == "function", "Factory component cannot restore state")
				if type(component.ValidateRollbackState) == "function" then
					local accepted, validationDetail = component:ValidateRollbackState(stateCopy, componentContext)
					assert(accepted == true, "Component state rejected for " .. savedComponent.Key .. ": " .. tostring(validationDetail))
				end
				entity:AddComponent(component)
				local restored, detail = component:RestoreRollbackState(stateCopy, componentContext)
				assert(restored ~= false, "Component restore failed for " .. savedComponent.Key .. ": " .. tostring(detail))
				component:SetEnabled(savedComponent.Enabled)
				if type(component.FinalizeRollbackRestore) == "function" then
					local finalized, finalizeDetail = component:FinalizeRollbackRestore(componentContext)
					assert(finalized ~= false, "Component restore finalization failed for "
						.. savedComponent.Key .. ": " .. tostring(finalizeDetail))
				end
			end
			local currentEntity = currentById[saved.Id]
			local rollbackComponent = currentEntity and currentEntity:GetComponent(RollbackComponent)
			if rollbackComponent then
				local restoredRollback = RollbackComponent.new(rollbackComponent.Profile)
				restoredRollback.CurrentFrame = rollbackComponent.CurrentFrame
				restoredRollback.LastRestoredFrame = rollbackComponent.LastRestoredFrame
				restoredRollback.LastRollbackFrame = rollbackComponent.LastRollbackFrame
				restoredRollback.RollbackCount = rollbackComponent.RollbackCount
				restoredRollback.RollbackState = rollbackComponent.RollbackState
				restoredRollback:SetEnabled(rollbackComponent:IsEnabled())
				entity:AddComponent(restoredRollback)
			end
			local predictionComponent = currentEntity and currentEntity:GetComponent(PredictionComponent)
			if predictionComponent then
				local restoredPrediction = PredictionComponent.new(predictionComponent.Profile)
				restoredPrediction:SetEnabled(predictionComponent:IsEnabled())
				local sourceState = predictionComponent.PredictionState
				local restoredState
				if sourceState then
					local PredictionState = require(script.Parent.PredictionState)
					local PredictionFrame = require(script.Parent.PredictionFrame)
					restoredState = PredictionState.new(saved.Id, sourceState.Profile)
					restoredState.Enabled = sourceState.Enabled
					restoredState.Started = sourceState.Started
					restoredState.CurrentFrame = sourceState.CurrentFrame
					restoredState.ConfirmedFrame = sourceState.ConfirmedFrame
					restoredState.PredictionFrameCount = sourceState.PredictionFrameCount
					for _, frameNumber in ipairs(sourceState.History.Order) do
						local frame = sourceState.History:Get(frameNumber)
						restoredState.History:Put(frameNumber, PredictionFrame.new({
							EntityId = frame.EntityId,
							Frame = frame.Frame,
							InputFrame = frame.InputFrame,
							Predicted = frame.Predicted,
							Confirmed = frame.Confirmed,
							PredictionIndex = frame.PredictionIndex,
						}))
					end
				end
				entity:AddComponent(restoredPrediction)
				if restoredState then
					restoredPrediction.PredictionState = restoredState
				end
			end
		end
	end)
	if not stagedOk then
		for _, entity in pairs(stagedById) do pcall(entity.Destroy, entity) end
		return false, "Could not stage entity roster: " .. tostring(stagedError)
	end

	local targetIds = {}
	for _, saved in ipairs(snapshot.Entities) do table.insert(targetIds, saved.Id) end
	local function idsOf(map)
		local ids = {}
		for id in pairs(map) do table.insert(ids, id) end
		table.sort(ids, idLess)
		return ids
	end
	local targetRosterState = {
		Ids = targetIds,
		IdGeneratorState = snapshot.IdGeneratorState,
		Frame = snapshot.Frame,
	}

	local rosterParticipant = {}
	function rosterParticipant:CaptureRollbackState()
		return { Ids = idsOf(currentById), IdGeneratorState = world.IdGenerator.LastId, Frame = world.CurrentFrame }
	end
	function rosterParticipant:ValidateRollbackState(state)
		if type(state) ~= "table" or not isDenseArray(state.Ids) then return false, "Roster IDs must be a dense array" end
		if type(state.IdGeneratorState) ~= "number" or state.IdGeneratorState < 0
			or state.IdGeneratorState % 1 ~= 0 or state.IdGeneratorState ~= state.IdGeneratorState
			or state.IdGeneratorState == math.huge then return false, "Invalid roster ID generator state" end
		if type(state.Frame) ~= "number" or state.Frame < 0 or state.Frame % 1 ~= 0 then return false, "Invalid roster frame" end
		local seen, previous = {}, nil
		for _, id in ipairs(state.Ids) do
			if (type(id) ~= "number" and type(id) ~= "string") or id == "" or seen[id]
				or (type(id) == "number" and (id ~= id or id == math.huge or id == -math.huge or id % 1 ~= 0)) then
				return false, "Invalid or duplicate roster entity ID"
			end
			if previous ~= nil and not idLess(previous, id) then return false, "Roster IDs are not canonical" end
			previous, seen[id] = id, true
		end
		return true
	end
	function rosterParticipant:PrepareRollbackRestore(state, context, role)
		local source = role == "Target" and context.TargetEntitiesById or context.CurrentEntitiesById
		local selected = {}
		for _, id in ipairs(state.Ids) do
			local entity = source[id]
			if not entity then return nil, "Roster entity object is missing for ID " .. tostring(id) end
			selected[id] = entity
		end
		return function()
			world.EntityRegistry:Clear()
			for id, entity in pairs(context.CurrentEntitiesById) do
				if selected[id] ~= entity then entity.World = nil end
			end
			for id, entity in pairs(context.TargetEntitiesById) do
				if selected[id] ~= entity then entity.World = nil end
			end
			for _, id in ipairs(state.Ids) do
				local entity = selected[id]
				entity.World = world
				world.EntityRegistry:Register(entity)
			end
			world.IdGenerator.LastId = state.IdGeneratorState
			world.CurrentFrame = state.Frame
		end
	end

	local providersParticipant = {}
	local providerKeys = {}
	for key in pairs(self.Providers) do table.insert(providerKeys, key) end
	table.sort(providerKeys)
	function providersParticipant:CaptureRollbackState(context)
		local states = {}
		for _, key in ipairs(providerKeys) do
			local provider = self.Schema.Providers[key]
			local state = provider:CaptureRollbackState(world)
			assert(type(state) == "table", "State provider " .. key .. " must capture a table")
			states[key] = Serializer.CloneSerializable(state, {
				MaxEntries = self.Schema.MaxSnapshotEntries, MaxDepth = self.Schema.MaxSnapshotDepth,
			})
		end
		return states
	end
	function providersParticipant:ValidateRollbackState(state)
		if type(state) ~= "table" then return false, "Provider aggregate must be a table" end
		for _, key in ipairs(providerKeys) do
			if state[key] == nil then return false, "Provider aggregate missing " .. key end
			local provider = self.Schema.Providers[key]
			local ok, accepted, detail = pcall(provider.ValidateRollbackState, provider, state[key], world)
			if not ok or accepted ~= true then return false, "Provider " .. key .. " rejected state: " .. tostring(ok and detail or accepted) end
		end
		for key in pairs(state) do
			if not self.Schema.Providers[key] then return false, "Unknown provider in aggregate: " .. tostring(key) end
		end
		return true
	end
	function providersParticipant:PrepareRollbackRestore(state, restoreContext, restoreRole)
		local commits = {}
		for _, key in ipairs(providerKeys) do
			local provider = self.Schema.Providers[key]
			local ok, commitOrError = pcall(provider.PrepareRollbackRestore, provider,
				Serializer.CloneSerializable(state[key]), world, restoreContext, restoreRole)
			if not ok or type(commitOrError) ~= "function" then
				return nil, "Provider " .. key .. " could not prepare: " .. tostring(commitOrError)
			end
			commits[key] = commitOrError
		end
		return function()
			for _, key in ipairs(providerKeys) do commits[key]() end
		end
	end
	providersParticipant.Schema = self

	local simulationParticipant = {}
	function simulationParticipant:CaptureRollbackState()
		local captureOk, state = pcall(simulation.CaptureState, simulation)
		if captureOk then return Serializer.CloneSerializable(state) end
		return simulation:CaptureRecoveryState()
	end
	function simulationParticipant:ValidateRollbackState(state)
		if type(state) == "table" and state.RecoveryVersion == 1 then
			return simulation:ValidateRecoveryState(state)
		end
		local ok, normalized = pcall(function()
			local SimulationState = require(script.Parent.Parent.Simulation.SimulationState)
			return SimulationState.new(state)
		end)
		if not ok then return false, tostring(normalized) end
		if type(normalized.Frame) ~= "number" or normalized.Frame < 0 then return false, "Invalid simulation frame" end
		return true
	end
	function simulationParticipant:PrepareRollbackRestore(state)
		local cloned = Serializer.CloneSerializable(state)
		return function()
			local restored, detail
			if cloned.RecoveryVersion == 1 then
				restored, detail = simulation:RestoreRecoveryState(cloned)
			else
				restored, detail = simulation:RestoreState(cloned)
			end
			assert(restored, "Simulation restore failed: " .. tostring(detail))
		end
	end

	local collisionParticipant = nil
	if world.CollisionWorld then
		collisionParticipant = {}
		function collisionParticipant:CaptureRollbackState()
			return Serializer.CloneSerializable(world.CollisionWorld:CaptureRollbackState(), {
				MaxEntries = self.Schema.MaxSnapshotEntries, MaxDepth = self.Schema.MaxSnapshotDepth,
			})
		end
		function collisionParticipant:ValidateRollbackState(state)
			if type(state) ~= "table" or state.Version ~= 1 then return false, "Invalid CollisionWorld snapshot" end
			if type(state.Frame) ~= "number" or state.Frame ~= state.Frame or state.Frame < 0
				or state.Frame == math.huge or state.Frame == -math.huge or state.Frame % 1 ~= 0 then
				return false, "Invalid CollisionWorld frame"
			end
			for _, name in ipairs({ "Hitboxes", "Hurtboxes", "AttackInstances", "ActivePairs" }) do
				if not isDenseArray(state[name]) then return false, "Invalid CollisionWorld " .. name end
			end
			if type(state.HitHistory) ~= "table" then return false, "Missing CollisionWorld HitHistory" end
			if world.CollisionWorld.AttackCatalog then
				local ok, detail = world.CollisionWorld.AttackCatalog:ValidateManifest(state.AttackCatalogManifest)
				if not ok then return false, "AttackCatalog mismatch: " .. tostring(detail) end
			elseif state.AttackCatalogManifest ~= nil then return false, "Snapshot requires AttackCatalog" end
			if world.CollisionWorld.TopologyCatalog then
				local ok, detail = world.CollisionWorld.TopologyCatalog:ValidateManifest(state.TopologyCatalogManifest)
				if not ok then return false, "TopologyCatalog mismatch: " .. tostring(detail) end
			elseif state.TopologyCatalogManifest ~= nil then return false, "Snapshot requires TopologyCatalog" end
			return true
		end
		function collisionParticipant:PrepareRollbackRestore(state, context, role)
			local entityMap = role == "Target" and context.TargetEntitiesById or context.CurrentEntitiesById
			local commit, detail = world.CollisionWorld:PrepareTopologyRebuild(state, entityMap)
			if type(commit) ~= "function" then return nil, detail end
			return commit
		end
		collisionParticipant.Schema = self
	end

	local coordinator = CombatRestoreCoordinator.new({
		MaxSnapshotEntries = self.MaxSnapshotEntries,
		MaxSnapshotDepth = self.MaxSnapshotDepth,
	})
	coordinator:Register("entities.roster.v1", rosterParticipant, 10)
	coordinator:Register("providers.aggregate.v1", providersParticipant, 20)
	coordinator:Register("simulation.v1", simulationParticipant, 30)
	if collisionParticipant then coordinator:Register("collision.topology.v1", collisionParticipant, 40) end
	local context = {
		World = world,
		TargetEntitiesById = stagedById,
		CurrentEntitiesById = currentById,
	}
	local transactionSnapshot = {
		Version = CombatRestoreCoordinator.Version,
		Participants = {
			["entities.roster.v1"] = targetRosterState,
			["providers.aggregate.v1"] = snapshot.Providers,
			["simulation.v1"] = snapshot.Simulation,
			["collision.topology.v1"] = snapshot.CollisionWorld,
		},
	}
	local transaction, prepareError = coordinator:Prepare(transactionSnapshot, context)
	if not transaction then
		for _, entity in pairs(stagedById) do pcall(entity.Destroy, entity) end
		return false, "Restore transaction preparation failed: " .. tostring(prepareError)
	end
	local committed, commitError = transaction:Commit()
	if not committed then
		for _, entity in pairs(stagedById) do pcall(entity.Destroy, entity) end
		return false, "Restore transaction failed: " .. tostring(commitError)
	end

	-- Old entities are retired only after all coordinated commits succeeded. Their Detach
	-- hooks must not publish irreversible effects; integrations should use frame-keyed events.
	for _, entity in ipairs(oldEntities) do
		if stagedById[entity.Id] ~= entity then pcall(entity.Destroy, entity) end
	end
	if world.RollbackResolver then
		world.RollbackResolver:RebindAfterWorldRestore(rollbackEntityIds)
	end
	if world.PredictionResolver then
		world.PredictionResolver:RebindAfterWorldRestore()
	end
	if world.HitstopResolver then world.HitstopResolver.Frame = snapshot.Frame end
	return true
end

return Schema
