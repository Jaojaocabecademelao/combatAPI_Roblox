local CombatResolutionEvent = require(script.Parent.CombatResolutionEvent)
local CombatResolutionResult = require(script.Parent.CombatResolutionResult)
local EntityState = require(script.Parent.Parent.Core.EntityState)

local CombatResolver = {}
CombatResolver.__index = CombatResolver

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

local function getAttackId(hitEvent)
	return hitEvent.AttackInstanceId
		or (hitEvent.AttackInstance and hitEvent.AttackInstance.Id)
end

local function getPriority(hitEvent)
	local properties = hitEvent.OffensiveProperties
	if properties and properties.Priority ~= nil then
		return properties.Priority
	end
	return hitEvent.Priority or 0
end

local function compareHitEvents(left, right)
	local leftFrame, rightFrame = left.Frame or 0, right.Frame or 0
	if leftFrame ~= rightFrame then
		return leftFrame < rightFrame
	end
	local compared = compareIds(getAttackId(left), getAttackId(right))
	if compared ~= 0 then
		return compared < 0
	end
	local leftPriority, rightPriority = getPriority(left), getPriority(right)
	if leftPriority ~= rightPriority then
		return leftPriority > rightPriority
	end
	for _, key in ipairs({ "AttackerEntityId", "TargetEntityId", "HitboxId", "HurtboxId" }) do
		compared = compareIds(left[key], right[key])
		if compared ~= 0 then
			return compared < 0
		end
	end
	return false
end

local function isClashEligible(hitEvent)
	local instance = hitEvent.AttackInstance
	local properties = hitEvent.OffensiveProperties
	if not instance or getAttackId(hitEvent) == nil then
		return false
	end
	local canClash = properties and properties.CanClash
	if canClash == nil and instance then
		canClash = instance.CanClash
	end
	if canClash == nil and hitEvent.Attack then
		canClash = hitEvent.Attack.CanClash
	end
	return canClash ~= false
end

local function isLiving(entity)
	return entity == nil or (entity.Destroyed ~= true and entity.State ~= EntityState.Dead
		and (type(entity.IsDead) ~= "function" or not entity:IsDead()))
end

local function isEventValid(hitEvent)
	local instance = hitEvent.AttackInstance
	return isLiving(hitEvent.Attacker) and isLiving(hitEvent.Target)
		and (instance == nil or instance.State ~= "Finished")
end

local function hasReciprocalOwners(left, right)
	local leftAttackerId = left.AttackerEntityId or (left.Attacker and left.Attacker.Id)
	local leftTargetId = left.TargetEntityId or (left.Target and left.Target.Id)
	local rightAttackerId = right.AttackerEntityId or (right.Attacker and right.Attacker.Id)
	local rightTargetId = right.TargetEntityId or (right.Target and right.Target.Id)
	return leftAttackerId ~= nil and leftTargetId ~= nil
		and rightAttackerId == leftTargetId and rightTargetId == leftAttackerId
		and leftAttackerId ~= leftTargetId
end

local function suppressPairEvents(ordered, eventA, eventB, suppressed, suppressA, suppressB)
	for _, candidate in ipairs(ordered) do
		if getAttackId(candidate) == getAttackId(eventA)
			and candidate.AttackerEntityId == eventA.AttackerEntityId
			and candidate.TargetEntityId == eventA.TargetEntityId
			and suppressA
		then
			suppressed[candidate] = true
		elseif getAttackId(candidate) == getAttackId(eventB)
			and candidate.AttackerEntityId == eventB.AttackerEntityId
			and candidate.TargetEntityId == eventB.TargetEntityId
			and suppressB
		then
			suppressed[candidate] = true
		end
	end
end

local function token(value)
	local valueString = tostring(value)
	return type(value) .. "#" .. #valueString .. ":" .. valueString
end

local function makePairId(frame, idA, idB)
	return tostring(frame) .. "|" .. token(idA) .. "|" .. token(idB)
end

local function copyArray(values)
	local result = {}
	for _, value in ipairs(values) do
		table.insert(result, value)
	end
	return result
end

local function compareResolutionEvents(left, right)
	if left.Frame ~= right.Frame then
		return left.Frame < right.Frame
	end
	if left.AttackInstanceIdA == right.AttackInstanceIdA
		and left.PriorityA ~= right.PriorityA
	then
		return left.PriorityA > right.PriorityA
	end
	for _, key in ipairs({
		"AttackInstanceIdA", "AttackInstanceIdB", "AttackerEntityIdA",
		"TargetEntityIdA", "AttackerEntityIdB", "TargetEntityIdB",
		"HitboxIdA", "HurtboxIdA", "Id",
	}) do
		local compared = compareIds(left[key], right[key])
		if compared ~= 0 then
			return compared < 0
		end
	end
	return false
end

function CombatResolver.new()
	return setmetatable({ ResolutionEvents = {} }, CombatResolver)
end

