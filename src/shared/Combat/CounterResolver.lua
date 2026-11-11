local OffensiveStateComponent = require(script.Parent.OffensiveStateComponent)
local CounterResult = require(script.Parent.CounterResult)
local DefenseResult = require(script.Parent.DefenseResult)
local EntityState = require(script.Parent.Parent.Core.EntityState)

local CounterResolver = {}
CounterResolver.__index = CounterResolver

local function copyArray(values)
	local result = {}
	for _, value in ipairs(values) do
		table.insert(result, value)
	end
	return result
end

local function compareIds(a, b)
	if a == b then return 0 end
	if a == nil then return -1 elseif b == nil then return 1 end
	if type(a) == type(b) then return a < b and -1 or 1 end
	return type(a) < type(b) and -1 or 1
end

local function compareEvents(a, b)
	if a.Frame ~= b.Frame then return a.Frame < b.Frame end
	for _, key in ipairs({ "AttackInstanceId", "TargetEntityId", "HitboxId", "HurtboxId", "AttackerEntityId" }) do
		local order = compareIds(a[key], b[key])
		if order ~= 0 then return order < 0 end
	end
	return false
end

local function isAlive(entity)
	return entity ~= nil and not entity.Destroyed and entity.State ~= EntityState.Dead
		and (type(entity.IsDead) ~= "function" or not entity:IsDead())
end

local function contactKey(event)
	local function token(value)
		local s = tostring(value)
		return type(value) .. "#" .. #s .. ":" .. s
	end
	return table.concat({ token(event.AttackInstanceId), token(event.TargetEntityId),
		token(event.HitboxId), token(event.HurtboxId), token(event.Frame) }, "|")
end

function CounterResolver.new()
	return setmetatable({ Results = {} }, CounterResolver)
end

-- Input must be the HitEvents that passed DefenseResolver (Normal only).
-- DefenseEvents can be supplied to preserve explicit defense filtering for standalone callers.
function CounterResolver:Process(hitEvents, defenseEvents)
	assert(type(hitEvents) == "table", "CounterResolver:Process() expects HitEvents")
	local allowed = nil
	if defenseEvents then
		allowed = {}
		for _, event in ipairs(defenseEvents) do
			if event.Result == DefenseResult.Normal then allowed[event.HitEvent] = true end
		end
	end
	local ordered = {}
	for _, event in ipairs(hitEvents) do
		if allowed == nil or allowed[event] then table.insert(ordered, event) end
	end
	table.sort(ordered, compareEvents)
	self.Results = {}
	local seen = {}
	for _, event in ipairs(ordered) do
		local attackId = event.AttackInstanceId or (event.AttackInstance and event.AttackInstance.Id)
		local targetId = event.TargetEntityId or (event.Target and event.Target.Id)
		local hitboxId = event.HitboxId or (event.Hitbox and event.Hitbox.Id)
		local hurtboxId = event.HurtboxId or (event.Hurtbox and event.Hurtbox.Id)
		if attackId ~= nil and targetId ~= nil and isAlive(event.Attacker) and isAlive(event.Target) then
			local key = contactKey({ AttackInstanceId = attackId, TargetEntityId = targetId,
				HitboxId = hitboxId, HurtboxId = hurtboxId, Frame = event.Frame or 0 })
			if not seen[key] then
				seen[key] = true
				local component = type(event.Target.GetComponent) == "function"
					and event.Target:GetComponent(OffensiveStateComponent)
				local resultType = component and component:IsVulnerable(event.Frame or 0)
					and CounterResult.Type.CounterHit or CounterResult.Type.Normal
				table.insert(self.Results, CounterResult.new(event, resultType))
			end
		end
	end
	return self:GetResults()
end

function CounterResolver:GetResults()
	local copy = {}
	for _, result in ipairs(self.Results) do table.insert(copy, result) end
	return copy
end

function CounterResolver:GetResultsForType(resultType)
	local matches = {}
	for _, result in ipairs(self.Results) do
		if result.Type == resultType then table.insert(matches, result) end
	end
	return matches
end

-- Counter results are frame-local outputs. Durable offensive state belongs to components.
-- The target snapshot intentionally contains no prior output objects; compensation preserves identity.
function CounterResolver:CaptureRollbackState()
	return { Version = 1 }
end

function CounterResolver:ValidateRollbackState(state)
	if type(state) ~= "table" or getmetatable(state) ~= nil or state.Version ~= 1 then
		return false, "Unsupported CounterResolver state"
	end
	for key in pairs(state) do
		if key ~= "Version" then
			return false, "Unknown CounterResolver state field: " .. tostring(key)
		end
	end
	return true
end

function CounterResolver:PrepareRollbackRestore(state, world, context, role)
	local valid, detail = self:ValidateRollbackState(state)
	if not valid then return nil, detail end
	local previousResults = copyArray(self.Results)
	return function()
		if role == "Compensation" then
			self.Results = copyArray(previousResults)
		else
			table.clear(self.Results)
		end
	end
end

return CounterResolver
