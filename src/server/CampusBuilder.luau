--!strict
-- Decodifica o snapshot binário SoA + Zstd + Base64 (data/campus_geometry.zst.b64)
-- e reconstrói toda a hierarquia Workspace.IFSul_Campus em lotes sem travar o Studio.

local EncodingService = game:GetService("EncodingService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local CampusBuilder = {}

local MATERIALS = {
	Enum.Material.SmoothPlastic,
	Enum.Material.Concrete,
	Enum.Material.Grass,
	Enum.Material.Asphalt,
	Enum.Material.Slate,
	Enum.Material.Metal,
	Enum.Material.Glass,
	Enum.Material.Wood,
	Enum.Material.Neon,
}

function CampusBuilder.BuildFromBase64(b64Payload: string, removeBaseplate: boolean?): (number, number, number)
	local comp = EncodingService:Base64Decode(buffer.fromstring(b64Payload))
	local buf = EncodingService:DecompressBuffer(comp, Enum.CompressionAlgorithm.Zstd)

	local off = 0
	local function rf32(): number local v = buffer.readf32(buf, off); off += 4; return v end
	local function ru32(): number local v = buffer.readu32(buf, off); off += 4; return v end
	local function ru16(): number local v = buffer.readu16(buf, off); off += 2; return v end
	local function ri16(): number local v = buffer.readi16(buf, off); off += 2; return v end
	local function ru8(): number  local v = buffer.readu8(buf, off);  off += 1; return v end

	local spx, spy, spz = rf32(), rf32(), rf32()
	local slx, sly, slz = rf32(), rf32(), rf32()

	local rotCount = ru16()
	local rotX = table.create(rotCount)
	local rotY = table.create(rotCount)
	local rotZ = table.create(rotCount)
	for i = 0, rotCount - 1 do
		rotX[i] = Vector3.new(ri16() / 10000, ri16() / 10000, ri16() / 10000)
		rotY[i] = Vector3.new(ri16() / 10000, ri16() / 10000, ri16() / 10000)
		rotZ[i] = Vector3.new(ri16() / 10000, ri16() / 10000, ri16() / 10000)
	end

	if removeBaseplate ~= false then
		local bp = Workspace:FindFirstChild("Baseplate")
		if bp then bp:Destroy() end
	end

	local old = Workspace:FindFirstChild("IFSul_Campus")
	if old then old:Destroy() end

	local root = Instance.new("Folder")
	root.Name = "IFSul_Campus"

	local fTerrain = Instance.new("Folder"); fTerrain.Name = "Terrain"; fTerrain.Parent = root
	local fBuildings = Instance.new("Folder"); fBuildings.Name = "Buildings"; fBuildings.Parent = root
	local fInteriors = Instance.new("Folder"); fInteriors.Name = "Interiors"; fInteriors.Parent = root
	local fProps = Instance.new("Folder"); fProps.Name = "Props"; fProps.Parent = root
	local fSignage = Instance.new("Folder"); fSignage.Name = "Signage"; fSignage.Parent = root
	local fLights = Instance.new("Folder"); fLights.Name = "Lights"; fLights.Parent = root

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CampusSpawn"
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = CFrame.lookAt(Vector3.new(spx, spy, spz), Vector3.new(slx, sly, slz))
	spawn.Parent = root
	root.Parent = Workspace

	Lighting.ClockTime = 14
	Lighting.Brightness = 2.2
	Lighting.GeographicLatitude = -29.8
	Lighting.GlobalShadows = true
	Lighting.OutdoorAmbient = Color3.fromRGB(115, 125, 135)

	local cats = { fTerrain, fBuildings, fInteriors, fProps }

	local N = ru32()
	local tOff = off; off += N
	local mOff = off; off += N
	local cOff = off; off += N
	local colOff = off; off += N
	local crOff = off; off += N
	local cgOff = off; off += N
	local cbOff = off; off += N
	local trOff = off; off += N
	local pxOff = off; off += N * 2
	local pyOff = off; off += N * 2
	local pzOff = off; off += N * 2
	local sxOff = off; off += N * 2
	local syOff = off; off += N * 2
	local szOff = off; off += N * 2
	local riOff = off; off += N * 2

	local rotCyl = CFrame.Angles(0, 0, math.pi * 0.5)
	for i = 0, N - 1 do
		local t = buffer.readu8(buf, tOff + i)
		local mi = buffer.readu8(buf, mOff + i)
		local ci = buffer.readu8(buf, cOff + i)
		local col = buffer.readu8(buf, colOff + i)
		local cr = buffer.readu8(buf, crOff + i)
		local cg = buffer.readu8(buf, cgOff + i)
		local cb = buffer.readu8(buf, cbOff + i)
		local tr = buffer.readu8(buf, trOff + i) / 255
		local o2 = i * 2
		local px = buffer.readi16(buf, pxOff + o2) / 20
		local py = buffer.readi16(buf, pyOff + o2) / 200
		local pz = buffer.readi16(buf, pzOff + o2) / 20
		local sx = buffer.readu16(buf, sxOff + o2) / 20
		local sy = buffer.readu16(buf, syOff + o2) / 200
		local sz = buffer.readu16(buf, szOff + o2) / 20
		local ri = buffer.readu16(buf, riOff + o2)

		local part: BasePart
		if t == 5 then
			part = Instance.new("WedgePart")
		else
			local p = Instance.new("Part")
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			part = p
		end
		part.Anchored = true
		part.CanCollide = (col == 1)
		part.Material = MATERIALS[mi] or Enum.Material.SmoothPlastic
		part.Color = Color3.fromRGB(cr, cg, cb)
		part.Transparency = tr
		if mi == 7 and tr == 0 then
			part.Reflectance = 0.22
		end

		local cf = CFrame.fromMatrix(Vector3.new(px, py, pz), rotX[ri], rotY[ri], rotZ[ri])
		if t == 2 or t == 4 then
			(part :: Part).Shape = Enum.PartType.Cylinder
			part.Size = Vector3.new(sy, sx, sz)
			part.CFrame = cf * rotCyl
		elseif t == 3 then
			if math.abs(sx - sy) < 0.08 * math.max(sx, sy) and math.abs(sx - sz) < 0.08 * math.max(sx, sz) then
				(part :: Part).Shape = Enum.PartType.Ball
				part.Size = Vector3.new(sx, sy, sz)
			else
				(part :: Part).Shape = Enum.PartType.Block
				part.Size = Vector3.new(sx, sy, sz)
				local sm = Instance.new("SpecialMesh")
				sm.MeshType = Enum.MeshType.Sphere
				sm.Parent = part
			end
			part.CFrame = cf
		else
			part.Size = Vector3.new(sx, sy, sz)
			part.CFrame = cf
		end
		part.Parent = cats[ci] or fBuildings

		if i % 500 == 499 then
			task.wait()
		end
	end
	task.wait()

	local L = ru16()
	local rot180 = CFrame.Angles(0, math.pi, 0)
	for _ = 1, L do
		local tlen = ru16()
		local txt = buffer.readstring(buf, off, tlen); off += tlen
		local ri = ru16()
		local ds = ru8()
		local cr, cg, cb = ru8(), ru8(), ru8()
		local px, py, pz = rf32(), rf32(), rf32()
		local w, h = rf32(), rf32()

		local p = Instance.new("Part")
		p.Name = "Sign"
		p.Anchored = true
		p.CanCollide = false
		p.Transparency = 1
		p.Size = Vector3.new(math.max(0.2, w), math.max(0.2, h), 0.1)
		p.CFrame = CFrame.fromMatrix(Vector3.new(px, py, pz), rotX[ri], rotY[ri], rotZ[ri]) * rot180

		local function addFace(face: Enum.NormalId)
			local sg = Instance.new("SurfaceGui")
			sg.Face = face
			sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			sg.PixelsPerStud = 40
			sg.LightInfluence = 0.2
			local tl = Instance.new("TextLabel")
			tl.Size = UDim2.fromScale(1, 1)
			tl.BackgroundTransparency = 1
			tl.Text = txt
			tl.TextColor3 = Color3.fromRGB(cr, cg, cb)
			tl.TextStrokeColor3 = Color3.new(0, 0, 0)
			tl.TextStrokeTransparency = 0.45
			tl.Font = Enum.Font.GothamBold
			tl.TextScaled = true
			tl.TextWrapped = true
			tl.Parent = sg
			sg.Parent = p
		end
		addFace(Enum.NormalId.Front)
		if ds == 1 then
			addFace(Enum.NormalId.Back)
		end
		p.Parent = fSignage
	end
	task.wait()

	local K = ru16()
	for _ = 1, K do
		local cr, cg, cb = ru8(), ru8(), ru8()
		local px, py, pz = rf32(), rf32(), rf32()
		local rng, e = rf32(), rf32()

		local p = Instance.new("Part")
		p.Name = "CampusLight"
		p.Anchored = true
		p.CanCollide = false
		p.Transparency = 1
		p.Size = Vector3.new(0.5, 0.5, 0.5)
		p.Position = Vector3.new(px, py, pz)
		local pl = Instance.new("PointLight")
		pl.Color = Color3.fromRGB(cr, cg, cb)
		pl.Range = rng
		pl.Brightness = e
		pl.Shadows = false
		pl.Parent = p
		p.Parent = fLights
	end
	task.wait()

	return N, L, K
end

return CampusBuilder
