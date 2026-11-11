local Serializer = require(script.Parent.Parent.Simulation.StateSerializer)

local Journal = {}
Journal.__index = Journal
Journal.Version = 1

local function validFrame(frame)
	return type(frame) == "number" and frame == frame and frame >= 0
		and frame < math.huge and frame % 1 == 0
end

local function validId(value)
	return type(value) == "string" and value ~= ""
end

local function validVersion(value)
	return type(value) == "string" and value ~= ""
		or type(value) == "number" and value == value and value >= 0
			and value < math.huge and value % 1 == 0
end

local function cloneData(value, options, label)
	local ok, cloned = pcall(Serializer.CloneSerializable, value, options)
	if not ok then
		return nil, label .. " is not serializable: " .. tostring(cloned)
	end
	if type(cloned) ~= "table" then
		return nil, label .. " must be a table"
	end
	return cloned
end

local function compareFacts(left, right)
	if left.Frame ~= right.Frame then
		return left.Frame < right.Frame
	end
	return left.QueryId < right.QueryId
end

function Journal.new(world, options)
	options = options or {}
	local maxFacts = options.MaxFacts or 100000
	assert(type(maxFacts) == "number" and maxFacts >= 1 and maxFacts % 1 == 0,
		"ExternalFactJournal MaxFacts must be a positive integer")
	return setmetatable({
		World = world,
		MaxFacts = maxFacts,
		FrameFacts = {},
		FactCount = 0,
		Migrations = {},
	}, Journal)
end

function Journal:_executionContext()
	return self.World and self.World:GetExecutionContext() or "Normal"
end

function Journal:_canMutate()
	local context = self:_executionContext()
	return context == "Normal" or context == "Authority", "CannotMutateExternalFactJournalDuring" .. tostring(context)
end

function Journal:_validateIdentity(frame, queryId, adapterId, adapterVersion)
	if not validFrame(frame) then return false, "InvalidFrame" end
	if not validId(queryId) then return false, "InvalidQueryId" end
	if not validId(adapterId) then return false, "InvalidAdapterId" end
	if not validVersion(adapterVersion) then return false, "InvalidAdapterVersion" end
	return true
end

function Journal:Record(frame, queryId, adapterId, adapterVersion, request, outcome)
	local valid, reason = self:_validateIdentity(frame, queryId, adapterId, adapterVersion)
	if not valid then return false, reason end
	local canMutate = self:_canMutate()
	if not canMutate then
		return false, "CannotRecordExternalFactDuring" .. tostring(self:_executionContext())
	end
	local requests, requestError = cloneData(request, nil, "External fact request")
	if not requests then return false, requestError end
	local outcomeCopy, outcomeError = cloneData(outcome, nil, "External fact outcome")
	if not outcomeCopy then return false, outcomeError end
	local facts = self.FrameFacts[frame]
	if facts and facts[queryId] then return false, "DuplicateExternalFact" end
	if self.FactCount >= self.MaxFacts then return false, "JournalCapacityExceeded" end
	if not facts then
		facts = {}
		self.FrameFacts[frame] = facts
	end
	facts[queryId] = {
		Frame = frame,
		QueryId = queryId,
		AdapterId = adapterId,
		AdapterVersion = adapterVersion,
		Request = requests,
		Outcome = outcomeCopy,
	}
	self.FactCount += 1
	return true
end

function Journal:Read(frame, queryId, adapterId, adapterVersion, request)
	local valid, reason = self:_validateIdentity(frame, queryId, adapterId, adapterVersion)
	if not valid then return nil, reason end
	local requests, requestError = cloneData(request, nil, "External fact request")
	if not requests then return nil, requestError end
	local facts = self.FrameFacts[frame]
	local fact = facts and facts[queryId]
	if not fact then return nil, "MissingExternalFact" end
	if fact.AdapterId ~= adapterId or fact.AdapterVersion ~= adapterVersion then
		return nil, "ExternalFactAdapterMismatch"
	end
	local recordedRequest = Serializer.Serialize(fact.Request)
	local currentRequest = Serializer.Serialize(requests)
	if recordedRequest ~= currentRequest then return nil, "ExternalFactRequestMismatch" end
	return Serializer.CloneSerializable(fact.Outcome)
end

function Journal:Resolve(frame, queryId, adapterId, adapterVersion, request, query)
	local context = self:_executionContext()
	if context == "Rollback" or context == "Replay" or context == "Prediction" then
		return self:Read(frame, queryId, adapterId, adapterVersion, request)
	end
	if context ~= "Normal" and context ~= "Authority" then
		return nil, "UnsupportedExternalFactExecutionContext:" .. tostring(context)
	end
	if type(query) ~= "function" then return nil, "ExternalFactQueryFunctionRequired" end
	local outcome = query()
	local recorded, reason = self:Record(frame, queryId, adapterId, adapterVersion, request, outcome)
	if not recorded then return nil, reason end
	return Serializer.CloneSerializable(outcome)
end

function Journal:PruneBefore(frame)
	if not validFrame(frame) then return false, "InvalidFrame" end
	local canMutate, mutationError = self:_canMutate()
	if not canMutate then return false, mutationError end
	for savedFrame, facts in pairs(self.FrameFacts) do
		if savedFrame < frame then
			for _ in pairs(facts) do self.FactCount -= 1 end
			self.FrameFacts[savedFrame] = nil
		end
	end
	return true
