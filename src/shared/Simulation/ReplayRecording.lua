local Serializer = require(script.Parent.StateSerializer)

local Recording = {}
Recording.__index = Recording
Recording.Version = 1

local function validFrame(frame)
	return type(frame) == "number" and frame == frame and frame >= 0
		and frame < math.huge and frame % 1 == 0
end

local function validateSnapshot(snapshot)
	if type(snapshot) ~= "table" or getmetatable(snapshot) ~= nil
		or snapshot.Version ~= Recording.Version or type(snapshot.Metadata) ~= "table"
		or type(snapshot.Metadata.ContentFingerprint) ~= "string"
		or snapshot.Metadata.ContentFingerprint == ""
		or not validFrame(snapshot.Metadata.StartFrame or 0)
		or type(snapshot.Frames) ~= "table" then
		return false, "Invalid replay recording header"
	end
	for key in pairs(snapshot) do
		if key ~= "Version" and key ~= "Metadata" and key ~= "InitialState"
			and key ~= "ExternalFacts" and key ~= "Frames" then
			return false, "Unknown replay recording field: " .. tostring(key)
		end
	end
	if type(snapshot.InitialState) ~= "table" then return false, "Replay recording requires an initial state" end
	local count, maxIndex = 0, 0
	for key in pairs(snapshot.Frames) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return false, "Replay frames must be a dense array"
		end
		count += 1
		if key > maxIndex then maxIndex = key end
	end
	if count ~= maxIndex then return false, "Replay frames must be a dense array" end
	return true
end

function Recording.new(options)
	assert(type(options) == "table", "ReplayRecording.new() expects an options table")
	assert(type(options.Metadata) == "table"
		and type(options.Metadata.ContentFingerprint) == "string"
		and options.Metadata.ContentFingerprint ~= "",
		"ReplayRecording requires a content fingerprint")
	local metadata = Serializer.CloneSerializable(options.Metadata)
	if metadata.StartFrame == nil then metadata.StartFrame = 0 end
	assert(validFrame(metadata.StartFrame), "ReplayRecording StartFrame must be a non-negative integer")
	assert(type(options.InitialState) == "table", "ReplayRecording requires an initial state")
	local externalFacts
	if options.ExternalFacts ~= nil then
		assert(type(options.ExternalFacts) == "table", "ReplayRecording ExternalFacts must be a table or nil")
		externalFacts = Serializer.CloneSerializable(options.ExternalFacts)
	end
	local self = setmetatable({
		Metadata = metadata,
		InitialState = Serializer.CloneSerializable(options.InitialState),
		ExternalFacts = externalFacts,
		Frames = {},
	}, Recording)
	return self
end

function Recording:AppendFrame(frame, inputs, stateHash, externalFacts)
	assert(validFrame(frame), "Replay frame must be a non-negative integer")
	assert(type(stateHash) == "string" and stateHash ~= "", "Replay frame requires a state hash")
	assert(inputs == nil or type(inputs) == "table", "Replay frame inputs must be a table or nil")
	assert(externalFacts == nil or type(externalFacts) == "table",
		"Replay frame external facts must be a table or nil")
	local expectedFrame = self.Metadata.StartFrame + #self.Frames + 1
	assert(frame == expectedFrame, "Replay frames must be contiguous and ordered")
	local record = {
		Frame = frame,
		Inputs = Serializer.CloneSerializable(inputs or {}),
		StateHash = stateHash,
	}
	if externalFacts ~= nil then
		record.ExternalFacts = Serializer.CloneSerializable(externalFacts)
	end
	table.insert(self.Frames, record)
	return record
end

function Recording:Capture()
	local snapshot = {
		Version = Recording.Version,
		Metadata = self.Metadata,
		InitialState = self.InitialState,
		Frames = self.Frames,
	}
	if self.ExternalFacts ~= nil then snapshot.ExternalFacts = self.ExternalFacts end
	return Serializer.CloneSerializable(snapshot)
end

