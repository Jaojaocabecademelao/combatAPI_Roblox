local ComboEvent = {}
ComboEvent.__index = ComboEvent
ComboEvent.Type = table.freeze({ Started = "ComboStarted", Hit = "ComboHit", Ended = "ComboEnded", Broken = "ComboBroken" })
function ComboEvent.new(data)
	assert(type(data) == "table", "ComboEvent.new() expects data")
	return setmetatable({ Type = data.Type, ComboId = data.ComboId, Frame = data.Frame,
		Attacker = data.Attacker, Defender = data.Defender, AttackerId = data.AttackerId,
		DefenderId = data.DefenderId, HitEvent = data.HitEvent, HitCount = data.HitCount,
		ConfirmedHitCount = data.ConfirmedHitCount, BlockedHitCount = data.BlockedHitCount,
		Damage = data.Damage, ChipDamage = data.ChipDamage, Reason = data.Reason,
		IsCounterHit = data.IsCounterHit == true, Combo = data.Combo }, ComboEvent)
end
return ComboEvent
