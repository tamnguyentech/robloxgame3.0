local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local CardDatabase       = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardDatabase"))
local PvpProtocol        = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PvpProtocol"))
local CardVisualResolver = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardVisualResolver"))
local HoloFoilController = require(script.Parent.ui.effects:WaitForChild("HoloFoilController"))
local RainbowBorderStroke = require(script.Parent.ui.effects:WaitForChild("RainbowBorderStroke"))
local ClientStateManager = require(script.Parent.core:WaitForChild("ClientStateManager"))
local DeviceContext = require(script.Parent.core:WaitForChild("DeviceContext"))
local DamagePopupManager = require(script.Parent.ui:WaitForChild("DamagePopupManager"))
local cardArtFolder      = ReplicatedStorage:WaitForChild("CardArt")

local remotesFolder = ReplicatedStorage:WaitForChild(PvpProtocol.Remotes.FolderName)
local challengeRequestEvent = remotesFolder:WaitForChild(PvpProtocol.Remotes.ChallengeRequest)
local inviteEvent = remotesFolder:WaitForChild(PvpProtocol.Remotes.InviteEvent)
local inviteResponseEvent = remotesFolder:WaitForChild(PvpProtocol.Remotes.InviteResponse)
local sessionEvent = remotesFolder:WaitForChild(PvpProtocol.Remotes.SessionEvent)
local actionEvent = remotesFolder:WaitForChild(PvpProtocol.Remotes.ActionEvent)

local COMBAT_SLOT_COUNT = 5
local RADIAL_RADIUS = 130
local PLAYER_ATTACK_SOUND_ASSET = "rbxassetid://12222242"
local HIT_SOUND_ASSET = "rbxassetid://9118828568"
local ABILITY_SPEED_SOUND_ASSET = "rbxassetid://9113420775"
local ABILITY_DAMAGE_SOUND_ASSET = "rbxassetid://9118828568"
local ABILITY_HEAL_SOUND_ASSET = "rbxassetid://9048375035"
local ABILITY_SOUND_PROFILE_BY_EFFECT = {
	TeamAttackSpeedBoost = {
		assetId = ABILITY_SPEED_SOUND_ASSET,
		volume = 0.22,
		speedMin = 1.04,
		speedMax = 1.18,
		layerAssetId = ABILITY_SPEED_SOUND_ASSET,
		layerVolume = 0.1,
		layerSpeedMin = 1.2,
		layerSpeedMax = 1.34,
	},
	TeamAttackDamageBoost = {
		assetId = ABILITY_DAMAGE_SOUND_ASSET,
		volume = 0.26,
		speedMin = 0.9,
		speedMax = 1.0,
		layerAssetId = HIT_SOUND_ASSET,
		layerVolume = 0.15,
		layerSpeedMin = 0.68,
		layerSpeedMax = 0.78,
	},
	HealLowestAlly = {
		assetId = ABILITY_HEAL_SOUND_ASSET,
		volume = 0.2,
		speedMin = 1.02,
		speedMax = 1.14,
		layerAssetId = ABILITY_HEAL_SOUND_ASSET,
		layerVolume = 0.09,
		layerSpeedMin = 1.24,
		layerSpeedMax = 1.38,
	},
}
local BATTLE_VIDEO_LOOP_START_OFFSET_SECONDS = 1.0
local trackedBattleVideoFrames = {}
local preloadedBattleVideoAssets = {}
local lastBattleVideoTimePosition = {}
local BATTLE_FX_TIME_SCALE = 1.35
local BATTLE_FX_LIFETIME_SCALE = 1.45
local ABILITY_WORLD_BURST_COOLDOWN_SECONDS = 0.16
local abilityWorldBurstCooldownByEffect = {}

local function fxTime(seconds)
	return math.max(0.01, (tonumber(seconds) or 0) * BATTLE_FX_TIME_SCALE)
end

local function fxLife(seconds)
	return math.max(0.05, (tonumber(seconds) or 0) * BATTLE_FX_LIFETIME_SCALE)
end

local function ensureBattleVideoFramePlayback(videoFrame, videoAssetId)
	if not (videoFrame and videoFrame:IsA("VideoFrame")) then
		return
	end

	local function forcePlay()
		videoFrame.Playing = true
		pcall(function()
			videoFrame:Play()
		end)
	end

	trackedBattleVideoFrames[videoFrame] = true
	if not preloadedBattleVideoAssets[videoAssetId] then
		preloadedBattleVideoAssets[videoAssetId] = true
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync({videoAssetId})
			end)
		end)
	end

	local shouldRestart = (videoFrame.Video ~= videoAssetId)
	videoFrame.Looped = true
	videoFrame.Video = videoAssetId
	if shouldRestart then
		videoFrame.TimePosition = BATTLE_VIDEO_LOOP_START_OFFSET_SECONDS
	end
	forcePlay()

	task.defer(function()
		if videoFrame.Parent and videoFrame.Visible and videoFrame.Video == videoAssetId then
			forcePlay()
		end
	end)
	task.delay(0.15, function()
		if videoFrame.Parent and videoFrame.Visible and videoFrame.Video == videoAssetId then
			forcePlay()
		end
	end)
	task.delay(0.4, function()
		if not (videoFrame.Parent and videoFrame.Visible and videoFrame.Video == videoAssetId) then
			return
		end
		local pos = tonumber(videoFrame.TimePosition) or 0
		if pos <= 0.02 then
			videoFrame.Video = ""
			task.wait()
			if not (videoFrame.Parent and videoFrame.Visible) then
				return
			end
			videoFrame.Video = videoAssetId
			videoFrame.TimePosition = BATTLE_VIDEO_LOOP_START_OFFSET_SECONDS
			forcePlay()
		end
	end)
end

local battleVideoGuardAccumulator = 0
RunService.Heartbeat:Connect(function(dt)
	battleVideoGuardAccumulator += dt
	if battleVideoGuardAccumulator < 0.2 then
		return
	end
	battleVideoGuardAccumulator = 0

	for videoFrame in pairs(trackedBattleVideoFrames) do
		if not videoFrame.Parent then
			trackedBattleVideoFrames[videoFrame] = nil
			lastBattleVideoTimePosition[videoFrame] = nil
		elseif videoFrame.Visible and videoFrame.Video ~= "" and videoFrame.Video ~= "rbxassetid://0" then
			videoFrame.Looped = true
			if not videoFrame.Playing then
				videoFrame.Playing = true
				pcall(function()
					videoFrame:Play()
				end)
			end

			local currentPos = tonumber(videoFrame.TimePosition) or 0
			local lastPos = lastBattleVideoTimePosition[videoFrame]
			if lastPos and currentPos + 0.03 < lastPos and currentPos < BATTLE_VIDEO_LOOP_START_OFFSET_SECONDS then
				videoFrame.TimePosition = BATTLE_VIDEO_LOOP_START_OFFSET_SECONDS
				currentPos = BATTLE_VIDEO_LOOP_START_OFFSET_SECONDS
			end
			lastBattleVideoTimePosition[videoFrame] = currentPos
		end
	end
end)

local function findCardArtDecal(cardId)
	if type(cardId) ~= "string" or cardId == "" then
		return nil
	end

	local exact = cardArtFolder:FindFirstChild(cardId)
	if exact and exact:IsA("Decal") then
		return exact
	end

	local target = string.lower(cardId)
	for _, obj in ipairs(cardArtFolder:GetChildren()) do
		if obj:IsA("Decal") and string.lower(obj.Name) == target then
			return obj
		end
	end

	return nil
end

local function emitWorldParticleBurst(color, burstCount, distanceFromCamera)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local fxPart = Instance.new("Part")
	fxPart.Name = "BattleParticleBurst"
	fxPart.Anchored = true
	fxPart.CanCollide = false
	fxPart.CanQuery = false
	fxPart.CanTouch = false
	fxPart.Transparency = 1
	fxPart.Size = Vector3.new(0.2, 0.2, 0.2)
	fxPart.CFrame = camera.CFrame * CFrame.new(0, 0, -(tonumber(distanceFromCamera) or 12))
	fxPart.Parent = Workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = fxPart

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "CardAttackEmitter"
	emitter.Rate = 0
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color:Lerp(Color3.fromRGB(255, 184, 90), 0.35)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 122, 36)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(84, 18, 8)),
	})
	emitter.LightEmission = 0.9
	emitter.LightInfluence = 0
	emitter.Lifetime = NumberRange.new(0.45, 0.95)
	emitter.Speed = NumberRange.new(10, 20)
	emitter.Drag = 2
	emitter.SpreadAngle = Vector2.new(95, 95)
	emitter.Acceleration = Vector3.new(0, 8, 0)
	emitter.RotSpeed = NumberRange.new(-220, 220)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.28),
		NumberSequenceKeypoint.new(0.35, 0.44),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.04),
		NumberSequenceKeypoint.new(0.6, 0.36),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	emitter.Parent = attachment

	emitter:Emit(math.max(4, math.floor(tonumber(burstCount) or 20)))
	Debris:AddItem(fxPart, fxLife(1.2))
end

