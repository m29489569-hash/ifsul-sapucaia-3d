--!strict
-- Decodificador do formato binario IFC2 (SoA + Zstd + Base64) por tile de 500m.

local EncodingService = game:GetService("EncodingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CityStyle = require(ReplicatedStorage:WaitForChild("IFSul"):WaitForChild("CityStyle"))

local CityTileCodec = {}

local PART_BLOCK = 1
local PART_CYLINDER = 2
local PART_WEDGE = 5

local FLAG_COLLIDE = 1
local FLAG_SHADOW = 2
local FLAG_CAN_QUERY = 4

local ROT_CYLINDER = CFrame.Angles(0, 0, math.pi * 0.5)
local TWO_PI = math.pi * 2

export type YieldBudget = {
	count: number,
}

local function flushBucketToFolder(bucket: { BasePart }, targetFolder: Folder)
	for _, part in ipairs(bucket) do
		part.Parent = targetFolder
	end
	table.clear(bucket)
end

function CityTileCodec.DecodeAndBuildTile(
	cityFolder: Folder,
	tileKey: string,
	b64Payload: string,
	budget: YieldBudget?
): (Model, number)
	local existing = cityFolder:FindFirstChild(tileKey)
	if existing then
		existing:Destroy()
	end

	local comp = EncodingService:Base64Decode(buffer.fromstring(b64Payload))
	local buf = EncodingService:DecompressBuffer(comp, Enum.CompressionAlgorithm.Zstd)

	local magic = buffer.readstring(buf, 0, 4)
	if magic ~= "IFC2" then
		error("CityTileCodec: magic invalido para tile " .. tileKey .. ": " .. magic)
	end

	local _tx = buffer.readi16(buf, 4)
	local _tz = buffer.readi16(buf, 6)
	local ox = buffer.readf32(buf, 8)
	local oz = buffer.readf32(buf, 12)
	local n = buffer.readu32(buf, 16)

	local model = Instance.new("Model")
	model.Name = tileKey
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local catFolders: { [number]: Folder } = {}
	for cid, cname in pairs(CityStyle.Categories) do
		local f = Instance.new("Folder")
		f.Name = cname
		f.Parent = model
		catFolders[cid] = f
	end
	model.Parent = cityFolder

	local off = 20
	local tOff = off; off += n
	local mOff = off; off += n
	local cOff = off; off += n
	local fOff = off; off += n
	local rOff = off; off += n
	local gOff = off; off += n
	local bOff = off; off += n

	local pxOff = off; off += n * 2
	local pyOff = off; off += n * 2
	local pzOff = off; off += n * 2
	local sxOff = off; off += n * 2
	local syOff = off; off += n * 2
	local szOff = off; off += n * 2
	local yawOff = off; off += n * 2

	local counter: YieldBudget = budget or { count = 0 }
	local batchLimit = CityStyle.TileBatchYieldSize
	local pendingByCat: { [number]: { BasePart } } = {
		[1] = {},
		[2] = {},
		[3] = {},
		[4] = {},
	}

	local materials = CityStyle.Materials

	for i = 0, n - 1 do
		local pType = buffer.readu8(buf, tOff + i)
		local matId = buffer.readu8(buf, mOff + i)
		local catId = buffer.readu8(buf, cOff + i)
		local flags = buffer.readu8(buf, fOff + i)
		local cr = buffer.readu8(buf, rOff + i)
		local cg = buffer.readu8(buf, gOff + i)
		local cb = buffer.readu8(buf, bOff + i)

		local o2 = i * 2
		local px = ox + buffer.readi16(buf, pxOff + o2) / 20
		local py = buffer.readi16(buf, pyOff + o2) / 100
		local pz = oz + buffer.readi16(buf, pzOff + o2) / 20
		local sx = buffer.readu16(buf, sxOff + o2) / 20
		local sy = buffer.readu16(buf, syOff + o2) / 100
		local sz = buffer.readu16(buf, szOff + o2) / 20
		local yaw = (buffer.readu16(buf, yawOff + o2) / 65536) * TWO_PI

		local part: BasePart
		if pType == PART_WEDGE then
			part = Instance.new("WedgePart")
		else
			local p = Instance.new("Part")
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			if pType == PART_CYLINDER then
				p.Shape = Enum.PartType.Cylinder
			end
			part = p
		end

		part.Anchored = true
		part.CanCollide = bit32.band(flags, FLAG_COLLIDE) ~= 0
		part.CanTouch = false
		part.CanQuery = bit32.band(flags, FLAG_CAN_QUERY) ~= 0
		part.CastShadow = bit32.band(flags, FLAG_SHADOW) ~= 0
		part.Material = materials[matId] or Enum.Material.SmoothPlastic
		part.Color = Color3.fromRGB(cr, cg, cb)

		local cf = CFrame.new(px, py, pz) * CFrame.Angles(0, yaw, 0)
		if pType == PART_CYLINDER then
			part.Size = Vector3.new(sy, sx, sz)
			part.CFrame = cf * ROT_CYLINDER
		else
			part.Size = Vector3.new(sx, sy, sz)
			part.CFrame = cf
		end

		local bucket = pendingByCat[catId] or pendingByCat[4]
		table.insert(bucket, part)
		counter.count += 1

		if counter.count >= batchLimit then
			for cid, bkt in pairs(pendingByCat) do
				if #bkt > 0 then
					flushBucketToFolder(bkt, catFolders[cid] or catFolders[4])
				end
			end
			counter.count = 0
			task.wait()
		end
	end

	for cid, bkt in pairs(pendingByCat) do
		if #bkt > 0 then
			flushBucketToFolder(bkt, catFolders[cid] or catFolders[4])
		end
	end

	return model, n
end

return CityTileCodec
