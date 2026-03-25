-- ProfileUIController.luau
-- Full-screen RPG-style Profile UI with stat allocation

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local BalanceConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BalanceConfig"))
local BuffBridge = require(script.Parent.Parent.Parent.core:WaitForChild("BuffBridge"))
local DeviceContext = require(script.Parent.Parent.Parent.core:WaitForChild("DeviceContext"))

local ProfileUIController = {}
local createStatCard
local createAllocationButton
local initRemotes

-- Cached lazily on first use inside Setup so we don't require before the module tree is ready.
local _clientStateManager = nil
local function getClientStateManager()
	if not _clientStateManager then
		_clientStateManager = require(script.Parent.Parent.Parent.core:WaitForChild("ClientStateManager"))
	end
	return _clientStateManager
end

-- UI References
local contentFrame = nil
local luckLabel = nil
local rollSpeedLabel = nil
local potionDurationLabel = nil
local borderChanceLabel = nil
local pointsLabel = nil
local allocPointsLabel = nil
-- Why: Explicit dictionary type tells the Luau checker that any string key may hold
-- an optional TextLabel, silencing false "Key not found" errors for entries that are
-- assigned inside Setup() after this declaration.
local effectLabels: { [string]: TextLabel? } = {}

-- Remote references
local allocateRemote = nil

-- Unsubscribe handle so repeated Setup() calls don't pile up stale listeners.
local _unsubscribeStats = nil


local function formatPercent(value)
	return string.format("%.2f%%", tonumber(value) or 0)
end

local function updateDerivedEffects(stats)
	if type(stats) ~= "table" then
		return
	end

	-- Effective luck = base stat + potion buff (read from bridge IntValue written by IdleCardGainer).
	-- Luck affects ONLY card rarity; FoilChance is separate and controls foiled rolls.
	local luckBonusVal = BuffBridge.GetLuckBuffBonusValue()
	local luckBonus = math.max(0, luckBonusVal and luckBonusVal.Value or 0)
	local effectiveLuck = math.max(0, (stats.Luck or 0) + luckBonus)

	-- Effective foil chance = base stat + FoilChancePotion buff (same bridge pattern).
	local foilChanceBonusVal = BuffBridge.GetFoilChanceBuffBonusValue()
	local foilChanceBonus = math.max(0, foilChanceBonusVal and foilChanceBonusVal.Value or 0)
	local effectiveFoilChance = math.max(0, (stats.FoilChance or stats.BorderChance or 0) + foilChanceBonus)

	local luckMultiplier = BalanceConfig.CalculateLuckMultiplier(effectiveLuck)
	local rollSpeedMultiplier = BalanceConfig.CalculateRollSpeedMultiplier(stats.RollSpeed or 1)
	-- Percentage speed-up relative to base interval (e.g. multiplier 0.90 → 10% faster).
	local rollSpeedPercentFaster = math.max(0, (1 - rollSpeedMultiplier) * 100)
	-- Actual roll interval so players can see the concrete value.
	local rollInterval = BalanceConfig.BASE_AUTO_ROLL_INTERVAL * rollSpeedMultiplier
	local potionBonusPercent = math.max(0, (tonumber(stats.PotionDuration) or 0) * BalanceConfig.POTION_DURATION_BONUS_PER_POINT * 100)
	local foilChancePercent = BalanceConfig.CalculateFoilChancePercent(effectiveFoilChance)
	local rarityRates = BalanceConfig.GetRarityRatesWithLuck(effectiveLuck)

	if effectLabels.LuckMultiplier then
		effectLabels.LuckMultiplier.Text = string.format("x%.2f rare-rate multiplier", luckMultiplier)
	end
	if effectLabels.RollSpeed then
		if rollSpeedPercentFaster > 0 then
			effectLabels.RollSpeed.Text = string.format("%.1f%% faster · %.2fs/roll", rollSpeedPercentFaster, rollInterval)
		else
			effectLabels.RollSpeed.Text = string.format("%.2fs/roll  (base speed)", rollInterval)
		end
	end
	if effectLabels.PotionDuration then
		effectLabels.PotionDuration.Text = "+" .. formatPercent(potionBonusPercent) .. " potion duration"
	end
	if effectLabels.FoilChance then
		if foilChanceBonus > 0 then
			effectLabels.FoilChance.Text = string.format("%s foil chance  (+%d potion)", formatPercent(foilChancePercent), foilChanceBonus)
		else
			effectLabels.FoilChance.Text = formatPercent(foilChancePercent) .. " foil roll chance"
		end
	end
	if effectLabels.God then
		effectLabels.God.Text = formatPercent(rarityRates.God)
	end
	if effectLabels.Legendary then
		effectLabels.Legendary.Text = formatPercent(rarityRates.Legendary)
	end
	if effectLabels.Mythic then
		effectLabels.Mythic.Text = formatPercent(rarityRates.Mythic)
	end
	if effectLabels.Rare then
		effectLabels.Rare.Text = formatPercent(rarityRates.Rare)
	end
	if effectLabels.Uncommon then
		effectLabels.Uncommon.Text = formatPercent(rarityRates.Uncommon)
	end
