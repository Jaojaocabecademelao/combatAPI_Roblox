local Profile = {}
Profile.__index = Profile

local function positiveInteger(value, minimum)
	return type(value) == "number" and value == value and value >= minimum
		and value < math.huge and value % 1 == 0
end

function Profile.new(options)
	options = options or {}
	assert(type(options) == "table", "RollbackProfile.new() expects an options table")
	for _, key in ipairs({
		"Enabled", "AllowSameFrameRollback", "AbortOnMissingInput",
		"AbortOnMissingSnapshot", "RecordReplayFrames",
	}) do
		assert(options[key] == nil or type(options[key]) == "boolean",
			("RollbackProfile %s must be boolean"):format(key))
	end

	local profile = {
		Enabled = options.Enabled == nil or options.Enabled == true,
		MaxRollbackFrames = options.MaxRollbackFrames or 120,
		MaxReplayFrames = options.MaxReplayFrames or 120,
		HistorySize = options.HistorySize or 120,
		MaxSnapshotEntries = options.MaxSnapshotEntries or 100000,
		MaxSnapshotDepth = options.MaxSnapshotDepth or 64,
		AllowSameFrameRollback = options.AllowSameFrameRollback == true,
		AbortOnMissingInput = options.AbortOnMissingInput ~= false,
		AbortOnMissingSnapshot = options.AbortOnMissingSnapshot ~= false,
		RecordReplayFrames = options.RecordReplayFrames == true,
	}
	assert(type(profile.Enabled) == "boolean", "RollbackProfile Enabled must be boolean")
	assert(positiveInteger(profile.MaxRollbackFrames, 0),
		"RollbackProfile MaxRollbackFrames must be a non-negative integer")
	assert(positiveInteger(profile.MaxReplayFrames, 0),
		"RollbackProfile MaxReplayFrames must be a non-negative integer")
	assert(positiveInteger(profile.HistorySize, 1),
		"RollbackProfile HistorySize must be a positive integer")
	assert(positiveInteger(profile.MaxSnapshotEntries, 1),
		"RollbackProfile MaxSnapshotEntries must be a positive integer")
	assert(positiveInteger(profile.MaxSnapshotDepth, 1),
		"RollbackProfile MaxSnapshotDepth must be a positive integer")
	assert(type(profile.AllowSameFrameRollback) == "boolean"
		and type(profile.AbortOnMissingInput) == "boolean"
		and type(profile.AbortOnMissingSnapshot) == "boolean"
		and type(profile.RecordReplayFrames) == "boolean",
		"RollbackProfile flags must be boolean")
	return setmetatable(profile, Profile)
end

return Profile
