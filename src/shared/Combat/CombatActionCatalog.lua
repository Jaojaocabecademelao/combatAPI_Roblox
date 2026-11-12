local Definition = require(script.Parent.CombatActionDefinition)
local Serializer = require(script.Parent.Parent.Simulation.StateSerializer)

local Catalog = {}
Catalog.__index = Catalog
Catalog.Version = 2

local function validId(id)
	return (type(id) == "string" and id ~= "")
		or (type(id) == "number" and id == id and id > -math.huge and id < math.huge
			and id % 1 == 0)
end

local function validVersion(version)
	return type(version) == "number" and version == version and version >= 1
		and version < math.huge and version % 1 == 0
end

local function idLess(left, right)
	if type(left) ~= type(right) then return type(left) < type(right) end
	return left < right
end

local function definitionData(definition)
	local data = {
		Id = definition.Id,
		DefinitionVersion = definition.Version,
		StartupFrames = definition.StartupFrames,
		ActiveFrames = definition.ActiveFrames,
		RecoveryFrames = definition.RecoveryFrames,
		DurationModel = definition.DurationModel,
		Cancelable = definition.Cancelable,
		Tags = table.clone(definition.Tags),
		Requirements = {
			Resources = Serializer.CloneSerializable(definition.Requirements.Resources),
			RequiredStatusTags = table.clone(definition.Requirements.RequiredStatusTags),
			ForbiddenStatusTags = table.clone(definition.Requirements.ForbiddenStatusTags),
			MovementStates = table.clone(definition.Requirements.MovementStates),
		},
		Costs = { Resources = Serializer.CloneSerializable(definition.Costs.Resources) },
	}
	if #definition.GameplayEvents > 0 then
		data.GameplayEvents = {}
		for index, event in ipairs(definition.GameplayEvents) do
			data.GameplayEvents[index] = {
				FrameOffset = event.FrameOffset,
				Type = event.Type,
				Parameters = Serializer.CloneSerializable(event.Parameters),
			}
		end
	end
	return data
end

function Catalog.new()
	return setmetatable({
		Definitions = {},
		Versions = {},
		Migrations = {},
		Sealed = false,
	}, Catalog)
end

function Catalog:Register(definition, contentVersion)
	assert(not self.Sealed, "CombatActionCatalog is sealed")
	assert(type(definition) == "table" and definition.Version == Definition.Version
		and validId(definition.Id), "Register requires a valid CombatActionDefinition")
	assert(validVersion(contentVersion), "Action content version must be a positive integer")
	assert(self.Definitions[definition.Id] == nil,
		"Action definition ID already registered: " .. tostring(definition.Id))
	self.Definitions[definition.Id] = definition
	self.Versions[definition.Id] = contentVersion
	return definition
end

function Catalog:RegisterMigration(actionId, fromVersion, toVersion, migrate)
	assert(not self.Sealed, "CombatActionCatalog is sealed")
	assert(validId(actionId), "Action migration requires a stable action ID")
	assert(validVersion(fromVersion) and validVersion(toVersion) and toVersion > fromVersion,
		"Action migration versions must be positive integers and move forward")
	assert(type(migrate) == "function", "Action migration must be a function")
	local migrations = self.Migrations[actionId]
	if not migrations then
		migrations = {}
		self.Migrations[actionId] = migrations
	end
	assert(migrations[fromVersion] == nil,
		"Action migration already registered from version " .. tostring(fromVersion))
	migrations[fromVersion] = { ToVersion = toVersion, Migrate = migrate }
	return self
end

function Catalog:Get(id)
	return self.Definitions[id]
end

function Catalog:GetVersion(id)
	return self.Versions[id]
end

function Catalog:Resolve(id, expectedVersion)
	local definition = self.Definitions[id]
	if not definition then return nil, "Unknown action definition: " .. tostring(id) end
	local actualVersion = self.Versions[id]
	if expectedVersion ~= nil and expectedVersion ~= actualVersion then
		return nil, "Action definition version mismatch for " .. tostring(id)
	end
	return definition, actualVersion
