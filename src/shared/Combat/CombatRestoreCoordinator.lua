-- Two-phase restore coordinator for deterministic, rollback-owned subsystem state.
-- Participants must be side-effect free during capture/validation/preparation and must
-- expose reversible, non-yielding commit closures. This does not make external side effects atomic.
local Serializer = require(script.Parent.Parent.Simulation.StateSerializer)

local Coordinator = {}
Coordinator.__index = Coordinator
Coordinator.Version = 1

local function isFiniteInteger(value)
	return type(value) == "number" and value == value and value ~= math.huge
		and value ~= -math.huge and value >= 0 and value % 1 == 0
end

local function callValidator(participant, state, context, label)
	local ok, accepted, detail = pcall(participant.ValidateRollbackState, participant, state, context)
	if not ok then return false, label .. " validation threw: " .. tostring(accepted) end
	if accepted ~= true then return false, label .. " rejected state: " .. tostring(detail) end
	return true
end

local function cloneState(state, options)
	return Serializer.CloneSerializable(state, options)
end

function Coordinator.new(options)
	options = options or {}
	assert(type(options) == "table", "CombatRestoreCoordinator.new expects an options table")
	return setmetatable({
		Participants = {},
		MaxSnapshotEntries = options.MaxSnapshotEntries or 100000,
		MaxSnapshotDepth = options.MaxSnapshotDepth or 64,
		IsPreparing = false,
		IsCommitting = false,
	}, Coordinator)
end

function Coordinator:Register(key, participant, order)
	assert(not self.IsPreparing and not self.IsCommitting, "Cannot register restore participants during a restore")
	assert(type(key) == "string" and key ~= "", "Participant key must be a non-empty string")
	assert(type(participant) == "table", "Participant must be a table")
	for _, method in ipairs({ "CaptureRollbackState", "ValidateRollbackState", "PrepareRollbackRestore" }) do
		assert(type(participant[method]) == "function", "Participant " .. key .. " must implement " .. method)
	end
	assert(order == nil or (type(order) == "number" and order == order and math.abs(order) < math.huge),
		"Participant order must be a finite number or nil")
	assert(not self.Participants[key], "Restore participant already registered: " .. key)
	self.Participants[key] = { Key = key, Instance = participant, Order = order or 0 }
	return self
end

function Coordinator:Unregister(key)
	assert(not self.IsPreparing and not self.IsCommitting, "Cannot change restore participants during a restore")
	if not self.Participants[key] then return false end
	self.Participants[key] = nil
	return true
end

function Coordinator:_orderedParticipants()
	local list = {}
	for _, entry in pairs(self.Participants) do table.insert(list, entry) end
	table.sort(list, function(a, b)
		if a.Order ~= b.Order then return a.Order < b.Order end
		return a.Key < b.Key
	end)
	return list
end

function Coordinator:Capture(context)
	assert(not self.IsPreparing and not self.IsCommitting, "Cannot capture during restore")
	local states = {}
	for _, entry in ipairs(self:_orderedParticipants()) do
		local ok, state = pcall(entry.Instance.CaptureRollbackState, entry.Instance, context)
		assert(ok, "Participant " .. entry.Key .. " capture failed: " .. tostring(state))
		assert(type(state) == "table", "Participant " .. entry.Key .. " must capture a table")
		local cloned = cloneState(state, {
			MaxEntries = self.MaxSnapshotEntries, MaxDepth = self.MaxSnapshotDepth,
		})
		local valid, reason = callValidator(entry.Instance, cloned, context, entry.Key)
		assert(valid, reason)
		states[entry.Key] = cloned
	end
	return Serializer.Freeze(cloneState({ Version = Coordinator.Version, Participants = states }, {
		MaxEntries = self.MaxSnapshotEntries, MaxDepth = self.MaxSnapshotDepth,
	}))
end

function Coordinator:Validate(snapshot, context)
	if type(snapshot) ~= "table" or getmetatable(snapshot) ~= nil then
		return false, "Restore snapshot must be a plain table"
	end
	if snapshot.Version ~= Coordinator.Version then return false, "Unsupported restore coordinator snapshot version" end
	for key in pairs(snapshot) do
		if key ~= "Version" and key ~= "Participants" then return false, "Unknown restore snapshot field: " .. tostring(key) end
	end
	if type(snapshot.Participants) ~= "table" or getmetatable(snapshot.Participants) ~= nil then
		return false, "Snapshot Participants must be a plain table"
	end
	for key in pairs(self.Participants) do
		if snapshot.Participants[key] == nil then return false, "Snapshot missing participant: " .. key end
	end
	for key, state in pairs(snapshot.Participants) do
		if not self.Participants[key] then return false, "Snapshot contains unregistered participant: " .. tostring(key) end
		if type(state) ~= "table" or getmetatable(state) ~= nil then
			return false, "Participant state must be a plain table: " .. tostring(key)
		end
	end
	local cloneOk, cloneError = pcall(cloneState, snapshot, {
		MaxEntries = self.MaxSnapshotEntries, MaxDepth = self.MaxSnapshotDepth,
	})
	if not cloneOk then return false, "Snapshot serialization rejected: " .. tostring(cloneError) end
	for _, entry in ipairs(self:_orderedParticipants()) do
		local valid, reason = callValidator(entry.Instance, snapshot.Participants[entry.Key], context, entry.Key)
		if not valid then return false, reason end
	end
	return true
