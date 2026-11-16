local CollisionQuery = {}

local AXES = {
	Vector3.new(1, 0, 0),
	Vector3.new(0, 1, 0),
	Vector3.new(0, 0, 1),
}

local function dot(left, right)
	return left.X * right.X + left.Y * right.Y + left.Z * right.Z
end

local function boxAxes(box)
	return {
		box.Rotation:VectorToWorldSpace(AXES[1]),
		box.Rotation:VectorToWorldSpace(AXES[2]),
		box.Rotation:VectorToWorldSpace(AXES[3]),
	}
end

local function halfExtents(box)
	return { box.Size.X * 0.5, box.Size.Y * 0.5, box.Size.Z * 0.5 }
end

local function boxesIntersect(left, right)
	local leftAxes = boxAxes(left)
	local rightAxes = boxAxes(right)
	local leftSize = halfExtents(left)
	local rightSize = halfExtents(right)
	local rotation = {}
	local absoluteRotation = {}

	for i = 1, 3 do
		rotation[i] = {}
		absoluteRotation[i] = {}
		for j = 1, 3 do
			rotation[i][j] = dot(leftAxes[i], rightAxes[j])
			absoluteRotation[i][j] = math.abs(rotation[i][j])
		end
	end

	local offset = right.Position - left.Position
	local translated = {
		dot(offset, leftAxes[1]),
		dot(offset, leftAxes[2]),
		dot(offset, leftAxes[3]),
	}

	for i = 1, 3 do
		local rightRadius = 0
		for j = 1, 3 do
			rightRadius += rightSize[j] * absoluteRotation[i][j]
		end
		if math.abs(translated[i]) > leftSize[i] + rightRadius then
			return false
		end
	end

	for j = 1, 3 do
		local translatedOnRight = 0
		local leftRadius = 0
		for i = 1, 3 do
			translatedOnRight += translated[i] * rotation[i][j]
			leftRadius += leftSize[i] * absoluteRotation[i][j]
		end
		if math.abs(translatedOnRight) > rightSize[j] + leftRadius then
			return false
		end
	end

	for i = 0, 2 do
		local i1 = i + 1
		local i2 = (i + 1) % 3 + 1
		local i3 = (i + 2) % 3 + 1
		for j = 0, 2 do
			local j1 = j + 1
			local j2 = (j + 1) % 3 + 1
			local j3 = (j + 2) % 3 + 1

			local leftRadius = leftSize[i2] * absoluteRotation[i3][j1]
				+ leftSize[i3] * absoluteRotation[i2][j1]
			local rightRadius = rightSize[j2] * absoluteRotation[i1][j3]
				+ rightSize[j3] * absoluteRotation[i1][j2]
			local projectedOffset = math.abs(
				translated[i3] * rotation[i2][j1]
					- translated[i2] * rotation[i3][j1]
			)
			if projectedOffset > leftRadius + rightRadius then
				return false
			end
		end
	end

	return true
end

local function sphereSphereIntersect(left, right)
	local offset = left.Position - right.Position
	local radiusSum = left.Radius + right.Radius
	return dot(offset, offset) <= radiusSum * radiusSum
end

local function boxSphereIntersect(box, sphere)
	local localCenter = box.Rotation:VectorToObjectSpace(sphere.Position - box.Position)
	local halfSize = box.Size * 0.5
	local closest = Vector3.new(
		math.clamp(localCenter.X, -halfSize.X, halfSize.X),
		math.clamp(localCenter.Y, -halfSize.Y, halfSize.Y),
		math.clamp(localCenter.Z, -halfSize.Z, halfSize.Z)
	)
	local difference = localCenter - closest
	return dot(difference, difference) <= sphere.Radius * sphere.Radius
end

local function boxProjectionRadius(box, axes, halfSizes, axis)
	local radius = 0
	for index = 1, 3 do
		radius += halfSizes[index] * math.abs(dot(axes[index], axis))
	end
	return radius
end

local function sweptBoxesIntersect(left, right, leftStart, rightStart)
	local leftAxes = boxAxes(left)
	local rightAxes = boxAxes(right)
	local leftSize = halfExtents(left)
	local rightSize = halfExtents(right)
	local axes = {}

	for _, axis in ipairs(leftAxes) do table.insert(axes, axis) end
	for _, axis in ipairs(rightAxes) do table.insert(axes, axis) end
	for _, leftAxis in ipairs(leftAxes) do
		for _, rightAxis in ipairs(rightAxes) do
			table.insert(axes, leftAxis:Cross(rightAxis))
		end
	end

	local relativeStart = leftStart - rightStart
	local relativeVelocity = (left.Position - leftStart) - (right.Position - rightStart)
	local firstTime, lastTime = 0, 1

	for _, axis in ipairs(axes) do
		if axis:Dot(axis) > 0 then
			local radius = boxProjectionRadius(left, leftAxes, leftSize, axis)
				+ boxProjectionRadius(right, rightAxes, rightSize, axis)
			local separation = dot(relativeStart, axis)
			local speed = dot(relativeVelocity, axis)
			if speed == 0 then
				if math.abs(separation) > radius then return false end
			else
				local entry = (-radius - separation) / speed
				local exit = (radius - separation) / speed
				if entry > exit then entry, exit = exit, entry end
				firstTime = math.max(firstTime, entry)
				lastTime = math.min(lastTime, exit)
				if firstTime > lastTime then return false end
			end
		end
	end
	return true
end

local function pointToBoxDistanceSquared(position, halfSize)
	local dx = math.max(math.abs(position[1]) - halfSize[1], 0)
	local dy = math.max(math.abs(position[2]) - halfSize[2], 0)
	local dz = math.max(math.abs(position[3]) - halfSize[3], 0)
	return dx * dx + dy * dy + dz * dz
