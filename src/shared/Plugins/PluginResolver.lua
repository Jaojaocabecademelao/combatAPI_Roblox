local Plugin = require(script.Parent.Plugin)
local Profile = require(script.Parent.PluginProfile)
local Registry = require(script.Parent.PluginRegistry)
local Context = require(script.Parent.PluginContext)
local Component = require(script.Parent.PluginComponent)
local Event = require(script.Parent.PluginEvent)
local Result = require(script.Parent.PluginResult)
local State = require(script.Parent.PluginState)
local PluginVersion = require(script.Parent.PluginVersion)

local Resolver = {}
Resolver.__index = Resolver
local function result(ok, code, plugin, value, details) return Result.new(ok, code, plugin and plugin.Id, value, details) end
local function pluginOrder(a,b)
	if a.Profile.Priority ~= b.Profile.Priority then return a.Profile.Priority > b.Profile.Priority end
	return a.Id < b.Id
end
function Resolver.new(world)
	return setmetatable({ World=world, Registry=Registry.new(world), Events={}, Results={}, Destroyed=false,
		Sequence=0, Components={} }, Resolver)
end
function Resolver:_emit(kind, plugin, details)
	self.Sequence += 1
	local payload={ Type=kind, PluginId=plugin and plugin.Id, Name=plugin and plugin.Name,
		Version=plugin and plugin.Version, State=plugin and plugin.State, Frame=self.World and self.World.CurrentFrame or 0,
		Sequence=self.Sequence, Details=details }
	table.insert(self.Events, Event.new(payload))
	if self.World and self.World.EventBus and not self.World.Destroyed then
		self.World.EventSequence += 1
		self.World.EventBus:Dispatch(kind, payload, { SimulationFrame=payload.Frame, SourceSystem="Plugin",
			Sequence=self.World.EventSequence, ExecutionMode=self.World:GetEventExecutionMode(), APIContext=self.World.APIContext })
	end
	return payload
end
function Resolver:_record(value) table.insert(self.Results,value); return value end
function Resolver:GetEvents() return table.clone(self.Events) end
function Resolver:GetResults() return table.clone(self.Results) end
function Resolver:GetPlugin(id) return self.Registry:Get(type(id)=="table" and id.Id or id) end
function Resolver:HasPlugin(id) return self.Registry:Has(type(id)=="table" and id.Id or id) end
function Resolver:ListPlugins() return self.Registry:List() end
function Resolver:ListPluginsByScope(scope)
	if scope ~= Profile.Scope.Gameplay and scope ~= Profile.Scope.Presentation then
		return {}
	end
	local plugins = {}
	for _, plugin in ipairs(self.Registry:List()) do
		if plugin.Scope == scope then table.insert(plugins, plugin) end
	end
	return plugins
end
function Resolver:GetPluginState(id) local p=self:GetPlugin(id); return p and p.State or nil end
function Resolver:GetPluginProfile(id) local p=self:GetPlugin(id); return p and p.Profile or nil end
function Resolver:HasCapability(id) return self.Registry:HasCapability(id) end
function Resolver:GetCapability(id) return self.Registry:GetCapability(id) end
function Resolver:ListCapabilities() return self.Registry:ListCapabilities() end
function Resolver:RegisterPlugin(plugin, implementation)
	if self.Destroyed or not self.World or self.World.Destroying or self.World.Destroyed then return self:_record(result(false,"WorldDestroyed")) end
	if getmetatable(plugin) ~= Plugin then
		local ok, normalized = pcall(function()
			if getmetatable(plugin) == Profile then return Plugin.new(plugin, implementation) end
			if type(plugin)=="table" and plugin.Profile then return Plugin.new(plugin.Profile, plugin) end
			return Plugin.new(plugin, implementation)
		end)
	if not ok then return self:_record(result(false,"InvalidPlugin",nil,nil,tostring(normalized))) end
		plugin=normalized
	end
	if plugin.Registry ~= nil then return self:_record(result(false,"PluginAlreadyOwned",plugin)) end
	if self.Registry:Has(plugin.Id) then return self:_record(result(false,"DuplicatePlugin",plugin)) end
	plugin.State=State.Registered; plugin.Enabled= true; plugin.Registry=self.Registry
	self.Registry.Plugins[plugin.Id]=plugin; self.Components[plugin.Id]=Component.new(plugin)
	self:_emit(Event.Type.Registered,plugin)
	return self:_record(result(true,"Registered",plugin,plugin))
