local NetworkSnapshot = require(script.Parent.NetworkSnapshot)
local Result = require(script.Parent.ReconciliationResult)

local Resolver = {}
Resolver.__index = Resolver

local function validFrame(frame)
	return type(frame) == "number" and frame == frame and frame >= 0
		and frame < math.huge and frame % 1 == 0
end

local function validSequence(sequence)
	return sequence == nil or (type(sequence) == "number" and sequence == sequence
		and sequence >= 0 and sequence < math.huge and sequence % 1 == 0)
end

function Resolver.new(world, options)
	assert(world and type(world.GetPredictionResolver) == "function",
		"ReconciliationResolver.new() requires a World")
	options = options or {}
	assert(type(options) == "table", "ReconciliationResolver.new() expects options")
	assert(options.ApplySnapshot == nil or type(options.ApplySnapshot) == "function",
		"ReconciliationResolver ApplySnapshot must be a function or nil")
	return setmetatable({
		World = world,
		ApplySnapshot = options.ApplySnapshot,
		LastSequence = nil,
		LastFrame = nil,
		Results = {},
	}, Resolver)
end

function Resolver:_result(kind, data)
	data = data or {}
	data.Type = kind
	local result = Result.new(data)
	table.insert(self.Results, result)
	return result
end

function Resolver:Reconcile(snapshot)
	if getmetatable(snapshot) ~= NetworkSnapshot
		or not validFrame(snapshot.SimulationFrame)
		or not validSequence(snapshot.Sequence) then
		return self:_result(Result.Type.InvalidSnapshot, { Snapshot = snapshot })
	end
	if self.LastSequence ~= nil and snapshot.Sequence ~= nil and snapshot.Sequence <= self.LastSequence then
		return self:_result(Result.Type.Duplicate, {
			Frame = snapshot.SimulationFrame, Sequence = snapshot.Sequence,
		})
	end
	if self.LastFrame ~= nil and snapshot.SimulationFrame < self.LastFrame then
		return self:_result(Result.Type.Duplicate, { Frame = snapshot.SimulationFrame })
	end

	local prediction = self.World:GetPredictionResolver()
	local comparison = nil
	if prediction then
		local ok, value = pcall(prediction.CompareSnapshot, prediction, snapshot)
		if not ok then
			return self:_result(Result.Type.CompareFailed, {
				Frame = snapshot.SimulationFrame, Detail = tostring(value),
			})
		end
		comparison = value
	end

	local divergences = comparison and comparison.Divergences or nil
	local hasDivergence = type(divergences) == "table" and #divergences > 0

	if not hasDivergence then
		self.LastSequence = snapshot.Sequence or self.LastSequence
		self.LastFrame = snapshot.SimulationFrame
		return self:_result(Result.Type.Matched, {
			Frame = snapshot.SimulationFrame, Sequence = snapshot.Sequence,
			Divergences = divergences or {},
		})
	end
	if type(self.ApplySnapshot) ~= "function" then
		return self:_result(Result.Type.MissingAdapter, {
			Frame = snapshot.SimulationFrame, Sequence = snapshot.Sequence,
			Divergences = divergences,
		})
	end

	local ok, detail = pcall(self.ApplySnapshot, snapshot, divergences)
	if not ok or detail == false then
		return self:_result(Result.Type.AdapterFailed, {
			Frame = snapshot.SimulationFrame, Sequence = snapshot.Sequence,
			Divergences = divergences, Detail = tostring(ok and detail or detail),
		})
	end
	self.LastSequence = snapshot.Sequence or self.LastSequence
	self.LastFrame = snapshot.SimulationFrame
	return self:_result(Result.Type.Applied, {
		Frame = snapshot.SimulationFrame, Sequence = snapshot.Sequence,
		Divergences = divergences,
	})
end

function Resolver:GetResults()
	local results = {}
	for _, result in ipairs(self.Results) do table.insert(results, result) end
	return results
end

function Resolver:Clear()
	self.Results = {}
	return self
end

return Resolver
