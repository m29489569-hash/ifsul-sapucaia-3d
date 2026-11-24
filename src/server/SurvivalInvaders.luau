--!strict
-- Gerador e Inteligência Artificial de Hordas R15 do Modo Sobrevivência
-- Usa o rig pronto R15 Drooling Zombie da Creator Store (com fallback nativo HumanoidDescription),
-- escala para 5 arquétipos/Bosses, navega pelas 4 brechas externas reais, aplica Highlight vermelho
-- automático nos últimos 5 inimigos vivos (estilo Zombie Attack) e impede inimigos travados.

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local IFSulFolder = ReplicatedStorage:WaitForChild("IFSul")
local Config = require(IFSulFolder:WaitForChild("Config"))
local SurvivalCatalog = require(IFSulFolder:WaitForChild("SurvivalCatalog"))

local SurvivalInvaders = {}

local rng = Random.new()
local enemiesFolder: Folder? = nil
local onPlayerHitCallback: ((player: Player, damage: number) -> ())? = nil

function SurvivalInvaders.SetContext(
	folder: Folder?,
	playerHitHandler: (player: Player, damage: number) -> ()
)
	enemiesFolder = folder
	onPlayerHitCallback = playerHitHandler
end

local function chooseArchetype(wave: number, forceBoss: boolean): SurvivalCatalog.ArchetypeDef
	if forceBoss then
		for _, a in ipairs(SurvivalCatalog.Archetypes) do
			if a.isBoss then
				return a
			end
		end
	end

	local pool: { SurvivalCatalog.ArchetypeDef } = {}
	local totalW = 0
	for _, a in ipairs(SurvivalCatalog.Archetypes) do
		if not a.isBoss and wave >= a.minWave and a.weight > 0 then
			table.insert(pool, a)
			totalW += a.weight
		end
	end

	local pick = rng:NextNumber(0, totalW)
	local acc = 0
	for _, a in ipairs(pool) do
		acc += a.weight
		if pick <= acc then
			return a
		end
	end
	return SurvivalCatalog.Archetypes[1]
end

local function createBaseZombieModel(): Model
	local assets = ServerStorage:FindFirstChild("IFSul_SurvivalAssets")
	local eFolder = assets and assets:FindFirstChild("Enemies")
	local container = eFolder and eFolder:FindFirstChild("drooling_zombie_r15")
	local template = container and container:FindFirstChild("Zombie")
	if template and template:IsA("Model") then
		return template:Clone()
	end

	-- Fallback 100% nativo da engine Roblox com animação oficial Zumbi R15
	local desc = Instance.new("HumanoidDescription")
	desc.WalkAnimation = 616168032
	desc.RunAnimation = 616163682
	desc.IdleAnimation = 616158929
	desc.JumpAnimation = 616161997
	return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
end

local function findNearestStandingPlayer(fromPos: Vector3): (Player?, BasePart?, number)
	local bestP: Player? = nil
	local bestHrp: BasePart? = nil
	local bestDist = math.huge
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if char and char:GetAttribute("Downed") ~= true then
			local hum = char:FindFirstChildOfClass("Humanoid")
			local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hum and hum.Health > 0 and hrp then
				local d = (hrp.Position - fromPos).Magnitude
				if d < bestDist then
					bestDist = d
					bestP = p
					bestHrp = hrp
				end
			end
		end
	end
	return bestP, bestHrp, bestDist
end

function SurvivalInvaders.GetAliveCount(): number
	if not enemiesFolder then
		return 0
	end
	local count = 0
	for _, m in ipairs(enemiesFolder:GetChildren()) do
		if m:IsA("Model") then
			local hum = m:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				count += 1
			end
		end
	end
	return count
end