local function emitAbilityWorldParticleBurst(effectType, color)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local effect = tostring(effectType or "")
	local burstColor = color or Color3.fromRGB(230, 230, 230)
	local texture = "rbxasset://textures/particles/fire_main.dds"
	local speed = NumberRange.new(9, 18)
	local lifetime = NumberRange.new(0.45, 0.95)
	local spread = Vector2.new(90, 90)
	local acceleration = Vector3.new(0, 8, 0)
	local burstCount = 28

	if effect == "TeamAttackSpeedBoost" then
		texture = "rbxasset://textures/particles/sparkles_main.dds"
		burstColor = Color3.fromRGB(130, 210, 255)
		speed = NumberRange.new(18, 34)
		lifetime = NumberRange.new(0.38, 0.8)
		spread = Vector2.new(45, 45)
		acceleration = Vector3.new(0, -4, 0)
		burstCount = 34
	elseif effect == "HealLowestAlly" then
		texture = "rbxasset://textures/particles/sparkles_main.dds"
		burstColor = Color3.fromRGB(126, 255, 180)
		speed = NumberRange.new(7, 16)
		lifetime = NumberRange.new(0.7, 1.25)
		spread = Vector2.new(55, 55)
		acceleration = Vector3.new(0, 10, 0)
		burstCount = 30
	end

	local fxPart = Instance.new("Part")
	fxPart.Name = "AbilityParticleBurst"
	fxPart.Anchored = true
	fxPart.CanCollide = false
	fxPart.CanQuery = false
	fxPart.CanTouch = false
	fxPart.Transparency = 1
	fxPart.Size = Vector3.new(0.2, 0.2, 0.2)
	fxPart.CFrame = camera.CFrame * CFrame.new(0, 0, -8)
	fxPart.Parent = Workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = fxPart

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "AbilityBuffEmitter"
	emitter.Rate = 0
	emitter.Texture = texture
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, burstColor:Lerp(Color3.fromRGB(255, 255, 255), 0.22)),
		ColorSequenceKeypoint.new(1, burstColor:Lerp(Color3.fromRGB(30, 30, 30), 0.25)),
	})
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Lifetime = lifetime
	emitter.Speed = speed
	emitter.Drag = 2
	emitter.SpreadAngle = spread
	emitter.Acceleration = acceleration
	emitter.RotSpeed = NumberRange.new(-240, 240)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.16),
		NumberSequenceKeypoint.new(0.35, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.02),
		NumberSequenceKeypoint.new(0.75, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = attachment

	emitter:Emit(burstCount)
	Debris:AddItem(fxPart, fxLife(1.4))
end

local function resolveArtScaleType(data, imageObj)
	if data and data.ArtFitMode == "Stretch" then
		return Enum.ScaleType.Stretch
	end
	if data and data.ArtFitMode == "Crop" then
		return Enum.ScaleType.Crop
	end
	if data and data.ArtFitMode == "Fit" then
		return Enum.ScaleType.Fit
	end

	if imageObj then
		local modeAttr = imageObj:GetAttribute("ArtFitMode")
		if type(modeAttr) == "string" then
			local normalized = string.lower(modeAttr)
			if normalized == "stretch" then
				return Enum.ScaleType.Stretch
			end
			if normalized == "crop" then
				return Enum.ScaleType.Crop
			end
			return Enum.ScaleType.Fit
		end
		if imageObj:GetAttribute("ForceStretch") == true or imageObj:GetAttribute("SquareArt") == true then
			return Enum.ScaleType.Stretch
		end
	end

	return Enum.ScaleType.Fit
end

local uiState = {
	sessionId = nil,
	opponentName = "",
	pendingInviteId = nil,
	pendingInviteFrom = "",
	radialTargetUserId = nil,
	radialTargetName = "",
	ambienceTween = nil,
}
local battleFrame

local function getPanelCard(panel, slotIndex)
	if not panel then
		return nil
	end
	local cardRow = panel:FindFirstChild("CardRow")
	if not (cardRow and cardRow:IsA("Frame")) then
		return nil
	end
	local card = cardRow:FindFirstChild("SlotCard" .. tostring(slotIndex))
	if card and card:IsA("Frame") then
		return card
	end
	return nil
end

local function ensureBattleSounds(frame)
	if not frame then
		return
	end

	local attack = frame:FindFirstChild("PvpAttackSound")
	if not (attack and attack:IsA("Sound")) then
		if attack then
			attack:Destroy()
		end
		attack = Instance.new("Sound")
		attack.Name = "PvpAttackSound"
		attack.SoundId = PLAYER_ATTACK_SOUND_ASSET
		attack.Volume = 0.22
		attack.Parent = frame
	end

	local hit = frame:FindFirstChild("PvpImpactSound")
	if not (hit and hit:IsA("Sound")) then
		if hit then
			hit:Destroy()
		end
		hit = Instance.new("Sound")
		hit.Name = "PvpImpactSound"
		hit.SoundId = HIT_SOUND_ASSET
		hit.Volume = 0.2
		hit.Parent = frame
	end

	local speedAbility = frame:FindFirstChild("PvpAbilitySpeedSound")
	if not (speedAbility and speedAbility:IsA("Sound")) then
		if speedAbility then
			speedAbility:Destroy()
		end
		speedAbility = Instance.new("Sound")
		speedAbility.Name = "PvpAbilitySpeedSound"
		speedAbility.SoundId = ABILITY_SPEED_SOUND_ASSET
		speedAbility.Volume = 0
		speedAbility.Parent = frame
	end

	local damageAbility = frame:FindFirstChild("PvpAbilityDamageSound")
	if not (damageAbility and damageAbility:IsA("Sound")) then
		if damageAbility then
			damageAbility:Destroy()
		end
		damageAbility = Instance.new("Sound")
		damageAbility.Name = "PvpAbilityDamageSound"
		damageAbility.SoundId = ABILITY_DAMAGE_SOUND_ASSET
		damageAbility.Volume = 0
		damageAbility.Parent = frame
	end

	local healAbility = frame:FindFirstChild("PvpAbilityHealSound")
	if not (healAbility and healAbility:IsA("Sound")) then
		if healAbility then
			healAbility:Destroy()
		end
		healAbility = Instance.new("Sound")
		healAbility.Name = "PvpAbilityHealSound"
		healAbility.SoundId = ABILITY_HEAL_SOUND_ASSET
		healAbility.Volume = 0
		healAbility.Parent = frame
	end
end

local function playOneShotAbilitySound(parentFrame, assetId, volume, speedMin, speedMax)
	if not (parentFrame and assetId) then
		return
	end

	local sound = Instance.new("Sound")
	sound.Name = "PvpAbilityOneShot"
	sound.SoundId = assetId
	sound.Volume = math.max(0, tonumber(volume) or 0.2)
	sound.PlaybackSpeed = (tonumber(speedMin) or 1) + (math.random() * math.max(0, (tonumber(speedMax) or 1) - (tonumber(speedMin) or 1)))
	sound.Parent = parentFrame
	sound:Play()
	Debris:AddItem(sound, 2)
end

local function playAbilitySound(effectType)
	if not battleFrame then
		return
	end
	local profile = ABILITY_SOUND_PROFILE_BY_EFFECT[tostring(effectType or "")]
	if not profile then
		return
	end

	playOneShotAbilitySound(battleFrame, profile.assetId, profile.volume, profile.speedMin, profile.speedMax)
	if profile.layerAssetId then
		playOneShotAbilitySound(battleFrame, profile.layerAssetId, profile.layerVolume, profile.layerSpeedMin, profile.layerSpeedMax)
	end
end

local function playCardDeathAnimation(card)
	if not (card and card.Parent) then
		return
	end
	if card:GetAttribute("DeathAnimated") then
		return
	end
	card:SetAttribute("DeathAnimated", true)

	local flash = Instance.new("Frame")
	flash.Name = "DeathFlash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.Position = UDim2.fromOffset(0, 0)
	flash.BackgroundColor3 = Color3.fromRGB(255, 88, 88)
	flash.BackgroundTransparency = 0.45
	flash.BorderSizePixel = 0
	flash.ZIndex = 20
	flash.Parent = card

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = flash

	TweenService:Create(
		flash,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundTransparency = 1}
	):Play()
	Debris:AddItem(flash, 0.24)

	for _, obj in ipairs(card:GetDescendants()) do
		if obj:IsA("TextLabel") then
			TweenService:Create(obj, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 0.65}):Play()
		elseif obj:IsA("ImageLabel") then
			TweenService:Create(obj, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {ImageTransparency = 0.55}):Play()
		elseif obj:IsA("Frame") then
			TweenService:Create(obj, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = math.min(1, obj.BackgroundTransparency + 0.4)}):Play()
		end
	end

	TweenService:Create(
		card,
		TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.In),
		{Rotation = 8, BackgroundTransparency = 0.7}
	):Play()
end

local function showBattleImpactPulse(frame)
	if not frame then
		return
	end
	local pulse = Instance.new("Frame")
	pulse.Name = "ImpactPulse"
	pulse.Size = UDim2.fromScale(1, 1)
	pulse.Position = UDim2.fromOffset(0, 0)
	pulse.BackgroundColor3 = Color3.fromRGB(255, 165, 165)
	pulse.BackgroundTransparency = 0.94
	pulse.BorderSizePixel = 0
	pulse.ZIndex = 4
	pulse.Parent = frame
	TweenService:Create(pulse, TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
	Debris:AddItem(pulse, 0.34)
end

local function animateAttackDash(attackerPanel, attackerSlotIndex, targetPanel, targetSlotIndex)
	local attackerCard = getPanelCard(attackerPanel, attackerSlotIndex)
	local targetCard = getPanelCard(targetPanel, targetSlotIndex)
	if not (attackerCard and targetCard and battleFrame) then
		return false
	end

	if attackerCard:GetAttribute("IsAnimatingAttack") then
		return false
	end
	attackerCard:SetAttribute("IsAnimatingAttack", true)

	local attackSound = battleFrame:FindFirstChild("PvpAttackSound")
	if attackSound and attackSound:IsA("Sound") then
		attackSound:Play()
	end

	local ghost = attackerCard:Clone()
	ghost.Name = "AttackGhost"
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.ZIndex = 30
	for _, obj in ipairs(ghost:GetDescendants()) do
		if obj:IsA("GuiObject") then
			obj.ZIndex = math.max(31, obj.ZIndex + 20)
		end
	end

	local frameAbs = battleFrame.AbsolutePosition
	local attackerCenter = attackerCard.AbsolutePosition + (attackerCard.AbsoluteSize * 0.5)
	local targetCenter = targetCard.AbsolutePosition + (targetCard.AbsoluteSize * 0.5)
	ghost.Size = UDim2.fromOffset(attackerCard.AbsoluteSize.X, attackerCard.AbsoluteSize.Y)
	ghost.Position = UDim2.fromOffset(attackerCenter.X - frameAbs.X, attackerCenter.Y - frameAbs.Y)
	ghost.Parent = battleFrame

	local launch = TweenService:Create(
		ghost,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = UDim2.fromOffset(targetCenter.X - frameAbs.X, targetCenter.Y - frameAbs.Y),
			Size = UDim2.fromOffset(math.max(40, math.floor(attackerCard.AbsoluteSize.X * 0.92)), math.max(40, math.floor(attackerCard.AbsoluteSize.Y * 0.92))),
		}
	)
	launch:Play()

	launch.Completed:Connect(function()
		if not (ghost and ghost.Parent) then
			attackerCard:SetAttribute("IsAnimatingAttack", false)
			return
		end

		local impactSound = battleFrame:FindFirstChild("PvpImpactSound")
		if impactSound and impactSound:IsA("Sound") then
			impactSound:Play()
		end
		showBattleImpactPulse(battleFrame)
		emitWorldParticleBurst(Color3.fromRGB(255, 150, 110), 24, 12)

		TweenService:Create(
			ghost,
			TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{BackgroundTransparency = 1, Rotation = 10}
		):Play()
		Debris:AddItem(ghost, 0.3)
		attackerCard:SetAttribute("IsAnimatingAttack", false)
	end)

	return true
end

