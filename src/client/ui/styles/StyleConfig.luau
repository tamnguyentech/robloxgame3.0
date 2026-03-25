-- StyleConfig.luau
-- Centralized style/theme configuration for UI

return {
    Colors = {
        Primary = Color3.fromRGB(52, 92, 158),
        Secondary = Color3.fromRGB(44, 126, 72),
        Accent = Color3.fromRGB(132, 96, 42),
        Background = Color3.fromRGB(24, 24, 24),
        Text = Color3.new(1, 1, 1),
    },
    Fonts = {
        Main = Enum.Font.SciFi,
        Title = Enum.Font.SourceSansBold,
        Stat = Enum.Font.Arcade,
    },
    Sizes = {
        ToggleButton = UDim2.fromOffset(108, 36),
        Modal = UDim2.fromOffset(760, 320),
        TouchTargetMin = 44,  -- Apple HIG minimum for mobile; use DeviceContext.getTouchTargetMin() at runtime
    },
}