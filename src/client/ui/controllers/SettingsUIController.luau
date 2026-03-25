-- SettingsUIController.luau
-- Game settings UI with tabbed layout: Audio, Graphics, Controls, Gameplay

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local DeviceContext = require(script.Parent.Parent.Parent.core:WaitForChild("DeviceContext"))
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsUIController = {}

local contentFrame = nil

-- Persistent settings state
local settingsState = {
	MasterVolume = 1.0,
	MusicVolume = 0.8,
	SFXVolume = 1.0,
	GraphicsQuality = "Auto",
	ShowDamageNumbers = true,
	ShowParticles = true,
	ScreenShake = true,
	CameraFOV = 70,
	ShowCardBorders = true,
	ShowHoverPreview = true,
	AutoRollEnabled = false,
	ShowIdleRollCardNotifications = true,
}

-- Style constants (touch targets on mobile)
local TAB_HEIGHT = 44
local TAB_GAP = 8
local SECTION_PAD = 16
local function getControlHeight()
	return math.max(40, DeviceContext.getTouchTargetMin())
end
local ACTIVE_TAB_COLOR = Color3.fromRGB(80, 90, 120)
local INACTIVE_TAB_COLOR = Color3.fromRGB(35, 38, 50)
local SLIDER_BG_COLOR = Color3.fromRGB(30, 32, 42)
local SLIDER_FILL_COLOR = Color3.fromRGB(100, 140, 230)
local TOGGLE_ON_COLOR = Color3.fromRGB(80, 180, 100)
local TOGGLE_OFF_COLOR = Color3.fromRGB(60, 60, 75)
local TEXT_COLOR = Color3.new(1, 1, 1)
local MUTED_TEXT = Color3.fromRGB(180, 180, 195)

----------------------------------------------------------------
-- UI builder helpers
----------------------------------------------------------------

local function createSectionLabel(parent, text, layoutOrder)
	local label = Instance.new("TextLabel")
	label.Name = "Section_" .. text
	label.Size = UDim2.new(1, 0, 0, 28)
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextColor3 = MUTED_TEXT
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.LayoutOrder = layoutOrder
	label.Parent = parent
	return label
end