local function startBattleAmbience()
	if uiState.ambienceTween then
		uiState.ambienceTween:Cancel()
		uiState.ambienceTween = nil
	end
	local vsLabel = battleFrame and battleFrame:FindFirstChild("VsLabel")
	if not (vsLabel and vsLabel:IsA("TextLabel")) then
		return
	end
	vsLabel.TextTransparency = 0
	uiState.ambienceTween = TweenService:Create(
		vsLabel,
		TweenInfo.new(1.05, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{TextTransparency = 0.35, BackgroundTransparency = 0.2}
	)
	uiState.ambienceTween:Play()
end

local function stopBattleAmbience()
	if uiState.ambienceTween then
		uiState.ambienceTween:Cancel()
		uiState.ambienceTween = nil
	end
	local vsLabel = battleFrame and battleFrame:FindFirstChild("VsLabel")
	if vsLabel and vsLabel:IsA("TextLabel") then
		vsLabel.TextTransparency = 0
		vsLabel.BackgroundTransparency = 0.08
	end
end

local function getOrCreateScreenGui(name, displayOrder)
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild(name)
	if gui and gui:IsA("ScreenGui") then
		return gui
	end
	if gui then
		gui:Destroy()
	end
	gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.DisplayOrder = displayOrder
	gui.Parent = playerGui
	return gui
end

local pvpMenuGui = getOrCreateScreenGui("PvpMenuGui", 460)
local pvpBattleGui = getOrCreateScreenGui("PvpBattleGui", 461)
local pvpInviteGui = getOrCreateScreenGui("PvpInviteGui", 462)
local mouse = player:GetMouse()

local oldDuelButton = pvpMenuGui:FindFirstChild("OpenDuelMenuButton")
if oldDuelButton then
	oldDuelButton:Destroy()
end

local radialDismiss = pvpMenuGui:FindFirstChild("RadialDismiss")
if not (radialDismiss and radialDismiss:IsA("TextButton")) then
	if radialDismiss then
		radialDismiss:Destroy()
	end
	radialDismiss = Instance.new("TextButton")
	radialDismiss.Name = "RadialDismiss"
	radialDismiss.Size = UDim2.fromScale(1, 1)
	radialDismiss.Position = UDim2.fromOffset(0, 0)
	radialDismiss.BackgroundTransparency = 1
	radialDismiss.BorderSizePixel = 0
	radialDismiss.Text = ""
	radialDismiss.Visible = false
	radialDismiss.ZIndex = 1
	radialDismiss.Parent = pvpMenuGui
end

local radialRoot = pvpMenuGui:FindFirstChild("RadialRoot")
if not (radialRoot and radialRoot:IsA("Frame")) then
	if radialRoot then
		radialRoot:Destroy()
	end
	radialRoot = Instance.new("Frame")
	radialRoot.Name = "RadialRoot"
	radialRoot.Size = UDim2.fromOffset(220, 220)
	radialRoot.AnchorPoint = Vector2.new(0.5, 0.5)
	radialRoot.Position = UDim2.fromScale(0.5, 0.5)
	radialRoot.BackgroundTransparency = 1
	radialRoot.Visible = false
	radialRoot.ZIndex = 3
	radialRoot.Parent = pvpMenuGui

	local center = Instance.new("TextLabel")
	center.Name = "CenterLabel"
	center.AnchorPoint = Vector2.new(0.5, 0.5)
	center.Size = UDim2.fromOffset(106, 106)
	center.Position = UDim2.fromScale(0.5, 0.5)
	center.BackgroundColor3 = Color3.fromRGB(16, 20, 28)
	center.BackgroundTransparency = 0.08
	center.BorderSizePixel = 0
	center.Text = "Choose\nAction"
	center.Font = Enum.Font.GothamBold
	center.TextSize = 16
	center.TextColor3 = Color3.fromRGB(235, 240, 255)
	center.ZIndex = 4
	center.Parent = radialRoot

	local centerCorner = Instance.new("UICorner")
	centerCorner.CornerRadius = UDim.new(1, 0)
	centerCorner.Parent = center

	local centerStroke = Instance.new("UIStroke")
	centerStroke.Thickness = 2
	centerStroke.Color = Color3.fromRGB(90, 120, 175)
	centerStroke.Transparency = 0.1
	centerStroke.Parent = center
end

local function clearRadialButtons()
	for _, child in ipairs(radialRoot:GetChildren()) do
		if child:IsA("TextButton") and child.Name == "ActionButton" then
			child:Destroy()
		end
	end
end

local function hideRadialMenu()
	radialRoot.Visible = false
	radialDismiss.Visible = false
	uiState.radialTargetUserId = nil
	uiState.radialTargetName = ""
	clearRadialButtons()
end

local function createActionButton(label, angleRadians, color, onClick)
	local center = Vector2.new(radialRoot.AbsoluteSize.X * 0.5, radialRoot.AbsoluteSize.Y * 0.5)
	local radius = RADIAL_RADIUS
	local x = center.X + (math.cos(angleRadians) * radius)
	local y = center.Y + (math.sin(angleRadians) * radius)

	local button = Instance.new("TextButton")
	button.Name = "ActionButton"
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Size = UDim2.fromOffset(92, math.max(38, DeviceContext.getTouchTargetMin()))
	button.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
	button.BackgroundColor3 = color
	button.BackgroundTransparency = 0.06
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 14
	button.TextColor3 = Color3.fromRGB(236, 240, 255)
	button.Text = label
	button.ZIndex = 4
	button.Parent = radialRoot

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 9)
	corner.Parent = button

	button.MouseButton1Click:Connect(onClick)
end

local function showRadialMenuForPlayer(targetPlayer, screenPosition)
	if not targetPlayer or targetPlayer == player then
		hideRadialMenu()
		return
	end

	clearRadialButtons()
	uiState.radialTargetUserId = targetPlayer.UserId
	uiState.radialTargetName = targetPlayer.DisplayName or targetPlayer.Name

	local centerLabel = radialRoot:FindFirstChild("CenterLabel")
	if centerLabel and centerLabel:IsA("TextLabel") then
		centerLabel.Text = tostring(uiState.radialTargetName) .. "\nPvP"
	end

	local viewSize = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local margin = 120
	local clampedX = math.clamp(math.floor(screenPosition.X), margin, math.max(margin, math.floor(viewSize.X - margin)))
	local clampedY = math.clamp(math.floor(screenPosition.Y), margin, math.max(margin, math.floor(viewSize.Y - margin)))
	radialRoot.Position = UDim2.fromOffset(clampedX, clampedY)

	radialRoot.Visible = true
	radialDismiss.Visible = true

	createActionButton("Duel", math.rad(-90), Color3.fromRGB(38, 124, 72), function()
		if uiState.radialTargetUserId then
			challengeRequestEvent:FireServer({
				targetUserId = uiState.radialTargetUserId,
			})
		end
		hideRadialMenu()
	end)

	createActionButton("Close", math.rad(90), Color3.fromRGB(142, 48, 48), function()
		hideRadialMenu()
	end)
end

radialDismiss.MouseButton1Click:Connect(hideRadialMenu)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton2 then
		return
	end

	local targetPart = mouse.Target
	if not targetPart then
		hideRadialMenu()
		return
	end

	local ancestor = targetPart
	local targetPlayer = nil
	while ancestor do
		if ancestor:IsA("Model") then
			targetPlayer = Players:GetPlayerFromCharacter(ancestor)
			if targetPlayer then
				break
			end
		end
		ancestor = ancestor.Parent
	end

	if targetPlayer and targetPlayer ~= player then
		showRadialMenuForPlayer(targetPlayer, Vector2.new(mouse.X, mouse.Y))
	else
		hideRadialMenu()
	end
end)

local inviteFrame = pvpInviteGui:FindFirstChild("InviteFrame")
if not (inviteFrame and inviteFrame:IsA("Frame")) then
	if inviteFrame then
		inviteFrame:Destroy()
	end
	inviteFrame = Instance.new("Frame")
	inviteFrame.Name = "InviteFrame"
	inviteFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	inviteFrame.Size = UDim2.fromOffset(380, 180)
	inviteFrame.Position = UDim2.fromScale(0.5, 0.5)
	inviteFrame.BackgroundColor3 = Color3.fromRGB(18, 24, 34)
	inviteFrame.BackgroundTransparency = 0.04
	inviteFrame.BorderSizePixel = 0
	inviteFrame.Visible = false
	inviteFrame.Parent = pvpInviteGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = inviteFrame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -24, 0, 70)
	title.Position = UDim2.fromOffset(12, 10)
	title.BackgroundTransparency = 1
	title.TextWrapped = true
	title.Text = "Duel Request"
	title.Font = Enum.Font.GothamBold
	title.TextSize = 21
	title.TextColor3 = Color3.fromRGB(244, 246, 255)
	title.Parent = inviteFrame

	local accept = Instance.new("TextButton")
	accept.Name = "Accept"
	accept.Size = UDim2.fromOffset(150, math.max(44, DeviceContext.getTouchTargetMin()))
	accept.Position = UDim2.fromOffset(28, 118)
	accept.BackgroundColor3 = Color3.fromRGB(38, 124, 72)
	accept.BorderSizePixel = 0
	accept.Text = "Accept"
	accept.Font = Enum.Font.GothamBold
	accept.TextSize = 18
	accept.TextColor3 = Color3.fromRGB(245, 255, 245)
	accept.Parent = inviteFrame

	local acceptCorner = Instance.new("UICorner")
	acceptCorner.CornerRadius = UDim.new(0, 8)
	acceptCorner.Parent = accept

	local decline = Instance.new("TextButton")
	decline.Name = "Decline"
	decline.Size = UDim2.fromOffset(150, math.max(44, DeviceContext.getTouchTargetMin()))
	decline.Position = UDim2.fromOffset(202, 118)
	decline.BackgroundColor3 = Color3.fromRGB(142, 48, 48)
	decline.BorderSizePixel = 0
	decline.Text = "Decline"
	decline.Font = Enum.Font.GothamBold
	decline.TextSize = 18
	decline.TextColor3 = Color3.fromRGB(255, 244, 244)
	decline.Parent = inviteFrame

	local declineCorner = Instance.new("UICorner")
	declineCorner.CornerRadius = UDim.new(0, 8)
	declineCorner.Parent = decline

	accept.MouseButton1Click:Connect(function()
		if not uiState.pendingInviteId then
			return
		end
		inviteResponseEvent:FireServer({
			inviteId = uiState.pendingInviteId,
			accepted = true,
		})
		uiState.pendingInviteId = nil
		uiState.pendingInviteFrom = ""
		inviteFrame.Visible = false
	end)

	decline.MouseButton1Click:Connect(function()
		if not uiState.pendingInviteId then
			return
		end
		inviteResponseEvent:FireServer({
			inviteId = uiState.pendingInviteId,
			accepted = false,
		})
		uiState.pendingInviteId = nil
		uiState.pendingInviteFrom = ""
		inviteFrame.Visible = false
	end)
end

