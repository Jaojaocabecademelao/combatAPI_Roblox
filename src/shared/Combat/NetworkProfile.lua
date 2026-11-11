local Profile = {}
Profile.__index = Profile
function Profile.new(options)
	options = options or {}
	local function positive(value, fallback) return value == nil and fallback or (type(value) == "number" and value >= 0 and value < math.huge and value % 1 == 0 and value or nil) end
	local send, receive = positive(options.SendRate, 0), positive(options.ReceiveRate, 0)
	assert(send and receive, "NetworkProfile rates are invalid")
	assert(options.Reliability == nil or options.Reliability == "Reliable" or options.Reliability == "Unreliable", "NetworkProfile reliability is invalid")
	assert(options.Ordering == nil or options.Ordering == "Ordered" or options.Ordering == "Unordered", "NetworkProfile ordering is invalid")
	return setmetatable({ SendRate = send, ReceiveRate = receive, Channel = options.Channel or "Simulation", Reliability = options.Reliability or "Reliable", Ordering = options.Ordering or "Ordered", BufferSize = options.BufferSize or 60, SnapshotInterval = options.SnapshotInterval or 0, InputInterval = options.InputInterval or 0 }, Profile)
end
return Profile
