local Component = require(script.Parent.Parent.Core.Component)
local HitPolicy = require(script.Parent.HitPolicy)

local Hitbox = {}
Hitbox.__index = Hitbox
setmetatable(Hitbox, { __index = Component })

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

local function resolveTransform(options)
	local position = options.Position or Vector3.new(0, 0, 0)
	assert(typeof(position) == "Vector3"
		and isFiniteNumber(position.X) and isFiniteNumber(position.Y) and isFiniteNumber(position.Z),
		"Hitbox Position must be a finite Vector3")

	local rotation = options.Rotation or options.Orientation or CFrame.new()
	if typeof(rotation) == "Vector3" then
		rotation = CFrame.fromOrientation(rotation.X, rotation.Y, rotation.Z)
	end
	assert(typeof(rotation) == "CFrame", "Hitbox Rotation must be a CFrame or Vector3 orientation")
	return position, rotation - rotation.Position
end

function Hitbox.new(options)
	options = options or {}
	assert(type(options) == "table", "Hitbox.new() expects an options table or nil")

	local shape = options.Shape or "Box"
	assert(shape == "Box" or shape == "Sphere", "Hitbox Shape must be Box or Sphere")
	local position, rotation = resolveTransform(options)

	local self = Component.new()
	local id = options.Id
	if id == nil and options.IdGenerator then
		assert(type(options.IdGenerator.Next) == "function",
			"Hitbox IdGenerator must implement Next()")
		id = options.IdGenerator:Next()
	end
	assert(id == nil or (isFiniteNumber(id) and id % 1 == 0), "Hitbox Id must be a finite integer")
	self.Id = id
	self.CombatRegionType = "Hitbox"
	self.TopologyDefinitionId = options.TopologyDefinitionId
	self.TopologyDefinitionVersion = options.TopologyDefinitionVersion
	assert(self.TopologyDefinitionId == nil or (type(self.TopologyDefinitionId) == "string" and self.TopologyDefinitionId ~= ""), "Hitbox TopologyDefinitionId must be a non-empty string or nil")
	assert(self.TopologyDefinitionVersion == nil or ((type(self.TopologyDefinitionVersion) == "string" and self.TopologyDefinitionVersion ~= "") or (type(self.TopologyDefinitionVersion) == "number" and self.TopologyDefinitionVersion >= 0 and self.TopologyDefinitionVersion % 1 == 0)), "Hitbox TopologyDefinitionVersion must be a non-negative integer or non-empty string")
	self.Shape = shape
	self.Position = position
	self.Rotation = rotation
	self.Owner = options.Owner
	self.Enabled = options.Enabled ~= false
	self.AttackId = options.AttackId
	self.PriorityOverride = options.Priority
	if self.PriorityOverride ~= nil then
		assert(isFiniteNumber(self.PriorityOverride), "Hitbox Priority must be a finite number")
	end
	self.Priority = self.PriorityOverride or 0
	self.ClashGroup = options.ClashGroup
	self.Damage = options.Damage
	self.Hitstun = options.Hitstun
	assert(self.Hitstun == nil or (isFiniteNumber(self.Hitstun) and self.Hitstun >= 0
		and self.Hitstun % 1 == 0),
		"Hitbox Hitstun must be a non-negative finite integer number of frames or nil")
	self.AttackInstance = nil
	self.HitPolicy = options.HitPolicy
	if self.HitPolicy ~= nil then
		HitPolicy.Validate(self.HitPolicy)
	end
	self.HitScope = options.HitScope
	if self.HitScope ~= nil then
		HitPolicy.ValidateScope(self.HitScope)
	end
	self.CanHit = options.CanHit
	assert(self.CanHit == nil or type(self.CanHit) == "function",
		"Hitbox CanHit must be a function or nil")

	if shape == "Box" then
		local size = options.Size
		assert(typeof(size) == "Vector3"
			and isFiniteNumber(size.X) and isFiniteNumber(size.Y) and isFiniteNumber(size.Z)
			and size.X > 0 and size.Y > 0 and size.Z > 0,
			"Box Hitbox requires a positive Vector3 Size")
		self.Size = size
	else
		local radius = options.Radius
		assert(isFiniteNumber(radius) and radius >= 0,
			"Sphere Hitbox requires a finite non-negative Radius")
		self.Radius = radius
		self.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	end

	return setmetatable(self, Hitbox)
end

function Hitbox:Attach(entity)
	Component.Attach(self, entity)
	if self.Id == nil and entity.World then
		self.Id = entity.World.IdGenerator:Next()
	end
	if self.Owner == nil then
		self.Owner = entity
	end

	local world = entity.World
	if world and world.CollisionWorld then
		world.CollisionWorld:RegisterHitbox(self)
	end

	return self
end

function Hitbox:Destroy()
	local entity = self.Entity
	local world = entity and entity.World
	if self.AttackInstance then
		local instance = self.AttackInstance
		if instance.OwnerEntity == entity and world and not world:HasEntity(entity) then
			instance:Finish()
		else
			instance:RemoveHitbox(self)
		end
	end
	if world and world.CollisionWorld then
		world.CollisionWorld:RemoveHitbox(self)
	end

	if self.Owner == entity then
		self.Owner = nil
	end
end

return Hitbox
