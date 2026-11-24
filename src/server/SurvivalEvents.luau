--!strict
-- Eventos Dinâmicos do Cenário do IFSul durante as Ondas:
-- 1) Caixas de Munição/Suprimento nos pátios usando os modelos prontos da Creator Store;
-- 2) Missões Bônus nos Setores Reais (Manutenção 404, Inovação 234, Saúde 112, Química 304 e Quadra Coberta).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local IFSulFolder = ReplicatedStorage:WaitForChild("IFSul")
local Config = require(IFSulFolder:WaitForChild("Config"))
local SurvivalCatalog = require(IFSulFolder:WaitForChild("SurvivalCatalog"))
local SurvivalWeapons = require(script.Parent:WaitForChild("SurvivalWeapons"))

local SurvivalEvents = {}

local rng = Random.new()
local cratesFolder: Folder? = nil
local missionFolder: Folder? = nil
local activeMission: {
	def: SurvivalCatalog.SectorMissionDef,
	expiresAt: number,
	progress: number,
	completed: boolean,
}? = nil

local onMissionUpdateCallback: ((state: { [string]: any }?) -> ())? = nil
local onSquadRewardCallback: ((creditsEach: number, message: string, reviveAll: boolean?, grantReactiveAmmo: boolean?) -> ())? = nil

function SurvivalEvents.SetContext(
	cFolder: Folder?,
	mFolder: Folder?,
	missionUpdateCb: (state: { [string]: any }?) -> (),
	squadRewardCb: (creditsEach: number, message: string, reviveAll: boolean?, grantReactiveAmmo: boolean?) -> ()
)
	cratesFolder = cFolder
	missionFolder = mFolder
	onMissionUpdateCallback = missionUpdateCb
	onSquadRewardCallback = squadRewardCb
end

function SurvivalEvents.ApplyDayOrBlackoutLighting(isBlackout: boolean)
	local preset = if isBlackout then Config.Lighting.Night else Config.Lighting.Day
	Lighting.ClockTime = preset.ClockTime
	Lighting.Brightness = if isBlackout then 0.35 else preset.Brightness
	Lighting.OutdoorAmbient = if isBlackout then Color3.fromRGB(18, 22, 34) else preset.OutdoorAmbient

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = if isBlackout then 0.42 else preset.AtmosphereDensity
		atmosphere.Color = preset.AtmosphereColor
		atmosphere.Decay = preset.AtmosphereDecay
		atmosphere.Haze = preset.AtmosphereHaze
	end

	local campus = Workspace:FindFirstChild("IFSul_Campus")
	local lightsFolder = campus and campus:FindFirstChild("Lights")
	if lightsFolder then
		for _, desc in ipairs(lightsFolder:GetDescendants()) do
			if desc:IsA("PointLight") then
				desc.Enabled = not isBlackout and (desc:GetAttribute("AlwaysOn") == true)
			end
		end
	end
end

local function cloneReadyProp(propName: string): Instance?
	local assets = ServerStorage:FindFirstChild("IFSul_SurvivalAssets")
	local props = assets and assets:FindFirstChild("Props")
	local container = props and props:FindFirstChild(propName)
	if not container then
		return nil
	end
	local inner = container:FindFirstChildOfClass("Model") or container:FindFirstChildWhichIsA("BasePart")
	if inner then
		return inner:Clone()
	end
	return container:Clone()
end

local function createMarkerBillboard(parent: Instance, titleText: string, subText: string, accent: Color3, alwaysOnTop: boolean): BillboardGui
	local bbg = Instance.new("BillboardGui")
	bbg.Name = "ObjectiveMarker"
	bbg.Size = UDim2.fromOffset(210, 52)
	bbg.StudsOffset = Vector3.new(0, 4.5, 0)
	bbg.MaxDistance = if alwaysOnTop then 1500 else 260
	bbg.AlwaysOnTop = alwaysOnTop
	bbg.Parent = parent

	local box = Instance.new("Frame")
	box.Size = UDim2.fromScale(1, 1)
	box.BackgroundColor3 = Color3.fromRGB(14, 20, 26)
	box.BackgroundTransparency = 0.12
	box.Parent = bbg

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = box

	local stroke = Instance.new("UIStroke")
	stroke.Color = accent
	stroke.Thickness = 2
	stroke.Parent = box

	local t1 = Instance.new("TextLabel")
	t1.Size = UDim2.new(1, -12, 0.54, 0)
	t1.Position = UDim2.fromOffset(6, 2)
	t1.BackgroundTransparency = 1
	t1.Font = Enum.Font.GothamBlack
	t1.TextScaled = true
	t1.TextColor3 = accent
	t1.Text = titleText
	t1.Parent = box

	local t2 = Instance.new("TextLabel")
	t2.Size = UDim2.new(1, -12, 0.40, 0)
	t2.Position = UDim2.new(0, 6, 0.55, 0)
	t2.BackgroundTransparency = 1
	t2.Font = Enum.Font.GothamSemibold
	t2.TextScaled = true
	t2.TextColor3 = Color3.fromRGB(230, 236, 242)
	t2.Text = subText
	t2.Parent = box

	return bbg
