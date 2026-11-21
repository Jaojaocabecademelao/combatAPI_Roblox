local PerformanceBudget = {}
PerformanceBudget.__index = PerformanceBudget

function PerformanceBudget.new(limits)
	limits = limits or {}
	assert(type(limits) == "table", "PerformanceBudget.new expects a table")
	local normalized = {}
	for name, limit in pairs(limits) do
		assert(type(name) == "string" and name ~= "", "Budget names must be non-empty strings")
		assert(type(limit) == "number" and limit == limit
			and limit >= 0 and limit < math.huge,
			("Budget %s must be a finite non-negative number"):format(name))
		normalized[name] = limit
	end
	return setmetatable({ Limits = table.freeze(normalized) }, PerformanceBudget)
end

function PerformanceBudget:Check(metrics)
	assert(type(metrics) == "table", "PerformanceBudget.Check expects a metrics table")
	local violations = {}
	for name, limit in pairs(self.Limits) do
		local value = metrics[name]
		if type(value) == "number" and value > limit then
			table.insert(violations, {
				Metric = name,
				Limit = limit,
				Value = value,
			})
		end
	end
	table.sort(violations, function(left, right) return left.Metric < right.Metric end)
	return table.freeze({
		Passed = #violations == 0,
		Violations = table.freeze(violations),
	})
end

return PerformanceBudget
