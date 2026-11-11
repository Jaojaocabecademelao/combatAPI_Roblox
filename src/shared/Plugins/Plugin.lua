local Profile = require(script.Parent.PluginProfile)
local Plugin = {}
Plugin.__index = Plugin
function Plugin.new(profile, implementation)
	if getmetatable(profile) ~= Profile then profile = Profile.new(profile) end
	implementation = implementation or {}
	assert(type(implementation) == "table", "Plugin implementation must be a table")
	for _, method in ipairs({ "Initialize", "Start", "Stop" }) do
		assert(implementation[method] == nil or type(implementation[method]) == "function", method .. " must be a function")
	end
	return setmetatable({ Profile=profile, Id=profile.Id, Name=profile.Name, Version=profile.Version,
		Scope=profile.Scope, State="Registered", Implementation=implementation, Context=nil, Failure=nil }, Plugin)
end
return Plugin
