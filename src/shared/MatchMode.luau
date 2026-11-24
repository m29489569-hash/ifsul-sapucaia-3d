--!strict
-- Gerencia o estado global entre Lobby Livre (Exploração) e Partida Dedicada de Sobrevivência.
-- Em servidores reservados (TeleportService:ReserveServer), inicia automaticamente em modo Sobrevivência.
-- No Roblox Studio, permite alternar ao vivo via atributo Workspace.SurvivalMode para testes rápidos.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MatchMode = {}

if RunService:IsServer() then
	if Workspace:GetAttribute("SurvivalMode") == nil then
		local isReservedMatch = (game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0)
			or (Workspace:GetAttribute("ForceSurvivalMatch") == true)
		Workspace:SetAttribute("SurvivalMode", isReservedMatch)
	end
end

function MatchMode.IsSurvival(): boolean
	return Workspace:GetAttribute("SurvivalMode") == true
end

function MatchMode.IsLobby(): boolean
	return not MatchMode.IsSurvival()
end

function MatchMode.SetSurvivalServer(enabled: boolean)
	if RunService:IsServer() then
		Workspace:SetAttribute("SurvivalMode", enabled)
	end
end

function MatchMode.OnChanged(callback: (isSurvival: boolean) -> ()): RBXScriptConnection
	return Workspace:GetAttributeChangedSignal("SurvivalMode"):Connect(function()
		callback(MatchMode.IsSurvival())
	end)
end

return MatchMode