end

local function segmentToBoxDistanceSquared(startPosition, endPosition, halfSize)
	local start = { startPosition.X, startPosition.Y, startPosition.Z }
	local finish = { endPosition.X, endPosition.Y, endPosition.Z }
	local velocity = {
		finish[1] - start[1],
		finish[2] - start[2],
		finish[3] - start[3],
	}
	local breakpoints = { 0, 1 }

	for axis = 1, 3 do
		if velocity[axis] ~= 0 then
			for _, boundary in ipairs({ -halfSize[axis], halfSize[axis] }) do
				local time = (boundary - start[axis]) / velocity[axis]
				if time > 0 and time < 1 then table.insert(breakpoints, time) end
			end
		end
	end
	table.sort(breakpoints)

	local minimum = math.min(
		pointToBoxDistanceSquared(start, halfSize),
		pointToBoxDistanceSquared(finish, halfSize)
	)
	for index = 1, #breakpoints - 1 do
		local intervalStart = breakpoints[index]
		local intervalEnd = breakpoints[index + 1]
		if intervalEnd > intervalStart then
			local middle = (intervalStart + intervalEnd) * 0.5
			local quadratic, linear = 0, 0
			for axis = 1, 3 do
				local middleValue = start[axis] + velocity[axis] * middle
				local boundary = middleValue < -halfSize[axis] and -halfSize[axis]
					or middleValue > halfSize[axis] and halfSize[axis]
					or nil
				if boundary ~= nil then
					quadratic += velocity[axis] * velocity[axis]
					linear += velocity[axis] * (start[axis] - boundary)
				end
			end
			if quadratic > 0 then
				local closestTime = math.clamp(-linear / quadratic, intervalStart, intervalEnd)
				minimum = math.min(minimum,
					pointToBoxDistanceSquared({
						start[1] + velocity[1] * closestTime,
						start[2] + velocity[2] * closestTime,
						start[3] + velocity[3] * closestTime,
					}, halfSize))
			end
		end
	end
	return minimum
end

local function sweptSphereSphereIntersect(left, right, leftStart, rightStart)
	local relativeStart = leftStart - rightStart
	local relativeEnd = left.Position - right.Position
	local velocity = relativeEnd - relativeStart
	local velocityLengthSquared = velocity:Dot(velocity)
	local time = 0
	if velocityLengthSquared > 0 then
		time = math.clamp(-relativeStart:Dot(velocity) / velocityLengthSquared, 0, 1)
	end
	local closest = relativeStart + velocity * time
	local radius = left.Radius + right.Radius
	return closest:Dot(closest) <= radius * radius
end

local function sweptBoxSphereIntersect(box, sphere, boxStart, sphereStart)
	local sphereStartInBox = box.Rotation:VectorToObjectSpace(sphereStart - boxStart)
	local sphereEndInBox = box.Rotation:VectorToObjectSpace(sphere.Position - box.Position)
	local halfSize = { box.Size.X * 0.5, box.Size.Y * 0.5, box.Size.Z * 0.5 }
	return segmentToBoxDistanceSquared(sphereStartInBox, sphereEndInBox, halfSize)
		<= sphere.Radius * sphere.Radius
end

local function assertRegion(region)
	assert(type(region) == "table" and (region.Shape == "Box" or region.Shape == "Sphere"),
		"CollisionQuery expects a Hitbox or Hurtbox with a supported Shape")
end

function CollisionQuery.BoxBox(left, right)
	assertRegion(left)
	assertRegion(right)
	assert(left.Shape == "Box" and right.Shape == "Box", "BoxBox() requires two boxes")
	return boxesIntersect(left, right)
end

function CollisionQuery.SphereSphere(left, right)
	assertRegion(left)
	assertRegion(right)
	assert(left.Shape == "Sphere" and right.Shape == "Sphere", "SphereSphere() requires two spheres")
	return sphereSphereIntersect(left, right)
end

function CollisionQuery.BoxSphere(box, sphere)
	assertRegion(box)
	assertRegion(sphere)
	assert(box.Shape == "Box" and sphere.Shape == "Sphere", "BoxSphere() requires a box and a sphere")
	return boxSphereIntersect(box, sphere)
end

function CollisionQuery.SphereBox(sphere, box)
	assertRegion(sphere)
	assertRegion(box)
	assert(sphere.Shape == "Sphere" and box.Shape == "Box", "SphereBox() requires a sphere and a box")
	return boxSphereIntersect(box, sphere)
end

function CollisionQuery.Intersects(left, right)
	assertRegion(left)
	assertRegion(right)

	if left.Shape == "Box" and right.Shape == "Box" then
		return boxesIntersect(left, right)
	elseif left.Shape == "Sphere" and right.Shape == "Sphere" then
		return sphereSphereIntersect(left, right)
	elseif left.Shape == "Box" then
		return boxSphereIntersect(left, right)
	else
		return boxSphereIntersect(right, left)
	end
end

function CollisionQuery.SweptIntersects(left, right, leftStart, rightStart)
	assertRegion(left)
	assertRegion(right)
	assert(typeof(leftStart) == "Vector3" and typeof(rightStart) == "Vector3",
		"SweptIntersects() requires previous Vector3 positions")

	if left.Shape == "Box" and right.Shape == "Box" then
		return sweptBoxesIntersect(left, right, leftStart, rightStart)
	elseif left.Shape == "Sphere" and right.Shape == "Sphere" then
		return sweptSphereSphereIntersect(left, right, leftStart, rightStart)
	elseif left.Shape == "Box" then
		return sweptBoxSphereIntersect(left, right, leftStart, rightStart)
	else
		return sweptBoxSphereIntersect(right, left, rightStart, leftStart)
	end
end

return CollisionQuery