battleFrame = pvpBattleGui:FindFirstChild("BattleFrame")
if not (battleFrame and battleFrame:IsA("Frame")) then
	if battleFrame then
		battleFrame:Destroy()
	end
	battleFrame = Instance.new("Frame")
	battleFrame.Name = "BattleFrame"
	battleFrame.Size = UDim2.fromOffset(1220, 760)
	battleFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	battleFrame.Position = UDim2.fromScale(0.5, 0.5)
	battleFrame.BackgroundColor3 = Color3.fromRGB(10, 13, 20)
	battleFrame.BackgroundTransparency = 0.06
	battleFrame.BorderSizePixel = 0
	battleFrame.Visible = false
	battleFrame.Parent = pvpBattleGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = battleFrame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -24, 0, 48)
	title.Position = UDim2.fromOffset(12, 10)
	title.BackgroundTransparency = 1
	title.Text = "Combat Deck Duel"
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.Font = Enum.Font.GothamBold
	title.TextSize = 34
	title.TextColor3 = Color3.fromRGB(238, 242, 255)
	title.Parent = battleFrame

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.Size = UDim2.new(1, -24, 0, 30)
	status.Position = UDim2.fromOffset(12, 62)
	status.BackgroundTransparency = 1
	status.Text = "Waiting for decks..."
	status.TextXAlignment = Enum.TextXAlignment.Center
	status.Font = Enum.Font.GothamMedium
	status.TextSize = 20
	status.TextColor3 = Color3.fromRGB(190, 205, 235)
	status.Parent = battleFrame

	local vs = Instance.new("TextLabel")
	vs.Name = "VsLabel"
	vs.Size = UDim2.fromOffset(124, 54)
	vs.AnchorPoint = Vector2.new(0.5, 0.5)
	vs.Position = UDim2.new(0.5, 0, 0.5, 26)
	vs.BackgroundColor3 = Color3.fromRGB(24, 30, 44)
	vs.BackgroundTransparency = 0.08
	vs.BorderSizePixel = 0
	vs.Text = "VS"
	vs.Font = Enum.Font.GothamBlack
	vs.TextSize = 32
	vs.TextColor3 = Color3.fromRGB(247, 250, 255)
	vs.ZIndex = 5
	vs.Parent = battleFrame

	local vsCorner = Instance.new("UICorner")
	vsCorner.CornerRadius = UDim.new(1, 0)
	vsCorner.Parent = vs

	local leftPanel = Instance.new("Frame")
	leftPanel.Name = "LeftPanel"
	leftPanel.Size = UDim2.new(1, -28, 0, 304)
	leftPanel.Position = UDim2.fromOffset(14, 102)
	leftPanel.BackgroundColor3 = Color3.fromRGB(21, 33, 50)
	leftPanel.BackgroundTransparency = 0.2
	leftPanel.BorderSizePixel = 0
	leftPanel.Parent = battleFrame

	local rightPanel = Instance.new("Frame")
	rightPanel.Name = "RightPanel"
	rightPanel.Size = UDim2.new(1, -28, 0, 304)
	rightPanel.Position = UDim2.new(0, 14, 1, -318)
	rightPanel.BackgroundColor3 = Color3.fromRGB(48, 24, 24)
	rightPanel.BackgroundTransparency = 0.2
	rightPanel.BorderSizePixel = 0
	rightPanel.Parent = battleFrame

	for _, panel in ipairs({leftPanel, rightPanel}) do
		local panelCorner = Instance.new("UICorner")
		panelCorner.CornerRadius = UDim.new(0, 10)
		panelCorner.Parent = panel

		local panelStroke = Instance.new("UIStroke")
		panelStroke.Thickness = 1
		panelStroke.Color = Color3.fromRGB(96, 118, 160)
		panelStroke.Transparency = 0.28
		panelStroke.Parent = panel

		local header = Instance.new("TextLabel")
		header.Name = "Header"
		header.Size = UDim2.new(1, -12, 0, 28)
		header.Position = UDim2.fromOffset(6, 4)
		header.BackgroundTransparency = 1
		header.TextXAlignment = Enum.TextXAlignment.Center
		header.Font = Enum.Font.GothamBold
		header.TextSize = 18
		header.TextColor3 = Color3.fromRGB(240, 244, 255)
		header.Text = "Team"
		header.Parent = panel

		local cardRow = Instance.new("Frame")
		cardRow.Name = "CardRow"
		cardRow.Size = UDim2.new(1, -16, 0, 258)
		cardRow.Position = UDim2.fromOffset(8, 34)
		cardRow.BackgroundTransparency = 1
		cardRow.Parent = panel

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, 12)
		layout.Parent = cardRow
	end

	local surrender = Instance.new("TextButton")
	surrender.Name = "Surrender"
	surrender.Size = UDim2.fromOffset(152, math.max(44, DeviceContext.getTouchTargetMin()))
	surrender.Position = UDim2.new(1, -164, 0, 12)
	surrender.BackgroundColor3 = Color3.fromRGB(138, 40, 40)
	surrender.BorderSizePixel = 0
	surrender.Text = "Surrender"
	surrender.Font = Enum.Font.GothamBold
	surrender.TextSize = 20
	surrender.TextColor3 = Color3.fromRGB(255, 246, 246)
	surrender.Parent = battleFrame

	local surrenderCorner = Instance.new("UICorner")
	surrenderCorner.CornerRadius = UDim.new(0, 8)
	surrenderCorner.Parent = surrender

	surrender.MouseButton1Click:Connect(function()
		if not uiState.sessionId then
			return
		end
		actionEvent:FireServer({
			actionType = PvpProtocol.ActionType.Surrender,
			sessionId = uiState.sessionId,
		})
	end)
end

local function buildCombatDeckSnapshot()
	local deck = {}
	local playerGui = player:FindFirstChild("PlayerGui")
	local mainUI = playerGui and playerGui:FindFirstChild("MainUI")
	local combatDeckFrame = mainUI and mainUI:FindFirstChild("CombatDeckFrame")
	if not (combatDeckFrame and combatDeckFrame:IsA("GuiObject")) then
		return deck
	end

	for i = 1, COMBAT_SLOT_COUNT do
		local slot = combatDeckFrame:FindFirstChild("CombatSlot" .. tostring(i))
		if slot then
			for _, child in ipairs(slot:GetChildren()) do
				if child:IsA("GuiButton") then
					local cardId = child:GetAttribute("CardId") or child.Name
					if type(cardId) == "string" and cardId ~= "" then
						table.insert(deck, {
							slotIndex = i,
							cardId = cardId,
						})
					end
					break
				end
			end
		end
	end
	return deck
end

