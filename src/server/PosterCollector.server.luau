--!strict
-- Sistema de Cartazes Colecionáveis nos corredores do IFSul — Câmpus Sapucaia do Sul
-- Detecta dinamicamente paredes livres nos corredores (sem sobrescrever edições manuais do mapa),
-- gera cartazes com frases por raridade e recompensa o jogador em moedas ao coletar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local IFSulFolder = ReplicatedStorage:WaitForChild("IFSul")
local CampusData = require(IFSulFolder:WaitForChild("CampusData"))
local MatchMode = require(IFSulFolder:WaitForChild("MatchMode"))

local remotes = IFSulFolder:FindFirstChild("Remotes") :: Folder?
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = IFSulFolder
end

local posterObservedRE = remotes:FindFirstChild("PosterObserved") :: RemoteEvent?
if not posterObservedRE then
	local re = Instance.new("RemoteEvent")
	re.Name = "PosterObserved"
	re.Parent = remotes
	posterObservedRE = re
end

type PosterDef = {
	phrase: string,
	rarity: "Comum" | "Incomum" | "Raro",
	reward: number,
	bgColor: Color3,
	headerColor: Color3,
	textColor: Color3,
	borderColor: Color3,
	isTransPride: boolean?,
}

local RARE_POSTERS: { PosterDef } = {
	{
		phrase = "Respeite crianças trans",
		rarity = "Raro",
		reward = 100,
		bgColor = Color3.fromRGB(252, 249, 255),
		headerColor = Color3.fromRGB(91, 206, 250),
		textColor = Color3.fromRGB(28, 22, 42),
		borderColor = Color3.fromRGB(255, 204, 48),
		isTransPride = true,
	},
}

local UNCOMMON_POSTERS: { PosterDef } = {
	{
		phrase = "Respeite os pronomes — todos os corpos importam",
		rarity = "Incomum",
		reward = 25,
		bgColor = Color3.fromRGB(247, 240, 255),
		headerColor = Color3.fromRGB(132, 68, 204),
		textColor = Color3.fromRGB(32, 20, 48),
		borderColor = Color3.fromRGB(154, 92, 226),
	},
	{
		phrase = "Todas as formas de amor importam",
		rarity = "Incomum",
		reward = 25,
		bgColor = Color3.fromRGB(255, 242, 247),
		headerColor = Color3.fromRGB(218, 58, 122),
		textColor = Color3.fromRGB(48, 18, 32),
		borderColor = Color3.fromRGB(232, 84, 142),
	},
	{
		phrase = "Luta antirracista todo dia",
		rarity = "Incomum",
		reward = 25,
		bgColor = Color3.fromRGB(255, 248, 236),
		headerColor = Color3.fromRGB(184, 94, 24),
		textColor = Color3.fromRGB(42, 24, 12),
		borderColor = Color3.fromRGB(214, 122, 42),
	},
	{
		phrase = "Cotas salvam vidas e transformam o Brasil",
		rarity = "Incomum",
		reward = 25,
		bgColor = Color3.fromRGB(240, 252, 245),
		headerColor = Color3.fromRGB(34, 146, 78),
		textColor = Color3.fromRGB(18, 42, 28),
		borderColor = Color3.fromRGB(52, 172, 98),
	},
	{
		phrase = "Direitos humanos são para todes",
		rarity = "Incomum",
		reward = 25,
		bgColor = Color3.fromRGB(240, 247, 255),
		headerColor = Color3.fromRGB(46, 114, 204),
		textColor = Color3.fromRGB(20, 32, 52),
		borderColor = Color3.fromRGB(76, 142, 224),
	},
}