function SurvivalInvaders.UpdateLastFiveHighlights()
	if not enemiesFolder then
		return
	end
	local aliveModels: { Model } = {}
	for _, m in ipairs(enemiesFolder:GetChildren()) do
		if m:IsA("Model") then
			local hum = m:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				table.insert(aliveModels, m)
			end
		end
	end

	local showAll = (#aliveModels > 0 and #aliveModels <= 5)
	for _, m in ipairs(aliveModels) do
		local isBoss = m:GetAttribute("IsBoss") == true
		local hl = m:FindFirstChild("RadarHighlight") :: Highlight?
		if showAll or isBoss then
			if not hl then
				hl = Instance.new("Highlight")
				hl.Name = "RadarHighlight"
				hl.FillColor = if isBoss then Color3.fromRGB(250, 185, 25) else Config.Colors.IFSulRed
				hl.FillTransparency = 0.65
				hl.OutlineColor = Color3.fromRGB(255, 70, 70)
				hl.OutlineTransparency = 0.05
				hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				hl.Parent = m
			end
		elseif hl then
			hl:Destroy()
		end
	end
end

local function attachOverheadBar(model: Model, hum: Humanoid, def: SurvivalCatalog.ArchetypeDef)
	local head = model:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end

	local bbg = Instance.new("BillboardGui")
	bbg.Name = "EnemyOverhead"
	bbg.Size = if def.isBoss then UDim2.fromOffset(170, 40) else UDim2.fromOffset(92, 22)
	bbg.StudsOffset = Vector3.new(0, if def.isBoss then 3.4 else 2.2, 0)
	bbg.MaxDistance = if def.isBoss then 320 else 95
	bbg.AlwaysOnTop = def.isBoss == true
	bbg.Parent = head

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.52, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = if def.isBoss then Color3.fromRGB(250, 204, 21) else Color3.fromRGB(240, 244, 248)
	title.TextStrokeTransparency = 0.4
	title.Text = def.name
	title.Parent = bbg

	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, 0, 0.34, 0)
	barBg.Position = UDim2.fromScale(0, 0.60)
	barBg.BackgroundColor3 = Color3.fromRGB(20, 24, 30)
	barBg.BorderSizePixel = 0
	barBg.Parent = bbg

	local c1 = Instance.new("UICorner")
	c1.CornerRadius = UDim.new(1, 0)
	c1.Parent = barBg

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = if def.isBoss then Color3.fromRGB(235, 52, 52) else Color3.fromRGB(72, 212, 96)
	fill.BorderSizePixel = 0
	fill.Parent = barBg

	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(1, 0)
	c2.Parent = fill

	hum.HealthChanged:Connect(function(hp: number)
		local ratio = math.clamp(hp / math.max(1, hum.MaxHealth), 0, 1)
		fill.Size = UDim2.fromScale(ratio, 1)
	end)
end

