local Snapshot = {}
Snapshot.__index = Snapshot
Snapshot.Version = 1
function Snapshot.new(data)
	assert(type(data) == "table" and type(data.SimulationFrame) == "number", "NetworkSnapshot is invalid")
	local version = data.Version == nil and Snapshot.Version or data.Version
	assert(version == Snapshot.Version, "NetworkSnapshot version is unsupported")
	return setmetatable({ Version = version, SimulationFrame = data.SimulationFrame, Sequence = data.Sequence, Entities = data.Entities or {}, Components = data.Components or {}, Metadata = data.Metadata or {} }, Snapshot)
end
return Snapshot
