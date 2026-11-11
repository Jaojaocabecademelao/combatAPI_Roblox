local HitPolicy = require(script.Parent.HitPolicy)

local HitHistory = {}
HitHistory.__index = HitHistory

local ATTACK_SCOPE = {}
local NIL_TARGET = {}

local function targetKey(target)
	return target or NIL_TARGET
end

local function isEmpty(map)
	return next(map) == nil
end

function HitHistory.new()
	return setmetatable({ Entries = {} }, HitHistory)
end

function HitHistory:_GetTargetBucket(attackInstance, hitbox, scope, create)
	local scopes = self.Entries[attackInstance]
	if scopes == nil and create then
		scopes = {}
		self.Entries[attackInstance] = scopes
	end
	if scopes == nil then
		return nil
	end

	local scopeKey = scope == HitPolicy.Scope.Hitbox and hitbox or ATTACK_SCOPE
	local targets = scopes[scopeKey]
	if targets == nil and create then
		targets = {}
		scopes[scopeKey] = targets
	end
	return targets
end

function HitHistory:CanRecord(attackInstance, target, hitbox, scope, policy, frame)
	local targets = self:_GetTargetBucket(attackInstance, hitbox, scope, false)
	local record = targets and targets[targetKey(target)]
	if record == nil then
		return true
	end
	if policy == HitPolicy.Once then
		-- Once is retained until the execution or referenced entity is explicitly cleaned up.
		return false
	end
	-- Multi permits one event for the selected scope per target on each simulation frame.
	return record.Frame ~= frame
end

function HitHistory:Record(attackInstance, target, hitbox, hurtbox, scope, frame)
	local targets = self:_GetTargetBucket(attackInstance, hitbox, scope, true)
	targets[targetKey(target)] = {
		Frame = frame,
		Hitbox = hitbox,
		Hurtbox = hurtbox,
	}
end

function HitHistory:RemoveAttackInstance(attackInstance)
	local existed = self.Entries[attackInstance] ~= nil
	self.Entries[attackInstance] = nil
	if attackInstance._HitHistory == self then
		attackInstance._HitHistory = nil
	end
	return existed
end

function HitHistory:RemoveEntity(entity)
	for attackInstance, scopes in pairs(self.Entries) do
		if attackInstance.OwnerEntity == entity then
			self:RemoveAttackInstance(attackInstance)
		else
			for scopeKey, targets in pairs(scopes) do
				targets[targetKey(entity)] = nil
				if isEmpty(targets) then
					scopes[scopeKey] = nil
				end
			end
			if isEmpty(scopes) then
				self:RemoveAttackInstance(attackInstance)
			end
		end
	end
end

function HitHistory:RemoveRegion(region)
	for attackInstance, scopes in pairs(self.Entries) do
		for scopeKey, targets in pairs(scopes) do
			if scopeKey == region then
				scopes[scopeKey] = nil
			else
				for _, record in pairs(targets) do
					if record.Hitbox == region then
						record.Hitbox = nil
					end
					if record.Hurtbox == region then
						record.Hurtbox = nil
					end
				end
			end
			if isEmpty(targets) then
				scopes[scopeKey] = nil
			end
		end
		if isEmpty(scopes) then
			self:RemoveAttackInstance(attackInstance)
		end
	end
end

function HitHistory:Prune(world)
	for attackInstance, scopes in pairs(self.Entries) do
		local owner = attackInstance.OwnerEntity
		if attackInstance.State == "Finished" or (owner and owner.Destroyed)
			or (owner and world and owner.Id ~= nil and not world:HasEntity(owner))
		then
			self:RemoveAttackInstance(attackInstance)
		else
			for scopeKey, targets in pairs(scopes) do
				for target in pairs(targets) do
					if target ~= NIL_TARGET and target.Destroyed then
						targets[target] = nil
					elseif target ~= NIL_TARGET and world and target.Id ~= nil
						and not world:HasEntity(target)
					then
						targets[target] = nil
					end
				end
				if isEmpty(targets) then
					scopes[scopeKey] = nil
				end
			end
			if isEmpty(scopes) then
				self:RemoveAttackInstance(attackInstance)
			end
		end
	end
