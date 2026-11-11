local Event = {}
Event.__index = Event
Event.Type = table.freeze({
	Started = "AnimationStarted", Paused = "AnimationPaused", Resumed = "AnimationResumed",
	Stopped = "AnimationStopped", Completed = "AnimationCompleted",
	Changed = "AnimationChanged", Failed = "AnimationFailed", Marker = "AnimationMarker",
})
function Event.new(data) return setmetatable(data, Event) end
return Event
