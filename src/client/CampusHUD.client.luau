--!strict
-- HUD institucional do IFSul — Câmpus Sapucaia do Sul (Roblox)
-- Exibe localização em tempo real (sala/setor), Buscador de Salas/POIs [G],
-- alternância Dia/Noite local [N], Sprint [Shift] e boas-vindas responsivas para PC e Mobile.

local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local IFSulFolder = ReplicatedStorage:WaitForChild("IFSul")
local Config = require(IFSulFolder:WaitForChild("Config"))
local CampusData = require(IFSulFolder:WaitForChild("CampusData"))
local remotes = IFSulFolder:WaitForChild("Remotes")
local teleportRemote = remotes:WaitForChild("TeleportToLocation") :: RemoteEvent

local isTouchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Remove HUD antigo se recarregado
local oldGui = playerGui:FindFirstChild("IFSulHUD")
if oldGui then
	oldGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "IFSulHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- Container superior esquerdo (responsivo para Desktop e Mobile)
local topContainer = Instance.new("Frame")
topContainer.Name = "TopLeftContainer"
topContainer.Size = UDim2.new(0.46, 0, 0, 52)
topContainer.Position = UDim2.fromOffset(12, 10)
topContainer.BackgroundTransparency = 1
topContainer.Parent = screenGui

local topConstraint = Instance.new("UISizeConstraint")
topConstraint.MinSize = Vector2.new(240, 52)
topConstraint.MaxSize = Vector2.new(390, 56)
topConstraint.Parent = topContainer

-- Pílula de localização (título + sala atual)
local topPill = Instance.new("Frame")
topPill.Name = "LocationPill"
topPill.Size = UDim2.new(1, 0, 0, 52)
topPill.Position = UDim2.fromOffset(0, 0)
topPill.BackgroundColor3 = Config.Colors.PanelBg
topPill.BackgroundTransparency = 0.12
topPill.Parent = topContainer

local pillCorner = Instance.new("UICorner")
pillCorner.CornerRadius = UDim.new(0, 10)
pillCorner.Parent = topPill

local pillStroke = Instance.new("UIStroke")
pillStroke.Color = Config.Colors.PanelBorder
pillStroke.Thickness = 1.5
pillStroke.Parent = topPill

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -20, 0, 20)
titleLbl.Position = UDim2.fromOffset(10, 5)
titleLbl.BackgroundTransparency = 1
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 13
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.TextTruncate = Enum.TextTruncate.AtEnd
titleLbl.TextColor3 = Config.Colors.IFSulGreen
titleLbl.Text = Config.CampusName
titleLbl.Parent = topPill

local locLbl = Instance.new("TextLabel")
locLbl.Size = UDim2.new(1, -20, 0, 20)
locLbl.Position = UDim2.fromOffset(10, 26)
locLbl.BackgroundTransparency = 1
locLbl.Font = Enum.Font.Gotham
locLbl.TextSize = 12
locLbl.TextXAlignment = Enum.TextXAlignment.Left
locLbl.TextTruncate = Enum.TextTruncate.AtEnd
locLbl.TextColor3 = Config.Colors.TextPrimary
locLbl.Text = "Área Externa do Câmpus"
locLbl.Parent = topPill

-- Lógica de Sprint (Shift no PC e botão padrão de correr no celular)
local isSprinting = false

local function applySprintToCharacter(char: Model?)
	if not char then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = if isSprinting then Config.SprintSpeed else Config.WalkSpeed
	end
end

local function setSprinting(active: boolean)
	isSprinting = active
	applySprintToCharacter(player.Character)
end

player.CharacterAdded:Connect(function(char: Model)
	char:WaitForChild("Humanoid")
	applySprintToCharacter(char)
end)

