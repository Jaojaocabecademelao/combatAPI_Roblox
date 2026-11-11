local ComboResult = {}
ComboResult.__index = ComboResult
ComboResult.Type = table.freeze({ Started = "Started", Continued = "Continued", Ended = "Ended", Ignored = "Ignored", Broken = "Broken" })
function ComboResult.new(data)
	return setmetatable({ Type = data.Type, ComboId = data.ComboId, Combo = data.Combo, HitEvent = data.HitEvent, Frame = data.Frame, Reason = data.Reason }, ComboResult)
end
return ComboResult