end
function Resolver:UnregisterPlugin(id)
	local plugin=self:GetPlugin(id); if not plugin then return self:_record(result(false,"PluginNotFound")) end
	for _, dependent in ipairs(self.Registry:List()) do
		if dependent.State == State.Active then
			for _, dependency in ipairs(dependent.Profile.Dependencies) do
				if dependency.PluginId == plugin.Id and not dependency.Optional then
					return self:_record(result(false,"ActiveDependents",plugin,nil,{DependentId=dependent.Id}))
				end
			end
		end
	end
	if plugin.State==State.Active or plugin.State==State.Initializing or plugin.State==State.Stopping then return self:_record(result(false,"PluginActive",plugin)) end
	if plugin.State==State.Failed and plugin.Context then plugin.Context:_invalidate() end
	self.Registry.Plugins[plugin.Id]=nil
	local component=self.Components[plugin.Id]; if component then component:Destroy() end; self.Components[plugin.Id]=nil
	plugin.Registry=nil; plugin.Context=nil
	return self:_record(result(true,"Unregistered",plugin))
end
function Resolver:_registerCapability(plugin,id,implementation,version)
	if type(id)~="string" or id=="" then return nil,"InvalidCapabilityId" end
	if version~=nil and not PluginVersion.isValid(version) then return nil,"InvalidCapabilityVersion" end
	local declared=false
	for _,capabilityId in ipairs(plugin.Profile.Capabilities) do if capabilityId==id then declared=true; break end end
	if not declared then return nil,"CapabilityNotDeclared" end
	if self.Registry.Capabilities[id] then return nil,"CapabilityConflict" end
	local capability=require(script.Parent.PluginCapability).new({Id=id,Implementation=implementation,Version=version,OwnerPluginId=plugin.Id})
	self.Registry.Capabilities[id]=capability
	self:_emit(Event.Type.CapabilityRegistered,plugin,{CapabilityId=id,Version=capability.Version})
	return capability
end
function Resolver:_unregisterCapability(plugin,id)
	local capability=self.Registry.Capabilities[id]
	if not capability then return false,"CapabilityNotFound" end
	if capability.OwnerPluginId~=plugin.Id then return false,"PermissionDenied" end
	self.Registry.Capabilities[id]=nil
	self:_emit(Event.Type.CapabilityUnregistered,plugin,{CapabilityId=id})
	return true
end
function Resolver:_failRuntime(plugin,failure)
	if plugin.State~=State.Active then return end
	plugin.Failure=tostring(failure); self:StopPlugin(plugin.Id,"RuntimeFailure")
	plugin.State=State.Failed; self.Components[plugin.Id].State=State.Failed
	self:_emit(Event.Type.Failed,plugin,{Error=plugin.Failure})
	self:_record(result(false,"PluginRuntimeFailed",plugin,nil,plugin.Failure))
end
function Resolver:_dependencyOrder(plugin)
	local state, order={},{}
	local function visit(current)
		if state[current.Id]==1 then return false,"DependencyCycle",current.Id end
		if state[current.Id]==2 then return true end
		state[current.Id]=1
		local dependencies=table.clone(current.Profile.Dependencies)
		table.sort(dependencies,function(a,b)
			local pa,pb=self.Registry:Get(a.PluginId),self.Registry:Get(b.PluginId)
			if pa and pb then return pluginOrder(pa,pb) end
			if pa~=nil then return true elseif pb~=nil then return false end
			return a.PluginId<b.PluginId
		end)
		for _,dependency in ipairs(dependencies) do
			local target=self.Registry:Get(dependency.PluginId)
			if not target then
				if not dependency.Optional then return false,"DependencyMissing",dependency.PluginId end
			elseif not PluginVersion.isAtLeast(target.Version, dependency.MinVersion) then
				return false,"DependencyVersionMismatch",dependency.PluginId
			else
				local ok,code,id=visit(target); if not ok then return false,code,id end
			end
		end
		state[current.Id]=2; table.insert(order,current); return true
	end
	local ok,code,id=visit(plugin); return ok and order or nil,code,id
