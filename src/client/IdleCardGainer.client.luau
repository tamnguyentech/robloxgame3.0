local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CardDatabase = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardDatabase"))
local BoosterOpenSequence = require(script.Parent:WaitForChild("ui"):WaitForChild("BoosterOpenSequence"))
local RarityConfig = require(script.Parent:WaitForChild("RarityConfig"))
local IdleRollProtocol = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("IdleRollProtocol"))
local BalanceConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BalanceConfig"))
local ClientStateManager = require(script.Parent.core:WaitForChild("ClientStateManager"))
local BuffBridge = require(script.Parent.core:WaitForChild("BuffBridge"))
local DeviceContext = require(script.Parent.core:WaitForChild("DeviceContext"))
local SettingsUIController = require(script.Parent.ui.controllers.SettingsUIController)

-- Template for card notifications
local template = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("CardTemplate"):WaitForChild("Card")
-- CardArt is optional now; the game can run purely from ArtAssetId / VideoAssetId.
local artFolder = ReplicatedStorage:FindFirstChild("CardArt")
local saveEvent = ReplicatedStorage:WaitForChild("SaveDataEvent")

local luckBuffEvent = BuffBridge.GetLuckBuffEvent()
local foilChanceBuffEvent = BuffBridge.GetFoilChanceBuffEvent()
local luckBuffBonusValue = BuffBridge.GetLuckBuffBonusValue()
local foilChanceBuffBonusValue = BuffBridge.GetFoilChanceBuffBonusValue()

-- IdleCardEvent: get-or-create to avoid blocking if IdleCardGainer loads before IdleRollBridge
local idleEvent = ReplicatedStorage:FindFirstChild("IdleCardEvent")
if not (idleEvent and idleEvent:IsA("BindableEvent")) then
	if idleEvent then idleEvent:Destroy() end
	idleEvent = Instance.new("BindableEvent")
	idleEvent.Name = "IdleCardEvent"
	idleEvent.Parent = ReplicatedStorage
end

local autoRollBuffEvent = ReplicatedStorage:FindFirstChild("AutoRollBuffEvent")
if not autoRollBuffEvent then
	autoRollBuffEvent = Instance.new("BindableEvent")
	autoRollBuffEvent.Name = "AutoRollBuffEvent"
	autoRollBuffEvent.Parent = ReplicatedStorage
end

local boosterOpenVisualEvent = ReplicatedStorage:FindFirstChild("BoosterOpenVisualEvent")
if not boosterOpenVisualEvent then
	boosterOpenVisualEvent = Instance.new("BindableEvent")
	boosterOpenVisualEvent.Name = "BoosterOpenVisualEvent"
	boosterOpenVisualEvent.Parent = ReplicatedStorage
end

local idleRollRemotes = ReplicatedStorage:WaitForChild(IdleRollProtocol.Remotes.FolderName)
local idleRollControlEvent = idleRollRemotes:WaitForChild(IdleRollProtocol.Remotes.ControlEvent)

local function getPreviewRarityColor(rarity)
	return RarityConfig.GetPreviewRarityColor(rarity)
end

local function getBorderPulseScale(rarity)
	return RarityConfig.GetBorderPulseScale(rarity)
end

local function buildBorderGradient(baseColor)
	return RarityConfig.BuildBorderGradient(baseColor)
end

