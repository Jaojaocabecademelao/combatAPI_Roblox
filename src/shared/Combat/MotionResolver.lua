local MotionRequest = require(script.Parent.MotionRequest)
local MotionResult = require(script.Parent.MotionResult)
local EntityState = require(script.Parent.Parent.Core.EntityState)

local MotionResolver = {}
MotionResolver.__index = MotionResolver

local function copyArray(values)
	local result = {}
	for _, value in ipairs(values) do
		table.insert(result, value)
	end
	return result
end

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

local function compareIds(left, right)
	if left == right then
		return 0
	elseif left == nil then
		return -1
	elseif right == nil then
		return 1
	end
	local leftType, rightType = type(left), type(right)
	if leftType == rightType then
		return left < right and -1 or 1
	end
	return leftType < rightType and -1 or 1
end

local function compareRequestOrder(left, right)
	local leftPriority, rightPriority = left.Priority or 0, right.Priority or 0
	if leftPriority ~= rightPriority then
		return leftPriority > rightPriority
	end

	local leftMagnitude, rightMagnitude = left.Magnitude or 0, right.Magnitude or 0
	if leftMagnitude ~= rightMagnitude then
		return leftMagnitude > rightMagnitude
	end

	local leftTarget = left.Target and left.Target.Id or left.Target
	local rightTarget = right.Target and right.Target.Id or right.Target
	local comparedTarget = compareIds(leftTarget, rightTarget)
	if comparedTarget ~= 0 then
		return comparedTarget < 0
	end

	local leftSource = left.Source and left.Source.Id or left.Source
	local rightSource = right.Source and right.Source.Id or right.Source
	local comparedSource = compareIds(leftSource, rightSource)
	if comparedSource ~= 0 then
		return comparedSource < 0
	end

	local leftType = left.Type or ""
	local rightType = right.Type or ""
	if leftType ~= rightType then
		return leftType < rightType
	end
	return false
end

local function compareResolutionOrder(left, right)
	if left.Frame ~= right.Frame then
		return left.Frame < right.Frame
	end
	if left.Priority ~= right.Priority then
		return left.Priority > right.Priority
	end
	local leftTarget = left.Target and left.Target.Id or left.Target
	local rightTarget = right.Target and right.Target.Id or right.Target
	local comparedTarget = compareIds(leftTarget, rightTarget)
	if comparedTarget ~= 0 then
		return comparedTarget < 0
	end
	local leftSource = left.Source and left.Source.Id or left.Source
	local rightSource = right.Source and right.Source.Id or right.Source
	local comparedSource = compareIds(leftSource, rightSource)
	if comparedSource ~= 0 then
		return comparedSource < 0
	end
	return left.Type < right.Type
end

local function isAlive(entity)
	return entity ~= nil and type(entity) == "table"
		and not entity.Destroyed
		and (entity.State == nil or entity.State ~= EntityState.Dead)
		and (type(entity.IsDead) ~= "function" or not entity:IsDead())
end

function MotionResolver.new()
	return setmetatable({
		PendingRequests = {},
		Results = {},
	}, MotionResolver)
end

function MotionResolver:QueueRequest(request)
	assert(request and type(request) == "table", "MotionResolver:QueueRequest() expects a MotionRequest")
	if request.Target and type(request.Target) == "table" and not isAlive(request.Target) then
		return nil
	end
	table.insert(self.PendingRequests, request)
	return request
end

function MotionResolver:GetPendingRequests()
	return copyArray(self.PendingRequests)
end

function MotionResolver:Clear()
	self.PendingRequests = {}
	self.Results = {}
	return self
end

function MotionResolver:Process(requests, frame)
	local sourceRequests = requests or self.PendingRequests
	if sourceRequests == nil then
		sourceRequests = {}
	end

	local ordered = {}
	for _, request in ipairs(sourceRequests) do
		if request and type(request) == "table" and request.Type ~= nil then
			local target = request.Target
			if not (target and type(target) == "table" and not isAlive(target)) then
				table.insert(ordered, request)
			end
		end
	end
	table.sort(ordered, compareRequestOrder)

	local winners = {}
	for _, request in ipairs(ordered) do
		local targetId = request.Target and request.Target.Id or request.TargetId
		if targetId ~= nil then
			local key = tostring(targetId)
			local current = winners[key]
			if current == nil or (request.Priority or 0) > (current.Priority or 0)
				or ((request.Priority or 0) == (current.Priority or 0) and (request.Magnitude or 0) > (current.Magnitude or 0))
				or ((request.Priority or 0) == (current.Priority or 0) and (request.Magnitude or 0) == (current.Magnitude or 0)
						and (request.Type or "") < (current.Type or "")) then
				winners[key] = request
			end
		else
			table.insert(winners, request)
		end
	end

	local values = {}
	for _, request in pairs(winners) do
		if type(request) == "table" and request.Type ~= nil then
			table.insert(values, request)
		end
	end

	table.sort(values, compareRequestOrder)
	local results = {}
	for _, request in ipairs(values) do
		local result = MotionResult.new(request, frame)
		table.insert(results, result)
	end
	table.sort(results, compareResolutionOrder)

	self.Results = results
	self.PendingRequests = {}
	return results
end

function MotionResolver:GetResults()
	local copy = {}
	for _, result in ipairs(self.Results) do
		table.insert(copy, result)
	end
	return copy
end

return MotionResolver