local function createDeckCardView(state)
	local frame = Instance.new("Frame")
	frame.Name = "SlotCard" .. tostring(state.slotIndex)
	frame.Size = UDim2.fromOffset(204, 228)
	frame.BackgroundColor3 = Color3.fromRGB(22, 28, 40)
	frame.BackgroundTransparency = 0.06
	frame.BorderSizePixel = 0
	frame.LayoutOrder = state.slotIndex
	frame:SetAttribute("SlotIndex", state.slotIndex)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local art = Instance.new("ImageLabel")
	art.Name = "Art"
	art.Size = UDim2.new(1, -10, 1, -74)
	art.Position = UDim2.fromOffset(5, 5)
	art.BackgroundColor3 = Color3.fromRGB(13, 16, 24)
	art.BackgroundTransparency = 0.04
	art.BorderSizePixel = 0
	art.Parent = frame

	local artCorner = Instance.new("UICorner")
	artCorner.CornerRadius = UDim.new(0, 8)
	artCorner.Parent = art

	local data = CardDatabase.GetCardData(state.cardId)
	local imageObj = findCardArtDecal(state.cardId)
	local videoAssetId = data and data.VideoAssetId
	if type(videoAssetId) == "string" and videoAssetId ~= "" and videoAssetId ~= "rbxassetid://0" then
		local artVideo = Instance.new("VideoFrame")
		artVideo.Name = "ArtVideo"
		artVideo.Size = UDim2.fromScale(1, 1)
		artVideo.Position = UDim2.fromOffset(0, 0)
		artVideo.BackgroundTransparency = 1
		artVideo.BorderSizePixel = 0
		artVideo.ZIndex = art.ZIndex + 1
		artVideo.Visible = true
		artVideo.Parent = art
		ensureBattleVideoFramePlayback(artVideo, videoAssetId)
		art.Image = ""
	elseif imageObj then
		art.Image = imageObj.Texture
	elseif data and type(data.ArtAssetId) == "string" and data.ArtAssetId ~= "" and data.ArtAssetId ~= "rbxassetid://0" then
		art.Image = data.ArtAssetId
	end
	art.ScaleType = resolveArtScaleType(data, imageObj)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, -8, 0, 26)
	nameLabel.Position = UDim2.new(0, 4, 1, -66)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 15
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.TextColor3 = Color3.fromRGB(240, 244, 255)
	nameLabel.Text = tostring(state.cardName or state.cardId or "Card")
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = frame

	local atkLabel = Instance.new("TextLabel")
	atkLabel.Name = "AtkLabel"
	atkLabel.Size = UDim2.new(0.5, -6, 0, 24)
	atkLabel.Position = UDim2.new(0, 4, 1, -30)
	atkLabel.BackgroundColor3 = Color3.fromRGB(78, 24, 19)
	atkLabel.BackgroundTransparency = 1
	atkLabel.BorderSizePixel = 0
	atkLabel.Font = Enum.Font.GothamBold
	atkLabel.TextSize = 16
	atkLabel.TextColor3 = Color3.fromRGB(255, 126, 104)
	atkLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	atkLabel.TextStrokeTransparency = 0.05
	atkLabel.Text = "ATK " .. CardDatabase.FormatAttack(math.max(1, math.floor(tonumber(state.attack) or 1)))
	atkLabel.Parent = frame

	local atkLabelStroke = Instance.new("UIStroke")
	atkLabelStroke.Thickness = 1
	atkLabelStroke.Color = Color3.fromRGB(0, 0, 0)
	atkLabelStroke.Transparency = 0.32
	atkLabelStroke.Parent = atkLabel

	local atkCorner = Instance.new("UICorner")
	atkCorner.CornerRadius = UDim.new(0, 6)
	atkCorner.Parent = atkLabel

	local hpLabel = Instance.new("TextLabel")
	hpLabel.Name = "HpLabel"
	hpLabel.Size = UDim2.new(0.5, -6, 0, 24)
	hpLabel.Position = UDim2.new(0.5, 2, 1, -30)
	hpLabel.BackgroundColor3 = Color3.fromRGB(18, 74, 28)
	hpLabel.BackgroundTransparency = 1
	hpLabel.BorderSizePixel = 0
	hpLabel.Font = Enum.Font.GothamBold
	hpLabel.TextSize = 16
	hpLabel.TextColor3 = Color3.fromRGB(126, 255, 152)
	hpLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	hpLabel.TextStrokeTransparency = 0.05
	hpLabel.Text = "HP --"
	hpLabel.Parent = frame

	local hpLabelStroke = Instance.new("UIStroke")
	hpLabelStroke.Thickness = 1
	hpLabelStroke.Color = Color3.fromRGB(0, 0, 0)
	hpLabelStroke.Transparency = 0.32
	hpLabelStroke.Parent = hpLabel

	local hpCorner = Instance.new("UICorner")
	hpCorner.CornerRadius = UDim.new(0, 6)
	hpCorner.Parent = hpLabel

	local cardBorderStroke = Instance.new("UIStroke")
	cardBorderStroke.Name = "CardBorderStroke"
	cardBorderStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cardBorderStroke.Thickness = 2
	cardBorderStroke.Color = Color3.fromRGB(130, 154, 214)
	cardBorderStroke.Transparency = 0.22
	cardBorderStroke.Parent = frame

	local drBar = Instance.new("Frame")
	drBar.Name = "OutgoingDrDebuffBar"
	drBar.Visible = false
	drBar.Size = UDim2.new(1, -10, 0, 22)
	drBar.Position = UDim2.new(0, 5, 0, 6)
	drBar.BackgroundColor3 = Color3.fromRGB(48, 26, 68)
	drBar.BackgroundTransparency = 0.15
	drBar.BorderSizePixel = 0
	drBar.ZIndex = 12
	drBar.Parent = frame
	local drBarCorner = Instance.new("UICorner")
	drBarCorner.CornerRadius = UDim.new(0, 6)
	drBarCorner.Parent = drBar
	local drBarStroke = Instance.new("UIStroke")
	drBarStroke.Thickness = 1
	drBarStroke.Color = Color3.fromRGB(180, 130, 255)
	drBarStroke.Transparency = 0.35
	drBarStroke.Parent = drBar
	local drText = Instance.new("TextLabel")
	drText.Name = "DrText"
	drText.Size = UDim2.fromScale(1, 1)
	drText.BackgroundTransparency = 1
	drText.Font = Enum.Font.GothamBold
	drText.TextSize = 13
	drText.TextColor3 = Color3.fromRGB(235, 200, 255)
	drText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	drText.TextStrokeTransparency = 0.4
	drText.Text = "DR 10% · 0.0s"
	drText.Parent = drBar

	local spdBar = Instance.new("Frame")
	spdBar.Name = "AtkSpeedBuffBar"
	spdBar.Visible = false
	spdBar.Size = UDim2.new(1, -10, 0, 22)
	spdBar.Position = UDim2.new(0, 5, 0, 6)
	spdBar.BackgroundColor3 = Color3.fromRGB(22, 48, 72)
	spdBar.BackgroundTransparency = 0.12
	spdBar.BorderSizePixel = 0
	spdBar.ZIndex = 13
	spdBar.Parent = frame
	local spdBarCorner = Instance.new("UICorner")
	spdBarCorner.CornerRadius = UDim.new(0, 6)
	spdBarCorner.Parent = spdBar
	local spdBarStroke = Instance.new("UIStroke")
	spdBarStroke.Thickness = 1
	spdBarStroke.Color = Color3.fromRGB(100, 190, 255)
	spdBarStroke.Transparency = 0.3
	spdBarStroke.Parent = spdBar
	local spdText = Instance.new("TextLabel")
	spdText.Name = "SpdText"
	spdText.Size = UDim2.fromScale(1, 1)
	spdText.BackgroundTransparency = 1
	spdText.Font = Enum.Font.GothamBold
	spdText.TextSize = 13
	spdText.TextColor3 = Color3.fromRGB(160, 225, 255)
	spdText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	spdText.TextStrokeTransparency = 0.4
	spdText.Text = "ATK SPD +0% · 0.0s"
	spdText.Parent = spdBar

	local healBar = Instance.new("Frame")
	healBar.Name = "HealingDebuffBar"
	healBar.Visible = false
	healBar.Size = UDim2.new(1, -10, 0, 22)
	healBar.Position = UDim2.new(0, 5, 0, 6)
	healBar.BackgroundColor3 = Color3.fromRGB(62, 34, 16)
	healBar.BackgroundTransparency = 0.12
	healBar.BorderSizePixel = 0
	healBar.ZIndex = 13
	healBar.Parent = frame
	local healCorner = Instance.new("UICorner")
	healCorner.CornerRadius = UDim.new(0, 6)
	healCorner.Parent = healBar
	local healStroke = Instance.new("UIStroke")
	healStroke.Thickness = 1
	healStroke.Color = Color3.fromRGB(255, 190, 95)
	healStroke.Transparency = 0.3
	healStroke.Parent = healBar
	local healText = Instance.new("TextLabel")
	healText.Name = "HealText"
	healText.Size = UDim2.fromScale(1, 1)
	healText.BackgroundTransparency = 1
	healText.Font = Enum.Font.GothamBold
	healText.TextSize = 13
	healText.TextColor3 = Color3.fromRGB(255, 220, 150)
	healText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	healText.TextStrokeTransparency = 0.4
	healText.Text = "HEAL DOWN 25% · 0.0s"
	healText.Parent = healBar

	local vulnBar = Instance.new("Frame")
	vulnBar.Name = "IncomingDamageBonusBar"
	vulnBar.Visible = false
	vulnBar.Size = UDim2.new(1, -10, 0, 22)
	vulnBar.Position = UDim2.new(0, 5, 0, 6)
	vulnBar.BackgroundColor3 = Color3.fromRGB(48, 22, 62)
	vulnBar.BackgroundTransparency = 0.12
	vulnBar.BorderSizePixel = 0
	vulnBar.ZIndex = 13
	vulnBar.Parent = frame
	local vulnCorner = Instance.new("UICorner")
	vulnCorner.CornerRadius = UDim.new(0, 6)
	vulnCorner.Parent = vulnBar
	local vulnStroke = Instance.new("UIStroke")
	vulnStroke.Thickness = 1
	vulnStroke.Color = Color3.fromRGB(210, 140, 255)
	vulnStroke.Transparency = 0.3
	vulnStroke.Parent = vulnBar
	local vulnText = Instance.new("TextLabel")
	vulnText.Name = "VulnText"
	vulnText.Size = UDim2.fromScale(1, 1)
	vulnText.BackgroundTransparency = 1
	vulnText.Font = Enum.Font.GothamBold
	vulnText.TextSize = 13
	vulnText.TextColor3 = Color3.fromRGB(230, 190, 255)
	vulnText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	vulnText.TextStrokeTransparency = 0.4
	vulnText.Text = "MARKED +0% · 0.0s"
	vulnText.Parent = vulnBar

	local sealBar = Instance.new("Frame")
	sealBar.Name = "SealDebuffBar"
	sealBar.Visible = false
	sealBar.Size = UDim2.new(1, -10, 0, 22)
	sealBar.Position = UDim2.new(0, 5, 0, 6)
	sealBar.BackgroundColor3 = Color3.fromRGB(58, 42, 8)
	sealBar.BackgroundTransparency = 0.1
	sealBar.BorderSizePixel = 0
	sealBar.ZIndex = 13
	sealBar.Parent = frame
	local sealCorner = Instance.new("UICorner")
	sealCorner.CornerRadius = UDim.new(0, 6)
	sealCorner.Parent = sealBar
	local sealStroke = Instance.new("UIStroke")
	sealStroke.Thickness = 1.2
	sealStroke.Color = Color3.fromRGB(255, 210, 90)
	sealStroke.Transparency = 0.2
	sealStroke.Parent = sealBar
	local sealText = Instance.new("TextLabel")
	sealText.Name = "SealText"
	sealText.Size = UDim2.fromScale(1, 1)
	sealText.BackgroundTransparency = 1
	sealText.Font = Enum.Font.GothamBold
	sealText.TextSize = 12
	sealText.TextColor3 = Color3.fromRGB(255, 235, 160)
	sealText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	sealText.TextStrokeTransparency = 0.35
	sealText.Text = "SEAL · abilities silenced · 0.0s"
	sealText.Parent = sealBar

	local controlBar = Instance.new("Frame")
	controlBar.Name = "ControlDebuffBar"
	controlBar.Visible = false
	controlBar.Size = UDim2.new(1, -10, 0, 22)
	controlBar.Position = UDim2.new(0, 5, 0, 6)
	controlBar.BackgroundColor3 = Color3.fromRGB(70, 18, 18)
	controlBar.BackgroundTransparency = 0.12
	controlBar.BorderSizePixel = 0
	controlBar.ZIndex = 14
	controlBar.Parent = frame
	local controlCorner = Instance.new("UICorner")
	controlCorner.CornerRadius = UDim.new(0, 6)
	controlCorner.Parent = controlBar
	local controlStroke = Instance.new("UIStroke")
	controlStroke.Name = "ControlStroke"
	controlStroke.Thickness = 1.5
	controlStroke.Color = Color3.fromRGB(255, 120, 120)
	controlStroke.Transparency = 0.25
	controlStroke.Parent = controlBar
	local controlText = Instance.new("TextLabel")
	controlText.Name = "ControlText"
	controlText.Size = UDim2.fromScale(1, 1)
	controlText.BackgroundTransparency = 1
	controlText.Font = Enum.Font.GothamBold
	controlText.TextSize = 13
	controlText.TextColor3 = Color3.fromRGB(255, 160, 160)
	controlText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	controlText.TextStrokeTransparency = 0.4
	controlText.Text = "STUN · 0.0s"
	controlText.Parent = controlBar

	return frame
end

