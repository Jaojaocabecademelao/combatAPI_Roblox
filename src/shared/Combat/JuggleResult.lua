local JuggleResult = {}
JuggleResult.__index = JuggleResult
JuggleResult.Type = table.freeze({
	Started = "Started", Continued = "Continued", Rejected = "Rejected",
	Ended = "Ended", LimitReached = "LimitReached", ReJuggled = "ReJuggled",
})
function JuggleResult.new(data)
	return setmetatable(data, JuggleResult)
end
return JuggleResult
