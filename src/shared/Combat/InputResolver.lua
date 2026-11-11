local InputComponent = require(script.Parent.InputComponent)
local InputProfile = require(script.Parent.InputProfile)
local InputState = require(script.Parent.InputState)
local InputFrame = require(script.Parent.InputFrame)
local InputEvent = require(script.Parent.InputEvent)
local EntityState = require(script.Parent.Parent.Core.EntityState)

local Resolver = {}
Resolver.__index = Resolver
local validStates = {}
for _, state in pairs(InputState) do validStates[state] = true end
local function finite(v) return type(v) == "number" and v == v and v >= 0 and v < math.huge and v % 1 == 0 end
local function id(v) return type(v) == "table" and v.Id or v end
local function copyMap(map)
	local copy = {}
	for key, value in pairs(map) do copy[key] = value end
	return copy
end
function Resolver.new(world, profile)
	profile = profile or InputProfile.new()
	if getmetatable(profile) ~= InputProfile then profile = InputProfile.new(profile) end
	return setmetatable({ World = world, Profile = profile, Events = {} }, Resolver)
end
function Resolver:_entity(v) if type(v) == "table" then return v end; return self.World and self.World:GetEntity(v) end
function Resolver:_component(v)
	local entity = self:_entity(v)
	if not entity or entity.Destroyed then return nil, entity end
	return entity:GetComponent(InputComponent), entity
end
function Resolver:_recordFrame(component, entity, frame, source)
	local inputFrame = component.InputBuffer:Get(frame)
	if not inputFrame then
		inputFrame = InputFrame.new({ Frame = frame, EntityId = entity.Id, Inputs = {}, Source = source })
		component.InputBuffer:Put(frame, inputFrame)
	elseif source ~= nil then
		inputFrame.Source = source
	end
	return inputFrame
end
function Resolver:SetInput(entityOrId, inputId, state, frame, context)
	if self.World and self.World:GetExecutionContext() ~= "Normal" then
		return nil, "RollbackInputMutation"
	end
	context = context or {}
	frame = frame or context.Frame
	local component, entity = self:_component(entityOrId)
	if not entity or not component then return nil, "InvalidEntity" end
	if not self.Profile:IsValidInput(inputId) then return nil, "InvalidInput" end
	if not validStates[state] or not finite(frame) then return nil, not validStates[state] and "InvalidState" or "InvalidFrame" end
	local previous = component:GetState(inputId)
	if state == InputState.Pressed
		and component.LastStateFrame[inputId] ~= frame
		and (previous == InputState.Pressed or previous == InputState.Held)
	then
		state = InputState.Held
	end
	component.PreviousInputs[inputId], component.CurrentInputs[inputId] = previous, state
	component.LastStateFrame[inputId] = frame
	component.LastInputFrame = math.max(component.LastInputFrame or frame, frame)
	if state == InputState.Pressed then
		component.LastPressedFrame[inputId], component.HeldSinceFrame[inputId] = frame, frame
		table.insert(self.Events, InputEvent.new({ Type = InputEvent.Type.Pressed, EntityId = entity.Id, InputId = inputId, Frame = frame, Source = context.Source }))
	elseif state == InputState.Released then
		component.LastReleasedFrame[inputId] = frame
		table.insert(self.Events, InputEvent.new({ Type = InputEvent.Type.Released, EntityId = entity.Id, InputId = inputId, Frame = frame, Source = context.Source }))
		component.HeldSinceFrame[inputId] = nil
	elseif state == InputState.Held and not component.HeldSinceFrame[inputId] then
		component.HeldSinceFrame[inputId] = frame
	end
	local inputFrame = self:_recordFrame(component, entity, frame, context.Source)
	inputFrame.Inputs[inputId] = state
	return inputFrame
end
function Resolver:AdvanceFrame(entityOrId, frame, source)
	if self.World and self.World:GetExecutionContext() ~= "Normal" then
		return nil, "RollbackInputMutation"
	end
	local component, entity = self:_component(entityOrId)
	if not component or not finite(frame) then return nil end
	for inputId, state in pairs(component.CurrentInputs) do
		if state == InputState.Pressed then self:SetInput(entity, inputId, InputState.Held, frame, { Source = source })
		elseif state == InputState.Released then self:SetInput(entity, inputId, InputState.None, frame, { Source = source }) end
	end
	return self:_recordFrame(component, entity, frame, source)
end
function Resolver:GetInput(entityOrId, inputId)
	local component = self:_component(entityOrId)
	return component and component:GetState(inputId) or InputState.None
