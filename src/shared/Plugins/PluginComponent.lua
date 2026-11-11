-- Runtime-local bookkeeping for a Plugin; unlike Core Component this is not attached to an Entity.
local PluginComponent = {}
PluginComponent.__index = PluginComponent
function PluginComponent.new(plugin)
	assert(type(plugin) == "table" and plugin.Id ~= nil, "PluginComponent requires a Plugin")
	return setmetatable({ Plugin=plugin, State=plugin.State, Resources={} }, PluginComponent)
end
function PluginComponent:Destroy()
	for _, resource in ipairs(self.Resources) do
		if type(resource.Disconnect) == "function" then pcall(resource.Disconnect, resource)
		elseif type(resource.Destroy) == "function" then pcall(resource.Destroy, resource) end
	end
	table.clear(self.Resources); self.Plugin=nil; self.State="Stopped"
end
return PluginComponent
