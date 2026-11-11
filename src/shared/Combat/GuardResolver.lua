local GuardComponent = require(script.Parent.GuardComponent)
local GuardEvent = require(script.Parent.GuardEvent)
local GuardResult = require(script.Parent.GuardResult)
local GuardProfile = require(script.Parent.GuardProfile)
local Blockstun = require(script.Parent.Blockstun)
local StatusContainer = require(script.Parent.StatusContainer)
local DamageRequest = require(script.Parent.DamageRequest)

local GuardResolver = {}
GuardResolver.__index = GuardResolver

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

local function clamp(value, minimum, maximum)
	if value < minimum then return minimum end
	if value > maximum then return maximum end
	return value
end

local function compareIds(a, b)
	if a == b then return 0 end
	if a == nil then return -1 elseif b == nil then return 1 end
	if type(a) == type(b) then return a < b and -1 or 1 end
	return type(a) < type(b) and -1 or 1
end

function GuardResolver.new(world)
	return setmetatable({
		World = world,
		Results = {},
		Events = {},
	}, GuardResolver)
end

function GuardResolver:GetEvents()
	local events = {}
	for _, event in ipairs(self.Events) do table.insert(events, event) end
	return events
end

function GuardResolver:GetResults()
	local results = {}
	for _, result in ipairs(self.Results) do table.insert(results, result) end
	return results
end

function GuardResolver:Clear()
	self.Results = {}
	self.Events = {}
	return self
end

function GuardResolver:_makeBlockstun(target, attacker, hitEvent, chipEvent, durationFrames, guardBroken)
	if target == nil or type(target.GetComponent) ~= "function" then
		return nil
	end
	if durationFrames == nil or durationFrames <= 0 then
		return nil
	end
	local statusContainer = target:GetComponent(StatusContainer)
	if not statusContainer then
		return nil
	end
	if guardBroken then
		return nil
	end
	local resolvedDuration = math.max(1, math.ceil(durationFrames or 0))
	return statusContainer:AddStatus(Blockstun.new({
		DurationFrames = resolvedDuration,
		Source = attacker,
		AttackInstance = hitEvent and hitEvent.AttackInstance,
		HitEvent = hitEvent,
		DamageEvent = chipEvent,
	}))
end

function GuardResolver:Process(defenseEvents, frame, time)
	assert(type(defenseEvents) == "table", "GuardResolver:Process() expects DefenseEvents")
	frame = frame or 0
	time = time or 0
	assert(type(frame) == "number" and frame >= 0 and frame % 1 == 0 and isFiniteNumber(frame),
		"GuardResolver requires a non-negative integer simulation frame")
	assert(isFiniteNumber(time), "GuardResolver requires finite simulation time")

	local ordered = {}
	for _, event in ipairs(defenseEvents) do
		table.insert(ordered, event)
	end
	table.sort(ordered, function(left, right)
		if (left.Frame or 0) ~= (right.Frame or 0) then return (left.Frame or 0) < (right.Frame or 0) end
		return compareIds((left.Target and left.Target.Id or left.TargetEntityId), (right.Target and right.Target.Id or right.TargetEntityId)) < 0
	end)

	self.Events = {}
	self.Results = {}
	for _, defenseEvent in ipairs(ordered) do
		if defenseEvent and defenseEvent.Result == "Blocked" then
			local target = defenseEvent.Defender or defenseEvent.Target
			local attacker = defenseEvent.Attacker
			if target and type(target.GetComponent) == "function" then
				local guard = target:GetComponent(GuardComponent)
				if guard then
					local profile = guard.Profile or GuardProfile.new({ MaxGuard = guard:GetMaxGuard() })
					local previousGuard = guard:GetGuard()
					local hitEvent = defenseEvent.HitEvent
					local offensive = hitEvent and hitEvent.OffensiveProperties or {}
					local damage = type(offensive.Damage) == "table" and (offensive.Damage.Amount or 0) or (offensive.Damage or (hitEvent and hitEvent.Damage) or 0)
					local chipBase = damage * (profile.ChipMultiplier or 0.1)
					local chipDamage = clamp(chipBase, 0, damage)
					local guardDamage = offensive.GuardDamage or profile.DefaultGuardDamage or 0
					if guardDamage == nil then guardDamage = 0 end
					guardDamage = guardDamage * (profile.GuardDamageMultiplier or 1)
					local blockstunFrames = (offensive.Blockstun or 0) * (profile.BlockstunMultiplier or 1)
					if blockstunFrames <= 0 and hitEvent and hitEvent.OffensiveProperties and hitEvent.OffensiveProperties.Hitstun then
						blockstunFrames = math.max(0, hitEvent.OffensiveProperties.Hitstun * (profile.BlockstunMultiplier or 1))
					end
					local guardAfterDrain = math.max(0, previousGuard - guardDamage)
					local guardBroken = guardAfterDrain <= 0
					guard:Drain(guardDamage)
					if guardBroken then
						guard.GuardBroken = true
						guard.GuardBreakRemaining = guard:GetMaxGuard() > 0 and math.max(0, (profile.GuardBreakFrames or 30)) or 0
					end
					local chipRequest = DamageRequest.new({
						Amount = chipDamage,
						Type = "Chip",
						Source = attacker,
						Target = target,
						Frame = frame,
						Time = time,
						AttackInstance = hitEvent and hitEvent.AttackInstance,
						HitEvent = hitEvent,
						OffensiveProperties = offensive,
					})
					local chipEvent = nil
					if self.World and self.World.DamageResolver and type(self.World.DamageResolver.Resolve) == "function" then
						chipEvent = self.World.DamageResolver:Resolve(chipRequest, frame, time)
					end
					local resolvedBlockstun = guardBroken and 0 or math.max(0, math.ceil(blockstunFrames))
					self:_makeBlockstun(target, attacker, hitEvent, chipEvent, resolvedBlockstun, guardBroken)
					local result = GuardResult.new({
						Type = guardBroken and GuardResult.Broken or GuardResult.Blocked,
						Result = guardBroken and GuardResult.Broken or GuardResult.Blocked,
						HitEvent = hitEvent,
						DefenseEvent = defenseEvent,
						Attacker = attacker,
						Defender = target,
						Target = target,
						AttackInstance = hitEvent and hitEvent.AttackInstance,
						AttackInstanceId = hitEvent and hitEvent.AttackInstanceId,
						Frame = frame,
						Time = time,
						PreviousGuard = previousGuard,
						GuardDamage = guardDamage,
						RemainingGuard = guard:GetGuard(),
						ChipDamage = chipDamage,
						BlockstunFrames = resolvedBlockstun,
						GuardBroken = guardBroken,
					})
					local event = GuardEvent.new({
						Type = "Guard",
						Result = guardBroken and GuardResult.Broken or GuardResult.Blocked,
						Frame = frame,
						Time = time,
						HitEvent = hitEvent,
						DefenseEvent = defenseEvent,
						Attacker = attacker,
						Defender = target,
						Target = target,
						AttackInstance = hitEvent and hitEvent.AttackInstance,
						AttackInstanceId = hitEvent and hitEvent.AttackInstanceId,
						PreviousGuard = previousGuard,
						GuardDamage = guardDamage,
						RemainingGuard = guard:GetGuard(),
						ChipDamage = chipDamage,
						BlockstunFrames = resolvedBlockstun,
						GuardBroken = guardBroken,
					})
					table.insert(self.Events, event)
					table.insert(self.Results, result)
				end
			end
		end
	end
	return self:GetResults()
end

return GuardResolver