local function applyBeliodusShadowParticles(card)
	if not card or card:GetAttribute("HasBeliodusShadowAura") then
		return
	end
	card:SetAttribute("HasBeliodusShadowAura", true)

	local aura = card:FindFirstChild("BeliodusShadowAura")
	if not aura then
		aura = Instance.new("Frame")
		aura.Name = "BeliodusShadowAura"
		aura.Size = UDim2.new(1, 36, 1, 36)
		aura.Position = UDim2.fromOffset(-18, -18)
		aura.BackgroundTransparency = 1
		aura.BorderSizePixel = 0
		aura.ClipsDescendants = false
		aura.ZIndex = math.max(14, card.ZIndex + 4)
		aura.Parent = card
	end

	local function runParticleLoop()
		while aura.Parent and card.Parent do
			for _ = 1, 2 do
				local particle = Instance.new("Frame")
				particle.Name = "ShadowParticle"
				particle.AnchorPoint = Vector2.new(0.5, 0.5)
				local startX = math.random(4, math.max(5, aura.AbsoluteSize.X - 4))
				local startY = math.random(4, math.max(5, aura.AbsoluteSize.Y - 4))
				local sizePx = math.random(4, 10)
				particle.Size = UDim2.fromOffset(sizePx, sizePx)
				particle.Position = UDim2.fromOffset(startX, startY)
				particle.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
				particle.BackgroundTransparency = 0.2 + (math.random() * 0.25)
				particle.BorderSizePixel = 0
				particle.ZIndex = aura.ZIndex
				particle.Parent = aura

				local particleCorner = Instance.new("UICorner")
				particleCorner.CornerRadius = UDim.new(1, 0)
				particleCorner.Parent = particle

				local rise = math.random(20, 44)
				local drift = math.random(-26, 26)
				local t = 0.65 + (math.random() * 0.55)
				TweenService:Create(
					particle,
					TweenInfo.new(t, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
					{
						Position = UDim2.fromOffset(startX + drift, startY - rise),
						BackgroundTransparency = 1,
						Size = UDim2.fromOffset(sizePx + 2, sizePx + 2),
					}
				):Play()

				local function destroyParticleLater()
					if particle and particle.Parent then
						particle:Destroy()
					end
				end
				task.delay(t + 0.05, destroyParticleLater)
			end

			task.wait(0.09)
		end
	end

	task.spawn(runParticleLoop)
end

local function applyAnimatedCardBorder(card, rarity, cardId)
	if not card or card:GetAttribute("HasAnimatedBorder") then
		return
	end
	card:SetAttribute("HasAnimatedBorder", true)

	local isBeliodus = (cardId == "BeliodusX") or (card and card.Name == "BeliodusX")
	local isGodRarity = rarity == "God" or rarity == "Transcendent"
	local borderColor = isBeliodus and Color3.fromRGB(8, 8, 8) or getPreviewRarityColor(rarity)
	local pulseScale = getBorderPulseScale(rarity)
	if isBeliodus then
		pulseScale = math.max(pulseScale, 1.7)
	elseif isGodRarity then
		pulseScale = math.max(pulseScale, 1.5)
	end

	local borderStroke = card:FindFirstChild("CardBorderStroke")
	if not borderStroke then
		borderStroke = Instance.new("UIStroke")
		borderStroke.Name = "CardBorderStroke"
		borderStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		borderStroke.Thickness = 3.4
		borderStroke.Transparency = 0.18
		borderStroke.Parent = card
	end
	borderStroke.Color = borderColor

	local borderGradient = borderStroke:FindFirstChild("CardBorderGradient")
	if not borderGradient then
		borderGradient = Instance.new("UIGradient")
		borderGradient.Name = "CardBorderGradient"
		borderGradient.Parent = borderStroke
	end
	borderGradient.Color = buildBorderGradient(borderColor)
	borderGradient.Rotation = 0

	local glowFrame = card:FindFirstChild("CardBorderGlow")
	if not glowFrame then
		glowFrame = Instance.new("Frame")
		glowFrame.Name = "CardBorderGlow"
		glowFrame.BackgroundTransparency = 1
		glowFrame.BorderSizePixel = 0
		glowFrame.Size = UDim2.new(1, 10, 1, 10)
		glowFrame.Position = UDim2.fromOffset(-5, -5)
		glowFrame.ZIndex = card.ZIndex
		glowFrame.Parent = card

		local glowCorner = Instance.new("UICorner")
		glowCorner.CornerRadius = UDim.new(0, 10)
		glowCorner.Parent = glowFrame
	end

	local glowStroke = glowFrame:FindFirstChild("GlowStroke")
	if not glowStroke then
		glowStroke = Instance.new("UIStroke")
		glowStroke.Name = "GlowStroke"
		glowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		glowStroke.Thickness = 6.6
		glowStroke.Transparency = 0.72
		glowStroke.Parent = glowFrame
	end
	glowStroke.Color = borderColor

	local glowGradient = glowStroke:FindFirstChild("GlowGradient")
	if not glowGradient then
		glowGradient = Instance.new("UIGradient")
		glowGradient.Name = "GlowGradient"
		glowGradient.Parent = glowStroke
	end
	glowGradient.Color = buildBorderGradient(borderColor)
	glowGradient.Rotation = 0

	TweenService:Create(
		borderStroke,
		TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{
			Thickness = 4.2 * pulseScale,
			Transparency = 0.03,
		}
	):Play()

	TweenService:Create(
		glowStroke,
		TweenInfo.new(1.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{
			Thickness = 7.8 * pulseScale,
			Transparency = 0.84,
		}
	):Play()

	TweenService:Create(
		borderGradient,
		TweenInfo.new(2.6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false),
		{Rotation = 360}
	):Play()

	TweenService:Create(
		glowGradient,
		TweenInfo.new(3.4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false),
		{Rotation = -360}
	):Play()

	if isBeliodus or isGodRarity then
		applyBeliodusShadowParticles(card)
	end
end

local function tweenIfProperty(guiObject, info, goals)
	if guiObject and guiObject.Parent then
		TweenService:Create(guiObject, info, goals):Play()
	end
end

local function fadeOutNotificationCard(notificationCard, duration)
	local fadeInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tweenIfProperty(notificationCard, fadeInfo, {
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 0, 0, 0),
	})

	for _, obj in ipairs(notificationCard:GetDescendants()) do
		if obj.Parent and (obj:IsA("TextLabel") or obj:IsA("TextButton")) then
			tweenIfProperty(obj, fadeInfo, {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
				BackgroundTransparency = 1,
			})
		elseif obj.Parent and (obj:IsA("ImageLabel") or obj:IsA("ImageButton")) then
			tweenIfProperty(obj, fadeInfo, {
				ImageTransparency = 1,
				BackgroundTransparency = 1,
			})
		elseif obj.Parent and obj:IsA("UIStroke") then
			tweenIfProperty(obj, fadeInfo, {Transparency = 1})
		elseif obj.Parent and obj:IsA("Frame") then
			tweenIfProperty(obj, fadeInfo, {BackgroundTransparency = 1})
		end
	end
end

-- Roll/level live in ClientStateManager; no local duplicate.
local autoRolling = true
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local rollSpeedMultiplier = 1
local buffEndTime = 0
local luckBuffEndTime = 0
local luckBuffBonus = 0
local foilChanceBuffEndTime = 0
local foilChanceBuffBonus = 0

-- Create roll tracker UI
local existingTrackerGui = playerGui:FindFirstChild("RollTrackerGui")
if existingTrackerGui then
	existingTrackerGui:Destroy()
end

local trackerGui = Instance.new("ScreenGui")
trackerGui.Name = "RollTrackerGui"
trackerGui.DisplayOrder = 50  -- Below notifications
trackerGui.Parent = playerGui

-- Ensure trackerGui DisplayOrder is high enough for auto-roll button
trackerGui.DisplayOrder = math.max(trackerGui.DisplayOrder or 0, 50)

local autoRollButton = Instance.new("TextButton")
autoRollButton.Name = "AutoRollButton"
local autoRollH = math.max(46, DeviceContext.getTouchTargetMin())
local autoRollW = DeviceContext.getIsMobile() and 120 or 168
autoRollButton.Size = UDim2.fromOffset(autoRollW, autoRollH)
local insets = DeviceContext.getSafeInsets()
-- Bottom-right; on mobile bring it up so it stays tappable above home indicator
local bottomOffset = (DeviceContext.getIsMobile() and 80 or 98) + insets.bottom
autoRollButton.AnchorPoint = Vector2.new(1, 1)
autoRollButton.Position = UDim2.new(1, -12 - insets.right, 1, -bottomOffset)
autoRollButton.BackgroundTransparency = 0.08
autoRollButton.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
autoRollButton.BorderSizePixel = 0
autoRollButton.AutoButtonColor = false
autoRollButton.Text = ""
autoRollButton.Parent = trackerGui

local autoCorner = Instance.new("UICorner")
autoCorner.CornerRadius = UDim.new(0, 14)
autoCorner.Parent = autoRollButton

local autoStroke = Instance.new("UIStroke")
autoStroke.Thickness = 1.5
autoStroke.Transparency = 0.45
autoStroke.Color = Color3.fromRGB(70, 100, 160)
autoStroke.Parent = autoRollButton

local autoGrad = Instance.new("UIGradient")
autoGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0,   Color3.fromRGB(30, 34, 48)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(18, 20, 28)),
	ColorSequenceKeypoint.new(1,   Color3.fromRGB(14, 16, 22)),
})
autoGrad.Rotation = 90
autoGrad.Parent = autoRollButton

