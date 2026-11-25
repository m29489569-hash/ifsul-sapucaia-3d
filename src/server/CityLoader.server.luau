--!strict
-- Carrega e descarrega tiles de cidade em Workspace.IFSul_City a partir de ServerStorage.IFSulCity.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local IFSulFolder = ReplicatedStorage:WaitForChild("IFSul")
local Config = require(IFSulFolder:WaitForChild("Config"))
local CityStyle = require(IFSulFolder:WaitForChild("CityStyle"))
local CityTileCodec = require(script.Parent:WaitForChild("CityTileCodec"))

type TileMeta = {
	key: string,
	center_x_studs: number,
	center_z_studs: number,
	parts: number,
}

type CityEntry = {
	name: string,
	folder: Folder,
	tilesFolder: Folder,
	tiles: { TileMeta },
	loaded: { [string]: Model },
}

local function discoverCities(cityRoot: Folder): { CityEntry }
	local storageRoot = ServerStorage:FindFirstChild("IFSulCity")
	if not storageRoot then
		return {}
	end

	local entries: { CityEntry } = {}
	for _, cityStorage in ipairs(storageRoot:GetChildren()) do
		local indexVal = cityStorage:FindFirstChild("Index")
		local tilesFolder = cityStorage:FindFirstChild("Tiles")
		if indexVal and indexVal:IsA("StringValue") and tilesFolder and tilesFolder:IsA("Folder") then
			local ok, decoded = pcall(HttpService.JSONDecode, HttpService, indexVal.Value)
			if ok and type(decoded) == "table" and type(decoded.tiles) == "table" then
				local wsFolder = cityRoot:FindFirstChild(cityStorage.Name) :: Folder?
				if not wsFolder then
					wsFolder = Instance.new("Folder")
					wsFolder.Name = cityStorage.Name
					wsFolder.Parent = cityRoot
				end

				local loaded: { [string]: Model } = {}
				for _, child in ipairs((wsFolder :: Folder):GetChildren()) do
					if child:IsA("Model") then
						loaded[child.Name] = child
					end
				end

				table.insert(entries, {
					name = cityStorage.Name,
					folder = wsFolder :: Folder,
					tilesFolder = tilesFolder,
					tiles = decoded.tiles :: { TileMeta },
					loaded = loaded,
				})
			end
		end
	end
	return entries
end

local function collectPlayerPositions(): { Vector3 }
	local positions: { Vector3 } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
		if root and root:IsA("BasePart") then
			table.insert(positions, root.Position)
		end
	end
	if #positions == 0 then
		table.insert(positions, Config.SpawnPosition)
	end
	return positions
end

local function minPlanarDistance(x: number, z: number, positions: { Vector3 }): number
	local best = math.huge
	for _, p in ipairs(positions) do
		local dx = p.X - x
		local dz = p.Z - z
		local d = math.sqrt(dx * dx + dz * dz)
		if d < best then
			best = d
		end
	end
	return best
end

task.spawn(function()
	local cityRoot = Workspace:FindFirstChild("IFSul_City") :: Folder?
	if not cityRoot then
		cityRoot = Instance.new("Folder")
		cityRoot.Name = "IFSul_City"
		cityRoot.Parent = Workspace
	end

	local cities = discoverCities(cityRoot :: Folder)
	if #cities == 0 then
		return
	end

	local loadR = CityStyle.LoadRadiusStuds
	local unloadR = CityStyle.UnloadRadiusStuds
	local budget: CityTileCodec.YieldBudget = { count = 0 }

	while true do
		local positions = collectPlayerPositions()
		for _, entry in ipairs(cities) do
			for _, meta in ipairs(entry.tiles) do
				local d = minPlanarDistance(meta.center_x_studs, meta.center_z_studs, positions)
				local existing = entry.loaded[meta.key]
				if not existing and d <= loadR then
					local tileVal = entry.tilesFolder:FindFirstChild(meta.key)
					if tileVal and tileVal:IsA("StringValue") and tileVal.Value ~= "" then
						local model = CityTileCodec.DecodeAndBuildTile(entry.folder, meta.key, tileVal.Value, budget)
						entry.loaded[meta.key] = model
					end
				elseif existing and d > unloadR then
					existing:Destroy()
					entry.loaded[meta.key] = nil
				end
			end
		end
		task.wait(CityStyle.CheckIntervalSeconds)
	end
end)
