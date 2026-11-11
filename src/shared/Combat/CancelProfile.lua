local CancelRule = require(script.Parent.CancelRule)

local Profile = {}
Profile.__index = Profile

function Profile.new(options)
	options = options or {}
	assert(type(options) == "table", "CancelProfile.new() expects a table")
	local rules = {}
	local ids = {}
	for _, value in ipairs(options.Rules or {}) do
		local rule = getmetatable(value) == CancelRule and value or CancelRule.new(value)
		assert(not ids[rule.RuleId], "Duplicate CancelRule RuleId: " .. rule.RuleId)
		ids[rule.RuleId] = true
		table.insert(rules, rule)
	end
	return setmetatable({ Rules = rules, AllowUniversalCancels = options.AllowUniversalCancels == true }, Profile)
end

function Profile:GetRules()
	local result = {}
	for _, rule in ipairs(self.Rules) do table.insert(result, rule) end
	return result
end

local function stableLess(a, b)
	if type(a) ~= type(b) then return type(a) < type(b) end
	return tostring(a) < tostring(b)
end

local function deepEqual(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	if getmetatable(a) ~= nil or getmetatable(b) ~= nil then return false end
	for key, value in pairs(a) do
		if b[key] == nil and value ~= nil then return false end
		if not deepEqual(value, b[key]) then return false end
	end
	for key in pairs(b) do if a[key] == nil then return false end end
	return true
end

-- This manifest validates rule data and callback presence without serializing closures.
-- If callback behavior changes, callers must version the profile/rule identity externally.
function Profile:GetRollbackManifest()
	local rules = {}
	for _, rule in ipairs(self.Rules) do
		local movementStates = nil
		if rule.RequiredMovementStates then
			movementStates = {}
			for _, value in ipairs(rule.RequiredMovementStates) do movementStates[#movementStates + 1] = value end
			table.sort(movementStates, stableLess)
		end
		rules[#rules + 1] = {
			RuleId = rule.RuleId,
			FromAction = rule.FromAction,
			ToAction = rule.ToAction,
			CancelType = rule.CancelType,
			StartFrame = rule.StartFrame,
			EndFrame = rule.EndFrame,
			Relative = rule.Relative,
			Repeatable = rule.Repeatable,
			Priority = rule.Priority,
			RequiredMovementStates = movementStates,
			HasConditionCallback = type(rule.Conditions) == "function",
		}
	end
	table.sort(rules, function(a, b) return a.RuleId < b.RuleId end)
	return { AllowUniversalCancels = self.AllowUniversalCancels, Rules = rules }
end

function Profile:ValidateRollbackManifest(manifest)
	if type(manifest) ~= "table" or getmetatable(manifest) ~= nil then
		return false, "CancelProfile manifest must be a plain table"
	end
	if not deepEqual(manifest, self:GetRollbackManifest()) then
		return false, "CancelProfile rule/configuration manifest mismatch"
	end
	return true
end

return Profile