local autoLabel = Instance.new("TextLabel")
autoLabel.Name = "Label"
autoLabel.BackgroundTransparency = 1
autoLabel.Position = UDim2.fromOffset(14, 7)
autoLabel.Size = UDim2.new(1, -80, 0, 16)
autoLabel.Font = Enum.Font.GothamMedium
autoLabel.TextSize = 12
autoLabel.TextXAlignment = Enum.TextXAlignment.Left
autoLabel.TextColor3 = Color3.fromRGB(195, 202, 214)
autoLabel.Text = "AUTO ROLL"
autoLabel.Parent = autoRollButton

local autoState = Instance.new("TextLabel")
autoState.Name = "State"
autoState.BackgroundTransparency = 1
autoState.Position = UDim2.fromOffset(14, 22)
autoState.Size = UDim2.new(1, -80, 0, 18)
autoState.Font = Enum.Font.GothamBold
autoState.TextSize = 14
autoState.TextXAlignment = Enum.TextXAlignment.Left
autoState.TextColor3 = Color3.fromRGB(240, 245, 255)
autoState.Text = "ON"
autoState.Parent = autoRollButton

local toggleW = DeviceContext.getIsMobile() and 56 or 52
local toggleH = DeviceContext.getIsMobile() and 32 or 26
local toggle = Instance.new("Frame")
toggle.Name = "Toggle"
toggle.Size = UDim2.fromOffset(toggleW, toggleH)
toggle.AnchorPoint = Vector2.new(1, 0.5)
toggle.Position = UDim2.new(1, -14, 0.5, 0)
toggle.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
toggle.BorderSizePixel = 0
toggle.Parent = autoRollButton

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 13)
toggleCorner.Parent = toggle

