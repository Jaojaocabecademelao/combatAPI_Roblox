local DefenseComponent = require(script.Parent.DefenseComponent)
local DefenseEvent = require(script.Parent.DefenseEvent)
local DefenseResult = require(script.Parent.DefenseResult)

local DefenseResolver = {}
DefenseResolver.__index = DefenseResolver

local function copyArray(values)
	local result = {}
	for _, value in ipairs(values) do
		table.insert(result, value)
	end
	return result
end

function DefenseResolver.new()
	return setmetatable({ DefenseEvents = {} }, DefenseResolver)
end

function DefenseResolver:Process(hitEvents, frame)
	assert(type(hitEvents) == "table", "DefenseResolver:Process() expects HitEvents")
	self.DefenseEvents = {}
	local damageableHitEvents = {}

	-- HitProcessor supplies stable HitEvent order; preserve it for all simultaneous defense outcomes.
	for _, hitEvent in ipairs(hitEvents) do
		local eventFrame = hitEvent.Frame or frame
		assert(type(eventFrame) == "number" and eventFrame >= 0
			and eventFrame < math.huge and eventFrame == eventFrame and eventFrame % 1 == 0,
			"DefenseResolver requires a simulation frame on each HitEvent")
		local result = DefenseResult.Normal
		local target = hitEvent.Target
		local defense = target and not target.Destroyed and type(target.GetComponent) == "function"
			and target:GetComponent(DefenseComponent)

		if defense then
			local offensiveProperties = hitEvent.OffensiveProperties
			local guard = offensiveProperties and offensiveProperties.Defense
			local canBlock = not guard or guard.CanBlock ~= false
			local canParry = not guard or guard.CanParry ~= false
			if canParry and defense:IsParryActive(eventFrame) then
				result = DefenseResult.Parried
			elseif canBlock and defense:IsBlocking() then
				result = DefenseResult.Blocked
			end
		end

		local defenseEvent = DefenseEvent.new(hitEvent, result, eventFrame)
		table.insert(self.DefenseEvents, defenseEvent)
		if result == DefenseResult.Normal then
			table.insert(damageableHitEvents, hitEvent)
		end
	end

	return damageableHitEvents
end

function DefenseResolver:GetDefenseEvents()
	return copyArray(self.DefenseEvents)
end

function DefenseResolver:GetDefenseEventsForResult(result)
	local events = {}
	for _, event in ipairs(self.DefenseEvents) do
		if event.Result == result then
			table.insert(events, event)
		end
	end
	return events
end

-- Defense intent lives in DefenseComponent; this resolver owns only frame-local outcomes.
function DefenseResolver:CaptureRollbackState()
	return { Version = 1 }
end

function DefenseResolver:ValidateRollbackState(state)
	if type(state) ~= "table" or getmetatable(state) ~= nil or state.Version ~= 1 then
		return false, "Unsupported DefenseResolver state"
	end
	for key in pairs(state) do
		if key ~= "Version" then
			return false, "Unknown DefenseResolver state field: " .. tostring(key)
		end
	end
	return true
end

function DefenseResolver:PrepareRollbackRestore(state, world, context, role)
	local valid, detail = self:ValidateRollbackState(state)
	if not valid then return nil, detail end
	local previousEvents = copyArray(self.DefenseEvents)
	return function()
		if role == "Compensation" then
			self.DefenseEvents = copyArray(previousEvents)
		else
			table.clear(self.DefenseEvents)
		end
	end
end

return DefenseResolver
