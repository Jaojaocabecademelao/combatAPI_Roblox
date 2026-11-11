-- Versioned registry of immutable Attack definitions.
local Serializer = require(script.Parent.Parent.Simulation.StateSerializer)
-- The version is an explicit gameplay contract: increment it whenever scalar data,
-- policy, or callback behavior changes. Functions/closures are deliberately not serialized.
local AttackCatalog = {}
AttackCatalog.__index = AttackCatalog
AttackCatalog.ManifestVersion = 2

local function validId(id)
	return (type(id) == "string" and id ~= "")
		or (type(id) == "number" and id == id and id ~= math.huge and id ~= -math.huge and id % 1 == 0)
end

local function validVersion(version)
	return (type(version) == "string" and version ~= "")
		or (type(version) == "number" and version == version and version ~= math.huge
			and version ~= -math.huge and version >= 0 and version % 1 == 0)
end

local function idLess(left, right)
	if type(left) ~= type(right) then return type(left) < type(right) end
	return left < right
end

local function damageManifest(value)
	if value == nil then return nil end
	if type(value) == "number" then return { Amount = value, Type = "Normal" } end
	assert(type(value) == "table" and type(value.Amount) == "number",
		"Attack damage must expose a numeric Amount")
	return { Amount = value.Amount, Type = value.Type or "Normal" }
end

local function sameDamage(left, right)
	if left == nil or right == nil then return left == right end
	return type(left) == "table" and type(right) == "table"
		and left.Amount == right.Amount and left.Type == right.Type
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

function AttackCatalog.new()
	return setmetatable({ Definitions = {}, Versions = {}, CustomDataCanonical = {}, Sealed = false }, AttackCatalog)
end

function AttackCatalog:Register(attack, version)
	assert(not self.Sealed, "AttackCatalog is sealed")
	assert(type(attack) == "table" and validId(attack.Id), "Register requires an Attack with a stable ID")
	assert(validVersion(version), "Attack definition version must be a non-empty string or non-negative integer")
	assert(not self.Definitions[attack.Id], "Attack definition ID already registered: " .. tostring(attack.Id))
	assert(type(attack.CanHit) == "function" or attack.CanHit == nil, "Attack CanHit must be a function or nil")
	local customData = attack.OffensiveProperties and attack.OffensiveProperties.CustomData
	local customDataCanonical
	if customData ~= nil then
		assert(type(customData) == "table" and getmetatable(customData) == nil,
			"AttackCatalog CustomData must be a plain serializable table")
		local ok, clone = pcall(Serializer.CloneSerializable, customData, { MaxEntries = 256, MaxDepth = 8 })
		assert(ok, "AttackCatalog CustomData is invalid: " .. tostring(clone))
		customDataCanonical = Serializer.Serialize(clone, { MaxEntries = 256, MaxDepth = 8 })
	end
	self.Definitions[attack.Id] = attack
	self.Versions[attack.Id] = version
	self.CustomDataCanonical[attack.Id] = customDataCanonical
	return attack
end

function AttackCatalog:Get(id)
	return self.Definitions[id]
end

function AttackCatalog:GetVersion(id)
	return self.Versions[id]
end

function AttackCatalog:Resolve(id, expectedVersion)
	local attack = self.Definitions[id]
	if not attack then return nil, "Unknown attack definition: " .. tostring(id) end
	local actualVersion = self.Versions[id]
	if expectedVersion ~= nil and expectedVersion ~= actualVersion then
		return nil, "Attack definition version mismatch for " .. tostring(id)
	end
	return attack, actualVersion
end

function AttackCatalog:CaptureManifest()
	local entries = {}
	for id, attack in pairs(self.Definitions) do
		local properties = attack.OffensiveProperties or {}
		table.insert(entries, {
			Id = id,
			Version = self.Versions[id],
			Priority = attack.Priority or 0,
			CanClash = attack.CanClash == true,
			HitPolicy = attack.HitPolicy,
			HitScope = attack.HitScope,
			Damage = damageManifest(properties.Damage),
			Hitstun = properties.Hitstun,
			HasCanHitCallback = attack.CanHit ~= nil,
			CustomDataCanonical = self.CustomDataCanonical[id],
		})
	end
	table.sort(entries, function(a, b) return idLess(a.Id, b.Id) end)
	return { Version = AttackCatalog.ManifestVersion, Entries = entries }
end

function AttackCatalog:ValidateManifest(manifest)
	if type(manifest) ~= "table" or getmetatable(manifest) ~= nil or (manifest.Version ~= 1 and manifest.Version ~= AttackCatalog.ManifestVersion)
		or not isDenseArray(manifest.Entries) then
		return false, "Invalid AttackCatalog manifest or non-dense entries"
	end
	if manifest.Version == 1 then
		for _, canonical in pairs(self.CustomDataCanonical) do
			if canonical ~= nil then return false, "AttackCatalog manifest v1 cannot verify CustomData definitions" end
		end
	end
	local seen, previous = {}, nil
	for _, entry in ipairs(manifest.Entries) do
		if type(entry) ~= "table" or not validId(entry.Id) or not validVersion(entry.Version) then
			return false, "Invalid attack manifest entry"
		end
		if seen[entry.Id] then return false, "Duplicate attack manifest ID" end
		if previous ~= nil and not idLess(previous, entry.Id) then return false, "Attack manifest is not canonically sorted" end
		seen[entry.Id], previous = true, entry.Id
		local attack, reason = self:Resolve(entry.Id, entry.Version)
		if not attack then return false, reason end
		local properties = attack.OffensiveProperties or {}
		if (attack.Priority or 0) ~= entry.Priority
			or (attack.CanClash == true) ~= entry.CanClash
			or attack.HitPolicy ~= entry.HitPolicy
			or attack.HitScope ~= entry.HitScope
			or not sameDamage(damageManifest(properties.Damage), entry.Damage)
			or properties.Hitstun ~= entry.Hitstun
			or (attack.CanHit ~= nil) ~= entry.HasCanHitCallback
				or (manifest.Version == AttackCatalog.ManifestVersion and entry.CustomDataCanonical ~= self.CustomDataCanonical[entry.Id]) then
			return false, "Attack definition manifest mismatch for " .. tostring(entry.Id)
		end
	end
	local registeredCount = 0
	for _ in pairs(self.Definitions) do registeredCount += 1 end
	if registeredCount ~= #manifest.Entries then return false, "Attack catalog size differs from snapshot manifest" end
	return true
end

function AttackCatalog:Seal()
	self.Sealed = true
	return self
end

return AttackCatalog
