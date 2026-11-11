local Event = {}
Event.__index = Event
Event.Type = table.freeze({
	Attached = "CharacterAttached", Detached = "CharacterDetached",
	Reattached = "CharacterReattached", AttachFailed = "CharacterAttachFailed",
	DetachFailed = "CharacterDetachFailed",
})
function Event.new(data) return setmetatable(data, Event) end
return Event
