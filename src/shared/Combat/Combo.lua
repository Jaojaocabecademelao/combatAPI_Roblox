local Combo = {}
Combo.__index = Combo

function Combo.new(data)
	assert(type(data) == "table", "Combo.new() expects data")
	return setmetatable({
		ComboId = data.ComboId,
		Attacker = data.Attacker,
		Defender = data.Defender,
		AttackerId = data.AttackerId,
		DefenderId = data.DefenderId,
		StartFrame = data.StartFrame,
		LastHitFrame = data.LastHitFrame,
		DurationFrames = 0,
		HitCount = 0,
		ConfirmedHitCount = 0,
		BlockedHitCount = 0,
		Damage = 0,
		ChipDamage = 0,
		State = "Active",
		HitRecords = {},
		Profile = data.Profile,
	}, Combo)
end

return Combo
