-- Versioned, side-effect-free factories for rebuilding collision topology from snapshots.
-- Factories must return fresh Hitbox/Hurtbox objects and must not mutate World or CollisionWorld.
local CollisionTopologyCatalog = {}
CollisionTopologyCatalog.__index = CollisionTopologyCatalog

local function validId(value)
 return type(value) == "string" and value ~= ""
end
local function validVersion(value)
 return (type(value) == "string" and value ~= "")
  or (type(value) == "number" and value == value and value > -math.huge and value < math.huge and value >= 0 and value % 1 == 0)
end
local function idLess(a, b) return a < b end

function CollisionTopologyCatalog.new()
 return setmetatable({ Definitions = {}, Versions = {}, Sealed = false }, CollisionTopologyCatalog)
end

function CollisionTopologyCatalog:Register(id, version, factory)
 assert(not self.Sealed, "CollisionTopologyCatalog is sealed")
 assert(validId(id), "Topology definition ID must be a non-empty string")
 assert(validVersion(version), "Topology definition version must be a non-negative integer or non-empty string")
 assert(type(factory) == "function", "Topology factory must be a function")
 assert(self.Definitions[id] == nil, "Topology definition already registered: " .. id)
 self.Definitions[id], self.Versions[id] = factory, version
 return self
end

function CollisionTopologyCatalog:Resolve(id, version)
 local factory = self.Definitions[id]
 if not factory then return nil, "Unknown topology definition: " .. tostring(id) end
 local actual = self.Versions[id]
 if version ~= nil and version ~= actual then return nil, "Topology definition version mismatch: " .. tostring(id) end
 return factory, actual
end

function CollisionTopologyCatalog:CaptureManifest()
 local entries = {}
 for id, version in pairs(self.Versions) do table.insert(entries, { Id = id, Version = version }) end
 table.sort(entries, function(a, b) return idLess(a.Id, b.Id) end)
 return { Version = 1, Entries = entries }
end

function CollisionTopologyCatalog:ValidateManifest(manifest)
 if type(manifest) ~= "table" or getmetatable(manifest) ~= nil or manifest.Version ~= 1 or type(manifest.Entries) ~= "table" then
  return false, "Invalid topology catalog manifest"
 end
 local count, maxIndex = 0, 0
 for key in pairs(manifest.Entries) do
  if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false, "Topology manifest entries must be a dense array" end
  count += 1; if key > maxIndex then maxIndex = key end
 end
 if count ~= maxIndex then return false, "Topology manifest entries must be a dense array" end
 local previous, seen = nil, {}
 for _, entry in ipairs(manifest.Entries) do
  if type(entry) ~= "table" or not validId(entry.Id) or not validVersion(entry.Version) then return false, "Invalid topology manifest entry" end
  if seen[entry.Id] then return false, "Duplicate topology definition ID" end
  if previous and not idLess(previous, entry.Id) then return false, "Topology manifest is not canonically sorted" end
  seen[entry.Id], previous = true, entry.Id
  local _, reason = self:Resolve(entry.Id, entry.Version)
  if not self:Resolve(entry.Id, entry.Version) then return false, reason end
 end
 local registered = 0; for _ in pairs(self.Definitions) do registered += 1 end
 if registered ~= #manifest.Entries then return false, "Topology catalog size differs from snapshot" end
 return true
end

function CollisionTopologyCatalog:CreateRegion(saved, owner)
 assert(type(saved) == "table", "CreateRegion requires a saved region descriptor")
 local factory, versionOrError = self:Resolve(saved.TopologyDefinitionId, saved.TopologyDefinitionVersion)
 if not factory then return nil, versionOrError end
 local ok, regionOrError = pcall(factory, saved, owner)
 if not ok then return nil, "Topology factory failed: " .. tostring(regionOrError) end
 local region = regionOrError
 local expectedType = saved.CombatRegionType
 if type(region) ~= "table" or region.CombatRegionType ~= expectedType then
  return nil, "Topology factory returned the wrong region type for ID " .. tostring(saved.Id)
 end
 if region.Id ~= saved.Id or region.Owner ~= owner then return nil, "Topology factory did not preserve region ID/owner" end
 if region.TopologyDefinitionId ~= saved.TopologyDefinitionId or region.TopologyDefinitionVersion ~= saved.TopologyDefinitionVersion then
  return nil, "Topology factory definition metadata mismatch for ID " .. tostring(saved.Id)
 end
 if region.Shape ~= saved.Shape then return nil, "Topology factory shape mismatch for ID " .. tostring(saved.Id) end
 return region
end

function CollisionTopologyCatalog:Seal()
 self.Sealed = true
 return self
end
return CollisionTopologyCatalog
