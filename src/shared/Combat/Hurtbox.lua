local Component = require(script.Parent.Parent.Core.Component)

local Hurtbox = {}
Hurtbox.__index = Hurtbox
setmetatable(Hurtbox, { __index = Component })

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
		"Hurtbox Position must be a finite Vector3")

	local rotation = options.Rotation or options.Orientation or CFrame.new()
	if typeof(rotation) == "Vector3" then
		rotation = CFrame.fromOrientation(rotation.X, rotation.Y, rotation.Z)
	end
	assert(typeof(rotation) == "CFrame", "Hurtbox Rotation must be a CFrame or Vector3 orientation")
	return position, rotation - rotation.Position
end

function Hurtbox.new(options)
	options = options or {}
	assert(type(options) == "table", "Hurtbox.new() expects an options table or nil")

	local shape = options.Shape or "Box"
	assert(shape == "Box" or shape == "Sphere", "Hurtbox Shape must be Box or Sphere")
	local position, rotation = resolveTransform(options)

	local self = Component.new()
	local id = options.Id
	if id == nil and options.IdGenerator then
		assert(type(options.IdGenerator.Next) == "function",
			"Hurtbox IdGenerator must implement Next()")
		id = options.IdGenerator:Next()
	end
	assert(id == nil or (isFiniteNumber(id) and id % 1 == 0), "Hurtbox Id must be a finite integer")
	self.Id = id
	self.CombatRegionType = "Hurtbox"
	self.TopologyDefinitionId = options.TopologyDefinitionId
	self.TopologyDefinitionVersion = options.TopologyDefinitionVersion
	assert(self.TopologyDefinitionId == nil or (type(self.TopologyDefinitionId) == "string" and self.TopologyDefinitionId ~= ""), "Hurtbox TopologyDefinitionId must be a non-empty string or nil")
	assert(self.TopologyDefinitionVersion == nil or ((type(self.TopologyDefinitionVersion) == "string" and self.TopologyDefinitionVersion ~= "") or (type(self.TopologyDefinitionVersion) == "number" and self.TopologyDefinitionVersion >= 0 and self.TopologyDefinitionVersion % 1 == 0)), "Hurtbox TopologyDefinitionVersion must be a non-negative integer or non-empty string")
	self.Shape = shape
	self.Position = position
	self.Rotation = rotation
	self.Owner = options.Owner
	self.Enabled = options.Enabled ~= false

	if shape == "Box" then
		local size = options.Size
		assert(typeof(size) == "Vector3"
			and isFiniteNumber(size.X) and isFiniteNumber(size.Y) and isFiniteNumber(size.Z)
			and size.X > 0 and size.Y > 0 and size.Z > 0,
			"Box Hurtbox requires a positive Vector3 Size")
		self.Size = size
	else
		local radius = options.Radius
		assert(isFiniteNumber(radius) and radius >= 0,
			"Sphere Hurtbox requires a finite non-negative Radius")
		self.Radius = radius
		self.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	end

	return setmetatable(self, Hurtbox)
end

function Hurtbox:Attach(entity)
	Component.Attach(self, entity)
	if self.Id == nil and entity.World then
		self.Id = entity.World.IdGenerator:Next()
	end
	if self.Owner == nil then
		self.Owner = entity
	end

	local world = entity.World
	if world and world.CollisionWorld then
		world.CollisionWorld:RegisterHurtbox(self)
	end

	return self
end

function Hurtbox:Destroy()
	local entity = self.Entity
	local world = entity and entity.World
	if world and world.CollisionWorld then
		world.CollisionWorld:RemoveHurtbox(self)
	end

	if self.Owner == entity then
		self.Owner = nil
	end
end

return Hurtbox
