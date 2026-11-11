local DamageEvent = {}
DamageEvent.__index = DamageEvent

function DamageEvent.new(data)
	assert(type(data) == "table", "DamageEvent.new() expects an event data table")
	return setmetatable({
		Target = data.Target,
		RequestedAmount = data.RequestedAmount,
		AppliedAmount = data.AppliedAmount,
		Amount = data.AppliedAmount,
		Type = data.Type,
		Source = data.Source,
		SourceEntity = data.Source,
		AttackInstance = data.AttackInstance,
		HitEvent = data.HitEvent,
		OffensiveProperties = data.OffensiveProperties,
		OldHealth = data.OldHealth,
		NewHealth = data.NewHealth,
		Frame = data.Frame,
		Time = data.Time,
		HitstunFrames = data.HitstunFrames,
	}, DamageEvent)
end

return DamageEvent