end

-- Gera Caixas de Suprimento e Munição pelos pátios do câmpus no início de cada onda
function SurvivalEvents.SpawnWaveSupplyCrates(wave: number)
	if not cratesFolder then
		return
	end
	cratesFolder:ClearAllChildren()

	local spots = table.clone(SurvivalCatalog.SupplySpots)
	for i = #spots, 2, -1 do
		local j = rng:NextInteger(1, i)
		spots[i], spots[j] = spots[j], spots[i]
	end

	local count = math.min(#spots, if wave <= 2 then 2 else 3)
	for i = 1, count do
		local pos = spots[i]
		local wrapper = Instance.new("Model")
		wrapper.Name = "SupplyCrate_" .. tostring(i)
		wrapper.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

		local prop = cloneReadyProp("ammo_crate")
		if prop then
			prop.Parent = wrapper
			if prop:IsA("Model") then
				prop:PivotTo(CFrame.new(pos + Vector3.new(0, 1.8, 0)))
			elseif prop:IsA("BasePart") then
				prop.CFrame = CFrame.new(pos + Vector3.new(0, 1.8, 0))
			end
		end

		local anchor = Instance.new("Part")
		anchor.Name = "PromptPart"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(4, 4, 4)
		anchor.Position = pos + Vector3.new(0, 2.2, 0)
		anchor.Parent = wrapper

		for _, bp in ipairs(wrapper:GetDescendants()) do
			if bp:IsA("BasePart") then
				bp.Anchored = true
			end
		end

		local hl = Instance.new("Highlight")
		hl.FillColor = Color3.fromRGB(250, 204, 21)
		hl.FillTransparency = 0.72
		hl.OutlineColor = Color3.fromRGB(255, 224, 92)
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = wrapper

		createMarkerBillboard(anchor, "📦 SUPRIMENTO DO IF", "Munição + Cura + Créditos [E]", Color3.fromRGB(250, 204, 21), false)

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Pegar Suprimento"
		prompt.ObjectText = "+Munição • +35 HP • +45 Créditos"
		prompt.HoldDuration = 0.6
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = anchor

		local used = false
		prompt.Triggered:Connect(function(player: Player)
			if used or not wrapper.Parent then
				return
			end
			local char = player.Character
			if not char or char:GetAttribute("Downed") == true then
				return
			end
			used = true
			SurvivalWeapons.RefillAllAmmo(player)
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				hum.Health = math.min(hum.MaxHealth, hum.Health + 35)
			end
			local st = SurvivalWeapons.GetStats(player)
			if st then
				st.credits += math.round(45 * st.creditMult)
				SurvivalWeapons.SyncPlayerAttributes(player)
			end
			wrapper:Destroy()
		end)

		wrapper.Parent = cratesFolder
	end
end

function SurvivalEvents.ClearActiveMission()
	if missionFolder then
		missionFolder:ClearAllChildren()
	end
	if activeMission and activeMission.def.kind == "Blackout" then
		SurvivalEvents.ApplyDayOrBlackoutLighting(false)
	end
	activeMission = nil
	if onMissionUpdateCallback then
		onMissionUpdateCallback(nil)
	end
end

-- Inicia 1 Missão Bônus em um setor real do IFSul (Ondas pares e múltiplas de 3)
function SurvivalEvents.TryStartSectorMission(wave: number)
	SurvivalEvents.ClearActiveMission()
	if not missionFolder or wave < 2 then
		return
	end
	if (wave % 2 ~= 0) and (wave % 3 ~= 0) then
		return
	end

	local missions = SurvivalCatalog.SectorMissions
	local chosen = missions[((wave // 2 - 1) % #missions) + 1]
	-- Na onda 5, 10, 15 prioriza o Apagão Noturno na Manutenção 404 para máximo impacto dramático!
	if wave % 5 == 0 then
		chosen = missions[1]
	end

	local now = os.clock()
	activeMission = {
		def = chosen,
		expiresAt = now + chosen.durationSec,
		progress = 0,
		completed = false,
	}

	if chosen.kind == "Blackout" then
		SurvivalEvents.ApplyDayOrBlackoutLighting(true)
	end

	local container = Instance.new("Model")
	container.Name = "ActiveSectorMission"
	container.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	container.Parent = missionFolder

	local anchor = Instance.new("Part")
	anchor.Name = "MissionAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = if chosen.kind == "HoldZone" then 0.55 else 1
	anchor.Material = Enum.Material.Neon
	anchor.Color = Color3.fromRGB(47, 215, 115)
	if chosen.kind == "HoldZone" then
		anchor.Shape = Enum.PartType.Cylinder
		anchor.Size = Vector3.new(0.5, 22, 22)
		anchor.CFrame = CFrame.new(chosen.position - Vector3.new(0, 3.8, 0)) * CFrame.Angles(0, 0, math.rad(90))
	else
		anchor.Size = Vector3.new(4, 5, 4)
		anchor.CFrame = CFrame.new(chosen.position)
	end
	anchor.Parent = container

	local propName = if chosen.kind == "Blackout"
		then "breaker_box"
		elseif chosen.kind == "SupplyRescue" then "medkit"
		else "ammo_crate"
	local prop = cloneReadyProp(propName)
	if prop then
		prop.Parent = container
		for _, bp in ipairs(prop:GetDescendants()) do
			if bp:IsA("BasePart") then
				bp.Anchored = true
				bp.CanCollide = false
			end
		end
		if prop:IsA("BasePart") then
			prop.Anchored = true
			prop.CanCollide = false
			prop.CFrame = CFrame.new(chosen.position)
		elseif prop:IsA("Model") then
			prop:PivotTo(CFrame.new(chosen.position))
		end
	end

	local hl = Instance.new("Highlight")
	hl.FillColor = Color3.fromRGB(250, 204, 21)
	hl.FillTransparency = 0.45
	hl.OutlineColor = Color3.new(1, 1, 1)
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = container

	createMarkerBillboard(anchor, "⚡ " .. chosen.title, chosen.sectorLabel, Color3.fromRGB(250, 204, 21), true)

	local function completeMission()
		if not activeMission or activeMission.completed then
			return
		end
		activeMission.completed = true
		if chosen.kind == "Blackout" then
			SurvivalEvents.ApplyDayOrBlackoutLighting(false)
			-- Acende todos os refletores do câmpus como recompensa visual!
			local campus = Workspace:FindFirstChild("IFSul_Campus")
			local lights = campus and campus:FindFirstChild("Lights")
			if lights then
				for _, d in ipairs(lights:GetDescendants()) do
					if d:IsA("PointLight") then
						d.Enabled = true
					end
				end
			end
		end

		if onSquadRewardCallback then
			onSquadRewardCallback(
				chosen.rewardCredits,
				string.format("Missão Concluída (%s)! +%d Créditos para a equipe!", chosen.sectorLabel, chosen.rewardCredits),
				chosen.kind == "SupplyRescue",
				chosen.kind == "ValveContainment"
			)
		end
		if chosen.kind == "AirDrop" then
			for _, p in ipairs(Players:GetPlayers()) do
				SurvivalWeapons.RefillAllAmmo(p)
				local st = SurvivalWeapons.GetStats(p)
				if st then
					st.medkits = math.min(5, st.medkits + 1)
					SurvivalWeapons.SyncPlayerAttributes(p)
				end
			end
		end
		SurvivalEvents.ClearActiveMission()
	end

	if chosen.kind ~= "HoldZone" then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = chosen.title
		prompt.ObjectText = chosen.sectorLabel
		prompt.HoldDuration = chosen.holdTimeSec
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = anchor
		prompt.Triggered:Connect(function(player: Player)
			if player.Character and player.Character:GetAttribute("Downed") ~= true then
				completeMission()
			end
		end)
	end

	task.spawn(function()
		while activeMission and not activeMission.completed and container.Parent do
			local rem = activeMission.expiresAt - os.clock()
			if rem <= 0 then
				SurvivalEvents.ClearActiveMission()
				break
			end

			if chosen.kind == "HoldZone" then
				local someoneInside = false
				for _, p in ipairs(Players:GetPlayers()) do
					local char = p.Character
					local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
					local hum = char and char:FindFirstChildOfClass("Humanoid")
					if char and char:GetAttribute("Downed") ~= true and hrp and hum and hum.Health > 0 then
						local dist = Vector2.new(hrp.Position.X - chosen.position.X, hrp.Position.Z - chosen.position.Z).Magnitude
						if dist <= 12.5 then
							someoneInside = true
							break
						end
					end
				end
				if someoneInside then
					activeMission.progress = math.min(1, activeMission.progress + (0.25 / chosen.holdTimeSec))
					if activeMission.progress >= 1 then
						completeMission()
						break
					end
				end
			end

			if onMissionUpdateCallback and activeMission then
				onMissionUpdateCallback({
					title = chosen.title,
					sector = chosen.sectorLabel,
					instruction = chosen.instruction,
					remainingSec = math.ceil(rem),
					progress = activeMission.progress,
					isHoldZone = chosen.kind == "HoldZone",
					artAssetId = chosen.artAssetId,
					rewardCredits = chosen.rewardCredits,
				})
			end

			task.wait(0.25)
		end
	end)
end

return SurvivalEvents
