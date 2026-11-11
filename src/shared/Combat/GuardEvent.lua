local GuardEvent = {}
GuardEvent.__index = GuardEvent

function GuardEvent.new(data)
	assert(type(data) == "table", "GuardEvent.new() expects a data table")
	return setmetatable({
		Type = data.Type or "Guard",
		Result = data.Result or "Blocked",
		Frame = data.Frame or 0,
		Time = data.Time,
		HitEvent = data.HitEvent,
		DefenseEvent = data.DefenseEvent,
		Attacker = data.Attacker,
		Defender = data.Defender,
		Target = data.Target or data.Defender,
		AttackInstance = data.AttackInstance,
		AttackInstanceId = data.AttackInstanceId,
		PreviousGuard = data.PreviousGuard,
		GuardDamage = data.GuardDamage or 0,
		RemainingGuard = data.RemainingGuard,
		ChipDamage = data.ChipDamage or 0,
		BlockstunFrames = data.BlockstunFrames or 0,
		GuardBroken = data.GuardBroken == true,
	}, GuardEvent)
end

return GuardEvent
