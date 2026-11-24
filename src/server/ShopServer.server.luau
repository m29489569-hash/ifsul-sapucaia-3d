--!strict
-- Servidor da Loja do IFSul — Câmpus Sapucaia do Sul
-- Gerencia compras por Moedas (validadas no servidor), compras por Robux (MarketplaceService)
-- e entrega/persistência dos Tools de ServerStorage.IFSul_ShopTools no Backpack e StarterGear.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local IFSulFolder = ReplicatedStorage:WaitForChild("IFSul")
local Config = require(IFSulFolder:WaitForChild("Config"))
local ShopCatalog = require(IFSulFolder:WaitForChild("ShopCatalog"))
local MatchMode = require(IFSulFolder:WaitForChild("MatchMode"))

local remotes = IFSulFolder:FindFirstChild("Remotes") :: Folder?
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = IFSulFolder
end

local function ensureRemoteFunction(name: string): RemoteFunction
	local existing = remotes:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	local rf = Instance.new("RemoteFunction")
	rf.Name = name
	rf.Parent = remotes
	return rf
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

local getStateRF = ensureRemoteFunction("ShopGetState")
local buyCoinsRF = ensureRemoteFunction("ShopBuyCoins")
local buyRobuxRF = ensureRemoteFunction("ShopBuyRobux")
local ownedUpdatedRE = ensureRemoteEvent("ShopOwnedUpdated")

local toolsFolder = ServerStorage:WaitForChild("IFSul_ShopTools", 15)

-- Inventário de itens adquiridos por jogador nesta sessão
local ownedByPlayer: { [Player]: { [string]: boolean } } = {}

local function getOwnedList(player: Player): { string }
	local map = ownedByPlayer[player]
	local list: { string } = {}
	if map then
		for id, has in pairs(map) do
			if has then
				table.insert(list, id)
			end
		end
	end
	return list
end

local function grantToolToPlayer(player: Player, itemId: string, displayName: string): boolean
	if MatchMode.IsSurvival() then
		return false
	end
	if not toolsFolder then
		warn("[ShopServer] ServerStorage.IFSul_ShopTools não encontrado.")
		return false
	end
	local template = toolsFolder:FindFirstChild(itemId)
	if not template or not template:IsA("Tool") then
		warn("[ShopServer] Tool não encontrado para item:", itemId)
		return false
	end

	-- Entrega no Backpack atual (se ainda não estiver lá ou equipado)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local char = player.Character
	local alreadyInHand = (backpack and backpack:FindFirstChild(displayName))
		or (char and char:FindFirstChild(displayName))
	if backpack and not alreadyInHand then
		local clone = template:Clone()
		clone.Name = displayName
		clone.Parent = backpack
	end

	-- Entrega também no StarterGear para manter após renascer
	local starterGear = player:FindFirstChildOfClass("StarterGear")
	if starterGear and not starterGear:FindFirstChild(displayName) then
		local gearClone = template:Clone()
		gearClone.Name = displayName
		gearClone.Parent = starterGear
	end

	return true
end

local function unlockItem(player: Player, itemId: string): boolean
	local item = ShopCatalog.GetById(itemId)
	if not item then
		return false
	end
	ownedByPlayer[player] = ownedByPlayer[player] or {}
	ownedByPlayer[player][itemId] = true
	grantToolToPlayer(player, item.id, item.name)
	ownedUpdatedRE:FireClient(player, getOwnedList(player))
	return true
end

local function isAdmin(player: Player): boolean
	if game.CreatorId > 0 and player.UserId == game.CreatorId then
		return true
	end
	if Config.AdminUserIds then
		for _, uid in ipairs(Config.AdminUserIds) do
			if player.UserId == uid then
				return true
			end
		end
	end
	return false
end

local function initPlayerInventory(player: Player)
	local map: { [string]: boolean } = {}
	if isAdmin(player) then
		for _, item in ipairs(ShopCatalog.Items) do
			map[item.id] = true
		end
	end
	ownedByPlayer[player] = map
end

Players.PlayerAdded:Connect(initPlayerInventory)

Players.PlayerRemoving:Connect(function(player: Player)
	ownedByPlayer[player] = nil
end)

for _, p in ipairs(Players:GetPlayers()) do
	if not ownedByPlayer[p] then
		initPlayerInventory(p)
	end
end

getStateRF.OnServerInvoke = function(player: Player)
	return {
		owned = getOwnedList(player),
	}
end

buyCoinsRF.OnServerInvoke = function(player: Player, itemId: unknown)
	if typeof(itemId) ~= "string" then
		return { ok = false, message = "Item inválido." }
	end
	local item = ShopCatalog.GetById(itemId)
	if not item then
		return { ok = false, message = "Item não encontrado." }
	end

	local owned = ownedByPlayer[player]
	if owned and owned[item.id] then
		grantToolToPlayer(player, item.id, item.name)
		return { ok = true, message = item.name .. " já adquirido e equipado na mochila!", owned = getOwnedList(player) }
	end

	local rawCoins = player:GetAttribute("Coins")
	local coins = if typeof(rawCoins) == "number" then rawCoins else 0
	if coins < item.coinPrice then
		return {
			ok = false,
			message = "Você precisa de " .. tostring(item.coinPrice) .. " moedas para comprar " .. item.name .. ".",
		}
	end

	player:SetAttribute("Coins", coins - item.coinPrice)
	unlockItem(player, item.id)

	return {
		ok = true,
		message = item.name .. " comprado com sucesso!",
		owned = getOwnedList(player),
	}
end

buyRobuxRF.OnServerInvoke = function(player: Player, itemId: unknown)
	if typeof(itemId) ~= "string" then
		return { ok = false, message = "Item inválido." }
	end
	local item = ShopCatalog.GetById(itemId)
	if not item then
		return { ok = false, message = "Item não encontrado." }
	end

	local owned = ownedByPlayer[player]
	if owned and owned[item.id] then
		grantToolToPlayer(player, item.id, item.name)
		return { ok = true, message = item.name .. " já adquirido e equipado na mochila!", owned = getOwnedList(player) }
	end

	if item.devProductId <= 0 then
		return {
			ok = false,
			message = "Configure o Developer Product ID ("
				.. tostring(item.robuxPrice)
				.. " R$) no ShopCatalog para ativar compra real por Robux.",
		}
	end

	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, item.devProductId)
	end)
	if not ok then
		warn("[ShopServer] Falha ao abrir compra Robux:", err)
		return { ok = false, message = "Não foi possível abrir a compra por Robux." }
	end

	return { ok = true, message = "Abrindo compra por " .. tostring(item.robuxPrice) .. " Robux..." }
end

-- Processa recibos de compra por Robux (Developer Products)
MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local item = ShopCatalog.GetByProductId(receiptInfo.ProductId)
	if not item then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local unlocked = unlockItem(player, item.id)
	if not unlocked then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end