end


local function stableId(value, label, allowNil)
	if value == nil and allowNil then return nil end
	assert(type(value) == "table" and (type(value.Id) == "number" or type(value.Id) == "string"),
		label .. " must have a stable numeric or string Id")
	return value.Id
end

local function idLess(left, right)
	if type(left) ~= type(right) then return type(left) < type(right) end
	return left < right
end

local function validStableId(id)
	return (type(id) == "number" and id == id and id > -math.huge and id < math.huge and id % 1 == 0)
		or (type(id) == "string" and id ~= "")
end

local function isDenseArray(value)
	if type(value) ~= "table" then return false end
	local count, maxIndex = 0, 0
	for key in pairs(value) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
		count += 1
		if key > maxIndex then maxIndex = key end
	end
	return count == maxIndex
end

-- Capture only stable identifiers; never serialize object references or table identities.
-- This state can be restored only after the owning CollisionWorld has reconstructed the
-- referenced AttackInstances, entities and regions.
function HitHistory:CaptureRollbackState()
	local entries = {}
	for attackInstance, scopes in pairs(self.Entries) do
		local attackId = stableId(attackInstance, "AttackInstance", false)
		for scopeKey, targets in pairs(scopes) do
			local scopeType, scopeId
			if scopeKey == ATTACK_SCOPE then
				scopeType = "AttackInstance"
			else
				scopeType = "Hitbox"
				scopeId = stableId(scopeKey, "HitHistory scope Hitbox", false)
			end
			for target, record in pairs(targets) do
				local actualTarget
				if target ~= NIL_TARGET then actualTarget = target end
				table.insert(entries, {
					AttackInstanceId = attackId,
					ScopeType = scopeType,
					ScopeId = scopeId,
					TargetIsNil = actualTarget == nil,
					TargetEntityId = actualTarget and stableId(actualTarget, "HitHistory target", false) or nil,
					Frame = record.Frame,
					HitboxId = record.Hitbox and stableId(record.Hitbox, "HitHistory record Hitbox", false) or nil,
					HurtboxId = record.Hurtbox and stableId(record.Hurtbox, "HitHistory record Hurtbox", false) or nil,
				})
			end
		end
	end
	table.sort(entries, function(a, b)
			if a.AttackInstanceId ~= b.AttackInstanceId then return idLess(a.AttackInstanceId, b.AttackInstanceId) end
			if a.ScopeType ~= b.ScopeType then return a.ScopeType < b.ScopeType end
			if a.ScopeId ~= b.ScopeId then
				if a.ScopeId == nil then return true end
				if b.ScopeId == nil then return false end
				return idLess(a.ScopeId, b.ScopeId)
			end
			if a.TargetIsNil ~= b.TargetIsNil then return a.TargetIsNil end
			if a.TargetEntityId ~= b.TargetEntityId then
				if a.TargetEntityId == nil then return true end
				if b.TargetEntityId == nil then return false end
				return idLess(a.TargetEntityId, b.TargetEntityId)
			end
			return a.Frame < b.Frame
		end)
	return { Version = 1, Entries = entries }
end

