-- FrameFactory.luau
-- Provides reusable frame creation functions for UI with RPG-themed button styling

local FrameFactory = {}

function FrameFactory.getOrCreateDeckFrame(mainUI, frameName, fallbackPosition)
    local existing = mainUI:FindFirstChild(frameName)
    if existing and existing:IsA("ScrollingFrame") then
        return existing
    end
    if existing then
        existing:Destroy()
    end
    local frame = Instance.new("ScrollingFrame")
    frame.Name = frameName
    frame.Size = fallbackPosition or UDim2.fromOffset(760, 320)
    frame.Position = fallbackPosition or UDim2.fromOffset(0, 0)
    frame.AnchorPoint = Vector2.new(0, 0)
    frame.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
    frame.BackgroundTransparency = 0.08
    frame.BorderSizePixel = 0
    frame.ScrollBarThickness = 8
    frame.CanvasSize = UDim2.new(0, 0, 0, 0)
    frame.Visible = false
    frame.ZIndex = 2
    frame.ClipsDescendants = true
    frame.Parent = mainUI
    return frame
end

function FrameFactory.getOrCreateBoolValue(name, defaultValue)
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local valueObj = ReplicatedStorage:FindFirstChild(name)
    if not (valueObj and valueObj:IsA("BoolValue")) then
        if valueObj then
            valueObj:Destroy()
        end
        valueObj = Instance.new("BoolValue")
        valueObj.Name = name
        valueObj.Value = defaultValue == true
        valueObj.Parent = ReplicatedStorage
    end
    return valueObj
end

function FrameFactory.createToggleBar(mainUI, buttonConfigs)
    local toggleBar = Instance.new("Frame")
    toggleBar.Name = "ToggleBar"
    toggleBar.Size = UDim2.fromOffset(340, 440)
    toggleBar.Position = UDim2.fromOffset(16, 16)
    toggleBar.BackgroundTransparency = 1
    toggleBar.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    toggleBar.BorderSizePixel = 0
    toggleBar.Parent = mainUI

    local gridLayout = Instance.new("UIGridLayout")
    gridLayout.CellSize = UDim2.fromOffset(100, 100)
    gridLayout.CellPadding = UDim2.fromOffset(12, 12)
    gridLayout.FillDirection = Enum.FillDirection.Vertical
    gridLayout.StartCorner = Enum.StartCorner.TopLeft
    gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
    gridLayout.Parent = toggleBar
    gridLayout.FillDirectionMaxCells = 3

    local ButtonStyler = require(script.Parent:WaitForChild("ButtonStyler"))

    -- Icon assets for each button type
    local iconAssets = {
        Inventory = "rbxassetid://6031763426", -- backpack
        Shop = "rbxassetid://6031280882",      -- money
        Profile = "rbxassetid://6031071050",   -- user
        Quests = "rbxassetid://6031071053",    -- star
        Settings = "rbxassetid://6031280882",  -- gear
        Teleport = "rbxassetid://6031094678",  -- arrow
    }

    for i, config in ipairs(buttonConfigs) do
        local btn = Instance.new("TextButton")
        btn.Name = config.name .. "Button"
        btn.Text = config.text
        btn.Size = UDim2.fromOffset(100, 100)
        btn.LayoutOrder = i
        btn.Parent = toggleBar
        btn.TextYAlignment = Enum.TextYAlignment.Bottom
        
        -- Get button type from name
        local buttonType = config.name or "Common"
        local iconImage = iconAssets[buttonType] or iconAssets.Settings
        
        -- Apply RPG-themed styling with epic gradient animations
        ButtonStyler.styleToggleButton(btn, config.text, nil, iconImage, buttonType)
        
        if config.onClick then
            btn.MouseButton1Click:Connect(config.onClick)
        end
    end
    return toggleBar
end

return FrameFactory