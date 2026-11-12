local CollisionQuery = require(script.Parent.CollisionQuery)
local HitResolver = require(script.Parent.HitResolver)
local HitProcessor = require(script.Parent.HitProcessor)
local DamageResolver = require(script.Parent.DamageResolver)
local CombatReactionResolver = require(script.Parent.CombatReactionResolver)
local DefenseResolver = require(script.Parent.DefenseResolver)
local CombatResolver = require(script.Parent.CombatResolver)
local CounterResolver = require(script.Parent.CounterResolver)
local MotionResolver = require(script.Parent.MotionResolver)
local EntityState = require(script.Parent.Parent.Core.EntityState)
local IdGenerator = require(script.Parent.Parent.Core.IdGenerator)
local Hitbox = require(script.Parent.Hitbox)
local Hurtbox = require(script.Parent.Hurtbox)
local AttackInstance = require(script.Parent.AttackInstance)
local Serializer = require(script.Parent.Parent.Simulation.StateSerializer)

local CollisionWorld = {}
CollisionWorld.__index = CollisionWorld

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

local function isOwnerActive(owner)
	if owner == nil then
		return true
	end
	if type(owner) ~= "table" then
		return true
	end
	if owner.Destroyed or owner.State == EntityState.Dead then
		return false
	end
	if type(owner.IsDead) == "function" and owner:IsDead() then
		return false
	end
	return true
end

local function isOwnerDestroyed(owner)
	return type(owner) == "table" and owner.Destroyed == true
end

local function sortedValues(regions)
	local result = {}
	for _, region in pairs(regions) do
		table.insert(result, region)
	end
	table.sort(result, function(left, right)
		return left.Id < right.Id
	end)
	return result
end

local function pruneResults(self, region)
	local results = {}
	for _, result in ipairs(self.Results) do
		if result.Hitbox ~= region and result.Hurtbox ~= region then
			table.insert(results, result)
		end
	end
	self.Results = results

	local hitEvents = {}
	for _, event in ipairs(self.HitEvents) do
		if event.Hitbox ~= region and event.Hurtbox ~= region then
			table.insert(hitEvents, event)
		end
	end
	self.HitEvents = hitEvents
end

local function vectorState(value)
	return { value.X, value.Y, value.Z }
end

local function cframeState(value)
	return { value:GetComponents() }
end

local function stateVector(value)
	return Vector3.new(value[1], value[2], value[3])
end

local function stateCFrame(value)
	return CFrame.new(table.unpack(value))
end

local function stableId(value, label)
	assert(type(value) == "table" and (type(value.Id) == "number" or type(value.Id) == "string"),
		label .. " must have a stable numeric or string Id")
	return value.Id
end

local function idLess(left, right)
	if type(left) ~= type(right) then return type(left) < type(right) end
	return left < right
end

local function sortedMapKeys(map)
	local keys = {}
	for key in pairs(map) do table.insert(keys, key) end
	table.sort(keys, idLess)
	return keys
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

local CUSTOM_DATA_LIMITS = require(script.Parent.OffensiveProperties).CustomDataLimits

local function validateCustomDataOverrides(value)
	if value == nil then return true end
	if type(value) ~= "table" or getmetatable(value) ~= nil then return false end
	return pcall(Serializer.CloneSerializable, value, CUSTOM_DATA_LIMITS)
end

function CollisionWorld.new(world)
	local self = setmetatable({}, CollisionWorld)
	self.World = nil
	self.Hitboxes = {}
	self.Hurtboxes = {}
	self.ActivePairs = {}
	self.Results = {}
	self.HitEvents = {}
	self.HitResolver = HitResolver.new()
	self.HitProcessor = HitProcessor.new(world)
	self.DamageResolver = DamageResolver.new(world)
	self.ReactionResolver = CombatReactionResolver.new(world)
	self.DefenseResolver = DefenseResolver.new()
	self.CombatResolver = CombatResolver.new()
	self.CounterResolver = CounterResolver.new()
	self.MotionResolver = MotionResolver.new()
	self.IdGenerator = world and world.IdGenerator or IdGenerator.new()
	self.AttackCatalog = nil
	self.TopologyCatalog = nil
	self.LastStepDeltaTime = nil
	self.Frame = 0

	if world then
		assert(type(world.SetCollisionWorld) == "function",
			"CollisionWorld.new() expects a World with SetCollisionWorld()")
		self.World = world
		world:SetCollisionWorld(self)
	end

	return self
end

function CollisionWorld:SetAttackCatalog(catalog)
	assert(catalog == nil or (type(catalog) == "table"
		and type(catalog.Resolve) == "function"
		and type(catalog.CaptureManifest) == "function"
		and type(catalog.ValidateManifest) == "function"),
		"SetAttackCatalog expects an AttackCatalog or nil")
	self.AttackCatalog = catalog
	return self
end

function CollisionWorld:SetTopologyCatalog(catalog)
 assert(catalog == nil or (type(catalog) == "table" and type(catalog.Resolve) == "function"
  and type(catalog.CaptureManifest) == "function" and type(catalog.ValidateManifest) == "function"
  and type(catalog.CreateRegion) == "function"),
  "SetTopologyCatalog expects a CollisionTopologyCatalog or nil")
 self.TopologyCatalog = catalog
 return self
end

