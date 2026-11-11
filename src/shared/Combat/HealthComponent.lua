local Component = require(script.Parent.Parent.Core.Component)
local EntityState = require(script.Parent.Parent.Core.EntityState)
local HealthChangedEvent = require(script.Parent.HealthChangedEvent)

local HealthComponent = {}
HealthComponent.__index = HealthComponent
HealthComponent.RollbackKey = "Combat.HealthComponent"
setmetatable(HealthComponent, { __index = Component })

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

local function validateHealth(value, label)
	assert(isFiniteNumber(value) and value >= 0, label .. " must be a finite non-negative number")
end

function HealthComponent.new(options)
	options = options or {}
	assert(type(options) == "table", "HealthComponent.new() expects an options table or nil")
	local maxHealth = options.MaxHealth or 100
	assert(isFiniteNumber(maxHealth) and maxHealth > 0,
		"HealthComponent MaxHealth must be a finite positive number")
	local currentHealth = options.CurrentHealth
	if currentHealth == nil then
		currentHealth = maxHealth
	end
	validateHealth(currentHealth, "HealthComponent CurrentHealth")
	assert(currentHealth <= maxHealth, "CurrentHealth cannot exceed MaxHealth")

	local self = Component.new()
	self._maxHealth = maxHealth
	self._currentHealth = currentHealth
	return setmetatable(self, HealthComponent)
end

function HealthComponent:Init()
	if self._currentHealth == 0 and self.Entity:GetState() ~= EntityState.Dead then
		self.Entity:SetState(EntityState.Dead)
	end
end

function HealthComponent:GetHealth()
	return self._currentHealth
end

function HealthComponent:GetMaxHealth()
	return self._maxHealth
end

function HealthComponent:GetHealthRatio()
	return self._currentHealth / self._maxHealth
end

function HealthComponent:SetMaxHealth(maxHealth, context)
	assert(isFiniteNumber(maxHealth) and maxHealth > 0,
		"HealthComponent:SetMaxHealth() expects a finite positive number")
	local oldHealth = self._currentHealth
	self._maxHealth = maxHealth
	self._currentHealth = math.min(self._currentHealth, maxHealth)
	if self._currentHealth == oldHealth then
		return nil
	end
	context = context or {}
	return HealthChangedEvent.new({
		Entity = self.Entity,
		OldHealth = oldHealth,
		NewHealth = self._currentHealth,
		MaxHealth = self._maxHealth,
		Reason = "MaxHealth",
		Frame = context.Frame,
		Time = context.Time,
	})
end

function HealthComponent:Heal(amount, context)
	validateHealth(amount, "Heal amount")
	local entity = self.Entity
	if amount == 0 or not entity or entity.Destroyed or entity:IsDead() then
		return nil
	end
	local oldHealth = self._currentHealth
	self._currentHealth = math.min(self._maxHealth, oldHealth + amount)
	if self._currentHealth == oldHealth then
		return nil
	end
	context = context or {}
	return HealthChangedEvent.new({
		Entity = entity,
		OldHealth = oldHealth,
		NewHealth = self._currentHealth,
		MaxHealth = self._maxHealth,
		Reason = context.Reason or "Heal",
		Frame = context.Frame,
		Time = context.Time,
		Source = context.Source,
		StatusName = context.StatusName,
		EffectId = context.EffectId,
	})
end

function HealthComponent:_ApplyResolvedDamage(request, finalDamage)
	assert(isFiniteNumber(finalDamage) and finalDamage >= 0,
		"Resolved damage must be a finite non-negative number")
	local entity = self.Entity
	if not entity or entity.Destroyed or entity:IsDead() then
		return nil
	end

	local oldHealth = self._currentHealth
	local newHealth = math.max(0, oldHealth - finalDamage)
	local appliedAmount = oldHealth - newHealth
	self._currentHealth = newHealth

	local died = newHealth == 0 and entity:GetState() ~= EntityState.Dead
	if died then
		entity:SetState(EntityState.Dead)
	end

	return {
		OldHealth = oldHealth,
		NewHealth = newHealth,
		AppliedAmount = appliedAmount,
		Changed = newHealth ~= oldHealth,
		Died = died,
		Request = request,
	}
end

function HealthComponent:CaptureRollbackState()
	return { Version = 1, MaxHealth = self._maxHealth, CurrentHealth = self._currentHealth }
end

function HealthComponent:ValidateRollbackState(state)
	if type(state) ~= "table" or getmetatable(state) ~= nil or state.Version ~= 1 then
		return false, "Invalid HealthComponent state version"
	end
	if not isFiniteNumber(state.MaxHealth) or state.MaxHealth <= 0 then
		return false, "MaxHealth must be finite and positive"
	end
	if not isFiniteNumber(state.CurrentHealth) or state.CurrentHealth < 0 or state.CurrentHealth > state.MaxHealth then
		return false, "CurrentHealth is outside valid bounds"
	end
	for key in pairs(state) do
		if key ~= "Version" and key ~= "MaxHealth" and key ~= "CurrentHealth" then
			return false, "Unknown HealthComponent state field: " .. tostring(key)
		end
	end
	return true
end

function HealthComponent:RestoreRollbackState(state)
	local valid, reason = self:ValidateRollbackState(state)
	if not valid then return false, reason end
	self._maxHealth = state.MaxHealth
	self._currentHealth = state.CurrentHealth
	return true
end

return HealthComponent
