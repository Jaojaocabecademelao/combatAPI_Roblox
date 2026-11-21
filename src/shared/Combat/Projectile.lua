local Serializer = require(script.Parent.Parent.Simulation.StateSerializer)

local Projectile = {}
Projectile.__index = Projectile
Projectile.Version = 1
Projectile.ContactPolicy = table.freeze({
	Stop = "Stop",
	Reflect = "Reflect",
	PassThrough = "PassThrough",
	Destroy = "Destroy",
})

local function finite(value)
	return type(value) == "number" and value == value
		and value > -math.huge and value < math.huge
end

local function cloneVector(value, name)
	assert(typeof(value) == "Vector3", name .. " must be a Vector3")
	assert(finite(value.X) and finite(value.Y) and finite(value.Z),
		name .. " must contain finite components")
	return value
end

function Projectile.new(options)
	options = options or {}
	assert(type(options) == "table", "Projectile.new expects an options table")
	local position = cloneVector(options.Position or Vector3.zero, "Projectile Position")
	local velocity = cloneVector(options.Velocity or Vector3.zero, "Projectile Velocity")
	local acceleration = cloneVector(options.Acceleration or Vector3.zero, "Projectile Acceleration")
	local lifetimeFrames = options.LifetimeFrames
	if lifetimeFrames == nil then lifetimeFrames = 0 end
	assert(type(lifetimeFrames) == "number" and lifetimeFrames >= 0
		and lifetimeFrames % 1 == 0, "Projectile LifetimeFrames must be a non-negative integer")
	local maxSpeed = options.MaxSpeed
	if maxSpeed == nil then maxSpeed = math.huge end
	assert(maxSpeed == math.huge or (finite(maxSpeed) and maxSpeed >= 0),
		"Projectile MaxSpeed must be finite and non-negative or nil")
	local drag = options.Drag
	if drag == nil then drag = 0 end
	assert(finite(drag) and drag >= 0, "Projectile Drag must be finite and non-negative")
	local policy = options.ContactPolicy or Projectile.ContactPolicy.PassThrough
	assert(policy == Projectile.ContactPolicy.Stop
		or policy == Projectile.ContactPolicy.Reflect
		or policy == Projectile.ContactPolicy.PassThrough
		or policy == Projectile.ContactPolicy.Destroy,
		"Projectile ContactPolicy is invalid")
	return setmetatable({
		Id = options.Id,
		OwnerEntityId = options.OwnerEntityId,
		Position = position,
		Velocity = velocity,
		Acceleration = acceleration,
		MaxSpeed = maxSpeed,
		Drag = drag,
		LifetimeFrames = lifetimeFrames,
		ElapsedFrames = 0,
		ContactPolicy = policy,
		Alive = true,
		LastContact = nil,
	}, Projectile)
end

function Projectile:Step(deltaFrames)
	if not self.Alive then return self end
	deltaFrames = deltaFrames or 1
	assert(type(deltaFrames) == "number" and deltaFrames >= 0
		and deltaFrames % 1 == 0, "Projectile Step frames must be a non-negative integer")
	local dragFactor = math.max(0, 1 - self.Drag * deltaFrames)
	local nextVelocity = (self.Velocity + self.Acceleration * deltaFrames) * dragFactor
	if nextVelocity.Magnitude > self.MaxSpeed then
		if nextVelocity.Magnitude > 0 then
			nextVelocity = nextVelocity.Unit * self.MaxSpeed
		end
	end
	self.Velocity = Vector3.new(nextVelocity.X, nextVelocity.Y, nextVelocity.Z)
	self.Position = self.Position + self.Velocity * deltaFrames
	self.ElapsedFrames += deltaFrames
	if self.LifetimeFrames > 0 and self.ElapsedFrames >= self.LifetimeFrames then
		self.Alive = false
	end
	return self
end

function Projectile:ResolveContact(contact)
	assert(contact == nil or type(contact) == "table", "Projectile contact must be a table or nil")
	if not self.Alive or contact == nil then return "NoContact" end
	local serializableContact = {}
	for key, value in pairs(contact) do
		if typeof(value) == "Vector3" then
			serializableContact[key] = { X = value.X, Y = value.Y, Z = value.Z }
		elseif type(value) ~= "userdata" and type(value) ~= "function" then
			local cloned = Serializer.CloneSerializable({ value })
			serializableContact[key] = cloned[1]
		end
	end
	local clonedContact = Serializer.CloneSerializable(serializableContact)
	self.LastContact = Serializer.Freeze(clonedContact)
	if self.ContactPolicy == Projectile.ContactPolicy.Stop then
		self.Velocity = Vector3.zero
	elseif self.ContactPolicy == Projectile.ContactPolicy.Destroy then
		self.Alive = false
	elseif self.ContactPolicy == Projectile.ContactPolicy.Reflect then
		local normal = contact.Normal
		if typeof(normal) == "Vector3" and normal.Magnitude > 0 then
			local unit = normal.Unit
			self.Velocity = self.Velocity - unit * (2 * self.Velocity:Dot(unit))
		end
	elseif self.ContactPolicy == Projectile.ContactPolicy.PassThrough then
		return "PassThrough"
	end
	return self.ContactPolicy
end

function Projectile:Capture()
	return Serializer.Freeze({
		Version = Projectile.Version,
		Id = self.Id,
		OwnerEntityId = self.OwnerEntityId,
		Position = { self.Position.X, self.Position.Y, self.Position.Z },
		Velocity = { self.Velocity.X, self.Velocity.Y, self.Velocity.Z },
		Acceleration = { self.Acceleration.X, self.Acceleration.Y, self.Acceleration.Z },
		MaxSpeed = self.MaxSpeed,
		Drag = self.Drag,
		LifetimeFrames = self.LifetimeFrames,
		ElapsedFrames = self.ElapsedFrames,
		ContactPolicy = self.ContactPolicy,
		Alive = self.Alive,
		LastContact = self.LastContact,
	})
end

function Projectile:Restore(state)
	assert(type(state) == "table" and state.Version == Projectile.Version,
		"Unsupported Projectile snapshot")
	local function vector(saved)
		assert(type(saved) == "table" and #saved == 3, "Projectile vector snapshot is invalid")
		return Vector3.new(saved[1], saved[2], saved[3])
	end
	self.Position = vector(state.Position)
	self.Velocity = vector(state.Velocity)
	self.Acceleration = vector(state.Acceleration)
	self.MaxSpeed = state.MaxSpeed
	self.Drag = state.Drag
	self.LifetimeFrames = state.LifetimeFrames
	self.ElapsedFrames = state.ElapsedFrames
	self.ContactPolicy = state.ContactPolicy
	self.Alive = state.Alive
	self.LastContact = state.LastContact
	return self
end

return Projectile