local function handleSprintAction(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject)
	if inputState == Enum.UserInputState.Begin then
		setSprinting(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		setSprinting(false)
	end
	return Enum.ContextActionResult.Pass
end

ContextActionService:BindAction(
	"IFSulSprint",
	handleSprintAction,
	true,
	Enum.KeyCode.LeftShift,
	Enum.KeyCode.RightShift
)
ContextActionService:SetTitle("IFSulSprint", "Correr")

-- Lógica de Dia / Noite LOCAL (cada jogador escolhe seu horário sem afetar outros jogadores)
local isNight = false

local function applyLocalLighting(night: boolean)
	isNight = night
	local preset = if night then Config.Lighting.Night else Config.Lighting.Day
	Lighting.ClockTime = preset.ClockTime
	Lighting.Brightness = preset.Brightness
	Lighting.OutdoorAmbient = preset.OutdoorAmbient
	Lighting.GeographicLatitude = Config.GeographicLatitude

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = preset.AtmosphereDensity
		atmosphere.Color = preset.AtmosphereColor
		atmosphere.Decay = preset.AtmosphereDecay
		atmosphere.Haze = preset.AtmosphereHaze
	end

	local campus = Workspace:FindFirstChild("IFSul_Campus")
	if campus then
		local lightsFolder = campus:FindFirstChild("Lights")
		if lightsFolder then
			for _, desc in ipairs(lightsFolder:GetDescendants()) do
				if desc:IsA("PointLight") then
					local alwaysOn = desc:GetAttribute("AlwaysOn") == true
					desc.Enabled = alwaysOn or night
					if alwaysOn then
						local targetB = if night then desc:GetAttribute("NightBrightness") else desc:GetAttribute("DayBrightness")
						if typeof(targetB) == "number" then
							desc.Brightness = targetB
						end
					end
				end
			end
		end
	end
end

-- Backdrop clicável para fechar o modal no celular ou PC
local modalBackdrop = Instance.new("TextButton")
modalBackdrop.Name = "RoomFinderBackdrop"
modalBackdrop.Size = UDim2.fromScale(1, 1)
modalBackdrop.BackgroundColor3 = Color3.new(0, 0, 0)
modalBackdrop.BackgroundTransparency = 0.55
modalBackdrop.Text = ""
modalBackdrop.AutoButtonColor = false
modalBackdrop.Visible = false
modalBackdrop.ZIndex = 10
modalBackdrop.Parent = screenGui

-- Modal Buscador de Salas & POIs (responsivo para celular paisagem e desktop)
local modal = Instance.new("Frame")
modal.Name = "RoomFinder"
modal.AnchorPoint = Vector2.new(0.5, 0.5)
modal.Position = UDim2.fromScale(0.5, 0.5)
modal.Size = UDim2.fromScale(0.86, 0.78)
modal.BackgroundColor3 = Config.Colors.PanelBg
modal.BackgroundTransparency = 0.05
modal.ZIndex = 11
modal.Parent = modalBackdrop

local modalConstraint = Instance.new("UISizeConstraint")
modalConstraint.MinSize = Vector2.new(260, 220)
modalConstraint.MaxSize = Vector2.new(460, 480)
modalConstraint.Parent = modal

local modalCorner = Instance.new("UICorner")
modalCorner.CornerRadius = UDim.new(0, 12)
modalCorner.Parent = modal

local modalStroke = Instance.new("UIStroke")
modalStroke.Color = Config.Colors.PanelBorder
modalStroke.Thickness = 1.8
modalStroke.Parent = modal

-- Cabeçalho do modal com título e botão Fechar (✕)
local modalHeader = Instance.new("Frame")
modalHeader.Size = UDim2.new(1, -24, 0, 32)
modalHeader.Position = UDim2.fromOffset(12, 10)
modalHeader.BackgroundTransparency = 1
modalHeader.ZIndex = 12
modalHeader.Parent = modal

local modalTitle = Instance.new("TextLabel")
modalTitle.Size = UDim2.new(1, -38, 1, 0)
modalTitle.BackgroundTransparency = 1
modalTitle.Font = Enum.Font.GothamBold
modalTitle.TextSize = 15
modalTitle.TextXAlignment = Enum.TextXAlignment.Left
modalTitle.TextColor3 = Config.Colors.IFSulGreen
modalTitle.Text = "Buscador de Salas & POIs"
modalTitle.ZIndex = 12
modalTitle.Parent = modalHeader

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseButton"
closeBtn.Size = UDim2.fromOffset(30, 30)
closeBtn.Position = UDim2.new(1, -30, 0, 1)
closeBtn.BackgroundColor3 = Color3.fromRGB(38, 48, 58)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 15
closeBtn.TextColor3 = Config.Colors.TextPrimary
closeBtn.Text = "✕"
closeBtn.ZIndex = 12
closeBtn.Parent = modalHeader

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = closeBtn

local searchBox = Instance.new("TextBox")
searchBox.Size = UDim2.new(1, -24, 0, 36)
searchBox.Position = UDim2.fromOffset(12, 48)
searchBox.BackgroundColor3 = Color3.fromRGB(26, 34, 42)
searchBox.Font = Enum.Font.Gotham
searchBox.TextSize = 13
searchBox.TextColor3 = Config.Colors.TextPrimary
searchBox.PlaceholderText = "Buscar sala (ex: 112, Cantina, Biblioteca, Auditório)..."
searchBox.PlaceholderColor3 = Config.Colors.TextMuted
searchBox.ClearTextOnFocus = false
searchBox.Text = ""
searchBox.ZIndex = 12
searchBox.Parent = modal

local sbCorner = Instance.new("UICorner")
sbCorner.CornerRadius = UDim.new(0, 8)
sbCorner.Parent = searchBox

local countLbl = Instance.new("TextLabel")
countLbl.Size = UDim2.new(1, -24, 0, 18)
countLbl.Position = UDim2.fromOffset(12, 88)
countLbl.BackgroundTransparency = 1
countLbl.Font = Enum.Font.Gotham
countLbl.TextSize = 11
countLbl.TextXAlignment = Enum.TextXAlignment.Left
countLbl.TextColor3 = Config.Colors.TextMuted
countLbl.Text = ""
countLbl.ZIndex = 12
countLbl.Parent = modal

local listFrame = Instance.new("ScrollingFrame")
listFrame.Size = UDim2.new(1, -24, 1, -118)
listFrame.Position = UDim2.fromOffset(12, 108)
listFrame.BackgroundTransparency = 1
listFrame.ScrollBarThickness = 6
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
listFrame.CanvasSize = UDim2.fromOffset(0, 0)
listFrame.ZIndex = 12
listFrame.Parent = modal

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.Parent = listFrame

type SearchItem = {
	key: string,
	label: string,
	searchText: string,
	badgeColor: Color3,
}

local allItems: { SearchItem } = {
	{
		key = "spawn",
		label = "Portaria Principal (Spawn)",
		searchText = "portaria principal entrada spawn inicio",
		badgeColor = Config.Colors.IFSulGreen,
	},
}

for _, poi in ipairs(CampusData.POIs) do
	table.insert(allItems, {
		key = "poi:" .. poi.id,
		label = "POI • " .. poi.title,
		searchText = string.lower(poi.title .. " " .. poi.subtitle),
		badgeColor = Config.Colors.IFSulRed,
	})
end

for _, room in ipairs(CampusData.Rooms) do
	local sec = CampusData.Sectors[room.sector]
	local badge = if sec then sec.color else Config.Colors.IFSulGreen
	local aliasStr = table.concat(room.aliases, " ")
	local label = if room.code ~= "" then (room.code .. " — " .. room.name) else room.name
	table.insert(allItems, {
		key = "room:" .. room.id,
		label = label,
		searchText = string.lower(room.code .. " " .. room.name .. " " .. aliasStr .. " setor " .. room.sector),
		badgeColor = badge,
	})
end

local function setFinderVisible(visible: boolean)
	modalBackdrop.Visible = visible
	if visible and not isTouchOnly then
		searchBox:CaptureFocus()
	end
end

local function rebuildList(query: string)
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local q = string.lower(query)
	local shown = 0
	for _, item in ipairs(allItems) do
		if q == "" or string.find(item.searchText, q, 1, true) then
			shown += 1
			local row = Instance.new("TextButton")
			row.Size = UDim2.new(1, -8, 0, 34)
			row.BackgroundColor3 = Color3.fromRGB(28, 36, 46)
			row.Font = Enum.Font.Gotham
			row.TextSize = 13
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.TextTruncate = Enum.TextTruncate.AtEnd
			row.TextColor3 = Config.Colors.TextPrimary
			row.Text = "   " .. item.label
			row.ZIndex = 13
			row.Parent = listFrame

			local rc = Instance.new("UICorner")
			rc.CornerRadius = UDim.new(0, 6)
			rc.Parent = row

			local bar = Instance.new("Frame")
			bar.Size = UDim2.new(0, 4, 1, -8)
			bar.Position = UDim2.fromOffset(4, 4)
			bar.BackgroundColor3 = item.badgeColor
			bar.BorderSizePixel = 0
			bar.ZIndex = 14
			bar.Parent = row

			row.MouseButton1Click:Connect(function()
				teleportRemote:FireServer(item.key)
				setFinderVisible(false)
			end)
		end
	end

	countLbl.Text = if shown == 1 then "1 local encontrado" else (tostring(shown) .. " locais encontrados")
end

rebuildList("")

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	rebuildList(searchBox.Text)
end)

