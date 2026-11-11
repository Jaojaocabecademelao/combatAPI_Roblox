return function()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")

local Component = require(Core.Component)
local World = require(Core.World)

local TestComponent = {}
TestComponent.__index = TestComponent
setmetatable(TestComponent, { __index = Component })

function TestComponent.new()
	local self = Component.new()
	self.UpdateCount = 0
	self.StepCount = 0
	return setmetatable(self, TestComponent)
end

function TestComponent:Attach(entity)
	self.AttachCalled = true
	self.ReceivedEntity = entity
	return Component.Attach(self, entity)
end

function TestComponent:Detach()
	self.DetachCalled = true
	return Component.Detach(self)
end

function TestComponent:Destroy()
	self.DestroyCalled = true
end

function TestComponent:Update(deltaTime)
	self.UpdateCount += 1
	self.LastUpdateDeltaTime = deltaTime
end

function TestComponent:Step(deltaTime)
	self.StepCount += 1
	self.LastStepDeltaTime = deltaTime
end

local world = World.new()
assert(world, "World.new() should create a world")

local kaelus = world:CreateEntity()
local projectile = world:CreateEntity()

assert(kaelus.Id ~= projectile.Id, "World should assign different IDs")
assert(world:HasEntity(kaelus), "Created entity should be registered")
assert(world:HasEntity(projectile), "Created entity should be registered")
assert(world:GetEntity(kaelus.Id) == kaelus, "GetEntity() should return the entity by ID")

local destroyedComponents = 0
local function addDestroyTracker(entity)
	local component = Component.new()
	function component:Destroy()
		destroyedComponents += 1
	end
	entity:AddComponent(component)
end

addDestroyTracker(kaelus)
addDestroyTracker(projectile)

assert(world:DestroyEntity(kaelus), "DestroyEntity() should destroy a registered entity")
assert(not world:HasEntity(kaelus), "Destroyed entity should be unregistered")
assert(kaelus.Destroyed, "DestroyEntity() should call entity:Destroy()")
assert(destroyedComponents == 1, "Destroy() should detach and destroy components")
assert(not world:DestroyEntity(kaelus), "Repeated destruction should be safe")

assert(world:DestroyEntity(projectile.Id), "DestroyEntity() should accept an ID")
assert(not world:HasEntity(projectile.Id), "Entity destroyed by ID should be unregistered")
assert(projectile.Destroyed, "Destroy by ID should call entity:Destroy()")
assert(destroyedComponents == 2, "Destroy by ID should destroy attached components")

local thirdEntity = world:CreateEntity()
local fourthEntity = world:CreateEntity()
addDestroyTracker(thirdEntity)
addDestroyTracker(fourthEntity)

local entities = world:GetEntities()
assert(#entities == 2, "GetEntities() should return all registered entities")

world:Clear()
assert(#world:GetEntities() == 0, "Clear() should remove every entity")
assert(thirdEntity.Destroyed and fourthEntity.Destroyed, "Clear() should destroy every entity")
assert(destroyedComponents == 4, "Clear() should destroy attached components")

local generatedIds = 0
local customGenerator = {
	Next = function()
		generatedIds += 1
		return 100 + generatedIds
	end,
}
local customWorld = World.new({ IdGenerator = customGenerator })
local customEntity = customWorld:CreateEntity()

assert(customEntity.Id == 101, "World should use the supplied IdGenerator")
assert(generatedIds == 1, "World should request an ID from the supplied generator")

local componentEntity = world:CreateEntity()
local component = componentEntity:AddComponent(TestComponent.new())

assert(component.AttachCalled, "AddComponent() should call Attach()")
assert(component.ReceivedEntity == componentEntity, "Attach() should receive the owning entity")
assert(component.Entity == componentEntity, "Component should reference its entity")
assert(componentEntity:GetComponent(TestComponent) == component, "Entity should return its component by type")
assert(component.Enabled == true and component:IsEnabled(), "Component should be enabled by default")

component:SetEnabled(false)
assert(not component:IsEnabled(), "SetEnabled(false) should disable the component")

assert(componentEntity:RemoveComponent(TestComponent), "Entity should remove its component by type")
assert(component.DetachCalled, "RemoveComponent() should call Detach()")
assert(componentEntity:GetComponent(TestComponent) == nil, "Removed component should no longer be returned")
assert(component.Entity == nil, "Removed component should no longer reference its entity")

local destroyedEntity = world:CreateEntity()
local destroyedEntityId = destroyedEntity.Id
local destroyedComponent = destroyedEntity:AddComponent(TestComponent.new())

assert(world:DestroyEntity(destroyedEntity), "World should destroy an entity with a component")
assert(destroyedComponent.DestroyCalled, "Entity destruction should call Component:Destroy()")
assert(destroyedComponent.DetachCalled, "Entity destruction should detach the component")
assert(destroyedComponent.Entity == nil, "Destroyed component should be unlinked from its entity")
assert(not world:HasEntity(destroyedEntity), "Destroyed entity should be removed from the World")
assert(world:GetEntity(destroyedEntityId) == nil, "Destroyed entity should not be retrievable by ID")

local updateWorld = World.new()
local updateEntityA = updateWorld:CreateEntity()
local updateEntityB = updateWorld:CreateEntity()
local updateComponentA = updateEntityA:AddComponent(TestComponent.new())
local updateComponentB = updateEntityB:AddComponent(TestComponent.new())
local componentWithoutUpdates = updateEntityA:AddComponent(Component.new())

updateWorld:Update(1 / 60)
updateWorld:Step(1 / 60)

assert(updateComponentA.UpdateCount == 1, "World:Update() should update components on the first entity")
assert(updateComponentB.UpdateCount == 1, "World:Update() should update components on multiple entities")
assert(updateComponentA.StepCount == 1, "World:Step() should step components on the first entity")
assert(updateComponentB.StepCount == 1, "World:Step() should step components on multiple entities")
assert(updateComponentA.LastUpdateDeltaTime == 1 / 60, "Update() should receive deltaTime")
assert(updateComponentB.LastStepDeltaTime == 1 / 60, "Step() should receive deltaTime")
assert(componentWithoutUpdates:IsEnabled(), "Components without Update/Step should remain valid")

updateComponentA:SetEnabled(false)
updateWorld:Update(0.25)
updateWorld:Step(0.25)
assert(updateComponentA.UpdateCount == 1, "Disabled components should not receive Update()")
assert(updateComponentA.StepCount == 1, "Disabled components should not receive Step()")
assert(updateComponentB.UpdateCount == 2 and updateComponentB.StepCount == 2,
	"Disabling one component should not prevent other entities from updating")

updateComponentA:SetEnabled(true)
updateWorld:Update(0.5)
updateWorld:Step(0.5)
assert(updateComponentA.UpdateCount == 2 and updateComponentA.LastUpdateDeltaTime == 0.5,
	"Re-enabled components should receive Update() and deltaTime")
assert(updateComponentA.StepCount == 2 and updateComponentA.LastStepDeltaTime == 0.5,
	"Re-enabled components should receive Step() and deltaTime")

local updateEntityId = updateEntityA.Id
assert(updateWorld:DestroyEntity(updateEntityA), "World should still destroy updated entities")
assert(updateComponentA.DestroyCalled and updateComponentA.Entity == nil,
	"Destroying an updated entity should still destroy and detach its components")
assert(updateWorld:GetEntity(updateEntityId) == nil,
	"Destroyed updated entities should no longer be retrievable")

print("World/Core update tests passed")

end
