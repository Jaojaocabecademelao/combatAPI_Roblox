local HitEvent = {}
HitEvent.__index = HitEvent

function HitEvent.new(data)
	assert(type(data) == "table", "HitEvent.new() expects an event data table")
	return setmetatable({
		AttackInstance = data.AttackInstance,
		Attack = data.Attack,
		Attacker = data.Attacker,
		Target = data.Target,
		Hitbox = data.Hitbox,
		Hurtbox = data.Hurtbox,
		AttackInstanceId = data.AttackInstanceId,
		AttackId = data.AttackId,
		AttackerEntityId = data.AttackerEntityId,
		TargetEntityId = data.TargetEntityId,
		HitboxId = data.HitboxId,
		HurtboxId = data.HurtboxId,
		Frame = data.Frame,
		Time = data.Time,
		ContactType = data.ContactType,
		IsFirstContact = data.IsFirstContact,
		IsContinuous = data.IsContinuous,
		Priority = data.Priority or 0,
		ClashGroup = data.ClashGroup,
		Damage = data.Damage,
		Hitstun = data.Hitstun,
		OffensiveProperties = data.OffensiveProperties,
	}, HitEvent)
end

return HitEvent
