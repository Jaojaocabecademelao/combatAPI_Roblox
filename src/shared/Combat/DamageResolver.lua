local HealthComponent = require(script.Parent.HealthComponent)
local DamageRequest = require(script.Parent.DamageRequest)
local DamageEvent = require(script.Parent.DamageEvent)
local HealthChangedEvent = require(script.Parent.HealthChangedEvent)
local DeathEvent = require(script.Parent.DeathEvent)

local DamageResolver = {}
DamageResolver.__index = DamageResolver

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

local function copyArray(values)
	local copy = {}
	for _, value in ipairs(values) do
		table.insert(copy, value)
	end
	return copy
end

function DamageResolver.new(world)
	return setmetatable({
		World = world,
		DamageRequests = {},
		DamageEvents = {},
		HealthChangedEvents = {},
		DeathEvents = {},
		LastResolvedFrame = nil,
	}, DamageResolver)
end

function DamageResolver:SetWorld(world)
	self.World = world
	return self
end

function DamageResolver:_Resolve(request, frame, time)
	local target = request.Target
	if type(target) ~= "table" or target.Destroyed
		or (self.World and target.Id ~= nil and self.World:GetEntity(target.Id) ~= target)
	then
		return nil
	end
	local health = type(target.GetComponent) == "function"
		and target:GetComponent(HealthComponent)
	if not health then
		return nil
	end

	local outcome = health:_ApplyResolvedDamage(request, request.Amount)
	if not outcome then
		return nil
	end

	local damageEvent = DamageEvent.new({
		Target = target,
		RequestedAmount = request.Amount,
		AppliedAmount = outcome.AppliedAmount,
		Type = request.Type,
		Source = request.Source,
		AttackInstance = request.AttackInstance,
		HitEvent = request.HitEvent,
		OffensiveProperties = request.OffensiveProperties,
		OldHealth = outcome.OldHealth,
		NewHealth = outcome.NewHealth,
		Frame = frame,
		Time = time,
		HitstunFrames = request.HitstunFrames,
	})
	table.insert(self.DamageEvents, damageEvent)

	if outcome.Changed then
		table.insert(self.HealthChangedEvents, HealthChangedEvent.new({
			Entity = target,
			OldHealth = outcome.OldHealth,
			NewHealth = outcome.NewHealth,
			MaxHealth = health:GetMaxHealth(),
			Reason = "Damage",
			DamageRequest = request,
			Frame = frame,
			Time = time,
		}))
	end
	if outcome.Died then
		table.insert(self.DeathEvents, DeathEvent.new({
			Entity = target,
			Cause = damageEvent,
			Frame = frame,
			Time = time,
		}))
	end
	return damageEvent
end

function DamageResolver:Resolve(request, frame, time)
	assert(type(request) == "table" and request.Amount ~= nil and request.Target ~= nil,
		"DamageResolver:Resolve() expects a DamageRequest")
	assert(isFiniteNumber(request.Amount) and request.Amount >= 0,
		"DamageResolver requires a finite non-negative amount")
	frame = frame or request.Frame or 0
	time = time or request.Time or 0
	assert(type(frame) == "number" and frame >= 0 and frame % 1 == 0,
		"DamageResolver frame must be a non-negative integer")
	assert(isFiniteNumber(time), "DamageResolver time must be finite")
	if self.LastResolvedFrame ~= frame then
		table.clear(self.DamageRequests)
		table.clear(self.DamageEvents)
		table.clear(self.HealthChangedEvents)
		table.clear(self.DeathEvents)
		self.LastResolvedFrame = frame
	end
	table.insert(self.DamageRequests, request)
	return self:_Resolve(request, frame, time)
end

function DamageResolver:Heal(target, amount, frame, time, context)
	assert(isFiniteNumber(amount) and amount >= 0,
		"DamageResolver:Heal() requires a finite non-negative amount")
	frame = frame or (self.World and self.World.CurrentFrame) or 0
	time = time or 0
	context = context or {}
	assert(type(context) == "table", "DamageResolver:Heal() context must be a table or nil")
	assert(type(frame) == "number" and frame >= 0 and frame % 1 == 0,
		"DamageResolver:Heal() frame must be a non-negative integer")
	assert(isFiniteNumber(time), "DamageResolver:Heal() time must be finite")
	if self.LastResolvedFrame ~= frame then
		table.clear(self.DamageRequests)
		table.clear(self.DamageEvents)
		table.clear(self.HealthChangedEvents)
		table.clear(self.DeathEvents)
		self.LastResolvedFrame = frame
	end
	if type(target) ~= "table" or target.Destroyed
		or (self.World and target.Id ~= nil and self.World:GetEntity(target.Id) ~= target) then
		return nil
	end
	local health = type(target.GetComponent) == "function" and target:GetComponent(HealthComponent)
	if not health then return nil end
	local event = health:Heal(amount, {
		Frame = frame,
		Time = time,
		Reason = context.Reason,
		Source = context.Source,
		StatusName = context.StatusName,
		EffectId = context.EffectId,
	})
	if event then table.insert(self.HealthChangedEvents, event) end
	return event