end

-- Update UI with current stats
local function updateUI(stats)
	if stats then
		if luckLabel then
			luckLabel.Text = tostring(stats.Luck)
		end
		if rollSpeedLabel then
			rollSpeedLabel.Text = tostring(stats.RollSpeed) .. "x"
		end
		if potionDurationLabel then
			potionDurationLabel.Text = string.format("+%d%%", math.max(0, math.floor(tonumber(stats.PotionDuration) or 0) * 10))
		end
		if borderChanceLabel then
			borderChanceLabel.Text = string.format("+%.2f%%", math.max(0, math.floor(tonumber(stats.FoilChance or stats.BorderChance) or 0)) * 0.25)
		end
		if pointsLabel then
			pointsLabel.Text = tostring(stats.Points)
		end
		if allocPointsLabel then
			-- Points = level - spent. Derive totalEarned from the stats themselves so the
			-- denominator is always correct without depending on a separately-tracked level.
			-- spent = sum of all allocatable stats above their defaults (RollSpeed base = 1).
			local avail = math.max(0, math.floor(tonumber(stats.Points) or 0))
			local spentFromStats = math.max(0, math.floor(tonumber(stats.Luck) or 0))
				+ math.max(0, math.floor(tonumber(stats.PotionDuration) or 0))
				+ math.max(0, math.floor(tonumber(stats.FoilChance or stats.BorderChance) or 0))
				+ math.max(0, math.floor(tonumber(stats.RollSpeed) or 1) - 1)
			local totalEarned = avail + spentFromStats
			if spentFromStats > 0 then
				allocPointsLabel.Text = string.format("Available: %d / %d  (%d spent)", avail, totalEarned, spentFromStats)
			else
				allocPointsLabel.Text = string.format("Available: %d / %d", avail, totalEarned)
			end
		end
		updateDerivedEffects(stats)
	end
end

