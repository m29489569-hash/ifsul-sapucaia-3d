--!strict
-- Servidor principal do IFSul — Câmpus Sapucaia do Sul (Roblox)
-- Configura iluminação/atmosfera inicial e gerencia teleporte seguro (com cooldown e suporte a Streaming).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local IFSulFolder = ReplicatedStorage:WaitForChild("IFSul")
local Config = require(IFSulFolder:WaitForChild("Config"))
local CampusData = require(IFSulFolder:WaitForChild("CampusData"))
local MatchMode = require(IFSulFolder:WaitForChild("MatchMode"))

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

local teleportRemote = ensureRemote("TeleportToLocation")

-- Configura atmosfera e nuvens iniciais (Dia/Noite é alternado localmente em cada cliente para evitar trollagem)
local function setupInitialEnvironment()
	local day = Config.Lighting.Day
	Lighting.ClockTime = day.ClockTime
	Lighting.Brightness = day.Brightness
	Lighting.OutdoorAmbient = day.OutdoorAmbient
	Lighting.GeographicLatitude = Config.GeographicLatitude
	Lighting.GlobalShadows = true

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = "CampusAtmosphere"
		atmosphere.Parent = Lighting
	end
	atmosphere.Density = day.AtmosphereDensity
	atmosphere.Offset = 0.25
	atmosphere.Color = day.AtmosphereColor
	atmosphere.Decay = day.AtmosphereDecay
	atmosphere.Glare = 0.15
	atmosphere.Haze = day.AtmosphereHaze

	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain and not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.45
		clouds.Density = 0.55
		clouds.Color = Color3.fromRGB(245, 248, 255)
		clouds.Parent = terrain
	end

	local campus = Workspace:FindFirstChild("IFSul_Campus")
	if campus then
		local lightsFolder = campus:FindFirstChild("Lights")
		if lightsFolder then
			for _, desc in ipairs(lightsFolder:GetDescendants()) do
				if desc:IsA("PointLight") then
					local alwaysOn = desc:GetAttribute("AlwaysOn") == true
					desc.Enabled = alwaysOn
					if alwaysOn then
						local dayB = desc:GetAttribute("DayBrightness")
						if typeof(dayB) == "number" then
							desc.Brightness = dayB
						end
					end
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

-- Cooldown por jogador para evitar spam de teleporte
local lastTeleport: { [Player]: number } = {}

Players.PlayerRemoving:Connect(function(player: Player)
	lastTeleport[player] = nil
end)

teleportRemote.OnServerEvent:Connect(function(player: Player, targetKey: unknown)
	-- Teleporte livre [G] fica desativado durante partidas do Modo Sobrevivência
	if MatchMode.IsSurvival() then
		return
	end
	if typeof(targetKey) ~= "string" then
		return
	end
	local dest = validTargets[targetKey]
	if not dest then
		return
	end

	local now = os.clock()
	local prev = lastTeleport[player]
	if prev and (now - prev) < Config.TeleportCooldown then
		return
	end
	lastTeleport[player] = now

	-- Se StreamingEnabled estiver ativo, solicita o carregamento da área antes de mover o personagem
	if Workspace.StreamingEnabled then
		pcall(function()
			player:RequestStreamAroundAsync(dest, 3)
		end)
	end

	local char = player.Character
	if not char then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	char:PivotTo(CFrame.new(dest))
end)

setupInitialEnvironment()
