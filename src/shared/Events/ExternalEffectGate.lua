local Gate = {}
Gate.__index = Gate

function Gate.new(world)
	return setmetatable({
		World = world,
		Committed = {},
		Results = {},
	}, Gate)
end

function Gate:Emit(effectId, callback)
	if type(effectId) ~= "string" or effectId == "" then
		return false, "InvalidEffectId"
	end
	if callback ~= nil and type(callback) ~= "function" then
		return false, "InvalidCallback"
	end
	local context = self.World:GetExecutionContext()
	if context == "Rollback" or context == "Replay" then
		local result = { EffectId = effectId, Suppressed = true, Context = context }
		table.insert(self.Results, result)
		return true, result
	end
	if self.Committed[effectId] then
		local result = { EffectId = effectId, Duplicate = true, Context = context }
		table.insert(self.Results, result)
		return true, result
	end
	if callback then
		local ok, detail = pcall(callback)
		if not ok then return false, tostring(detail) end
	end
	self.Committed[effectId] = true
	local result = { EffectId = effectId, Emitted = true, Context = context }
	table.insert(self.Results, result)
	return true, result
end

function Gate:HasEmitted(effectId)
	return self.Committed[effectId] == true
end

function Gate:GetResults()
	return table.clone(self.Results)
end

function Gate:GetSuppressedEffects()
	local suppressed = {}
	for _, result in ipairs(self.Results) do
		if result.Suppressed then table.insert(suppressed, result) end
	end
	return suppressed
end

function Gate:ClearResults()
	table.clear(self.Results)
	return self
end

return Gate
