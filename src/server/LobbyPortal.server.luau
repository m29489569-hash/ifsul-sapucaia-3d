--!strict
-- Portal / Zona de Fila (1 a 6 Jogadores) na Portaria Principal no modo Lobby
-- Usa TeleportService:ReserveServer(game.PlaceId) em servidores publicados e alternância
-- instantânea ao vivo no Roblox Studio (permitindo testar sem precisar publicar antes).

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local IFSulFolder = ReplicatedStorage:WaitForChild("IFSul")
local Config = require(IFSulFolder:WaitForChild("Config"))
local MatchMode = require(IFSulFolder:WaitForChild("MatchMode"))
local SurvivalCatalog = require(IFSulFolder:WaitForChild("SurvivalCatalog"))

local remotes = IFSulFolder:FindFirstChild("Remotes") :: Folder?
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = IFSulFolder
end

local function ensureRemoteEvent(name: string): RemoteEvent
	local existing = remotes:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = remotes
	return re
end

local portalStateRE = ensureRemoteEvent("SurvivalPortalState")
local portalActionRE = ensureRemoteEvent("SurvivalPortalAction")

-- Configura CollisionGroups para impedir saída do câmpus pelos jogadores na partida,
-- deixando os invasores entrarem livremente pelas 4 ruas externas.
local GROUPS_READY = false
local function setupCollisionGroups()
	if GROUPS_READY then
		return
	end
	GROUPS_READY = true
	pcall(function()
		PhysicsService:RegisterCollisionGroup("SurvivalPlayers")
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup("SurvivalInvaders")
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup("CampusPerimeterBlock")
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable("SurvivalPlayers", "SurvivalPlayers", false)
		PhysicsService:CollisionGroupSetCollidable("SurvivalPlayers", "CampusPerimeterBlock", true)
		PhysicsService:CollisionGroupSetCollidable("SurvivalInvaders", "SurvivalInvaders", false)
		PhysicsService:CollisionGroupSetCollidable("SurvivalInvaders", "CampusPerimeterBlock", false)
	end)
end

setupCollisionGroups()

local function applyPlayerCollisionGroup(char: Model)
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = "SurvivalPlayers"
		end
	end
	char.DescendantAdded:Connect(function(d: Instance)
		if d:IsA("BasePart") then
			d.CollisionGroup = "SurvivalPlayers"
		end
	end)
end

Players.PlayerAdded:Connect(function(p: Player)
	p.CharacterAdded:Connect(applyPlayerCollisionGroup)
	if p.Character then
		applyPlayerCollisionGroup(p.Character)
	end
end)
for _, p in ipairs(Players:GetPlayers()) do
	p.CharacterAdded:Connect(applyPlayerCollisionGroup)
	if p.Character then
		applyPlayerCollisionGroup(p.Character)
	end
end