end

function DamageResolver:Process(hitEvents, frame, time, armorResults)
	assert(type(hitEvents) == "table", "DamageResolver:Process() expects HitEvents")
	assert(type(frame) == "number" and frame >= 0 and frame % 1 == 0,
		"DamageResolver:Process() expects a non-negative integer frame")
	assert(isFiniteNumber(time), "DamageResolver:Process() expects finite simulation time")
	table.clear(self.DamageRequests)
	table.clear(self.DamageEvents)
	table.clear(self.HealthChangedEvents)
	table.clear(self.DeathEvents)
	self.LastResolvedFrame = frame

	-- HitProcessor already sorts HitEvents; preserving that sequence makes same-frame damage deterministic.
	local armorByHit = {}
	for _, result in ipairs(armorResults or {}) do armorByHit[result.HitEvent] = result end
	for _, hitEvent in ipairs(hitEvents) do
		local request = DamageRequest.FromHitEvent(hitEvent)
		if request then
			local armor = armorByHit[hitEvent]
			if armor and armor:Blocks("Hitstun") then request.HitstunFrames = nil end
			request.Frame = frame
			request.Time = time
			table.insert(self.DamageRequests, request)
			self:_Resolve(request, frame, time)
		end
	end
	return self:GetDamageEvents()
end

function DamageResolver:RemoveEntity(entity)
	local removedDamageEvents = {}
	local damageEvents = {}
	for _, event in ipairs(self.DamageEvents) do
		if event.Target == entity or event.Source == entity then
			removedDamageEvents[event] = true
		else
			table.insert(damageEvents, event)
		end
	end
	self.DamageEvents = damageEvents

	local requests = {}
	for _, request in ipairs(self.DamageRequests) do
		if request.Target ~= entity and request.Source ~= entity then
			table.insert(requests, request)
		end
	end
	self.DamageRequests = requests

	local healthChanges = {}
	for _, event in ipairs(self.HealthChangedEvents) do
		if event.Entity ~= entity then
			table.insert(healthChanges, event)
		end
	end
	self.HealthChangedEvents = healthChanges

	local deaths = {}
	for _, event in ipairs(self.DeathEvents) do
		if event.Entity ~= entity and not removedDamageEvents[event.Cause] then
			table.insert(deaths, event)
		end
	end
	self.DeathEvents = deaths
end

function DamageResolver:GetDamageRequests()
	return copyArray(self.DamageRequests)
end

function DamageResolver:GetDamageEvents()
	return copyArray(self.DamageEvents)
end

function DamageResolver:GetHealthChangedEvents()
	return copyArray(self.HealthChangedEvents)
end

function DamageResolver:GetDeathEvents()
	return copyArray(self.DeathEvents)
end

-- Damage itself is restored through HealthComponent. Resolver arrays are frame-local
-- outputs and are intentionally cleared on target restore to avoid replaying notifications.
function DamageResolver:CaptureRollbackState()
	return { Version = 1 }
end

function DamageResolver:ValidateRollbackState(state)
	if type(state) ~= "table" or getmetatable(state) ~= nil or state.Version ~= 1 then
		return false, "Unsupported DamageResolver state"
	end
	for key in pairs(state) do
		if key ~= "Version" then
			return false, "Unknown DamageResolver state field: " .. tostring(key)
		end
	end
	return true
end

function DamageResolver:PrepareRollbackRestore(state, world, context, role)
	local valid, detail = self:ValidateRollbackState(state)
	if not valid then return nil, detail end
	if role ~= "Target" and role ~= "Compensation" then
		return nil, "Unknown DamageResolver restore role: " .. tostring(role)
	end
	local previous = {
		DamageRequests = copyArray(self.DamageRequests),
		DamageEvents = copyArray(self.DamageEvents),
		HealthChangedEvents = copyArray(self.HealthChangedEvents),
		DeathEvents = copyArray(self.DeathEvents),
		LastResolvedFrame = self.LastResolvedFrame,
	}
	return function()
		if role == "Compensation" then
			self.DamageRequests = copyArray(previous.DamageRequests)
			self.DamageEvents = copyArray(previous.DamageEvents)
			self.HealthChangedEvents = copyArray(previous.HealthChangedEvents)
			self.DeathEvents = copyArray(previous.DeathEvents)
			self.LastResolvedFrame = previous.LastResolvedFrame
		else
			table.clear(self.DamageRequests)
			table.clear(self.DamageEvents)
			table.clear(self.HealthChangedEvents)
			table.clear(self.DeathEvents)
			self.LastResolvedFrame = nil
		end
	end
end

return DamageResolver
