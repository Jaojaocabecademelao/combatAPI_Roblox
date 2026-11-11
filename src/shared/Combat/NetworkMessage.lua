local Message = {}
Message.__index = Message
Message.Version = 1
Message.Type = table.freeze({ Input = "Input", Snapshot = "Snapshot", Acknowledgement = "Acknowledgement", Synchronization = "Synchronization", Command = "Command", Event = "Event" })
function Message.new(data)
	assert(type(data) == "table", "NetworkMessage data is required")
	assert(type(data.Type) == "string" and type(data.Channel) == "string", "NetworkMessage envelope is invalid")
	assert(type(data.SimulationFrame) == "number" and data.SimulationFrame >= 0, "NetworkMessage frame is invalid")
	local version = data.Version == nil and Message.Version or data.Version
	assert(type(version) == "number" and version == Message.Version and version % 1 == 0,
		"NetworkMessage version is unsupported")
	return setmetatable({
		Version = version,
		Type = data.Type, Channel = data.Channel, Sequence = data.Sequence,
		SimulationFrame = data.SimulationFrame, Sender = data.Sender, Payload = data.Payload,
		AcknowledgedFrame = data.AcknowledgedFrame,
	}, Message)
end
return Message
