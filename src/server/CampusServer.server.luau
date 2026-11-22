--!strict
-- Servidor principal do IFSul — Câmpus Sapucaia do Sul (Roblox)
-- Gerencia iluminação Dia/Noite e teleporte seguro para salas e POIs.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local IFSulFolder = ReplicatedStorage:WaitForChild("IFSul")
local Config = require(IFSulFolder:WaitForChild("Config"))
local CampusData = require(IFSulFolder:WaitForChild("CampusData"))

-- Cria pasta de RemoteEvents em ReplicatedStorage.IFSul.Remotes
local remotes = IFSulFolder:FindFirstChild("Remotes") :: Folder?
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = IFSulFolder
end

local function ensureRemote(name: string): RemoteEvent
	local existing = remotes:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = remotes
	return re
end

local toggleDayNightRemote = ensureRemote("ToggleDayNight")
local teleportRemote = ensureRemote("TeleportToLocation")

local isNight = false

local function applyLighting(night: boolean)
	isNight = night
	local preset = if night then Config.Lighting.Night else Config.Lighting.Day
	Lighting.ClockTime = preset.ClockTime
	Lighting.Brightness = preset.Brightness
	Lighting.OutdoorAmbient = preset.OutdoorAmbient
	Lighting.GeographicLatitude = Config.GeographicLatitude

	local campus = Workspace:FindFirstChild("IFSul_Campus")
	if campus then
		local lightsFolder = campus:FindFirstChild("Lights")
		if lightsFolder then
			for _, desc in ipairs(lightsFolder:GetDescendants()) do
				if desc:IsA("PointLight") then
					desc.Enabled = night
				end
			end
		end
	end
end

-- Índice rápido de destinos permitidos (evita teleporte arbitrário do cliente)
local validTargets: { [string]: Vector3 } = {
	spawn = Config.SpawnPosition,
}
for _, poi in ipairs(CampusData.POIs) do
	validTargets["poi:" .. poi.id] = poi.position + Vector3.new(0, 3, 0)
end
for _, room in ipairs(CampusData.Rooms) do
	validTargets["room:" .. room.id] = room.center + Vector3.new(0, 1.5, 0)
end

toggleDayNightRemote.OnServerEvent:Connect(function(_player: Player)
	applyLighting(not isNight)
	toggleDayNightRemote:FireAllClients(isNight)
end)

teleportRemote.OnServerEvent:Connect(function(player: Player, targetKey: unknown)
	if typeof(targetKey) ~= "string" then
		return
	end
	local dest = validTargets[targetKey]
	if not dest then
		return
	end
	local char = player.Character
	if not char then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		hrp.CFrame = CFrame.new(dest)
	end
end)

applyLighting(false)
