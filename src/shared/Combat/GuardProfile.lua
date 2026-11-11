local GuardProfile = {}
GuardProfile.__index = GuardProfile

local function finite(value)
	return type(value) == "number" and value == value
		and value > -math.huge and value < math.huge
end

function GuardProfile.new(options)
	options = options or {}
	assert(type(options) == "table", "GuardProfile.new() expects an options table or nil")

	local maxGuard = options.MaxGuard
	if maxGuard == nil then
		maxGuard = 100
	end
	assert(finite(maxGuard) and maxGuard > 0 and maxGuard % 1 == 0,
		"GuardProfile MaxGuard must be a finite positive integer")

	local chipMultiplier = options.ChipMultiplier
	if chipMultiplier == nil then
		chipMultiplier = 0.1
	end
	assert(finite(chipMultiplier) and chipMultiplier >= 0,
		"GuardProfile ChipMultiplier must be a finite non-negative number")

	local guardDamageMultiplier = options.GuardDamageMultiplier
	if guardDamageMultiplier == nil then
		guardDamageMultiplier = 1
	end
	assert(finite(guardDamageMultiplier) and guardDamageMultiplier >= 0,
		"GuardProfile GuardDamageMultiplier must be a finite non-negative number")

	local blockstunMultiplier = options.BlockstunMultiplier
	if blockstunMultiplier == nil then
		blockstunMultiplier = 1
	end
	assert(finite(blockstunMultiplier) and blockstunMultiplier >= 0,
		"GuardProfile BlockstunMultiplier must be a finite non-negative number")

	local breakFrames = options.GuardBreakFrames
	if breakFrames == nil then
		breakFrames = 30
	end
	assert(finite(breakFrames) and breakFrames >= 0 and breakFrames % 1 == 0,
		"GuardProfile GuardBreakFrames must be a non-negative integer")

	local defaultGuardDamage = options.DefaultGuardDamage
	if defaultGuardDamage == nil then
		defaultGuardDamage = 0
	end
	assert(finite(defaultGuardDamage) and defaultGuardDamage >= 0,
		"GuardProfile DefaultGuardDamage must be a finite non-negative number")

	return setmetatable({
		MaxGuard = maxGuard,
		ChipMultiplier = chipMultiplier,
		GuardDamageMultiplier = guardDamageMultiplier,
		BlockstunMultiplier = blockstunMultiplier,
		GuardBreakFrames = breakFrames,
		DefaultGuardDamage = defaultGuardDamage,
		Name = options.Name or "GuardProfile",
	}, GuardProfile)
end

return GuardProfile
