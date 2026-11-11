local Combo = require(script.Parent.Combo)
local ComboComponent = require(script.Parent.ComboComponent)
local ComboProfile = require(script.Parent.ComboProfile)
local ComboEvent = require(script.Parent.ComboEvent)
local ComboResult = require(script.Parent.ComboResult)
local DefenseResult = require(script.Parent.DefenseResult)
local EntityState = require(script.Parent.Parent.Core.EntityState)
local IdGenerator = require(script.Parent.Parent.Core.IdGenerator)

local ComboResolver = {}
ComboResolver.__index = ComboResolver

local function compareId(a, b)
	if a == b then return 0 end
	if a == nil then return -1 elseif b == nil then return 1 end
	if type(a) == type(b) then return a < b and -1 or 1 end
	return type(a) < type(b) and -1 or 1
end
local function id(entity) return entity and entity.Id end
local function attackId(hit) return hit.AttackInstanceId or (hit.AttackInstance and hit.AttackInstance.Id) end
local function token(value)
	local encoded = tostring(value)
	return type(value) .. "#" .. tostring(#encoded) .. ":" .. encoded
end
local function alive(entity)
	return entity ~= nil and not entity.Destroyed and entity.State ~= EntityState.Dead
		and (type(entity.IsDead) ~= "function" or not entity:IsDead())
end
local function relationKey(attackerId, defenderId)
	return token(attackerId) .. "|" .. token(defenderId)
end
local function hitKey(hit)
	return table.concat({ token(hit.Frame or 0), token(attackId(hit)), token(hit.AttackerEntityId or id(hit.Attacker)),
		token(hit.TargetEntityId or id(hit.Target)), token(hit.HitboxId or (hit.Hitbox and hit.Hitbox.Id)),
		token(hit.HurtboxId or (hit.Hurtbox and hit.Hurtbox.Id)) }, "|")
end
local function compareHits(a, b)
	if (a.Frame or 0) ~= (b.Frame or 0) then return (a.Frame or 0) < (b.Frame or 0) end
	for _, pair in ipairs({ { attackId(a), attackId(b) },
		{ a.AttackerEntityId or id(a.Attacker), b.AttackerEntityId or id(b.Attacker) },
		{ a.TargetEntityId or id(a.Target), b.TargetEntityId or id(b.Target) },
		{ a.HitboxId or (a.Hitbox and a.Hitbox.Id), b.HitboxId or (b.Hitbox and b.Hitbox.Id) },
		{ a.HurtboxId or (a.Hurtbox and a.Hurtbox.Id), b.HurtboxId or (b.Hurtbox and b.Hurtbox.Id) } }) do
		local order = compareId(pair[1], pair[2]); if order ~= 0 then return order < 0 end
	end
	return false
end

function ComboResolver.new(world, profile)
	if profile == nil then profile = ComboProfile.new() end
	if getmetatable(profile) ~= ComboProfile then profile = ComboProfile.new(profile) end
	return setmetatable({ World = world, Profile = profile, Events = {}, Results = {}, Active = {}, IdGenerator = world and world.IdGenerator or IdGenerator.new() }, ComboResolver)
end
function ComboResolver:_component(attacker)
	if type(attacker) ~= "table" and self.World and type(self.World.GetEntity) == "function" then
		attacker = self.World:GetEntity(attacker)
	end
	if not attacker or attacker.Destroyed or type(attacker.GetComponent) ~= "function" then return nil end
	return attacker:GetComponent(ComboComponent)
end
function ComboResolver:GetCombo(attacker, defender)
	local component = self:_component(attacker)
	if not component then return nil end
	if type(attacker) ~= "table" and self.World and type(self.World.GetEntity) == "function" then
		attacker = self.World:GetEntity(attacker)
	end
	if type(defender) ~= "table" and self.World and type(self.World.GetEntity) == "function" then
		defender = self.World:GetEntity(defender)
	end
	return component:GetCombo(attacker, defender)
end
function ComboResolver:GetActiveCombos()
	local result = {}; for _, combo in pairs(self.Active) do table.insert(result, combo) end
	table.sort(result, function(a, b) return a.ComboId < b.ComboId end); return result
end
function ComboResolver:GetEvents()
	local result = {}; for _, event in ipairs(self.Events) do table.insert(result, event) end; return result
end
function ComboResolver:GetResults()
	local result = {}; for _, item in ipairs(self.Results) do table.insert(result, item) end; return result
end

local function comboProfileState(profile)
	return { MaxGapFrames = profile.MaxGapFrames, CountBlockedHits = profile.CountBlockedHits,
		RequireDamage = profile.RequireDamage, RequireHitstun = profile.RequireHitstun,
		MaxHitRecords = profile.MaxHitRecords }
end
local function sameProfile(a, b)
	return a.MaxGapFrames == b.MaxGapFrames and a.CountBlockedHits == b.CountBlockedHits
		and a.RequireDamage == b.RequireDamage and a.RequireHitstun == b.RequireHitstun
		and a.MaxHitRecords == b.MaxHitRecords
end
local function denseArray(value)
	if type(value) ~= "table" then return false end
	local count, maxIndex = 0, 0
	for key in pairs(value) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
		count += 1
		if key > maxIndex then maxIndex = key end
	end
	return count == maxIndex
end
local function finiteInteger(value, minimum)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
		and value >= (minimum or 0) and value % 1 == 0
end

-- Register this resolver with CombatStateSchema:RegisterStateProvider("combat.combo-resolver.v1", resolver).
-- Active combo objects are rebuilt from staged ComboComponents, not serialized as Lua references.
function ComboResolver:CaptureRollbackState()
	local active = {}
	for _, combo in ipairs(self:GetActiveCombos()) do
		active[#active + 1] = { ComboId = combo.ComboId, AttackerId = combo.AttackerId,
			DefenderId = combo.DefenderId, StartFrame = combo.StartFrame, LastHitFrame = combo.LastHitFrame,
			DurationFrames = combo.DurationFrames, HitCount = combo.HitCount,
			ConfirmedHitCount = combo.ConfirmedHitCount, BlockedHitCount = combo.BlockedHitCount,
			Damage = combo.Damage, ChipDamage = combo.ChipDamage }
	end
	return { Version = 1, Profile = comboProfileState(self.Profile), Active = active,
		EventCount = #self.Events, ResultCount = #self.Results }
end

function ComboResolver:ValidateRollbackState(state, world)
	if type(state) ~= "table" or state.Version ~= 1 then return false, "Unsupported ComboResolver state" end
	if type(state.Profile) ~= "table" or not sameProfile(state.Profile, comboProfileState(self.Profile)) then
		return false, "ComboResolver profile mismatch"
	end
	if not denseArray(state.Active) or not finiteInteger(state.EventCount, 0)
		or not finiteInteger(state.ResultCount, 0) then return false, "Invalid ComboResolver output counts or active list" end
	local seenIds, seenRelations, previousId = {}, {}, nil
	for _, saved in ipairs(state.Active) do
		if type(saved) ~= "table" or type(saved.ComboId) ~= "number" or saved.ComboId < 1
			or saved.ComboId % 1 ~= 0 or saved.ComboId ~= saved.ComboId or saved.ComboId == math.huge then
			return false, "Invalid active combo ID"
		end
		if previousId ~= nil and saved.ComboId <= previousId then return false, "Active combos are not canonically ordered" end
		previousId = saved.ComboId
		if seenIds[saved.ComboId] then return false, "Duplicate active combo ID" end
		seenIds[saved.ComboId] = true
		if (type(saved.AttackerId) ~= "number" and type(saved.AttackerId) ~= "string")
			or (type(saved.DefenderId) ~= "number" and type(saved.DefenderId) ~= "string")
			or saved.AttackerId == saved.DefenderId then return false, "Invalid active combo entity IDs" end
		local relation = relationKey(saved.AttackerId, saved.DefenderId)
		if seenRelations[relation] then return false, "Duplicate active combo relation" end
		seenRelations[relation] = true
		for _, field in ipairs({ "StartFrame", "LastHitFrame", "HitCount", "ConfirmedHitCount", "BlockedHitCount" }) do
			local value = saved[field]
			if type(value) ~= "number" or value < 0 or value % 1 ~= 0 or value ~= value or value == math.huge then
				return false, "Invalid active combo field: " .. field
			end
		end
		if saved.LastHitFrame < saved.StartFrame or saved.HitCount ~= saved.ConfirmedHitCount + saved.BlockedHitCount then
			return false, "Inconsistent active combo counters"
		end
		if not finiteInteger(saved.DurationFrames, 0) or type(saved.Damage) ~= "number" or saved.Damage ~= saved.Damage
			or saved.Damage < 0 or saved.Damage == math.huge or saved.Damage == -math.huge
			or type(saved.ChipDamage) ~= "number" or saved.ChipDamage ~= saved.ChipDamage
			or saved.ChipDamage < 0 or saved.ChipDamage == math.huge or saved.ChipDamage == -math.huge then
			return false, "Invalid active combo totals"
		end
	end
	return true
end

function ComboResolver:PrepareRollbackRestore(state, world, context, role)
	local entityMap = role == "Target" and context and context.TargetEntitiesById
		or context and context.CurrentEntitiesById
	if type(entityMap) ~= "table" then return nil, "ComboResolver restore context has no entity map" end
	local preparedActive = {}
	for _, saved in ipairs(state.Active) do
		local attacker, defender = entityMap[saved.AttackerId], entityMap[saved.DefenderId]
		if not attacker or not defender then return nil, "ComboResolver entity reference is absent from staged roster" end
		local component = attacker:GetComponent(ComboComponent)
		local combo = component and component:GetCombo(saved.AttackerId, saved.DefenderId)
		if not combo or combo.ComboId ~= saved.ComboId or combo.StartFrame ~= saved.StartFrame
			or combo.LastHitFrame ~= saved.LastHitFrame or combo.DurationFrames ~= saved.DurationFrames
			or combo.HitCount ~= saved.HitCount or combo.ConfirmedHitCount ~= saved.ConfirmedHitCount
			or combo.BlockedHitCount ~= saved.BlockedHitCount or combo.Damage ~= saved.Damage
			or combo.ChipDamage ~= saved.ChipDamage then
			return nil, "ComboResolver active map does not match staged ComboComponent state"
		end
		preparedActive[relationKey(saved.AttackerId, saved.DefenderId)] = combo
	end
	if state.EventCount > #self.Events or state.ResultCount > #self.Results then
		return nil, "ComboResolver output history no longer contains the snapshot prefix"
	end
	local previousEvents, previousResults = {}, {}
	for index, event in ipairs(self.Events) do previousEvents[index] = event end
	for index, result in ipairs(self.Results) do previousResults[index] = result end
	return function()
		self.Active = preparedActive
		if role == "Target" then
			while #self.Events > state.EventCount do table.remove(self.Events) end
			while #self.Results > state.ResultCount do table.remove(self.Results) end
		else
			table.clear(self.Events); for _, event in ipairs(previousEvents) do table.insert(self.Events, event) end
			table.clear(self.Results); for _, result in ipairs(previousResults) do table.insert(self.Results, result) end
		end
		for _, entity in pairs(entityMap) do
			local component = entity:GetComponent(ComboComponent)
			if component then component.Resolver = self end
		end
	end
end
function ComboResolver:_emit(combo, eventType, frame, hit, reason, counter)
	local event = ComboEvent.new({ Type = eventType, ComboId = combo.ComboId, Frame = frame,
		Attacker = combo.Attacker, Defender = combo.Defender, AttackerId = combo.AttackerId,
		DefenderId = combo.DefenderId, HitEvent = hit, HitCount = combo.HitCount,
		ConfirmedHitCount = combo.ConfirmedHitCount, BlockedHitCount = combo.BlockedHitCount,
		Damage = combo.Damage, ChipDamage = combo.ChipDamage, Reason = reason,
		IsCounterHit = counter, Combo = combo })
	table.insert(self.Events, event)
	return event
end
function ComboResolver:_finish(combo, frame, reason, broken)
	if not combo or combo.State ~= "Active" then return nil end
	combo.DurationFrames = math.max(combo.DurationFrames or 0, frame - combo.StartFrame)
	combo.State, combo.EndFrame, combo.BreakReason = broken and "Broken" or "Ended", frame, reason
	local component = self:_component(combo.Attacker)
	if component then component:_RemoveCombo(combo.AttackerId, combo.DefenderId) end
	self.Active[relationKey(combo.AttackerId, combo.DefenderId)] = nil
	local eventType = broken and ComboEvent.Type.Broken or ComboEvent.Type.Ended
	self:_emit(combo, eventType, frame, nil, reason, false)
	table.insert(self.Results, ComboResult.new({ Type = broken and ComboResult.Type.Broken or ComboResult.Type.Ended,
		ComboId = combo.ComboId, Combo = combo, Frame = frame, Reason = reason }))
	return combo
end
function ComboResolver:Break(attacker, defender, reason, frame)
	local combo = self:GetCombo(attacker, defender)
	if not combo then return nil end
	return self:_finish(combo, frame or (self.World and self.World.CurrentFrame or combo.LastHitFrame), reason or "Manual", true)
end
function ComboResolver:BreakEntity(entity, reason, frame)
	local combos = self:GetActiveCombos()
	for _, combo in ipairs(combos) do
		if combo.Attacker == entity or combo.Defender == entity then
			self:_finish(combo, frame or (self.World and self.World.CurrentFrame or combo.LastHitFrame), reason or "InvalidTarget", false)
		end
	end
end
function ComboResolver:Reset(frame)
	for _, combo in ipairs(self:GetActiveCombos()) do self:_finish(combo, frame or (self.World and self.World.CurrentFrame or 0), "Manual", false) end
	return self
end
function ComboResolver:_append(combo, hit, frame, confirmed, damage, counter)
	combo.HitCount += 1
	if confirmed then combo.ConfirmedHitCount += 1 else combo.BlockedHitCount += 1 end
	combo.LastHitFrame = frame
	combo.DurationFrames = math.max(combo.DurationFrames or 0, frame - combo.StartFrame)
	if confirmed and damage then combo.Damage += damage end
	local record = { HitIndex = combo.HitCount, Frame = frame, AttackInstanceId = attackId(hit),
		HitEventId = hitKey(hit), Damage = confirmed and (damage or 0) or 0,
		IsCounterHit = counter == true, IsBlocked = not confirmed }
	table.insert(combo.HitRecords, record)
	while #combo.HitRecords > combo.Profile.MaxHitRecords do table.remove(combo.HitRecords, 1) end
	return record
end
function ComboResolver:_record(hit, frame, confirmed, damage, counter)
	local attacker, defender = hit.Attacker, hit.Target
	local attackerId, defenderId = hit.AttackerEntityId or id(attacker), hit.TargetEntityId or id(defender)
	if not alive(attacker) or not alive(defender) or attackerId == nil or defenderId == nil then
		table.insert(self.Results, ComboResult.new({ Type = ComboResult.Type.Ignored, HitEvent = hit, Frame = frame, Reason = "InvalidTarget" }))
		return
	end
	local component = self:_component(attacker)
	if not component then
		table.insert(self.Results, ComboResult.new({ Type = ComboResult.Type.Ignored, HitEvent = hit, Frame = frame, Reason = "MissingComboComponent" }))
		return
	end
	local key = relationKey(attackerId, defenderId)
	local combo = self.Active[key]
	if combo and frame - combo.LastHitFrame > combo.Profile.MaxGapFrames then self:_finish(combo, frame, "Timeout", false); combo = nil end
	local profile = combo and combo.Profile or self.Profile
	if profile.RequireDamage and (not confirmed or (damage or 0) <= 0) then
		table.insert(self.Results, ComboResult.new({ Type = ComboResult.Type.Ignored, ComboId = combo and combo.ComboId, Combo = combo, HitEvent = hit, Frame = frame, Reason = "DamageRequired" }))
		return
	end
	if profile.RequireHitstun then
		local frames = hit.Hitstun or (hit.OffensiveProperties and hit.OffensiveProperties.Hitstun) or 0
		if not confirmed or frames <= 0 then
			table.insert(self.Results, ComboResult.new({ Type = ComboResult.Type.Ignored, ComboId = combo and combo.ComboId, Combo = combo, HitEvent = hit, Frame = frame, Reason = "HitstunRequired" }))
			return
		end
	end
	if not confirmed and not profile.CountBlockedHits then
		table.insert(self.Results, ComboResult.new({ Type = ComboResult.Type.Ignored, ComboId = combo and combo.ComboId, Combo = combo, HitEvent = hit, Frame = frame, Reason = "Blocked" }))
		return
	end
	local started = false
	if not combo then
		local comboId = self.IdGenerator:Next()
		combo = Combo.new({ ComboId = comboId, Attacker = attacker, Defender = defender,
			AttackerId = attackerId, DefenderId = defenderId, StartFrame = frame, LastHitFrame = frame, Profile = self.Profile })
		self.Active[key] = combo; component:_SetCombo(combo, self); started = true
	end
	local record = self:_append(combo, hit, frame, confirmed, damage, counter)
	if started then self:_emit(combo, ComboEvent.Type.Started, frame, hit, nil, counter) end
	self:_emit(combo, ComboEvent.Type.Hit, frame, hit, nil, counter)
	table.insert(self.Results, ComboResult.new({ Type = started and ComboResult.Type.Started or ComboResult.Type.Continued,
		ComboId = combo.ComboId, Combo = combo, HitEvent = hit, Frame = frame }))
end

function ComboResolver:Process(hitEvents, defenseEvents, damageEvents, counterResults, frame, deathEvents, guardEvents, armorResults, reactionHitEvents)
	assert(type(hitEvents or {}) == "table", "ComboResolver:Process() expects HitEvents")
	frame = frame or (self.World and self.World.CurrentFrame or 0)
	assert(type(frame) == "number" and frame >= 0 and frame < math.huge and frame == frame and frame % 1 == 0,
		"ComboResolver frame must be a non-negative simulation frame")
	self.Events, self.Results = {}, {}
	local orderedDeaths = {}
	for _, death in ipairs(deathEvents or {}) do table.insert(orderedDeaths, death) end
	table.sort(orderedDeaths, function(a, b)
		if (a.Frame or frame) ~= (b.Frame or frame) then return (a.Frame or frame) < (b.Frame or frame) end
		return compareId(id(a.Entity), id(b.Entity)) < 0
	end)
	for _, death in ipairs(orderedDeaths) do self:BreakEntity(death.Entity, "Death", death.Frame or frame) end
	for _, combo in ipairs(self:GetActiveCombos()) do
		if not alive(combo.Attacker) or not alive(combo.Defender)
			or (self.World and (self.World:GetEntity(combo.AttackerId) ~= combo.Attacker or self.World:GetEntity(combo.DefenderId) ~= combo.Defender)) then
			local dead = (combo.Attacker and combo.Attacker.State == EntityState.Dead)
				or (combo.Defender and combo.Defender.State == EntityState.Dead)
			self:_finish(combo, frame, dead and "Death" or "InvalidTarget", false)
		elseif frame - combo.LastHitFrame > combo.Profile.MaxGapFrames then self:_finish(combo, frame, "Timeout", false) end
	end
	local damageByHit, counterByHit, defenseByHit, armorByHit, reactionAllowed = {}, {}, {}, {}, nil
	for _, event in ipairs(damageEvents or {}) do if event.HitEvent then damageByHit[event.HitEvent] = (damageByHit[event.HitEvent] or 0) + (event.AppliedAmount or event.Amount or 0) end end
	for _, result in ipairs(counterResults or {}) do if result.HitEvent then counterByHit[result.HitEvent] = result.Type == "CounterHit" end end
	for _, event in ipairs(defenseEvents or {}) do defenseByHit[event.HitEvent] = event end
	for _, result in ipairs(armorResults or {}) do armorByHit[result.HitEvent] = result end
	if reactionHitEvents then reactionAllowed = {}; for _, hit in ipairs(reactionHitEvents) do reactionAllowed[hit] = true end end
	local parries = {}
	for _, event in ipairs(defenseEvents or {}) do if event.Result == DefenseResult.Parried then table.insert(parries, event) end end
	table.sort(parries, function(a, b) if (a.Frame or frame) ~= (b.Frame or frame) then return (a.Frame or frame) < (b.Frame or frame) end; return compareHits(a.HitEvent, b.HitEvent) end)
	for _, event in ipairs(parries) do
		local hit = event.HitEvent; local combo = hit and self:GetCombo(hit.Attacker, hit.Target)
		if combo then self:_finish(combo, event.Frame or frame, "Parry", true) end
	end
	local blockedHits = {}
	for _, event in ipairs(defenseEvents or {}) do
		if event.Result == DefenseResult.Blocked and event.HitEvent then table.insert(blockedHits, event.HitEvent) end
	end
	for _, event in ipairs(guardEvents or {}) do if event.GuardBroken and event.HitEvent then blockedHits[#blockedHits + 1] = event.HitEvent end end
	local seen = {}
	local orderedBlocked = {}; for _, hit in ipairs(blockedHits) do table.insert(orderedBlocked, hit) end; table.sort(orderedBlocked, compareHits)
	for _, hit in ipairs(orderedBlocked) do
		local k = hitKey(hit)
		if not seen[k] then seen[k] = true; self:_record(hit, hit.Frame or frame, false, 0, false) end
	end
	local ordered = {}; for _, hit in ipairs(hitEvents or {}) do table.insert(ordered, hit) end; table.sort(ordered, compareHits)
	for _, hit in ipairs(ordered) do
		local k = hitKey(hit)
		local armor = armorByHit[hit]
		local hasHitstun = (hit.Hitstun or (hit.OffensiveProperties and hit.OffensiveProperties.Hitstun) or 0) > 0
		local hitstunAvailable = hasHitstun and (not armor or not armor:Blocks("Hitstun"))
		if reactionAllowed and not reactionAllowed[hit] then hitstunAvailable = false end
		local profile = self:GetCombo(hit.Attacker, hit.Target)
		profile = profile and profile.Profile or self.Profile
		if not seen[k] and (not profile.RequireHitstun or hitstunAvailable)
			and (not defenseByHit[hit] or defenseByHit[hit].Result == DefenseResult.Normal) then
			seen[k] = true
			local damage = damageByHit[hit] or 0
			self:_record(hit, hit.Frame or frame, true, damage, counterByHit[hit] == true)
		end
	end
	return self:GetResults()
end

return ComboResolver
