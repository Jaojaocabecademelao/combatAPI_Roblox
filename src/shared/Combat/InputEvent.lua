local Event = {}
Event.__index = Event
Event.Type = table.freeze({ Pressed = "InputPressed", Released = "InputReleased" })
function Event.new(data) return setmetatable(data, Event) end
return Event
