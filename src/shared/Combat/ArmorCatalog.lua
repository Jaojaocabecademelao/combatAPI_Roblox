-- Versioned registry for ArmorProfile definitions. Callback behavior is represented by
-- an explicit version; closures themselves are never serialized.
local ArmorCatalog = {}
ArmorCatalog.__index = ArmorCatalog

local function validId(value)
	return (type(value) == "string" and value ~= "")
		or (type(value) == "number" and value == value and value > -math.huge
			and value < math.huge and value % 1 == 0)
end

local function validVersion(value)
	return (type(value) == "string" and value ~= "")
		or (type(value) == "number" and value == value and value >= 0
			and value < math.huge and value % 1 == 0)
end

local function idLess(a, b)
	if type(a) ~= type(b) then return type(a) < type(b) end
	return a < b
end

local function consequences(profile)
	local result = {}
	for key, value in pairs(profile.Consequences) do result[key] = value end
	return result
end

local function sameMap(a, b)
	for key, value in pairs(a) do if b[key] ~= value then return false end end
	for key, value in pairs(b) do if a[key] ~= value then return false end end
	return true
end

function ArmorCatalog.new()
	return setmetatable({ Profiles = {}, Versions = {}, Sealed = false }, ArmorCatalog)
end

function ArmorCatalog:Register(profile, version)
	assert(not self.Sealed, "ArmorCatalog is sealed")
	assert(type(profile) == "table" and validId(profile.Id), "ArmorCatalog requires an ArmorProfile with a stable ID")
	assert(validVersion(version), "Armor profile version must be a non-empty string or non-negative integer")
	assert(not self.Profiles[profile.Id], "Armor profile ID already registered: " .. tostring(profile.Id))
	self.Profiles[profile.Id] = profile
	self.Versions[profile.Id] = version
	return profile
end

function ArmorCatalog:Resolve(id, expectedVersion)
	local profile = self.Profiles[id]
	if not profile then return nil, "Unknown armor profile: " .. tostring(id) end
	local version = self.Versions[id]
	if expectedVersion ~= nil and version ~= expectedVersion then
		return nil, "Armor profile version mismatch: " .. tostring(id)
	end
	return profile, version
end

function ArmorCatalog:CaptureManifest()
	local entries = {}
	for id, profile in pairs(self.Profiles) do
		table.insert(entries, {
			Id = id, Version = self.Versions[id], Name = profile.Name, Kind = profile.Kind,
			DurationFrames = profile.DurationFrames, Priority = profile.Priority,
			Consequences = consequences(profile), HasCondition = profile.Condition ~= nil,
		})
	end
	table.sort(entries, function(a, b) return idLess(a.Id, b.Id) end)
	return { Version = 1, Entries = entries }
end

function ArmorCatalog:ValidateManifest(manifest)
	if type(manifest) ~= "table" or getmetatable(manifest) ~= nil or manifest.Version ~= 1
		or type(manifest.Entries) ~= "table" then return false, "Invalid ArmorCatalog manifest" end
	local count, maxIndex = 0, 0
	for key in pairs(manifest.Entries) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false, "Armor manifest entries must be dense" end
		count += 1; if key > maxIndex then maxIndex = key end
	end
	if count ~= maxIndex then return false, "Armor manifest entries must be dense" end
	local seen, previous = {}, nil
	for _, entry in ipairs(manifest.Entries) do
		if type(entry) ~= "table" or not validId(entry.Id) or not validVersion(entry.Version) then
			return false, "Invalid armor manifest entry"
		end
		if seen[entry.Id] or (previous ~= nil and not idLess(previous, entry.Id)) then
			return false, "Duplicate or non-canonical armor manifest entry"
		end
		seen[entry.Id], previous = true, entry.Id
		local profile, reason = self:Resolve(entry.Id, entry.Version)
		if not profile then return false, reason end
		if profile.Name ~= entry.Name or profile.Kind ~= entry.Kind
			or profile.DurationFrames ~= entry.DurationFrames or profile.Priority ~= entry.Priority
			or (profile.Condition ~= nil) ~= entry.HasCondition
			or type(entry.Consequences) ~= "table"
			or not sameMap(consequences(profile), entry.Consequences) then
			return false, "Armor profile definition mismatch: " .. tostring(entry.Id)
		end
	end
	local registered = 0
	for _ in pairs(self.Profiles) do registered += 1 end
	if registered ~= #manifest.Entries then return false, "Armor catalog size differs from snapshot" end
	return true
end

function ArmorCatalog:Seal()
	self.Sealed = true
	return self
end

return ArmorCatalog