-- Setup the profile UI in the given content frame
function ProfileUIController.Setup(parentContent)
	if not parentContent then
		warn("[ProfileUI] No content frame provided!")
		return
	end
	
	contentFrame = parentContent
	local isMobile = DeviceContext.getIsMobile()
	
	-- Clear any existing content
	for _, child in ipairs(contentFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	
	-- Remove any previous subscription before adding a new one so re-opening the
	-- profile modal does not accumulate stale listeners that silently fail on
	-- destroyed labels and block the live update from reaching the new ones.
	if _unsubscribeStats then
		_unsubscribeStats()
		_unsubscribeStats = nil
	end
	local csm = getClientStateManager()
	_unsubscribeStats = csm.subscribe("stats", function(stats)
		updateUI(stats)
	end)
	-- Refresh Effects tab when buff bonuses change (potion use/expiry) so displayed values stay accurate.
	local luckBonusVal = BuffBridge.GetLuckBuffBonusValue()
	if luckBonusVal then
		luckBonusVal.Changed:Connect(function()
			updateUI(csm.getStats())
		end)
	end
	local foilChanceBonusVal = BuffBridge.GetFoilChanceBuffBonusValue()
	if foilChanceBonusVal then
		foilChanceBonusVal.Changed:Connect(function()
			updateUI(csm.getStats())
		end)
	end

	local player = Players.LocalPlayer
	local rollsPerLevel = BalanceConfig.ROLLS_PER_LEVEL or 100

	local function updateProgressHeader()
		local level = csm.getLevel()
		local rollCount = csm.getRollCount()
		local coins = csm.getCoins()
		local rollsIntoLevel = rollCount % rollsPerLevel
		local progressToNext = rollsIntoLevel / rollsPerLevel

		local levelLabel = contentFrame:FindFirstChild("ProfileLevelLabel")
		if levelLabel then
			levelLabel.Text = "Level " .. tostring(level)
		end
		local rollsLabel = contentFrame:FindFirstChild("ProfileRollsLabel")
		if rollsLabel then
			rollsLabel.Text = tostring(rollCount) .. " rolls"
		end
		local coinsLabel = contentFrame:FindFirstChild("ProfileCoinsLabel")
		if coinsLabel then
			coinsLabel.Text = tostring(coins) .. " coins"
		end
		local progressBar = contentFrame:FindFirstChild("ProfileProgressBar")
		if progressBar and progressBar:IsA("Frame") then
			local fill = progressBar:FindFirstChild("ProgressFill")
			if fill and fill:IsA("Frame") then
				fill.Size = UDim2.new(math.clamp(progressToNext, 0, 1), 0, 1, 0)
			end
		end
	end

	csm.subscribe("level", updateProgressHeader)
	csm.subscribe("rollCount", updateProgressHeader)
	csm.subscribe("coins", updateProgressHeader)
	task.defer(updateProgressHeader)

	-- Player identity header (very compact on mobile)
	local headerH = isMobile and 56 or 100
	local headerFrame = Instance.new("Frame")
	headerFrame.Name = "ProfileHeader"
	headerFrame.Size = UDim2.new(1, 0, 0, headerH)
	headerFrame.Position = UDim2.new(0, 0, 0, 0)
	headerFrame.BackgroundColor3 = Color3.fromRGB(30, 32, 45)
	headerFrame.BackgroundTransparency = 0.1
	headerFrame.BorderSizePixel = 0
	headerFrame.Parent = contentFrame

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 12)
	headerCorner.Parent = headerFrame

	local headerStroke = Instance.new("UIStroke")
	headerStroke.Thickness = 2
	headerStroke.Color = Color3.fromRGB(100, 120, 180)
	headerStroke.Transparency = 0.6
	headerStroke.Parent = headerFrame

	-- Avatar thumbnail (smaller on mobile)
	local avatarSize = isMobile and 48 or 64
	local avatarImage = Instance.new("ImageLabel")
	avatarImage.Name = "ProfileAvatar"
	avatarImage.Size = UDim2.fromOffset(avatarSize, avatarSize)
	avatarImage.Position = UDim2.fromOffset(isMobile and 12 or 16, isMobile and 12 or 18)
	avatarImage.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
	avatarImage.BorderSizePixel = 0
	avatarImage.Parent = headerFrame

	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(1, 0)
	avatarCorner.Parent = avatarImage

	task.spawn(function()
		local ok, thumbUrl = pcall(function()
			local url = Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
			return url
		end)
		if ok and type(thumbUrl) == "string" and thumbUrl ~= "" and avatarImage.Parent then
			avatarImage.Image = thumbUrl
		end
	end)

	-- Display name (responsive: leave room for level/rolls/coins)
	local nameRightMargin = isMobile and 120 or 200
	local nameLeft = isMobile and 68 or 92
	local displayNameLabel = Instance.new("TextLabel")
	displayNameLabel.Name = "ProfileDisplayName"
	displayNameLabel.Size = UDim2.new(1, -nameRightMargin, 0, isMobile and 20 or 28)
	displayNameLabel.Position = UDim2.fromOffset(nameLeft, isMobile and 8 or 16)
	displayNameLabel.BackgroundTransparency = 1
	displayNameLabel.Text = player.DisplayName or player.Name
	displayNameLabel.Font = Enum.Font.GothamBold
	displayNameLabel.TextSize = isMobile and 16 or 24
	displayNameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	displayNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	displayNameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	displayNameLabel.Parent = headerFrame

	-- Username
	local usernameLabel = Instance.new("TextLabel")
	usernameLabel.Name = "ProfileUsername"
	usernameLabel.Size = UDim2.new(1, -nameRightMargin, 0, isMobile and 16 or 22)
	usernameLabel.Position = UDim2.fromOffset(nameLeft, isMobile and 28 or 44)
	usernameLabel.BackgroundTransparency = 1
	usernameLabel.Text = "@" .. player.Name
	usernameLabel.Font = Enum.Font.Gotham
	usernameLabel.TextSize = isMobile and 12 or 16
	usernameLabel.TextColor3 = Color3.fromRGB(180, 190, 210)
	usernameLabel.TextXAlignment = Enum.TextXAlignment.Left
	usernameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	usernameLabel.Parent = headerFrame

	-- Level, rolls, coins row (responsive: compact block on mobile)
	local lvlW, lvlX = isMobile and 50 or 140, isMobile and -118 or -340
	local rollW, rollX = isMobile and 55 or 90, isMobile and -62 or -200
	local coinW, coinX = isMobile and 52 or 90, isMobile and -6 or -100
	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "ProfileLevelLabel"
	levelLabel.Size = UDim2.new(0, lvlW, 0, isMobile and 18 or 24)
	levelLabel.Position = UDim2.new(1, lvlX, 0, isMobile and 6 or 14)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = "Level 1"
	levelLabel.Font = Enum.Font.GothamBold
	levelLabel.TextSize = isMobile and 14 or 18
	levelLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
	levelLabel.TextXAlignment = Enum.TextXAlignment.Right
	levelLabel.TextTruncate = Enum.TextTruncate.AtEnd
	levelLabel.Parent = headerFrame

	local rollsLabel = Instance.new("TextLabel")
	rollsLabel.Name = "ProfileRollsLabel"
	rollsLabel.Size = UDim2.new(0, rollW, 0, isMobile and 16 or 20)
	rollsLabel.Position = UDim2.new(1, rollX, 0, isMobile and 26 or 40)
	rollsLabel.BackgroundTransparency = 1
	rollsLabel.Text = "0 rolls"
	rollsLabel.Font = Enum.Font.Gotham
	rollsLabel.TextSize = isMobile and 11 or 14
	rollsLabel.TextColor3 = Color3.fromRGB(200, 210, 230)
	rollsLabel.TextXAlignment = Enum.TextXAlignment.Right
	rollsLabel.TextTruncate = Enum.TextTruncate.AtEnd
	rollsLabel.Parent = headerFrame

	local coinsLabel = Instance.new("TextLabel")
	coinsLabel.Name = "ProfileCoinsLabel"
	coinsLabel.Size = UDim2.new(0, coinW, 0, isMobile and 16 or 20)
	coinsLabel.Position = UDim2.new(1, coinX, 0, isMobile and 26 or 40)
	coinsLabel.BackgroundTransparency = 1
	coinsLabel.Text = "0 coins"
	coinsLabel.Font = Enum.Font.Gotham
	coinsLabel.TextSize = isMobile and 11 or 14
	coinsLabel.TextColor3 = Color3.fromRGB(200, 210, 230)
	coinsLabel.TextXAlignment = Enum.TextXAlignment.Right
	coinsLabel.TextTruncate = Enum.TextTruncate.AtEnd
	coinsLabel.Parent = headerFrame

	-- Progress bar to next level
	local progressBg = Instance.new("Frame")
	progressBg.Name = "ProfileProgressBar"
	progressBg.Size = UDim2.new(1, -24, 0, 8)
	progressBg.Position = UDim2.fromOffset(12, headerH - 16)
	progressBg.BackgroundColor3 = Color3.fromRGB(25, 28, 38)
	progressBg.BorderSizePixel = 0
	progressBg.Parent = headerFrame

	local progressBgCorner = Instance.new("UICorner")
	progressBgCorner.CornerRadius = UDim.new(1, 0)
	progressBgCorner.Parent = progressBg

	local progressFill = Instance.new("Frame")
	progressFill.Name = "ProgressFill"
	progressFill.Size = UDim2.new(0, 0, 1, 0)
	progressFill.Position = UDim2.fromOffset(0, 0)
	progressFill.BackgroundColor3 = Color3.fromRGB(80, 140, 255)
	progressFill.BorderSizePixel = 0
	progressFill.Parent = progressBg

	local progressFillCorner = Instance.new("UICorner")
	progressFillCorner.CornerRadius = UDim.new(1, 0)
	progressFillCorner.Parent = progressFill
	
	-- Two-column on PC; single-column on mobile (hide favorite card to maximize stats/alloc)
	local leftW = isMobile and 1 or 0.4
	local leftPanel = Instance.new("Frame")
	leftPanel.Name = "LeftPanel"
	leftPanel.Size = UDim2.new(leftW, isMobile and 0 or -10, 1, -(headerH + 8))
	leftPanel.Position = UDim2.new(0, 0, 0, headerH + 8)
	leftPanel.BackgroundTransparency = 1
	leftPanel.Parent = contentFrame
	
	local rightPanel = Instance.new("Frame")
	rightPanel.Name = "RightPanel"
	rightPanel.Size = UDim2.new(isMobile and 0 or 0.6, isMobile and 0 or -10, 1, -(headerH + 8))
	rightPanel.Position = UDim2.new(leftW, isMobile and 0 or 20, 0, headerH + 8)
	rightPanel.BackgroundTransparency = 1
	rightPanel.Visible = not isMobile
	rightPanel.Parent = contentFrame

	-- === LEFT PANEL: Stats / Effects tabs ===
	local tabBar = Instance.new("Frame")
	tabBar.Name = "TabBar"
	tabBar.Size = UDim2.new(1, 0, 0, 40)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = leftPanel

	local tabBarLayout = Instance.new("UIListLayout")
	tabBarLayout.FillDirection = Enum.FillDirection.Horizontal
	tabBarLayout.Padding = UDim.new(0, 10)
	tabBarLayout.Parent = tabBar

	local statsTitle = Instance.new("TextButton")
	statsTitle.Name = "StatsTitle"
	statsTitle.Size = UDim2.new(isMobile and 0.5 or 0, isMobile and -6 or 90, 0, math.max(36, DeviceContext.getTouchTargetMin()))
	statsTitle.BackgroundColor3 = Color3.fromRGB(55, 75, 120)
	statsTitle.Text = "Stats"
	statsTitle.Font = Enum.Font.GothamBold
	statsTitle.TextSize = 18
	statsTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	statsTitle.BorderSizePixel = 0
	statsTitle.Parent = tabBar

	local statsTitleCorner = Instance.new("UICorner")
	statsTitleCorner.CornerRadius = UDim.new(0, 8)
	statsTitleCorner.Parent = statsTitle

	local effectsTitle = Instance.new("TextButton")
	effectsTitle.Name = "EffectsTitle"
	effectsTitle.Size = UDim2.new(isMobile and 0.5 or 0, isMobile and -6 or 90, 0, math.max(36, DeviceContext.getTouchTargetMin()))
	effectsTitle.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
	effectsTitle.Text = "Effects"
	effectsTitle.Font = Enum.Font.GothamBold
	effectsTitle.TextSize = 18
	effectsTitle.TextColor3 = Color3.fromRGB(200, 200, 200)
	effectsTitle.BorderSizePixel = 0
	effectsTitle.Parent = tabBar

	local effectsTitleCorner = Instance.new("UICorner")
	effectsTitleCorner.CornerRadius = UDim.new(0, 8)
	effectsTitleCorner.Parent = effectsTitle

	-- Stats tab content wrapper: stats left, allocator right (side by side)
	local statsContentFrame = Instance.new("Frame")
	statsContentFrame.Name = "StatsContentFrame"
	statsContentFrame.Size = UDim2.new(1, 0, 1, -50)
	statsContentFrame.Position = UDim2.new(0, 0, 0, 50)
	statsContentFrame.BackgroundTransparency = 1
	statsContentFrame.Parent = leftPanel

	-- Stat cards container: PC 58% width side-by-side; mobile 100% width, ~55% height stacked
	local statsW, statsH = isMobile and 1 or 0.58, isMobile and 0.55 or 1
	local statsContainer = Instance.new("ScrollingFrame")
	statsContainer.Name = "StatsContainer"
	statsContainer.Size = UDim2.new(statsW, isMobile and 0 or -4, statsH, 0)
	statsContainer.Position = UDim2.new(0, 0, 0, 0)
	statsContainer.BackgroundTransparency = 1
	statsContainer.BorderSizePixel = 0
	statsContainer.ScrollBarThickness = 8
	statsContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
	statsContainer.CanvasSize = UDim2.fromOffset(0, 0)
	statsContainer.Parent = statsContentFrame

	local statsPadding = Instance.new("UIPadding")
	statsPadding.PaddingRight = UDim.new(0, 12)
	statsPadding.PaddingBottom = UDim.new(0, 8)
	statsPadding.Parent = statsContainer

	local statsLayout = Instance.new("UIListLayout")
	statsLayout.FillDirection = Enum.FillDirection.Vertical
	statsLayout.Padding = UDim.new(0, 8)
	statsLayout.Parent = statsContainer

	local effectsContainer = Instance.new("ScrollingFrame")
	effectsContainer.Name = "EffectsContainer"
	effectsContainer.Size = UDim2.new(1, 0, 1, -60)
	effectsContainer.Position = UDim2.new(0, 0, 0, 50)
	effectsContainer.BackgroundTransparency = 1
	effectsContainer.BorderSizePixel = 0
	effectsContainer.ScrollBarThickness = 8
	effectsContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
	effectsContainer.CanvasSize = UDim2.fromOffset(0, 0)
	effectsContainer.Visible = false
	effectsContainer.Parent = leftPanel

	local effectsPadding = Instance.new("UIPadding")
	effectsPadding.PaddingRight = UDim.new(0, 12)
	effectsPadding.PaddingBottom = UDim.new(0, 8)
	effectsPadding.Parent = effectsContainer

	local effectsLayout = Instance.new("UIListLayout")
	effectsLayout.FillDirection = Enum.FillDirection.Vertical
	effectsLayout.Padding = UDim.new(0, 8)
	effectsLayout.Parent = effectsContainer

	-- Allocation section: PC 40% at 0.58; mobile 100% width, ~40% height below stats
	local allocW, allocX, allocY, allocH = isMobile and 1 or 0.4, isMobile and 0 or 0.58, isMobile and 0.55 or 0, isMobile and 0.45 or 1
	local allocationSection = Instance.new("ScrollingFrame")
	allocationSection.Name = "AllocationSection"
	allocationSection.Size = UDim2.new(allocW, isMobile and 0 or -4, allocH, 0)
	allocationSection.Position = UDim2.new(allocX, isMobile and 0 or 4, allocY, 0)
	allocationSection.BackgroundTransparency = 1
	allocationSection.BorderSizePixel = 0
	allocationSection.ScrollBarThickness = 6
	allocationSection.AutomaticCanvasSize = Enum.AutomaticSize.Y
	allocationSection.CanvasSize = UDim2.fromOffset(0, 0)
	allocationSection.Parent = statsContentFrame

	local allocInner = Instance.new("Frame")
	allocInner.Name = "AllocInner"
	allocInner.Size = UDim2.new(1, 0, 0, 0)
	allocInner.AutomaticSize = Enum.AutomaticSize.Y
	allocInner.BackgroundTransparency = 1
	allocInner.Parent = allocationSection

	local allocSectionLayout = Instance.new("UIListLayout")
	allocSectionLayout.FillDirection = Enum.FillDirection.Vertical
	allocSectionLayout.Padding = UDim.new(0, 6)
	allocSectionLayout.Parent = allocInner

	local allocSectionPadding = Instance.new("UIPadding")
	allocSectionPadding.PaddingTop = UDim.new(0, 4)
	allocSectionPadding.PaddingRight = UDim.new(0, 4)
	allocSectionPadding.PaddingBottom = UDim.new(0, 4)
	allocSectionPadding.Parent = allocInner
	
	-- Luck Stat Card (compact for narrow column)
	local luckCard = createStatCard(statsContainer, "Luck", "rbxassetid://6031071053", Color3.fromRGB(255, 200, 50), true)
	luckLabel = luckCard:FindFirstChild("ValueLabel")
	
	-- Roll Speed Stat Card
	local speedCard = createStatCard(statsContainer, "Roll Speed", "rbxassetid://6031094678", Color3.fromRGB(50, 200, 255), true)
	rollSpeedLabel = speedCard:FindFirstChild("ValueLabel")
	
	-- Potion Duration Stat Card
	local potionDurationCard = createStatCard(statsContainer, "Potion Duration", "rbxassetid://6031075931", Color3.fromRGB(182, 114, 255), true)
	potionDurationLabel = potionDurationCard:FindFirstChild("ValueLabel")
	
	-- Border Chance Stat Card
	local borderChanceCard = createStatCard(statsContainer, "Border Chance", "rbxassetid://6031280882", Color3.fromRGB(255, 150, 92), true)
	borderChanceLabel = borderChanceCard:FindFirstChild("ValueLabel")
	
	-- Points Stat Card
	local pointsCard = createStatCard(statsContainer, "Points", "rbxassetid://6031071050", Color3.fromRGB(100, 255, 100), true)
	pointsLabel = pointsCard:FindFirstChild("ValueLabel")

	local luckEffectCard = createStatCard(effectsContainer, "Luck Effect", "rbxassetid://6031071053", Color3.fromRGB(255, 200, 50), true)
	effectLabels.LuckMultiplier = luckEffectCard:FindFirstChild("ValueLabel")
	local rollSpeedEffectCard = createStatCard(effectsContainer, "Roll Speed Effect", "rbxassetid://6031094678", Color3.fromRGB(50, 200, 255), true)
	effectLabels.RollSpeed = rollSpeedEffectCard:FindFirstChild("ValueLabel")
	local potionEffectCard = createStatCard(effectsContainer, "Potion Effect", "rbxassetid://6031075931", Color3.fromRGB(182, 114, 255), true)
	effectLabels.PotionDuration = potionEffectCard:FindFirstChild("ValueLabel")
	local borderEffectCard = createStatCard(effectsContainer, "Border Effect", "rbxassetid://6031280882", Color3.fromRGB(255, 150, 92), true)
	effectLabels.FoilChance = borderEffectCard:FindFirstChild("ValueLabel")

	-- Section header for rarity effects
	local rarityHeader = Instance.new("TextLabel")
	rarityHeader.Name = "RarityEffectsHeader"
	rarityHeader.Size = UDim2.new(1, 0, 0, 20)
	rarityHeader.BackgroundTransparency = 1
	rarityHeader.Text = "Rarity Effects"
	rarityHeader.Font = Enum.Font.GothamBold
	rarityHeader.TextSize = 12
	rarityHeader.TextColor3 = Color3.fromRGB(160, 170, 190)
	rarityHeader.TextXAlignment = Enum.TextXAlignment.Left
	rarityHeader.Parent = effectsContainer

	local godRateCard = createStatCard(effectsContainer, "God Roll Chance", "rbxassetid://6031071050", Color3.fromRGB(255, 110, 110), true)
	effectLabels.God = godRateCard:FindFirstChild("ValueLabel")
	local legendaryRateCard = createStatCard(effectsContainer, "Legendary Roll Chance", "rbxassetid://6031071050", Color3.fromRGB(255, 196, 84), true)
	effectLabels.Legendary = legendaryRateCard:FindFirstChild("ValueLabel")
	local mythicRateCard = createStatCard(effectsContainer, "Mythic Roll Chance", "rbxassetid://6031071050", Color3.fromRGB(198, 120, 255), true)
	effectLabels.Mythic = mythicRateCard:FindFirstChild("ValueLabel")
	local rareRateCard = createStatCard(effectsContainer, "Rare Roll Chance", "rbxassetid://6031071050", Color3.fromRGB(120, 200, 255), true)
	effectLabels.Rare = rareRateCard:FindFirstChild("ValueLabel")
	local uncommonRateCard = createStatCard(effectsContainer, "Uncommon Roll Chance", "rbxassetid://6031071050", Color3.fromRGB(150, 255, 170), true)
	effectLabels.Uncommon = uncommonRateCard:FindFirstChild("ValueLabel")

	local function setLeftTab(activeTab)
		local isStats = (activeTab == "Stats")
		local isEffects = (activeTab == "Effects")
		statsContentFrame.Visible = isStats
		effectsContainer.Visible = isEffects
		statsTitle.BackgroundColor3 = isStats and Color3.fromRGB(55, 75, 120) or Color3.fromRGB(45, 45, 60)
		statsTitle.TextColor3 = isStats and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
		effectsTitle.BackgroundColor3 = isEffects and Color3.fromRGB(120, 82, 55) or Color3.fromRGB(45, 45, 60)
		effectsTitle.TextColor3 = isEffects and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
	end

	statsTitle.MouseButton1Click:Connect(function() setLeftTab("Stats") end)
	effectsTitle.MouseButton1Click:Connect(function() setLeftTab("Effects") end)

	setLeftTab("Stats")

	-- === RIGHT PANEL: Large card slot (Favorite/Equip placeholder) ===
	local favoriteSlot = Instance.new("Frame")
	favoriteSlot.Name = "FavoriteCardSlot"
	favoriteSlot.Size = UDim2.new(1, 0, 1, 0)
	favoriteSlot.Position = UDim2.new(0, 0, 0, 0)
	favoriteSlot.BackgroundColor3 = Color3.fromRGB(28, 30, 42)
	favoriteSlot.BorderSizePixel = 0
	favoriteSlot.Parent = rightPanel

	local favoriteCorner = Instance.new("UICorner")
	favoriteCorner.CornerRadius = UDim.new(0, 12)
	favoriteCorner.Parent = favoriteSlot

	local favoriteStroke = Instance.new("UIStroke")
	favoriteStroke.Thickness = 2
	favoriteStroke.Color = Color3.fromRGB(80, 90, 120)
	favoriteStroke.Transparency = 0.5
	favoriteStroke.Parent = favoriteSlot

	-- Centered inner card-area frame (220x330 card aspect)
	local cardAreaFrame = Instance.new("Frame")
	cardAreaFrame.Name = "CardAreaFrame"
	cardAreaFrame.Size = UDim2.fromOffset(220, 330)
	cardAreaFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	cardAreaFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	cardAreaFrame.BackgroundColor3 = Color3.fromRGB(35, 38, 55)
	cardAreaFrame.BorderSizePixel = 0
	cardAreaFrame.Parent = favoriteSlot

	local cardAreaCorner = Instance.new("UICorner")
	cardAreaCorner.CornerRadius = UDim.new(0, 12)
	cardAreaCorner.Parent = cardAreaFrame

	local cardAreaStroke = Instance.new("UIStroke")
	cardAreaStroke.Thickness = 2
	cardAreaStroke.Color = Color3.fromRGB(100, 110, 140)
	cardAreaStroke.Transparency = 0.4
	cardAreaStroke.Parent = cardAreaFrame

	local favoriteLabel = Instance.new("TextLabel")
	favoriteLabel.Name = "PlaceholderLabel"
	favoriteLabel.Size = UDim2.new(1, -24, 1, -24)
	favoriteLabel.Position = UDim2.new(0, 12, 0, 12)
	favoriteLabel.AnchorPoint = Vector2.new(0, 0)
	favoriteLabel.BackgroundTransparency = 1
	favoriteLabel.Text = "Equip Card (Coming Soon)"
	favoriteLabel.Font = Enum.Font.Gotham
	favoriteLabel.TextSize = 16
	favoriteLabel.TextColor3 = Color3.fromRGB(140, 150, 170)
	favoriteLabel.TextXAlignment = Enum.TextXAlignment.Center
	favoriteLabel.TextYAlignment = Enum.TextYAlignment.Center
	favoriteLabel.TextWrapped = true
	favoriteLabel.Parent = cardAreaFrame

	-- Allocation UI (right side - scrollable)
	allocPointsLabel = Instance.new("TextLabel")
	allocPointsLabel.Name = "AllocPointsLabel"
	allocPointsLabel.Size = UDim2.new(1, 0, 0, 20)
	allocPointsLabel.BackgroundTransparency = 1
	allocPointsLabel.Text = "Available: 0"
	allocPointsLabel.Font = Enum.Font.GothamBold
	allocPointsLabel.TextSize = 14
	allocPointsLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
	allocPointsLabel.TextXAlignment = Enum.TextXAlignment.Left
	allocPointsLabel.TextTruncate = Enum.TextTruncate.AtEnd
	allocPointsLabel.Parent = allocInner
	
	local buttonsContainer = Instance.new("Frame")
	buttonsContainer.Name = "ButtonsContainer"
	buttonsContainer.Size = UDim2.new(1, 0, 0, 0)
	buttonsContainer.AutomaticSize = Enum.AutomaticSize.Y
	buttonsContainer.BackgroundTransparency = 1
	buttonsContainer.Parent = allocInner
	
	local buttonsLayout = Instance.new("UIListLayout")
	buttonsLayout.FillDirection = Enum.FillDirection.Vertical
	buttonsLayout.Padding = UDim.new(0, 6)
	buttonsLayout.Parent = buttonsContainer
	
	-- Add Luck Button
	local addLuckBtn = createAllocationButton(buttonsContainer, "+ Add Luck", Color3.fromRGB(60, 140, 80))
	addLuckBtn.MouseButton1Click:Connect(function()
		if allocateRemote then
			local result = allocateRemote:InvokeServer({action = "allocate", stat = "Luck"})
			if result then
				updateUI(result)
			end
		else
			warn("[ProfileUI] allocateRemote not available!")
		end
	end)
	
	-- Add Roll Speed Button
	local addSpeedBtn = createAllocationButton(buttonsContainer, "+ Add Roll Speed", Color3.fromRGB(60, 100, 160))
	addSpeedBtn.MouseButton1Click:Connect(function()
		if allocateRemote then
			local result = allocateRemote:InvokeServer({action = "allocate", stat = "RollSpeed"})
			if result then
				updateUI(result)
			end
		else
			warn("[ProfileUI] allocateRemote not available!")
		end
	end)
	
	-- Add Potion Duration Button
	local addPotionDurationBtn = createAllocationButton(buttonsContainer, "+ Add Potion Duration", Color3.fromRGB(132, 82, 196))
	addPotionDurationBtn.MouseButton1Click:Connect(function()
		if allocateRemote then
			local result = allocateRemote:InvokeServer({action = "allocate", stat = "PotionDuration"})
			if result then
				updateUI(result)
			end
		else
			warn("[ProfileUI] allocateRemote not available!")
		end
	end)
	
	-- Add Foil Chance Button
	local addFoilChanceBtn = createAllocationButton(buttonsContainer, "+ Add Foil Chance", Color3.fromRGB(188, 118, 70))
	addFoilChanceBtn.MouseButton1Click:Connect(function()
		if allocateRemote then
			local result = allocateRemote:InvokeServer({action = "allocate", stat = "FoilChance"})
			if result then
				updateUI(result)
			end
		else
			warn("[ProfileUI] allocateRemote not available!")
		end
	end)
	
	-- Reset Button
	local resetBtn = createAllocationButton(buttonsContainer, "Reset All Points", Color3.fromRGB(180, 60, 80))
	resetBtn.MouseButton1Click:Connect(function()
		if allocateRemote then
			local result = allocateRemote:InvokeServer({action = "reset"})
			if result then
				updateUI(result)
			end
		else
			warn("[ProfileUI] allocateRemote not available!")
		end
	end)
	
	task.spawn(initRemotes)
