local JuggleEvent = {}
JuggleEvent.__index = JuggleEvent
JuggleEvent.Type = table.freeze({
	Started = "JuggleStarted", Hit = "JuggleHit", Ended = "JuggleEnded",
	LimitReached = "JuggleLimitReached", ReJuggled = "ReJuggle", Rejected = "JuggleRejected",
})
function JuggleEvent.new(data)
	return setmetatable(data, JuggleEvent)
end
return JuggleEvent
