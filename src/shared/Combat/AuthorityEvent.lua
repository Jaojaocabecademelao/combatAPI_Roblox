local Event = {}
Event.__index = Event

Event.Type = table.freeze({
	Started = "AuthorityStarted",
	Stopped = "AuthorityStopped",
	InputAccepted = "AuthorityInputAccepted",
	InputRejected = "AuthorityInputRejected",
	InputValidated = "AuthorityInputValidated",
	InputInvalid = "AuthorityInputInvalid",
	SimulationAdvanced = "AuthoritySimulationAdvanced",
	SnapshotCreated = "AuthoritySnapshotCreated",
	SnapshotPublished = "AuthoritySnapshotPublished",
	Error = "AuthorityError",
})

function Event.new(data)
	assert(type(data) == "table" and type(data.Type) == "string", "AuthorityEvent is invalid")
	return setmetatable(data, Event)
end

return Event
