local Capability = {}
Capability.__index = Capability
function Capability.new(data)
	assert(type(data) == "table" and type(data.Id) == "string" and data.Id ~= "", "Capability Id is required")
	assert(data.Version == nil or type(data.Version) == "string", "Capability Version must be a string")
	return table.freeze(setmetatable({ Id = data.Id, Version = data.Version or "1.0.0", Implementation = data.Implementation,
		OwnerPluginId = data.OwnerPluginId }, Capability))
end
return Capability
