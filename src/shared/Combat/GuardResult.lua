local GuardResult = {}
GuardResult.__index = GuardResult

GuardResult.Blocked = "Blocked"
GuardResult.Broken = "Broken"
GuardResult.Ignored = "Ignored"
GuardResult.Invalid = "Invalid"

function GuardResult.new(options)
	options = options or {}
	assert(type(options) == "table", "GuardResult.new() expects an options table")
	return setmetatable({
		Type = options.Type or GuardResult.Blocked,
		Result = options.Result or options.Type or GuardResult.Blocked,
		HitEvent = options.HitEvent,
		DefenseEvent = options.DefenseEvent,
		Attacker = options.Attacker,
		Defender = options.Defender,
		Target = options.Target or options.Defender,
		AttackInstance = options.AttackInstance,
		AttackInstanceId = options.AttackInstanceId,
		Frame = options.Frame or 0,
		Time = options.Time,
		PreviousGuard = options.PreviousGuard,
		GuardDamage = options.GuardDamage or 0,
		RemainingGuard = options.RemainingGuard,
		ChipDamage = options.ChipDamage or 0,
		BlockstunFrames = options.BlockstunFrames or 0,
		GuardBroken = options.GuardBroken == true,
	}, GuardResult)
end

return GuardResult
