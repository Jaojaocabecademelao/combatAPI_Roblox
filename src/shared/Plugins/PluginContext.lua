local Context = {}
Context.__index = Context
function Context.new(resolver, plugin)
	local self=setmetatable({ _resolver=resolver, _plugin=plugin, _valid=true, _resources={} }, Context)
	self._registryView=table.freeze({
		Get=function(_,id) return self:IsValid() and self._resolver.Registry:Get(id) or nil end,
		Has=function(_,id) return self:IsValid() and self._resolver.Registry:Has(id) or false end,
		List=function() return self:IsValid() and self._resolver.Registry:List() or {} end,
		HasCapability=function(_,id) return self:IsValid() and self._resolver.Registry:HasCapability(id) or false end,
		GetCapability=function(_,id) return self:IsValid() and self._resolver.Registry:GetCapability(id) or nil end,
		ListCapabilities=function() return self:IsValid() and self._resolver.Registry:ListCapabilities() or {} end,
	})
	return self
end
function Context:IsValid() return self._valid and self._resolver ~= nil end
function Context:GetWorld() return self:IsValid() and self._resolver.World or nil end
function Context:GetAPI() return self:IsValid() and self._resolver.World.APIContext or nil end
function Context:GetEventBus() return self:IsValid() and self._resolver.World.EventBus or nil end
function Context:GetRegistry() return self:IsValid() and self._registryView or nil end
function Context:GetCapability(id) return self:IsValid() and self._resolver.Registry:GetCapability(id) or nil end
function Context:RegisterCapability(id, implementation, version)
	if not self:IsValid() then return nil, "InvalidContext" end
	local capability, code = self._resolver:_registerCapability(self._plugin, id, implementation, version)
	if capability then table.insert(self._resources, { Kind="Capability", Id=id }) end
	return capability, code
end
function Context:Subscribe(eventType, callback, options)
	if not self:IsValid() then return nil, "InvalidContext" end
	if type(eventType)~="string" or eventType=="" or type(callback)~="function" then return nil,"InvalidArgument" end
	local userCallback = callback
	local subscription, err = self._resolver.World.EventBus:Subscribe(eventType, function(event, api)
		if not self:IsValid() then return end
		local ok, failure = pcall(userCallback, event, api, self)
		if not ok then self._resolver:_failRuntime(self._plugin, failure) end
	end, options)
	if subscription then table.insert(self._resources, { Kind="Subscription", Value=subscription }) end
	return subscription, err
end
function Context:Register(kind, id, implementation, version)
	if kind ~= "Capability" then return nil, "UnsupportedExtensionKind" end
	return self:RegisterCapability(id, implementation, version)
end
function Context:_invalidate()
	if not self._valid then return false end
	self._valid=false
	for index=#self._resources,1,-1 do
		local resource=self._resources[index]
		if resource.Kind == "Subscription" then resource.Value:Disconnect()
		elseif resource.Kind == "Capability" then self._resolver:_unregisterCapability(self._plugin, resource.Id) end
	end
	table.clear(self._resources); self._resolver=nil; self._plugin=nil; self._registryView=nil; return true
end
return Context