function HitHistory:ValidateRollbackState(state, context)
	if type(state) ~= "table" or state.Version ~= 1 or not isDenseArray(state.Entries) then
		return false, "Invalid HitHistory state schema"
	end
	context = context or {}
	local function has(map, id)
		return id ~= nil and type(map) == "table" and map[id] ~= nil
	end
	local seen = {}
	for index, entry in ipairs(state.Entries) do
		if type(entry) ~= "table" or not validStableId(entry.AttackInstanceId) then
			return false, "Invalid HitHistory entry at index " .. tostring(index)
		end
		if entry.ScopeType ~= "AttackInstance" and entry.ScopeType ~= "Hitbox" then
			return false, "Invalid HitHistory scope type at index " .. tostring(index)
		end
		if entry.ScopeType == "Hitbox" and not validStableId(entry.ScopeId) then
			return false, "Hitbox scope requires a stable ID at index " .. tostring(index)
		end
		if entry.ScopeType == "AttackInstance" and entry.ScopeId ~= nil then return false, "AttackInstance scope must not carry ScopeId" end
		if type(entry.TargetIsNil) ~= "boolean" then return false, "Invalid target nil marker" end
		if not entry.TargetIsNil and not validStableId(entry.TargetEntityId) then return false, "Target ID is missing or invalid" end
		if entry.TargetIsNil and entry.TargetEntityId ~= nil then return false, "Nil target must not carry TargetEntityId" end
		if entry.HitboxId ~= nil and not validStableId(entry.HitboxId) then return false, "Invalid referenced Hitbox ID" end
		if entry.HurtboxId ~= nil and not validStableId(entry.HurtboxId) then return false, "Invalid referenced Hurtbox ID" end
		if type(entry.Frame) ~= "number" or entry.Frame ~= entry.Frame or entry.Frame == math.huge or entry.Frame == -math.huge or entry.Frame < 0 or entry.Frame % 1 ~= 0 then
			return false, "Invalid HitHistory frame at index " .. tostring(index)
		end
		local function token(value)
			local encoded = value == nil and "" or tostring(value)
			return tostring(#encoded) .. ":" .. encoded
		end
		local identity = token(entry.AttackInstanceId) .. token(entry.ScopeType)
			.. token(entry.ScopeId) .. token(entry.TargetIsNil and nil or entry.TargetEntityId)
		if seen[identity] then return false, "Duplicate HitHistory target/scope record" end
		seen[identity] = true
		if context.RequireReferences then
			if not has(context.AttackInstancesById, entry.AttackInstanceId) then return false, "Missing AttackInstance " .. tostring(entry.AttackInstanceId) end
			if entry.ScopeType == "Hitbox" and not has(context.HitboxesById, entry.ScopeId) then return false, "Missing Hitbox scope " .. tostring(entry.ScopeId) end
			if not entry.TargetIsNil and not has(context.EntitiesById, entry.TargetEntityId) then return false, "Missing target entity " .. tostring(entry.TargetEntityId) end
			if entry.HitboxId ~= nil and not has(context.HitboxesById, entry.HitboxId) then return false, "Missing referenced Hitbox " .. tostring(entry.HitboxId) end
			if entry.HurtboxId ~= nil and not has(context.HurtboxesById, entry.HurtboxId) then return false, "Missing referenced Hurtbox " .. tostring(entry.HurtboxId) end
		end
	end
	return true
end

-- Prepare a replacement map without mutating the active history. The caller commits only
-- after every combat subsystem has prepared successfully.
function HitHistory:PrepareRollbackRestore(state, context)
	local valid, reason = self:ValidateRollbackState(state, context)
	if not valid then return nil, reason end
	context = context or {}
	assert(type(context.AttackInstancesById) == "table" and type(context.EntitiesById) == "table"
		and type(context.HitboxesById) == "table" and type(context.HurtboxesById) == "table",
		"PrepareRollbackRestore requires complete stable-ID reference maps")
	local staged = {}
	for _, entry in ipairs(state.Entries) do
		local attackInstance = context.AttackInstancesById[entry.AttackInstanceId]
		local scopeKey = entry.ScopeType == "AttackInstance" and ATTACK_SCOPE or context.HitboxesById[entry.ScopeId]
		local target = entry.TargetIsNil and NIL_TARGET or context.EntitiesById[entry.TargetEntityId]
		local scopes = staged[attackInstance]
		if not scopes then scopes = {}; staged[attackInstance] = scopes end
		local targets = scopes[scopeKey]
		if not targets then targets = {}; scopes[scopeKey] = targets end
		targets[target] = {
			Frame = entry.Frame,
			Hitbox = entry.HitboxId ~= nil and context.HitboxesById[entry.HitboxId] or nil,
			Hurtbox = entry.HurtboxId ~= nil and context.HurtboxesById[entry.HurtboxId] or nil,
		}
	end
	return function()
		for attackInstance in pairs(self.Entries) do
			if attackInstance._HitHistory == self then attackInstance._HitHistory = nil end
		end
		self.Entries = staged
		for attackInstance in pairs(staged) do attackInstance._HitHistory = self end
	end
end

return HitHistory
