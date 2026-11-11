local Status = {}
Status.__index = Status

local function finite(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function validVersion(value)
	return (type(value) == "string" and value ~= "")
		or (type(value) == "number" and finite(value) and value >= 0 and value % 1 == 0)
end

local function encodeSource(source)
	if source == nil then return nil, false end
	if type(source) == "table" then
		local id = source.Id
		if (type(id) == "number" and finite(id) and id % 1 == 0)
			or (type(id) == "string" and id ~= "") then return id, true end
		return nil, true, "Status source entity has no stable ID"
	end
	if (type(source) == "string" and source ~= "")
		or (type(source) == "number" and finite(source)) then return source, false end
	return nil, false, "Status source must be a stable entity, string, number, or nil"
end

local function validateDuration(durationFrames)
	assert(durationFrames == nil or (type(durationFrames) == "number"
		and durationFrames == durationFrames and durationFrames > 0
		and durationFrames < math.huge and durationFrames % 1 == 0),
		"Status DurationFrames must be a positive finite integer or nil")
end

local function normalizeTags(tags)
	assert(tags == nil or type(tags) == "table", "Status Tags must be a table or nil")
	local result, seen = {}, {}
	local count, maxIndex = 0, 0
	for key in pairs(tags or {}) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			error("Status Tags must be a dense array")
		end
		count += 1
		if key > maxIndex then maxIndex = key end
	end
	assert(count == maxIndex, "Status Tags must be a dense array")
	for index, tag in ipairs(tags or {}) do
		assert(type(tag) == "string" and tag ~= "", "Status tags must be non-empty strings")
		assert(not seen[tag], "Status tags must not contain duplicates")
		seen[tag] = true
		result[index] = tag
	end
	return table.freeze(result)
end

local function normalizeModifiers(modifiers)
	assert(modifiers == nil or type(modifiers) == "table", "Status Modifiers must be a table or nil")
	local result = {}
	for name, amount in pairs(modifiers or {}) do
		assert(type(name) == "string" and name ~= "", "Status modifier names must be non-empty strings")
		assert(finite(amount), "Status modifier values must be finite numbers")
		result[name] = amount
	end
	return table.freeze(result)
end

local function normalizePeriodicEffects(effects)
	assert(effects == nil or type(effects) == "table", "Status PeriodicEffects must be a table or nil")
	local result, seen = {}, {}
	local count, maxIndex = 0, 0
	for key in pairs(effects or {}) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			error("Status PeriodicEffects must be a dense array")
		end
		count += 1
		if key > maxIndex then maxIndex = key end
	end
	assert(count == maxIndex, "Status PeriodicEffects must be a dense array")
	for index, effect in ipairs(effects or {}) do
		assert(type(effect) == "table", "Periodic status effects must be tables")
		assert(type(effect.Id) == "string" and effect.Id ~= "" and not seen[effect.Id],
			"Periodic status effects require unique non-empty IDs")
		assert(effect.Type == "DamageOverTime" or effect.Type == "HealingOverTime",
			"Periodic status effect Type must be DamageOverTime or HealingOverTime")
		assert(finite(effect.Amount) and effect.Amount > 0,
			"Periodic status effect Amount must be finite and positive")
		assert(type(effect.IntervalFrames) == "number" and effect.IntervalFrames >= 1
			and effect.IntervalFrames < math.huge and effect.IntervalFrames % 1 == 0,
			"Periodic status effect IntervalFrames must be a positive integer")
		local damageType = effect.DamageType or "Physical"
		assert(type(damageType) == "string" and damageType ~= "",
			"Periodic status effect DamageType must be a non-empty string")
		for key in pairs(effect) do
			if key ~= "Id" and key ~= "Type" and key ~= "Amount"
				and key ~= "IntervalFrames" and key ~= "DamageType" then
				error("Unknown periodic status effect field: " .. tostring(key))
			end
		end
		seen[effect.Id] = true
		result[index] = table.freeze({
			Id = effect.Id,
			Type = effect.Type,
			Amount = effect.Amount,
			IntervalFrames = effect.IntervalFrames,
			DamageType = damageType,
		})
	end
	return table.freeze(result), table.create(#result, 0)
end

function Status.new(options)
	options = options or {}
	assert(type(options) == "table", "Status.new() expects an options table or nil")
	assert(type(options.Name) == "string" and options.Name ~= "",
		"Status.new() requires a non-empty Name")
	validateDuration(options.DurationFrames)
	local policy = options.ReapplicationPolicy or "Refresh"
	assert(policy == "Refresh" or policy == "Replace" or policy == "Extend"
		or policy == "Ignore" or policy == "Stack",
		"Status ReapplicationPolicy must be Refresh, Replace, Extend, Ignore, or Stack")
	local periodicEffects, periodicEffectFrames = normalizePeriodicEffects(options.PeriodicEffects)

	return setmetatable({
		Name = options.Name,
		DurationFrames = options.DurationFrames,
		RemainingFrames = options.DurationFrames,
		ReapplicationPolicy = policy,
		Source = options.Source,
		AttackInstance = options.AttackInstance,
		HitEvent = options.HitEvent,
		DamageEvent = options.DamageEvent,
		Entity = nil,
		Active = false,
		Enabled = options.Enabled ~= false,
		Tags = normalizeTags(options.Tags),
		Modifiers = normalizeModifiers(options.Modifiers),
		PeriodicEffects = periodicEffects,
		_PeriodicEffectFrames = periodicEffectFrames,
	}, Status)
end

function Status:ResetPeriodicEffects()
	for index in ipairs(self._PeriodicEffectFrames) do
		self._PeriodicEffectFrames[index] = 0
	end
end

function Status:Start(entity)
	self.Entity = entity
	self.Active = true
	self.RemainingFrames = self.DurationFrames
	self:ResetPeriodicEffects()
end

function Status:Update(_deltaTime)
	-- Optional lifecycle hook for concrete statuses.
end

function Status:End(_reason)
	self.Active = false
	self.Entity = nil
end

function Status:GetRemainingFrames()
	return self.RemainingFrames
end

function Status:SetEnabled(enabled)
	self.Enabled = enabled == true
	return self
end

function Status:IsEnabled()
	return self.Enabled
end

function Status:HasTag(tag)
	assert(type(tag) == "string" and tag ~= "", "Status tag must be a non-empty string")
	for _, current in ipairs(self.Tags) do
		if current == tag then return true end
	end
	return false
end

function Status:GetModifier(name)
	assert(type(name) == "string" and name ~= "", "Status modifier name must be a non-empty string")
	return self.Modifiers[name] or 0
end

function Status:GetTags()
	return self.Tags
end

function Status:AdvancePeriodicEffects()
	local triggered = {}
	for index, effect in ipairs(self.PeriodicEffects) do
		local elapsed = self._PeriodicEffectFrames[index] + 1
		if elapsed >= effect.IntervalFrames then
			self._PeriodicEffectFrames[index] = 0
			triggered[#triggered + 1] = effect
		else
			self._PeriodicEffectFrames[index] = elapsed
		end
	end
	return triggered
end

function Status:Refresh(durationFrames, context)
	validateDuration(durationFrames)
	self.DurationFrames = durationFrames
	self.RemainingFrames = durationFrames
	self:ResetPeriodicEffects()
	if context then
		self.Source = context.Source
		self.AttackInstance = context.AttackInstance
		self.HitEvent = context.HitEvent
		self.DamageEvent = context.DamageEvent
	end
	return self
end

-- Custom statuses override CaptureCustomRollbackState/ValidateCustomRollbackState/
-- RestoreCustomRollbackState for their own deterministic fields. Callbacks and closures
-- are never serialized; their behavior is pinned by the StatusCatalog version.
function Status:CaptureCustomRollbackState()
	return nil
end

function Status:ValidateCustomRollbackState(state)
	if state == nil then return true end
	return false, "Status type does not accept custom state"
end

function Status:RestoreCustomRollbackState(state)
	if state == nil then return true end
	return false, "Status type does not accept custom state"
end

function Status:CaptureRollbackState(context)
	local typeId, typeVersion = self.RollbackTypeId, self.RollbackVersion
	assert(type(typeId) == "string" and typeId ~= "" and validVersion(typeVersion),
		"Status must declare a stable RollbackTypeId and RollbackVersion")
	local sourceId, sourceIsEntity, sourceError = encodeSource(self.Source)
	assert(not sourceError, sourceError)
	local duration = self.DurationFrames
	local remaining = self.RemainingFrames
	assert(duration == nil or (finite(duration) and duration > 0 and duration % 1 == 0),
		"Status duration must be a positive integer or nil")
	assert(remaining == nil or (finite(remaining) and remaining > 0 and remaining % 1 == 0),
		"Status remaining duration must be a positive integer or nil")
	local customState = self:CaptureCustomRollbackState(context)
	local state = {
		Version = 1,
		TypeId = typeId,
		TypeVersion = typeVersion,
		Name = self.Name,
		DurationFrames = duration,
		RemainingFrames = remaining,
		ReapplicationPolicy = self.ReapplicationPolicy,
		Enabled = self.Enabled == true,
		SourceId = sourceId,
		SourceIsEntity = sourceIsEntity,
		CustomState = customState,
	}
	if #self.PeriodicEffects > 0 then
		state.PeriodicEffectFrames = {}
		for index, effect in ipairs(self.PeriodicEffects) do
			state.PeriodicEffectFrames[index] = {
				Id = effect.Id,
				ElapsedFrames = self._PeriodicEffectFrames[index],
			}
		end
	end
	return state
end

function Status:ValidateRollbackState(state, context)
	if type(state) ~= "table" or getmetatable(state) ~= nil or state.Version ~= 1 then
		return false, "Invalid Status rollback state version"
	end
	for key in pairs(state) do
		if key ~= "Version" and key ~= "TypeId" and key ~= "TypeVersion" and key ~= "Name"
			and key ~= "DurationFrames" and key ~= "RemainingFrames" and key ~= "ReapplicationPolicy"
			and key ~= "Enabled" and key ~= "SourceId" and key ~= "SourceIsEntity"
			and key ~= "CustomState" and key ~= "PeriodicEffectFrames" then
			return false, "Unknown Status rollback field: " .. tostring(key)
		end
	end
	if #self.PeriodicEffects == 0 then
		if state.PeriodicEffectFrames ~= nil then return false, "Unexpected periodic status effect state" end
	elseif type(state.PeriodicEffectFrames) ~= "table" or getmetatable(state.PeriodicEffectFrames) ~= nil then
		return false, "Periodic status effect state is required"
	else
		local count, maxIndex = 0, 0
		for key in pairs(state.PeriodicEffectFrames) do
			if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
				return false, "Periodic status effect state must be a dense array"
			end
			count += 1
			if key > maxIndex then maxIndex = key end
		end
		if count ~= maxIndex or count ~= #self.PeriodicEffects then
			return false, "Periodic status effect state count mismatch"
		end
		for index, effect in ipairs(self.PeriodicEffects) do
			local saved = state.PeriodicEffectFrames[index]
			if type(saved) ~= "table" or getmetatable(saved) ~= nil
				or saved.Id ~= effect.Id or not finite(saved.ElapsedFrames)
				or saved.ElapsedFrames < 0 or saved.ElapsedFrames >= effect.IntervalFrames
				or saved.ElapsedFrames % 1 ~= 0 then
				return false, "Invalid periodic status effect state"
			end
			for key in pairs(saved) do
				if key ~= "Id" and key ~= "ElapsedFrames" then
					return false, "Unknown periodic status effect state field: " .. tostring(key)
				end
			end
		end
	end
	if state.TypeId ~= self.RollbackTypeId or state.TypeVersion ~= self.RollbackVersion
		or type(state.Name) ~= "string" or state.Name ~= self.Name then return false, "Status definition/type mismatch" end
	if type(state.Enabled) ~= "boolean" or type(state.SourceIsEntity) ~= "boolean" then return false, "Invalid Status flags" end
	if state.DurationFrames ~= nil and (not finite(state.DurationFrames) or state.DurationFrames <= 0
		or state.DurationFrames % 1 ~= 0) then return false, "Invalid Status duration" end
	if state.RemainingFrames ~= nil and (not finite(state.RemainingFrames) or state.RemainingFrames <= 0
		or state.RemainingFrames % 1 ~= 0 or (state.DurationFrames ~= nil and state.RemainingFrames > state.DurationFrames)) then
		return false, "Invalid Status remaining duration"
	end
	local policy = state.ReapplicationPolicy
	if policy ~= "Refresh" and policy ~= "Replace" and policy ~= "Extend" and policy ~= "Ignore" and policy ~= "Stack" then
		return false, "Invalid Status reapplication policy"
	end
	if state.SourceIsEntity then
		if not ((type(state.SourceId) == "number" and finite(state.SourceId) and state.SourceId % 1 == 0)
			or (type(state.SourceId) == "string" and state.SourceId ~= "")) then
			return false, "Entity Status source requires a stable ID"
		end
		if context and context.EntitiesById and not context.EntitiesById[state.SourceId] then
			return false, "Status source entity is absent from staged roster"
		end
	elseif state.SourceId ~= nil and not ((type(state.SourceId) == "number" and finite(state.SourceId))
		or (type(state.SourceId) == "string" and state.SourceId ~= "")) then
		return false, "Status source value must be a non-empty string or finite number"
	end
	return self:ValidateCustomRollbackState(state.CustomState, context)
end

function Status:RestoreRollbackState(state, entity, context)
	local valid, detail = self:ValidateRollbackState(state, context)
	if not valid then return false, detail end
	local source = state.SourceId
	if state.SourceIsEntity then
		if not context or not context.EntitiesById then return false, "Staged entity map is required for Status restore" end
		source = context.EntitiesById[state.SourceId]
	end
	self.DurationFrames = state.DurationFrames
	self.RemainingFrames = state.RemainingFrames
	self.ReapplicationPolicy = state.ReapplicationPolicy
	self.Enabled = state.Enabled
	self.Source = source
	self.SourceEntity = source
	if state.PeriodicEffectFrames then
		for index, saved in ipairs(state.PeriodicEffectFrames) do
			self._PeriodicEffectFrames[index] = saved.ElapsedFrames
		end
	else
		self:ResetPeriodicEffects()
	end
	self.AttackInstance, self.HitEvent, self.DamageEvent = nil, nil, nil
	self.Entity = entity
	self.Active = true
	return self:RestoreCustomRollbackState(state.CustomState, context)
end

return Status