function CollisionWorld:RegisterHitbox(hitbox)
	assert(hitbox and hitbox.CombatRegionType == "Hitbox",
		"CollisionWorld:RegisterHitbox() expects a Hitbox")
	if hitbox.Id == nil then
		hitbox.Id = self.IdGenerator:Next()
	end
	local existing = self.Hitboxes[hitbox.Id]
	assert(existing == nil or existing == hitbox, "Hitbox ID is already registered")
	self.Hitboxes[hitbox.Id] = hitbox
	return hitbox
end

function CollisionWorld:RegisterHurtbox(hurtbox)
	assert(hurtbox and hurtbox.CombatRegionType == "Hurtbox",
		"CollisionWorld:RegisterHurtbox() expects a Hurtbox")
	if hurtbox.Id == nil then
		hurtbox.Id = self.IdGenerator:Next()
	end
	local existing = self.Hurtboxes[hurtbox.Id]
	assert(existing == nil or existing == hurtbox, "Hurtbox ID is already registered")
	self.Hurtboxes[hurtbox.Id] = hurtbox
	return hurtbox
end

function CollisionWorld:RemoveHitbox(hitboxOrId)
	local id = type(hitboxOrId) == "table" and hitboxOrId.Id or hitboxOrId
	local hitbox = self.Hitboxes[id]
	if not hitbox then
		return false
	end

	self.Hitboxes[id] = nil
	self.ActivePairs[hitbox] = nil
	self.HitProcessor:RemoveRegion(hitbox)
	pruneResults(self, hitbox)
	return true
end

function CollisionWorld:RemoveHurtbox(hurtboxOrId)
	local id = type(hurtboxOrId) == "table" and hurtboxOrId.Id or hurtboxOrId
	local hurtbox = self.Hurtboxes[id]
	if not hurtbox then
		return false
	end

	self.Hurtboxes[id] = nil
	self.HitProcessor:RemoveRegion(hurtbox)
	for _, hurtboxes in pairs(self.ActivePairs) do
		hurtboxes[hurtbox] = nil
	end
	pruneResults(self, hurtbox)
	return true
end

function CollisionWorld:GetHitboxes()
	return sortedValues(self.Hitboxes)
end

function CollisionWorld:GetHurtboxes()
	return sortedValues(self.Hurtboxes)
end

function CollisionWorld:GetResults()
	local results = {}
	for _, result in ipairs(self.Results) do
		table.insert(results, result)
	end
	return results
end

function CollisionWorld:GetHitEvents()
	local hitEvents = {}
	for _, event in ipairs(self.HitEvents) do
		table.insert(hitEvents, event)
	end
	return hitEvents
end

function CollisionWorld:RemoveEntity(entity)
	for _, hitbox in ipairs(self:GetHitboxes()) do
		local instance = hitbox.AttackInstance
		if instance and instance.OwnerEntity == entity then
			instance:Finish()
		end
	end
	local results = {}
	for _, result in ipairs(self.Results) do
		if result.Attacker ~= entity and result.Target ~= entity then
			table.insert(results, result)
		end
	end
	self.Results = results
	local hitEvents = {}
	for _, event in ipairs(self.HitEvents) do
		if event.Attacker ~= entity and event.Target ~= entity then
			table.insert(hitEvents, event)
		end
	end
	self.HitEvents = hitEvents
	self.HitProcessor:RemoveEntity(entity)
end

function CollisionWorld:Step(deltaTime, frame, time)
	assert(isFiniteNumber(deltaTime) and deltaTime >= 0,
		"CollisionWorld:Step() expects a finite non-negative fixed deltaTime")
	if frame == nil then
		self.Frame += 1
		frame = self.Frame
	else
		assert(type(frame) == "number" and frame >= 0 and frame % 1 == 0,
			"CollisionWorld:Step() frame must be a non-negative integer")
		self.Frame = frame
	end
	if time == nil then
		time = frame * deltaTime
	end
	assert(isFiniteNumber(time), "CollisionWorld:Step() time must be finite")
	self.LastStepDeltaTime = deltaTime

	for _, hitbox in ipairs(self:GetHitboxes()) do
		if hitbox.Destroyed or isOwnerDestroyed(hitbox.Owner) then
			self:RemoveHitbox(hitbox)
		end
	end
	for _, hurtbox in ipairs(self:GetHurtboxes()) do
		if hurtbox.Destroyed or isOwnerDestroyed(hurtbox.Owner) then
			self:RemoveHurtbox(hurtbox)
		end
	end

	local hitboxes = self:GetHitboxes()
	local hurtboxes = self:GetHurtboxes()
	local nextActivePairs = {}
	local results = {}

	for _, hitbox in ipairs(hitboxes) do
		local attackOwner = hitbox.Owner
		if hitbox.AttackInstance then
			attackOwner = hitbox.AttackInstance.OwnerEntity
		end
		local activeOwner = attackOwner or hitbox.Owner
		if hitbox:IsEnabled() and isOwnerActive(activeOwner) then
			for _, hurtbox in ipairs(hurtboxes) do
				local distinctOwners = attackOwner == nil or hurtbox.Owner == nil
					or attackOwner ~= hurtbox.Owner
				if hurtbox:IsEnabled() and isOwnerActive(hurtbox.Owner)
					and distinctOwners and CollisionQuery.Intersects(hitbox, hurtbox)
				then
					local previousHurtboxes = self.ActivePairs[hitbox]
					local isContinuous = previousHurtboxes ~= nil and previousHurtboxes[hurtbox] == true
					local currentHurtboxes = nextActivePairs[hitbox]
					if currentHurtboxes == nil then
						currentHurtboxes = {}
						nextActivePairs[hitbox] = currentHurtboxes
					end
					currentHurtboxes[hurtbox] = true

					table.insert(results, {
						Hitbox = hitbox,
						Hurtbox = hurtbox,
						Attacker = attackOwner,
						Target = hurtbox.Owner,
						ContactType = isContinuous and "Continuous" or "FirstContact",
						IsFirstContact = not isContinuous,
						IsContinuous = isContinuous,
					})
				end
			end
		end
	end

	self.ActivePairs = nextActivePairs
	self.Results = results
	local candidates = self.HitResolver:Resolve(results)
	self.HitEvents = self.HitProcessor:Process(candidates, frame, time)
	return self:GetResults()
