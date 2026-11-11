local Event = {}
Event.__index = Event
Event.Type = table.freeze({ Connected = "Connected", Disconnected = "Disconnected", MessageSent = "MessageSent", MessageReceived = "MessageReceived", MessageRejected = "MessageRejected", Acknowledged = "Acknowledged", SequenceRejected = "SequenceRejected", SnapshotReceived = "SnapshotReceived", InputReceived = "InputReceived", SynchronizationReceived = "SynchronizationReceived" })
function Event.new(data) return setmetatable(data, Event) end
return Event
