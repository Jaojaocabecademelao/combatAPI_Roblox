local DefenseEvent = {}
DefenseEvent.__index = DefenseEvent

function DefenseEvent.new(hitEvent, result, frame)
	return setmetatable({
		Result = result,
		HitEvent = hitEvent,
		Attacker = hitEvent.Attacker,
		Defender = hitEvent.Target,
		Target = hitEvent.Target,
		Attack = hitEvent.Attack,
		AttackInstance = hitEvent.AttackInstance,
		AttackInstanceId = hitEvent.AttackInstanceId,
		OffensiveProperties = hitEvent.OffensiveProperties,
		Frame = frame,
	}, DefenseEvent)
end

return DefenseEvent
