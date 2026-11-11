local Policy = require(script.Parent.AuthorityPolicy)

local Profile = {}
Profile.__index = Profile

local function integer(value, minimum)
	return type(value) == "number" and value == value and value >= minimum
		and value < math.huge and value % 1 == 0
end

function Profile.new(options)
	options = options or {}
	assert(type(options) == "table", "AuthorityProfile.new() expects an options table")
	for _, key in ipairs({ "Enabled", "RejectInvalidInputs", "PublishSnapshots" }) do
		assert(options[key] == nil or type(options[key]) == "boolean",
			("AuthorityProfile %s must be boolean"):format(key))
	end
	local policy = options.PastInputPolicy or Policy.PastInput.Reject
	assert(policy == Policy.PastInput.Reject or policy == Policy.PastInput.Rollback,
		"AuthorityProfile PastInputPolicy is invalid")
	local profile = {
		Enabled = options.Enabled ~= false,
		InputPolicy = options.InputPolicy or Policy.Reject,
		MaxInputLeadFrames = options.MaxInputLeadFrames or 8,
		MaxInputDelayFrames = options.MaxInputDelayFrames or 0,
		MaxFutureFrames = options.MaxFutureFrames or 8,
		MaxPastFrames = options.MaxPastFrames or 0,
		RejectInvalidInputs = options.RejectInvalidInputs ~= false,
		PublishSnapshots = options.PublishSnapshots ~= false,
		SnapshotInterval = options.SnapshotInterval or 3,
		MaxInputsPerFrame = options.MaxInputsPerFrame or 8,
		MaxFramesPerAdvance = options.MaxFramesPerAdvance or 120,
		PastInputPolicy = policy,
		SnapshotFilter = options.SnapshotFilter,
	}
	assert(profile.InputPolicy == Policy.Accept or profile.InputPolicy == Policy.Reject
		or profile.InputPolicy == Policy.Ignore or profile.InputPolicy == Policy.Disconnect,
		"AuthorityProfile InputPolicy is invalid")
	for _, key in ipairs({
		"MaxInputLeadFrames", "MaxInputDelayFrames", "MaxFutureFrames",
		"MaxPastFrames", "SnapshotInterval", "MaxInputsPerFrame", "MaxFramesPerAdvance",
	}) do
		assert(integer(profile[key], key == "SnapshotInterval" and 1 or 0),
			("AuthorityProfile %s is invalid"):format(key))
	end
	assert(type(profile.Enabled) == "boolean" and type(profile.RejectInvalidInputs) == "boolean"
		and type(profile.PublishSnapshots) == "boolean", "AuthorityProfile flags are invalid")
	assert(profile.SnapshotFilter == nil or type(profile.SnapshotFilter) == "function",
		"AuthorityProfile SnapshotFilter must be a function or nil")
	return setmetatable(profile, Profile)
end

return Profile
