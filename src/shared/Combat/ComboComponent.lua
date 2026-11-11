local Component = require(script.Parent.Parent.Core.Component)
local Combo = require(script.Parent.Combo)
local ComboProfile = require(script.Parent.ComboProfile)

local ComboComponent = setmetatable({}, Component)
ComboComponent.__index = ComboComponent
ComboComponent.RollbackKey = "Combat.ComboComponent"

local function relationKey(a, d)
	return type(a) .. "#" .. tostring(a) .. "|" .. type(d) .. "#" .. tostring(d)
end
local function finiteNumber(value, minimum)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
		and value >= (minimum or -math.huge)
end
local function integer(value, minimum)
	return finiteNumber(value, minimum) and value % 1 == 0
end
local function isDenseArray(value)
	if type(value) ~= "table" then return false end
	local count, maxIndex = 0, 0
	for key in pairs(value) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
		count += 1
		if key > maxIndex then maxIndex = key end
	end
	return count == maxIndex
end
local function profileState(profile)
	return {
		MaxGapFrames = profile.MaxGapFrames,
		CountBlockedHits = profile.CountBlockedHits,
		RequireDamage = profile.RequireDamage,
		RequireHitstun = profile.RequireHitstun,
		MaxHitRecords = profile.MaxHitRecords,
	}
end
local function comboState(combo)
	return {
		ComboId = combo.ComboId,
		AttackerId = combo.AttackerId,
		DefenderId = combo.DefenderId,
		StartFrame = combo.StartFrame,
		LastHitFrame = combo.LastHitFrame,
		DurationFrames = combo.DurationFrames,
		HitCount = combo.HitCount,
		ConfirmedHitCount = combo.ConfirmedHitCount,
		BlockedHitCount = combo.BlockedHitCount,
		Damage = combo.Damage,
		ChipDamage = combo.ChipDamage,
		State = combo.State,
		BreakReason = combo.BreakReason,
		EndFrame = combo.EndFrame,
		HitRecords = combo.HitRecords,
		Profile = profileState(combo.Profile),
	}
end

function ComboComponent.new()
	local self = setmetatable(Component.new(), ComboComponent)
	self.ActiveCombos = {}
	return self
end
function ComboComponent:_SetCombo(combo, resolver)
	self.ActiveCombos[relationKey(combo.AttackerId, combo.DefenderId)] = combo
	self.Resolver = resolver
	return combo
end
function ComboComponent:_RemoveCombo(attackerId, defenderId)
	local k = relationKey(attackerId, defenderId)
	local combo = self.ActiveCombos[k]
	self.ActiveCombos[k] = nil
	return combo
end
function ComboComponent:GetCombo(attacker, defender)
	local a = type(attacker) == "table" and attacker.Id or attacker
	local d = type(defender) == "table" and defender.Id or defender
	return self.ActiveCombos[relationKey(a, d)]
end
function ComboComponent:GetActiveCombos()
	local result = {}
	for _, combo in pairs(self.ActiveCombos) do table.insert(result, combo) end
	table.sort(result, function(a, b) return a.ComboId < b.ComboId end)
	return result
end
function ComboComponent:IsInCombo(attacker, defender)
	if attacker ~= nil and defender ~= nil then return self:GetCombo(attacker, defender) ~= nil end
	return next(self.ActiveCombos) ~= nil
end

