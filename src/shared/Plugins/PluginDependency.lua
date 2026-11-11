local Dependency = {}
Dependency.__index = Dependency
function Dependency.new(value)
	if type(value) == "string" then value = { PluginId = value } end
	assert(type(value) == "table" and type(value.PluginId) == "string" and value.PluginId ~= "", "Invalid plugin dependency")
	assert(value.MinVersion == nil or (type(value.MinVersion) == "string" and value.MinVersion ~= ""), "Invalid minimum dependency version")
	assert(value.MinVersion == nil or value.MinVersion:match("^%d+%.%d+%.%d+$") ~= nil, "Minimum dependency version must be numeric major.minor.patch")
	assert(value.Optional == nil or type(value.Optional) == "boolean", "Optional must be boolean")
	return table.freeze(setmetatable({ PluginId = value.PluginId, MinVersion = value.MinVersion, Optional = value.Optional == true }, Dependency))
end
return Dependency
