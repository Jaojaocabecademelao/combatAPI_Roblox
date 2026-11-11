local Component = require(script.Parent.Parent.Core.Component)
local MovementState = require(script.Parent.MovementState)

local ComponentType = setmetatable({}, Component)
ComponentType.__index = ComponentType
ComponentType.RollbackKey = "Combat.MovementStateComponent"

local validStates = {}
for _, state in pairs(MovementState) do validStates[state] = true end

local function validFrame(value)
	return type(value) == "number" and value == value and value >= 0
		and value < math.huge and value % 1 == 0
end

local function profileManifest(profile)
	if not profile then return nil end
	local transitions = {}
	for from, targets in pairs(profile.AllowedTransitions or {}) do
		for to, allowed in pairs(targets) do
			transitions[#transitions + 1] = { From = from, To = to, Allowed = allowed }
		end
	end
	table.sort(transitions, function(a, b)
		if a.From ~= b.From then return a.From < b.From end
		return a.To < b.To
	end)
	local durations = {}
	for state, config in pairs(profile.StateDurations or {}) do
		durations[#durations + 1] = { State = state, MinFrames = config.MinFrames, MaxFrames = config.MaxFrames }
	end
	table.sort(durations, function(a, b) return a.State < b.State end)
	return { InitialState = profile.InitialState, Transitions = transitions, Durations = durations }
end

local function sameManifest(a, b)
	if a == nil or b == nil then return a == b end
	if type(a) ~= "table" or type(b) ~= "table" or a.InitialState ~= b.InitialState
		or #a.Transitions ~= #b.Transitions or #a.Durations ~= #b.Durations then return false end
	for i, item in ipairs(a.Transitions) do
		local other = b.Transitions[i]
		if not other or item.From ~= other.From or item.To ~= other.To or item.Allowed ~= other.Allowed then return false end
	end
	for i, item in ipairs(a.Durations) do
		local other = b.Durations[i]
		if not other or item.State ~= other.State or item.MinFrames ~= other.MinFrames
			or item.MaxFrames ~= other.MaxFrames then return false end
	end
	return true
end

function ComponentType.new(profile)
	local self = setmetatable(Component.new(), ComponentType)
	self.Profile = profile
	self.CurrentState = profile and profile.InitialState or MovementState.Idle
	self.PreviousState = nil
	self.StateStartFrame = 0
	self.LastTransitionFrame = 0
	self.TransitionCount = 0
	return self
end

function ComponentType:GetState() return self.CurrentState end
function ComponentType:GetPreviousState() return self.PreviousState end
function ComponentType:GetStateStartFrame() return self.StateStartFrame end
function ComponentType:GetLastTransitionFrame() return self.LastTransitionFrame end
function ComponentType:SetState(state, frame)
	self.PreviousState = self.CurrentState
	self.CurrentState = state
	self.StateStartFrame = frame
	self.LastTransitionFrame = frame
	self.TransitionCount += 1
	return self
end
function ComponentType:Reset(frame, initialState)
	self.CurrentState = initialState or (self.Profile and self.Profile.InitialState) or MovementState.Idle
	self.PreviousState = nil
	self.StateStartFrame = frame or 0
	self.LastTransitionFrame = frame or 0
	self.TransitionCount = 0
	return self
end
function ComponentType:OnEntityStateChanged(state)
	if state == "Dead" then self:Reset(self.LastTransitionFrame) end
end

function ComponentType:CaptureRollbackState()
	return {
		Version = 1,
		CurrentState = self.CurrentState,
		PreviousState = self.PreviousState,
		StateStartFrame = self.StateStartFrame,
		LastTransitionFrame = self.LastTransitionFrame,
		TransitionCount = self.TransitionCount,
		ProfileManifest = profileManifest(self.Profile),
	}
end

function ComponentType:ValidateRollbackState(state)
	if type(state) ~= "table" or getmetatable(state) ~= nil or state.Version ~= 1 then
		return false, "Invalid MovementStateComponent state version"
	end
	local allowed = { Version = true, CurrentState = true, PreviousState = true,
		StateStartFrame = true, LastTransitionFrame = true, TransitionCount = true, ProfileManifest = true }
	for key in pairs(state) do if not allowed[key] then return false, "Unknown movement state field: " .. tostring(key) end end
	if not validStates[state.CurrentState] or (state.PreviousState ~= nil and not validStates[state.PreviousState]) then
		return false, "Movement state identifier is invalid"
	end
	if not validFrame(state.StateStartFrame) or not validFrame(state.LastTransitionFrame)
		or not validFrame(state.TransitionCount) then return false, "Movement state counters must be non-negative integers" end
	if state.StateStartFrame > state.LastTransitionFrame then return false, "Movement state start is after last transition" end
	if (state.TransitionCount == 0 and state.PreviousState ~= nil)
		or (state.TransitionCount > 0 and state.PreviousState == nil) then
		return false, "Movement state transition count does not match previous state"
	end
	if not sameManifest(state.ProfileManifest, profileManifest(self.Profile)) then
		return false, "MovementStateProfile mismatch"
	end
	return true
end

function ComponentType:RestoreRollbackState(state)
	local valid, detail = self:ValidateRollbackState(state)
	if not valid then return false, detail end
	self.CurrentState = state.CurrentState
	self.PreviousState = state.PreviousState
	self.StateStartFrame = state.StateStartFrame
	self.LastTransitionFrame = state.LastTransitionFrame
	self.TransitionCount = state.TransitionCount
	return true
end

return ComponentType