local knobPad = 3
local knobSize = math.min(20, toggleH - 6)
local knob = Instance.new("Frame")
knob.Name = "Knob"
knob.Size = UDim2.fromOffset(knobSize, knobSize)
knob.Position = UDim2.fromOffset(knobPad, (toggleH - knobSize) / 2)
knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
knob.BorderSizePixel = 0
knob.Parent = toggle

local knobCorner = Instance.new("UICorner")
knobCorner.CornerRadius = UDim.new(0, 10)
knobCorner.Parent = knob

local function UpdateAutoRollButton()
	local isOn = autoRolling == true
	autoState.Text = isOn and "ON" or "OFF"
	autoState.TextColor3 = isOn and Color3.fromRGB(170, 255, 190) or Color3.fromRGB(255, 170, 170)

	local bgColor = isOn and Color3.fromRGB(80, 180, 100) or Color3.fromRGB(60, 60, 75)
	local knobXOn = toggleW - knobSize - knobPad
	local knobY = (toggleH - knobSize) / 2
	local knobPos = isOn and UDim2.fromOffset(knobXOn, knobY) or UDim2.fromOffset(knobPad, knobY)
	TweenService:Create(toggle, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundColor3 = bgColor,
	}):Play()
	TweenService:Create(knob, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = knobPos,
	}):Play()
end

local function onAutoRollButtonClick()
	autoRolling = not autoRolling
	UpdateAutoRollButton()
	idleRollControlEvent:FireServer({
		enabled = autoRolling,
	})
end

autoRollButton.MouseButton1Click:Connect(onAutoRollButtonClick)

UpdateAutoRollButton()

local NOTIFICATION_CARD_WIDTH = 170
local NOTIFICATION_CARD_HEIGHT = 250
local AUTO_NOTIFICATION_DISPLAY_ORDER = -10
local BOOSTER_NOTIFICATION_DISPLAY_ORDER = 300

local buffGui = Instance.new("ScreenGui")
buffGui.Name = "AutoRollBuffGui"
buffGui.DisplayOrder = 75
buffGui.Parent = playerGui

local function getBuffLabelWidth()
	local vp = DeviceContext.getViewportSize()
	return math.min(250, math.max(160, vp.X - 80))
end

local buffTimerLabel = Instance.new("TextLabel")
buffTimerLabel.Name = "BuffTimerLabel"
buffTimerLabel.AnchorPoint = Vector2.new(1, 0)
buffTimerLabel.Size = UDim2.fromOffset(getBuffLabelWidth(), 42)
buffTimerLabel.Position = UDim2.new(1, -16 - insets.right, 0, 14 + insets.top)
buffTimerLabel.BackgroundColor3 = Color3.fromRGB(34, 62, 110)
buffTimerLabel.BackgroundTransparency = 0.22
buffTimerLabel.BorderSizePixel = 0
buffTimerLabel.TextColor3 = Color3.new(1, 1, 1)
buffTimerLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
buffTimerLabel.TextStrokeTransparency = 0
buffTimerLabel.Font = Enum.Font.SourceSansBold
buffTimerLabel.TextSize = 20
buffTimerLabel.TextXAlignment = Enum.TextXAlignment.Center
buffTimerLabel.Text = ""
buffTimerLabel.Visible = false
buffTimerLabel.Parent = buffGui

local buffCorner = Instance.new("UICorner")
buffCorner.CornerRadius = UDim.new(0, 8)
buffCorner.Parent = buffTimerLabel

