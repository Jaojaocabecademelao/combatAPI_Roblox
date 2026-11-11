local Juggle = {}
Juggle.__index = Juggle

function Juggle.new(data)
	assert(type(data) == "table", "Juggle.new() expects a table")
	return setmetatable({
		Target = data.Target,
		TargetId = data.TargetId,
		Attacker = data.Attacker,
		AttackerId = data.AttackerId,
		AirState = data.AirState,
		LaunchFrame = data.LaunchFrame,
		LastJuggleHitFrame = data.LastJuggleHitFrame,
		JuggleCount = 0,
		ReJuggleCount = 0,
		MaxJuggleHits = data.Profile.MaxJuggleHits,
		State = "Active",
		Profile = data.Profile,
		RecoveryRemaining = 0,
	}, Juggle)
end

return Juggle
