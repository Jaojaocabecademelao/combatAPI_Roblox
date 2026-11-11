local Component = require(script.Parent.Parent.Core.Component)
local EntityState = require(script.Parent.Parent.Core.EntityState)
local StatusEvent = require(script.Parent.StatusEvent)
local HitstopComponent = require(script.Parent.HitstopComponent)
local HealthComponent = require(script.Parent.HealthComponent)
local StatusCatalog = require(script.Parent.StatusCatalog)

local StatusContainer = {}
StatusContainer.__index = StatusContainer
StatusContainer.RollbackKey = "Combat.StatusContainer"
setmetatable(StatusContainer, { __index = Component })

local function copyArray(values)
	local result = {}
	for _, value in ipairs(values) do result[#result + 1] = value end
	return result
end

local function isDenseArray(values)
	if type(values) ~= "table" then return false end
	local count, maxIndex = 0, 0
	for key in pairs(values) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
		count += 1
		if key > maxIndex then maxIndex = key end
	end
	return count == maxIndex
end

local function finite(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function StatusContainer.new(statusCatalog)
	local self = Component.new()
	self._statuses = {}
	self._events = {}
	self._effectRequests = {}
	self.StatusCatalog = statusCatalog or StatusCatalog.new()
	assert(type(self.StatusCatalog) == "table"
		and type(self.StatusCatalog.Resolve) == "function"
		and type(self.StatusCatalog.Create) == "function"
		and type(self.StatusCatalog.CaptureManifest) == "function"
		and type(self.StatusCatalog.ValidateManifest) == "function",
		"StatusContainer requires a valid StatusCatalog")
	return setmetatable(self, StatusContainer)
end

function StatusContainer:GetStatusCatalog()
	return self.StatusCatalog
end

function StatusContainer:_contains(status)
	for _, current in ipairs(self._statuses) do if current == status then return true end end
	return false
end

function StatusContainer:_remove(status, reason, eventType)
	for index, current in ipairs(self._statuses) do
		if current == status then
			table.remove(self._statuses, index)
			status:End(reason)
			table.insert(self._events, StatusEvent.new(eventType or "StatusRemoved", self.Entity, status, reason))
			return true
		end
	end
	return false
end

function StatusContainer:AddStatus(status, context)
	assert(type(status) == "table" and type(status.Name) == "string"
		and type(status.Start) == "function" and type(status.Update) == "function"
		and type(status.End) == "function",
		"StatusContainer:AddStatus() expects a Status instance")
	assert(self.Entity ~= nil and not self.Entity.Destroyed,
		"Cannot add a status to a detached or destroyed entity")
	if not self:IsEnabled() or self.Entity:GetState() ~= EntityState.Alive then return nil, "EntityUnavailable" end
	assert(not status.Active and status.Entity == nil, "Status is already active")
	if type(status.PeriodicEffects) == "table" and #status.PeriodicEffects > 0 then
		if not self.Entity:GetComponent(HealthComponent) then
			return nil, "PeriodicStatusRequiresHealthComponent"
		end
		local world = self.Entity.World
		if not world or type(world.GetDamageResolver) ~= "function" or not world:GetDamageResolver() then
			return nil, "PeriodicStatusRequiresDamageResolver"
		end
		if type(status.AdvancePeriodicEffects) ~= "function" then
			return nil, "PeriodicStatusMissingScheduler"
		end
	end

	local existing = self:GetStatus(status.Name)
	if existing then
		local policy = status.ReapplicationPolicy or existing.ReapplicationPolicy or "Refresh"
		if policy == "Ignore" then
			return existing, "Ignored"
		elseif policy == "Refresh" then
			existing:Refresh(status.DurationFrames, context or status)
			table.insert(self._events, StatusEvent.new("StatusRefreshed", self.Entity, existing))
			return existing, "Refreshed"
		elseif policy == "Extend" then
			if existing.RemainingFrames ~= nil and status.DurationFrames ~= nil then
				existing:Refresh(existing.RemainingFrames + status.DurationFrames, context or status)
			elseif existing.RemainingFrames == nil or status.DurationFrames == nil then
				existing:Refresh(nil, context or status)
			end
			table.insert(self._events, StatusEvent.new("StatusRefreshed", self.Entity, existing))
			return existing, "Extended"
		elseif policy == "Replace" then
			self:_remove(existing, "Replaced")
		elseif policy ~= "Stack" then
			error("Unsupported Status reapplication policy: " .. tostring(policy))
		end
	end

	status:Start(self.Entity, context)
	table.insert(self._statuses, status)
	table.insert(self._events, StatusEvent.new("StatusAdded", self.Entity, status))
	return status, "Added"
end

function StatusContainer:RemoveStatus(nameOrStatus, reason)
	local status = nameOrStatus
	if type(nameOrStatus) == "string" then status = self:GetStatus(nameOrStatus) end
	if not status then return false end
	return self:_remove(status, reason or "Removed")
end

function StatusContainer:HasStatus(name)
	return self:GetStatus(name) ~= nil
end

function StatusContainer:HasTag(tag)
	assert(type(tag) == "string" and tag ~= "", "Status tag must be a non-empty string")
	for _, status in ipairs(self._statuses) do
		if status.Active and status:IsEnabled() and type(status.HasTag) == "function"
			and status:HasTag(tag) then
			return true
		end
	end
	return false
end

function StatusContainer:GetModifier(name)
	assert(type(name) == "string" and name ~= "", "Status modifier name must be a non-empty string")
	local total = 0
	for _, status in ipairs(self._statuses) do
		if status.Active and status:IsEnabled() and type(status.GetModifier) == "function" then
			total += status:GetModifier(name)
			assert(finite(total), "Aggregated Status modifier is not finite")
		end
	end
	return total
end

function StatusContainer:RemoveByTag(tag, reason)
	assert(type(tag) == "string" and tag ~= "", "Status tag must be a non-empty string")
	local snapshot, removed = copyArray(self._statuses), 0
	for _, status in ipairs(snapshot) do
		if status.Active and type(status.HasTag) == "function" and status:HasTag(tag)
			and self:_remove(status, reason or "TagRemoved") then
			removed += 1
		end
	end
	return removed
end

function StatusContainer:GetStatus(name)
	for _, status in ipairs(self._statuses) do
		if status.Active and status.Name == name then return status end
	end
	return nil
end

function StatusContainer:GetStatuses(name)
	local result = {}
	for _, status in ipairs(self._statuses) do
		if status.Active and (name == nil or status.Name == name) then result[#result + 1] = status end
	end
	return result
end

function StatusContainer:ClearStatuses(reason)
	local snapshot = copyArray(self._statuses)
	for _, status in ipairs(snapshot) do self:_remove(status, reason or "Cleared") end
end

function StatusContainer:Step(deltaTime)
	if not self:IsEnabled() or not self.Entity or self.Entity.Destroyed then return end
	if self.Entity:GetState() == EntityState.Dead then self:ClearStatuses("EntityDead"); return end
	local hitstop = self.Entity:GetComponent(HitstopComponent)
	if hitstop and hitstop:IsFrozen() then return end

	local snapshot = copyArray(self._statuses)
	for _, status in ipairs(snapshot) do
		if not self:IsEnabled() then break end
		if not self.Entity or self.Entity.Destroyed or self.Entity:GetState() == EntityState.Dead then
			local reason = self.Entity and self.Entity:GetState() == EntityState.Dead and "EntityDead" or "ContainerDetached"
			self:ClearStatuses(reason)
			break
		end
		if self:_contains(status) and status.Active and status:IsEnabled() then
			status:Update(deltaTime)
			if self:_contains(status) and status.Active and status:IsEnabled()
				and type(status.AdvancePeriodicEffects) == "function" then
				for _, effect in ipairs(status:AdvancePeriodicEffects()) do
					table.insert(self._effectRequests, {
						Type = effect.Type,
						EffectId = effect.Id,
						Amount = effect.Amount,
						DamageType = effect.DamageType,
						Target = self.Entity,
						Source = status.Source,
						StatusName = status.Name,
						Status = status,
					})
				end
			end
			if self:_contains(status) and status.Active and status.RemainingFrames ~= nil then
				status.RemainingFrames -= 1
				if status.RemainingFrames <= 0 then self:_remove(status, "Expired", "StatusExpired") end
			end
		end
	end
end

function StatusContainer:GetEvents()
	return copyArray(self._events)
end

function StatusContainer:ClearEvents()
	table.clear(self._events)
end

function StatusContainer:DrainEvents()
	local events = copyArray(self._events)
	table.clear(self._events)
	return events
end

function StatusContainer:DrainEffectRequests()
	local requests = copyArray(self._effectRequests)
	table.clear(self._effectRequests)
	return requests
end

function StatusContainer:Destroy()
	self:ClearStatuses("ContainerDestroyed")
	table.clear(self._effectRequests)
end

function StatusContainer:CaptureRollbackState(context)
	if context == nil and self.Entity and self.Entity.World then
		local entitiesById = {}
		for _, entity in ipairs(self.Entity.World:GetEntities()) do entitiesById[entity.Id] = entity end
		context = { World = self.Entity.World, EntitiesById = entitiesById }
	end
	local statuses = {}
	for index, status in ipairs(self._statuses) do
		assert(type(status.CaptureRollbackState) == "function" and type(status.ValidateRollbackState) == "function"
			and type(status.RestoreRollbackState) == "function",
			"Custom status must implement the rollback contract: " .. tostring(status.Name))
		local typeId = status.RollbackTypeId
		local factory, version = self.StatusCatalog:Resolve(typeId)
		assert(factory and status.RollbackVersion == version,
			"StatusCatalog has no matching versioned factory for " .. tostring(typeId))
		local state = status:CaptureRollbackState(context)
		local valid, detail = status:ValidateRollbackState(state, context)
		assert(valid == true, "Status rejected its own rollback state: " .. tostring(detail))
		statuses[index] = state
	end
	return {
		Version = 2,
		CatalogManifest = self.StatusCatalog:CaptureManifest(),
		Statuses = statuses,
	}
end

function StatusContainer:ValidateRollbackState(state, context)
	if type(state) ~= "table" or getmetatable(state) ~= nil or state.Version ~= 2
		or not isDenseArray(state.Statuses) then return false, "Invalid StatusContainer rollback state" end
	for key in pairs(state) do
		if key ~= "Version" and key ~= "CatalogManifest" and key ~= "Statuses" then
			return false, "Unknown StatusContainer field: " .. tostring(key)
		end
	end
	local manifestOk, manifestError = self.StatusCatalog:ValidateManifest(state.CatalogManifest)
	if not manifestOk then return false, "StatusCatalog mismatch: " .. tostring(manifestError) end
	local nonStacking = {}
	for _, saved in ipairs(state.Statuses) do
		if type(saved) ~= "table" or getmetatable(saved) ~= nil then return false, "Invalid saved status" end
		local factory, factoryError = self.StatusCatalog:Resolve(saved.TypeId, saved.TypeVersion)
		if not factory then return false, factoryError end
		local status, createError = self.StatusCatalog:Create(saved.TypeId, saved.TypeVersion, context)
		if not status then return false, createError end
		if type(status.ValidateRollbackState) ~= "function" or type(status.RestoreRollbackState) ~= "function" then
			return false, "Status factory did not return a rollback-capable instance"
		end
		local valid, detail = status:ValidateRollbackState(saved, context)
		if valid ~= true then return false, "Status state rejected: " .. tostring(detail) end
		if saved.ReapplicationPolicy ~= "Stack" then
			if nonStacking[saved.Name] then return false, "Duplicate non-stacking status" end
			nonStacking[saved.Name] = true
		end
	end
	return true
end

function StatusContainer:RestoreRollbackState(state, context)
	local valid, detail = self:ValidateRollbackState(state, context)
	if not valid then return false, detail end
	local restored = {}
	for _, saved in ipairs(state.Statuses) do
		local status, createError = self.StatusCatalog:Create(saved.TypeId, saved.TypeVersion, context)
		if not status then return false, createError end
		local ok, restoreError = status:RestoreRollbackState(saved, self.Entity, context)
		if ok ~= true then return false, restoreError end
		restored[#restored + 1] = status
	end
	self._statuses = restored
	table.clear(self._effectRequests)
	-- Status events are outputs and replay recreates them; restoring must not republish them.
	table.clear(self._events)
	return true
end

return StatusContainer