closeBtn.MouseButton1Click:Connect(function()
	setFinderVisible(false)
end)
modalBackdrop.MouseButton1Click:Connect(function()
	setFinderVisible(false)
end)

-- Card discreto de boas-vindas ao entrar no jogo
local welcomeCard = Instance.new("Frame")
welcomeCard.Name = "WelcomeCard"
welcomeCard.AnchorPoint = Vector2.new(0.5, 1)
welcomeCard.Position = UDim2.new(0.5, 0, 1, -18)
welcomeCard.Size = UDim2.new(0.88, 0, 0, 114)
welcomeCard.BackgroundColor3 = Config.Colors.PanelBg
welcomeCard.BackgroundTransparency = 0.08
welcomeCard.ZIndex = 8
welcomeCard.Parent = screenGui

local welcomeConstraint = Instance.new("UISizeConstraint")
welcomeConstraint.MinSize = Vector2.new(260, 108)
welcomeConstraint.MaxSize = Vector2.new(440, 124)
welcomeConstraint.Parent = welcomeCard

local wcCorner = Instance.new("UICorner")
wcCorner.CornerRadius = UDim.new(0, 12)
wcCorner.Parent = welcomeCard

local wcStroke = Instance.new("UIStroke")
wcStroke.Color = Config.Colors.IFSulGreen
wcStroke.Thickness = 1.6
wcStroke.Parent = welcomeCard

