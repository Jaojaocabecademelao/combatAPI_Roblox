local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local CombatAPI = require(Shared.CombatAPI)
local Simulation = require(Shared.Simulation.Simulation)
local Hitbox = require(Shared.Combat.Hitbox)
local Hurtbox = require(Shared.Combat.Hurtbox)
local CollisionQuery = require(Shared.Combat.CollisionQuery)

-- This example separates the authoritative combat simulation from the Roblox
-- world query used for environment interaction.
--
-- Important: Workspace:Spherecast / GetPartBoundsInBox are only external inputs.
-- They do not make the combat result deterministic or replay-safe unless the
-- game records them for the matching simulation frame and reuses the captured
-- result during rollback.

local world = CombatAPI.CreateWorld()
local simulation = Simulation.new(world, { Seed = 17 })

local projectile = {
	Position = Vector3.new(0, 5, 0),
	Velocity = Vector3.new(20, 0, 0),
	Radius = 0.5,
	Lifetime = 5,
	Hitbox = Hitbox.new({
		Shape = "Sphere",
		Position = Vector3.new(0, 5, 0),
		Radius = 0.5,
		Owner = nil,
	}),
	Visual = Instance.new("Part"),
	Alive = true,
}

projectile.Visual.Shape = Enum.PartType.Ball
projectile.Visual.Size = Vector3.new(projectile.Radius * 2, projectile.Radius * 2, projectile.Radius * 2)
projectile.Visual.Anchored = true
projectile.Visual.Material = Enum.Material.Neon
projectile.Visual.Color = Color3.fromRGB(255, 128, 0)
projectile.Visual.Parent = Workspace
projectile.Visual.CFrame = CFrame.new(projectile.Position)

local target = Hurtbox.new({
	Shape = "Box",
	Position = Vector3.new(12, 5, 0),
	Size = Vector3.new(2, 2, 2),
	Owner = nil,
})

local function queryEnvironment(position, radius)
	local origin = position
	local direction = Vector3.zero
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace }
	return Workspace:Spherecast(origin, radius, direction, params)
end

local function updateVisual(position)
	projectile.Visual.CFrame = CFrame.new(position)
end

local function advanceProjectiles(dt)
	if not projectile.Alive then
		return
	end

	projectile.Lifetime -= dt
	projectile.Position = projectile.Position + projectile.Velocity * dt
	projectile.Hitbox.Position = projectile.Position
	updateVisual(projectile.Position)

	local environmentHit = queryEnvironment(projectile.Position, projectile.Radius)
	if environmentHit then
		projectile.Velocity = projectile.Velocity * Vector3.new(-0.7, 1, 0.6)
		projectile.Position = environmentHit.Position + environmentHit.Normal * (projectile.Radius + 0.05)
		projectile.Hitbox.Position = projectile.Position
		updateVisual(projectile.Position)
	end

	local contact = CollisionQuery.Intersects(projectile.Hitbox, target)
	if contact then
		projectile.Alive = false
		projectile.Visual:Destroy()
		print("Projectile hit authoritative hurtbox; combat resolution remains in CombatAPI")
	end
end

-- The gameplay state remains authoritative in CombatAPI while the Roblox object
-- is only a visual representation of that same frame.
for frame = 1, 30 do
	simulation:Step()
	advanceProjectiles(1 / 60)
	if not projectile.Alive then
		break
	end
end

if projectile.Visual and projectile.Visual.Parent then
	projectile.Visual:Destroy()
end
world:Destroy()
