local Event = {}
Event.__index = Event
Event.Type = table.freeze({ Allowed = "CancelAllowed", Rejected = "CancelRejected" })
function Event.new(data) return setmetatable(data, Event) end
return Event
