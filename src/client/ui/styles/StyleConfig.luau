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
    -- Floating combat damage text (see ui/DamageNumberView.luau). Tune fonts/colors/motion without touching battle logic.
    DamageNumbers = {
        Default = {
            Size = UDim2.fromOffset(96, 26),
            StartPosition = UDim2.fromScale(0.5, 0.42),
            EndPosition = UDim2.fromScale(0.5, 0.1),
            DurationSeconds = 0.42,
            Prefix = "-",
            Font = Enum.Font.GothamBlack,
            TextSize = 16,
            TextColor = Color3.fromRGB(255, 120, 120),
            TextStrokeColor = Color3.fromRGB(8, 8, 8),
            TextStrokeTransparency = 0,
            ZIndex = 122,
        },
        PlayerToNpc = {
            Size = UDim2.fromOffset(104, 28),
            StartPosition = UDim2.fromScale(0.5, 0.38),
            EndPosition = UDim2.fromScale(0.5, 0.08),
            -- PvE: parent to battle Root so numbers are not covered by DeckRow (sibling Z-order).
            RootStartOffsetY = -14,
            RootEndOffsetY = -78,
            DurationSeconds = 0.44,
            Prefix = "-",
            Font = Enum.Font.GothamBlack,
            TextSize = 18,
            TextColor = Color3.fromRGB(255, 210, 96),
            TextStrokeColor = Color3.fromRGB(12, 8, 4),
            TextStrokeTransparency = 0.05,
            ZIndex = 125,
        },
        NpcToPlayer = {
            Size = UDim2.fromOffset(96, 26),
            StartPosition = UDim2.fromScale(0.5, 0.42),
            EndPosition = UDim2.fromScale(0.5, 0.1),
            RootStartOffsetY = -12,
            RootEndOffsetY = -72,
            DurationSeconds = 0.42,
            Prefix = "-",
            Font = Enum.Font.GothamBlack,
            TextSize = 16,
            TextColor = Color3.fromRGB(255, 96, 96),
            TextStrokeColor = Color3.fromRGB(8, 8, 8),
            TextStrokeTransparency = 0,
            ZIndex = 122,
        },
        PvpHit = {
            Size = UDim2.fromOffset(86, 24),
            StartPosition = UDim2.fromScale(0.5, 0.42),
            EndPosition = UDim2.fromScale(0.5, 0.1),
            DurationSeconds = 0.42,
            Prefix = "-",
            Font = Enum.Font.GothamBlack,
            TextSize = 16,
            TextColor = Color3.fromRGB(255, 120, 120),
            TextStrokeColor = Color3.fromRGB(8, 8, 8),
            TextStrokeTransparency = 0,
            ZIndex = 122,
        },
    },
}