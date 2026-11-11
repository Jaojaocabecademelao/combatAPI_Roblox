local Input = require(script.Parent.Input)
local InputState = require(script.Parent.InputState)

local Adapter = {}

local bitByInput = {
	[Input.Up] = 1,
	[Input.Down] = 2,
	[Input.Left] = 4,
	[Input.Right] = 8,
	[Input.Forward] = 16,
	[Input.Back] = 32,
	[Input.Light] = 64,
	[Input.Medium] = 128,
	[Input.Heavy] = 256,
	[Input.Special] = 512,
	[Input.Guard] = 1024,
	[Input.Jump] = 2048,
	[Input.Dash] = 4096,
}

local function isActive(state)
	return state == InputState.Pressed or state == InputState.Held
end

function Adapter.GetBit(inputId)
	return bitByInput[inputId]
end

function Adapter.ToButtons(inputFrame)
	assert(type(inputFrame) == "table" and type(inputFrame.Inputs) == "table",
		"InputPacketAdapter requires an InputFrame")
	local buttons = 0
	for inputId, state in pairs(inputFrame.Inputs) do
		local bit = bitByInput[inputId]
		if bit and isActive(state) then
			buttons += bit
		end
	end
	return buttons
end

function Adapter.ToSerializerInput(inputFrame, options)
	options = options or {}
	assert(type(inputFrame) == "table" and type(inputFrame.Frame) == "number",
		"InputPacketAdapter requires an InputFrame")
	return {
		seq = options.Seq or inputFrame.Frame,
		timestamp = options.Timestamp or inputFrame.Frame,
		playerId = options.PlayerId,
		buttons = Adapter.ToButtons(inputFrame),
		move = options.Move or { X = 0, Y = 0, Z = 0 },
		aim = options.Aim or { X = 0, Y = 0, Z = 1 },
		extras = options.Extras,
	}
end

function Adapter.GetInputMap()
	return table.clone(bitByInput)
end

return Adapter