end


-- Phase 3 rollback state for a stable, already reconstructed collision topology.
-- Entity/region creation and destruction reconstruction is intentionally handled by the
-- next integration step; this API rejects topology mismatches instead of silently degrading.
function CollisionWorld:CaptureRollbackState()
	assert(#self.MotionResolver.PendingRequests == 0,
		"Cannot capture CollisionWorld state while standalone MotionResolver requests are pending; "
			.. "use MotionComponent for rollback-owned requests or process the queue first")
	local hitboxes, hurtboxes, attacks, activePairs = {}, {}, {}, {}
	local hitboxById, hurtboxById = {}, {}
	for _, hitbox in ipairs(self:GetHitboxes()) do hitboxById[stableId(hitbox, "Hitbox")] = hitbox end
	for _, hurtbox in ipairs(self:GetHurtboxes()) do hurtboxById[stableId(hurtbox, "Hurtbox")] = hurtbox end

	local function captureRegion(region)
		local ownerId = region.Owner and stableId(region.Owner, "Collision region owner") or nil
		local data = {
			Id = region.Id, OwnerEntityId = ownerId, Shape = region.Shape,
			CombatRegionType = region.CombatRegionType,
			TopologyDefinitionId = region.TopologyDefinitionId,
			TopologyDefinitionVersion = region.TopologyDefinitionVersion,
			Position = vectorState(region.Position), Rotation = cframeState(region.Rotation),
			Enabled = region:IsEnabled(),
			PriorityOverride = region.PriorityOverride, Priority = region.Priority,
			ClashGroup = region.ClashGroup, Damage = region.Damage, Hitstun = region.Hitstun,
			HitPolicy = region.HitPolicy, HitScope = region.HitScope,
			HasCanHitCallback = region.CanHit ~= nil,
			AttackInstanceId = region.AttackInstance and region.AttackInstance.Id or nil,
		}
		if region.Shape == "Box" then data.Size = vectorState(region.Size)
		else data.Radius = region.Radius end
		return data
	end
	for _, hitbox in ipairs(self:GetHitboxes()) do
		table.insert(hitboxes, captureRegion(hitbox))
		local instance = hitbox.AttackInstance
		if instance then
			if self.AttackCatalog then
				local registeredAttack, catalogError = self.AttackCatalog:Resolve(instance.Attack.Id)
				assert(registeredAttack == instance.Attack,
					"AttackInstance references a definition not registered in AttackCatalog: " .. tostring(catalogError or instance.Attack.Id))
			end
			local id = stableId(instance, "AttackInstance")
			local saved = attacks[id]
			if not saved then
				saved = {
					Id = id, AttackId = stableId(instance.Attack, "Attack definition"),
					DefinitionVersion = self.AttackCatalog and self.AttackCatalog:GetVersion(instance.Attack.Id) or nil,
					OwnerEntityId = instance.OwnerEntity and stableId(instance.OwnerEntity, "Attack owner") or nil,
					State = instance.State, HitboxIds = {},
						CustomDataOverrides = instance.CustomDataOverrides and Serializer.CloneSerializable(instance.CustomDataOverrides, CUSTOM_DATA_LIMITS) or nil,
				}
				attacks[id] = saved
			end
			table.insert(saved.HitboxIds, hitbox.Id)
		end
	end
	for _, hurtbox in ipairs(self:GetHurtboxes()) do table.insert(hurtboxes, captureRegion(hurtbox)) end
	for _, id in ipairs(sortedMapKeys(attacks)) do
		local attack = attacks[id]
		table.sort(attack.HitboxIds, idLess)
		table.insert(activePairs, attack)
	end
	local pairsState = {}
	for _, hitboxId in ipairs(sortedMapKeys(hitboxById)) do
		local hitbox = hitboxById[hitboxId]
		local targets = self.ActivePairs[hitbox]
		if targets then
			local ids = {}
			for hurtbox in pairs(targets) do table.insert(ids, stableId(hurtbox, "Active-pair Hurtbox")) end
			table.sort(ids, idLess)
			table.insert(pairsState, { HitboxId = hitboxId, HurtboxIds = ids })
		end
	end
	return {
		Version = 1, Frame = self.Frame, LastStepDeltaTime = self.LastStepDeltaTime,
		Hitboxes = hitboxes, Hurtboxes = hurtboxes, AttackInstances = activePairs,
		ActivePairs = pairsState, HitHistory = self.HitProcessor.HitHistory:CaptureRollbackState(),
		AttackCatalogManifest = self.AttackCatalog and self.AttackCatalog:CaptureManifest() or nil,
		TopologyCatalogManifest = self.TopologyCatalog and self.TopologyCatalog:CaptureManifest() or nil,
	}