function ComboComponent:CaptureRollbackState()
	local combos = {}
	for _, combo in ipairs(self:GetActiveCombos()) do
		assert(combo.State == "Active", "ComboComponent only stores active combos")
		combos[#combos + 1] = comboState(combo)
	end
	return { Version = 1, Combos = combos }
end

function ComboComponent:ValidateRollbackState(state, context)
	if type(state) ~= "table" or state.Version ~= 1 then return false, "Unsupported ComboComponent state" end
	if not isDenseArray(state.Combos) then return false, "Combo list must be a dense array" end
	local seenCombo, seenRelation = {}, {}
	local previousId = nil
	for index, saved in ipairs(state.Combos) do
		if type(saved) ~= "table" or not integer(saved.ComboId, 1) then return false, "Invalid combo ID" end
		if previousId ~= nil and saved.ComboId <= previousId then return false, "Combos are not in canonical ID order" end
		previousId = saved.ComboId
		if seenCombo[saved.ComboId] then return false, "Duplicate combo ID" end
		seenCombo[saved.ComboId] = true
		if (type(saved.AttackerId) ~= "number" and type(saved.AttackerId) ~= "string")
			or (type(saved.DefenderId) ~= "number" and type(saved.DefenderId) ~= "string")
			or saved.AttackerId == saved.DefenderId then return false, "Invalid combo entity IDs" end
		local relation = relationKey(saved.AttackerId, saved.DefenderId)
		if seenRelation[relation] then return false, "Duplicate active combo relation" end
		seenRelation[relation] = true
		if context and context.EntitiesById then
			if not context.EntitiesById[saved.AttackerId] or not context.EntitiesById[saved.DefenderId] then
				return false, "Combo references an entity absent from the restore roster"
			end
		end
		for _, field in ipairs({ "StartFrame", "LastHitFrame", "DurationFrames", "HitCount", "ConfirmedHitCount", "BlockedHitCount" }) do
			if not integer(saved[field], 0) then return false, "Invalid combo field: " .. field end
		end
		if saved.LastHitFrame < saved.StartFrame or saved.DurationFrames < 0
			or saved.HitCount ~= saved.ConfirmedHitCount + saved.BlockedHitCount then
			return false, "Inconsistent combo counters or frames"
		end
		if not finiteNumber(saved.Damage, 0) or not finiteNumber(saved.ChipDamage, 0) then return false, "Invalid combo damage totals" end
		if saved.State ~= "Active" then return false, "Only active combos can be restored" end
		if type(saved.Profile) ~= "table" then return false, "Missing combo profile" end
		local profileOk = pcall(ComboProfile.new, saved.Profile)
		if not profileOk then return false, "Invalid combo profile" end
		if not isDenseArray(saved.HitRecords) then return false, "Combo hit records must be a dense array" end
		local maxRecords = saved.Profile.MaxHitRecords or 128
		if #saved.HitRecords > maxRecords then return false, "Too many combo hit records" end
		local previousHitIndex = 0
		for _, record in ipairs(saved.HitRecords) do
			if type(record) ~= "table" or not integer(record.HitIndex, 1) or record.HitIndex <= previousHitIndex
				or not integer(record.Frame, 0) or record.Frame > saved.LastHitFrame
				or not finiteNumber(record.Damage, 0) or type(record.IsCounterHit) ~= "boolean"
				or type(record.IsBlocked) ~= "boolean" or type(record.HitEventId) ~= "string" then
				return false, "Invalid combo hit record"
			end
			previousHitIndex = record.HitIndex
		end
	end
	return true
end

function ComboComponent:RestoreRollbackState(state, context)
	local valid, detail = self:ValidateRollbackState(state, context)
	if not valid then return false, detail end
	local staged = {}
	for _, saved in ipairs(state.Combos) do
		local attacker = context and context.EntitiesById and context.EntitiesById[saved.AttackerId]
		local defender = context and context.EntitiesById and context.EntitiesById[saved.DefenderId]
		if not attacker or not defender then return false, "Combo entity references could not be resolved" end
		local combo = Combo.new({ ComboId = saved.ComboId, Attacker = attacker, Defender = defender,
			AttackerId = saved.AttackerId, DefenderId = saved.DefenderId,
			StartFrame = saved.StartFrame, LastHitFrame = saved.LastHitFrame,
			Profile = ComboProfile.new(saved.Profile) })
		for _, field in ipairs({ "DurationFrames", "HitCount", "ConfirmedHitCount", "BlockedHitCount", "Damage", "ChipDamage", "State", "BreakReason", "EndFrame" }) do
			combo[field] = saved[field]
		end
		combo.HitRecords = {}
		for _, record in ipairs(saved.HitRecords) do
			local copy = {}
			for key, value in pairs(record) do copy[key] = value end
			table.insert(combo.HitRecords, copy)
		end
		staged[relationKey(saved.AttackerId, saved.DefenderId)] = combo
	end
	self.ActiveCombos = staged
	return true
end

function ComboComponent:Destroy()
	-- Detaching a staged/retired component must not mutate the resolver's active state.
	-- The global ComboResolver provider owns active-map replacement during rollback.
	if self.Resolver and self.Entity and self.Entity.World then
		self.Resolver:BreakEntity(self.Entity, "InvalidTarget")
	end
	table.clear(self.ActiveCombos)
	self.Resolver = nil
end

return ComboComponent