-- Luck potion buff timer — sits directly below the AutoRoll buff label.
-- Styled in purple to distinguish it from the blue AutoRoll buff.
local luckBuffTimerLabel = Instance.new("TextLabel")
luckBuffTimerLabel.Name = "LuckBuffTimerLabel"
luckBuffTimerLabel.AnchorPoint = Vector2.new(1, 0)
luckBuffTimerLabel.Size = UDim2.fromOffset(getBuffLabelWidth(), 42)
luckBuffTimerLabel.Position = UDim2.new(1, -16 - insets.right, 0, 66 + insets.top)   -- 14 + 42 + 10 below AutoRoll label
luckBuffTimerLabel.BackgroundColor3 = Color3.fromRGB(80, 34, 130)
luckBuffTimerLabel.BackgroundTransparency = 0.22
luckBuffTimerLabel.BorderSizePixel = 0
luckBuffTimerLabel.TextColor3 = Color3.new(1, 1, 1)
luckBuffTimerLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
luckBuffTimerLabel.TextStrokeTransparency = 0
luckBuffTimerLabel.Font = Enum.Font.SourceSansBold
luckBuffTimerLabel.TextSize = 20
luckBuffTimerLabel.TextXAlignment = Enum.TextXAlignment.Center
luckBuffTimerLabel.Text = ""
luckBuffTimerLabel.Visible = false
luckBuffTimerLabel.Parent = buffGui

local luckBuffCorner = Instance.new("UICorner")
luckBuffCorner.CornerRadius = UDim.new(0, 8)
luckBuffCorner.Parent = luckBuffTimerLabel

-- Foil Chance potion buff timer — sits below the Luck buff label.
-- Styled in teal/steel-blue to represent foil chance.
local foilChanceBuffTimerLabel = Instance.new("TextLabel")
foilChanceBuffTimerLabel.Name = "FoilChanceBuffTimerLabel"
foilChanceBuffTimerLabel.AnchorPoint = Vector2.new(1, 0)
foilChanceBuffTimerLabel.Size = UDim2.fromOffset(getBuffLabelWidth(), 42)
foilChanceBuffTimerLabel.Position = UDim2.new(1, -16 - insets.right, 0, 118 + insets.top)  -- 66 + 42 + 10 below Luck label
foilChanceBuffTimerLabel.BackgroundColor3 = Color3.fromRGB(22, 88, 138)
foilChanceBuffTimerLabel.BackgroundTransparency = 0.22
foilChanceBuffTimerLabel.BorderSizePixel = 0
foilChanceBuffTimerLabel.TextColor3 = Color3.new(1, 1, 1)
foilChanceBuffTimerLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
foilChanceBuffTimerLabel.TextStrokeTransparency = 0
foilChanceBuffTimerLabel.Font = Enum.Font.SourceSansBold
foilChanceBuffTimerLabel.TextSize = 20
foilChanceBuffTimerLabel.TextXAlignment = Enum.TextXAlignment.Center
foilChanceBuffTimerLabel.Text = ""
foilChanceBuffTimerLabel.Visible = false
foilChanceBuffTimerLabel.Parent = buffGui

local foilChanceBuffCorner = Instance.new("UICorner")
foilChanceBuffCorner.CornerRadius = UDim.new(0, 8)
foilChanceBuffCorner.Parent = foilChanceBuffTimerLabel

local function updateBuffTimerLabel()
	local now = os.clock()
	if buffEndTime > now then
		local remaining = math.max(0, math.ceil(buffEndTime - now))
		buffTimerLabel.Text = "2x Auto Roll: " .. tostring(remaining) .. "s"
		buffTimerLabel.Visible = true
	else
		rollSpeedMultiplier = 1
		buffEndTime = 0
		buffTimerLabel.Visible = false
	end
	-- Update luck buff label independently.
	if luckBuffEndTime > now then
		local remaining = math.max(0, math.ceil(luckBuffEndTime - now))
		luckBuffTimerLabel.Text = "+" .. tostring(luckBuffBonus) .. " Luck: " .. tostring(remaining) .. "s"
		luckBuffTimerLabel.Visible = true
	else
		luckBuffEndTime = 0
		luckBuffBonus = 0
		luckBuffBonusValue.Value = 0
		luckBuffTimerLabel.Visible = false
	end
	-- Update foil chance buff label independently.
	if foilChanceBuffEndTime > now then
		local remaining = math.max(0, math.ceil(foilChanceBuffEndTime - now))
		foilChanceBuffTimerLabel.Text = "+" .. tostring(foilChanceBuffBonus) .. " Foil: " .. tostring(remaining) .. "s"
		foilChanceBuffTimerLabel.Visible = true
	else
		foilChanceBuffEndTime = 0
		foilChanceBuffBonus = 0
		foilChanceBuffBonusValue.Value = 0
		foilChanceBuffTimerLabel.Visible = false
	end
