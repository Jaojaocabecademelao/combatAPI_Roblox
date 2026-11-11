local Input = require(script.Parent.Input)
local InputState = require(script.Parent.InputState)
local AuthorityInput = require(script.Parent.AuthorityInput)
local NetworkMessage = require(script.Parent.NetworkMessage)
local NetworkChannel = require(script.Parent.NetworkChannel)

local Validation = {}
local validInputs, validStates = {}, {}
for _, value in pairs(Input) do validInputs[value] = true end
for _, value in pairs(InputState) do validStates[value] = true end

local function finiteInteger(value, minimum, maximum)
	return type(value) == "number" and value == value and value >= minimum
		and value <= maximum and value < math.huge and value % 1 == 0
end

local function validId(value)
	if type(value) == "string" then return value ~= "" and #value <= 128 end
	return finiteInteger(value, 0, math.huge)
end

local function exactKeys(value, allowed)
	for key in pairs(value) do
		if not allowed[key] then return false, key end
	end
	return true
end

local function copyInputs(inputs, inputProfile)
	if type(inputs) ~= "table" or getmetatable(inputs) ~= nil then
		return nil, "MalformedInputs"
	end
	local count, copied = 0, {}
	for inputId, state in pairs(inputs) do
		count += 1
		if count > 13 or type(inputId) ~= "string" or not validInputs[inputId]
			or not inputProfile:IsValidInput(inputId) or not validStates[state] then
			return nil, "InvalidInput"
		end
		copied[inputId] = state
	end
	return copied
end

function Validation.Parse(value, profile, inputProfile, peerId)
	local frame, sequence, entityId, inputs
	if getmetatable(value) == AuthorityInput then
		frame, sequence, entityId, inputs = value.SimulationFrame, value.NetworkSequence, value.EntityId, value.Inputs
	elseif getmetatable(value) == NetworkMessage then
		if value.Type ~= NetworkMessage.Type.Input or value.Channel ~= NetworkChannel.Input
			or type(value.Payload) ~= "table" or getmetatable(value.Payload) ~= nil then
			return nil, "InvalidInput"
		end
		frame, sequence = value.SimulationFrame, value.Sequence
		local ok, badKey = exactKeys(value.Payload, { EntityId = true, Inputs = true })
		if not ok then return nil, "ForbiddenField:" .. tostring(badKey) end
		entityId, inputs = value.Payload.EntityId, value.Payload.Inputs
	elseif type(value) == "table" and getmetatable(value) == nil then
		local ok, badKey = exactKeys(value, {
			EntityId = true, SimulationFrame = true, NetworkSequence = true, Inputs = true,
		})
		if not ok then return nil, "ForbiddenField:" .. tostring(badKey) end
		frame, sequence, entityId, inputs = value.SimulationFrame, value.NetworkSequence,
			value.EntityId, value.Inputs
	else
		return nil, "MalformedPayload"
	end
	if not finiteInteger(frame, 0, math.huge) then return nil, "InvalidFrame" end
	if peerId ~= nil and not finiteInteger(sequence, 0, 4294967295) then
		return nil, "InvalidSequence"
	end
	if peerId == nil and sequence ~= nil and not finiteInteger(sequence, 0, 4294967295) then
		return nil, "InvalidSequence"
	end
	if entityId ~= nil and not validId(entityId) then
		return nil, "InvalidEntity"
	end
	local copied, failure = copyInputs(inputs, inputProfile)
	if not copied then return nil, failure end
	local parsed = AuthorityInput.new({
		EntityId = entityId, SimulationFrame = frame, NetworkSequence = sequence,
		Inputs = copied, Source = peerId == nil and "Server" or "Peer",
	})
	return parsed
end

function Validation.IsValidFrame(value)
	return finiteInteger(value, 0, math.huge)
end

return Validation