local function createSlider(parent, labelText, min, max, initial, layoutOrder, onChange)
	local row = Instance.new("Frame")
	row.Name = "Slider_" .. labelText
	row.Size = UDim2.new(1, 0, 0, getControlHeight())
	row.BackgroundTransparency = 1
	row.LayoutOrder = layoutOrder
	row.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.35, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 15
	label.TextColor3 = TEXT_COLOR
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = row

	local sliderBg = Instance.new("Frame")
	sliderBg.Name = "SliderBg"
	local trackH = math.max(10, DeviceContext.getTouchTargetMin() - 20)
	sliderBg.Size = UDim2.new(0.5, 0, 0, trackH)
	sliderBg.Position = UDim2.new(0.36, 0, 0.5, -trackH / 2)
	sliderBg.BackgroundColor3 = SLIDER_BG_COLOR
	sliderBg.BorderSizePixel = 0
	sliderBg.Parent = row

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 5)
	bgCorner.Parent = sliderBg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale((initial - min) / (max - min), 1)
	fill.BackgroundColor3 = SLIDER_FILL_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = sliderBg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 5)
	fillCorner.Parent = fill

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "Value"
	valueLabel.Size = UDim2.new(0.12, 0, 1, 0)
	valueLabel.Position = UDim2.new(0.88, 0, 0, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Text = tostring(math.floor(initial * 100 + 0.5)) .. "%"
	valueLabel.Font = Enum.Font.GothamBold
	valueLabel.TextSize = 14
	valueLabel.TextColor3 = SLIDER_FILL_COLOR
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Parent = row

	-- Dragging
	local dragging = false
	local function updateFromInput(inputPos)
		local absPos = sliderBg.AbsolutePosition.X
		local absSize = sliderBg.AbsoluteSize.X
		if absSize <= 0 then return end
		local pct = math.clamp((inputPos.X - absPos) / absSize, 0, 1)
		local value = min + pct * (max - min)
		fill.Size = UDim2.fromScale(pct, 1)
		valueLabel.Text = tostring(math.floor(value * 100 + 0.5)) .. "%"
		if onChange then
			onChange(value)
		end
	end

	sliderBg.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			updateFromInput(input.Position)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			updateFromInput(input.Position)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	return row
end

local function createToggle(parent, labelText, initial, layoutOrder, onChange)
	local row = Instance.new("Frame")
	row.Name = "Toggle_" .. labelText
	row.Size = UDim2.new(1, 0, 0, getControlHeight())
	row.BackgroundTransparency = 1
	row.LayoutOrder = layoutOrder
	row.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.75, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 15
	label.TextColor3 = TEXT_COLOR
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = row

	local toggleW = DeviceContext.getIsMobile() and 56 or 52
	local toggleH = math.max(26, DeviceContext.getTouchTargetMin() - 8)
	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Name = "ToggleBtn"
	toggleBtn.Size = UDim2.fromOffset(toggleW, toggleH)
	toggleBtn.Position = UDim2.new(1, -toggleW, 0.5, -toggleH / 2)
	toggleBtn.BackgroundColor3 = initial and TOGGLE_ON_COLOR or TOGGLE_OFF_COLOR
	toggleBtn.Text = ""
	toggleBtn.AutoButtonColor = false
	toggleBtn.BorderSizePixel = 0
	toggleBtn.Parent = row

	local toggleCorner = Instance.new("UICorner")
	toggleCorner.CornerRadius = UDim.new(0, 13)
	toggleCorner.Parent = toggleBtn

	local knobSize = math.min(20, toggleH - 6)
	local knobPad = 3
	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.Size = UDim2.fromOffset(knobSize, knobSize)
	knob.Position = initial and UDim2.fromOffset(toggleW - knobSize - knobPad, (toggleH - knobSize) / 2) or UDim2.fromOffset(knobPad, (toggleH - knobSize) / 2)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BorderSizePixel = 0
	knob.Parent = toggleBtn

	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(0, 10)
	knobCorner.Parent = knob

	local isOn = initial
	toggleBtn.MouseButton1Click:Connect(function()
		isOn = not isOn
		TweenService:Create(toggleBtn, TweenInfo.new(0.18), {
			BackgroundColor3 = isOn and TOGGLE_ON_COLOR or TOGGLE_OFF_COLOR
		}):Play()
		local knobXOn = toggleW - knobSize - knobPad
		local knobY = (toggleH - knobSize) / 2
		TweenService:Create(knob, TweenInfo.new(0.18), {
			Position = isOn and UDim2.fromOffset(knobXOn, knobY) or UDim2.fromOffset(knobPad, knobY)
		}):Play()
		if onChange then
			onChange(isOn)
		end
	end)

	return row
end

local function createDropdown(parent, labelText, options, initial, layoutOrder, onChange)
	local row = Instance.new("Frame")
	row.Name = "Dropdown_" .. labelText
	row.Size = UDim2.new(1, 0, 0, getControlHeight())
	row.BackgroundTransparency = 1
	row.LayoutOrder = layoutOrder
	row.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.5, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 15
	label.TextColor3 = TEXT_COLOR
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = row

	local currentIndex = 1
	for i, opt in ipairs(options) do
		if opt == initial then
			currentIndex = i
			break
		end
	end

	local btn = Instance.new("TextButton")
	btn.Name = "DropdownBtn"
	btn.Size = UDim2.new(0.45, 0, 0, 30)
	btn.Position = UDim2.new(0.55, 0, 0.5, -15)
	btn.BackgroundColor3 = SLIDER_BG_COLOR
	btn.Text = tostring(options[currentIndex])
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 14
	btn.TextColor3 = SLIDER_FILL_COLOR
	btn.AutoButtonColor = false
	btn.BorderSizePixel = 0
	btn.Parent = row

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = btn

	btn.MouseButton1Click:Connect(function()
		currentIndex = (currentIndex % #options) + 1
		btn.Text = tostring(options[currentIndex])
		if onChange then
			onChange(options[currentIndex])
		end
	end)

	return row
end

----------------------------------------------------------------
-- Tab content builders
----------------------------------------------------------------

local function buildAudioTab(scrollFrame)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scrollFrame

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, SECTION_PAD)
	pad.PaddingLeft = UDim.new(0, SECTION_PAD)
	pad.PaddingRight = UDim.new(0, SECTION_PAD)
	pad.Parent = scrollFrame

	createSectionLabel(scrollFrame, "Volume", 1)

	createSlider(scrollFrame, "Master Volume", 0, 1, settingsState.MasterVolume, 2, function(v)
		settingsState.MasterVolume = v
		SoundService.Volume = v
	end)

	createSlider(scrollFrame, "Music", 0, 1, settingsState.MusicVolume, 3, function(v)
		settingsState.MusicVolume = v
	end)

	createSlider(scrollFrame, "Sound Effects", 0, 1, settingsState.SFXVolume, 4, function(v)
		settingsState.SFXVolume = v
	end)
end

local function buildGraphicsTab(scrollFrame)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scrollFrame

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, SECTION_PAD)
	pad.PaddingLeft = UDim.new(0, SECTION_PAD)
	pad.PaddingRight = UDim.new(0, SECTION_PAD)
	pad.Parent = scrollFrame

	createSectionLabel(scrollFrame, "Quality", 1)

	createDropdown(scrollFrame, "Graphics Quality", {"Auto", "Low", "Medium", "High"}, settingsState.GraphicsQuality, 2, function(v)
		settingsState.GraphicsQuality = v
		if v == "Low" then
			settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
		elseif v == "Medium" then
			settings().Rendering.QualityLevel = Enum.QualityLevel.Level04
		elseif v == "High" then
			settings().Rendering.QualityLevel = Enum.QualityLevel.Level10
		else
			settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
		end
	end)

	createSectionLabel(scrollFrame, "Effects", 10)

	createToggle(scrollFrame, "Show Particles", settingsState.ShowParticles, 11, function(v)
		settingsState.ShowParticles = v
	end)

	createToggle(scrollFrame, "Show Damage Numbers", settingsState.ShowDamageNumbers, 12, function(v)
		settingsState.ShowDamageNumbers = v
	end)

	createToggle(scrollFrame, "Screen Shake", settingsState.ScreenShake, 13, function(v)
		settingsState.ScreenShake = v
	end)

	createSlider(scrollFrame, "Camera FOV", 0.5, 1.2, settingsState.CameraFOV / 120, 14, function(v)
		settingsState.CameraFOV = math.floor(v * 120)
		workspace.CurrentCamera.FieldOfView = settingsState.CameraFOV
	end)
