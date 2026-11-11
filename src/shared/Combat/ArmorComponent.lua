local Component = require(script.Parent.Parent.Core.Component)
local ArmorProfile = require(script.Parent.ArmorProfile)

local ArmorComponent = setmetatable({}, Component)
ArmorComponent.__index = ArmorComponent
ArmorComponent.RollbackKey = "Combat.ArmorComponent"

local function compareIds(a, b)
	if a == b then return 0 end
	if a == nil then return -1 elseif b == nil then return 1 end
	if type(a) == type(b) then return a < b and -1 or 1 end
	return type(a) < type(b) and -1 or 1
end

local function sourceId(source)
	return type(source) == "table" and source.Id or source
end

function ArmorComponent.new(catalog)
	local self = setmetatable(Component.new(), ArmorComponent)
	self.Handles = {}
	self.NextHandleId = 0
	self.Catalog = catalog
	return self
end

function ArmorComponent:Grant(profile, durationFrames, source)
	assert(getmetatable(profile) == ArmorProfile, "ArmorComponent:Grant() expects an ArmorProfile")
	if self.Catalog then
		local registered, version = self.Catalog:Resolve(profile.Id)
		assert(registered == profile and version ~= nil, "Armor profile must be registered in ArmorCatalog")
	end
	if not self.Entity or self.Entity.Destroyed then return nil, "EntityUnavailable" end
	if not self:IsEnabled() then return nil, "Disabled" end
	if durationFrames == nil then durationFrames = profile.DurationFrames end
	if durationFrames ~= nil then
		assert(type(durationFrames) == "number" and durationFrames == durationFrames
			and durationFrames > 0 and durationFrames < math.huge and durationFrames % 1 == 0,
			"Armor duration must be a positive integer or nil for permanent armor")
	end
	self.NextHandleId += 1
	local handle = {
		Id = self.NextHandleId,
		Profile = profile,
		RemainingFrames = durationFrames,
		Priority = profile.Priority,
		Source = source ~= nil and source or profile.Source,
		Active = true,
		CreatedFrame = self.Entity.World and self.Entity.World.CurrentFrame or 0,
	}
	table.insert(self.Handles, handle)
	return handle
end

function ArmorComponent:Remove(handle)
	for index, current in ipairs(self.Handles) do
		if current == handle and current.Active then
			current.Active = false
			table.remove(self.Handles, index)
			return true
		end
	end
	return false
end

function ArmorComponent:GetHandles()
	local handles = {}
	for _, handle in ipairs(self.Handles) do table.insert(handles, handle) end
	return handles
end

function ArmorComponent:ResolveRule(category, hitEvent)
	if not self:IsEnabled() or not self.Entity or self.Entity.Destroyed then return nil end
	local best
	for _, handle in ipairs(self.Handles) do
		local active = handle.Active and (handle.RemainingFrames == nil or handle.RemainingFrames > 0)
		local conditionMatches = active and (handle.Profile.Condition == nil
			or handle.Profile.Condition(hitEvent, category, self.Entity) == true)
		if conditionMatches and handle.Profile.Consequences[category] ~= nil then
			local duration = handle.RemainingFrames or math.huge
			local bestDuration = best and (best.RemainingFrames or math.huge) or -math.huge
			local sourceOrder = best and compareIds(sourceId(handle.Source), sourceId(best.Source)) or -1
			if not best or handle.Priority > best.Priority
				or (handle.Priority == best.Priority and duration > bestDuration)
				or (handle.Priority == best.Priority and duration == bestDuration
					and (compareIds(handle.Profile.Id, best.Profile.Id) < 0
						or (handle.Profile.Id == best.Profile.Id and sourceOrder < 0)))
			then
				best = handle
			end
		end
	end
	return best
end

function ArmorComponent:Resolve(category, hitEvent)
	local rule = self:ResolveRule(category, hitEvent)
	return rule and not rule.Profile:Allows(category) and rule or nil
end

function ArmorComponent:AdvanceStep(frame)
	for index = #self.Handles, 1, -1 do
		local handle = self.Handles[index]
		if handle.RemainingFrames ~= nil
			and (frame == nil or handle.CreatedFrame < frame)
		then
			handle.RemainingFrames -= 1
			if handle.RemainingFrames <= 0 then
				handle.Active = false
				table.remove(self.Handles, index)
			end
		end
	end
end

function ArmorComponent:Destroy()
	for _, handle in ipairs(self.Handles) do handle.Active = false end
	table.clear(self.Handles)
end