end

-- Prepares both target commits and compensating commits before any live state is changed.
-- Returned transaction is single-use. All commits must be deterministic, non-yielding, and
-- limited to rollback-owned state; irreversible external effects are outside this contract.
function Coordinator:Prepare(snapshot, context)
	if self.IsPreparing or self.IsCommitting then return nil, "RestoreAlreadyInProgress" end
	self.IsPreparing = true
	local valid, validationError = self:Validate(snapshot, context)
	if not valid then
		self.IsPreparing = false
		return nil, validationError
	end
	local targetCommits, compensationCommits, entries = {}, {}, self:_orderedParticipants()
	local ok, prepareError = pcall(function()
		for _, entry in ipairs(entries) do
			local participant = entry.Instance
			local targetState = cloneState(snapshot.Participants[entry.Key], {
				MaxEntries = self.MaxSnapshotEntries, MaxDepth = self.MaxSnapshotDepth,
			})
			local targetCommit, targetError = participant:PrepareRollbackRestore(targetState, context, "Target")
			assert(type(targetCommit) == "function", "Target preparation failed for " .. entry.Key .. ": " .. tostring(targetError))
			targetCommits[entry.Key] = targetCommit

			local currentState = participant:CaptureRollbackState(context)
			assert(type(currentState) == "table", "Compensation capture failed for " .. entry.Key)
			local currentValid, currentReason = callValidator(participant, currentState, context, entry.Key .. " current state")
			assert(currentValid, currentReason)
			local compensationCommit, compensationError = participant:PrepareRollbackRestore(
				cloneState(currentState, { MaxEntries = self.MaxSnapshotEntries, MaxDepth = self.MaxSnapshotDepth }), context, "Compensation")
			assert(type(compensationCommit) == "function",
				"Compensation preparation failed for " .. entry.Key .. ": " .. tostring(compensationError))
			compensationCommits[entry.Key] = compensationCommit
		end
	end)
	self.IsPreparing = false
	if not ok then return nil, tostring(prepareError) end

	local coordinator = self
	local transaction = { Used = false, PreparedParticipantKeys = {} }
	for _, entry in ipairs(entries) do table.insert(transaction.PreparedParticipantKeys, entry.Key) end

	function transaction:Commit()
		if self.Used then return false, "RestoreTransactionAlreadyUsed" end
		if coordinator.IsPreparing or coordinator.IsCommitting then return false, "RestoreAlreadyInProgress" end
		self.Used = true
		coordinator.IsCommitting = true
		local committed = {}
		local failedKey, commitError
		for _, entry in ipairs(entries) do
			-- Include the current participant in compensation because a broken commit can mutate
			-- before throwing. Participants are contractually forbidden from doing so.
			table.insert(committed, entry.Key)
			local commitOk, result = pcall(targetCommits[entry.Key])
			if not commitOk then failedKey, commitError = entry.Key, result; break end
		end
		if not failedKey then
			coordinator.IsCommitting = false
			return true
		end
		local compensationFailures = {}
		for index = #committed, 1, -1 do
			local key = committed[index]
			local compensationOk, compensationError = pcall(compensationCommits[key])
			if not compensationOk then
				table.insert(compensationFailures, key .. ": " .. tostring(compensationError))
			end
		end
		coordinator.IsCommitting = false
		if #compensationFailures > 0 then
			return false, "Commit failed at " .. failedKey .. "; compensation incomplete: "
				.. table.concat(compensationFailures, "; ") .. "; original error: " .. tostring(commitError)
		end
		return false, "Commit failed at " .. failedKey .. "; all committed participants compensated: " .. tostring(commitError)
	end

	return transaction
end

function Coordinator:Restore(snapshot, context)
	local transaction, reason = self:Prepare(snapshot, context)
	if not transaction then return false, reason end
	return transaction:Commit()
end

return Coordinator
