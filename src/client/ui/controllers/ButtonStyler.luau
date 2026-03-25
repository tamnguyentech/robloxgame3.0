-- ButtonStyler.luau
-- Clean RPG Idle Game Button Styling with Gradient Loop Animation

local ButtonStyler = {}
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- RPG Rarity Color Palettes
local RARITY_PALETTES = {
	Rare = {
		primary = Color3.fromRGB(0, 120, 255),
		secondary = Color3.fromRGB(0, 200, 255),
		accent = Color3.fromRGB(100, 220, 255),
		dark = Color3.fromRGB(0, 60, 140),
	},
	Epic = {
		primary = Color3.fromRGB(180, 0, 255),
		secondary = Color3.fromRGB(255, 0, 220),
		accent = Color3.fromRGB(255, 100, 255),
		dark = Color3.fromRGB(80, 0, 120),
	},
	Legendary = {
		primary = Color3.fromRGB(255, 140, 0),
		secondary = Color3.fromRGB(255, 220, 0),
		accent = Color3.fromRGB(255, 255, 100),
		dark = Color3.fromRGB(180, 80, 0),
	},
	God = {
		primary = Color3.fromRGB(255, 0, 60),
		secondary = Color3.fromRGB(255, 80, 80),
		accent = Color3.fromRGB(255, 150, 150),
		dark = Color3.fromRGB(150, 0, 30),
	},
	Common = {
		primary = Color3.fromRGB(140, 140, 160),
		secondary = Color3.fromRGB(220, 220, 240),
		accent = Color3.fromRGB(255, 255, 255),
		dark = Color3.fromRGB(80, 80, 100),
	},
	Transcendent = {
		primary = Color3.fromRGB(0, 255, 255),
		secondary = Color3.fromRGB(255, 0, 255),
		accent = Color3.fromRGB(255, 255, 0),
		dark = Color3.fromRGB(0, 100, 120),
	},
}

local BUTTON_TYPE_TO_RARITY = {
	Backpack = "Rare",
	Deck = "Epic",
	Shop = "Epic",
	Profile = "Legendary",
	Quests = "God",
	Settings = "Common",
	Teleport = "Transcendent",
}

-- Main styling function
function ButtonStyler.styleToggleButton(button, text, bgColor, iconImage, buttonType)
	buttonType = buttonType or "Common"
	local palette = RARITY_PALETTES[BUTTON_TYPE_TO_RARITY[buttonType]] or RARITY_PALETTES.Common
	
	-- Clean button setup
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.BackgroundColor3 = palette.dark
	button.BackgroundTransparency = 0
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = false
	button.ClipsDescendants = true
	
	-- Rounded corners
	local corner = button:FindFirstChildOfClass("UICorner")
	if not corner then
		corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = button
	end
	
	-- Clean gradient - directly on button, flowing horizontally
	local gradient = button:FindFirstChild("ButtonGradient")
	if gradient then
		gradient:Destroy()
	end
	gradient = Instance.new("UIGradient")
	gradient.Name = "ButtonGradient"
	gradient.Rotation = 0
	
	-- Flowing gradient using primary and secondary colors
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, palette.primary),
		ColorSequenceKeypoint.new(0.5, palette.secondary),
		ColorSequenceKeypoint.new(1, palette.primary),
	})
	gradient.Parent = button
	
	-- Animate gradient offset (flowing effect) - contained within button
	local offset = 0
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not button or not button.Parent then
			connection:Disconnect()
			return
		end
		offset = (offset + dt * 0.3) % 1
		gradient.Offset = Vector2.new(offset - 0.5, 0)
	end)
	
	-- Single clean border stroke
	local border = button:FindFirstChild("ButtonBorder")
	if border then
		border:Destroy()
	end
	border = Instance.new("UIStroke")
	border.Name = "ButtonBorder"
	border.Thickness = 2
	border.Color = palette.accent
	border.Transparency = 0.4
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Parent = button
	
	-- Icon
	local icon = button:FindFirstChild("Icon")
	if not icon then
		icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.ZIndex = button.ZIndex + 2
		icon.Parent = button
	end
	icon.Size = UDim2.fromOffset(44, 44)
	icon.Position = UDim2.new(0.5, -22, 0, 6)
	icon.Image = iconImage
	icon.ImageColor3 = Color3.new(1, 1, 1)
	
	-- Text label
	local label = button:FindFirstChild("Label")
	if not label then
		label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextSize = 14
		label.ZIndex = button.ZIndex + 3
		label.Parent = button
	end
	label.Size = UDim2.new(1, -8, 0, 18)
	label.Position = UDim2.new(0, 4, 1, -22)
	label.Text = text
	
	-- Subtle text shadow
	local shadow = button:FindFirstChild("TextShadow")
	if not shadow then
		shadow = Instance.new("TextLabel")
		shadow.Name = "TextShadow"
		shadow.Size = label.Size
		shadow.Position = UDim2.new(0, 5, 1, -25)
		shadow.BackgroundTransparency = 1
		shadow.TextColor3 = Color3.new(0, 0, 0)
		shadow.Font = label.Font
		shadow.TextXAlignment = label.TextXAlignment
		shadow.TextSize = label.TextSize
		shadow.ZIndex = button.ZIndex + 2
		shadow.TextTransparency = 0.7
		shadow.Parent = button
	end
	shadow.Text = text
	
	-- Hover effect
	local function onHover()
		TweenService:Create(button, TweenInfo.new(0.2), {BackgroundColor3 = palette.primary}):Play()
		TweenService:Create(border, TweenInfo.new(0.2), {Color = palette.accent, Transparency = 0.1}):Play()
		TweenService:Create(icon, TweenInfo.new(0.2), {Size = UDim2.fromOffset(48, 48), Position = UDim2.new(0.5, -24, 0, 4)}):Play()
	end
	
	local function onLeave()
		TweenService:Create(button, TweenInfo.new(0.3), {BackgroundColor3 = palette.dark}):Play()
		TweenService:Create(border, TweenInfo.new(0.3), {Color = palette.accent, Transparency = 0.4}):Play()
		TweenService:Create(icon, TweenInfo.new(0.3), {Size = UDim2.fromOffset(44, 44), Position = UDim2.new(0.5, -22, 0, 6)}):Play()
	end
	
	local function onClick()
		-- Quick flash effect
		local flash = Instance.new("Frame")
		flash.Name = "ClickFlash"
		flash.Size = UDim2.fromScale(1, 1)
		flash.BackgroundColor3 = palette.accent
		flash.BackgroundTransparency = 0.6
		flash.BorderSizePixel = 0
		flash.ZIndex = button.ZIndex + 10
		flash.Parent = button
		
		local flashCorner = Instance.new("UICorner")
		flashCorner.CornerRadius = corner.CornerRadius
		flashCorner.Parent = flash
		
		TweenService:Create(flash, TweenInfo.new(0.12), {BackgroundTransparency = 1}):Play()
		game:GetService("Debris"):AddItem(flash, 0.15)
		
		-- Brief scale animation
		local w, h = button.Size.X.Offset, button.Size.Y.Offset
		TweenService:Create(button, TweenInfo.new(0.08), {Size = UDim2.fromOffset(math.max(1, w - 4), math.max(1, h - 4))}):Play()
		task.delay(0.08, function()
			if button and button.Parent then
				TweenService:Create(button, TweenInfo.new(0.08), {Size = UDim2.fromOffset(w, h)}):Play()
			end
		end)
	end
	
	button.MouseEnter:Connect(onHover)
	button.MouseLeave:Connect(onLeave)
	button.MouseButton1Down:Connect(onClick)
end

return ButtonStyler