-- Resolves reciprocal hits as one pair, in frame then AttackInstance ID order.
-- Any attack that loses a priority pair, or ties in a Clash, is withheld from
-- Defense/Damage for the step. Winners continue only if they lose no other pair.
function CombatResolver:Process(hitEvents)
	assert(type(hitEvents) == "table", "CombatResolver:Process() expects HitEvents")
	self.ResolutionEvents = {}
	local ordered = copyArray(hitEvents)
	local valid = {}
	for _, hitEvent in ipairs(ordered) do
		if isEventValid(hitEvent) then table.insert(valid, hitEvent) end
	end
	ordered = valid
	table.sort(ordered, compareHitEvents)

	local seenPairs = {}
	local suppressed = {}
	local participating = {}
	for i = 1, #ordered do
		local left = ordered[i]
		if isClashEligible(left) then
			for j = i + 1, #ordered do
				local right = ordered[j]
				local leftId, rightId = getAttackId(left), getAttackId(right)
				local rightFrame = right.Frame or 0
				if rightFrame > (left.Frame or 0) then
					break
				end
				if left.AttackInstance ~= right.AttackInstance
					and left.Attacker ~= right.Attacker
					and isClashEligible(right)
					and hasReciprocalOwners(left, right)
				then
					local idOrder = compareIds(leftId, rightId)
					if idOrder ~= 0 then
						local eventA, eventB = left, right
						local idA, idB = leftId, rightId
						if idOrder > 0 then
							eventA, eventB = right, left
							idA, idB = rightId, leftId
						end
						local frame = eventA.Frame or eventB.Frame or 0
						local pairId = makePairId(frame, idA, idB)
						if not seenPairs[pairId] then
							seenPairs[pairId] = true
							local priorityA, priorityB = getPriority(eventA), getPriority(eventB)
							local outcome, winner, loser, winnerInstance, loserInstance
							local outcomeA, outcomeB
							if priorityA == priorityB then
								outcome = CombatResolutionResult.Clash
								outcomeA, outcomeB = outcome, outcome
								suppressPairEvents(ordered, eventA, eventB, suppressed, true, true)
							elseif priorityA > priorityB then
								outcome = CombatResolutionResult.PriorityWin
								outcomeA, outcomeB = CombatResolutionResult.PriorityWin, CombatResolutionResult.PriorityLoss
								winner, loser = eventA, eventB
								winnerInstance, loserInstance = eventA.AttackInstance, eventB.AttackInstance
								suppressPairEvents(ordered, eventA, eventB, suppressed, false, true)
							else
								outcome = CombatResolutionResult.PriorityWin
								outcomeA, outcomeB = CombatResolutionResult.PriorityLoss, CombatResolutionResult.PriorityWin
								winner, loser = eventB, eventA
								winnerInstance, loserInstance = eventB.AttackInstance, eventA.AttackInstance
								suppressPairEvents(ordered, eventA, eventB, suppressed, true, false)
							end
							participating[eventA] = true
							participating[eventB] = true
							table.insert(self.ResolutionEvents, CombatResolutionEvent.new({
								Id = pairId,
								Frame = frame,
								Outcome = outcome,
								OutcomeA = outcomeA,
								OutcomeB = outcomeB,
								AttackInstanceA = eventA.AttackInstance,
								AttackInstanceB = eventB.AttackInstance,
								AttackInstanceIdA = idA,
								AttackInstanceIdB = idB,
								HitEventA = eventA,
								HitEventB = eventB,
								PriorityA = priorityA,
								PriorityB = priorityB,
								AttackerEntityIdA = eventA.AttackerEntityId,
								TargetEntityIdA = eventA.TargetEntityId,
								AttackerEntityIdB = eventB.AttackerEntityId,
								TargetEntityIdB = eventB.TargetEntityId,
								HitboxIdA = eventA.HitboxId,
								HurtboxIdA = eventA.HurtboxId,
								Winner = winner,
								Loser = loser,
								WinnerAttackInstance = winnerInstance,
								LoserAttackInstance = loserInstance,
							}))
						end
					end
				end
			end
		end
	end

	local processable = {}
	for _, hitEvent in ipairs(ordered) do
		if not suppressed[hitEvent] then
			table.insert(processable, hitEvent)
			if not participating[hitEvent] then
				table.insert(self.ResolutionEvents, CombatResolutionEvent.new({
					Id = "normal|" .. tostring(hitEvent.Frame or 0) .. "|" .. token(getAttackId(hitEvent))
						.. "|" .. token(hitEvent.AttackerEntityId) .. "|" .. token(hitEvent.TargetEntityId)
						.. "|" .. token(hitEvent.HitboxId) .. "|" .. token(hitEvent.HurtboxId),
					Frame = hitEvent.Frame or 0,
					Outcome = CombatResolutionResult.Normal,
					OutcomeA = CombatResolutionResult.Normal,
					HitEventA = hitEvent,
					AttackInstanceA = hitEvent.AttackInstance,
					AttackInstanceIdA = getAttackId(hitEvent),
					PriorityA = getPriority(hitEvent),
					AttackerEntityIdA = hitEvent.AttackerEntityId,
					TargetEntityIdA = hitEvent.TargetEntityId,
					HitboxIdA = hitEvent.HitboxId,
					HurtboxIdA = hitEvent.HurtboxId,
				}))
			end
		end
	end
	table.sort(self.ResolutionEvents, compareResolutionEvents)
	return processable
end

function CombatResolver:GetResolutionEvents()
	return copyArray(self.ResolutionEvents)
end

function CombatResolver:GetResolutionEventsForResult(result)
	local events = {}
	for _, event in ipairs(self.ResolutionEvents) do
		if event.Outcome == result or event.OutcomeA == result or event.OutcomeB == result then
			table.insert(events, event)
		end
	end
	return events
end

return CombatResolver
