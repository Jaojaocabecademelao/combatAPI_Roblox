local AttackInstance = {}
AttackInstance.__index = AttackInstance
local OffensiveProperties = require(script.Parent.OffensiveProperties)
local Serializer = require(script.Parent.Parent.Simulation.StateSerializer)

local CUSTOM_DATA_LIMITS = { MaxEntries = 256, MaxDepth = 8 }

local function mergeCustomData(base, overrides)
	if overrides == nil then return base end
	if base == nil then return overrides end
	local merged = table.clone(base)
	for key, value in pairs(overrides) do merged[key] = value end
	return table.freeze(merged)
end

-- AttackInstance owns per-execution identity and lifecycle; its ID comes from an injected World generator.

function AttackInstance.new(attack, ownerEntity, idGenerator, options)
	local explicitId, rawOverrides
	if type(options) == "table" then
		explicitId, rawOverrides = options.Id, options.CustomDataOverrides
	else
		explicitId = options
	end
	assert(type(attack) == "table" and attack.Id ~= nil,
		"AttackInstance.new() requires an Attack definition")
	if idGenerator == nil and ownerEntity and ownerEntity.World then
		idGenerator = ownerEntity.World.IdGenerator
	end
	if explicitId == nil then
		assert(idGenerator and type(idGenerator.Next) == "function",
			"AttackInstance.new() requires an IdGenerator or an owner in a World")
	else
		assert((type(explicitId) == "number" and explicitId == explicitId and explicitId > -math.huge and explicitId < math.huge and explicitId % 1 == 0)
			or (type(explicitId) == "string" and explicitId ~= ""), "AttackInstance explicit ID must be a stable integer or non-empty string")
	end
	local properties = attack.OffensiveProperties
	if type(properties) ~= "table" or not table.isfrozen(properties) then
		properties = OffensiveProperties.new({
			Damage = attack.Damage,
			Hitstun = attack.Hitstun,
			HasHitstun = attack.Hitstun ~= nil,
			Defense = attack.Defense,
			Priority = attack.Priority,
			CanClash = attack.CanClash,
				CustomData = attack.CustomData,
		})
	end

	local overrides
	if rawOverrides ~= nil then
		assert(type(rawOverrides) == "table" and getmetatable(rawOverrides) == nil,
			"AttackInstance CustomDataOverrides must be a plain table")
		local ok, clone = pcall(Serializer.CloneSerializable, rawOverrides, CUSTOM_DATA_LIMITS)
		assert(ok, "AttackInstance CustomDataOverrides must be plain serializable data: " .. tostring(clone))
		if next(clone) ~= nil then overrides = Serializer.Freeze(clone) end
	end
	if overrides ~= nil then
		properties = OffensiveProperties.WithCustomData(properties, mergeCustomData(properties.CustomData, overrides))
	end

	return setmetatable({
		Id = explicitId ~= nil and explicitId or idGenerator:Next(),
		Attack = attack,
		OffensiveProperties = properties,
		CustomDataOverrides = overrides,
		Priority = properties.Priority,
		CanClash = properties.CanClash,
		OwnerEntity = ownerEntity,
		State = "Created",
		Hitboxes = {},
	}, AttackInstance)
end

function AttackInstance:GetOffensiveProperties()
	return self.OffensiveProperties
end

function AttackInstance:Activate()
	assert(self.State ~= "Finished", "Cannot activate a finished AttackInstance")
	self.State = "Active"
	return self
end

function AttackInstance:AddHitbox(hitbox)
	assert(self.State ~= "Finished", "Cannot add a Hitbox to a finished AttackInstance")
	assert(hitbox and hitbox.CombatRegionType == "Hitbox",
		"AttackInstance:AddHitbox() expects a Hitbox")
	assert(hitbox.AttackInstance == nil or hitbox.AttackInstance == self,
		"Hitbox already belongs to another AttackInstance")
	self.Hitboxes[hitbox] = true
	hitbox.AttackInstance = self
	return hitbox
end

function AttackInstance:RemoveHitbox(hitbox)
	if not self.Hitboxes[hitbox] then
		return false
	end
	self.Hitboxes[hitbox] = nil
	if hitbox.AttackInstance == self then
		hitbox.AttackInstance = nil
	end
	return true
end

function AttackInstance:Finish()
	if self.State == "Finished" then
		return false
	end
	self.State = "Finished"
	if self._HitHistory then
		self._HitHistory:RemoveAttackInstance(self)
	end
	for hitbox in pairs(self.Hitboxes) do
		if hitbox.AttackInstance == self then
			hitbox.AttackInstance = nil
			hitbox:SetEnabled(false)
		end
	end
	table.clear(self.Hitboxes)
	return true
end

function AttackInstance:Destroy()
	return self:Finish()
end

return AttackInstance