end

function Catalog:GetDefinitions()
	local definitions = {}
	for _, definition in pairs(self.Definitions) do
		table.insert(definitions, definition)
	end
	table.sort(definitions, function(left, right) return idLess(left.Id, right.Id) end)
	return definitions
end

function Catalog:MigrateDefinitionData(actionId, fromVersion, toVersion, data)
	if not validId(actionId) or not validVersion(fromVersion) or not validVersion(toVersion)
		or toVersion < fromVersion or type(data) ~= "table" then
		return nil, "InvalidActionMigrationRequest"
	end
	local ok, migrated = pcall(Serializer.CloneSerializable, data)
	if not ok then return nil, tostring(migrated) end
	if migrated.Id ~= actionId then return nil, "ActionMigrationIdMismatch" end
	local migrations = self.Migrations[actionId] or {}
	local version = fromVersion
	while version < toVersion do
		local migration = migrations[version]
		if not migration then
			return nil, "MissingActionMigrationFromVersion:" .. tostring(version)
		end
		if migration.ToVersion > toVersion then
			return nil, "ActionMigrationOvershootsTargetVersion"
		end
		local success, result = pcall(migration.Migrate, Serializer.CloneSerializable(migrated))
		if not success then return nil, "ActionMigrationFailed:" .. tostring(result) end
		if type(result) ~= "table" or result.Id ~= actionId then
			return nil, "ActionMigrationReturnedInvalidDefinition"
		end
		local valid, cloned = pcall(Serializer.CloneSerializable, result)
		if not valid then return nil, "ActionMigrationReturnedInvalidData:" .. tostring(cloned) end
		migrated = cloned
		version = migration.ToVersion
	end
	if version ~= toVersion then return nil, "ActionMigrationDidNotReachTargetVersion" end
	local valid, reason = pcall(Definition.new, migrated)
	if not valid then return nil, "MigratedActionDefinitionIsInvalid:" .. tostring(reason) end
	return migrated
end

function Catalog:CaptureManifest()
	local entries = {}
	for id, definition in pairs(self.Definitions) do
		table.insert(entries, {
			Id = id,
			ContentVersion = self.Versions[id],
			Definition = definitionData(definition),
		})
	end
	table.sort(entries, function(left, right) return idLess(left.Id, right.Id) end)
	return { Version = Catalog.Version, Entries = entries }
end

function Catalog:ValidateManifest(manifest)
	if type(manifest) ~= "table" or getmetatable(manifest) ~= nil
		or (manifest.Version ~= 1 and manifest.Version ~= Catalog.Version)
		or type(manifest.Entries) ~= "table" then
		return false, "Invalid CombatActionCatalog manifest"
	end
	if manifest.Version == 1 then
		for _, definition in pairs(self.Definitions) do
			if #definition.GameplayEvents > 0 then
				return false, "Legacy CombatActionCatalog manifest cannot validate definitions with gameplay events"
			end
		end
	end
	local entries = manifest.Entries
	local count, maxIndex = 0, 0
	for key in pairs(entries) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return false, "CombatActionCatalog manifest entries must be a dense array"
		end
		count += 1
		if key > maxIndex then maxIndex = key end
	end
	if count ~= maxIndex then return false, "CombatActionCatalog manifest entries must be a dense array" end
	local expected = self:CaptureManifest()
	if manifest.Version == 1 then
		expected.Version = 1
	end
	local okActual, actualText = pcall(Serializer.Serialize, manifest)
	local okExpected, expectedText = pcall(Serializer.Serialize, expected)
	if not okActual or not okExpected then return false, "CombatActionCatalog manifest is not serializable" end
	if actualText ~= expectedText then
		return false, "CombatActionCatalog content differs from the registered manifest"
	end
	return true
end

function Catalog:Seal()
	self.Sealed = true
	return self
end

return Catalog
