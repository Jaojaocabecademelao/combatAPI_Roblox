return function()
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local World=require(Shared.Core.World)
local CombatAPI=require(Shared.CombatAPI)
local Plugin=require(Shared.Plugins.Plugin)
local Profile=require(Shared.Plugins.PluginProfile)
local PluginVersion=require(Shared.Plugins.PluginVersion)
local State=require(Shared.Plugins.PluginState)
local Event=require(Shared.Plugins.PluginEvent)

local assertions=0
local function check(value,message) assert(value,message or ("Plugin assertion "..tostring(assertions+1).." failed")); assertions+=1 end
local function make(id, options, impl)
	options=options or {}; options.Id=id; options.Name=options.Name or id; options.Version=options.Version or "1.0.0"
	return Plugin.new(Profile.new(options),impl)
end
local function ok(result, code)
	check(result.Success and (not code or result.Code==code),
		"Expected successful result " .. tostring(code) .. ", got "
			.. tostring(result.Code) .. ": " .. tostring(result.Details))
end
local function fail(result, code) check(not result.Success and result.Code==code,"Expected failure "..tostring(code)..", got "..tostring(result.Code)) end

-- Definition validation and immutable metadata.
do
	check(PluginVersion.isValid("1.2.3") and not PluginVersion.isValid("1.2"),
		"Shared plugin version validator accepts only numeric major.minor.patch")
	check(PluginVersion.isAtLeast("100000000000000000000.0.0", "99999999999999999999.0.0"),
		"Plugin version comparison remains exact beyond floating-point integer precision")
	check(not PluginVersion.isAtLeast("99999999999999999999.0.0", "100000000000000000000.0.0"),
		"Plugin version comparison does not round distinct large components to equality")
	check(PluginVersion.isAtLeast("1.0.0", nil), "Missing minimum version accepts any valid plugin version")
	check(not PluginVersion.isAtLeast("invalid", nil),
		"Missing minimum does not make an invalid actual version valid")
	check(not pcall(function()
		CombatAPI.PluginCapability.new({ Id = "BadVersion", Version = "latest", OwnerPluginId = "Owner" })
	end), "Capability constructor rejects non-numeric versions")
	check(not pcall(function()
		CombatAPI.PluginCapability.new({ Id = "FalseVersion", Version = false, OwnerPluginId = "Owner" })
	end), "Capability constructor rejects non-string versions instead of defaulting them")
	check(not pcall(function()
		CombatAPI.PluginCapability.new({ Id = "MissingOwner", OwnerPluginId = "" })
	end), "Capability constructor requires an owner")
	check(not pcall(function() Profile.new({Name="Missing id",Version="1.0.0"}) end),"Missing ID is rejected")
	check(not pcall(function() Profile.new({Id="bad id",Name="Bad",Version="1.0.0"}) end),"Invalid ID is rejected")
	check(not pcall(function() Profile.new({Id="P",Version="1.0.0"}) end),"Missing name is rejected")
	check(not pcall(function() Profile.new({Id="P",Name="P",Version="v1"}) end),"Invalid version is rejected")
	check(not pcall(function() Profile.new({Id="P",Name="P",Version="1.0.0",Priority=0/0}) end),"NaN priority is rejected")
	check(not pcall(function() Profile.new({Id="P",Name="P",Version="1.0.0",AutoStart=1}) end),"Invalid AutoStart is rejected")
	check(not pcall(function() Profile.new({Id="P",Name="P",Version="1.0.0",Dependencies={"X","X"}}) end),"Duplicate dependencies are rejected")
	check(not pcall(function() Profile.new({Id="P",Name="P",Version="1.0.0",Dependencies={{PluginId=""}}}) end),"Empty dependency ID is rejected")
	check(not pcall(function() Profile.new({Id="P",Name="P",Version="1.0.0",Dependencies={{PluginId="X",Optional=1}}}) end),"Invalid Optional is rejected")
	check(not pcall(function() Profile.new({Id="P",Name="P",Version="1.0.0",Dependencies={{PluginId="X",MinVersion="latest"}}}) end),"Invalid minimum dependency version is rejected")
	check(not pcall(function() Profile.new({Id="P",Name="P",Version="1.0.0",Capabilities={"X","X"}}) end),"Duplicate capability declaration is rejected")
	local p=Profile.new({Id="Meta",Name="Metadata",Version="2.3.4",Priority=8,AutoStart=true,Dependencies={"Z","A"},Capabilities={"Y","B"}})
	check(p.Id=="Meta" and p.Name=="Metadata","Profile retains identity")
	check(p.Version=="2.3.4" and p.Priority==8 and p.AutoStart,"Profile retains version and lifecycle config")
	check(p.Scope == Profile.Scope.Gameplay,"Plugins default to the gameplay scope")
	check(p.Dependencies[1].PluginId=="A" and p.Dependencies[2].PluginId=="Z","Dependencies normalize deterministically")
	check(p.Capabilities[1]=="B" and p.Capabilities[2]=="Y","Capabilities normalize deterministically")
	check(table.isfrozen(p) and table.isfrozen(p.Dependencies) and table.isfrozen(p.Capabilities),"Profile data is immutable")
	check(not pcall(function() p.Id="Changed" end),"Frozen identity cannot be mutated")
	check(make("Valid").State==State.Registered,"New Plugin begins Registered")
	check(Plugin.new({Id="Legacy",Name="Legacy",Version="1.0.0"}).State==State.Registered,"Plugin accepts profile data directly")
	check(not pcall(function() Plugin.new(Profile.new({Id="BadImpl",Name="Bad",Version="1.0.0"}),{Initialize=true}) end),"Invalid lifecycle hook is rejected")
