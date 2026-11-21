local RestoreReadiness = {}
RestoreReadiness.__index = RestoreReadiness
RestoreReadiness.Version = 1

function RestoreReadiness.new()
	return setmetatable({
		Participants = {},
		ExternalDependencies = {},
	}, RestoreReadiness)
end

function RestoreReadiness:RegisterParticipant(key, participant)
	assert(type(key) == "string" and key ~= "", "Restore participant key is required")
	assert(type(participant) == "table", "Restore participant must be a table")
	for _, method in ipairs({ "CaptureRollbackState", "ValidateRollbackState", "PrepareRollbackRestore" }) do
		assert(type(participant[method]) == "function",
			("Restore participant %s must implement %s"):format(key, method))
	end
	self.Participants[key] = participant
	return self
end

function RestoreReadiness:AddExternalDependency(queryId, adapterId, adapterVersion)
	assert(type(queryId) == "string" and queryId ~= "", "External query ID is required")
	assert(type(adapterId) == "string" and adapterId ~= "", "External adapter ID is required")
	assert(type(adapterVersion) == "string" or type(adapterVersion) == "number",
		"External adapter version is required")
	self.ExternalDependencies[queryId] = {
		QueryId = queryId,
		AdapterId = adapterId,
		AdapterVersion = adapterVersion,
	}
	return self
end

function RestoreReadiness:Report(context)
	local ready = {}
	local blocked = {}
	for key in pairs(self.Participants) do
		local participant = self.Participants[key]
		local captureOk, captureState = pcall(participant.CaptureRollbackState, participant, context)
		local validateOk, valid, detail
		if captureOk then
			validateOk, valid, detail = pcall(
				participant.ValidateRollbackState, participant, captureState, context)
			if not validateOk then
				valid = false
				detail = "validation threw"
			elseif valid ~= true then
				detail = detail or "validation rejected state"
			end
		else
			valid = false
			detail = "capture threw"
		end
		if valid then
			table.insert(ready, key)
		else
			table.insert(blocked, { Key = key, Reason = tostring(detail or "Unknown") })
		end
	end
	table.sort(ready)
	table.sort(blocked, function(left, right) return left.Key < right.Key end)
	local dependencies = {}
	for _, dependency in pairs(self.ExternalDependencies) do
		table.insert(dependencies, {
			QueryId = dependency.QueryId,
			AdapterId = dependency.AdapterId,
			AdapterVersion = dependency.AdapterVersion,
		})
	end
	table.sort(dependencies, function(left, right) return left.QueryId < right.QueryId end)
	return table.freeze({
		Version = RestoreReadiness.Version,
		Ready = table.freeze(ready),
		Blocked = table.freeze(blocked),
		ExternalDependencies = table.freeze(dependencies),
		CanRestore = #blocked == 0,
	})
end

return RestoreReadiness
