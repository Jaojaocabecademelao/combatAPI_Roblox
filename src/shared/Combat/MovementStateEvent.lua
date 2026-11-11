local Event = {}
Event.__index = Event
Event.Type = table.freeze({ StateChanged = "StateChanged", TransitionRejected = "TransitionRejected" })
function Event.new(data) return setmetatable(data, Event) end
return Event
