local ProtectionQuery = {}
ProtectionQuery.__index = ProtectionQuery

function ProtectionQuery.new(options)
	options = options or {}
	assert(type(options) == "table", "ProtectionQuery.new() expects an options table")
	assert(options.Target and type(options.Target) == "table", "ProtectionQuery requires a Target entity")
	local category = options.Category or "Damage"
	assert(type(category) == "string" and category ~= "", "ProtectionQuery category must be a non-empty string")
	return setmetatable({
		Target = options.Target,
		Category = category,
		Interaction = options.Interaction or category,
		Source = options.Source,
		Priority = options.Priority or 0,
		Frame = options.Frame or 0,
		Time = options.Time,
		Kind = options.Kind,
	}, ProtectionQuery)
end

return ProtectionQuery