end
function Resolver:IsPressed(e, i) return self:GetInput(e, i) == InputState.Pressed end
function Resolver:IsHeld(e, i) return self:GetInput(e, i) == InputState.Held end
function Resolver:IsReleased(e, i) return self:GetInput(e, i) == InputState.Released end
function Resolver:GetInputFrame(entityOrId, frame)
	local component = self:_component(entityOrId)
	return component and component.InputBuffer:Get(frame) or nil
end
function Resolver:ApplyInputFrame(entityOrId, inputFrame)
	local entity = self:_entity(entityOrId)
	local component = entity and not entity.Destroyed and entity:GetComponent(InputComponent)
	if not component or type(inputFrame) ~= "table" or getmetatable(inputFrame) ~= InputFrame
		or inputFrame.EntityId ~= entity.Id or not finite(inputFrame.Frame)
		or type(inputFrame.Inputs) ~= "table" then
		return false, "InvalidInputFrame"
	end
	local previous, current = {}, copyMap(component.CurrentInputs)
	local lastStateFrame = copyMap(component.LastStateFrame)
	local lastPressedFrame = copyMap(component.LastPressedFrame)
	local lastReleasedFrame = copyMap(component.LastReleasedFrame)
	local heldSinceFrame = copyMap(component.HeldSinceFrame)
	for inputId, state in pairs(inputFrame.Inputs) do
		if not self.Profile:IsValidInput(inputId) or not validStates[state] then
			return false, "InvalidInputFrame"
		end
		previous[inputId] = component.CurrentInputs[inputId]
		if state == InputState.None then
			current[inputId] = nil
		else
			current[inputId] = state
		end
		lastStateFrame[inputId] = inputFrame.Frame
		if state == InputState.None then
			heldSinceFrame[inputId] = nil
		elseif state == InputState.Pressed then
			lastPressedFrame[inputId] = inputFrame.Frame
			heldSinceFrame[inputId] = inputFrame.Frame
		elseif state == InputState.Released then
			lastReleasedFrame[inputId] = inputFrame.Frame
			heldSinceFrame[inputId] = nil
		elseif state == InputState.Held and heldSinceFrame[inputId] == nil then
			heldSinceFrame[inputId] = inputFrame.Frame
		end
	end
	component.LastStateFrame = lastStateFrame
	component.LastPressedFrame = lastPressedFrame
	component.LastReleasedFrame = lastReleasedFrame
	component.HeldSinceFrame = heldSinceFrame
	component.PreviousInputs = previous
	component.CurrentInputs = current
	component.LastInputFrame = math.max(component.LastInputFrame or inputFrame.Frame, inputFrame.Frame)
	local stored = InputFrame.new(inputFrame)
	component.InputBuffer:Put(stored.Frame, stored)
	return true
end
function Resolver:GetRecentInputs(entityOrId, startFrame, endFrame)
	local component = self:_component(entityOrId)
	local result = {}
	if not component then return result end
	return component and component.InputBuffer:GetWindow(startFrame, endFrame) or result
end
function Resolver:GetLastPressedFrame(e, i) local c = self:_component(e); return c and c.LastPressedFrame[i] end
function Resolver:GetLastReleasedFrame(e, i) local c = self:_component(e); return c and c.LastReleasedFrame[i] end
function Resolver:WasPressedWithin(e, i, window, frame)
	local last = self:GetLastPressedFrame(e, i)
	return last ~= nil and frame - window <= last and last <= frame
end
function Resolver:WasReleasedWithin(e, i, window, frame)
	local last = self:GetLastReleasedFrame(e, i)
	return last ~= nil and frame - window <= last and last <= frame
end
function Resolver:GetHeldDuration(e, i, frame)
	local c = self:_component(e); local start = c and c.HeldSinceFrame[i]
	return start and math.max(0, frame - start) or 0
end
function Resolver:Reset(e) local c = self:_component(e); if not c then return false end; c:Reset(); return true end
function Resolver:GetEvents()
	local r = {}
	for _, v in ipairs(self.Events) do table.insert(r, v) end
	table.sort(r, function(a, b)
		if a.Frame ~= b.Frame then return a.Frame < b.Frame end
		if a.EntityId ~= b.EntityId then return a.EntityId < b.EntityId end
		if a.InputId ~= b.InputId then return a.InputId < b.InputId end
		return a.Type < b.Type
	end)
	return r
end
function Resolver:Clear() self.Events = {}; return self end
return Resolver