end

-- Registration, deterministic registry queries, duplicates, and result codes.
do
	local world=World.new(); local r=world:GetPluginResolver()
	check(r~=nil and r.Registry.World==world,"World owns an isolated registry")
	check(#r:ListPlugins()==0 and not r:HasPlugin("absent"),"Empty registry query is safe")
	for i=1,12 do
		local id=string.format("Reg%02d",i); local plugin=make(id,{Priority=i%4})
		ok(r:RegisterPlugin(plugin),"Registered"); check(plugin.State==State.Registered,"Registration preserves Registered state")
		check(r:GetPlugin(id)==plugin and r:HasPlugin(id),"Get and Has return the registered plugin")
		check(r:GetPluginProfile(id)==plugin.Profile and r:GetPluginState(id)==State.Registered,"Profile and state queries work")
	end
	local presentation=make("Presentation", { Scope = Profile.Scope.Presentation })
	ok(r:RegisterPlugin(presentation))
	check(#r:ListPluginsByScope(Profile.Scope.Gameplay) == 12,
		"Gameplay scope query excludes presentation plugins")
	check(#r:ListPluginsByScope(Profile.Scope.Presentation) == 1,
		"Presentation scope query returns presentation plugins")
	local list=r:ListPlugins(); check(#list==13,"List includes every plugin")
	for i=2,#list do check(list[i-1].Id<list[i].Id,"List order is stable by ID") end
	fail(r:RegisterPlugin(make("Reg01")),"DuplicatePlugin")
	check(r:GetPlugin("missing")==nil and r:GetPluginState("missing")==nil,"Missing plugin queries return nil")
	local result=r:UnregisterPlugin("absent"); fail(result,"PluginNotFound")
	local stopped=make("Unregister"); ok(r:RegisterPlugin(stopped)); ok(r:UnregisterPlugin(stopped.Id),"Unregistered")
	check(not r:HasPlugin(stopped.Id),"Unregister removes registry ownership")
	local invalid=r:RegisterPlugin({}); fail(invalid,"InvalidPlugin")
	for i=1,10 do
		local plugin=r:GetPlugin(string.format("Reg%02d",i)); check(plugin~=nil,"Registered plugin remains retrievable")
		check(plugin.State==State.Registered and plugin.Enabled,"Registration is enabled but not started")
	end
	check(#r:GetEvents()>=13 and r:GetEvents()[1].Type==Event.Type.Registered,"Registration events are observable")
	check(#r:GetResults()>=15,"Registry operations produce results")
	world:Destroy()
end

do
	local world = World.new()
	local entity = world:CreateEntity()
	check(world:DestroyEntity(entity), "Entity destruction succeeds")
	check(not world:HasEntity(entity.Id) and entity.Destroyed, "Entity destruction removes roster entry")
	check(not world:DestroyEntity(entity), "Repeated entity destruction is idempotently rejected")
	world:Destroy()
end

-- Lifecycle, repeated operations, isolation of hook errors, and cleanup.
do
	local world=World.new(); local r=world:GetPluginResolver(); local log={}
	local p=make("Life",{}, {Initialize=function(ctx) log[#log+1]="init"; check(ctx:IsValid(),"Initialize receives valid context") end,
		Stop=function(ctx) log[#log+1]="stop"; check(ctx:IsValid(),"Stop receives valid context") end})
	ok(r:RegisterPlugin(p),"Registered"); check(p.State==State.Registered,"Registered state is visible")
	ok(r:StartPlugin(p.Id),"Started"); check(p.State==State.Active,"Start enters Active")
	check(log[1]=="init" and p.Context:IsValid(),"Initialize runs and context remains valid")
	ok(r:StartPlugin(p.Id),"Started"); check(log[1]=="init","Repeated start does not initialize twice")
	fail(r:UnregisterPlugin(p.Id),"PluginActive")
	ok(r:StopPlugin(p.Id),"Stopped"); check(p.State==State.Stopped,"Stop enters Stopped")
	check(log[2]=="stop" and p.Context==nil,"Stop hook runs and context is released")
	ok(r:StopPlugin(p.Id),"AlreadyStopped"); ok(r:StartPlugin(p.Id),"Started")
	ok(r:StopPlugin(p.Id),"Stopped"); ok(r:UnregisterPlugin(p.Id),"Unregistered")
	local disabled=make("Disabled"); ok(r:RegisterPlugin(disabled)); ok(r:DisablePlugin(disabled.Id),"Disabled")
	check(not disabled.Enabled,"Disable changes enabled flag")
	fail(r:StartPlugin(disabled.Id),"PluginDisabled"); ok(r:EnablePlugin(disabled.Id),"Enabled")
	ok(r:EnablePlugin(disabled.Id),"AlreadyEnabled"); ok(r:StartPlugin(disabled.Id),"Started")
	ok(r:DisablePlugin(disabled.Id),"Disabled"); check(disabled.State==State.Stopped,"Disable stops an active plugin")
	local broken=make("Broken",{}, {Initialize=function() error("expected init fault") end})
	ok(r:RegisterPlugin(broken)); fail(r:StartPlugin(broken.Id),"InitializationFailed")
	check(broken.State==State.Failed and broken.Context==nil,"Initialization fault leaves Failed state and invalid context")
	check(r:GetPluginState(broken.Id)==State.Failed,"Failed state is queryable")
	ok(r:UnregisterPlugin(broken.Id),"Unregistered")
	local hookOrder={}; local hooks=make("BothHooks",{}, {
		Initialize=function() hookOrder[#hookOrder+1]="initialize" end,
		Start=function() hookOrder[#hookOrder+1]="start" end,
		Stop=function() hookOrder[#hookOrder+1]="stop" end,
	})
	ok(r:RegisterPlugin(hooks)); ok(r:StartPlugin(hooks.Id)); check(hookOrder[1]=="initialize" and hookOrder[2]=="start","Initialize precedes Start hook")
	ok(r:StopPlugin(hooks.Id)); check(hookOrder[3]=="stop","Stop hook runs after lifecycle starts")
	local eventPlugin=make("EventFault",{}, {Initialize=function(ctx) ctx:Subscribe("PluginTestFault",function() error("callback fault") end) end})
	ok(r:RegisterPlugin(eventPlugin)); ok(r:StartPlugin(eventPlugin.Id),"Started")
	world.EventBus:Dispatch("PluginTestFault",{},{}); check(eventPlugin.State==State.Failed,"Callback failure is isolated and stops that plugin")
	check(r:GetPlugin("Disabled").State==State.Stopped,"Other plugins survive a plugin failure")
	local counts={}; for _,e in ipairs(r:GetEvents()) do counts[e.Type]=(counts[e.Type] or 0)+1 end
	for _,kind in ipairs({Event.Type.Initializing,Event.Type.Started,Event.Type.Stopping,Event.Type.Stopped,Event.Type.Failed,Event.Type.Enabled,Event.Type.Disabled}) do
		check((counts[kind] or 0)>0,"Lifecycle event emitted: "..kind)
	end
	check(#world.EventBus:GetErrors()==0,"Plugin callback failures are handled without EventBus errors")
	world:Destroy()
end

-- Dependency graph, version constraints, optional edges, cycles, and priority.
do
	local world=World.new(); local r=world:GetPluginResolver(); local order={}
	local base=make("Base",{Version="2.1.0",Priority=-4},{Initialize=function() order[#order+1]="Base" end})
	local child=make("Child",{Dependencies={{PluginId="Base",MinVersion="2.0.0"}},Priority=30},{Initialize=function() order[#order+1]="Child" end})
	ok(r:RegisterPlugin(child)); ok(r:RegisterPlugin(base))
	local resolved=r:ResolveDependencies("Child"); ok(resolved,"DependenciesResolved")
	check(resolved.Value[1]=="Base" and resolved.Value[2]=="Child","Dependency order precedes dependent")
	ok(r:StartPlugin("Child")); check(order[1]=="Base" and order[2]=="Child","Start follows dependency order over priority")
	fail(r:StopPlugin("Base"),"ActiveDependents"); fail(r:UnregisterPlugin("Base"),"ActiveDependents")
	ok(r:StopPlugin("Child")); ok(r:StopPlugin("Base"))
	local missing=make("Missing",{Dependencies={"NoSuchPlugin"}}); ok(r:RegisterPlugin(missing))
	fail(r:StartPlugin("Missing"),"DependencyMissing")
	local optional=make("Optional",{Dependencies={{PluginId="NoSuchPlugin",Optional=true}}}); ok(r:RegisterPlugin(optional))
	ok(r:ResolveDependencies("Optional"),"DependenciesResolved"); ok(r:StartPlugin("Optional"),"Started")
	local incompatible=make("Incompatible",{Dependencies={{PluginId="Base",MinVersion="3.0.0"}}}); ok(r:RegisterPlugin(incompatible))
	fail(r:StartPlugin("Incompatible"),"DependencyVersionMismatch")
	local preciseBase=make("PreciseBase",{Version="99999999999999999999.0.0"})
	local preciseDependent=make("PreciseDependent",{
		Dependencies={{PluginId="PreciseBase",MinVersion="100000000000000000000.0.0"}},
	})
	ok(r:RegisterPlugin(preciseBase)); ok(r:RegisterPlugin(preciseDependent))
	fail(r:StartPlugin(preciseDependent.Id),"DependencyVersionMismatch")
	check(preciseBase.State==State.Registered and preciseDependent.State==State.Registered,
		"Dependency resolver rejects an insufficient large version component exactly")
	local b=make("CycleB",{Dependencies={"CycleC"}}); local c=make("CycleC",{Dependencies={"CycleB"}})
	ok(r:RegisterPlugin(b)); ok(r:RegisterPlugin(c)); fail(r:ResolveDependencies("CycleB"),"DependencyCycle")
	local noVersion=make("NoVersion"); check(not pcall(function() noVersion.Profile.Version="x" end),"Version profile cannot mutate")
	local priority={}
	for _,spec in ipairs({{"PriLow",-5},{"PriHigh",8},{"PriMid",2}}) do
		local pluginId,pluginPriority=spec[1],spec[2]
		local p=make(pluginId,{Priority=pluginPriority,AutoStart=true},{Initialize=function() priority[#priority+1]=pluginId end}); ok(r:RegisterPlugin(p))
	end
	local results=r:StartAll(); check(#results==3,"StartAll processes all AutoStart plugins")
	check(priority[1]=="PriHigh" and priority[2]=="PriMid" and priority[3]=="PriLow","Priority sorts independent plugins")
	local tie=World.new(); local tr=tie:GetPluginResolver(); local tieOrder={}
	for _,id in ipairs({"TieB","TieA"}) do local pluginId=id
		ok(tr:RegisterPlugin(make(pluginId,{AutoStart=true,Priority=0},{Initialize=function() tieOrder[#tieOrder+1]=pluginId end}))) end
	tr:StartAll(); check(tieOrder[1]=="TieA" and tieOrder[2]=="TieB","Equal priority tie breaks by ID")
	local chain=make("Chain",{Dependencies={"Base"},AutoStart=true},{Initialize=function() priority[#priority+1]="Chain" end}); ok(r:RegisterPlugin(chain))
	local chainResult=r:StartPlugin("Chain"); check(chainResult.Success and chain.State==State.Active,"Existing dependency allows another dependent")
	check(r:GetPlugin("Missing").State==State.Registered,"Failed dependencies do not initialize dependent")
	check(r:GetPlugin("Incompatible").State==State.Registered,"Version mismatch leaves plugin registered")
	check(r:GetPlugin("CycleB").State==State.Registered and r:GetPlugin("CycleC").State==State.Registered,"Cycle detection leaves graph intact")
	tie:Destroy(); world:Destroy()
end

-- Context capability ownership, subscription cleanup, and explicit conflicts.
do
	local world=World.new(); local r=world:GetPluginResolver(); local saved,received
	local owner=make("Owner",{Capabilities={"CustomDamageRule"}}, {Initialize=function(ctx)
		saved=ctx; local cap,code=ctx:RegisterCapability("CustomDamageRule",function() return "owner" end,"1.2.0")
		check(cap~=nil and code==nil,"Capability registers from plugin context")
		local invalidVersion,invalidVersionCode=ctx:RegisterCapability("CustomDamageRule",{},"latest")
		check(invalidVersion==nil and invalidVersionCode=="InvalidCapabilityVersion",
			"Malformed capability versions return InvalidCapabilityVersion instead of raising")
		check(ctx:GetCapability("CustomDamageRule")==cap,"Plugin can query a registered capability")
		local sub=ctx:Subscribe("PluginOwnedEvent",function(event) received=event.Type end)
		check(sub~=nil and sub:IsConnected(),"Context subscription is connected")
	end})
	ok(r:RegisterPlugin(owner)); ok(r:StartPlugin(owner.Id))
	check(r:HasCapability("CustomDamageRule"),"Registry reports capability")
	check(r:GetCapability("CustomDamageRule").OwnerPluginId==owner.Id,"Capability records owner")
	check(r:GetCapability("CustomDamageRule").Version=="1.2.0","Capability records version")
	check(r:GetCapability("CustomDamageRule").Implementation() == "owner","Capability implementation is retrievable")
	check(#r:ListCapabilities()==1 and r:ListCapabilities()[1].Id=="CustomDamageRule","Capability list is deterministic")
	world.EventBus:Dispatch("PluginOwnedEvent",{},{}); check(received=="PluginOwnedEvent","Plugin receives subscribed event")
	local competitor=make("Competitor",{Capabilities={"CustomDamageRule"}}, {Initialize=function(ctx)
		local cap,code=ctx:RegisterCapability("CustomDamageRule",{},"1.0.0"); check(cap==nil and code=="CapabilityConflict","Capability collision is explicit")
	end})
	ok(r:RegisterPlugin(competitor)); ok(r:StartPlugin(competitor.Id))
	local denied,deniedCode=r:_unregisterCapability(competitor,"CustomDamageRule")
	check(denied==false and deniedCode=="PermissionDenied","Foreign owner cannot unregister capability")
	local undeclared=make("Undeclared",{}, {Initialize=function(ctx)
		local value,code=ctx:RegisterCapability("NotDeclared",{})
		check(value==nil and code=="CapabilityNotDeclared","Plugin can register only declared capabilities")
	end})
	ok(r:RegisterPlugin(undeclared)); ok(r:StartPlugin(undeclared.Id)); ok(r:StopPlugin(undeclared.Id))
	local invalidContext=saved; ok(r:StopPlugin(owner.Id))
	check(not invalidContext:IsValid() and invalidContext:GetWorld()==nil,"Stopped context is invalidated")
	check(invalidContext:RegisterCapability("Late",{})==nil,"Invalid context cannot register extensions")
	check(not r:HasCapability("CustomDamageRule"),"Stop cleans owner capability")
	check(received=="PluginOwnedEvent","Subscription callback was observed before cleanup")
	local before=received; world.EventBus:Dispatch("PluginOwnedEvent",{},{}); check(received==before,"Stopped plugin no longer receives events")
	local d=make("RemoveCapability",{Capabilities={"Temporary"}}); ok(r:RegisterPlugin(d)); ok(r:StartPlugin(d.Id))
	local context=d.Context; local cap=context:Register("Capability","Temporary",42)
	check(cap~=nil and r:HasCapability("Temporary"),"Generic extension API routes capability registration")
	local removed,removeCode=r:_unregisterCapability(d,"Temporary"); check(removed and removeCode==nil,"Owner can unregister capability")
	check(not r:HasCapability("Temporary"),"Explicit unregister removes capability")
	ok(r:StopPlugin(d.Id)); check(not context:IsValid(),"Cleanup invalidates every plugin context")
	local eventTypes={}; for _,e in ipairs(r:GetEvents()) do eventTypes[e.Type]=true end
	check(eventTypes[Event.Type.CapabilityRegistered] and eventTypes[Event.Type.CapabilityUnregistered],"Capability lifecycle events are emitted")
	world:Destroy()
end

-- Multi-World isolation, EventBus reuse, public API, execution mode, and teardown.
do
	local a,b=World.new(),World.new(); local ra,rb=a:GetPluginResolver(),b:GetPluginResolver()
	local hitsA,hitsB=0,0
	local sharedProfile=Profile.new({Id="SharedDefinition",Name="Shared",Version="1.0.0"})
	local pa=Plugin.new(sharedProfile,{Initialize=function(ctx) ctx:Subscribe("Isolation",function() hitsA+=1 end) end})
	local pb=Plugin.new(sharedProfile,{Initialize=function(ctx) ctx:Subscribe("Isolation",function() hitsB+=1 end) end})
	ok(ra:RegisterPlugin(pa)); ok(rb:RegisterPlugin(pb)); ok(ra:StartPlugin(pa.Id)); ok(rb:StartPlugin(pb.Id))
	check(pa~=pb and pa.Context~=pb.Context,"Same profile identity receives distinct runtime plugin instances")
	check(pa.Profile==pb.Profile,"World-local instances may reuse one immutable definition")
	check(ra.Registry~=rb.Registry and a.EventBus~=b.EventBus,"World resources are independent")
	fail(rb:RegisterPlugin(pa),"PluginAlreadyOwned")
	a.EventBus:Dispatch("Isolation",{},{}); check(hitsA==1 and hitsB==0,"World A event does not leak to World B")
	b.EventBus:Dispatch("Isolation",{},{}); check(hitsA==1 and hitsB==1,"World B event remains local")
	check(CombatAPI.GetPluginResolver(a)==ra and CombatAPI.GetPluginResolver(b)==rb,"CombatAPI returns per-world resolver")
	local publicWorld=CombatAPI.CreateWorld(); local publicContext=CombatAPI.GetAPIContext(publicWorld)
	local registration=CombatAPI.RegisterPlugin(publicWorld,{Id="Public",Name="Public",Version="1.0.0"})
	check(registration.Success and registration.Value.Code=="Registered","Public API registers plugin with APIResult")
	local found=publicContext:GetPlugin("Public"); check(found.Success and found.Value.Id=="Public","API context queries plugin")
	local start=CombatAPI.StartPlugin(publicWorld,"Public"); check(start.Success and publicWorld:GetPluginResolver():GetPluginState("Public")==State.Active,"Public API starts plugin")
	local contextResolver=publicContext:GetPluginResolver(); check(contextResolver==publicWorld:GetPluginResolver(),"Public API context exposes plugin resolver")
	check(publicContext:HasFeature("Plugins") and publicContext:HasSystem("Plugins"),"Plugins are discoverable through public API feature queries")
	local missing=CombatAPI.RegisterPlugin({},{}); check(not missing.Success,"Public API rejects non-world target")
	publicContext:StopPlugin("Public"); publicWorld:Destroy(); check(publicContext:GetPluginResolver()==nil,"Destroyed API context cannot access plugin resolver")
	local destroyedLookup = publicContext:GetPlugin("Public")
	check(not destroyedLookup.Success and destroyedLookup.Error.Code=="Destroyed",
		"Destroyed API context reports Destroyed when looking up a plugin")
	local modeSeen={}; local modePlugin=make("Modes",{}, {Initialize=function(ctx)
		ctx:Subscribe("ModeEvent",function(event) modeSeen[#modeSeen+1]=event.ExecutionMode end)
	end})
	ok(ra:RegisterPlugin(modePlugin)); ok(ra:StartPlugin(modePlugin.Id))
	for _,mode in ipairs({"Normal","Prediction","Replay","Authority"}) do
		a.EventBus:Dispatch("ModeEvent",{}, {ExecutionMode=mode}); check(modeSeen[#modeSeen]==mode,"Event preserves execution mode "..mode)
	end
	local saved=pa.Context; a:Destroy(); b:Destroy()
	check(a.Destroyed and b.Destroyed and ra.Destroyed and rb.Destroyed,"World teardown destroys plugin resolver")
	check(saved==nil or not saved:IsValid(),"World destruction invalidates plugin contexts")
	check(#ra:ListPlugins()==0 and #rb:ListPlugins()==0,"World teardown unregisters runtime plugins")
	check(ra:StartPlugin("anything").Success==false,"Destroyed resolver refuses new lifecycle work")
	check(publicWorld.Destroyed,"Public world cleanup completed")
	check(not modePlugin.Context or not modePlugin.Context:IsValid(),"All runtime contexts are released on destroy")
	check(Event.Type.Registered=="PluginRegistered" and Event.Type.DependencyFailed=="PluginDependencyFailed","Plugin event names are stable")
	local orderWorld=World.new(); local orderResolver=orderWorld:GetPluginResolver(); local stopOrder={}
	local root=make("DestroyRoot",{}, {Stop=function() stopOrder[#stopOrder+1]="root" end})
	local dependent=make("DestroyDependent",{Dependencies={"DestroyRoot"}},{Stop=function() stopOrder[#stopOrder+1]="dependent" end})
	ok(orderResolver:RegisterPlugin(root)); ok(orderResolver:RegisterPlugin(dependent)); ok(orderResolver:StartPlugin(dependent.Id))
	orderWorld:Destroy()
	check(stopOrder[1]=="dependent" and stopOrder[2]=="root","World teardown stops dependents before dependencies")
end

-- Per-plugin contract matrix: contexts, ownership, event delivery, and priority ordering.
do
	local world=World.new(); local r=world:GetPluginResolver(); local received={}; local registrations={}
	for i=1,12 do
		local id=string.format("Matrix%02d",i); local capability="MatrixCapability"..tostring(i)
		local pluginId,capabilityId,index=id,capability,i
		local plugin=make(id,{Capabilities={capability}}, {Initialize=function(ctx)
			local value,err=ctx:RegisterCapability(capabilityId,{Index=index},"1.0.0")
			check(value~=nil and err==nil,"Matrix capability owner registers without conflict")
			local subscription,subscribeError=ctx:Subscribe("PluginMatrixEvent",function(event)
				received[#received+1]=pluginId..":"..event.Type
			end,{Priority=index%4})
			check(subscription~=nil and subscribeError==nil,"Matrix plugin owns a valid subscription")
		end})
		registrations[i]=plugin
		ok(r:RegisterPlugin(plugin)); ok(r:StartPlugin(id))
		check(r:GetPlugin(id)==plugin,"Matrix runtime lookup preserves identity")
		check(plugin.State==State.Active and r:GetPluginState(id)==State.Active,"Matrix lifecycle records active state")
		check(plugin.Context:IsValid() and plugin.Context:GetWorld()==world,"Matrix context binds to its own World")
		check(plugin.Context:GetAPI()==world.APIContext and plugin.Context:GetEventBus()==world.EventBus,"Matrix context shares public API bus")
		check(r:HasCapability(capability) and r:GetCapability(capability).OwnerPluginId==id,"Matrix capability ownership is exact")
		check(r:GetCapability(capability).Version=="1.0.0" and r:GetCapability(capability).Implementation.Index==i,"Matrix payload and version survive registry")
		check(plugin.Context:GetCapability(capability)==r:GetCapability(capability),"Matrix context sees its owned capability")
	end
	world.EventBus:Dispatch("PluginMatrixEvent",{Marker=1},{ExecutionMode="Normal"})
	check(#received==12,"One public event reaches each active subscriber exactly once")
	for i=1,#received do check(received[i]:match("^Matrix%d%d:PluginMatrixEvent$")~=nil,"Delivered event has stable type and owner") end
	local expected={}; for i=1,12 do table.insert(expected,registrations[i]) end
	table.sort(expected,function(a,b)
		local pa,pb=tonumber(a.Id:match("(%d+)$"))%4,tonumber(b.Id:match("(%d+)$"))%4
		if pa~=pb then return pa>pb end
		return a.Id<b.Id
	end)
	for index,plugin in ipairs(expected) do
		check(received[index]==plugin.Id..":PluginMatrixEvent","Listener priority and registration order are deterministic")
		check(plugin.Context:IsValid() and plugin.Context:GetRegistry():Has(plugin.Id),"Active context exposes safe registry queries")
		check(plugin.Context:GetRegistry().Plugins==nil,"Context registry does not expose mutable storage")
	end
	for i=1,12 do
		local plugin=registrations[i]; ok(r:StopPlugin(plugin.Id))
		check(not plugin.Context and plugin.State==State.Stopped,"Matrix stop releases context")
		check(not r:HasCapability("MatrixCapability"..tostring(i)),"Matrix stop releases owned capability")
		check(r:GetPlugin(plugin.Id)==plugin and r:GetPluginState(plugin.Id)==State.Stopped,"Stopped definition remains queryable")
	end
	local before=#received; world.EventBus:Dispatch("PluginMatrixEvent",{},{}); check(#received==before,"All matrix listeners cleaned up")
	check(#r:ListCapabilities()==0,"All matrix capabilities cleaned up")
	world:Destroy()
end

-- Repeated construction yields deterministic registration and start traces.
do
	local function trace()
		local world=World.new(); local resolver=world:GetPluginResolver(); local output={}
		for _,spec in ipairs({{"TraceC",4},{"TraceA",4},{"TraceB",9}}) do
			local pluginId,pluginPriority=spec[1],spec[2]
			local plugin=make(pluginId,{Priority=pluginPriority,AutoStart=true},{Initialize=function() output[#output+1]=pluginId end})
			resolver:RegisterPlugin(plugin)
		end
		resolver:StartAll(); local ids={}; for _,plugin in ipairs(resolver:ListPlugins()) do ids[#ids+1]=plugin.Id end
		world:Destroy(); return table.concat(ids,",").."|"..table.concat(output,",")
	end
	local first,second=trace(),trace()
	check(first==second,"Equivalent plugin registrations produce deterministic lifecycle trace")
	check(first=="TraceA,TraceB,TraceC|TraceB,TraceA,TraceC","Priority and ID define stable initialization order")
end

assert(assertions>=250,"Plugin suite must include at least 250 meaningful assertions; got "..tostring(assertions))
print("Combat plugin tests passed ("..tostring(assertions).." assertions)")

end
