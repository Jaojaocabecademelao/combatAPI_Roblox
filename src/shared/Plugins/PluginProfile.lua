local Dependency = require(script.Parent.PluginDependency)
local PluginVersion = require(script.Parent.PluginVersion)
local Profile = {}
Profile.__index = Profile
Profile.Scope = table.freeze({ Gameplay = "Gameplay", Presentation = "Presentation" })
function Profile.new(data)
	assert(type(data) == "table", "PluginProfile.new() expects a table")
	assert(type(data.Id) == "string" and data.Id:match("^[%w_.%-]+$") ~= nil, "Plugin Id is invalid")
	assert(type(data.Name) == "string" and data.Name ~= "", "Plugin Name is required")
	assert(type(data.Version) == "string" and PluginVersion.isValid(data.Version), "Plugin Version must be numeric major.minor.patch")
	assert(data.Priority == nil or (type(data.Priority) == "number" and data.Priority == data.Priority and math.abs(data.Priority) < math.huge), "Plugin Priority must be finite")
	assert(data.AutoStart == nil or type(data.AutoStart) == "boolean", "AutoStart must be boolean")
	local scope = data.Scope or Profile.Scope.Gameplay
	assert(scope == Profile.Scope.Gameplay or scope == Profile.Scope.Presentation,
		"Plugin Scope must be Gameplay or Presentation")
	local dependencies, capabilities, seen = {}, {}, {}
	for _, dependency in ipairs(data.Dependencies or {}) do
		local normalized = Dependency.new(dependency); assert(not seen[normalized.PluginId], "Duplicate plugin dependency")
		seen[normalized.PluginId] = true; table.insert(dependencies, normalized)
	end
	local seenCapabilities={}
	for _, capability in ipairs(data.Capabilities or {}) do
		assert(type(capability) == "string" and capability ~= "", "Capability IDs must be non-empty strings")
		assert(not seenCapabilities[capability], "Duplicate plugin capability declaration")
		seenCapabilities[capability]=true
		table.insert(capabilities, capability)
	end
	table.sort(dependencies, function(a,b) return a.PluginId < b.PluginId end); table.sort(capabilities)
	return table.freeze(setmetatable({ Id=data.Id, Name=data.Name, Version=data.Version, Dependencies=table.freeze(dependencies),
		Capabilities=table.freeze(capabilities), AutoStart=data.AutoStart == true, Priority=data.Priority or 0,
		Scope=scope }, Profile))
end
return Profile
