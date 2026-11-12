local DeterminismGuard = {}
DeterminismGuard.__index = DeterminismGuard

local FORBIDDEN_DURING_REPLAY = table.freeze({
	WallClock = true,
	UnseededRandom = true,
	ExternalPhysicsQuery = true,
	NetworkArrivalOrder = true,
	InstanceMutation = true,
	LegacyClosureTimer = true,
	IrreversibleSideEffect = true,
})

local function isValidFrame(frame)
	return type(frame) == "number" and frame == frame and frame >= 0
		and frame < math.huge and frame % 1 == 0
end

function DeterminismGuard.new(contextProvider, frameProvider)
	assert(contextProvider == nil or type(contextProvider) == "function",
		"DeterminismGuard context provider must be a function or nil")
	assert(frameProvider == nil or type(frameProvider) == "function",
		"DeterminismGuard frame provider must be a function or nil")
	return setmetatable({
		ContextProvider = contextProvider,
		FrameProvider = frameProvider,
		Violations = {},
		Sequence = 0,
	}, DeterminismGuard)
end

function DeterminismGuard:GetContext()
	if not self.ContextProvider then return "Normal" end
	return self.ContextProvider() or "Normal"
end

function DeterminismGuard:IsForbidden(operation)
	return FORBIDDEN_DURING_REPLAY[operation] == true
end

function DeterminismGuard:Check(operation, details)
	assert(type(operation) == "string" and operation ~= "",
		"DeterminismGuard:Check() requires an operation name")
	local context = self:GetContext()
	if context == "Normal" or not self:IsForbidden(operation) then return true end
	local frame
	if self.FrameProvider then
		frame = self.FrameProvider()
		assert(isValidFrame(frame), "DeterminismGuard frame provider must return a non-negative integer")
	end
	local detailText
	if details ~= nil then detailText = tostring(details) end
	self.Sequence += 1
	local violationData = {
		Sequence = self.Sequence,
		Operation = operation,
		Context = context,
	}
	if frame ~= nil then violationData.Frame = frame end
	if detailText ~= nil then violationData.Details = detailText end
	local violation = table.freeze(violationData)
	table.insert(self.Violations, violation)
	return false, violation
end

function DeterminismGuard:AssertAllowed(operation, details)
	local allowed, violation = self:Check(operation, details)
	if not allowed then
		local context = violation and violation.Context or self:GetContext()
		error(("DeterminismGuard rejected %s during %s"):format(
			tostring(operation), tostring(context)), 2)
	end
	return true
end

function DeterminismGuard:GetViolations()
	return table.freeze(table.clone(self.Violations))
end

function DeterminismGuard:ClearViolations()
	table.clear(self.Violations)
end

DeterminismGuard.ForbiddenOperations = FORBIDDEN_DURING_REPLAY
return table.freeze(DeterminismGuard)
