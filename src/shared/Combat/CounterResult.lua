local CounterResult = {}
CounterResult.__index = CounterResult

CounterResult.Type = table.freeze({ Normal = "Normal", CounterHit = "CounterHit" })

function CounterResult.new(hitEvent, resultType)
	return setmetatable({
		Type = resultType,
		HitEvent = hitEvent,
		AttackInstance = hitEvent.AttackInstance,
		AttackInstanceId = hitEvent.AttackInstanceId
			or (hitEvent.AttackInstance and hitEvent.AttackInstance.Id),
		Attacker = hitEvent.Attacker,
		AttackerId = hitEvent.AttackerEntityId
			or (hitEvent.Attacker and hitEvent.Attacker.Id),
		Target = hitEvent.Target,
		TargetId = hitEvent.TargetEntityId or (hitEvent.Target and hitEvent.Target.Id),
		HitboxId = hitEvent.HitboxId or (hitEvent.Hitbox and hitEvent.Hitbox.Id),
		HurtboxId = hitEvent.HurtboxId or (hitEvent.Hurtbox and hitEvent.Hurtbox.Id),
		Frame = hitEvent.Frame or 0,
	}, CounterResult)
end

return CounterResult
