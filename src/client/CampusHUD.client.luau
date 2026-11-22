--!strict
-- HUD institucional do IFSul — Câmpus Sapucaia do Sul (Roblox)
-- Exibe contador de moedas, Buscador de Salas/POIs [G],
-- alternância Dia/Noite local [N] e Sprint (Shift no PC / botão padrão no celular).

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
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
screenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- Contador de moedas responsivo (Phone, Tablet, Desktop e Console/TV)
-- Usa CoreUISafeInsets para respeitar Topbar, notches/bordas arredondadas e overscan de TV.
local coinCounter = Instance.new("Frame")
coinCounter.Name = "CoinCounter"
coinCounter.AnchorPoint = Vector2.new(0, 0)
coinCounter.AutomaticSize = Enum.AutomaticSize.X
coinCounter.Size = UDim2.fromOffset(0, 46)
coinCounter.Position = UDim2.fromOffset(16, 12)
coinCounter.BackgroundColor3 = Config.Colors.PanelBg
coinCounter.BackgroundTransparency = 0.22
coinCounter.Parent = screenGui

local coinScale = Instance.new("UIScale")
coinScale.Scale = 1
coinScale.Parent = coinCounter

local coinConstraint = Instance.new("UISizeConstraint")
coinConstraint.MinSize = Vector2.new(124, 46)
coinConstraint.MaxSize = Vector2.new(320, 64)
coinConstraint.Parent = coinCounter

local coinCorner = Instance.new("UICorner")
coinCorner.CornerRadius = UDim.new(1, 0) -- Cápsula/pílula completa
coinCorner.Parent = coinCounter

local coinStroke = Instance.new("UIStroke")
coinStroke.Color = Color3.fromRGB(224, 180, 64)
coinStroke.Thickness = 1.6
coinStroke.Transparency = 0.1
coinStroke.Parent = coinCounter

local coinPadding = Instance.new("UIPadding")
coinPadding.PaddingLeft = UDim.new(0, 7)
coinPadding.PaddingRight = UDim.new(0, 16)
coinPadding.Parent = coinCounter

local coinLayout = Instance.new("UIListLayout")
coinLayout.FillDirection = Enum.FillDirection.Horizontal
coinLayout.VerticalAlignment = Enum.VerticalAlignment.Center
coinLayout.Padding = UDim.new(0, 8)
coinLayout.SortOrder = Enum.SortOrder.LayoutOrder
coinLayout.Parent = coinCounter

local coinIcon = Instance.new("ImageLabel")
coinIcon.Name = "CoinIcon"
coinIcon.LayoutOrder = 1
coinIcon.Size = UDim2.fromOffset(34, 34)
coinIcon.BackgroundTransparency = 1
coinIcon.ScaleType = Enum.ScaleType.Fit
coinIcon.Image = Config.CoinIconAssetId
coinIcon.Parent = coinCounter

local coinIconAspect = Instance.new("UIAspectRatioConstraint")
coinIconAspect.AspectRatio = 1
coinIconAspect.Parent = coinIcon

local coinLbl = Instance.new("TextLabel")
coinLbl.Name = "CoinAmount"
coinLbl.LayoutOrder = 2
coinLbl.AutomaticSize = Enum.AutomaticSize.X
coinLbl.Size = UDim2.fromOffset(0, 34)
coinLbl.BackgroundTransparency = 1
coinLbl.Font = Enum.Font.GothamBold
coinLbl.TextSize = 20
coinLbl.TextXAlignment = Enum.TextXAlignment.Left
coinLbl.TextColor3 = Config.Colors.TextPrimary
coinLbl.TextStrokeColor3 = Color3.fromRGB(10, 14, 18)
coinLbl.TextStrokeTransparency = 0.65
coinLbl.Text = "0"
coinLbl.Parent = coinCounter

type CoinProfile = {
	height: number,
	minWidth: number,
	iconSize: number,
	textSize: number,
	padLeft: number,
	padRight: number,
	gap: number,
	posX: number,
	posY: number,
	strokeThickness: number,
}