end

-- Helper to create a stat card (compact = smaller icon/fonts; ultraCompact on mobile)
createStatCard = function(parent, statName, iconId, color, compact)
	compact = compact == true
	local ultraCompact = compact and DeviceContext.getIsMobile()
	local iconSize = ultraCompact and 28 or (compact and 36 or 60)
	local cardHeight = ultraCompact and 44 or (compact and 56 or 100)
	local leftMargin = ultraCompact and 6 or (compact and 8 or 20)
	local textLeft = ultraCompact and 38 or (compact and 52 or 90)
	
	local card = Instance.new("Frame")
	card.Name = statName .. "Card"
	card.Size = UDim2.new(1, 0, 0, cardHeight)
	card.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
	card.BorderSizePixel = 0
	card.Parent = parent
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, ultraCompact and 6 or (compact and 8 or 12))
	corner.Parent = card
	
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = ultraCompact and 1 or (compact and 1 or 2)
	stroke.Color = color
	stroke.Transparency = 0.5
	stroke.Parent = card
	
	-- Icon
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, iconSize, 0, iconSize)
	icon.Position = UDim2.new(0, leftMargin, 0.5, -iconSize / 2)
	icon.BackgroundTransparency = 1
	icon.Image = iconId
	icon.ImageColor3 = color
	icon.Parent = card
	
	-- Stat name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, -textLeft - 8, 0, ultraCompact and 14 or (compact and 18 or 30))
	nameLabel.Position = UDim2.new(0, textLeft, 0, ultraCompact and 4 or (compact and 6 or 20))
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = statName
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = ultraCompact and 10 or (compact and 12 or 20)
	nameLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = card
	
	-- Value
	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "ValueLabel"
	valueLabel.Size = UDim2.new(1, -textLeft - 8, 0, ultraCompact and 22 or (compact and 28 or 40))
	valueLabel.Position = UDim2.new(0, textLeft, 0, ultraCompact and 22 or (compact and 28 or 45))
	valueLabel.BackgroundTransparency = 1
	valueLabel.Text = "0"
	valueLabel.Font = Enum.Font.GothamBold
	valueLabel.TextSize = ultraCompact and 16 or (compact and 20 or 32)
	valueLabel.TextColor3 = color
	valueLabel.TextXAlignment = Enum.TextXAlignment.Left
	valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
	valueLabel.Parent = card
	
	return card
