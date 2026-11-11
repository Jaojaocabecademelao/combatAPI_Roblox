local Request = {}
Request.__index = Request

Request.Reason = table.freeze({
	PredictionDivergence = "PredictionDivergence",
	AuthoritativeCorrection = "AuthoritativeCorrection",
	LateInput = "LateInput",
	StateCorrection = "StateCorrection",
	Manual = "Manual",
})

local validReasons = {}
for _, reason in pairs(Request.Reason) do validReasons[reason] = true end

function Request.new(data)
	assert(type(data) == "table", "RollbackRequest.new() expects a table")
	assert(type(data.FromFrame) == "number" and data.FromFrame >= 0
		and data.FromFrame < math.huge and data.FromFrame % 1 == 0,
		"RollbackRequest FromFrame is invalid")
	assert(type(data.ToFrame) == "number" and data.ToFrame >= data.FromFrame
		and data.ToFrame < math.huge and data.ToFrame % 1 == 0,
		"RollbackRequest ToFrame is invalid")
	local scope = data.Scope or "World"
	assert(scope == "World" or scope == "Entity", "RollbackRequest scope is invalid")
	assert(data.Reason == nil or validReasons[data.Reason], "RollbackRequest reason is invalid")
	return setmetatable({
		FromFrame = data.FromFrame,
		ToFrame = data.ToFrame,
		Reason = data.Reason or Request.Reason.Manual,
		Scope = scope,
		EntityId = data.EntityId,
	}, Request)
end

return Request
