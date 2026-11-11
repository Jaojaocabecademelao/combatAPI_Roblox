local EntityState = require(script.Parent.Parent.Core.EntityState)
local StatusContainer = require(script.Parent.StatusContainer)
local Hitstun = require(script.Parent.Hitstun)

local CombatReactionResolver = {}
CombatReactionResolver.__index = CombatReactionResolver

function CombatReactionResolver.new(world)
	return setmetatable({ World = world }, CombatReactionResolver)
end

function CombatReactionResolver:SetWorld(world)
	self.World = world
	return self
end

function CombatReactionResolver:Process(damageEvents, armorResults, hitEvents)
	assert(type(damageEvents) == "table", "CombatReactionResolver:Process() expects DamageEvents")
	local armorByHit, damageByHit = {}, {}
	for _, result in ipairs(armorResults or {}) do armorByHit[result.HitEvent] = result end
	for _, damageEvent in ipairs(damageEvents) do
		if damageEvent.HitEvent then damageByHit[damageEvent.HitEvent] = damageEvent end
	end
	local orderedHits = hitEvents
	if orderedHits == nil then
		orderedHits = {}
		for _, damageEvent in ipairs(damageEvents) do
			if damageEvent.HitEvent then table.insert(orderedHits, damageEvent.HitEvent) end
		end
	end
	-- Hit reactions are driven by eligible HitEvents, not by Health/Damage existence.
	for _, hitEvent in ipairs(orderedHits) do
		local damageEvent = damageByHit[hitEvent]
		local armor = armorByHit[hitEvent]
		local target = hitEvent.Target
		local frames = damageEvent and damageEvent.HitstunFrames or hitEvent.Hitstun
		if not (armor and armor:Blocks("Hitstun")) and target and not target.Destroyed
			and target:GetState() == EntityState.Alive
		then
			local container = target:GetComponent(StatusContainer)
			if container and frames and frames > 0 then
				container:AddStatus(Hitstun.new({
					DurationFrames = frames,
					Source = damageEvent and damageEvent.Source or hitEvent.Attacker,
					AttackInstance = hitEvent.AttackInstance,
					HitEvent = hitEvent,
					DamageEvent = damageEvent,
				}))
			end
		end
	end

	-- A lethal DamageEvent clears existing statuses immediately in the same fixed step.
	for _, damageEvent in ipairs(damageEvents) do
		local target = damageEvent.Target
		if target and not target.Destroyed and target:GetState() == EntityState.Dead then
			local container = target:GetComponent(StatusContainer)
			if container then
				container:ClearStatuses("EntityDead")
			end
		end
	end
end

-- The resolver is intentionally stateless: persistent reaction state lives in StatusContainer.
-- This contract snapshots no event objects or entity references. Frame-local reaction outputs
-- are owned by StatusContainer and are restored by that component's rollback contract.
function CombatReactionResolver:CaptureRollbackState()
	return { Version = 1 }
end

function CombatReactionResolver:ValidateRollbackState(state)
	if type(state) ~= "table" or getmetatable(state) ~= nil or state.Version ~= 1 then
		return false, "Unsupported CombatReactionResolver state"
	end
	for key in pairs(state) do
		if key ~= "Version" then
			return false, "Unknown CombatReactionResolver state field: " .. tostring(key)
		end
	end
	return true
end

function CombatReactionResolver:PrepareRollbackRestore(state, _world, _context, role)
	local valid, detail = self:ValidateRollbackState(state)
	if not valid then return nil, detail end
	-- There are no mutable resolver fields to commit or compensate. StatusContainer
	-- owns active statuses; its restore recreates them without publishing old events.
	return function()
		if role ~= "Target" and role ~= "Compensation" then
			error("Unknown CombatReactionResolver restore role: " .. tostring(role))
		end
	end
end

return CombatReactionResolver
