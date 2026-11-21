local ExternalFactJournal = require(script.Parent.Parent.Events.ExternalFactJournal)
local Serializer = require(script.Parent.Parent.Simulation.StateSerializer)

local SceneQuery = {}
SceneQuery.__index = SceneQuery
SceneQuery.MissingPolicy = table.freeze({
	Reject = "Reject",
	Deny = "Deny",
	Unavailable = "Unavailable",
})

function SceneQuery.new(world, options)
	options = options or {}
	assert(type(options) == "table", "SceneQuery.new expects an options table")
	local missingPolicy = options.MissingPolicy or SceneQuery.MissingPolicy.Reject
	assert(missingPolicy == SceneQuery.MissingPolicy.Reject
		or missingPolicy == SceneQuery.MissingPolicy.Deny
		or missingPolicy == SceneQuery.MissingPolicy.Unavailable,
		"SceneQuery MissingPolicy is invalid")
	return setmetatable({
		World = world,
		Journal = options.Journal or ExternalFactJournal.new(world),
		MissingPolicy = missingPolicy,
		Queries = {},
	}, SceneQuery)
end

function SceneQuery:GetJournal()
	return self.Journal
end

function SceneQuery:Resolve(frame, queryId, adapterId, adapterVersion, request, query)
	local outcome, reason = self.Journal:Resolve(
		frame, queryId, adapterId, adapterVersion, request, query)
	if outcome ~= nil then
		self.Queries[queryId] = {
			Frame = frame,
			QueryId = queryId,
			AdapterId = adapterId,
			AdapterVersion = adapterVersion,
			Request = Serializer.CloneSerializable(request),
			Outcome = Serializer.CloneSerializable(outcome),
		}
		return outcome
	end
	if reason == "MissingExternalFact" or reason == "ExternalFactRequestMismatch"
		or reason == "ExternalFactAdapterMismatch" then
		if self.MissingPolicy == SceneQuery.MissingPolicy.Deny then
			return nil, "Deny"
		elseif self.MissingPolicy == SceneQuery.MissingPolicy.Unavailable then
			return nil, "Unavailable"
		end
	end
	return nil, reason
end

function SceneQuery:GetQuery(queryId)
	local entry = self.Queries[queryId]
	return entry and Serializer.CloneSerializable(entry) or nil
end

function SceneQuery:Capture()
	return Serializer.Freeze({
		Version = 1,
		MissingPolicy = self.MissingPolicy,
		Journal = self.Journal:Capture(),
	})
end

return SceneQuery