local COMMON_POSTERS: { PosterDef } = {
	{
		phrase = "Educação pública, gratuita e de qualidade",
		rarity = "Comum",
		reward = 10,
		bgColor = Color3.fromRGB(244, 252, 244),
		headerColor = Color3.fromRGB(47, 158, 65),
		textColor = Color3.fromRGB(22, 36, 26),
		borderColor = Color3.fromRGB(47, 158, 65),
	},
	{
		phrase = "Mais diversidade, menos preconceito",
		rarity = "Comum",
		reward = 10,
		bgColor = Color3.fromRGB(255, 252, 235),
		headerColor = Color3.fromRGB(222, 152, 28),
		textColor = Color3.fromRGB(42, 32, 14),
		borderColor = Color3.fromRGB(222, 152, 28),
	},
	{
		phrase = "Lugar de mulher é onde ela quiser",
		rarity = "Comum",
		reward = 10,
		bgColor = Color3.fromRGB(254, 242, 252),
		headerColor = Color3.fromRGB(178, 56, 156),
		textColor = Color3.fromRGB(44, 18, 40),
		borderColor = Color3.fromRGB(178, 56, 156),
	},
	{
		phrase = "Defenda o ensino público e a ciência",
		rarity = "Comum",
		reward = 10,
		bgColor = Color3.fromRGB(240, 249, 255),
		headerColor = Color3.fromRGB(36, 128, 188),
		textColor = Color3.fromRGB(18, 36, 50),
		borderColor = Color3.fromRGB(36, 128, 188),
	},
	{
		phrase = "Câmpus inclusivo: fora todo preconceito",
		rarity = "Comum",
		reward = 10,
		bgColor = Color3.fromRGB(255, 245, 240),
		headerColor = Color3.fromRGB(206, 72, 48),
		textColor = Color3.fromRGB(48, 22, 16),
		borderColor = Color3.fromRGB(206, 72, 48),
	},
	{
		phrase = "Respeito às pessoas LGBTQIA+",
		rarity = "Comum",
		reward = 10,
		bgColor = Color3.fromRGB(246, 244, 255),
		headerColor = Color3.fromRGB(108, 76, 206),
		textColor = Color3.fromRGB(28, 22, 52),
		borderColor = Color3.fromRGB(108, 76, 206),
	},
	{
		phrase = "Nenhum direito a menos",
		rarity = "Comum",
		reward = 10,
		bgColor = Color3.fromRGB(255, 244, 244),
		headerColor = Color3.fromRGB(198, 42, 52),
		textColor = Color3.fromRGB(46, 18, 20),
		borderColor = Color3.fromRGB(198, 42, 52),
	},
	{
		phrase = "Por um câmpus livre de machismo e LGBTfobia",
		rarity = "Comum",
		reward = 10,
		bgColor = Color3.fromRGB(242, 252, 250),
		headerColor = Color3.fromRGB(28, 148, 132),
		textColor = Color3.fromRGB(18, 42, 38),
		borderColor = Color3.fromRGB(28, 148, 132),
	},
}

local POSTER_WIDTH = 2.8
local POSTER_HEIGHT = 3.6
local POSTER_THICKNESS = 0.12
local POSTER_Y = 6.3
local MIN_SPOT_SPACING = 26
local MAX_OBSERVE_DISTANCE = 18

local rng = Random.new()

-- Rastreia quais cartazes cada jogador já observou (impede ganhar moedas 2x no mesmo cartaz)
local observedByPlayer: { [Player]: { [number]: boolean } } = {}

-- Inicializa atributo de moedas ao entrar
local function ensureCoinsAttribute(player: Player)
	if player:GetAttribute("Coins") == nil then
		player:SetAttribute("Coins", 0)
	end
	observedByPlayer[player] = observedByPlayer[player] or {}
end

Players.PlayerAdded:Connect(ensureCoinsAttribute)
Players.PlayerRemoving:Connect(function(player: Player)
	observedByPlayer[player] = nil
end)
for _, p in ipairs(Players:GetPlayers()) do
	ensureCoinsAttribute(p)
end

local function isInsideAnyRoom(pos: Vector3): boolean
	for _, room in ipairs(CampusData.Rooms) do
		local dx = pos.X - room.center.X
		local dz = pos.Z - room.center.Z
		local halfW = room.size.X * 0.5
		local halfD = room.size.Y * 0.5
		if math.abs(dx) <= halfW + 1 and math.abs(dz) <= halfD + 1 then
			local rad = math.rad(-room.rotDeg)
			local c, s = math.cos(rad), math.sin(rad)
			local lx = dx * c - dz * s
			local lz = dx * s + dz * c
			if math.abs(lx) <= halfW - 0.3 and math.abs(lz) <= halfD - 0.3 then
				return true
			end
		end
	end
	return false
end

type WallSpot = {
	cframe: CFrame,
	position: Vector3,
}

