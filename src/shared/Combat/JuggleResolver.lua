local Juggle = require(script.Parent.Juggle)
local JuggleComponent = require(script.Parent.JuggleComponent)
local JuggleProfile = require(script.Parent.JuggleProfile)
local JuggleEvent = require(script.Parent.JuggleEvent)
local JuggleResult = require(script.Parent.JuggleResult)
local AirState = require(script.Parent.AirState)
local MotionType = require(script.Parent.MotionType)
local EntityState = require(script.Parent.Parent.Core.EntityState)

local Resolver = {}
Resolver.__index = Resolver

local function id(value) return type(value) == "table" and value.Id or value end
local function idLess(a, b)
	if type(a) ~= type(b) then return type(a) < type(b) end
	return a < b
end
local function alive(entity)
	return entity and not entity.Destroyed and entity:GetState() ~= EntityState.Dead
end
local function key(target)
	local value = id(target)
	local encoded = tostring(value)
	return type(value) .. "#" .. tostring(#encoded) .. ":" .. encoded
end
local function compare(a, b)
	if (a.Frame or 0) ~= (b.Frame or 0) then return (a.Frame or 0) < (b.Frame or 0) end
	local aa = id(a.Attacker or a.Source) or 0
	local ba = id(b.Attacker or b.Source) or 0
	if aa ~= ba then return aa < ba end
	return tostring(a.AttackInstanceId or (a.AttackInstance and a.AttackInstance.Id) or "") <
		tostring(b.AttackInstanceId or (b.AttackInstance and b.AttackInstance.Id) or "")
end

function Resolver.new(world, profile)
	profile = profile or JuggleProfile.new()
	if getmetatable(profile) ~= JuggleProfile then profile = JuggleProfile.new(profile) end
	return setmetatable({ World = world, Profile = profile, Active = {}, Events = {}, Results = {} }, Resolver)
end

function Resolver:_component(target)
	return target and type(target.GetComponent) == "function" and target:GetComponent(JuggleComponent)
end
function Resolver:GetJuggle(target)
	return self.Active[key(target)]
end
function Resolver:GetActiveJuggles()
	local result = {}
	for _, juggle in pairs(self.Active) do table.insert(result, juggle) end
	table.sort(result, function(a, b) return a.TargetId < b.TargetId end)
	return result
end
function Resolver:GetEvents() local r = {}; for _, v in ipairs(self.Events) do table.insert(r, v) end; return r end
function Resolver:GetResults() local r = {}; for _, v in ipairs(self.Results) do table.insert(r, v) end; return r end


local function profileState(profile)
	return { MaxJuggleHits = profile.MaxJuggleHits, JuggleWindowFrames = profile.JuggleWindowFrames,
		ReJuggleLimit = profile.ReJuggleLimit, RecoveryFrames = profile.RecoveryFrames }
end
local function sameProfile(a, b)
	return a.MaxJuggleHits == b.MaxJuggleHits and a.JuggleWindowFrames == b.JuggleWindowFrames
		and a.ReJuggleLimit == b.ReJuggleLimit and a.RecoveryFrames == b.RecoveryFrames
end
local function finiteInteger(value, minimum)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
		and value >= (minimum or 0) and value % 1 == 0
end
local function denseArray(value)
	if type(value) ~= "table" then return false end
	local count, maxIndex = 0, 0
	for index in pairs(value) do
		if type(index) ~= "number" or index < 1 or index % 1 ~= 0 then return false end
		count += 1
		if index > maxIndex then maxIndex = index end
	end
	return count == maxIndex
end

-- Register explicitly with schema:RegisterStateProvider("combat.juggle-resolver.v1", world:GetJuggleResolver()).
function Resolver:CaptureRollbackState()
	local active = {}
	for _, juggle in ipairs(self:GetActiveJuggles()) do
		active[#active + 1] = { TargetId = juggle.TargetId, AttackerId = juggle.AttackerId,
			LaunchFrame = juggle.LaunchFrame, LastJuggleHitFrame = juggle.LastJuggleHitFrame,
			JuggleCount = juggle.JuggleCount, ReJuggleCount = juggle.ReJuggleCount,
			RecoveryRemaining = juggle.RecoveryRemaining, AirState = juggle.AirState, State = juggle.State }
	end
	return { Version = 1, Profile = profileState(self.Profile), Active = active }
end

function Resolver:ValidateRollbackState(state)
	if type(state) ~= "table" or state.Version ~= 1 or type(state.Profile) ~= "table"
		or not sameProfile(state.Profile, profileState(self.Profile)) or not denseArray(state.Active) then
		return false, "Invalid JuggleResolver state or profile mismatch"
	end
	local targets, previous = {}, nil
	for _, saved in ipairs(state.Active) do
		if type(saved) ~= "table" or (type(saved.TargetId) ~= "number" and type(saved.TargetId) ~= "string")
			or (type(saved.AttackerId) ~= "number" and type(saved.AttackerId) ~= "string") then
			return false, "Invalid active juggle entity IDs"
		end
		if targets[saved.TargetId] then return false, "Duplicate active juggle target" end
		if previous ~= nil and not idLess(previous, saved.TargetId) then return false, "Active juggles are not in canonical order" end
		previous, targets[saved.TargetId] = saved.TargetId, true
		for _, field in ipairs({ "LaunchFrame", "LastJuggleHitFrame", "JuggleCount", "ReJuggleCount", "RecoveryRemaining" }) do
			if not finiteInteger(saved[field], 0) then return false, "Invalid active juggle field: " .. field end
		end
		if saved.LastJuggleHitFrame < saved.LaunchFrame or saved.State ~= "Active" or saved.AirState ~= AirState.Juggled then
			return false, "Inconsistent active juggle temporal state"
		end
		if saved.JuggleCount > self.Profile.MaxJuggleHits or saved.ReJuggleCount > self.Profile.ReJuggleLimit then
			return false, "Active juggle exceeds configured profile limits"
		end
	end
	return true
end

function Resolver:PrepareRollbackRestore(state, world, context, role)
	local entityMap = role == "Target" and context and context.TargetEntitiesById
		or context and context.CurrentEntitiesById
	if type(entityMap) ~= "table" then return nil, "JuggleResolver restore context has no entity map" end
	local prepared = {}
	for _, saved in ipairs(state.Active) do
		local target, attacker = entityMap[saved.TargetId], entityMap[saved.AttackerId]
		if not target or not attacker then return nil, "Juggle references an entity absent from staged roster" end
		local component = target:GetComponent(JuggleComponent)
		if not component or not component.Active or component.AttackerId ~= saved.AttackerId
			or component.LaunchFrame ~= saved.LaunchFrame or component.LastJuggleHitFrame ~= saved.LastJuggleHitFrame
			or component.JuggleCount ~= saved.JuggleCount or component.ReJuggleCount ~= saved.ReJuggleCount
			or component.AirState ~= saved.AirState then
			return nil, "JuggleResolver state does not match staged JuggleComponent"
		end
		local juggle = Juggle.new({ Target = target, TargetId = saved.TargetId, Attacker = attacker,
			AttackerId = saved.AttackerId, AirState = saved.AirState, LaunchFrame = saved.LaunchFrame,
			LastJuggleHitFrame = saved.LastJuggleHitFrame, Profile = self.Profile })
		juggle.JuggleCount = saved.JuggleCount
		juggle.ReJuggleCount = saved.ReJuggleCount
		juggle.RecoveryRemaining = saved.RecoveryRemaining
		prepared[key(target)] = juggle
	end
	local previousActive = self.Active
	local previousEvents, previousResults = {}, {}
	for _, event in ipairs(self.Events) do previousEvents[#previousEvents + 1] = event end
	for _, result in ipairs(self.Results) do previousResults[#previousResults + 1] = result end
	return function()
		self.Active = prepared
		if role == "Target" then
			table.clear(self.Events)
			table.clear(self.Results)
		else
			self.Active = previousActive
			table.clear(self.Events); for _, event in ipairs(previousEvents) do table.insert(self.Events, event) end
			table.clear(self.Results); for _, result in ipairs(previousResults) do table.insert(self.Results, result) end
		end
		for _, entity in pairs(entityMap) do
			local component = entity:GetComponent(JuggleComponent)
			if component then component.Resolver = self end
		end
	end
end

function Resolver:_emit(juggle, eventType, frame, hit, reason)
	local event = JuggleEvent.new({
		Type = eventType, Frame = frame, Target = juggle.Target, TargetId = juggle.TargetId,
		Attacker = juggle.Attacker, AttackerId = juggle.AttackerId, HitEvent = hit,
		JuggleCount = juggle.JuggleCount, ReJuggleCount = juggle.ReJuggleCount,
		AirState = juggle.AirState, Reason = reason,
	})
	table.insert(self.Events, event)
	return event
end
function Resolver:_result(kind, juggle, frame, hit, reason)
	local result = JuggleResult.new({ Type = kind, Frame = frame, Target = juggle and juggle.Target,
		Attacker = juggle and juggle.Attacker, Juggle = juggle, HitEvent = hit, Reason = reason })
	table.insert(self.Results, result)
	return result
end
function Resolver:_end(juggle, frame, reason)
	if not juggle or juggle.State ~= "Active" then return end
	juggle.State = "Ended"
	juggle.AirState = AirState.Recovering
	juggle.RecoveryRemaining = juggle.Profile.RecoveryFrames
	self.Active[key(juggle.Target)] = nil
	local component = self:_component(juggle.Target)
	if component then
		component.Active = false
		component.AirState = AirState.Recovering
		component.RecoveryRemaining = juggle.RecoveryRemaining
	end
	self:_emit(juggle, JuggleEvent.Type.Ended, frame, nil, reason)
	self:_result(JuggleResult.Type.Ended, juggle, frame, nil, reason)
end
function Resolver:Break(target, reason, frame)
	local juggle = self:GetJuggle(target)
	if juggle then self:_end(juggle, frame or 0, reason or "Manual") end
	return juggle
end
function Resolver:Reset(frame)
	for _, juggle in ipairs(self:GetActiveJuggles()) do self:_end(juggle, frame or 0, "Reset") end
	return self
end

function Resolver:_start(motion, frame)
	local target = motion.Target
	local component = self:_component(target)
	if not component or not alive(target) then return nil end
	local existing = self:GetJuggle(target)
	if existing then
		if existing.ReJuggleCount >= existing.Profile.ReJuggleLimit then
			self:_emit(existing, JuggleEvent.Type.Rejected, frame, nil, "ReJuggleLimit")
			return self:_result(JuggleResult.Type.Rejected, existing, frame, nil, "ReJuggleLimit")
		end
		existing.ReJuggleCount += 1
		existing.AirState = AirState.Juggled
		component.AirState, component.ReJuggleCount = AirState.Juggled, existing.ReJuggleCount
		self:_emit(existing, JuggleEvent.Type.ReJuggled, frame, nil, nil)
		return self:_result(JuggleResult.Type.ReJuggled, existing, frame, nil, nil)
	end
	local juggle = Juggle.new({ Target = target, TargetId = target.Id, Attacker = motion.Source,
		AttackerId = id(motion.Source), AirState = AirState.Juggled, LaunchFrame = frame,
		LastJuggleHitFrame = frame, Profile = self.Profile })
	self.Active[key(target)] = juggle
	component.Resolver, component.Active = self, true
	component.AttackerId = juggle.AttackerId
	component.AirState, component.LaunchFrame = AirState.Juggled, frame
	component.LastJuggleHitFrame = frame
	self:_emit(juggle, JuggleEvent.Type.Started, frame, nil, nil)
	return self:_result(JuggleResult.Type.Started, juggle, frame, nil, nil)
end

function Resolver:_hit(hit, defense, frame)
	local target = hit.Target
	local juggle = self:GetJuggle(target)
	if not juggle or not alive(target) or (defense and defense.Result ~= "Normal") then
		return self:_result(JuggleResult.Type.Rejected, juggle, frame, hit, defense and defense.Result or "NotJuggled")
	end
	if frame - juggle.LastJuggleHitFrame > juggle.Profile.JuggleWindowFrames then
		self:_end(juggle, frame, "Timeout")
		return self:_result(JuggleResult.Type.Rejected, juggle, frame, hit, "Timeout")
	end
	if juggle.JuggleCount >= juggle.Profile.MaxJuggleHits then
		if juggle.JuggleCount == juggle.Profile.MaxJuggleHits then
			self:_emit(juggle, JuggleEvent.Type.LimitReached, frame, hit, "MaxJuggleHits")
		end
		return self:_result(JuggleResult.Type.LimitReached, juggle, frame, hit, "MaxJuggleHits")
	end
	juggle.JuggleCount += 1
	juggle.LastJuggleHitFrame = frame
	local component = self:_component(target)
	component.JuggleCount = juggle.JuggleCount
	component.LastJuggleHitFrame = juggle.LastJuggleHitFrame
	self:_emit(juggle, JuggleEvent.Type.Hit, frame, hit, nil)
	return self:_result(JuggleResult.Type.Continued, juggle, frame, hit, nil)
end

function Resolver:Process(hitEvents, motionResults, defenseEvents, frame)
	assert(type(hitEvents or {}) == "table", "JuggleResolver:Process() expects HitEvents")
	frame = frame or 0
	self.Events, self.Results = {}, {}
	for _, entity in ipairs(self.World and self.World:GetEntities() or {}) do
		local component = self:_component(entity)
		if component and component:IsRecovering() then
			component.RecoveryRemaining = math.max(0, component.RecoveryRemaining - 1)
			if component.RecoveryRemaining <= 0 then
				component:SetAirState(AirState.Airborne)
				component.Active = false
				component.JuggleCount = 0
				component.ReJuggleCount = 0
				component.LaunchFrame = nil
				component.LastJuggleHitFrame = nil
				component.AttackerId = nil
			end
		end
	end
	for _, juggle in ipairs(self:GetActiveJuggles()) do
		if not alive(juggle.Target) then self:_end(juggle, frame, "Death")
		elseif frame - juggle.LastJuggleHitFrame > juggle.Profile.JuggleWindowFrames then self:_end(juggle, frame, "Timeout") end
	end
	local motions = {}
	for _, motion in ipairs(motionResults or {}) do
		if motion.Type == MotionType.Launch then table.insert(motions, motion) end
	end
	table.sort(motions, compare)
	for _, motion in ipairs(motions) do self:_start(motion, motion.Frame or frame) end
	local defenses = {}
	for _, event in ipairs(defenseEvents or {}) do defenses[event.HitEvent] = event end
	local ordered = {}
	for _, hit in ipairs(hitEvents or {}) do table.insert(ordered, hit) end
	table.sort(ordered, compare)
	for _, hit in ipairs(ordered) do self:_hit(hit, defenses[hit], hit.Frame or frame) end
	return self:GetResults()
end

return Resolver