end

function CollisionWorld:ValidateRollbackState(state)
	if type(state) ~= "table" or state.Version ~= 1 then return false, "Invalid CollisionWorld state version" end
	if type(state.Frame) ~= "number" or state.Frame < 0 or state.Frame % 1 ~= 0 then return false, "Invalid CollisionWorld frame" end
	if state.LastStepDeltaTime ~= nil and (not isFiniteNumber(state.LastStepDeltaTime) or state.LastStepDeltaTime < 0) then
		return false, "Invalid CollisionWorld delta time"
	end
	for _, name in ipairs({ "Hitboxes", "Hurtboxes", "AttackInstances", "ActivePairs" }) do
		if not isDenseArray(state[name]) then return false, "Missing or non-dense CollisionWorld " .. name end
	end
	if self.AttackCatalog then
		if type(state.AttackCatalogManifest) ~= "table" then
			return false, "Snapshot is missing the AttackCatalog manifest"
		end
		local manifestValid, manifestError = self.AttackCatalog:ValidateManifest(state.AttackCatalogManifest)
		if not manifestValid then return false, "AttackCatalog manifest rejected: " .. tostring(manifestError) end
	elseif state.AttackCatalogManifest ~= nil then
		return false, "Snapshot requires an AttackCatalog, but none is configured"
	end
	if self.TopologyCatalog then
		if type(state.TopologyCatalogManifest) ~= "table" then return false, "Snapshot is missing the topology catalog manifest" end
		local topologyValid, topologyError = self.TopologyCatalog:ValidateManifest(state.TopologyCatalogManifest)
		if not topologyValid then return false, "Topology catalog manifest rejected: " .. tostring(topologyError) end
	elseif state.TopologyCatalogManifest ~= nil then
		return false, "Snapshot requires a topology catalog, but none is configured"
	end
	local function validId(id) return type(id) == "number" and isFiniteNumber(id) and id % 1 == 0 or type(id) == "string" and id ~= "" end
	local function validateRegions(savedRegions, liveRegions, label)
		local seen = {}
		local liveCount = 0
		for _ in pairs(liveRegions) do liveCount += 1 end
		if #savedRegions ~= liveCount then return false, label .. " topology differs from snapshot" end
		local byId = {}
		for id, region in pairs(liveRegions) do byId[id] = region end
		for index, saved in ipairs(savedRegions) do
			if type(saved) ~= "table" or not validId(saved.Id) or seen[saved.Id] then return false, "Invalid/duplicate " .. label .. " ID" end
			seen[saved.Id] = true
			local region = byId[saved.Id]
			if not region then return false, label .. " missing live ID " .. tostring(saved.Id) end
			local liveOwnerId = region.Owner and region.Owner.Id or nil
			if liveOwnerId ~= saved.OwnerEntityId then return false, label .. " owner mismatch for ID " .. tostring(saved.Id) end
			if saved.OwnerEntityId ~= nil and (not self.World or not self.World:GetEntity(saved.OwnerEntityId)) then
				return false, label .. " references missing owner entity " .. tostring(saved.OwnerEntityId)
			end
			if saved.Shape ~= "Box" and saved.Shape ~= "Sphere" then return false, "Invalid region shape" end
			if region.Shape ~= saved.Shape then return false, label .. " shape mismatch for ID " .. tostring(saved.Id) end
			if type(saved.Position) ~= "table" or #saved.Position ~= 3 or type(saved.Rotation) ~= "table" or #saved.Rotation ~= 12 then
				return false, "Invalid transform for " .. label .. " " .. tostring(saved.Id)
			end
			for _, n in ipairs(saved.Position) do if not isFiniteNumber(n) then return false, "Non-finite region position" end end
			for _, n in ipairs(saved.Rotation) do if not isFiniteNumber(n) then return false, "Non-finite region rotation" end end
			if type(saved.Enabled) ~= "boolean" then return false, "Invalid Enabled flag" end
			if saved.OwnerEntityId ~= nil and (type(saved.OwnerEntityId) ~= "number" and type(saved.OwnerEntityId) ~= "string") then return false, "Invalid region owner ID" end
			if saved.Shape == "Box" then
				if type(saved.Size) ~= "table" or #saved.Size ~= 3 then return false, "Invalid Box size" end
				for _, n in ipairs(saved.Size) do if not isFiniteNumber(n) or n <= 0 then return false, "Invalid Box size value" end end
			else
				if not isFiniteNumber(saved.Radius) or saved.Radius < 0 then return false, "Invalid Sphere radius" end
			end
		end
		return true
	end
	local ok, reason = validateRegions(state.Hitboxes, self.Hitboxes, "Hitbox")
	if not ok then return false, reason end
	ok, reason = validateRegions(state.Hurtboxes, self.Hurtboxes, "Hurtbox")
	if not ok then return false, reason end
	local attacksById = {}
	for _, saved in ipairs(state.AttackInstances) do
		if type(saved) ~= "table" or not validId(saved.Id) or attacksById[saved.Id] then return false, "Invalid/duplicate AttackInstance ID" end
		if not validateCustomDataOverrides(saved.CustomDataOverrides) then
			return false, "Invalid CustomDataOverrides for AttackInstance " .. tostring(saved.Id)
		end
		if not isDenseArray(saved.HitboxIds) then return false, "Missing/non-dense AttackInstance hitbox IDs" end
		attacksById[saved.Id] = saved
		local found = false
		for _, hitbox in pairs(self.Hitboxes) do
			if hitbox.AttackInstance and hitbox.AttackInstance.Id == saved.Id then
				found = true
				if hitbox.AttackInstance.Attack.Id ~= saved.AttackId then return false, "Attack definition mismatch for instance " .. tostring(saved.Id) end
			end
		end
		if not found then return false, "AttackInstance topology mismatch for ID " .. tostring(saved.Id) end
		if saved.State ~= "Created" and saved.State ~= "Active" and saved.State ~= "Finished" then return false, "Invalid AttackInstance state" end
		if saved.AttackId == nil or (type(saved.AttackId) ~= "number" and type(saved.AttackId) ~= "string") then return false, "Invalid Attack definition ID" end
		if self.AttackCatalog then
			if saved.DefinitionVersion == nil then return false, "AttackInstance is missing definition version" end
			local definition, definitionError = self.AttackCatalog:Resolve(saved.AttackId, saved.DefinitionVersion)
			if not definition then return false, "Attack definition rejected: " .. tostring(definitionError) end
		end
		local liveInstance
		for _, hitbox in pairs(self.Hitboxes) do if hitbox.AttackInstance and hitbox.AttackInstance.Id == saved.Id then liveInstance = hitbox.AttackInstance; break end end
		local liveOwnerId = liveInstance and liveInstance.OwnerEntity and liveInstance.OwnerEntity.Id or nil
		if liveOwnerId ~= saved.OwnerEntityId then return false, "AttackInstance owner mismatch for " .. tostring(saved.Id) end
		if saved.OwnerEntityId ~= nil and (not self.World or not self.World:GetEntity(saved.OwnerEntityId)) then return false, "AttackInstance references missing owner entity" end
		local expectedHitboxes = {}
		for _, hitboxId in ipairs(saved.HitboxIds) do
			local hitbox = self.Hitboxes[hitboxId]
			if not hitbox or not hitbox.AttackInstance or hitbox.AttackInstance.Id ~= saved.Id or expectedHitboxes[hitboxId] then
				return false, "AttackInstance hitbox membership mismatch for " .. tostring(saved.Id)
			end
			expectedHitboxes[hitboxId] = true
		end
		local actualCount = 0
		for _, hitbox in pairs(self.Hitboxes) do
			if hitbox.AttackInstance and hitbox.AttackInstance.Id == saved.Id then actualCount += 1 end
		end
		if actualCount ~= #saved.HitboxIds then return false, "AttackInstance hitbox count mismatch for " .. tostring(saved.Id) end
	end
	local hitboxIds, hurtboxIds = {}, {}
	for id in pairs(self.Hitboxes) do hitboxIds[id] = self.Hitboxes[id] end
	for id in pairs(self.Hurtboxes) do hurtboxIds[id] = self.Hurtboxes[id] end
	local historyValid, historyError = self.HitProcessor.HitHistory:ValidateRollbackState(state.HitHistory, {
		RequireReferences = true,
		AttackInstancesById = (function() local m = {}; for _, h in pairs(self.Hitboxes) do if h.AttackInstance then m[h.AttackInstance.Id] = h.AttackInstance end end; return m end)(),
		EntitiesById = (function() local m = {}; if self.World then for _, e in ipairs(self.World:GetEntities()) do m[e.Id] = e end end; return m end)(),
		HitboxesById = hitboxIds, HurtboxesById = hurtboxIds,
	})
	if not historyValid then return false, "HitHistory: " .. tostring(historyError) end
	local seenPairs = {}
	for _, pairState in ipairs(state.ActivePairs) do
		if type(pairState) ~= "table" or not self.Hitboxes[pairState.HitboxId] or not isDenseArray(pairState.HurtboxIds) then return false, "Invalid active contact pair" end
		if seenPairs[pairState.HitboxId] then return false, "Duplicate active pair Hitbox ID" end
		seenPairs[pairState.HitboxId] = true
		local seenHurt = {}
		for _, hurtboxId in ipairs(pairState.HurtboxIds) do
			if not self.Hurtboxes[hurtboxId] or seenHurt[hurtboxId] then return false, "Invalid/duplicate active pair Hurtbox ID" end
			seenHurt[hurtboxId] = true
		end
	end
	return true
