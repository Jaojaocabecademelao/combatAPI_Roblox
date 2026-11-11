local HitPolicy = require(script.Parent.HitPolicy)
local HitHistory = require(script.Parent.HitHistory)
local HitEvent = require(script.Parent.HitEvent)
local OffensiveProperties = require(script.Parent.OffensiveProperties)

local HitProcessor = {}
HitProcessor.__index = HitProcessor

local function compareIds(left, right)
	if left == right then
		return 0
	end
	if left == nil then
		return -1
	elseif right == nil then
		return 1
	end
	if type(left) == type(right) then
		return left < right and -1 or 1
	end
	local leftType = type(left)
	local rightType = type(right)
	return leftType < rightType and -1 or 1
end

local function compareEvents(left, right)
	-- Higher priority first, then stable simulation IDs; no table iteration order enters the result.
	if left.Priority ~= right.Priority then
		return left.Priority > right.Priority
	end
	local keys = {
		"AttackInstanceId",
		"AttackerEntityId",
		"TargetEntityId",
		"HitboxId",
		"HurtboxId",
	}
	for _, key in ipairs(keys) do
		local compared = compareIds(left[key], right[key])
		if compared ~= 0 then
			return compared < 0
		end
	end
	return false
end

local function isLiving(entity)
	return entity == nil or (entity.Destroyed ~= true
		and (type(entity.IsDead) ~= "function" or not entity:IsDead()))
end

local function acceptsFilter(filter, attacker, target, hitbox, hurtbox)
	return filter == nil or filter(attacker, target, hitbox, hurtbox) == true
end

function HitProcessor.new(world)
	return setmetatable({
		World = world,
		HitHistory = HitHistory.new(),
	}, HitProcessor)
end

function HitProcessor:Process(collisionResults, frame, time)
	assert(type(collisionResults) == "table", "HitProcessor:Process() expects collision results")
	assert(type(frame) == "number" and frame >= 0 and frame % 1 == 0,
		"HitProcessor:Process() expects a non-negative integer frame")
	assert(type(time) == "number" and time == time and time > -math.huge and time < math.huge,
		"HitProcessor:Process() expects a finite simulation time")

	self.HitHistory:Prune(self.World)
	local events = {}
	for _, result in ipairs(collisionResults) do
		local hitbox = result.Hitbox
		local hurtbox = result.Hurtbox
		local instance = hitbox.AttackInstance
		local attack = instance and instance.Attack
		local attacker = result.Attacker
		if instance then
			attacker = instance.OwnerEntity
		end
		local target = result.Target

		if isLiving(attacker) and isLiving(target) and (attacker == nil or target == nil or attacker ~= target)
			and (instance == nil or instance.State == "Active")
		then
			local canHit = acceptsFilter(hitbox.CanHit, attacker, target, hitbox, hurtbox)
				and acceptsFilter(attack and attack.CanHit, attacker, target, hitbox, hurtbox)
			if canHit then
				local policy = hitbox.HitPolicy or (attack and attack.HitPolicy) or HitPolicy.Once
				local scope = hitbox.HitScope or (attack and attack.HitScope) or HitPolicy.Scope.AttackInstance
				HitPolicy.Validate(policy)
				HitPolicy.ValidateScope(scope)
				local eligible = instance == nil or self.HitHistory:CanRecord(
					instance, target, hitbox, scope, policy, frame
				)
				if eligible then
					local priority = hitbox.PriorityOverride
					if priority == nil then
						priority = (attack and attack.Priority) or hitbox.Priority or 0
					end
					local attackProperties = instance and instance.OffensiveProperties
					if attackProperties == nil and instance
						and type(instance.GetOffensiveProperties) == "function"
					then
						attackProperties = instance:GetOffensiveProperties()
					end
					if attackProperties == nil and attack then
						attackProperties = attack.OffensiveProperties
					end
					local hasHitstun = attackProperties and attackProperties.HasHitstun
						or (not attackProperties and hitbox.Hitstun ~= nil)
					local hitstun = attackProperties and attackProperties.HasHitstun
						and attackProperties.Hitstun or hitbox.Hitstun
					local needsHitboxFallback = attackProperties
						and ((attackProperties.Damage == nil and hitbox.Damage ~= nil)
							or (not attackProperties.HasHitstun and hitbox.Hitstun ~= nil))
					local canClash = attackProperties and attackProperties.CanClash
					if canClash == nil and attack then
						canClash = attack.CanClash
					end
					local offensiveProperties = attackProperties and not needsHitboxFallback
						and attackProperties or OffensiveProperties.new({
							Damage = (attackProperties and attackProperties.Damage) or hitbox.Damage,
							Hitstun = hitstun,
							HasHitstun = hasHitstun == true,
							Defense = attackProperties and attackProperties.Defense,
							Priority = attackProperties and attackProperties.Priority or priority,
							CanClash = canClash,
				CustomData = attackProperties and attackProperties.CustomData,
						})
					local event = HitEvent.new({
						AttackInstance = instance,
						Attack = attack,
						Attacker = attacker,
						Target = target,
						Hitbox = hitbox,
						Hurtbox = hurtbox,
						AttackInstanceId = instance and instance.Id,
						AttackId = attack and attack.Id or hitbox.AttackId,
						AttackerEntityId = attacker and attacker.Id,
						TargetEntityId = target and target.Id,
						HitboxId = hitbox.Id,
						HurtboxId = hurtbox.Id,
						Frame = frame,
						Time = time,
						ContactType = result.ContactType,
						IsFirstContact = result.IsFirstContact,
						IsContinuous = result.IsContinuous,
						Priority = priority,
						ClashGroup = hitbox.ClashGroup,
						Damage = offensiveProperties.Damage,
						Hitstun = offensiveProperties.HasHitstun and offensiveProperties.Hitstun or nil,
						OffensiveProperties = offensiveProperties,
					})
					table.insert(events, event)
					if instance then
						instance._HitHistory = self.HitHistory
						self.HitHistory:Record(instance, target, hitbox, hurtbox, scope, frame)
					end
				end
			end
		end
	end

	table.sort(events, compareEvents)
	return events
end

function HitProcessor:FinishAttackInstance(attackInstance)
	return self.HitHistory:RemoveAttackInstance(attackInstance)
end

function HitProcessor:RemoveEntity(entity)
	self.HitHistory:RemoveEntity(entity)
end

function HitProcessor:RemoveRegion(region)
	self.HitHistory:RemoveRegion(region)
end

return HitProcessor
