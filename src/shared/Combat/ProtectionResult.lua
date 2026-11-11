local ProtectionResult = {}
ProtectionResult.__index = ProtectionResult

function ProtectionResult.new(query, result, protection)
	query = query or {}
	assert(type(query) == "table", "ProtectionResult.new() expects a ProtectionQuery")
	result = result or "Allowed"
	return setmetatable({
		Target = query.Target,
		TargetId = query.Target and query.Target.Id,
		Category = query.Category,
		Interaction = query.Interaction or query.Category,
		Source = query.Source,
		Protection = protection,
		Kind = protection and protection.Kind,
		Result = result,
		Priority = protection and protection.Priority or (query.Priority or 0),
		Frame = query.Frame or 0,
		Time = query.Time,
	}, ProtectionResult)
end

return ProtectionResult
