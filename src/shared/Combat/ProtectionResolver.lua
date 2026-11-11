local ProtectionComponent = require(script.Parent.ProtectionComponent)
local ProtectionQuery = require(script.Parent.ProtectionQuery)
local ProtectionResult = require(script.Parent.ProtectionResult)

local ProtectionResolver = {}
ProtectionResolver.__index = ProtectionResolver

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

function ProtectionResolver.new(world)
	return setmetatable({
		World = world,
		Results = {},
	}, ProtectionResolver)
end

function ProtectionResolver:Query(query)
	if getmetatable(query) ~= ProtectionQuery then
		query = ProtectionQuery.new(query)
	end
	local target = query.Target
	local component = target and type(target.GetComponent) == "function" and target:GetComponent(ProtectionComponent)
	local protection = component and component:Resolve(query.Category)
	local result = protection and "Blocked" or "Allowed"
	local outcome = ProtectionResult.new(query, result, protection)
	table.insert(self.Results, outcome)
	return outcome
end

function ProtectionResolver:Process(queries)
	self.Results = {}
	local results = {}
	for _, query in ipairs(queries or {}) do
		table.insert(results, self:Query(query))
	end
	return results
end

function ProtectionResolver:FilterHitEvents(hitEvents, category, frame, time)
	local allowed = {}
	for _, hitEvent in ipairs(hitEvents) do
		local result = self:Query({
			Target = hitEvent.Target,
			Category = category,
			Source = hitEvent.AttackInstance or hitEvent.Attacker,
			Frame = frame or hitEvent.Frame or 0,
			Time = time or hitEvent.Time,
		})
		if result.Result == "Allowed" then table.insert(allowed, hitEvent) end
	end
	return allowed
end

function ProtectionResolver:AdvanceFrame(frame)
	if not self.World then
		return self
	end
	if frame ~= nil then
		assert(type(frame) == "number" and frame >= 0 and frame % 1 == 0 and isFiniteNumber(frame),
			"ProtectionResolver:AdvanceFrame() expects a non-negative integer simulation frame")
	end
	for _, entity in ipairs(self.World:GetEntities()) do
		local component = type(entity.GetComponent) == "function"
			and entity:GetComponent(ProtectionComponent)
		if component then
			component:AdvanceFrame(frame)
		end
	end
	return self
end

function ProtectionResolver:GetResults()
	local results = {}
	for _, result in ipairs(self.Results) do
		table.insert(results, result)
	end
	return results
end

function ProtectionResolver:Clear()
	self.Results = {}
	return self
end

return ProtectionResolver
