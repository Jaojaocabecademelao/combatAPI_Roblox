local MovementState = require(script.Parent.MovementState)

local Profile = {}
Profile.__index = Profile

local defaults = {
	Idle = { Moving = true, Crouching = true, Dashing = true, Jumping = true },
	Moving = { Idle = true, Crouching = true, Dashing = true, Jumping = true },
	Crouching = { Idle = true, Moving = true },
	Dashing = { Idle = true, Moving = true, Jumping = true },
	Jumping = { Falling = true },
	Falling = { Idle = true },
}

local valid = {}
for _, state in pairs(MovementState) do valid[state] = true end

local function copyRules(source)
	local result = {}
	for from, targets in pairs(source) do
		assert(valid[from] and type(targets) == "table", "Invalid movement transition source")
		result[from] = {}
		for to, allowed in pairs(targets) do
			assert(valid[to] and type(allowed) == "boolean", "Invalid movement transition target")
			result[from][to] = allowed
		end
	end
	return result
end

function Profile.new(options)
	options = options or {}
	assert(type(options) == "table", "MovementStateProfile.new() expects a table")
	local initial = options.InitialState or MovementState.Idle
	assert(valid[initial], "MovementStateProfile InitialState is invalid")
	local rules = options.AllowedTransitions or defaults
	local durations = options.StateDurations or {}
	for state, duration in pairs(durations) do
		assert(valid[state] and type(duration) == "table", "Invalid StateDurations entry")
		for name, value in pairs(duration) do
			assert((name == "MinFrames" or name == "MaxFrames")
				and type(value) == "number" and value >= 0 and value % 1 == 0
				and value < math.huge, "State duration must be a finite frame count")
		end
	end
	return setmetatable({
		InitialState = initial,
		AllowedTransitions = copyRules(rules),
		StateDurations = durations,
	}, Profile)
end

function Profile:IsValidState(state) return valid[state] == true end
function Profile:Allows(from, to)
	return self.AllowedTransitions[from] and self.AllowedTransitions[from][to] == true or false
end

return Profile