local wcTitle = Instance.new("TextLabel")
wcTitle.Size = UDim2.new(1, -24, 0, 22)
wcTitle.Position = UDim2.fromOffset(12, 10)
wcTitle.BackgroundTransparency = 1
wcTitle.Font = Enum.Font.GothamBold
wcTitle.TextSize = 14
wcTitle.TextXAlignment = Enum.TextXAlignment.Left
wcTitle.TextColor3 = Config.Colors.IFSulGreen
wcTitle.Text = "Bem-vindo ao IFSul — Câmpus Sapucaia do Sul!"
wcTitle.ZIndex = 9
wcTitle.Parent = welcomeCard

local wcBody = Instance.new("TextLabel")
wcBody.Size = UDim2.new(1, -24, 0, 38)
wcBody.Position = UDim2.fromOffset(12, 33)
wcBody.BackgroundTransparency = 1
wcBody.Font = Enum.Font.Gotham
wcBody.TextSize = 12
wcBody.TextWrapped = true
wcBody.TextXAlignment = Enum.TextXAlignment.Left
wcBody.TextYAlignment = Enum.TextYAlignment.Top
wcBody.TextColor3 = Config.Colors.TextPrimary
wcBody.Text = if isTouchOnly
	then "Explore o câmpus em escala real 1:1 com 92 salas. Use o botão de correr para se deslocar mais rápido."
	else "Explore o câmpus em escala real 1:1 com 92 salas. Segure Shift para correr, [G] para buscar salas ou [N] para alternar Dia/Noite."
wcBody.ZIndex = 9
wcBody.Parent = welcomeCard

local wcBtn = Instance.new("TextButton")
wcBtn.Size = UDim2.fromOffset(110, 28)
wcBtn.Position = UDim2.new(1, -122, 1, -36)
wcBtn.BackgroundColor3 = Config.Colors.IFSulGreen
wcBtn.Font = Enum.Font.GothamBold
wcBtn.TextSize = 12
wcBtn.TextColor3 = Color3.new(1, 1, 1)
wcBtn.Text = "Explorar"
wcBtn.ZIndex = 9
wcBtn.Parent = welcomeCard

local wcBtnCorner = Instance.new("UICorner")
wcBtnCorner.CornerRadius = UDim.new(0, 7)
wcBtnCorner.Parent = wcBtn

local function dismissWelcome()
	if welcomeCard and welcomeCard.Parent then
		welcomeCard:Destroy()
	end
end

wcBtn.MouseButton1Click:Connect(dismissWelcome)

-- Atalhos de teclado
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if input.KeyCode == Enum.KeyCode.Escape and modalBackdrop.Visible then
		setFinderVisible(false)
		return
	end
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.G then
		dismissWelcome()
		setFinderVisible(not modalBackdrop.Visible)
	elseif input.KeyCode == Enum.KeyCode.N then
		applyLocalLighting(not isNight)
	end
end)

-- Detecta em tempo real em qual sala o jogador está
local accum = 0
RunService.Heartbeat:Connect(function(dt: number)
	accum += dt
	if accum < 0.35 then
		return
	end
	accum = 0
	local char = player.Character
	if not char then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end
	local pos = hrp.Position
	local foundText = "Área Externa do Câmpus"
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
			if math.abs(lx) <= halfW and math.abs(lz) <= halfD then
				foundText = if room.code ~= "" then ("Sala " .. room.code .. " — " .. room.name) else room.name
				break
			end
		end
	end
	locLbl.Text = foundText
end)
