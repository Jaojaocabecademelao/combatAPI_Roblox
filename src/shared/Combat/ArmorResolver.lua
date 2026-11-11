local ArmorComponent = require(script.Parent.ArmorComponent)
local ArmorResult = require(script.Parent.ArmorResult)
local ArmorCategory = require(script.Parent.ArmorCategory)

local ArmorResolver = {}
ArmorResolver.__index = ArmorResolver

local categories = {
	ArmorCategory.Damage, ArmorCategory.Hitstun, ArmorCategory.Knockback,
	ArmorCategory.Launch, ArmorCategory.Push, ArmorCategory.Pull, ArmorCategory.Hit,
}

local function compareIds(a, b)
	if a == b then return 0 end
	if a == nil then return -1 elseif b == nil then return 1 end
	if type(a) == type(b) then return a < b and -1 or 1 end
	return type(a) < type(b) and -1 or 1
end

local function attackId(event)
	return event.AttackInstanceId or (event.AttackInstance and event.AttackInstance.Id)
end

local function targetId(event)
	return event.TargetEntityId or (event.Target and event.Target.Id)
end

local function compareEvents(a, b)
	if (a.Frame or 0) ~= (b.Frame or 0) then return (a.Frame or 0) < (b.Frame or 0) end
	local compared = compareIds(targetId(a), targetId(b))
	if compared ~= 0 then return compared < 0 end
	compared = compareIds(attackId(a), attackId(b))
	if compared ~= 0 then return compared < 0 end
	return compareIds(a.HitboxId, b.HitboxId) < 0
end

function ArmorResolver.new(world)
	return setmetatable({ World = world, Results = {}, ResultsByHitEvent = {} }, ArmorResolver)
end

function ArmorResolver:Resolve(hitEvent)
	assert(type(hitEvent) == "table", "ArmorResolver:Resolve() expects a HitEvent")
	local target = hitEvent.Target
	local component = target and not target.Destroyed and type(target.GetComponent) == "function"
		and target:GetComponent(ArmorComponent)
	local handles = {}
	if component then
		for _, category in ipairs(categories) do
			handles[category] = component:ResolveRule(category, hitEvent)
		end
	end
	return ArmorResult.new(hitEvent, categories, handles)
end

function ArmorResolver:Process(hitEvents)
	assert(type(hitEvents) == "table", "ArmorResolver:Process() expects HitEvents")
	local ordered = {}
	for _, event in ipairs(hitEvents) do table.insert(ordered, event) end
	table.sort(ordered, compareEvents)
	self.Results = {}
	self.ResultsByHitEvent = {}
	for _, event in ipairs(ordered) do
		local result = self:Resolve(event)
		table.insert(self.Results, result)
		self.ResultsByHitEvent[event] = result
	end
	return self:GetResults()
end

function ArmorResolver:GetResults()
	local results = {}
	for _, result in ipairs(self.Results) do table.insert(results, result) end
	return results
end

function ArmorResolver:GetResultForHit(hitEvent)
	return self.ResultsByHitEvent[hitEvent]
end

function ArmorResolver:FilterHitEvents(hitEvents, category)
	local allowed = {}
	for _, hitEvent in ipairs(hitEvents) do
		local result = self:GetResultForHit(hitEvent) or self:Resolve(hitEvent)
		if result:Allows(category) then table.insert(allowed, hitEvent) end
	end
	return allowed
end

function ArmorResolver:FilterMotionRequests(requests, armorResults)
	local resultByKey = {}
	for _, result in ipairs(armorResults or self.Results) do
		local key = tostring(result.TargetId) .. "|" .. tostring(result.AttackInstanceId)
		resultByKey[key] = result
	end
	local allowed = {}
	for _, request in ipairs(requests) do
		local source = request.Source
		local instanceId = source and (source.AttackInstanceId or source.Id
			or (source.AttackInstance and source.AttackInstance.Id))
		local targetIdValue = request.Target and request.Target.Id or request.TargetId
		local result = resultByKey[tostring(targetIdValue) .. "|" .. tostring(instanceId)]
		if result == nil or result:Allows(request.Type) then table.insert(allowed, request) end
	end
	return allowed
end

function ArmorResolver:AdvanceStep()
	if not self.World then return self end
	for _, entity in ipairs(self.World:GetEntities()) do
		local component = entity:GetComponent(ArmorComponent)
		if component then component:AdvanceStep(self.World.CurrentFrame) end
	end
	return self
end

function ArmorResolver:Clear()
	table.clear(self.Results)
	table.clear(self.ResultsByHitEvent)
	return self
end

return ArmorResolver
