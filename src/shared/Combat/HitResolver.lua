local HitResolver = {}
HitResolver.__index = HitResolver

function HitResolver.new()
	return setmetatable({}, HitResolver)
end

function HitResolver:Resolve(collisionResults)
	assert(type(collisionResults) == "table", "HitResolver:Resolve() expects a collision result list")

	-- This stage only copies collision facts. HitProcessor applies attack policy and filtering.
	local hitEvents = {}
	for _, result in ipairs(collisionResults) do
		table.insert(hitEvents, {
			Hitbox = result.Hitbox,
			Hurtbox = result.Hurtbox,
			Attacker = result.Attacker,
			Target = result.Target,
			ContactType = result.ContactType,
			IsFirstContact = result.IsFirstContact,
			IsContinuous = result.IsContinuous,
			AttackId = result.Hitbox.AttackId,
			Priority = result.Hitbox.Priority,
			ClashGroup = result.Hitbox.ClashGroup,
			Damage = result.Hitbox.Damage,
		})
	end

	return hitEvents
end

return HitResolver