local function renderPanel(panel, titleText, states)
	local header = panel:FindFirstChild("Header")
	if header and header:IsA("TextLabel") then
		header.Text = titleText
	end

	local cardRow = panel:FindFirstChild("CardRow")
	if not (cardRow and cardRow:IsA("Frame")) then
		return
	end

	local bySlot = {}
	for _, state in ipairs(states or {}) do
		if type(state.slotIndex) == "number" then
			bySlot[state.slotIndex] = state
		end
	end

	-- Resolve FoilChance once for the whole deck render.
	local _pvpStats = ClientStateManager.getStats and ClientStateManager.getStats() or {}
	local _pvpFoilChance = _pvpStats.FoilChance or _pvpStats.BorderChance or 0

	for i = 1, COMBAT_SLOT_COUNT do
		local state = bySlot[i]
		local cardName = "SlotCard" .. tostring(i)
		local card = cardRow:FindFirstChild(cardName)
		if state then
			local isNewCard = not (card and card:IsA("Frame"))
			if isNewCard then
				card = createDeckCardView(state)
				card.Parent = cardRow
				-- Apply foil to bordered cards on first creation only (not on
				-- stat-update rebuilds) so we don't double-attach the overlay.
				local visualStyle = CardVisualResolver.resolve(
					tostring(state.cardId or ""), _pvpFoilChance, nil
				)
				if visualStyle.isBordered then
					local outerStroke = card:FindFirstChild("CardBorderStroke")
					if outerStroke and outerStroke:IsA("UIStroke") then
						if visualStyle.tierKey == "Rainbow" then
							RainbowBorderStroke.attach(outerStroke)
						else
							RainbowBorderStroke.detach(outerStroke)
							outerStroke.Color = visualStyle.strokeColor
						end
					end
					local foilCtrl = HoloFoilController.Attach(card, visualStyle.foilOpts)
					card.Destroying:Connect(function()
						if outerStroke and outerStroke.Parent then
							RainbowBorderStroke.detach(outerStroke)
						end
						foilCtrl:Destroy()
					end)
				end
			end

			local nameLabel = card:FindFirstChild("NameLabel")
			if nameLabel and nameLabel:IsA("TextLabel") then
				nameLabel.Text = tostring(state.cardName or state.cardId or "Card")
			end

			local hp = math.max(0, math.floor(tonumber(state.health) or 0))
			local maxHp = math.max(1, math.floor(tonumber(state.maxHealth) or 1))
			local attack = math.max(1, math.floor(tonumber(state.attack) or 1))

			local atkLabel = card:FindFirstChild("AtkLabel")
			if atkLabel and atkLabel:IsA("TextLabel") then
				atkLabel.Text = "ATK " .. CardDatabase.FormatAttack(attack)
			end
			local hpLabel = card:FindFirstChild("HpLabel")
			if hpLabel and hpLabel:IsA("TextLabel") then
				hpLabel.Text = string.format("HP %s/%s", CardDatabase.FormatAttack(hp), CardDatabase.FormatAttack(maxHp))
			end

			local drBar = card:FindFirstChild("OutgoingDrDebuffBar")
			local drText = drBar and drBar:FindFirstChild("DrText")
			local drVisible = false
			if drBar and drText then
				local rem = tonumber(state.outgoingAttackDebuffRemainingSec) or 0
				local pct = tonumber(state.outgoingAttackDebuffPercent) or 0
				if rem > 0 and pct > 0 then
					drBar.Visible = true
					drVisible = true
					local pctDisp = math.floor(pct * 100 + 0.5)
					drText.Text = string.format("DR %d%% · %.1fs", pctDisp, rem)
				else
					drBar.Visible = false
				end
			end

			local spdBar = card:FindFirstChild("AtkSpeedBuffBar")
			local spdText = spdBar and spdBar:FindFirstChild("SpdText")
			local spdVisible = false
			if spdBar and spdText then
				local spdRem = tonumber(state.speedBoostRemainingSec) or 0
				local spdMag = tonumber(state.speedBoostMagnitude) or 0
				if spdRem > 0 and spdMag > 0 then
					spdBar.Visible = true
					spdVisible = true
					local spdPct = math.floor(spdMag * 100 + 0.5)
					spdText.Text = string.format("ATK SPD +%d%% · %.1fs", spdPct, spdRem)
					spdBar.Position = drVisible and UDim2.new(0, 5, 0, 30) or UDim2.new(0, 5, 0, 6)
				else
					spdBar.Visible = false
					spdVisible = false
				end
			end

			local healBar = card:FindFirstChild("HealingDebuffBar")
			local healText = healBar and healBar:FindFirstChild("HealText")
			local healVisible = false
			if healBar and healText then
				local healRem = tonumber(state.healingReductionRemainingSec) or 0
				local healFrac = tonumber(state.healingReductionFraction) or 0
				if healRem > 0 and healFrac > 0 then
					healBar.Visible = true
					healVisible = true
					local healPct = math.floor(healFrac * 100 + 0.5)
					local barsAbove = (drVisible and 1 or 0) + (spdVisible and 1 or 0)
					healBar.Position = UDim2.new(0, 5, 0, 6 + (barsAbove * 24))
					healText.Text = string.format("HEAL DOWN %d%% · %.1fs", healPct, healRem)
				else
					healBar.Visible = false
				end
			end

			local vulnBar = card:FindFirstChild("IncomingDamageBonusBar")
			local vulnText = vulnBar and vulnBar:FindFirstChild("VulnText")
			local vulnVisible = false
			if vulnBar and vulnText then
				local vulnRem = tonumber(state.incomingDamageBonusRemainingSec) or 0
				local vulnFrac = tonumber(state.incomingDamageBonusFraction) or 0
				if vulnRem > 0 and vulnFrac > 0 then
					vulnBar.Visible = true
					vulnVisible = true
					local vulnPct = math.floor(vulnFrac * 100 + 0.5)
					local barsAbove = (drVisible and 1 or 0) + (spdVisible and 1 or 0) + (healVisible and 1 or 0)
					vulnBar.Position = UDim2.new(0, 5, 0, 6 + (barsAbove * 24))
					vulnText.Text = string.format("MARKED +%d%% · %.1fs", vulnPct, vulnRem)
				else
					vulnBar.Visible = false
				end
			end

			local sealBar = card:FindFirstChild("SealDebuffBar")
			local sealText = sealBar and sealBar:FindFirstChild("SealText")
			local sealVisible = false
			if sealBar and sealText then
				local sealRem = tonumber(state.sealRemainingSec) or 0
				if sealRem > 0 then
					sealBar.Visible = true
					sealVisible = true
					local barsAbove = (drVisible and 1 or 0) + (spdVisible and 1 or 0) + (healVisible and 1 or 0) + (vulnVisible and 1 or 0)
					sealBar.Position = UDim2.new(0, 5, 0, 6 + (barsAbove * 24))
					sealText.Text = string.format("SEAL · abilities silenced · %.1fs", sealRem)
				else
					sealBar.Visible = false
				end
			end

			local controlBar = card:FindFirstChild("ControlDebuffBar")
			local controlText = controlBar and controlBar:FindFirstChild("ControlText")
			if controlBar and controlText then
				local stunRem = tonumber(state.stunRemainingSec) or 0
				local dodgeDisabledRem = tonumber(state.dodgeDisabledRemainingSec) or 0

				local rem = 0
				local label = nil
				local textColor = Color3.fromRGB(255, 160, 160)
				local strokeColor = Color3.fromRGB(255, 120, 120)
				local bgColor = Color3.fromRGB(70, 18, 18)

				if stunRem > 0 then
					rem = stunRem
					label = "STUN"
					textColor = Color3.fromRGB(255, 160, 160)
					strokeColor = Color3.fromRGB(255, 120, 120)
					bgColor = Color3.fromRGB(70, 18, 18)
				elseif dodgeDisabledRem > 0 then
					rem = dodgeDisabledRem
					label = "DODGE OFF"
					textColor = Color3.fromRGB(155, 240, 255)
					strokeColor = Color3.fromRGB(110, 230, 255)
					bgColor = Color3.fromRGB(20, 55, 70)
				end

				if rem > 0 and label then
					controlBar.Visible = true
					local barsAbove = (drVisible and 1 or 0) + (spdVisible and 1 or 0) + (healVisible and 1 or 0) + (vulnVisible and 1 or 0) + (sealVisible and 1 or 0)
					local y = 6 + (barsAbove * 24)
					controlBar.Position = UDim2.new(0, 5, 0, y)

					controlBar.BackgroundColor3 = bgColor
					local controlStroke = controlBar:FindFirstChild("ControlStroke")
					if controlStroke and controlStroke:IsA("UIStroke") then
						controlStroke.Color = strokeColor
					end
					controlText.TextColor3 = textColor
					controlText.Text = string.format("%s · %.1fs", label, rem)
				else
					controlBar.Visible = false
				end
			end

			if hp > 0 then
				if card:GetAttribute("DeathAnimated") then
					card:SetAttribute("DeathAnimated", false)
					card.Rotation = 0
				end
				card.BackgroundTransparency = 0.06
				card.BackgroundColor3 = Color3.fromRGB(22, 28, 40)
			else
				if not card:GetAttribute("DeathAnimated") then
					playCardDeathAnimation(card)
				end
				card.BackgroundTransparency = 0.35
				card.BackgroundColor3 = Color3.fromRGB(32, 26, 26)
			end
		elseif card then
			card:Destroy()
		end
	end
end

local function animateRowPulse(panel, slotIndex, hitColor)
	if not panel then
		return
	end
	local cardRow = panel:FindFirstChild("CardRow")
	local card = cardRow and cardRow:FindFirstChild("SlotCard" .. tostring(slotIndex))
	if not (card and card:IsA("Frame")) then
		return
	end

	local baseColor = card.BackgroundColor3
	local baseSize = card.Size
	local pulseSize = UDim2.fromOffset(
		baseSize.X.Offset + 8,
		baseSize.Y.Offset + 8
	)
	TweenService:Create(
		card,
		TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundColor3 = hitColor, Size = pulseSize}
	):Play()
	task.delay(0.16, function()
		if card and card.Parent then
			TweenService:Create(
				card,
				TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{BackgroundColor3 = baseColor, Size = baseSize}
			):Play()
		end
	end)
end

local function showDamagePopup(panel, slotIndex, attack, staggerDelay, targetKeyPrefix)
	if not panel or type(attack) ~= "table" then
		return
	end
	local cardRow = panel:FindFirstChild("CardRow")
	local card = cardRow and cardRow:FindFirstChild("SlotCard" .. tostring(slotIndex))
	if not (card and card:IsA("Frame")) then
		return
	end
	local dmg = tonumber(attack.damage) or 0
	local cat = DamagePopupManager.MapCategory(dmg, attack.isCrit, attack.isDodged, attack.absorbed)
	local show = cat == "Dodge" or cat == "ShieldAbsorb" or dmg > 0
	if not show then
		return
	end
	DamagePopupManager.EnqueueOnCard({
		sessionId = uiState.sessionId,
		targetKey = tostring(targetKeyPrefix) .. "_" .. tostring(slotIndex),
		cardFrame = card,
		amount = dmg,
		absorbed = attack.absorbed,
		category = cat,
		contextKind = "PvpHit",
		sequence = tonumber(attack.hitSeq) or 0,
		staggerDelay = tonumber(staggerDelay) or 0,
	})
end

local function getAbilityEffectStyle(effectType)
	if effectType == "HealLowestAlly" then
		return Color3.fromRGB(86, 214, 122), "HEAL"
	end
	if effectType == "TeamAttackSpeedBoost" then
		return Color3.fromRGB(90, 184, 255), "ATK SPD+"
	end
	if effectType == "TeamAttackDamageBoost" then
		return Color3.fromRGB(255, 154, 76), "ATK DMG+"
	end
	if effectType == "EnemyPartyAttackDown" then
		return Color3.fromRGB(190, 130, 255), "ATK DOWN"
	end
	if effectType == "StunOneEnemy" or effectType == "StunAllEnemies" then
		return Color3.fromRGB(255, 110, 110), "STUN"
	end
	if effectType == "SealOneEnemy" then
		return Color3.fromRGB(255, 215, 95), "SEAL"
	end
	if effectType == "DisableDodgeAllEnemies" then
		return Color3.fromRGB(110, 230, 255), "DODGE OFF"
	end
	return Color3.fromRGB(220, 220, 220), "BUFF"
end

local function getBuffNoticeText(abilityEvent, isAlly)
	if type(abilityEvent) ~= "table" then
		return nil
	end

	local sideLabel = isAlly and "ALLY" or "ENEMY"
	local effectType = tostring(abilityEvent.effectType or "")
	local magnitudePercent = math.max(0, math.floor((tonumber(abilityEvent.magnitude) or 0) * 100 + 0.5))
	local durationSeconds = math.max(0, tonumber(abilityEvent.durationSeconds) or 0)

	if effectType == "TeamAttackSpeedBoost" then
		return string.format("%s BUFF: +%d%% ATK SPD (%.1fs)", sideLabel, magnitudePercent, durationSeconds)
	end
	if effectType == "TeamAttackDamageBoost" then
		return string.format("%s BUFF: +%d%% ATK DMG (%.1fs)", sideLabel, magnitudePercent, durationSeconds)
	end
	if effectType == "EnemyPartyAttackDown" then
		return string.format("Enemy ATK -%d%% (%.1fs)", magnitudePercent, durationSeconds)
	end
	if effectType == "StunOneEnemy" or effectType == "StunAllEnemies" then
		return string.format("Enemy STUN (%.1fs)", durationSeconds)
	end
	if effectType == "SealOneEnemy" then
		return string.format("Enemy SEAL (%.1fs)", durationSeconds)
	end
	if effectType == "DisableDodgeAllEnemies" then
		return string.format("Enemy DODGE OFF (%.1fs)", durationSeconds)
	end

	return nil