end

function CollisionWorld:PrepareRollbackRestore(state)
	local valid, reason = self:ValidateRollbackState(state)
	if not valid then return nil, reason end
	local attackInstancesById, entitiesById, hitboxesById, hurtboxesById = {}, {}, {}, {}
	for _, hitbox in pairs(self.Hitboxes) do
		hitboxesById[hitbox.Id] = hitbox
		if hitbox.AttackInstance then attackInstancesById[hitbox.AttackInstance.Id] = hitbox.AttackInstance end
	end
	for id, hurtbox in pairs(self.Hurtboxes) do hurtboxesById[id] = hurtbox end
	if self.World then for _, entity in ipairs(self.World:GetEntities()) do entitiesById[entity.Id] = entity end end
	local historyCommit, historyError = self.HitProcessor.HitHistory:PrepareRollbackRestore(state.HitHistory, {
		RequireReferences = true, AttackInstancesById = attackInstancesById,
		EntitiesById = entitiesById, HitboxesById = hitboxesById, HurtboxesById = hurtboxesById,
	})
	if not historyCommit then return nil, historyError end
	local function prepareRegion(saved, map)
		local region = map[saved.Id]
		return function()
			region.Position = stateVector(saved.Position)
			region.Rotation = stateCFrame(saved.Rotation)
			region:SetEnabled(saved.Enabled)
			if saved.Shape == "Box" then region.Size = stateVector(saved.Size) else region.Radius = saved.Radius; region.Size = Vector3.new(saved.Radius * 2, saved.Radius * 2, saved.Radius * 2) end
		end
	end
	local commits = {}
	for _, saved in ipairs(state.Hitboxes) do table.insert(commits, prepareRegion(saved, self.Hitboxes)) end
	for _, saved in ipairs(state.Hurtboxes) do table.insert(commits, prepareRegion(saved, self.Hurtboxes)) end
	local attackCommits = {}
	for _, saved in ipairs(state.AttackInstances) do
		local instance = attackInstancesById[saved.Id]
		local restoredOk, restoredInstance = pcall(AttackInstance.new,
			instance.Attack, instance.OwnerEntity, nil, {
				Id = saved.Id,
				CustomDataOverrides = saved.CustomDataOverrides,
			})
		if not restoredOk then
			return nil, "Invalid AttackInstance CustomDataOverrides for " .. tostring(saved.Id)
				.. ": " .. tostring(restoredInstance)
		end
		table.insert(attackCommits, function()
			instance.State = saved.State
			instance.OffensiveProperties = restoredInstance.OffensiveProperties
			instance.CustomDataOverrides = restoredInstance.CustomDataOverrides
			instance.Priority = restoredInstance.Priority
			instance.CanClash = restoredInstance.CanClash
		end)
	end
	local pairsStaged = {}
	for _, pairState in ipairs(state.ActivePairs) do
		local hitbox = hitboxesById[pairState.HitboxId]
		local targets = {}
		for _, hurtboxId in ipairs(pairState.HurtboxIds) do targets[hurtboxesById[hurtboxId]] = true end
		pairsStaged[hitbox] = targets
	end
	return function()
		for _, commit in ipairs(commits) do commit() end
		for _, commit in ipairs(attackCommits) do commit() end
		historyCommit()
		self.ActivePairs = pairsStaged
		self.Frame = state.Frame
		self.LastStepDeltaTime = state.LastStepDeltaTime
		-- Contact outputs are deliberately cleared: restoring them as new notifications could
		-- replay external effects. Consumers must use frame-keyed event IDs for deduplication.
		self.Results = {}
		self.HitEvents = {}
	end
