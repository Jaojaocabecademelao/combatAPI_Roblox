local Status = require(script.Parent.Status)

local Hitstun = {}
Hitstun.__index = Hitstun
Hitstun.RollbackTypeId = "Combat.Hitstun"
Hitstun.RollbackVersion = 1
setmetatable(Hitstun, { __index = Status })

function Hitstun.new(options)
	assert(type(options) == "table", "Hitstun.new() expects an options table")
	assert(type(options.DurationFrames) == "number" and options.DurationFrames > 0
		and options.DurationFrames < math.huge and options.DurationFrames % 1 == 0,
		"Hitstun DurationFrames must be a positive finite integer")
	local status = Status.new({
		Name = "Hitstun",
		DurationFrames = options.DurationFrames,
		ReapplicationPolicy = options.ReapplicationPolicy or "Refresh",
		Source = options.Source,
		AttackInstance = options.AttackInstance,
		HitEvent = options.HitEvent,
		DamageEvent = options.DamageEvent,
	})
	return setmetatable(status, Hitstun)
end

return Hitstun
