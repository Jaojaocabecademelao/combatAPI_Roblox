local ArmorCategory = require(script.Parent.ArmorCategory)

local ArmorResult = {}
ArmorResult.__index = ArmorResult

function ArmorResult.new(hitEvent, categories, handles)
	local allowed, blocked, profileByCategory, handleByCategory, priorityByCategory = {}, {}, {}, {}, {}
	local priority
	local sourceByCategory = {}
	for _, category in ipairs(categories) do
		local handle = handles[category]
		if handle then
			profileByCategory[category] = handle.Profile
			handleByCategory[category] = handle
			priorityByCategory[category] = handle.Priority
			sourceByCategory[category] = handle.Source
			priority = priority == nil and handle.Priority or math.max(priority, handle.Priority)
			if handle.Profile:Allows(category) then
				allowed[category] = true
			else
				blocked[category] = true
			end
		else
			allowed[category] = true
		end
	end
	local attackInstance = hitEvent and hitEvent.AttackInstance
	return setmetatable({
		Type = "ArmorResult",
		HitEvent = hitEvent,
		AttackInstance = attackInstance,
		AttackInstanceId = hitEvent and (hitEvent.AttackInstanceId or (attackInstance and attackInstance.Id)),
		Attacker = hitEvent and hitEvent.Attacker,
		Target = hitEvent and hitEvent.Target,
		TargetId = hitEvent and (hitEvent.TargetEntityId or (hitEvent.Target and hitEvent.Target.Id)),
		Allowed = allowed,
		Blocked = blocked,
		ProfileByCategory = profileByCategory,
		Profiles = profileByCategory,
		ArmorByCategory = handleByCategory,
		Found = next(handleByCategory) ~= nil,
		SourceByCategory = sourceByCategory,
		PriorityByCategory = priorityByCategory,
		Priority = priority or 0,
		Source = sourceByCategory.Hitstun or sourceByCategory.Damage
			or sourceByCategory.Knockback or sourceByCategory.Launch
			or sourceByCategory.Push or sourceByCategory.Pull,
	}, ArmorResult)
end

function ArmorResult:Allows(category)
	if category == "Impulse" then category = ArmorCategory.Knockback end
	return self.Blocked[category] ~= true
end

function ArmorResult:Blocks(category)
	return not self:Allows(category)
end

function ArmorResult:GetProfile(category)
	if category == "Impulse" then category = ArmorCategory.Knockback end
	return self.ProfileByCategory[category]
end

return ArmorResult