end

-- Helper to create allocation button (compact for narrow allocation column)
createAllocationButton = function(parent, text, color)
	local btn = Instance.new("TextButton")
	btn.Name = text:gsub("[^%w]", "") .. "Btn"
	btn.Size = UDim2.new(1, 0, 0, math.max(30, DeviceContext.getTouchTargetMin()))
	btn.BackgroundColor3 = color
	btn.Text = text
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 14
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.BorderSizePixel = 0
	btn.Parent = parent
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = btn
	
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = color:lerp(Color3.new(1, 1, 1), 0.3)
	stroke.Parent = btn
	
	-- Hover effects
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = color:lerp(Color3.new(1, 1, 1), 0.2)}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.2), {Transparency = 0}):Play()
	end)
	
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = color}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.2), {Transparency = 0}):Play()
	end)
	
	return btn
end

-- Fetch initial stat snapshot from server.
-- ClientStateManager.subscribe (set up in Setup) is the primary live-update path via
-- StatsUpdatedEvent; this only fetches the initial authoritative value via InvokeServer.
initRemotes = function()
	allocateRemote = ReplicatedStorage:WaitForChild("AllocatePointsRemote", 30)

	if allocateRemote then
		local success, result = pcall(function()
			return allocateRemote:InvokeServer({action = "get"})
		end)
		if success and result then
			updateUI(result)
		end
	else
		warn("[ProfileUI] AllocatePointsRemote not found!")
	end
end

return ProfileUIController