end
function Resolver:ResolveDependencies(id)
	local plugin=self:GetPlugin(id); if not plugin then return self:_record(result(false,"PluginNotFound")) end
	local order,code,dependencyId=self:_dependencyOrder(plugin)
	if not order then
		self:_emit(Event.Type.DependencyFailed,plugin,{Code=code,DependencyId=dependencyId})
		return self:_record(result(false,code,plugin,nil,{DependencyId=dependencyId}))
	end
	local ids={}; for _,item in ipairs(order) do table.insert(ids,item.Id) end
	return self:_record(result(true,"DependenciesResolved",plugin,table.freeze(ids)))
end
function Resolver:_startOne(plugin)
	if plugin.State==State.Active then return result(true,"AlreadyActive",plugin,plugin) end
	if not plugin.Enabled then return result(false,"PluginDisabled",plugin) end
	plugin.State=State.Initializing; self.Components[plugin.Id].State=State.Initializing
	self:_emit(Event.Type.Initializing,plugin)
	local context=Context.new(self,plugin); plugin.Context=context
	for _,hookName in ipairs({"Initialize","Start"}) do
		local hook=plugin.Implementation[hookName]
		if hook then
			local ok,failure=pcall(hook,context,plugin)
			if not ok or failure==false then
				plugin.Failure=tostring(ok and (hookName.."Rejected") or failure); context:_invalidate()
				plugin.Context=nil; plugin.State=State.Failed; self.Components[plugin.Id].State=State.Failed
				self:_emit(Event.Type.Failed,plugin,{Error=plugin.Failure,Hook=hookName})
				return result(false,"InitializationFailed",plugin,nil,plugin.Failure)
			end
		end
	end
	plugin.State=State.Active; self.Components[plugin.Id].State=State.Active
	self:_emit(Event.Type.Started,plugin); return result(true,"Started",plugin,plugin)
end
function Resolver:StartPlugin(id)
	local plugin=self:GetPlugin(id); if not plugin then return self:_record(result(false,"PluginNotFound")) end
	if self.Destroyed or not self.World or self.World.Destroying or self.World.Destroyed then return self:_record(result(false,"WorldDestroyed",plugin)) end
	local order,code,dependencyId=self:_dependencyOrder(plugin)
	if not order then self:_emit(Event.Type.DependencyFailed,plugin,{Code=code,DependencyId=dependencyId}); return self:_record(result(false,code,plugin,nil,{DependencyId=dependencyId})) end
	for _,item in ipairs(order) do
		if item.State~=State.Active then
			local started=self:_startOne(item)
			if not started.Success then
				if item~=plugin then self:_emit(Event.Type.DependencyFailed,plugin,{Code=started.Code,DependencyId=item.Id}) end
				return self:_record(result(false,item==plugin and started.Code or "DependencyFailed",plugin,nil,{DependencyId=item.Id,Failure=started.Code}))
			end
		end
	end
	return self:_record(result(true,"Started",plugin,plugin))