end

local function onAutoRollBuff(payload)
	if type(payload) ~= "table" then
		return
	end
	local multiplier = tonumber(payload.multiplier) or 2
	local duration = tonumber(payload.duration) or 20
	multiplier = math.max(1, multiplier)
	duration = math.max(1, duration)

	rollSpeedMultiplier = math.max(rollSpeedMultiplier, multiplier)
	buffEndTime = math.max(buffEndTime, os.clock()) + duration
	updateBuffTimerLabel()
end

local function onLuckBuff(payload)
	if type(payload) ~= "table" then
		return
	end
	local bonus = math.max(0, math.floor(tonumber(payload.luckBonus) or 0))
	local duration = math.max(1, math.floor(tonumber(payload.duration) or 180))
	luckBuffEndTime = math.max(luckBuffEndTime, os.clock()) + duration
	luckBuffBonus = math.max(luckBuffBonus, bonus)
	luckBuffBonusValue.Value = luckBuffBonus
	updateBuffTimerLabel()
end

local function onFoilChanceBuff(payload)
	if type(payload) ~= "table" then
		return
	end
	local bonus = math.max(0, math.floor(tonumber(payload.foilChanceBonus) or 0))
	local duration = math.max(1, math.floor(tonumber(payload.duration) or 180))
	foilChanceBuffEndTime = math.max(foilChanceBuffEndTime, os.clock()) + duration
	foilChanceBuffBonus = math.max(foilChanceBuffBonus, bonus)
	foilChanceBuffBonusValue.Value = foilChanceBuffBonus
	updateBuffTimerLabel()
end

autoRollBuffEvent.Event:Connect(onAutoRollBuff)
luckBuffEvent.Event:Connect(onLuckBuff)
foilChanceBuffEvent.Event:Connect(onFoilChanceBuff)

local function runBuffTimerLoop()
	while player and player.Parent and script.Parent do
		updateBuffTimerLabel()
		task.wait(0.2)
	end
end

task.spawn(runBuffTimerLoop)

local function ShowLevelUpPopup(newLevel)
	local popupGui = Instance.new("ScreenGui")
	popupGui.Name = "LevelUpPopupGui"
	popupGui.DisplayOrder = 200
	popupGui.Parent = playerGui

	local popupLabel = Instance.new("TextLabel")
	popupLabel.Name = "LevelUpLabel"
	popupLabel.Size = UDim2.new(0, 0, 0, 0)
	popupLabel.Position = UDim2.fromScale(0.5, 0.2)
	popupLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	popupLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	popupLabel.BackgroundTransparency = 0.2
	popupLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	popupLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	popupLabel.TextStrokeTransparency = 0
	popupLabel.Font = Enum.Font.SourceSansBold
	popupLabel.TextScaled = true
	popupLabel.Text = "LEVEL UP!  Lv." .. tostring(newLevel)
	popupLabel.ZIndex = 50
	popupLabel.Parent = popupGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = popupLabel

	local vp = DeviceContext.getViewportSize()
	local popupW = math.min(360, vp.X - 40)
	local inTween = TweenService:Create(
		popupLabel,
		TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Size = UDim2.fromOffset(popupW, 70)}
	)
	inTween:Play()

	local function onLevelUpPopupDelay()
		if not popupLabel.Parent then
			return
		end
		local outTween = TweenService:Create(
			popupLabel,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{BackgroundTransparency = 1, TextTransparency = 1, TextStrokeTransparency = 1}
		)
		outTween:Play()
		outTween.Completed:Wait()
		popupGui:Destroy()
	end

	task.delay(1.2, onLevelUpPopupDelay)
end

local function onSaveData(data)
	if type(data) ~= "table" then
		return
	end
	ClientStateManager.syncFromServer(data)
end

saveEvent.OnClientEvent:Connect(onSaveData)

-- Function to show card gain notification
local function findCardArtDecal(cardId)
	if type(cardId) ~= "string" or cardId == "" then
		return nil
	end

	if not artFolder then
		return nil
	end

	local exact = artFolder:FindFirstChild(cardId)
	if exact and exact:IsA("Decal") then
		return exact
	end

	local target = string.lower(cardId)
	for _, obj in ipairs(artFolder:GetChildren()) do
		if obj:IsA("Decal") and string.lower(obj.Name) == target then
			return obj
		end
	end

	return nil
end