end


-- Strictly stages an entirely new collision topology from a snapshot. No live map is
-- modified until the returned commit closure is called. Every region must have a
-- versioned factory definition; callbacks are supplied by that factory, never serialized.
function CollisionWorld:PrepareTopologyRebuild(state, entitiesByIdOverride)
 if not self.World then return nil, "Topology rebuild requires a World" end
 if type(state) ~= "table" or state.Version ~= 1 then return nil, "Invalid CollisionWorld snapshot version" end
 for _, name in ipairs({ "Hitboxes", "Hurtboxes", "AttackInstances", "ActivePairs" }) do
  if not isDenseArray(state[name]) then return nil, "Missing/non-dense " .. name end
 end
 if type(state.Frame) ~= "number" or not isFiniteNumber(state.Frame)
  or state.Frame < 0 or state.Frame % 1 ~= 0 then return nil, "Invalid collision frame" end
 if state.LastStepDeltaTime ~= nil
  and (not isFiniteNumber(state.LastStepDeltaTime) or state.LastStepDeltaTime < 0) then
  return nil, "Invalid collision delta time"
 end
 if not self.TopologyCatalog then
  if state.TopologyCatalogManifest ~= nil then return nil, "Snapshot requires a CollisionTopologyCatalog" end
  if #state.Hitboxes > 0 or #state.Hurtboxes > 0 or #state.AttackInstances > 0
   or #state.ActivePairs > 0 then
   return nil, "Non-empty collision topology requires a CollisionTopologyCatalog"
  end
  if next(self.Hitboxes) ~= nil or next(self.Hurtboxes) ~= nil or next(self.ActivePairs) ~= nil then
   return nil, "Cannot rebuild live collision topology without a CollisionTopologyCatalog"
  end
  if self.AttackCatalog then
   local attackOk, attackError = self.AttackCatalog:ValidateManifest(state.AttackCatalogManifest)
   if not attackOk then return nil, "Attack catalog manifest rejected: " .. tostring(attackError) end
  elseif state.AttackCatalogManifest ~= nil then
   return nil, "Snapshot requires an AttackCatalog"
  end
  local entitiesById = entitiesByIdOverride or {}
  if not entitiesByIdOverride then
   for _, entity in ipairs(self.World:GetEntities()) do entitiesById[entity.Id] = entity end
  end
  local historyCommit, historyError = self.HitProcessor.HitHistory:PrepareRollbackRestore(state.HitHistory, {
   RequireReferences = true,
   AttackInstancesById = {},
   EntitiesById = entitiesById,
   HitboxesById = {},
   HurtboxesById = {},
  })
  if not historyCommit then return nil, "HitHistory rejected empty topology restore: " .. tostring(historyError) end
  return function()
   historyCommit()
   self.Frame = state.Frame
   self.LastStepDeltaTime = state.LastStepDeltaTime
   self.Results, self.HitEvents = {}, {}
  end
 end
 local topologyOk, topologyError = self.TopologyCatalog:ValidateManifest(state.TopologyCatalogManifest)
 if not topologyOk then return nil, "Topology catalog manifest rejected: " .. tostring(topologyError) end
 if self.AttackCatalog then
  local attackOk, attackError = self.AttackCatalog:ValidateManifest(state.AttackCatalogManifest)
  if not attackOk then return nil, "Attack catalog manifest rejected: " .. tostring(attackError) end
 elseif state.AttackCatalogManifest ~= nil then return nil, "Snapshot requires an AttackCatalog" end
 local function validStableId(id)
  return (type(id) == "number" and isFiniteNumber(id) and id % 1 == 0)
   or (type(id) == "string" and id ~= "")
 end
 local function validateSavedRegions(regions, expectedType)
  local seen = {}
  for _, saved in ipairs(regions) do
   if type(saved) ~= "table" or saved.CombatRegionType ~= expectedType or not validStableId(saved.Id) then
    return false, "Invalid " .. expectedType .. " descriptor or stable ID"
   end
   if seen[saved.Id] then return false, "Duplicate " .. expectedType .. " ID" end
   seen[saved.Id] = true
   if saved.Shape ~= "Box" and saved.Shape ~= "Sphere" then return false, "Invalid region shape" end
   if type(saved.Position) ~= "table" or #saved.Position ~= 3 or type(saved.Rotation) ~= "table" or #saved.Rotation ~= 12 then
    return false, "Invalid region transform"
   end
   for _, value in ipairs(saved.Position) do if not isFiniteNumber(value) then return false, "Non-finite region position" end end
   for _, value in ipairs(saved.Rotation) do if not isFiniteNumber(value) then return false, "Non-finite region rotation" end end
   if type(saved.Enabled) ~= "boolean" then return false, "Invalid region Enabled flag" end
   if saved.OwnerEntityId ~= nil and not validStableId(saved.OwnerEntityId) then return false, "Invalid region owner ID" end
   if saved.Shape == "Box" then
    if type(saved.Size) ~= "table" or #saved.Size ~= 3 then return false, "Invalid box size" end
    for _, value in ipairs(saved.Size) do if not isFiniteNumber(value) or value <= 0 then return false, "Invalid box size value" end end
   elseif not isFiniteNumber(saved.Radius) or saved.Radius < 0 then return false, "Invalid sphere radius" end
   if saved.Priority ~= nil and not isFiniteNumber(saved.Priority) then
    return false, "Invalid region priority"
   end
   if saved.PriorityOverride ~= nil and not isFiniteNumber(saved.PriorityOverride) then return false, "Invalid region priority" end
   if saved.Hitstun ~= nil and (not isFiniteNumber(saved.Hitstun) or saved.Hitstun < 0 or saved.Hitstun % 1 ~= 0) then return false, "Invalid region hitstun" end
   if type(saved.HasCanHitCallback) ~= "boolean" then return false, "Missing callback compatibility marker" end
  end
  return true
 end
 local regionOk, regionError = validateSavedRegions(state.Hitboxes, "Hitbox")
 if not regionOk then return nil, regionError end
 regionOk, regionError = validateSavedRegions(state.Hurtboxes, "Hurtbox")
 if not regionOk then return nil, regionError end
 local entitiesById = entitiesByIdOverride or {}
 if not entitiesByIdOverride then
  for _, entity in ipairs(self.World:GetEntities()) do entitiesById[entity.Id] = entity end
 end
 local stagedHitboxes, stagedHurtboxes, stagedAttacks = {}, {}, {}
 local stagedHitboxesById, stagedHurtboxesById, stagedAttacksById = {}, {}, {}
 local function buildRegions(savedRegions, expectedType, targetMap, targetById)
  for _, saved in ipairs(savedRegions) do
   if type(saved) ~= "table" or saved.CombatRegionType ~= expectedType
    or saved.TopologyDefinitionId == nil or saved.TopologyDefinitionVersion == nil then
    return false, "Every restored region requires a typed, versioned topology definition"
   end
   if targetById[saved.Id] or (expectedType == "Hitbox" and stagedHurtboxesById[saved.Id])
    or (expectedType == "Hurtbox" and stagedHitboxesById[saved.Id]) then return false, "Duplicate collision region ID" end
   local owner = saved.OwnerEntityId ~= nil and entitiesById[saved.OwnerEntityId] or nil
   if saved.OwnerEntityId ~= nil and not owner then return false, "Missing collision region owner " .. tostring(saved.OwnerEntityId) end
   local region, factoryError = self.TopologyCatalog:CreateRegion(saved, owner)
   if not region then return false, factoryError end
   if region.Id ~= saved.Id then return false, "Factory changed stable region ID" end
   if expectedType == "Hitbox" then
    if region.Shape == "Box" then region.Size = stateVector(saved.Size) else region.Radius = saved.Radius; region.Size = Vector3.new(saved.Radius * 2, saved.Radius * 2, saved.Radius * 2) end
   else
    if region.Shape == "Box" then region.Size = stateVector(saved.Size) else region.Radius = saved.Radius; region.Size = Vector3.new(saved.Radius * 2, saved.Radius * 2, saved.Radius * 2) end
   end
   region.Position = stateVector(saved.Position)
   region.Rotation = stateCFrame(saved.Rotation)
   region:SetEnabled(saved.Enabled == true)
   if region.PriorityOverride ~= saved.PriorityOverride or (region.Priority or 0) ~= (saved.Priority or 0)
    or region.ClashGroup ~= saved.ClashGroup or region.Hitstun ~= saved.Hitstun
    or region.HitPolicy ~= saved.HitPolicy or region.HitScope ~= saved.HitScope
    or (region.CanHit ~= nil) ~= (saved.HasCanHitCallback == true) then
    return false, "Topology factory behavior mismatch for region " .. tostring(saved.Id)
   end
   -- Damage is validated as serialized scalar/table data by equality where possible.
   if type(region.Damage) ~= type(saved.Damage) then return false, "Topology factory damage type mismatch" end
   targetMap[saved.Id] = region; targetById[saved.Id] = region
  end
  return true
 end
 local ok, reason = buildRegions(state.Hitboxes, "Hitbox", stagedHitboxes, stagedHitboxesById)
 if not ok then return nil, reason end
 ok, reason = buildRegions(state.Hurtboxes, "Hurtbox", stagedHurtboxes, stagedHurtboxesById)
 if not ok then return nil, reason end
 -- Construct each attack with its snapshot ID without consuming the live ID generator.
 for _, saved in ipairs(state.AttackInstances) do
  if type(saved) ~= "table" or stagedAttacksById[saved.Id] or not isDenseArray(saved.HitboxIds) then
   return nil, "Invalid or duplicate AttackInstance record"
  end
  if not validateCustomDataOverrides(saved.CustomDataOverrides) then
   return nil, "Invalid CustomDataOverrides for AttackInstance " .. tostring(saved.Id)
  end
  if not self.AttackCatalog then return nil, "Rebuilding active attacks requires an AttackCatalog" end
  local definition, definitionError = self.AttackCatalog:Resolve(saved.AttackId, saved.DefinitionVersion)
  if not definition then return nil, "Attack definition rejected: " .. tostring(definitionError) end
  local owner = saved.OwnerEntityId ~= nil and entitiesById[saved.OwnerEntityId] or nil
  if saved.OwnerEntityId ~= nil and not owner then return nil, "Missing AttackInstance owner" end
  if saved.State ~= "Created" and saved.State ~= "Active" and saved.State ~= "Finished" then return nil, "Invalid AttackInstance state" end
  local instanceOk, instance = pcall(AttackInstance.new, definition, owner, self.IdGenerator, {
   Id = saved.Id, CustomDataOverrides = saved.CustomDataOverrides,
  })
  if not instanceOk then
   return nil, "Could not rebuild AttackInstance " .. tostring(saved.Id) .. ": " .. tostring(instance)
  end
  instance.State = saved.State
  stagedAttacksById[saved.Id] = instance; table.insert(stagedAttacks, instance)
 end
 local seenMembership = {}
 for _, saved in ipairs(state.AttackInstances) do
  local instance = stagedAttacksById[saved.Id]
  for _, hitboxId in ipairs(saved.HitboxIds) do
   local hitbox = stagedHitboxesById[hitboxId]
   if not hitbox or seenMembership[hitboxId] then return nil, "Invalid or duplicate AttackInstance hitbox membership" end
   seenMembership[hitboxId] = saved.Id
   instance:AddHitbox(hitbox)
  end
 end
 for _, saved in ipairs(state.Hitboxes) do
  if saved.AttackInstanceId ~= nil and seenMembership[saved.Id] ~= saved.AttackInstanceId then
   return nil, "Hitbox-to-AttackInstance membership mismatch"
  end
 end
 -- Rebuild hit history against staged objects; this catches dangling references before commit.
 local historyContext = { RequireReferences = true, AttackInstancesById = stagedAttacksById,
  EntitiesById = entitiesById, HitboxesById = stagedHitboxesById, HurtboxesById = stagedHurtboxesById }
 local historyCommit, historyError = self.HitProcessor.HitHistory:PrepareRollbackRestore(state.HitHistory, historyContext)
 if not historyCommit then return nil, "HitHistory rejected topology rebuild: " .. tostring(historyError) end
 local stagedPairs = {}
 local pairSeen = {}
 for _, pairState in ipairs(state.ActivePairs) do
  local hitbox = stagedHitboxesById[pairState.HitboxId]
  if not hitbox or pairSeen[pairState.HitboxId] then return nil, "Invalid active pair hitbox" end
  pairSeen[pairState.HitboxId] = true
  local targets = {}
  for _, hurtboxId in ipairs(pairState.HurtboxIds) do
   local hurtbox = stagedHurtboxesById[hurtboxId]
   if not hurtbox or targets[hurtbox] then return nil, "Invalid active pair hurtbox" end
   targets[hurtbox] = true
  end
  stagedPairs[hitbox] = targets
 end
 return function()
  -- Commit only swaps internal topology and rollback-owned state; no events are published.
  for _, oldHitbox in pairs(self.Hitboxes) do
   if oldHitbox.AttackInstance then oldHitbox.AttackInstance:RemoveHitbox(oldHitbox) end
  end
  self.Hitboxes, self.Hurtboxes = stagedHitboxes, stagedHurtboxes
  self.ActivePairs = stagedPairs
  historyCommit()
  self.Frame = state.Frame
  self.LastStepDeltaTime = state.LastStepDeltaTime
  self.Results, self.HitEvents = {}, {}
  for _, instance in ipairs(stagedAttacks) do instance._HitHistory = self.HitProcessor.HitHistory end
 end
end

return CollisionWorld
