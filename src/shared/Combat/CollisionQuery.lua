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

return CollisionQuery