end

local function buildControlsTab(scrollFrame)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scrollFrame

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, SECTION_PAD)
	pad.PaddingLeft = UDim.new(0, SECTION_PAD)
	pad.PaddingRight = UDim.new(0, SECTION_PAD)
	pad.Parent = scrollFrame

	createSectionLabel(scrollFrame, "Keybinds", 1)

	local keybinds = {
		{label = "Open Inventory", key = "B", order = 2},
		{label = "Open Shop", key = "N", order = 3},
		{label = "Open Profile", key = "P", order = 4},
		{label = "Toggle Settings", key = "ESC", order = 5},
		{label = "Quick Roll", key = "R", order = 6},
	}

	for _, bind in ipairs(keybinds) do
		local row = Instance.new("Frame")
		row.Name = "Keybind_" .. bind.label
		row.Size = UDim2.new(1, 0, 0, getControlHeight())
		row.BackgroundTransparency = 1
		row.LayoutOrder = bind.order
		row.Parent = scrollFrame

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(0.6, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = bind.label
		lbl.Font = Enum.Font.GothamMedium
		lbl.TextSize = 15
		lbl.TextColor3 = TEXT_COLOR
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = row

		local keyBtn = Instance.new("TextButton")
		keyBtn.Name = "KeyBtn"
		keyBtn.Size = UDim2.fromOffset(80, 30)
		keyBtn.Position = UDim2.new(1, -80, 0.5, -15)
		keyBtn.BackgroundColor3 = SLIDER_BG_COLOR
		keyBtn.Text = "[" .. bind.key .. "]"
		keyBtn.Font = Enum.Font.GothamBold
		keyBtn.TextSize = 14
		keyBtn.TextColor3 = SLIDER_FILL_COLOR
		keyBtn.AutoButtonColor = false
		keyBtn.BorderSizePixel = 0
		keyBtn.Parent = row

		local keyCorner = Instance.new("UICorner")
		keyCorner.CornerRadius = UDim.new(0, 6)
		keyCorner.Parent = keyBtn
	end

	createSectionLabel(scrollFrame, "Mouse", 10)

	createToggle(scrollFrame, "Invert Camera Y", false, 11, function(_v)
	end)
end

local function buildGameplayTab(scrollFrame)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scrollFrame

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, SECTION_PAD)
	pad.PaddingLeft = UDim.new(0, SECTION_PAD)
	pad.PaddingRight = UDim.new(0, SECTION_PAD)
	pad.Parent = scrollFrame

	createSectionLabel(scrollFrame, "Card Display", 1)

	createToggle(scrollFrame, "Show Card Borders", settingsState.ShowCardBorders, 2, function(v)
		settingsState.ShowCardBorders = v
	end)

	createToggle(scrollFrame, "Show Hover Preview", settingsState.ShowHoverPreview, 3, function(v)
		settingsState.ShowHoverPreview = v
	end)

	createToggle(scrollFrame, "Show Idle Roll Card Popups", settingsState.ShowIdleRollCardNotifications, 4, function(v)
		settingsState.ShowIdleRollCardNotifications = v
		local ev = ReplicatedStorage:FindFirstChild("ClientSettingsChangedEvent")
		if ev and ev:IsA("BindableEvent") then
			ev:Fire()
		end
	end)

	createSectionLabel(scrollFrame, "Automation", 10)

	createToggle(scrollFrame, "Auto Roll", settingsState.AutoRollEnabled, 12, function(v)
		settingsState.AutoRollEnabled = v
	end)