local function finite(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function validId(value)
	return (type(value) == "string" and value ~= "")
		or (type(value) == "number" and finite(value) and value % 1 == 0)
end

local function encodeSource(source)
	if source == nil then return { Kind = "None" } end
	if type(source) == "table" then
		local id = source.Id
		assert(validId(id), "Armor source entities must expose a stable string/integer Id")
		return { Kind = "Entity", Id = id }
	end
	assert(validId(source), "Armor source must be nil, a stable entity reference, or a string/integer ID")
	return { Kind = "Value", Value = source }
end

function ArmorComponent:CaptureRollbackState()
	assert(self.Catalog and self.Catalog.Sealed, "ArmorComponent rollback requires a sealed ArmorCatalog")
	local handles = {}
	for _, handle in ipairs(self.Handles) do
		assert(handle.Active == true, "ArmorComponent contains an inactive handle")
		local profile, version = self.Catalog:Resolve(handle.Profile.Id)
		assert(profile == handle.Profile and version ~= nil, "Armor handle profile is not registered")
		table.insert(handles, {
			Id = handle.Id, ProfileId = profile.Id, ProfileVersion = version,
			RemainingFrames = handle.RemainingFrames, Priority = handle.Priority,
			Source = encodeSource(handle.Source), CreatedFrame = handle.CreatedFrame,
		})
	end
	table.sort(handles, function(a, b) return a.Id < b.Id end)
	return {
		Version = 1, NextHandleId = self.NextHandleId,
		CatalogManifest = self.Catalog:CaptureManifest(), Handles = handles,
	}
end

function ArmorComponent:ValidateRollbackState(state, context)
	if not self.Catalog or not self.Catalog.Sealed then return false, "ArmorComponent requires a sealed ArmorCatalog" end
	if type(state) ~= "table" or getmetatable(state) ~= nil or state.Version ~= 1 then
		return false, "Invalid ArmorComponent state version"
	end
	if not finite(state.NextHandleId) or state.NextHandleId < 0 or state.NextHandleId % 1 ~= 0 then
		return false, "NextHandleId must be a non-negative integer"
	end
	local manifestOk, manifestError = self.Catalog:ValidateManifest(state.CatalogManifest)
	if not manifestOk then return false, manifestError end
	if type(state.Handles) ~= "table" or getmetatable(state.Handles) ~= nil then return false, "Handles must be a plain array" end
	local count, maxIndex, seen, previousId = 0, 0, {}, 0
	for key in pairs(state.Handles) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false, "Handles must be a dense array" end
		count += 1; if key > maxIndex then maxIndex = key end
	end
	if count ~= maxIndex then return false, "Handles must be a dense array" end
	for _, handle in ipairs(state.Handles) do
		if type(handle) ~= "table" or getmetatable(handle) ~= nil
			or not finite(handle.Id) or handle.Id <= previousId or handle.Id % 1 ~= 0 then
			return false, "Invalid or non-canonical armor handle ID"
		end
		previousId = handle.Id
		if seen[handle.Id] then return false, "Duplicate armor handle ID" end
		seen[handle.Id] = true
		if handle.Id > state.NextHandleId then return false, "Armor handle ID exceeds NextHandleId" end
		local profile, reason = self.Catalog:Resolve(handle.ProfileId, handle.ProfileVersion)
		if not profile then return false, reason end
		if not finite(handle.Priority) or handle.Priority ~= profile.Priority then return false, "Armor handle priority differs from profile" end
		if handle.RemainingFrames ~= nil and (not finite(handle.RemainingFrames) or handle.RemainingFrames < 0 or handle.RemainingFrames % 1 ~= 0) then
			return false, "Invalid armor remaining duration"
		end
		if not finite(handle.CreatedFrame) or handle.CreatedFrame < 0 or handle.CreatedFrame % 1 ~= 0 then
			return false, "Invalid armor CreatedFrame"
		end
		local source = handle.Source
		if type(source) ~= "table" or getmetatable(source) ~= nil then return false, "Invalid armor source descriptor" end
		if source.Kind == "Entity" then
			if not validId(source.Id) then return false, "Invalid armor source entity ID" end
			if context and context.EntitiesById and not context.EntitiesById[source.Id] then
				return false, "Armor source entity is absent: " .. tostring(source.Id)
			end
		elseif source.Kind == "Value" then
			if not validId(source.Value) then return false, "Invalid armor source value" end
		elseif source.Kind ~= "None" then return false, "Unknown armor source descriptor kind" end
	end
	return true
end

function ArmorComponent:RestoreRollbackState(state, context)
	local valid, reason = self:ValidateRollbackState(state, context)
	if not valid then return false, reason end
	local handles = {}
	for _, saved in ipairs(state.Handles) do
		local profile = assert(self.Catalog:Resolve(saved.ProfileId, saved.ProfileVersion))
		local source
		if saved.Source.Kind == "Entity" then
			source = context and context.EntitiesById and context.EntitiesById[saved.Source.Id]
			if not source then return false, "Cannot resolve armor source entity: " .. tostring(saved.Source.Id) end
		elseif saved.Source.Kind == "Value" then source = saved.Source.Value end
		table.insert(handles, {
			Id = saved.Id, Profile = profile, RemainingFrames = saved.RemainingFrames,
			Priority = saved.Priority, Source = source, Active = true, CreatedFrame = saved.CreatedFrame,
		})
	end
	self.Handles = handles
	self.NextHandleId = state.NextHandleId
	return true
end

return ArmorComponent
