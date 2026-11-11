local Registry = {}
Registry.__index = Registry
function Registry.new(world)
	return setmetatable({ World=world, Plugins={}, Capabilities={}, Destroyed=false }, Registry)
end
function Registry:Get(id) return self.Plugins[id] end
function Registry:Has(id) return self.Plugins[id] ~= nil end
function Registry:List()
	local result={}; for _, plugin in pairs(self.Plugins) do table.insert(result, plugin) end
	table.sort(result, function(a,b) return a.Id < b.Id end); return result
end
function Registry:HasCapability(id) return self.Capabilities[id] ~= nil end
function Registry:GetCapability(id) return self.Capabilities[id] end
function Registry:ListCapabilities()
	local result={}; for _, capability in pairs(self.Capabilities) do table.insert(result, capability) end
	table.sort(result, function(a,b) return a.Id < b.Id end); return result
end
return Registry
