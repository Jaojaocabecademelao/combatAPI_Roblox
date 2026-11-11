local Component = require(script.Parent.Parent.Core.Component)
local EntityState = require(script.Parent.Parent.Core.EntityState)
local AirState = require(script.Parent.AirState)

local JuggleComponent = setmetatable({}, Component)
JuggleComponent.__index = JuggleComponent
JuggleComponent.RollbackKey = "Combat.JuggleComponent"

local valid = {}
for _, state in pairs(AirState) do valid[state] = true end

function JuggleComponent.new()
	local self = setmetatable(Component.new(), JuggleComponent)
	self.Active = false
	self.AirState = AirState.Grounded
	self.JuggleCount = 0
	self.ReJuggleCount = 0
	self.LaunchFrame = nil
	self.LastJuggleHitFrame = nil
	self.RecoveryRemaining = 0
	self.AttackerId = nil
	self.Resolver = nil
	return self
end

function JuggleComponent:SetAirState(state)
	assert(valid[state], "JuggleComponent:SetAirState() received an invalid AirState")
	if self.Entity and self.Entity:GetState() == EntityState.Dead then
		return false, "EntityUnavailable"
	end
	self.AirState = state
	return state
end

function JuggleComponent:GetAirState() return self.AirState end
function JuggleComponent:IsJuggled() return self.Active and self.AirState == AirState.Juggled end
function JuggleComponent:IsRecovering() return self.AirState == AirState.Recovering end
function JuggleComponent:GetJuggleCount() return self.JuggleCount end
function JuggleComponent:GetReJuggleCount() return self.ReJuggleCount end

function JuggleComponent:Reset()
	self.Active = false
	self.AirState = AirState.Grounded
	self.JuggleCount = 0
	self.ReJuggleCount = 0
	self.LaunchFrame = nil
	self.LastJuggleHitFrame = nil
	self.RecoveryRemaining = 0
	self.AttackerId = nil
	return self
end

function JuggleComponent:OnEntityStateChanged(state)
	if state == EntityState.Dead then self:Reset() end
end

function JuggleComponent:Destroy()
	self:Reset()
	self.Resolver = nil
end

local function validFrameOrNil(frame)
	return frame == nil or (type(frame) == "number" and frame == frame
		and frame >= 0 and frame < math.huge and frame % 1 == 0)
end

function JuggleComponent:CaptureRollbackState()
	return {
		Version = 2,
		Active = self.Active,
		AttackerId = self.AttackerId,
		AirState = self.AirState,
		JuggleCount = self.JuggleCount,
		ReJuggleCount = self.ReJuggleCount,
		LaunchFrame = self.LaunchFrame,
		LastJuggleHitFrame = self.LastJuggleHitFrame,
		RecoveryRemaining = self.RecoveryRemaining,
	}
end

function JuggleComponent:ValidateRollbackState(state, context)
	if type(state) ~= "table" or getmetatable(state) ~= nil or state.Version ~= 2 then
		return false, "Invalid JuggleComponent state version"
	end
	if type(state.Active) ~= "boolean" or not valid[state.AirState] then return false, "Invalid juggle active/air state" end
	for _, key in ipairs({ "JuggleCount", "ReJuggleCount", "RecoveryRemaining" }) do
		local value = state[key]
		if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge or value % 1 ~= 0 then
			return false, key .. " must be a non-negative integer"
		end
	end
	if not validFrameOrNil(state.LaunchFrame) or not validFrameOrNil(state.LastJuggleHitFrame) then
		return false, "Juggle frames must be non-negative integers or nil"
	end
	if state.LastJuggleHitFrame ~= nil and state.LaunchFrame == nil then
		return false, "LastJuggleHitFrame requires LaunchFrame"
	end
	if state.AttackerId ~= nil and type(state.AttackerId) ~= "number" and type(state.AttackerId) ~= "string" then
		return false, "AttackerId must be a stable entity ID or nil"
	end
	if state.Active and (state.AttackerId == nil or state.LaunchFrame == nil or state.LastJuggleHitFrame == nil
		or state.AirState ~= AirState.Juggled) then
		return false, "Active juggle requires attacker and consistent launch frames"
	end
	if state.Active and context and context.EntitiesById and not context.EntitiesById[state.AttackerId] then
		return false, "Active juggle attacker is absent from the restore roster"
	end
	return true
end

function JuggleComponent:RestoreRollbackState(state, context)
	local validState, reason = self:ValidateRollbackState(state, context)
	if not validState then return false, reason end
	self.Active = state.Active
	self.AttackerId = state.AttackerId
	self.AirState = state.AirState
	self.JuggleCount = state.JuggleCount
	self.ReJuggleCount = state.ReJuggleCount
	self.LaunchFrame = state.LaunchFrame
	self.LastJuggleHitFrame = state.LastJuggleHitFrame
	self.RecoveryRemaining = state.RecoveryRemaining
	return true
end

return JuggleComponent
