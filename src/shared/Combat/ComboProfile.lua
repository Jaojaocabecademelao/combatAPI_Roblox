local ComboProfile = {}
ComboProfile.__index = ComboProfile

function ComboProfile.new(options)
	options = options or {}
	assert(type(options) == "table", "ComboProfile.new() expects an options table")
	local maxGap = options.MaxGapFrames
	if maxGap == nil then maxGap = 30 end
	assert(type(maxGap) == "number" and maxGap == maxGap and maxGap >= 0
		and maxGap < math.huge and maxGap % 1 == 0,
		"ComboProfile MaxGapFrames must be a non-negative integer")
	local maxRecords = options.MaxHitRecords
	if maxRecords == nil then maxRecords = 128 end
	assert(type(maxRecords) == "number" and maxRecords == maxRecords and maxRecords >= 1
		and maxRecords < math.huge and maxRecords % 1 == 0,
		"ComboProfile MaxHitRecords must be a positive integer")
	for _, key in ipairs({ "CountBlockedHits", "RequireDamage", "RequireHitstun" }) do
		assert(options[key] == nil or type(options[key]) == "boolean", key .. " must be a boolean")
	end
	return setmetatable({
		MaxGapFrames = maxGap,
		CountBlockedHits = options.CountBlockedHits == true,
		RequireDamage = options.RequireDamage == true,
		RequireHitstun = options.RequireHitstun == true,
		MaxHitRecords = maxRecords,
	}, ComboProfile)
end

return ComboProfile