local function findCorridorWallSpots(campus: Instance): { WallSpot }
	local interiors = campus:FindFirstChild("Interiors")
	local ie = interiors and interiors:FindFirstChild("InteriorEnhanced")
	local wallsFolder = ie and ie:FindFirstChild("WallsAndDado")
	if not wallsFolder then
		return {}
	end

	local filterList: { Instance } = {}
	for _, name in ipairs({ "Buildings", "Interiors", "Signage" }) do
		local child = campus:FindFirstChild(name)
		if child then
			table.insert(filterList, child)
		end
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = filterList

	local spots: { WallSpot } = {}

	for _, desc in ipairs(wallsFolder:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name == "CorridorGreenDado" then
			local len: number
			local thick: number
			local normal: Vector3
			local tangent: Vector3
			if desc.Size.X >= desc.Size.Z then
				len = desc.Size.X
				thick = desc.Size.Z
				normal = desc.CFrame.LookVector
				tangent = desc.CFrame.RightVector
			else
				len = desc.Size.Z
				thick = desc.Size.X
				normal = desc.CFrame.RightVector
				tangent = desc.CFrame.LookVector
			end

			if len >= 6.5 and thick <= 1.2 then
				local basePos = Vector3.new(desc.Position.X, POSTER_Y, desc.Position.Z)
				for _, sign in ipairs({ 1, -1 }) do
					local n = Vector3.new(normal.X * sign, 0, normal.Z * sign).Unit
					local frontPos = basePos + n * (thick * 0.5 + 0.15)
					local testCorridorPos = frontPos + n * 3.0

					if not isInsideAnyRoom(testCorridorPos) then
						local backHit = Workspace:Raycast(frontPos + n * 1.0, -n * 2.4, rayParams)
						local frontHit = Workspace:Raycast(frontPos + n * 0.3, n * 4.5, rayParams)
						if backHit and not frontHit then
							-- Garante que as laterais do cartaz também encostam em parede sólida
							local tFlat = Vector3.new(tangent.X, 0, tangent.Z).Unit
							local leftBack = Workspace:Raycast(frontPos + tFlat * 1.3 + n * 1.0, -n * 2.4, rayParams)
							local rightBack = Workspace:Raycast(frontPos - tFlat * 1.3 + n * 1.0, -n * 2.4, rayParams)
							if leftBack and rightBack then
								local hitNormal = Vector3.new(backHit.Normal.X, 0, backHit.Normal.Z)
								if hitNormal.Magnitude > 0.1 then
									hitNormal = hitNormal.Unit
									local wallPoint = backHit.Position + hitNormal * (POSTER_THICKNESS * 0.5 + 0.04)
									local tooClose = false
									for _, existing in ipairs(spots) do
										if (existing.position - wallPoint).Magnitude < MIN_SPOT_SPACING then
											tooClose = true
											break
										end
									end
									if not tooClose then
										-- Front face (-Z) aponta para fora da parede (hitNormal)
										local cf = CFrame.lookAt(wallPoint, wallPoint + hitNormal, Vector3.yAxis)
										table.insert(spots, {
											cframe = cf,
											position = wallPoint,
										})
										break
									end
								end
							end
						end
					end
				end
			end
		end
	end

	return spots
end

local function rollPosterDef(forceRare: boolean?): PosterDef
	if forceRare then
		return RARE_POSTERS[rng:NextInteger(1, #RARE_POSTERS)]
	end
	local roll = rng:NextNumber()
	if roll < 0.06 then
		return RARE_POSTERS[rng:NextInteger(1, #RARE_POSTERS)]
	elseif roll < 0.34 then
		return UNCOMMON_POSTERS[rng:NextInteger(1, #UNCOMMON_POSTERS)]
	end
	return COMMON_POSTERS[rng:NextInteger(1, #COMMON_POSTERS)]
end

local function buildPosterVisual(part: BasePart, def: PosterDef)
	-- Limpa visuais antigos ao respawnar
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("SurfaceGui") or child:IsA("PointLight") or child:IsA("Sparkles") then
			child:Destroy()
		end
	end

	part.Color = def.borderColor
	part.Material = if def.rarity == "Raro" then Enum.Material.Neon else Enum.Material.SmoothPlastic

	local gui = Instance.new("SurfaceGui")
	gui.Name = "PosterGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 75
	gui.LightInfluence = if def.rarity == "Raro" then 0.25 else 0.75
	gui.AlwaysOnTop = false
	gui.Parent = part

	local bg = Instance.new("Frame")
	bg.Name = "Canvas"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = def.bgColor
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local border = Instance.new("UIStroke")
	border.Color = def.borderColor
	border.Thickness = if def.rarity == "Raro" then 8 else 5
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Parent = bg

	-- Fitas adesivas decorativas nos cantos superiores
	for _, xPos in ipairs({ 0.06, 0.76 }) do
		local tape = Instance.new("Frame")
		tape.Size = UDim2.fromScale(0.18, 0.045)
		tape.Position = UDim2.fromScale(xPos, 0.012)
		tape.BackgroundColor3 = Color3.fromRGB(235, 224, 186)
		tape.BackgroundTransparency = 0.25
		tape.BorderSizePixel = 0
		tape.ZIndex = 4
		tape.Parent = bg
	end

	-- Faixa superior (bandeira trans estilizada no cartaz raro, ou faixa colorida nos demais)
	if def.isTransPride then
		local stripeColors = {
			Color3.fromRGB(91, 206, 250),
			Color3.fromRGB(245, 169, 184),
			Color3.fromRGB(255, 255, 255),
			Color3.fromRGB(245, 169, 184),
			Color3.fromRGB(91, 206, 250),
		}
		for i, col in ipairs(stripeColors) do
			local stripe = Instance.new("Frame")
			stripe.Size = UDim2.fromScale(1, 0.036)
			stripe.Position = UDim2.fromScale(0, (i - 1) * 0.036)
			stripe.BackgroundColor3 = col
			stripe.BorderSizePixel = 0
			stripe.Parent = bg
		end
	else
		local header = Instance.new("Frame")
		header.Size = UDim2.fromScale(1, 0.16)
		header.BackgroundColor3 = def.headerColor
		header.BorderSizePixel = 0
		header.Parent = bg

		local headerLbl = Instance.new("TextLabel")
		headerLbl.Size = UDim2.fromScale(0.92, 0.75)
		headerLbl.Position = UDim2.fromScale(0.04, 0.14)
		headerLbl.BackgroundTransparency = 1
		headerLbl.Font = Enum.Font.GothamBold
		headerLbl.TextScaled = true
		headerLbl.TextColor3 = Color3.new(1, 1, 1)
		headerLbl.Text = "MURAL ESTUDANTIL • IFSUL"
		headerLbl.Parent = header
	end

	-- Frase principal
	local phraseLbl = Instance.new("TextLabel")
	phraseLbl.Name = "Phrase"
	phraseLbl.Size = UDim2.fromScale(0.86, 0.56)
	phraseLbl.Position = UDim2.fromScale(0.07, 0.22)
	phraseLbl.BackgroundTransparency = 1
	phraseLbl.Font = Enum.Font.GothamBlack
	phraseLbl.TextWrapped = true
	phraseLbl.TextScaled = true
	phraseLbl.TextColor3 = def.textColor
	phraseLbl.Text = string.upper(def.phrase)
	phraseLbl.Parent = bg

	local phraseConstraint = Instance.new("UITextSizeConstraint")
	phraseConstraint.MaxTextSize = 36
	phraseConstraint.MinTextSize = 14
	phraseConstraint.Parent = phraseLbl

	-- Rodapé com raridade e recompensa em moedas
	local footer = Instance.new("Frame")
	footer.Size = UDim2.fromScale(0.88, 0.14)
	footer.Position = UDim2.fromScale(0.06, 0.81)
	footer.BackgroundColor3 = if def.rarity == "Raro"
		then Color3.fromRGB(255, 204, 48)
		else def.headerColor
	footer.BorderSizePixel = 0
	footer.Parent = bg

	local footerCorner = Instance.new("UICorner")
	footerCorner.CornerRadius = UDim.new(0, 8)
	footerCorner.Parent = footer

	local footerLbl = Instance.new("TextLabel")
	footerLbl.Size = UDim2.fromScale(0.92, 0.8)
	footerLbl.Position = UDim2.fromScale(0.04, 0.1)
	footerLbl.BackgroundTransparency = 1
	footerLbl.Font = Enum.Font.GothamBlack
	footerLbl.TextScaled = true
	footerLbl.TextColor3 = if def.rarity == "Raro" then Color3.fromRGB(26, 20, 10) else Color3.new(1, 1, 1)
	footerLbl.TextWrapped = false
	footerLbl.Text = if def.rarity == "Raro"
		then ("★ RARO • +" .. tostring(def.reward) .. " ★")
		else (string.upper(def.rarity) .. " • +" .. tostring(def.reward))
	footerLbl.Parent = footer

	if def.rarity == "Raro" then
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 214, 92)
		glow.Brightness = 0.8
		glow.Range = 8
		glow.Parent = part

		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Color3.fromRGB(255, 215, 70)
		sparkles.Parent = part
	end
end

local function spawnPosters()
	local campus = Workspace:WaitForChild("IFSul_Campus", 15)
	if not campus then
		warn("[PosterCollector] Workspace.IFSul_Campus não encontrado.")
		return
	end

	local oldFolder = campus:FindFirstChild("CollectiblePosters")
	if oldFolder then
		oldFolder:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "CollectiblePosters"
	folder.Parent = campus

	local spots = findCorridorWallSpots(campus)
	if #spots == 0 then
		warn("[PosterCollector] Nenhum ponto de parede de corredor encontrado.")
		return
	end

	-- Embaralha os pontos e garante pelo menos 2 cartazes raros no início
	local indices: { number } = {}
	for i = 1, #spots do
		indices[i] = i
	end
	for i = #indices, 2, -1 do
		local j = rng:NextInteger(1, i)
		indices[i], indices[j] = indices[j], indices[i]
	end

	local guaranteedRare = math.min(2, #spots)

	for order, spotIdx in ipairs(indices) do
		local spot = spots[spotIdx]
		local currentDef = rollPosterDef(order <= guaranteedRare)

		local part = Instance.new("Part")
		part.Name = "CollectiblePoster_" .. tostring(order)
		part.Size = Vector3.new(POSTER_WIDTH, POSTER_HEIGHT, POSTER_THICKNESS)
		part.CFrame = spot.cframe
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CastShadow = false
		part.Parent = folder

		buildPosterVisual(part, currentDef)

		local sound = Instance.new("Sound")
		sound.Name = "ObserveSound"
		sound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
		sound.Volume = 0.55
		sound.Parent = part

		local promptAnchor = Instance.new("Attachment")
		promptAnchor.Name = "PromptAnchor"
		-- Posiciona o prompt abaixo da borda inferior do cartaz (sobre o barrado verde),
		-- mantendo 100% da frase legível ao se aproximar.
		promptAnchor.Position = Vector3.new(0, -(POSTER_HEIGHT * 0.5 + 0.85), -0.1)
		promptAnchor.Parent = part

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "CollectPrompt"
		prompt.ActionText = "Observar"
		prompt.ObjectText = if currentDef.rarity == "Raro"
			then ("+" .. tostring(currentDef.reward) .. " • Raro")
			else ("+" .. tostring(currentDef.reward) .. " moedas")
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0.2
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.UIOffset = Vector2.new(0, 12)
		prompt.Parent = promptAnchor

		prompt.Triggered:Connect(function(player: Player)
			if MatchMode.IsSurvival() then
				return
			end
			observedByPlayer[player] = observedByPlayer[player] or {}
			if observedByPlayer[player][order] then
				return
			end
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hrp or (hrp.Position - part.Position).Magnitude > MAX_OBSERVE_DISTANCE then
				return
			end

			observedByPlayer[player][order] = true

			-- Recompensa em moedas (o cartaz permanece visível na parede, mas só dá moedas 1x por jogador)
			local prev = player:GetAttribute("Coins")
			local currentCoins = if typeof(prev) == "number" then prev else 0
			player:SetAttribute("Coins", currentCoins + currentDef.reward)

			sound.PlaybackSpeed = if currentDef.rarity == "Raro" then 1.35 else 1.05
			sound:Play()

			-- Desativa o prompt localmente apenas para este jogador
			if posterObservedRE then
				posterObservedRE:FireClient(player, part.Name)
			end
		end)
	end
end

if not MatchMode.IsSurvival() then
	spawnPosters()
end

MatchMode.OnChanged(function(isSurvival: boolean)
	local campus = Workspace:FindFirstChild("IFSul_Campus")
	local folder = campus and campus:FindFirstChild("CollectiblePosters")
	if isSurvival then
		if folder then
			folder:Destroy()
		end
	else
		if not folder then
			spawnPosters()
		end
	end
end)