function SurvivalInvaders.SpawnInvader(
	wave: number,
	playerCount: number,
	breach: SurvivalCatalog.BreachDef,
	forceBoss: boolean
): Model?
	if not enemiesFolder then
		return nil
	end

	local def = chooseArchetype(wave, forceBoss)
	local model = createBaseZombieModel()
	model.Name = def.name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	if math.abs(def.scale - 1.0) > 0.02 then
		pcall(function()
			model:ScaleTo(def.scale)
		end)
	end

	local bc = model:FindFirstChildOfClass("BodyColors") or Instance.new("BodyColors", model)
	bc.HeadColor3 = def.skinColor
	bc.LeftArmColor3 = def.skinColor
	bc.RightArmColor3 = def.skinColor
	bc.TorsoColor3 = def.torsoColor
	bc.LeftLegColor3 = def.legsColor
	bc.RightLegColor3 = def.legsColor

	for _, bp in ipairs(model:GetDescendants()) do
		if bp:IsA("BasePart") then
			bp.Anchored = false
			bp.CollisionGroup = "SurvivalInvaders"
		end
	end

	if def.isAcidic then
		local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("HumanoidRootPart")
		if torso then
			local sp = Instance.new("Sparkles")
			sp.SparkleColor = Color3.fromRGB(110, 250, 95)
			sp.Parent = torso
		end
	end

	local hum = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not hrp then
		model:Destroy()
		return nil
	end

	local waveHpScale = 1 + (wave - 1) * 0.16 + math.max(0, playerCount - 1) * 0.22
	local maxHp = math.round(def.baseHealth * waveHpScale)
	local spd = def.walkSpeed + math.min(3.5, (wave - 1) * 0.18)

	hum.MaxHealth = maxHp
	hum.Health = maxHp
	hum.WalkSpeed = spd
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.BreakJointsOnDeath = false

	model:SetAttribute("ArchetypeId", def.id)
	model:SetAttribute("CreditReward", def.creditReward)
	model:SetAttribute("BaseWalkSpeed", spd)
	model:SetAttribute("IsBoss", def.isBoss == true)

	local spawnBase = breach.spawnPoints[rng:NextInteger(1, #breach.spawnPoints)]
	local jitter = Vector3.new(rng:NextNumber(-6, 6), 0, rng:NextNumber(-6, 6))
	model:PivotTo(CFrame.lookAt(spawnBase + jitter, breach.entryPoint))
	model.Parent = enemiesFolder

	pcall(function()
		hrp:SetNetworkOwner(nil)
	end)

	attachOverheadBar(model, hum, def)
	SurvivalInvaders.UpdateLastFiveHighlights()

	-- Limpeza pós-morte
	hum.Died:Connect(function()
		SurvivalInvaders.UpdateLastFiveHighlights()
		task.delay(2.2, function()
			if model.Parent then
				model:Destroy()
			end
		end)
	end)

	-- Loop de IA: atravessa primeiro a brecha externa para entrar no câmpus e então persegue os jogadores
	task.spawn(function()
		local enteredCampus = false
		local lastAttackAt = 0
		local lastProgressPos = hrp.Position
		local lastProgressAt = os.clock()
		local nextPathComputeAt = 0
		local waypoints: { PathWaypoint } = {}
		local wpIndex = 2

		while model.Parent and hum.Health > 0 do
			local now = os.clock()

			if not enteredCampus then
				local distToEntry = Vector2.new(hrp.Position.X - breach.entryPoint.X, hrp.Position.Z - breach.entryPoint.Z).Magnitude
				if distToEntry <= 16 then
					enteredCampus = true
				else
					-- Se estagnar tentando passar pelo portão, avança para Pathfinding completo
					if (now - lastProgressAt) > 3.0 then
						enteredCampus = true
					else
						hum:MoveTo(breach.entryPoint)
						task.wait(0.35)
						continue
					end
				end
			end

			local targetPlayer, targetHrp, dist = findNearestStandingPlayer(hrp.Position)
			if not targetPlayer or not targetHrp then
				task.wait(0.5)
				continue
			end

			-- Ataque corpo a corpo quando encosta no jogador
			if dist <= def.attackRange and (now - lastAttackAt) >= def.attackCooldown then
				lastAttackAt = now
				if onPlayerHitCallback then
					local scaledDmg = math.round(def.attackDamage * (1 + (wave - 1) * 0.05))
					onPlayerHitCallback(targetPlayer, scaledDmg)
				end
			end

			-- Anti-travamento: se ficar 7s sem sair do lugar longe dos jogadores, reposiciona na entrada da brecha
			if (hrp.Position - lastProgressPos).Magnitude > 3.2 then
				lastProgressPos = hrp.Position
				lastProgressAt = now
			elseif (now - lastProgressAt) > 7.0 and dist > 26 then
				lastProgressAt = now
				model:PivotTo(CFrame.new(breach.entryPoint + Vector3.new(rng:NextNumber(-4, 4), 1, rng:NextNumber(-4, 4))))
				lastProgressPos = hrp.Position
				table.clear(waypoints)
			end

			-- Perseguição direta se tiver linha de visão livre ou estiver perto; PathfindingService caso haja paredes
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			local perim = Workspace:FindFirstChild("IFSul_SurvivalPerimeter")
			rayParams.FilterDescendantsInstances = if perim
				then { enemiesFolder :: Instance, targetPlayer.Character :: Instance, perim }
				else { enemiesFolder :: Instance, targetPlayer.Character :: Instance }
			local toTarget = targetHrp.Position - hrp.Position
			local blocked = dist > 18 and Workspace:Raycast(hrp.Position, toTarget.Unit * math.min(dist, 65), rayParams) ~= nil

			if not blocked then
				hum:MoveTo(targetHrp.Position)
			else
				if now >= nextPathComputeAt or wpIndex > #waypoints then
					nextPathComputeAt = now + rng:NextNumber(1.4, 2.2)
					local path = PathfindingService:CreatePath({
						AgentRadius = if def.isBoss then 3.0 else 1.8,
						AgentHeight = 5.2,
						AgentCanJump = true,
					})
					local ok = pcall(function()
						path:ComputeAsync(hrp.Position, targetHrp.Position)
					end)
					if ok and path.Status == Enum.PathStatus.Success then
						waypoints = path:GetWaypoints()
						wpIndex = 2
					else
						table.clear(waypoints)
					end
				end

				if wpIndex <= #waypoints then
					local wp = waypoints[wpIndex]
					if wp.Action == Enum.PathWaypointAction.Jump then
						hum.Jump = true
					end
					hum:MoveTo(wp.Position)
					if (Vector2.new(hrp.Position.X - wp.Position.X, hrp.Position.Z - wp.Position.Z)).Magnitude < 4.5 then
						wpIndex += 1
					end
				else
					hum:MoveTo(targetHrp.Position)
				end
			end

			task.wait(0.25)
		end
	end)

	return model
end

return SurvivalInvaders
