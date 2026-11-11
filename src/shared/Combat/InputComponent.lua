local Component = require(script.Parent.Parent.Core.Component)
local InputState = require(script.Parent.InputState)
local InputBuffer = require(script.Parent.InputBuffer)
local InputFrame = require(script.Parent.InputFrame)
local InputProfile = require(script.Parent.InputProfile)
local InputComponent = setmetatable({}, Component)
InputComponent.__index = InputComponent
InputComponent.RollbackKey = "Combat.InputComponent"
function InputComponent.new(profile)
	profile = profile or InputProfile.new()
	assert(type(profile) == "table" and type(profile.BufferSize) == "number",
		"InputComponent.new() requires an InputProfile")
	local self = setmetatable(Component.new(), InputComponent)
	self.Profile = profile
	self.CurrentInputs, self.PreviousInputs = {}, {}
	self.LastPressedFrame, self.LastReleasedFrame, self.HeldSinceFrame = {}, {}, {}
	self.LastStateFrame = {}
	self.InputBuffer = InputBuffer.new(profile.BufferSize)
	self.LastInputFrame = nil
	return self
end
function InputComponent:Attach(entity)
	Component.Attach(self, entity)
	self.EntityId = entity.Id
	return self
end
function InputComponent:Detach()
	Component.Detach(self)
	self.EntityId = nil
end
function InputComponent:GetState(inputId) return self.CurrentInputs[inputId] or InputState.None end
function InputComponent:Reset()
	self.CurrentInputs, self.PreviousInputs = {}, {}
	self.LastPressedFrame, self.LastReleasedFrame, self.HeldSinceFrame = {}, {}, {}
	self.LastStateFrame = {}
	self.InputBuffer:Clear()
	self.LastInputFrame = nil
	return self
end
function InputComponent:Destroy() return self:Reset() end

local function copyMap(map)
	local copy = {}
	for key, value in pairs(map) do copy[key] = value end
	return copy
end

function InputComponent:CaptureRollbackState()
	local bufferFrames = {}
	for _, frame in ipairs(self.InputBuffer.Order) do
		local inputFrame = self.InputBuffer:Get(frame)
		local inputs = {}
		for inputId, state in pairs(inputFrame.Inputs) do inputs[inputId] = state end
		table.insert(bufferFrames, {
			Frame = frame, EntityId = inputFrame.EntityId,
			Inputs = inputs,
		})
	end
	return {
		CurrentInputs = copyMap(self.CurrentInputs),
		PreviousInputs = copyMap(self.PreviousInputs),
		LastPressedFrame = copyMap(self.LastPressedFrame),
		LastReleasedFrame = copyMap(self.LastReleasedFrame),
		HeldSinceFrame = copyMap(self.HeldSinceFrame),
		LastStateFrame = copyMap(self.LastStateFrame),
		LastInputFrame = self.LastInputFrame,
		BufferFrames = bufferFrames,
	}
end

function InputComponent:RestoreRollbackState(state)
	assert(type(state) == "table" and type(state.BufferFrames) == "table",
		"InputComponent rollback state is invalid")
	self.CurrentInputs = copyMap(state.CurrentInputs)
	self.PreviousInputs = copyMap(state.PreviousInputs)
	self.LastPressedFrame = copyMap(state.LastPressedFrame)
	self.LastReleasedFrame = copyMap(state.LastReleasedFrame)
	self.HeldSinceFrame = copyMap(state.HeldSinceFrame)
	self.LastStateFrame = copyMap(state.LastStateFrame)
	self.LastInputFrame = state.LastInputFrame
	self.InputBuffer:Clear()
	for _, data in ipairs(state.BufferFrames) do
		self.InputBuffer:Put(data.Frame, InputFrame.new(data))
	end
	return true
end

return InputComponent