-- Constrói ou remove a barreira de perímetro murado para partidas de Sobrevivência
local perimeterFolder: Folder? = nil
local function setPerimeterLocked(locked: boolean)
	if perimeterFolder then
		perimeterFolder:Destroy()
		perimeterFolder = nil
	end
	if not locked then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "IFSul_SurvivalPerimeter"
	folder.Parent = Workspace
	perimeterFolder = folder

	local pts = SurvivalCatalog.PerimeterPoints
	for i = 1, #pts do
		local a = pts[i]
		local b = pts[(i % #pts) + 1]
		local delta = b - a
		local len = delta.Magnitude
		if len > 0.5 then
			local mid = (a + b) * 0.5 + Vector3.new(0, 18, 0)
			local wall = Instance.new("Part")
			wall.Name = "PerimeterWall_" .. tostring(i)
			wall.Anchored = true
			wall.Transparency = 1
			wall.CanCollide = true
			wall.CanQuery = false
			wall.CanTouch = false
			wall.CollisionGroup = "CampusPerimeterBlock"
			wall.Size = Vector3.new(1.5, 42, len)
			wall.CFrame = CFrame.lookAt(mid, mid + delta.Unit)
			wall.Parent = folder
		end
	end

	-- Posiciona grades prontas da Creator Store nos portões abertos para indicar visualmente o bloqueio
	local assets = ServerStorage:FindFirstChild("IFSul_SurvivalAssets")
	local props = assets and assets:FindFirstChild("Props")
	local fenceContainer = props and props:FindFirstChild("fence_barricade")
	local fenceTemplate = fenceContainer and fenceContainer:FindFirstChildOfClass("Model")
	if fenceTemplate then
		for idx, spec in ipairs(SurvivalCatalog.GateVisualBarricades) do
			local clone = fenceTemplate:Clone()
			clone.Name = "LockedGateFence_" .. tostring(idx)
			for _, bp in ipairs(clone:GetDescendants()) do
				if bp:IsA("BasePart") then
					bp.Anchored = true
					bp.CanCollide = true
					bp.CollisionGroup = "CampusPerimeterBlock"
				end
			end
			clone:PivotTo(CFrame.lookAt(spec.pos + Vector3.new(0, 3.2, 0), spec.lookAt + Vector3.new(0, 3.2, 0)))
			clone.Parent = folder
		end
	end
end

-- Construção visual do Portal de Esquadrão (1 a 6 Jogadores) na Portaria Principal (apenas no Lobby)
local portalFolder: Instance? = nil
local statusLbl: TextLabel? = nil
local timerLbl: TextLabel? = nil
local RING_RADIUS = 11.5

local queuedPlayers: { Player } = {}
local countdown: number = 0
local isTeleporting = false

local function isInQueue(p: Player): boolean
	for _, qp in ipairs(queuedPlayers) do
		if qp == p then
			return true
		end
	end
	return false
end

local function broadcastPortalState()
	local names: { string } = {}
	for _, qp in ipairs(queuedPlayers) do
		table.insert(names, qp.DisplayName)
	end
	local count = #queuedPlayers
	if statusLbl then
		statusLbl.Text = string.format("ESQUADRÃO: %d / %d JOGADORES", count, SurvivalCatalog.MaxPlayersPerSquad)
	end
	if timerLbl then
		if isTeleporting then
			timerLbl.Text = "INICIANDO PARTIDA..."
		elseif count > 0 then
			timerLbl.Text = string.format("Partida inicia em %ds (ou clique em Iniciar Agora)", math.ceil(countdown))
		else
			timerLbl.Text = "Pise no círculo verde para defender o câmpus em ondas!"
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		portalStateRE:FireClient(p, {
			inQueue = isInQueue(p),
			count = count,
			maxPlayers = SurvivalCatalog.MaxPlayersPerSquad,
			countdown = math.ceil(countdown),
			names = names,
			visible = MatchMode.IsLobby(),
		})
	end
end

local function buildLobbyPortal()
	if portalFolder then
		portalFolder:Destroy()
		portalFolder = nil
	end
	if MatchMode.IsSurvival() then
		return
	end

	local folder = Instance.new("Model")
	folder.Name = "IFSul_SurvivalLobbyPortal"
	folder.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	folder.Parent = Workspace
	portalFolder = folder :: any

	local center = SurvivalCatalog.LobbyPortalPosition

	-- Plataforma circular luminosa no chão
	local pad = Instance.new("Part")
	pad.Name = "SquadPad"
	pad.Shape = Enum.PartType.Cylinder
	pad.Anchored = true
	pad.CanCollide = false
	pad.Material = Enum.Material.Neon
	pad.Color = Config.Colors.IFSulGreen
	pad.Transparency = 0.35
	pad.Size = Vector3.new(0.35, RING_RADIUS * 2, RING_RADIUS * 2)
	pad.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	pad.Parent = folder

	local innerPad = Instance.new("Part")
	innerPad.Name = "SquadPadInner"
	innerPad.Shape = Enum.PartType.Cylinder
	innerPad.Anchored = true
	innerPad.CanCollide = false
	innerPad.Material = Enum.Material.SmoothPlastic
	innerPad.Color = Color3.fromRGB(20, 30, 26)
	innerPad.Transparency = 0.2
	innerPad.Size = Vector3.new(0.38, (RING_RADIUS - 1.1) * 2, (RING_RADIUS - 1.1) * 2)
	innerPad.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	innerPad.Parent = folder

	-- Props prontos da Creator Store nas laterais do portal (Caixas Táticas + Torreta)
	local assets = ServerStorage:FindFirstChild("IFSul_SurvivalAssets")
	local props = assets and assets:FindFirstChild("Props")
	local crateModel = props and props:FindFirstChild("ammo_crate") and props.ammo_crate:FindFirstChildOfClass("Model")
	if crateModel then
		local cClone = crateModel:Clone()
		cClone:PivotTo(CFrame.new(center + Vector3.new(-8.5, 1.8, -6.5)) * CFrame.Angles(0, math.rad(25), 0))
		cClone.Parent = folder
	end
	local turretModel = props and props:FindFirstChild("sentry_turret") and props.sentry_turret:FindFirstChildOfClass("Model")
	if turretModel then
		local tClone = turretModel:Clone()
		tClone:PivotTo(CFrame.new(center + Vector3.new(8.5, 2.0, -6.5)) * CFrame.Angles(0, math.rad(-30), 0))
		tClone.Parent = folder
	end

	-- Painel Totem com o Banner gerado no Nano Banana
	local boardPos = center + Vector3.new(0, 6.8, -9.5)
	local board = Instance.new("Part")
	board.Name = "PortalBillboardPart"
	board.Anchored = true
	board.CanCollide = false
	board.Color = Config.Colors.PanelBg
	board.Material = Enum.Material.SmoothPlastic
	board.Size = Vector3.new(15.5, 9.2, 0.5)
	board.CFrame = CFrame.lookAt(boardPos, center + Vector3.new(0, 5.2, 6))
	board.Parent = folder

	for _, side in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = Instance.new("SurfaceGui")
		sg.Face = side
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 55
		sg.LightInfluence = 0.15
		sg.Parent = board

		local rootFrame = Instance.new("Frame")
		rootFrame.Size = UDim2.fromScale(1, 1)
		rootFrame.BackgroundColor3 = Config.Colors.PanelBg
		rootFrame.BorderSizePixel = 0
		rootFrame.Parent = sg

		local stroke = Instance.new("UIStroke")
		stroke.Color = Config.Colors.IFSulGreen
		stroke.Thickness = 6
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = rootFrame

		local bannerImg = Instance.new("ImageLabel")
		bannerImg.Size = UDim2.fromScale(1, 0.62)
		bannerImg.BackgroundColor3 = Color3.fromRGB(12, 16, 22)
		bannerImg.BorderSizePixel = 0
		bannerImg.ScaleType = Enum.ScaleType.Crop
		bannerImg.Image = SurvivalCatalog.UIArt.PortalBanner
		bannerImg.Parent = rootFrame

		local badge = Instance.new("TextLabel")
		badge.Size = UDim2.fromScale(0.92, 0.14)
		badge.Position = UDim2.fromScale(0.04, 0.46)
		badge.BackgroundColor3 = Color3.fromRGB(16, 22, 28)
		badge.BackgroundTransparency = 0.18
		badge.Font = Enum.Font.GothamBlack
		badge.TextScaled = true
		badge.TextColor3 = Color3.fromRGB(250, 204, 21)
		badge.Text = "🛡️ MODO SOBREVIVÊNCIA EM ONDAS • IFSUL"
		badge.Parent = rootFrame

		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 10)
		bc.Parent = badge

		local sLbl = Instance.new("TextLabel")
		sLbl.Size = UDim2.fromScale(0.92, 0.15)
		sLbl.Position = UDim2.fromScale(0.04, 0.65)
		sLbl.BackgroundTransparency = 1
		sLbl.Font = Enum.Font.GothamBlack
		sLbl.TextScaled = true
		sLbl.TextColor3 = Color3.new(1, 1, 1)
		sLbl.Text = "ESQUADRÃO: 0 / 6 JOGADORES"
		sLbl.Parent = rootFrame

		local tLbl = Instance.new("TextLabel")
		tLbl.Size = UDim2.fromScale(0.92, 0.13)
		tLbl.Position = UDim2.fromScale(0.04, 0.82)
		tLbl.BackgroundTransparency = 1
		tLbl.Font = Enum.Font.GothamSemibold
		tLbl.TextScaled = true
		tLbl.TextColor3 = Color3.fromRGB(168, 224, 182)
		tLbl.Text = "Pise no círculo verde para defender o câmpus em ondas!"
		tLbl.Parent = rootFrame

		if side == Enum.NormalId.Front then
			statusLbl = sLbl
			timerLbl = tLbl
		end
	end

	-- Marcador flutuante visível de longe na entrada
	local bbg = Instance.new("BillboardGui")
	bbg.Size = UDim2.fromOffset(240, 54)
	bbg.StudsOffset = Vector3.new(0, 6.2, 0)
	bbg.MaxDistance = 260
	bbg.AlwaysOnTop = false
	bbg.Parent = board

	local pill = Instance.new("Frame")
	pill.Size = UDim2.fromScale(1, 1)
	pill.BackgroundColor3 = Color3.fromRGB(16, 24, 20)
	pill.BackgroundTransparency = 0.12
	pill.Parent = bbg

	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(1, 0)
	pc.Parent = pill

	local ps = Instance.new("UIStroke")
	ps.Color = Color3.fromRGB(250, 204, 21)
	ps.Thickness = 2
	ps.Parent = pill

	local pText = Instance.new("TextLabel")
	pText.Size = UDim2.fromScale(0.9, 0.8)
	pText.Position = UDim2.fromScale(0.05, 0.1)
	pText.BackgroundTransparency = 1
	pText.Font = Enum.Font.GothamBlack
	pText.TextScaled = true
	pText.TextColor3 = Color3.fromRGB(250, 204, 21)
	pText.Text = "🧟 DEFENDER CÂMPUS (1–6)"
	pText.Parent = pill
end

local function launchSquadMatch()
	if isTeleporting or #queuedPlayers == 0 then
		return
	end
	isTeleporting = true
	broadcastPortalState()

	local squad = table.clone(queuedPlayers)
	table.clear(queuedPlayers)

	-- No Roblox Studio, ReserveServer não é suportado pela engine local:
	-- fazemos a transição ao vivo para o Modo Sobrevivência para testar tudo instantaneamente!
	if RunService:IsStudio() or game.PlaceId == 0 then
		MatchMode.SetSurvivalServer(true)
		isTeleporting = false
		return
	end

	local ok, err = pcall(function()
		local accessCode = TeleportService:ReserveServer(game.PlaceId)
		TeleportService:TeleportToPrivateServer(game.PlaceId, accessCode, squad)
	end)
	if not ok then
		warn("[LobbyPortal] ReserveServer falhou, iniciando partida local de fallback:", err)
		MatchMode.SetSurvivalServer(true)
	end
	isTeleporting = false
end

portalActionRE.OnServerEvent:Connect(function(player: Player, action: unknown)
	if MatchMode.IsSurvival() then
		if action == "ReturnToLobby" then
			if RunService:IsStudio() or game.PlaceId == 0 then
				MatchMode.SetSurvivalServer(false)
			else
				pcall(function()
					TeleportService:TeleportAsync(game.PlaceId, { player })
				end)
			end
		end
		return
	end

	if action == "StartNow" and isInQueue(player) then
		launchSquadMatch()
	elseif action == "LeaveQueue" then
		for i = #queuedPlayers, 1, -1 do
			if queuedPlayers[i] == player then
				table.remove(queuedPlayers, i)
			end
		end
		if #queuedPlayers == 0 then
			countdown = 0
		end
		broadcastPortalState()
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	for i = #queuedPlayers, 1, -1 do
		if queuedPlayers[i] == player then
			table.remove(queuedPlayers, i)
		end
	end
end)

local function refreshForMode(isSurvival: boolean)
	table.clear(queuedPlayers)
	countdown = 0
	isTeleporting = false
	setPerimeterLocked(isSurvival)
	if isSurvival then
		if portalFolder then
			portalFolder:Destroy()
			portalFolder = nil
		end
	else
		buildLobbyPortal()
	end
	broadcastPortalState()
end

refreshForMode(MatchMode.IsSurvival())
MatchMode.OnChanged(refreshForMode)

-- Loop leve (4x por segundo) para detectar jogadores dentro do círculo da Portaria
task.spawn(function()
	while true do
		task.wait(0.25)
		if MatchMode.IsLobby() and not isTeleporting then
			local center = SurvivalCatalog.LobbyPortalPosition
			local changed = false

			-- Remove quem saiu da área física
			for i = #queuedPlayers, 1, -1 do
				local p = queuedPlayers[i]
				local char = p.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if not p.Parent or not hrp or not hum or hum.Health <= 0 then
					table.remove(queuedPlayers, i)
					changed = true
				else
					local flatDist = Vector2.new(hrp.Position.X - center.X, hrp.Position.Z - center.Z).Magnitude
					if flatDist > RING_RADIUS + 1.8 then
						table.remove(queuedPlayers, i)
						changed = true
					end
				end
			end

			-- Adiciona quem entrou no círculo (até 6 jogadores)
			if #queuedPlayers < SurvivalCatalog.MaxPlayersPerSquad then
				for _, p in ipairs(Players:GetPlayers()) do
					if not isInQueue(p) and #queuedPlayers < SurvivalCatalog.MaxPlayersPerSquad then
						local char = p.Character
						local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
						local hum = char and char:FindFirstChildOfClass("Humanoid")
						if hrp and hum and hum.Health > 0 then
							local flatDist = Vector2.new(hrp.Position.X - center.X, hrp.Position.Z - center.Z).Magnitude
							if flatDist <= RING_RADIUS and math.abs(hrp.Position.Y - center.Y) < 12 then
								if #queuedPlayers == 0 then
									countdown = 12
								end
								table.insert(queuedPlayers, p)
								changed = true
							end
						end
					end
				end
			end

			if #queuedPlayers > 0 then
				countdown = math.max(0, countdown - 0.25)
				broadcastPortalState()
				if countdown <= 0 then
					launchSquadMatch()
				end
			elseif changed then
				countdown = 0
				broadcastPortalState()
			end
		end
	end
end)