end
function Resolver:StopPlugin(id, reason)
	local plugin=self:GetPlugin(id); if not plugin then return self:_record(result(false,"PluginNotFound")) end
	for _, dependent in ipairs(self.Registry:List()) do
		if dependent.State == State.Active then
			for _, dependency in ipairs(dependent.Profile.Dependencies) do
				if dependency.PluginId == plugin.Id and not dependency.Optional then
					return self:_record(result(false,"ActiveDependents",plugin,nil,{DependentId=dependent.Id}))
				end
			end
		end
	end
	if plugin.State==State.Stopped or plugin.State==State.Registered then return self:_record(result(true,"AlreadyStopped",plugin,plugin)) end
	if plugin.State~=State.Active and plugin.State~=State.Failed then return self:_record(result(false,"InvalidLifecycleState",plugin)) end
	local oldContext=plugin.Context; plugin.State=State.Stopping; self.Components[plugin.Id].State=State.Stopping
	self:_emit(Event.Type.Stopping,plugin,{Reason=reason})
	local stop=plugin.Implementation.Stop; local ok,failure=true,nil
	if stop and oldContext then ok,failure=pcall(stop,oldContext,plugin) end
	if oldContext then oldContext:_invalidate() end
	plugin.Context=nil
	if not ok then plugin.Failure=tostring(failure); plugin.State=State.Failed; self.Components[plugin.Id].State=State.Failed
		self:_emit(Event.Type.Failed,plugin,{Error=plugin.Failure}); return self:_record(result(false,"StopFailed",plugin,nil,plugin.Failure)) end
	plugin.State=State.Stopped; self.Components[plugin.Id].State=State.Stopped
	self:_emit(Event.Type.Stopped,plugin,{Reason=reason})
	return self:_record(result(true,"Stopped",plugin,plugin))
end
function Resolver:EnablePlugin(id)
	local plugin=self:GetPlugin(id); if not plugin then return self:_record(result(false,"PluginNotFound")) end
	if plugin.Enabled then return self:_record(result(true,"AlreadyEnabled",plugin,plugin)) end
	plugin.Enabled=true; self:_emit(Event.Type.Enabled,plugin); return self:_record(result(true,"Enabled",plugin,plugin))
end
function Resolver:DisablePlugin(id)
	local plugin=self:GetPlugin(id); if not plugin then return self:_record(result(false,"PluginNotFound")) end
	if not plugin.Enabled then return self:_record(result(true,"AlreadyDisabled",plugin,plugin)) end
	if plugin.State==State.Active then local stopped=self:StopPlugin(id,"Disabled"); if not stopped.Success then return stopped end end
	plugin.Enabled=false; self:_emit(Event.Type.Disabled,plugin); return self:_record(result(true,"Disabled",plugin,plugin))
end
function Resolver:StartAll()
	local candidates={}; for _,plugin in ipairs(self.Registry:List()) do if plugin.Profile.AutoStart then table.insert(candidates,plugin) end end
	table.sort(candidates,pluginOrder); local results={}
	for _,plugin in ipairs(candidates) do results[#results+1]=self:StartPlugin(plugin.Id) end
	return results
end
function Resolver:Destroy()
	if self.Destroyed then return false end
	local remaining=true
	while remaining do
		remaining=false
		local plugins=self.Registry:List(); table.sort(plugins,pluginOrder)
		for _,plugin in ipairs(plugins) do
			if plugin.State==State.Active then
				local hasActiveDependent=false
				for _,candidate in ipairs(plugins) do if candidate.State==State.Active then
					for _,dependency in ipairs(candidate.Profile.Dependencies) do
						if not dependency.Optional and dependency.PluginId==plugin.Id then hasActiveDependent=true end
					end
				end end
				if not hasActiveDependent then self:StopPlugin(plugin.Id,"WorldDestroyed"); remaining=true end
			end
		end
	end
	for _,plugin in ipairs(self.Registry:List()) do if plugin.State==State.Failed then self:StopPlugin(plugin.Id,"WorldDestroyed") end end
	for _,plugin in ipairs(self.Registry:List()) do self:UnregisterPlugin(plugin.Id) end
	self.Destroyed=true; self.Registry.Destroyed=true; self.World=nil
	return true
end
Resolver.Register=Resolver.RegisterPlugin; Resolver.Unregister=Resolver.UnregisterPlugin
Resolver.Start=Resolver.StartPlugin; Resolver.Stop=Resolver.StopPlugin
return Resolver
