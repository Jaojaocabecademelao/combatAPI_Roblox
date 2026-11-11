local Component = require(script.Parent.Parent.Core.Component)
local EntityState = require(script.Parent.Parent.Core.EntityState)
local Protection = require(script.Parent.Protection)

local ProtectionComponent = setmetatable({}, Component)
ProtectionComponent.__index = ProtectionComponent
ProtectionComponent.RollbackKey = "Combat.ProtectionComponent"

local function compareIds(a, b)
	if a == b then return 0 end
	if a == nil then return -1 elseif b == nil then return 1 end
	if type(a) == type(b) then return a < b and -1 or 1 end
	return type(a) < type(b) and -1 or 1
end

local function sourceId(source)
	return type(source) == "table" and source.Id or source
end

function ProtectionComponent.new()
	local self = setmetatable(Component.new(), ProtectionComponent)
	self.Protections = {}
	return self
end

function ProtectionComponent:Add(protection)
	assert(getmetatable(protection) == Protection, "ProtectionComponent:Add() expects a Protection")
	assert(self.Entity ~= nil and not self.Entity.Destroyed, "ProtectionComponent must be attached")
	protection.Target = self.Entity
	protection.Active = true
	if self.Entity.World then protection.Frame = self.Entity.World.CurrentFrame or protection.Frame end
	protection.LastAdvancedFrame = protection.Frame or 0
	table.insert(self.Protections, protection)
	return protection, "Added"
end

function ProtectionComponent:Grant(options)
	assert(type(options) == "table", "ProtectionComponent:Grant() expects options")
	local normalized = {}
	for key, value in pairs(options) do normalized[key] = value end
	normalized.Target = self.Entity
	if normalized.Frame == nil and self.Entity.World then
		normalized.Frame = self.Entity.World.CurrentFrame or 0
	end
	return self:Add(Protection.new(normalized))
end

function ProtectionComponent:Remove(protection)
	for index, current in ipairs(self.Protections) do
		if current == protection then
			current.Active = false
			table.remove(self.Protections, index)
			return true
		end
	end
	return false
end

function ProtectionComponent:Resolve(category)
	if not self:IsEnabled() or not self.Entity or self.Entity.Destroyed then return nil end
	if type(self.Entity.GetState) == "function" and self.Entity:GetState() == EntityState.Dead then return nil end
	local best
	for _, protection in ipairs(self.Protections) do
		if protection.Active and protection:Blocks(category) then
			if not best or protection.Priority > best.Priority
				or (protection.Priority == best.Priority
					and (protection.RemainingFrames or math.huge) > (best.RemainingFrames or math.huge))
			or (protection.Priority == best.Priority
				and protection.RemainingFrames == best.RemainingFrames
				and (compareIds(sourceId(protection.Source), sourceId(best.Source)) < 0
					or (sourceId(protection.Source) == sourceId(best.Source)
						and protection.Kind < best.Kind)))
			then best = protection end
		end
	end
	return best
end

function ProtectionComponent:AdvanceFrame(frame)
	for index = #self.Protections, 1, -1 do
		local protection = self.Protections[index]
		if not protection.Permanent and protection.RemainingFrames ~= nil then
			local lastFrame = protection.LastAdvancedFrame or protection.Frame or 0
			local targetFrame = math.max(lastFrame, frame or (lastFrame + 1))
			local steps = math.max(0, targetFrame - lastFrame)
			for _ = 1, steps do
				protection:AdvanceFrame()
				if protection:IsExpired() then break end
			end
			protection.LastAdvancedFrame = targetFrame
			if protection:IsExpired() then table.remove(self.Protections, index) end
		end
	end
	return self
end

function ProtectionComponent:GetProtections()
	local result = {}
	for _, protection in ipairs(self.Protections) do table.insert(result, protection) end
	return result
end

function ProtectionComponent:GetActiveProtections()
	local result = {}
	for _, protection in ipairs(self.Protections) do
		if protection.Active and not protection:IsExpired() then table.insert(result, protection) end
	end
	return result
end

function ProtectionComponent:Destroy()
	for _, protection in ipairs(self.Protections) do protection.Active = false end
	table.clear(self.Protections)
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
		assert(validId(id), "Protection source entities must expose a stable string/integer Id")
		return { Kind = "Entity", Id = id }
	end
	assert(validId(source), "Protection source must be nil, an entity reference, or a string/integer ID")
	return { Kind = "Value", Value = source }
end

function ProtectionComponent:CaptureRollbackState()
	local protections = {}
	for _, protection in ipairs(self.Protections) do
		local categories = {}
		for index, category in ipairs(protection.Categories) do categories[index] = category end
		table.insert(protections, {
			Kind = protection.Kind, Categories = categories, Source = encodeSource(protection.Source),
			Priority = protection.Priority, Permanent = protection.Permanent,
			DurationFrames = protection.DurationFrames, RemainingFrames = protection.RemainingFrames,
			StartFrame = protection.StartFrame, Frame = protection.Frame, CreatedAt = protection.CreatedAt,
			LastAdvancedFrame = protection.LastAdvancedFrame, Active = protection.Active,
		})
	end
	return { Version = 1, Protections = protections }