function Recording.FromSnapshot(snapshot, migrations)
	if type(snapshot) ~= "table" or getmetatable(snapshot) ~= nil then
		return nil, "InvalidReplayRecording"
	end
	local cloneOk, current = pcall(Serializer.CloneSerializable, snapshot)
	if not cloneOk then return nil, tostring(current) end
	if migrations ~= nil and type(migrations) ~= "table" then
		return nil, "InvalidReplayMigrations"
	end
	migrations = migrations or {}
	if not validFrame(current.Version) then return nil, "InvalidReplayRecordingVersion" end
	while type(current.Version) == "number" and current.Version < Recording.Version do
		local migrate = migrations[current.Version]
		if type(migrate) ~= "function" then return nil, "UnsupportedReplayRecordingVersion" end
		local ok, migrated = pcall(migrate, Serializer.CloneSerializable(current))
		if not ok then return nil, "ReplayMigrationFailed:" .. tostring(migrated) end
		if type(migrated) ~= "table" or migrated.Version ~= current.Version + 1 then
			return nil, "ReplayMigrationMustAdvanceExactlyOneVersion"
		end
		current = migrated
	end
	if current.Version ~= Recording.Version then return nil, "UnsupportedReplayRecordingVersion" end
	local valid, detail = validateSnapshot(current)
	if not valid then return nil, detail end
	local recording
	local ok, result = pcall(Recording.new, {
		Metadata = current.Metadata,
		InitialState = current.InitialState,
		ExternalFacts = current.ExternalFacts,
	})
	if not ok then return nil, tostring(result) end
	recording = result
	local previous = recording.Metadata.StartFrame
	for _, frame in ipairs(current.Frames) do
		if type(frame) ~= "table" or frame.Frame ~= previous + 1
			or type(frame.Inputs) ~= "table"
			or type(frame.StateHash) ~= "string" or frame.StateHash == ""
			or (frame.ExternalFacts ~= nil and type(frame.ExternalFacts) ~= "table") then
			return nil, "InvalidReplayFrame"
		end
		for key in pairs(frame) do
			if key ~= "Frame" and key ~= "Inputs" and key ~= "StateHash" and key ~= "ExternalFacts" then
				return nil, "UnknownReplayFrameField:" .. tostring(key)
			end
		end
		local appended, appendError = pcall(recording.AppendFrame, recording,
			frame.Frame, frame.Inputs, frame.StateHash, frame.ExternalFacts)
		if not appended then return nil, tostring(appendError) end
		previous = frame.Frame
	end
	return recording
end

function Recording:FindFirstDivergence(other)
	if getmetatable(other) ~= Recording then return nil, "InvalidReplayRecording" end
	if self.Metadata.ContentFingerprint ~= other.Metadata.ContentFingerprint then
		return nil, "ContentFingerprintMismatch"
	end
	if self.Metadata.StartFrame ~= other.Metadata.StartFrame then return nil, "StartFrameMismatch" end
	if Serializer.Serialize(self.Metadata) ~= Serializer.Serialize(other.Metadata) then
		return nil, "MetadataMismatch"
	end
	if Serializer.Serialize(self.ExternalFacts) ~= Serializer.Serialize(other.ExternalFacts) then
		return nil, "ExternalFactsMismatch"
	end
	if Serializer.Serialize(self.InitialState) ~= Serializer.Serialize(other.InitialState) then
		return self.Metadata.StartFrame, {
			Reason = "InitialStateMismatch",
			ExpectedHash = nil,
			ActualHash = nil,
		}
	end
	local common = math.min(#self.Frames, #other.Frames)
	for index = 1, common do
		local expected, actual = self.Frames[index], other.Frames[index]
		if Serializer.Serialize(expected.Inputs) ~= Serializer.Serialize(actual.Inputs) then
			return expected.Frame, {
				Reason = "InputMismatch",
				ExpectedHash = expected.StateHash,
				ActualHash = actual.StateHash,
			}
		end
		if Serializer.Serialize(expected.ExternalFacts) ~= Serializer.Serialize(actual.ExternalFacts) then
			return expected.Frame, {
				Reason = "ExternalFactsMismatch",
				ExpectedHash = expected.StateHash,
				ActualHash = actual.StateHash,
			}
		end
		if expected.StateHash ~= actual.StateHash then
			return expected.Frame, {
				Reason = "StateHashMismatch",
				ExpectedHash = expected.StateHash,
				ActualHash = actual.StateHash,
			}
		end
	end
	if #self.Frames ~= #other.Frames then
		local missing = self.Frames[common + 1] or other.Frames[common + 1]
		return missing.Frame, {
			Reason = "MissingFrame",
			ExpectedHash = self.Frames[common + 1] and self.Frames[common + 1].StateHash or nil,
			ActualHash = other.Frames[common + 1] and other.Frames[common + 1].StateHash or nil,
		}
	end
	return nil
end

return table.freeze(Recording)
