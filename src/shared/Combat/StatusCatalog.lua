-- Registry of deterministic, versioned factories for rollback-compatible status types.
-- Factories must return a fresh inactive status and must not mutate the world or emit effects.
local Hitstun = require(script.Parent.Hitstun)
local Blockstun = require(script.Parent.Blockstun)

local StatusCatalog = {}
StatusCatalog.__index = StatusCatalog

local function validVersion(value)
	return (type(value) == "string" and value ~= "")
		or (type(value) == "number" and value == value and value >= 0
			and value < math.huge and value % 1 == 0)
end

local function typeLess(a, b)
	return a < b
end

function StatusCatalog.new(options)
	options = options or {}
	assert(type(options) == "table", "StatusCatalog.new expects an options table")
	local self = setmetatable({ Factories = {}, Versions = {}, Builtins = {}, Sealed = false }, StatusCatalog)
	if options.IncludeBuiltins ~= false then
		self:Register("Combat.Hitstun", 1, function()
			return Hitstun.new({ DurationFrames = 1 })
		end)
		self.Builtins["Combat.Hitstun"] = true
		self:Register("Combat.Blockstun", 1, function()
			return Blockstun.new({ DurationFrames = 1 })
		end)
		self.Builtins["Combat.Blockstun"] = true
	end
	return self
end

function StatusCatalog:Register(typeId, version, factory)
	assert(not self.Sealed, "StatusCatalog is sealed")
	assert(type(typeId) == "string" and typeId ~= "", "Status type ID must be a non-empty string")
	assert(validVersion(version), "Status type version must be a non-empty string or non-negative integer")
	assert(type(factory) == "function", "Status factory must be a function")
	assert(not self.Factories[typeId], "Status type already registered: " .. typeId)
	self.Factories[typeId] = factory
	self.Versions[typeId] = version
	return self
end

function StatusCatalog:Resolve(typeId, expectedVersion)
	local factory = self.Factories[typeId]
	if not factory then return nil, "Unknown status type: " .. tostring(typeId) end
	local version = self.Versions[typeId]
	if expectedVersion ~= nil and version ~= expectedVersion then
		return nil, "Status type version mismatch: " .. tostring(typeId)
	end
	return factory, version
end

function StatusCatalog:Create(typeId, expectedVersion, context)
	local factory, versionOrError = self:Resolve(typeId, expectedVersion)
	if not factory then return nil, versionOrError end
	local ok, status = pcall(factory, context)
	if not ok then return nil, "Status factory failed for " .. typeId .. ": " .. tostring(status) end
	if type(status) ~= "table" or status.RollbackTypeId ~= typeId
		or status.RollbackVersion ~= versionOrError then
		return nil, "Status factory returned an incompatible type/version: " .. typeId
	end
	if status.Active ~= false or status.Entity ~= nil then
		return nil, "Status factory must return a fresh inactive instance: " .. typeId
	end
	if not self.Builtins[typeId] and status.RollbackCustomStateContract ~= true then
		return nil, "Custom status must declare RollbackCustomStateContract: " .. typeId
	end
	return status
end

function StatusCatalog:IsBuiltin(typeId)
	return self.Builtins[typeId] == true
end

function StatusCatalog:CaptureManifest()
	local entries = {}
	for typeId, version in pairs(self.Versions) do
		entries[#entries + 1] = { TypeId = typeId, Version = version }
	end
	table.sort(entries, function(a, b) return typeLess(a.TypeId, b.TypeId) end)
	return { Version = 1, Entries = entries }
end

function StatusCatalog:ValidateManifest(manifest)
	if type(manifest) ~= "table" or getmetatable(manifest) ~= nil or manifest.Version ~= 1
		or type(manifest.Entries) ~= "table" then return false, "Invalid StatusCatalog manifest" end
	for key in pairs(manifest) do
		if key ~= "Version" and key ~= "Entries" then return false, "Unknown StatusCatalog manifest field" end
	end
	local count, maxIndex, seen, previous = 0, 0, {}, nil
	for key in pairs(manifest.Entries) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false, "Status manifest must be dense" end
		count += 1
		if key > maxIndex then maxIndex = key end
	end
	if count ~= maxIndex then return false, "Status manifest must be dense" end
	for _, entry in ipairs(manifest.Entries) do
		if type(entry) ~= "table" or getmetatable(entry) ~= nil or type(entry.TypeId) ~= "string"
			or entry.TypeId == "" or not validVersion(entry.Version) then return false, "Invalid status manifest entry" end
		for key in pairs(entry) do if key ~= "TypeId" and key ~= "Version" then return false, "Unknown status manifest entry field" end end
		if seen[entry.TypeId] or (previous and not typeLess(previous, entry.TypeId)) then
			return false, "Duplicate or non-canonical status manifest entry"
		end
		seen[entry.TypeId], previous = true, entry.TypeId
		local factory, reason = self:Resolve(entry.TypeId, entry.Version)
		if not factory then return false, reason end
	end
	local registered = 0
	for _ in pairs(self.Factories) do registered += 1 end
	if registered ~= #manifest.Entries then return false, "Status catalog size differs from snapshot" end
	return true
end

function StatusCatalog:Seal()
	self.Sealed = true
	return self
end

return StatusCatalog