end

function ProtectionComponent:ValidateRollbackState(state, context)
	if type(state) ~= "table" or getmetatable(state) ~= nil or state.Version ~= 1 then
		return false, "Invalid ProtectionComponent state version"
	end
	if type(state.Protections) ~= "table" or getmetatable(state.Protections) ~= nil then
		return false, "Protections must be a plain array"
	end
	local count, maxIndex = 0, 0
	for key in pairs(state.Protections) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false, "Protections must be a dense array" end
		count += 1; if key > maxIndex then maxIndex = key end
	end
	if count ~= maxIndex then return false, "Protections must be a dense array" end
	for _, item in ipairs(state.Protections) do
		if type(item) ~= "table" or getmetatable(item) ~= nil then return false, "Invalid protection entry" end
		if item.Kind ~= "Invulnerability" and item.Kind ~= "Immunity" then return false, "Invalid protection kind" end
		if type(item.Categories) ~= "table" or getmetatable(item.Categories) ~= nil or #item.Categories == 0 then
			return false, "Protection categories must be a non-empty array"
		end
		local categoryCount, categoryMax = 0, 0
		for key in pairs(item.Categories) do
			if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false, "Protection categories must be a dense array" end
			categoryCount += 1; if key > categoryMax then categoryMax = key end
		end
		if categoryCount ~= categoryMax then return false, "Protection categories must be a dense array" end
		for _, category in ipairs(item.Categories) do
			if type(category) ~= "string" or category == "" then return false, "Invalid protection category" end
		end
		if not finite(item.Priority) then return false, "Protection priority must be finite" end
		if type(item.Permanent) ~= "boolean" or type(item.Active) ~= "boolean" then return false, "Protection flags must be boolean" end
		for _, key in ipairs({ "DurationFrames", "RemainingFrames", "StartFrame", "Frame", "CreatedAt", "LastAdvancedFrame" }) do
			local value = item[key]
			if value ~= nil and (not finite(value) or value < 0 or value % 1 ~= 0) then return false, key .. " must be a non-negative frame or nil" end
		end
		if item.Permanent and (item.DurationFrames ~= nil or item.RemainingFrames ~= nil) then
			return false, "Permanent protection cannot have a duration"
		end
		if not item.Permanent and item.RemainingFrames ~= nil and item.DurationFrames == nil then
			return false, "Remaining duration requires an original duration"
		end
		if not item.Permanent and item.RemainingFrames ~= nil and item.DurationFrames ~= nil
			and item.RemainingFrames > item.DurationFrames then return false, "Remaining protection duration exceeds original duration" end
		for _, requiredFrame in ipairs({ "StartFrame", "Frame", "CreatedAt", "LastAdvancedFrame" }) do
			if not finite(item[requiredFrame]) or item[requiredFrame] < 0 or item[requiredFrame] % 1 ~= 0 then
				return false, requiredFrame .. " must be present as a non-negative integer frame"
			end
		end
		if item.Active == false then return false, "Inactive protections must not remain in the component list" end
		local source = item.Source
		if type(source) ~= "table" or getmetatable(source) ~= nil then return false, "Invalid protection source descriptor" end
		if source.Kind == "Entity" then
			if not validId(source.Id) then return false, "Invalid protection source entity ID" end
			if context and context.EntitiesById and not context.EntitiesById[source.Id] then
				return false, "Protection source entity is absent: " .. tostring(source.Id)
			end
		elseif source.Kind == "Value" then
			if not validId(source.Value) then return false, "Invalid protection source value" end
		elseif source.Kind ~= "None" then return false, "Unknown protection source descriptor kind" end
	end
	return true
end

function ProtectionComponent:RestoreRollbackState(state, context)
	local valid, reason = self:ValidateRollbackState(state, context)
	if not valid then return false, reason end
	local rebuilt = {}
	for _, item in ipairs(state.Protections) do
		local source
		if item.Source.Kind == "Entity" then
			source = context and context.EntitiesById and context.EntitiesById[item.Source.Id]
			if not source then return false, "Cannot resolve protection source entity: " .. tostring(item.Source.Id) end
		elseif item.Source.Kind == "Value" then source = item.Source.Value end
		local protection = Protection.new({
			Kind = item.Kind, Categories = item.Categories, Target = self.Entity, Source = source,
			Priority = item.Priority, Permanent = item.Permanent, DurationFrames = item.DurationFrames,
			StartFrame = item.StartFrame, Frame = item.Frame, CreatedAt = item.CreatedAt,
		})
		protection.RemainingFrames = item.RemainingFrames
		protection.LastAdvancedFrame = item.LastAdvancedFrame
		protection.Active = item.Active
		table.insert(rebuilt, protection)
	end
	self.Protections = rebuilt
	return true
end

return ProtectionComponent
