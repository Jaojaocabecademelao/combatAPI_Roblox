local HealthChangedEvent = {}
HealthChangedEvent.__index = HealthChangedEvent

function HealthChangedEvent.new(data)
	assert(type(data) == "table", "HealthChangedEvent.new() expects an event data table")
	return setmetatable({
		Entity = data.Entity,
		OldHealth = data.OldHealth,
		NewHealth = data.NewHealth,
		Delta = data.NewHealth - data.OldHealth,
		MaxHealth = data.MaxHealth,
		Reason = data.Reason,
		DamageRequest = data.DamageRequest,
		Frame = data.Frame,
		Time = data.Time,
		Source = data.Source,
		StatusName = data.StatusName,
		EffectId = data.EffectId,
	}, HealthChangedEvent)
end

return HealthChangedEvent