end

local function playBuffScreenPulse(color)
	if not (battleFrame and battleFrame.Parent) then
		return
	end

	local pulse = Instance.new("Frame")
	pulse.Name = "BuffScreenPulse"
	pulse.Size = UDim2.fromScale(1, 1)
	pulse.Position = UDim2.fromOffset(0, 0)
	pulse.BackgroundColor3 = color
	pulse.BackgroundTransparency = 0.97
	pulse.BorderSizePixel = 0
	pulse.ZIndex = 35
	pulse.Parent = battleFrame

	TweenService:Create(
		pulse,
		TweenInfo.new(fxTime(0.18), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundTransparency = 0.9}
	):Play()

	task.delay(fxTime(0.14), function()
		if pulse and pulse.Parent then
			TweenService:Create(
				pulse,
				TweenInfo.new(fxTime(0.36), Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{BackgroundTransparency = 1}
			):Play()
		end
	end)

	Debris:AddItem(pulse, fxLife(0.58))
end

local function playAbilityThemeFx(card, color, effectType)
	local effect = tostring(effectType or "")
	local burstNow = os.clock()
	if (abilityWorldBurstCooldownByEffect[effect] or 0) <= burstNow then
		emitAbilityWorldParticleBurst(effect, color)
		abilityWorldBurstCooldownByEffect[effect] = burstNow + ABILITY_WORLD_BURST_COOLDOWN_SECONDS
	end

	if effect == "TeamAttackSpeedBoost" then
		for _ = 1, 10 do
			local arc = Instance.new("Frame")
			arc.Name = "SpeedArc"
			arc.AnchorPoint = Vector2.new(0.5, 0.5)
			arc.Size = UDim2.fromOffset(math.random(18, 34), math.random(2, 3))
			arc.Position = UDim2.fromScale(math.random(20, 80) / 100, math.random(20, 80) / 100)
			arc.Rotation = math.random(-70, 70)
			arc.BackgroundColor3 = color
			arc.BackgroundTransparency = 0.12
			arc.BorderSizePixel = 0
			arc.ZIndex = 25
			arc.Parent = card

			TweenService:Create(
				arc,
				TweenInfo.new(fxTime(0.3), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{Position = UDim2.fromScale(math.random(10, 90) / 100, math.random(10, 90) / 100), BackgroundTransparency = 1}
			):Play()
			Debris:AddItem(arc, fxLife(0.38))
		end
	elseif effect == "TeamAttackDamageBoost" then
		local shock = Instance.new("Frame")
		shock.Name = "DamageShock"
		shock.AnchorPoint = Vector2.new(0.5, 0.5)
		shock.Size = UDim2.fromOffset(20, 20)
		shock.Position = UDim2.fromScale(0.5, 0.5)
		shock.BackgroundTransparency = 1
		shock.BorderSizePixel = 0
		shock.ZIndex = 25
		shock.Parent = card

		local shockStroke = Instance.new("UIStroke")
		shockStroke.Thickness = 2.5
		shockStroke.Color = Color3.fromRGB(255, 108, 56)
		shockStroke.Transparency = 0.06
		shockStroke.Parent = shock

		local shockCorner = Instance.new("UICorner")
		shockCorner.CornerRadius = UDim.new(1, 0)
		shockCorner.Parent = shock

		TweenService:Create(
			shock,
			TweenInfo.new(fxTime(0.38), Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{Size = UDim2.fromOffset(card.AbsoluteSize.X + 30, card.AbsoluteSize.Y + 30), Rotation = -140}
		):Play()
		TweenService:Create(
			shockStroke,
			TweenInfo.new(fxTime(0.38), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Transparency = 1}
		):Play()
		Debris:AddItem(shock, fxLife(0.46))

		for i = 1, 14 do
			local ember = Instance.new("Frame")
			ember.Name = "DamageEmber"
			ember.AnchorPoint = Vector2.new(0.5, 0.5)
			ember.Size = UDim2.fromOffset(math.random(2, 5), math.random(2, 5))
			ember.Position = UDim2.fromScale(0.5, 0.5)
			ember.BackgroundColor3 = (i % 2 == 0) and Color3.fromRGB(255, 120, 62) or Color3.fromRGB(255, 214, 146)
			ember.BackgroundTransparency = 0.08
			ember.BorderSizePixel = 0
			ember.ZIndex = 26
			ember.Parent = card

			local angle = math.rad(math.random(0, 359))
			local radius = math.random(26, 60)
			local tx = 0.5 + (math.cos(angle) * radius / math.max(1, card.AbsoluteSize.X))
			local ty = 0.5 + (math.sin(angle) * radius / math.max(1, card.AbsoluteSize.Y))

			TweenService:Create(
				ember,
				TweenInfo.new(fxTime(0.34), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{Position = UDim2.fromScale(tx, ty), BackgroundTransparency = 1}
			):Play()
			Debris:AddItem(ember, fxLife(0.42))
		end
	elseif effect == "HealLowestAlly" then
		local glyph = Instance.new("Frame")
		glyph.Name = "HealGlyph"
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Size = UDim2.fromOffset(24, 24)
		glyph.Position = UDim2.fromScale(0.5, 0.56)
		glyph.BackgroundTransparency = 1
		glyph.BorderSizePixel = 0
		glyph.ZIndex = 25
		glyph.Parent = card

		local glyphStroke = Instance.new("UIStroke")
		glyphStroke.Thickness = 2
		glyphStroke.Color = Color3.fromRGB(130, 255, 176)
		glyphStroke.Transparency = 0.08
		glyphStroke.Parent = glyph

		local glyphCorner = Instance.new("UICorner")
		glyphCorner.CornerRadius = UDim.new(1, 0)
		glyphCorner.Parent = glyph

		TweenService:Create(
			glyph,
			TweenInfo.new(fxTime(0.46), Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{Size = UDim2.fromOffset(card.AbsoluteSize.X + 20, card.AbsoluteSize.Y + 20), Position = UDim2.fromScale(0.5, 0.5)}
		):Play()
		TweenService:Create(
			glyphStroke,
			TweenInfo.new(fxTime(0.46), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Transparency = 1}
		):Play()
		Debris:AddItem(glyph, fxLife(0.56))

		for _ = 1, 12 do
			local mote = Instance.new("Frame")
			mote.Name = "HealMote"
			mote.AnchorPoint = Vector2.new(0.5, 0.5)
			mote.Size = UDim2.fromOffset(math.random(2, 4), math.random(2, 4))
			mote.Position = UDim2.fromScale(math.random(25, 75) / 100, math.random(45, 80) / 100)
			mote.BackgroundColor3 = Color3.fromRGB(180, 255, 210)
			mote.BackgroundTransparency = 0.05
			mote.BorderSizePixel = 0
			mote.ZIndex = 26
			mote.Parent = card

			TweenService:Create(
				mote,
				TweenInfo.new(fxTime(0.5), Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{
					Position = UDim2.fromScale(math.random(20, 80) / 100, math.random(10, 35) / 100),
					BackgroundTransparency = 1,
				}
			):Play()
			Debris:AddItem(mote, fxLife(0.58))
		end
	end
end

local function playAbilityPulse(panel, slotIndex, color, effectType)
	local card = getPanelCard(panel, slotIndex)
	if not (card and card.Parent) then
		return
	end

	local fx = Instance.new("Frame")
	fx.Name = "AbilityPulse"
	fx.Size = UDim2.fromScale(1, 1)
	fx.Position = UDim2.fromOffset(0, 0)
	fx.BackgroundColor3 = color
	fx.BackgroundTransparency = 0.92
	fx.BorderSizePixel = 0
	fx.ZIndex = 20
	fx.Parent = card

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = fx

	TweenService:Create(
		fx,
		TweenInfo.new(fxTime(0.24), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundTransparency = 0.72}
	):Play()

	task.delay(fxTime(0.24), function()
		if not (fx and fx.Parent) then
			return
		end
		TweenService:Create(
			fx,
			TweenInfo.new(fxTime(0.34), Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{BackgroundTransparency = 1}
		):Play()
	end)

	Debris:AddItem(fx, fxLife(0.68))

	local rune = Instance.new("Frame")
	rune.Name = "AbilityRune"
	rune.AnchorPoint = Vector2.new(0.5, 0.5)
	rune.Size = UDim2.fromOffset(26, 26)
	rune.Position = UDim2.fromScale(0.5, 0.5)
	rune.BackgroundTransparency = 1
	rune.BorderSizePixel = 0
	rune.ZIndex = 22
	rune.Parent = card

	local runeStroke = Instance.new("UIStroke")
	runeStroke.Thickness = 2
	runeStroke.Color = color
	runeStroke.Transparency = 0.15
	runeStroke.Parent = rune

	local runeCorner = Instance.new("UICorner")
	runeCorner.CornerRadius = UDim.new(1, 0)
	runeCorner.Parent = rune

	TweenService:Create(
		rune,
		TweenInfo.new(fxTime(0.5), Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Size = UDim2.fromOffset(card.AbsoluteSize.X + 18, card.AbsoluteSize.Y + 18), Rotation = 120}
	):Play()
	TweenService:Create(
		runeStroke,
		TweenInfo.new(fxTime(0.5), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Transparency = 1}
	):Play()
	Debris:AddItem(rune, fxLife(0.58))

	for i = 1, 12 do
		local shard = Instance.new("Frame")
		shard.Name = "BuffShard"
		shard.AnchorPoint = Vector2.new(0.5, 0.5)
		shard.Size = UDim2.fromOffset(math.random(3, 7), math.random(10, 20))
		shard.Position = UDim2.fromScale(0.5, 0.5)
		shard.Rotation = math.random(0, 180)
		shard.BackgroundColor3 = (i % 2 == 0) and color or Color3.fromRGB(255, 245, 210)
		shard.BackgroundTransparency = 0.05
		shard.BorderSizePixel = 0
		shard.ZIndex = 23
		shard.Parent = card

		local angle = math.rad((360 / 12) * i + math.random(-8, 8))
		local radius = math.random(30, 52)
		local tx = 0.5 + (math.cos(angle) * radius / math.max(1, card.AbsoluteSize.X))
		local ty = 0.5 + (math.sin(angle) * radius / math.max(1, card.AbsoluteSize.Y))

		TweenService:Create(
			shard,
			TweenInfo.new(fxTime(0.38), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Position = UDim2.fromScale(tx, ty),
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(1, 1),
			}
		):Play()
		Debris:AddItem(shard, fxLife(0.46))
	end

	for i = 1, 4 do
		local streak = Instance.new("Frame")
		streak.Name = "BuffStreak"
		streak.AnchorPoint = Vector2.new(0.5, 0.5)
		streak.Size = UDim2.fromOffset(math.random(34, 58), math.random(2, 4))
		streak.Position = UDim2.fromScale(0.5, 0.5)
		streak.Rotation = (i - 1) * 45 + math.random(-6, 6)
		streak.BackgroundColor3 = color
		streak.BackgroundTransparency = 0.18
		streak.BorderSizePixel = 0
		streak.ZIndex = 24
		streak.Parent = card

		TweenService:Create(
			streak,
			TweenInfo.new(fxTime(0.34), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Size = UDim2.fromOffset(math.random(70, 96), 1), BackgroundTransparency = 1}
		):Play()
		Debris:AddItem(streak, fxLife(0.42))
	end

	playAbilityThemeFx(card, color, effectType)
end

local function showAbilityPopup(panel, slotIndex, color, text)
	local card = getPanelCard(panel, slotIndex)
	if not (card and card.Parent) then
		return
	end

	local popup = Instance.new("TextLabel")
	popup.Name = "AbilityPopup"
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.Size = UDim2.fromOffset(156, 40)
	popup.Position = UDim2.fromScale(0.5, -0.05)
	popup.BackgroundColor3 = Color3.fromRGB(16, 20, 28)
	popup.BackgroundTransparency = 1
	popup.Text = text
	popup.Font = Enum.Font.GothamBold
	popup.TextSize = 21
	popup.TextColor3 = color
	popup.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	popup.TextStrokeTransparency = 0.05
	popup.ZIndex = 21
	popup.Parent = card

	local popupCorner = Instance.new("UICorner")
	popupCorner.CornerRadius = UDim.new(0, 8)
	popupCorner.Parent = popup

	local popupStroke = Instance.new("UIStroke")
	popupStroke.Thickness = 2
	popupStroke.Color = Color3.fromRGB(0, 0, 0)
	popupStroke.Transparency = 0
	popupStroke.Parent = popup

	TweenService:Create(
		popup,
		TweenInfo.new(fxTime(0.3), Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Position = UDim2.fromScale(0.5, -0.14)}
	):Play()

	task.delay(fxTime(2.1), function()
		if not (popup and popup.Parent) then
			return
		end
		TweenService:Create(
			popup,
			TweenInfo.new(fxTime(0.42), Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{Position = UDim2.fromScale(0.5, -0.2), TextTransparency = 1, TextStrokeTransparency = 1, BackgroundTransparency = 1}
		):Play()
		if popupStroke and popupStroke.Parent then
			TweenService:Create(
				popupStroke,
				TweenInfo.new(fxTime(0.42), Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{Transparency = 1}
			):Play()
		end
	end)

	Debris:AddItem(popup, fxLife(2.9))
end

local function playAbilityEvents(payload, leftPanel, rightPanel, myUserId, enemyUserId)
	if type(payload.abilityEvents) ~= "table" then
		return
	end

	for _, abilityEvent in ipairs(payload.abilityEvents) do
		if type(abilityEvent) == "table" then
			local color, text = getAbilityEffectStyle(abilityEvent.effectType)
			local casterPanel = nil
			local isAlly = false
			if abilityEvent.attackerUserId == myUserId then
				casterPanel = leftPanel
				isAlly = true
			elseif abilityEvent.attackerUserId == enemyUserId then
				casterPanel = rightPanel
			end
			local noticeText = getBuffNoticeText(abilityEvent, isAlly)

			if casterPanel then
				playAbilitySound(abilityEvent.effectType)
				playAbilityPulse(casterPanel, abilityEvent.casterSlotIndex, color, abilityEvent.effectType)
				showAbilityPopup(casterPanel, abilityEvent.casterSlotIndex, color, text)
				local targetPanel = casterPanel
				if abilityEvent.effectType == "EnemyPartyAttackDown" then
					targetPanel = (casterPanel == leftPanel) and rightPanel or leftPanel
				end
				for _, slotIndex in ipairs(abilityEvent.targetSlotIndices or {}) do
					playAbilityPulse(targetPanel, slotIndex, color, abilityEvent.effectType)
				end
			end
			if noticeText then
				playBuffScreenPulse(color)
			end
		end
	end
end

inviteEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	local eventType = payload.eventType

	if eventType == PvpProtocol.EventType.InviteReceived then
		uiState.pendingInviteId = payload.inviteId
		uiState.pendingInviteFrom = tostring(payload.challengerName or "Unknown")
		local title = inviteFrame:FindFirstChild("Title")
		if title and title:IsA("TextLabel") then
			title.Text = uiState.pendingInviteFrom .. " challenged you to a 5v5 duel"
		end
		inviteFrame.Visible = true
		return
	end

	if eventType == PvpProtocol.EventType.InviteSent then
		local centerLabel = radialRoot:FindFirstChild("CenterLabel")
		if centerLabel and centerLabel:IsA("TextLabel") then
			centerLabel.Text = "Invite Sent"
		end
		task.delay(1, function()
			if centerLabel and centerLabel.Parent then
				if radialRoot.Visible and uiState.radialTargetName ~= "" then
					centerLabel.Text = tostring(uiState.radialTargetName) .. "\nPvP"
				else
					centerLabel.Text = "Choose\nAction"
				end
			end
		end)
		return
	end

	if eventType == PvpProtocol.EventType.InviteDeclined then
		local centerLabel = radialRoot:FindFirstChild("CenterLabel")
		if centerLabel and centerLabel:IsA("TextLabel") then
			centerLabel.Text = "Declined"
		end
		task.delay(1, function()
			if centerLabel and centerLabel.Parent then
				if radialRoot.Visible and uiState.radialTargetName ~= "" then
					centerLabel.Text = tostring(uiState.radialTargetName) .. "\nPvP"
				else
					centerLabel.Text = "Choose\nAction"
				end
			end
		end)
		return
	end

	if eventType == PvpProtocol.EventType.InviteExpired then
		if uiState.pendingInviteId and payload.inviteId == uiState.pendingInviteId then
			uiState.pendingInviteId = nil
			uiState.pendingInviteFrom = ""
			inviteFrame.Visible = false
		end
		return
	end

	if eventType == PvpProtocol.EventType.ErrorEvent then
		warn("[PvP] " .. tostring(payload.reason))
	end
end)

sessionEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	local eventType = payload.eventType

	if eventType == PvpProtocol.EventType.SessionStarted then
		uiState.sessionId = payload.sessionId
		uiState.opponentName = tostring(payload.opponentName or "Opponent")
		battleFrame.Visible = true
		ensureBattleSounds(battleFrame)
		startBattleAmbience()
		local status = battleFrame:FindFirstChild("Status")
		if status and status:IsA("TextLabel") then
			status.Text = "Preparing duel with " .. uiState.opponentName
		end

		local deck = buildCombatDeckSnapshot()
		actionEvent:FireServer({
			actionType = PvpProtocol.ActionType.SubmitDeckSnapshot,
			sessionId = uiState.sessionId,
			deck = deck,
		})
		return
	end

	if eventType == PvpProtocol.EventType.StateUpdate then
		if uiState.sessionId ~= payload.sessionId then
			return
		end
		battleFrame.Visible = true

		local leftPanel = battleFrame:FindFirstChild("LeftPanel")
		local rightPanel = battleFrame:FindFirstChild("RightPanel")
		local status = battleFrame:FindFirstChild("Status")
		if status and status:IsA("TextLabel") then
			status.Text = tostring(payload.reason or "Fight in progress")
		end

		local myStates
		local enemyStates
		local myTitle
		local enemyTitle
		if payload.playerAUserId == player.UserId then
			myStates = payload.playerAStates
			enemyStates = payload.playerBStates
			myTitle = tostring(payload.playerAName or "You")
			enemyTitle = tostring(payload.playerBName or "Opponent")
		else
			myStates = payload.playerBStates
			enemyStates = payload.playerAStates
			myTitle = tostring(payload.playerBName or "You")
			enemyTitle = tostring(payload.playerAName or "Opponent")
		end

		if leftPanel and leftPanel:IsA("Frame") then
			renderPanel(leftPanel, myTitle, myStates)
		end
		if rightPanel and rightPanel:IsA("Frame") then
			renderPanel(rightPanel, enemyTitle, enemyStates)
		end

		if type(payload.attacks) == "table" then
			local myUserId = player.UserId
			local enemyUserId = (payload.playerAUserId == myUserId) and payload.playerBUserId or payload.playerAUserId
			local stagger = DamagePopupManager.STAGGER_SEC
			local ENTRY_MULTI_HIT_STAGGER_SEC = 0.13
			for i, attack in ipairs(payload.attacks) do
				local effectiveStagger = (attack and attack.isEntryMultiHit) and ENTRY_MULTI_HIT_STAGGER_SEC or stagger
				local displayIndex = tonumber(attack and attack.entryHitIndex) or i
				local delay = math.max(0, displayIndex - 1) * effectiveStagger
				if attack.attackerUserId == myUserId then
					animateAttackDash(leftPanel, attack.attackerSlotIndex, rightPanel, attack.targetSlotIndex)
					animateRowPulse(leftPanel, attack.attackerSlotIndex, Color3.fromRGB(38, 122, 76))
					animateRowPulse(rightPanel, attack.targetSlotIndex, Color3.fromRGB(148, 54, 54))
					showDamagePopup(rightPanel, attack.targetSlotIndex, attack, delay, "pvpR")
				elseif attack.attackerUserId == enemyUserId then
					animateAttackDash(rightPanel, attack.attackerSlotIndex, leftPanel, attack.targetSlotIndex)
					animateRowPulse(rightPanel, attack.attackerSlotIndex, Color3.fromRGB(38, 122, 76))
					animateRowPulse(leftPanel, attack.targetSlotIndex, Color3.fromRGB(148, 54, 54))
					showDamagePopup(leftPanel, attack.targetSlotIndex, attack, delay, "pvpL")
				end
			end
			playAbilityEvents(payload, leftPanel, rightPanel, myUserId, enemyUserId)
		elseif type(payload.abilityEvents) == "table" then
			local myUserId = player.UserId
			local enemyUserId = (payload.playerAUserId == myUserId) and payload.playerBUserId or payload.playerAUserId
			playAbilityEvents(payload, leftPanel, rightPanel, myUserId, enemyUserId)
		end
		return
	end

	if eventType == PvpProtocol.EventType.SessionEnded then
		if uiState.sessionId and payload.sessionId and uiState.sessionId ~= payload.sessionId then
			return
		end
		if uiState.sessionId then
			DamagePopupManager.ClearSession(uiState.sessionId)
		end
		uiState.sessionId = nil
		local reason = tostring(payload.reason or "Duel ended")
		local status = battleFrame:FindFirstChild("Status")
		if status and status:IsA("TextLabel") then
			status.Text = reason
		end
		task.delay(1.2, function()
			stopBattleAmbience()
			if battleFrame and battleFrame.Parent then
				battleFrame.Visible = false
			end
		end)
		return
	end

	if eventType == PvpProtocol.EventType.ErrorEvent then
		warn("[PvP] " .. tostring(payload.reason))
	end
end)