end

----------------------------------------------------------------
-- Main setup
----------------------------------------------------------------

function SettingsUIController.Setup(parentContent)
	if not parentContent then
		warn("[SettingsUI] No content frame provided!")
		return
	end

	contentFrame = parentContent

	for _, child in ipairs(contentFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	-- Tab bar
	local tabBar = Instance.new("Frame")
	tabBar.Name = "SettingsTabBar"
	tabBar.Size = UDim2.new(1, 0, 0, TAB_HEIGHT)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = contentFrame

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, TAB_GAP)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabBar

	-- Content area
	local contentArea = Instance.new("Frame")
	contentArea.Name = "SettingsContentArea"
	contentArea.Size = UDim2.new(1, 0, 1, -(TAB_HEIGHT + 12))
	contentArea.Position = UDim2.fromOffset(0, TAB_HEIGHT + 12)
	contentArea.BackgroundTransparency = 1
	contentArea.Parent = contentFrame

	local tabs = {
		{name = "Audio", builder = buildAudioTab, order = 1},
		{name = "Graphics", builder = buildGraphicsTab, order = 2},
		{name = "Controls", builder = buildControlsTab, order = 3},
		{name = "Gameplay", builder = buildGameplayTab, order = 4},
	}

	local tabButtons = {}
	local tabScrolls = {}

	for _, tab in ipairs(tabs) do
		-- ScrollingFrame per tab
		local scroll = Instance.new("ScrollingFrame")
		scroll.Name = tab.name .. "Scroll"
		scroll.Size = UDim2.fromScale(1, 1)
		scroll.BackgroundTransparency = 0.5
		scroll.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
		scroll.BorderSizePixel = 0
		scroll.ScrollBarThickness = 6
		scroll.Visible = (tab.order == 1)
		scroll.CanvasSize = UDim2.fromOffset(0, 400)
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.Parent = contentArea

		local scrollCorner = Instance.new("UICorner")
		scrollCorner.CornerRadius = UDim.new(0, 12)
		scrollCorner.Parent = scroll

		tab.builder(scroll)
		tabScrolls[tab.name] = scroll

		-- Tab button
		local btn = Instance.new("TextButton")
		btn.Name = tab.name .. "Tab"
		btn.Size = UDim2.fromOffset(110, TAB_HEIGHT)
		btn.BackgroundColor3 = (tab.order == 1) and ACTIVE_TAB_COLOR or INACTIVE_TAB_COLOR
		btn.Text = tab.name
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 15
		btn.TextColor3 = TEXT_COLOR
		btn.AutoButtonColor = false
		btn.BorderSizePixel = 0
		btn.LayoutOrder = tab.order
		btn.Parent = tabBar

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 8)
		btnCorner.Parent = btn

		local btnStroke = Instance.new("UIStroke")
		btnStroke.Thickness = 1.5
		btnStroke.Color = SLIDER_FILL_COLOR
		btnStroke.Transparency = (tab.order == 1) and 0 or 0.6
		btnStroke.Parent = btn

		tabButtons[tab.name] = {btn = btn, stroke = btnStroke}

		btn.MouseButton1Click:Connect(function()
			for tName, tScroll in pairs(tabScrolls) do
				tScroll.Visible = (tName == tab.name)
			end
			for tName, tBtn in pairs(tabButtons) do
				local isActive = (tName == tab.name)
				TweenService:Create(tBtn.btn, TweenInfo.new(0.15), {
					BackgroundColor3 = isActive and ACTIVE_TAB_COLOR or INACTIVE_TAB_COLOR
				}):Play()
				TweenService:Create(tBtn.stroke, TweenInfo.new(0.15), {
					Transparency = isActive and 0 or 0.6
				}):Play()
			end
		end)
	end
end

function SettingsUIController.GetState()
	return settingsState
end

-- Apply saved client settings from server (e.g. on load/rejoin)
function SettingsUIController.ApplyClientSettings(clientSettings)
	if type(clientSettings) ~= "table" then
		return
	end
	if clientSettings.ShowIdleRollCardNotifications ~= nil then
		settingsState.ShowIdleRollCardNotifications = (clientSettings.ShowIdleRollCardNotifications == true)
	end
end

return SettingsUIController