local function setupVisualCard(card, cardId, sizeX, sizeY)
	if not (card and card:FindFirstChild("NameLabel") and card:FindFirstChild("ArtLabel")) then
		return false
	end
	local data = CardDatabase.GetCardData(cardId)
	if not data then
		return false
	end

	local nameLabel = card:FindFirstChild("NameLabel")
	local artLabel = card:FindFirstChild("ArtLabel")
	local attackLabel = card:FindFirstChild("AttackLabel")
	local numberLabel = card:FindFirstChild("NumberLabel")

	card.Size = UDim2.fromOffset(sizeX, sizeY)
	card.BackgroundTransparency = 0.2
	card.BackgroundColor3 = Color3.new(1, 1, 1)
	card.Active = false

	if nameLabel then
		nameLabel.Text = data.Name
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
		nameLabel.BackgroundTransparency = 1
	end
	if attackLabel then
		attackLabel.Text = "ATK: " .. CardDatabase.FormatAttack(data.Attack)
		attackLabel.TextColor3 = Color3.new(1, 0, 0)
		attackLabel.BackgroundTransparency = 1
		attackLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
		attackLabel.TextStrokeTransparency = 0
	end
	if numberLabel then
		numberLabel.Text = ""
		numberLabel.TextColor3 = Color3.new(1, 1, 1)
		numberLabel.BackgroundTransparency = 1
	end

	local useStretchArt = data.ArtFitMode == "Stretch"
	local imageObj = findCardArtDecal(cardId)
	local videoAssetId = data and data.VideoAssetId
	if type(videoAssetId) == "string" and videoAssetId ~= "" and videoAssetId ~= "rbxassetid://0" then
		local artVideo = card:FindFirstChild("ArtVideo")
		if not (artVideo and artVideo:IsA("VideoFrame")) then
			if artVideo then
				artVideo:Destroy()
			end
			artVideo = Instance.new("VideoFrame")
			artVideo.Name = "ArtVideo"
			artVideo.Size = UDim2.fromScale(1, 1)
			artVideo.Position = UDim2.fromOffset(0, 0)
			artVideo.BackgroundTransparency = 1
			artVideo.BorderSizePixel = 0
			artVideo.Parent = card
		end
		if artLabel then
			artVideo.ZIndex = artLabel.ZIndex
		end
		artVideo.Looped = true
		local shouldRestart = (artVideo.Video ~= videoAssetId)
		artVideo.Video = videoAssetId
		artVideo.Visible = true
		if shouldRestart then
			artVideo.TimePosition = 0
		end
		artVideo.Playing = true
		if artLabel then
			artLabel.Image = ""
			artLabel.Visible = false
		end
	elseif imageObj and imageObj:IsA("Decal") and artLabel then
		if not useStretchArt then
			local modeAttr = imageObj:GetAttribute("ArtFitMode")
			if type(modeAttr) == "string" then
				useStretchArt = string.lower(modeAttr) == "stretch"
			else
				useStretchArt = imageObj:GetAttribute("ForceStretch") == true or imageObj:GetAttribute("SquareArt") == true
			end
		end
		artLabel.Image = imageObj.Texture
		artLabel.Visible = true
	elseif type(data.ArtAssetId) == "string" and data.ArtAssetId ~= "" and data.ArtAssetId ~= "rbxassetid://0" and artLabel then
		artLabel.Image = data.ArtAssetId
		artLabel.Visible = true
	elseif artLabel then
		artLabel.Image = ""
		artLabel.Visible = true
	end
	local artVideo = card:FindFirstChild("ArtVideo")
	if artVideo and artVideo:IsA("VideoFrame") and artLabel and artLabel.Visible then
		artVideo.Visible = false
		artVideo.Playing = false
	end
	if artLabel then
		artLabel.ScaleType = useStretchArt and Enum.ScaleType.Stretch or Enum.ScaleType.Crop
	end

	applyAnimatedCardBorder(card, data.Rarity, cardId)
	return true
end

local function safeSetInteractable(obj, value)
	pcall(function()
		obj.Interactable = value
	end)
end

local function disableGuiInteraction(guiObject)
	if not guiObject then
		return
	end

	local function disableOne(obj)
		if not obj:IsA("GuiObject") then
			return
		end
		obj.Active = false
		obj.Selectable = false
		safeSetInteractable(obj, false)
		if obj:IsA("GuiButton") then
			obj.AutoButtonColor = false
		end
	end

	disableOne(guiObject)
	for _, child in ipairs(guiObject:GetDescendants()) do
		disableOne(child)
	end
end

