local CancelType = require(script.Parent.CancelType)

local Rule = {}
Rule.__index = Rule

function Rule.new(options)
	options = options or {}
	assert(type(options) == "table", "CancelRule.new() expects a table")
	assert(type(options.RuleId) == "string" and options.RuleId ~= "", "CancelRule RuleId is required")
	assert(type(options.FromAction) == "string" and options.FromAction ~= "", "CancelRule FromAction is required")
	assert(type(options.ToAction) == "string" and options.ToAction ~= "", "CancelRule ToAction is required")
	assert(options.CancelType == nil or type(options.CancelType) == "string", "CancelRule CancelType must be a string")
	local startFrame = options.StartFrame or (options.Window and options.Window.StartFrame) or 0
	local endFrame = options.EndFrame or (options.Window and options.Window.EndFrame) or startFrame
	assert(type(startFrame) == "number" and type(endFrame) == "number"
		and startFrame >= 0 and endFrame >= startFrame
		and startFrame % 1 == 0 and endFrame % 1 == 0, "CancelRule window is invalid")
	local priority = options.Priority or 0
	assert(type(priority) == "number" and priority == priority and priority > -math.huge and priority < math.huge,
		"CancelRule Priority must be finite")
	return setmetatable({
		RuleId = options.RuleId,
		FromAction = options.FromAction,
		ToAction = options.ToAction,
		CancelType = options.CancelType or CancelType.Normal,
		StartFrame = startFrame,
		EndFrame = endFrame,
		Relative = options.Relative ~= false,
		Repeatable = options.Repeatable == true,
		Conditions = options.Conditions or {},
		RequiredMovementStates = options.RequiredMovementStates,
		Priority = priority,
	}, Rule)
end

return Rule
