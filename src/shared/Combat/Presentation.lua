local Serializer = require(script.Parent.Parent.Simulation.StateSerializer)

local Presentation = {}
Presentation.__index = Presentation
Presentation.State = table.freeze({
	Speculative = "Speculative",
	Confirmed = "Confirmed",
	Cancelled = "Cancelled",
	Replaced = "Replaced",
})

function Presentation.new()
	return setmetatable({ Effects = {}, Order = 0 }, Presentation)
end

function Presentation:Create(effectId, kind, payload)
	assert(type(effectId) == "string" and effectId ~= "", "Presentation effect Id is required")
	assert(type(kind) == "string" and kind ~= "", "Presentation effect kind is required")
	assert(payload == nil or type(payload) == "table", "Presentation payload must be a table or nil")
	assert(not self.Effects[effectId], "Presentation effect already exists")
	local copy = payload == nil and {} or Serializer.CloneSerializable(payload)
	self.Order += 1
	self.Effects[effectId] = table.freeze({
		Id = effectId,
		Kind = kind,
		Payload = Serializer.Freeze(copy),
		State = Presentation.State.Speculative,
		Order = self.Order,
	})
	return effectId
end

function Presentation:_transition(effectId, state)
	local effect = self.Effects[effectId]
	if not effect then return false, "PresentationEffectNotFound" end
	if effect.State == state then return true end
	if effect.State == Presentation.State.Cancelled
		or effect.State == Presentation.State.Replaced then
		return false, "PresentationEffectFinal"
	end
	self.Effects[effectId] = table.freeze({
		Id = effect.Id,
		Kind = effect.Kind,
		Payload = effect.Payload,
		State = state,
		Order = effect.Order,
	})
	return true
end

function Presentation:Confirm(effectId)
	return self:_transition(effectId, Presentation.State.Confirmed)
end

function Presentation:Cancel(effectId)
	return self:_transition(effectId, Presentation.State.Cancelled)
end

function Presentation:Replace(effectId, replacementKind, replacementPayload)
	local effect = self.Effects[effectId]
	if not effect then return false, "PresentationEffectNotFound" end
	local replacementId = effectId .. ":replace:" .. tostring(self.Order + 1)
	self:_transition(effectId, Presentation.State.Replaced)
	self:Create(replacementId, replacementKind, replacementPayload)
	return true, replacementId
end

function Presentation:Get(effectId)
	local effect = self.Effects[effectId]
	return effect and Serializer.CloneSerializable(effect) or nil
end

function Presentation:List(state)
	local result = {}
	for _, effect in pairs(self.Effects) do
		if state == nil or effect.State == state then
			table.insert(result, Serializer.CloneSerializable(effect))
		end
	end
	table.sort(result, function(left, right)
		return left.Order < right.Order
	end)
	return table.freeze(result)
end

function Presentation:ClearFinal()
	for effectId, effect in pairs(self.Effects) do
		if effect.State == Presentation.State.Confirmed
			or effect.State == Presentation.State.Cancelled
			or effect.State == Presentation.State.Replaced then
			self.Effects[effectId] = nil
		end
	end
end

function Presentation:InterpolatePosition(fromPosition, toPosition, alpha)
	assert(typeof(fromPosition) == "Vector3"
		and typeof(toPosition) == "Vector3",
		"Presentation interpolation requires Vector3 positions")
	assert(type(alpha) == "number" and alpha >= 0 and alpha <= 1,
		"Presentation interpolation alpha must be between zero and one")
	return fromPosition:Lerp(toPosition, alpha)
end

function Presentation:InterpolateCFrame(fromCFrame, toCFrame, alpha)
	assert(typeof(fromCFrame) == "CFrame"
		and typeof(toCFrame) == "CFrame",
		"Presentation interpolation requires CFrame values")
	assert(type(alpha) == "number" and alpha >= 0 and alpha <= 1,
		"Presentation interpolation alpha must be between zero and one")
	return fromCFrame:Lerp(toCFrame, alpha)
end

return Presentation
