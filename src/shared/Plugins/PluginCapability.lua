local Capability = {}
Capability.__index = Capability
local PluginVersion = require(script.Parent.PluginVersion)
function Capability.new(data)
	assert(type(data) == "table" and type(data.Id) == "string" and data.Id ~= "", "Capability Id is required")
	local version = data.Version
	if version == nil then version = "1.0.0" end
	assert(type(version) == "string" and PluginVersion.isValid(version),
		"Capability Version must be numeric major.minor.patch")
	assert(type(data.OwnerPluginId) == "string" and data.OwnerPluginId ~= "", "Capability OwnerPluginId is required")
	return table.freeze(setmetatable({ Id = data.Id, Version = version, Implementation = data.Implementation,
		OwnerPluginId = data.OwnerPluginId }, Capability))
end
return Capability
