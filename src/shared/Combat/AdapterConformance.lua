local Serializer = require(script.Parent.Parent.Simulation.StateSerializer)

local Conformance = {}
Conformance.__index = Conformance
Conformance.Version = 1

Conformance.Context = table.freeze({
	Normal = "Normal",
	Prediction = "Prediction",
	Replay = "Replay",
	Rollback = "Rollback",
})

function Conformance.new()
	return setmetatable({ Adapters = {}, Versions = {} }, Conformance)
end

function Conformance:Register(id, options)
	options = options or {}
	assert(type(id) == "string" and id ~= "", "Adapter ID is required")
	assert(type(options) == "table", "Adapter conformance options must be a table")
	assert(self.Adapters[id] == nil, "Adapter conformance already registered")
	local contexts = options.Contexts or {}
	assert(type(contexts) == "table", "Adapter contexts must be a table")
	local normalizedContexts = {}
	for _, context in ipairs(contexts) do
		assert(context == Conformance.Context.Normal
			or context == Conformance.Context.Prediction
			or context == Conformance.Context.Replay
			or context == Conformance.Context.Rollback,
			"Unknown adapter execution context")
		assert(not normalizedContexts[context], "Duplicate adapter context")
		normalizedContexts[context] = true
	end
	local adapter = {
		Id = id,
		Version = options.Version or "1.0.0",
		Authoritative = options.Authoritative == true,
		Contexts = normalizedContexts,
		CaptureRollbackState = options.CaptureRollbackState,
		ValidateRollbackState = options.ValidateRollbackState,
		PrepareRollbackRestore = options.PrepareRollbackRestore,
		Cleanup = options.Cleanup,
		Adapter = options.Adapter,
	}
	self.Adapters[id] = adapter
	return adapter
end

function Conformance:Check(id)
	local adapter = self.Adapters[id]
	if not adapter then return nil, "AdapterNotRegistered" end
	local errors = {}
	if adapter.Authoritative then
		if type(adapter.CaptureRollbackState) ~= "function"
			or type(adapter.ValidateRollbackState) ~= "function"
			or type(adapter.PrepareRollbackRestore) ~= "function" then
			table.insert(errors, "Authoritative adapters must implement capture, validate and prepare")
		end
		if not adapter.Contexts[Conformance.Context.Rollback]
			or not adapter.Contexts[Conformance.Context.Replay] then
			table.insert(errors, "Authoritative adapters must support Replay and Rollback")
		end
	end
	if type(adapter.Adapter) == "table" then
		if type(adapter.Cleanup) ~= "function"
			and type(adapter.Adapter.Disconnect) ~= "function"
			and type(adapter.Adapter.Destroy) ~= "function" then
			table.insert(errors, "Adapters should expose cleanup or teardown")
		end
	end
	table.sort(errors)
	return table.freeze({
		Version = Conformance.Version,
		Id = adapter.Id,
		AdapterVersion = adapter.Version,
		Authoritative = adapter.Authoritative,
		Contexts = table.freeze(Serializer.CloneSerializable(
			(function()
				local list = {}
				for context in pairs(adapter.Contexts) do table.insert(list, context) end
				table.sort(list)
				return list
			end)())),
		Passed = #errors == 0,
		Errors = table.freeze(errors),
	})
end

function Conformance:Report()
	local list = {}
	for id in pairs(self.Adapters) do
		local report = self:Check(id)
		table.insert(list, report)
	end
	table.sort(list, function(left, right) return left.Id < right.Id end)
	local failed = 0
	for _, report in ipairs(list) do
		if not report.Passed then failed += 1 end
	end
	return table.freeze({
		Version = Conformance.Version,
		Passed = failed == 0,
		FailedCount = failed,
		Adapters = table.freeze(list),
	})
end

return Conformance