end

function Journal:Capture()
	local facts = {}
	for _, frameFacts in pairs(self.FrameFacts) do
		for _, fact in pairs(frameFacts) do
			table.insert(facts, Serializer.CloneSerializable(fact))
		end
	end
	table.sort(facts, compareFacts)
	return Serializer.Freeze({
		Version = Journal.Version,
		Facts = facts,
	})
end

function Journal:Validate(snapshot)
	if type(snapshot) ~= "table" or getmetatable(snapshot) ~= nil then
		return false, "External fact journal must be a plain table"
	end
	if snapshot.Version ~= Journal.Version then return false, "Unsupported external fact journal version" end
	for key in pairs(snapshot) do
		if key ~= "Version" and key ~= "Facts" then
			return false, "Unknown external fact journal field: " .. tostring(key)
		end
	end
	if type(snapshot.Facts) ~= "table" then return false, "External fact Facts must be a table" end
	local seen, previous, count = {}, nil, 0
	for index, fact in ipairs(snapshot.Facts) do
		if type(fact) ~= "table" or getmetatable(fact) ~= nil then
			return false, "Invalid external fact at index " .. tostring(index)
		end
		local valid, reason = self:_validateIdentity(
			fact.Frame, fact.QueryId, fact.AdapterId, fact.AdapterVersion)
		if not valid then return false, reason .. " at fact " .. tostring(index) end
		if type(fact.Request) ~= "table" or type(fact.Outcome) ~= "table" then
			return false, "External fact request and outcome must be tables"
		end
		if previous and not compareFacts(previous, fact) then
			return false, "External facts are not in canonical order"
		end
		local key = tostring(fact.Frame) .. "\0" .. fact.QueryId
		if seen[key] then return false, "Duplicate external fact identity" end
		seen[key] = true
		previous = fact
		count += 1
		if count > self.MaxFacts then return false, "JournalCapacityExceeded" end
	end
	local denseCount, maxIndex = 0, 0
	for key in pairs(snapshot.Facts) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return false, "External fact list must be dense"
		end
		denseCount += 1
		if key > maxIndex then maxIndex = key end
	end
	if denseCount ~= maxIndex then return false, "External fact list must be dense" end
	local ok, detail = pcall(Serializer.CloneSerializable, snapshot)
	if not ok then return false, "External fact serialization rejected: " .. tostring(detail) end
	return true
end

function Journal:RegisterMigration(fromVersion, migrate)
	assert(type(fromVersion) == "number" and fromVersion >= 1
		and fromVersion < Journal.Version and fromVersion % 1 == 0,
		"External fact migration source version must be older than the current version")
	assert(type(migrate) == "function", "External fact migration must be a function")
	assert(not self.Migrations[fromVersion], "External fact migration already registered")
	self.Migrations[fromVersion] = migrate
	return self
end

function Journal:Migrate(snapshot)
	if type(snapshot) ~= "table" or type(snapshot.Version) ~= "number" then
		return nil, "InvalidExternalFactJournal"
	end
	if snapshot.Version > Journal.Version then return nil, "UnsupportedExternalFactJournalVersion" end
	local migrated
	local ok, detail = pcall(Serializer.CloneSerializable, snapshot)
	if not ok then return nil, "ExternalFactSerializationRejected:" .. tostring(detail) end
	migrated = detail
	while migrated.Version < Journal.Version do
		local migration = self.Migrations[migrated.Version]
		if not migration then
			return nil, "MissingExternalFactMigrationFromVersion:" .. tostring(migrated.Version)
		end
		local migratedOk, nextSnapshot = pcall(migration, Serializer.CloneSerializable(migrated))
		if not migratedOk then return nil, "ExternalFactMigrationFailed:" .. tostring(nextSnapshot) end
		if type(nextSnapshot) ~= "table" or nextSnapshot.Version ~= migrated.Version + 1 then
			return nil, "ExternalFactMigrationMustAdvanceExactlyOneVersion"
		end
		local cloneOk, clone = pcall(Serializer.CloneSerializable, nextSnapshot)
		if not cloneOk then return nil, "ExternalFactMigrationProducedInvalidData:" .. tostring(clone) end
		migrated = clone
	end
	return migrated
end

function Journal:Import(snapshot)
	local canMutate, mutationError = self:_canMutate()
	if not canMutate then return false, mutationError end
	local migrated, migrationError = self:Migrate(snapshot)
	if not migrated then return false, migrationError end
	local valid, validationError = self:Validate(migrated)
	if not valid then return false, validationError end
	local frameFacts, count = {}, 0
	for _, fact in ipairs(migrated.Facts) do
		frameFacts[fact.Frame] = frameFacts[fact.Frame] or {}
		frameFacts[fact.Frame][fact.QueryId] = {
			Frame = fact.Frame,
			QueryId = fact.QueryId,
			AdapterId = fact.AdapterId,
			AdapterVersion = fact.AdapterVersion,
			Request = Serializer.CloneSerializable(fact.Request),
			Outcome = Serializer.CloneSerializable(fact.Outcome),
		}
		count += 1
	end
	self.FrameFacts = frameFacts
	self.FactCount = count
	return true
end

function Journal:Clear()
	local canMutate, mutationError = self:_canMutate()
	if not canMutate then return false, mutationError end
	self.FrameFacts = {}
	self.FactCount = 0
	return self
end

return table.freeze(Journal)
