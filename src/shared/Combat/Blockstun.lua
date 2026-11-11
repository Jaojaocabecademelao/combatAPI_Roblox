local Status = require(script.Parent.Status)

local Blockstun = {}
Blockstun.__index = Blockstun
Blockstun.RollbackTypeId = "Combat.Blockstun"
Blockstun.RollbackVersion = 1
setmetatable(Blockstun, { __index = Status })

function Blockstun.new(options)
	assert(type(options) == "table", "Blockstun.new() expects an options table")
	assert(type(options.DurationFrames) == "number" and options.DurationFrames > 0
		and options.DurationFrames < math.huge and options.DurationFrames % 1 == 0,
		"Blockstun DurationFrames must be a positive finite integer")
	local status = Status.new({
		Name = "Blockstun",
		DurationFrames = options.DurationFrames,
		ReapplicationPolicy = options.ReapplicationPolicy or "Refresh",
		Source = options.Source,
		AttackInstance = options.AttackInstance,
		HitEvent = options.HitEvent,
		DamageEvent = options.DamageEvent,
	})
	return setmetatable(status, Blockstun)
end

return Blockstun