local COIN_PROFILES: { [string]: CoinProfile } = {
	Phone = {
		height = 36,
		minWidth = 92,
		iconSize = 26,
		textSize = 15,
		padLeft = 5,
		padRight = 12,
		gap = 6,
		posX = 12,
		posY = 8,
		strokeThickness = 1.4,
	},
	Tablet = {
		height = 42,
		minWidth = 112,
		iconSize = 30,
		textSize = 18,
		padLeft = 6,
		padRight = 14,
		gap = 8,
		posX = 16,
		posY = 12,
		strokeThickness = 1.5,
	},
	Desktop = {
		height = 46,
		minWidth = 124,
		iconSize = 34,
		textSize = 20,
		padLeft = 7,
		padRight = 16,
		gap = 8,
		posX = 16,
		posY = 12,
		strokeThickness = 1.6,
	},
	Console = {
		height = 58,
		minWidth = 156,
		iconSize = 42,
		textSize = 26,
		padLeft = 9,
		padRight = 20,
		gap = 10,
		posX = 32,
		posY = 24,
		strokeThickness = 2.0,
	},
}

local function detectDeviceProfile(): string
	if GuiService:IsTenFootInterface() then
		return "Console"
	end
	local cam = Workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	local minSide = math.min(vp.X, vp.Y)
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		if minSide < 550 then
			return "Phone"
		end
		return "Tablet"
	end
	if minSide < 520 then
		return "Phone"
	elseif vp.X < 1050 then
		return "Tablet"
	end
	return "Desktop"
end

local function applyCoinResponsiveLayout()
	local profileName = detectDeviceProfile()
	local p = COIN_PROFILES[profileName] or COIN_PROFILES.Desktop
	coinCounter.Size = UDim2.fromOffset(0, p.height)
	coinCounter.Position = UDim2.fromOffset(p.posX, p.posY)
	coinConstraint.MinSize = Vector2.new(p.minWidth, p.height)
	coinConstraint.MaxSize = Vector2.new(340, p.height)
	coinStroke.Thickness = p.strokeThickness
	coinPadding.PaddingLeft = UDim.new(0, p.padLeft)
	coinPadding.PaddingRight = UDim.new(0, p.padRight)
	coinLayout.Padding = UDim.new(0, p.gap)
	coinIcon.Size = UDim2.fromOffset(p.iconSize, p.iconSize)
	coinLbl.Size = UDim2.fromOffset(0, p.iconSize)
	coinLbl.TextSize = p.textSize
end

local function bindViewportResize(cam: Camera?)
	if not cam then
		return
	end
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyCoinResponsiveLayout)
end

applyCoinResponsiveLayout()
bindViewportResize(Workspace.CurrentCamera)
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	bindViewportResize(Workspace.CurrentCamera)
	applyCoinResponsiveLayout()
end)

local function formatCoins(amount: number): string
	local n = math.max(0, math.floor(amount))
	if n >= 1_000_000_000 then
		return (string.format("%.1fB", n / 1_000_000_000):gsub("%.0B$", "B"))
	elseif n >= 1_000_000 then
		return (string.format("%.1fM", n / 1_000_000):gsub("%.0M$", "M"))
	elseif n >= 10_000 then
		return (string.format("%.1fK", n / 1_000):gsub("%.0K$", "K"))
	end
	local s = tostring(n)
	local formatted = string.reverse(s):gsub("(%d%d%d)", "%1."):reverse()
	return (formatted:gsub("^%.", ""))
end

local lastCoins = 0
local popInInfo = TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local popOutInfo = TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function updateCoinsDisplay()
	local raw = player:GetAttribute("Coins")
	local value = if typeof(raw) == "number" then raw else 0
	coinLbl.Text = formatCoins(value)
	if value > lastCoins then
		local tIn = TweenService:Create(coinScale, popInInfo, { Scale = 1.12 })
		tIn:Play()
		tIn.Completed:Connect(function()
			TweenService:Create(coinScale, popOutInfo, { Scale = 1 }):Play()
		end)
	end
	lastCoins = value
end

updateCoinsDisplay()
player:GetAttributeChangedSignal("Coins"):Connect(updateCoinsDisplay)

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
		setFinderVisible(not modalBackdrop.Visible)
	elseif input.KeyCode == Enum.KeyCode.N then
		applyLocalLighting(not isNight)
	end
end)
