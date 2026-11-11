local Event = {}
Event.Type = table.freeze({ Registered="PluginRegistered", Initializing="PluginInitializing", Started="PluginStarted",
	Stopping="PluginStopping", Stopped="PluginStopped", Failed="PluginFailed", Enabled="PluginEnabled",
	Disabled="PluginDisabled", DependencyFailed="PluginDependencyFailed", CapabilityRegistered="PluginCapabilityRegistered",
	CapabilityUnregistered="PluginCapabilityUnregistered" })
function Event.new(data) return table.freeze(data) end
return Event