local function doNotificationFade(notificationCard, screenGui)
	if notificationCard and notificationCard.Parent then
		fadeOutNotificationCard(notificationCard, 0.6)
		task.wait(0.6)
		screenGui:Destroy()
	end
end

local function scheduleNotificationFade(notificationCard, screenGui)
	local function runNotificationFade()
		doNotificationFade(notificationCard, screenGui)
	end

	task.delay(1.4, runNotificationFade)
end

local function ShowCardNotification(cardId, positionOverride, displayOrderOverride)
	if not CardDatabase.GetCardData(cardId) then
		return
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CardNotificationGui"
	screenGui.DisplayOrder = displayOrderOverride or AUTO_NOTIFICATION_DISPLAY_ORDER
	screenGui.Parent = playerGui

	local notificationCard = template:Clone()
	notificationCard.Name = "CardNotification"
	notificationCard.Size = UDim2.new(0, 0, 0, 0)
	notificationCard.Position = positionOverride or UDim2.fromScale(0.5, 0.5)
	notificationCard.AnchorPoint = Vector2.new(0.5, 0.5)
	notificationCard.BackgroundTransparency = 0.2
	notificationCard.BackgroundColor3 = Color3.new(1, 1, 1)
	notificationCard.ZIndex = 10
	notificationCard.Active = false

	if not setupVisualCard(notificationCard, cardId, NOTIFICATION_CARD_WIDTH, NOTIFICATION_CARD_HEIGHT) then
		screenGui:Destroy()
		return
	end

	disableGuiInteraction(notificationCard)

	-- Parent to screen
	notificationCard.Parent = screenGui
	notificationCard.ZIndex = 10

	-- Animate in with bounce effect
	local tweenInfo = TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local tweenGoals = {
		Size = UDim2.fromOffset(NOTIFICATION_CARD_WIDTH, NOTIFICATION_CARD_HEIGHT),
	}
	local tween = TweenService:Create(notificationCard, tweenInfo, tweenGoals)
	tween:Play()

	scheduleNotificationFade(notificationCard, screenGui)
end

local function onBoosterOpenVisual(payload)
	if type(payload) == "table" and type(payload.cardIds) == "table" then
		local cardIds = payload.cardIds
		BoosterOpenSequence.Play(
			cardIds,
			NOTIFICATION_CARD_WIDTH,
			NOTIFICATION_CARD_HEIGHT,
			ShowCardNotification,
			0.09,
			BOOSTER_NOTIFICATION_DISPLAY_ORDER
		)
		return
	end

	if type(payload) == "string" then
		ShowCardNotification(payload, nil, BOOSTER_NOTIFICATION_DISPLAY_ORDER)
	end
end

local function processIdleStateUpdate(payload, newRollCount, newLevel, previousLevel)
	ClientStateManager.setRollCount(newRollCount)
	ClientStateManager.setLevel(newLevel)

	if type(payload.stats) == "table" then
		ClientStateManager.setStats(payload.stats)
	end

	if newLevel > previousLevel then
		ShowLevelUpPopup(newLevel)
	end
end

local function onIdleEvent(payload)
	if type(payload) ~= "table" then
		if type(payload) == "string" then
			ShowCardNotification(payload)
		end
		return
	end

	if type(payload.cardIds) == "table" then
		for _, cardId in ipairs(payload.cardIds) do
			if type(cardId) == "string" and cardId ~= "" then
				ShowCardNotification(cardId)
			end
		end
	elseif type(payload.cardId) == "string" and payload.cardId ~= "" then
		local settings = SettingsUIController.GetState()
		if settings and settings.ShowIdleRollCardNotifications then
			ShowCardNotification(payload.cardId)
		end
		-- Card still goes to inventory via InventoryController listener regardless.
	end

	local rollCountFromPayload = payload.rollCount
	local newRollCount
	if type(rollCountFromPayload) == "number" then
		newRollCount = math.max(0, math.floor(rollCountFromPayload))
	else
		newRollCount = ClientStateManager.getRollCount()
	end

	if newRollCount < ClientStateManager.getRollCount() then
		return
	end

	local previousLevel = ClientStateManager.getLevel()
	local levelFromPayload = payload["level"]
	local newLevel
	if type(levelFromPayload) == "number" then
		newLevel = math.max(1, math.floor(levelFromPayload))
	else
		newLevel = math.floor(newRollCount / BalanceConfig.ROLLS_PER_LEVEL) + 1
	end

	processIdleStateUpdate(payload, newRollCount, newLevel, previousLevel)
end

boosterOpenVisualEvent.Event:Connect(onBoosterOpenVisual)
idleEvent.Event:Connect(onIdleEvent)
