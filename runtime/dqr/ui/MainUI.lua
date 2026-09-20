-- DQR modular runtime: ui/MainUI.lua
-- Thin Serenity-style interface for Auto Farm (display only for now) + Macro.

local Macro = Runtime.MacroController
if not Macro then
    warn("[DQR UI] Macro controller unavailable")
    return
end

local UIEnv = (type(getgenv) == "function" and getgenv()) or _G
local UI_KEY = "__SERENITY_DQR_UI_V1"

local previous = UIEnv[UI_KEY]
if previous and type(previous.Destroy) == "function" then
    pcall(previous.Destroy)
end

local UI = {
    Alive = true,
    Connections = {},
}

local function track(connection)
    UI.Connections[#UI.Connections + 1] = connection
    return connection
end

local function create(className, properties, parent)
    local object = Instance.new(className)
    for key, value in pairs(properties or {}) do
        object[key] = value
    end
    if parent then
        object.Parent = parent
    end
    return object
end

local function corner(parent, radius)
    return create("UICorner", {
        CornerRadius = UDim.new(0, radius or 8),
    }, parent)
end

local function stroke(parent, color, transparency, thickness)
    return create("UIStroke", {
        Color = color,
        Transparency = transparency or 0,
        Thickness = thickness or 1,
    }, parent)
end

local COLORS = {
    Background = Color3.fromRGB(11, 14, 20),
    Panel = Color3.fromRGB(17, 21, 29),
    Panel2 = Color3.fromRGB(21, 26, 36),
    Panel3 = Color3.fromRGB(27, 33, 44),
    Border = Color3.fromRGB(48, 58, 76),
    Accent = Color3.fromRGB(82, 214, 197),
    AccentSoft = Color3.fromRGB(42, 108, 103),
    Text = Color3.fromRGB(239, 243, 250),
    Muted = Color3.fromRGB(151, 161, 181),
    Danger = Color3.fromRGB(235, 92, 104),
    Warning = Color3.fromRGB(241, 190, 75),
    Success = Color3.fromRGB(104, 224, 155),
}

local parent
if type(gethui) == "function" then
    local ok, result = pcall(gethui)
    if ok then
        parent = result
    end
end

if not parent then
    local ok, coreGui = pcall(game.GetService, game, "CoreGui")
    if ok then
        parent = coreGui
    end
end

if not parent then
    parent = LP:WaitForChild("PlayerGui")
end

local gui = create("ScreenGui", {
    Name = "SerenityDQR",
    ResetOnSpawn = false,
    IgnoreGuiInset = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 500,
}, parent)

UI.Gui = gui

local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
local compact = viewport.X < 650
local sidebarWidth = compact and 110 or 150

local main = create("Frame", {
    Name = "Window",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.new(0.86, 0, 0.78, 0),
    BackgroundColor3 = COLORS.Background,
    BorderSizePixel = 0,
    ClipsDescendants = false,
}, gui)

create("UISizeConstraint", {
    MinSize = Vector2.new(340, 390),
    MaxSize = Vector2.new(820, 560),
}, main)

corner(main, 12)
stroke(main, COLORS.Border, 0.15, 1)

local topbar = create("Frame", {
    Name = "Topbar",
    Size = UDim2.new(1, 0, 0, 48),
    BackgroundColor3 = COLORS.Panel,
    BorderSizePixel = 0,
}, main)

corner(topbar, 12)

create("Frame", {
    Position = UDim2.new(0, 0, 1, -1),
    Size = UDim2.new(1, 0, 0, 1),
    BackgroundColor3 = COLORS.Border,
    BorderSizePixel = 0,
}, topbar)

local brand = create("TextLabel", {
    Position = UDim2.fromOffset(16, 0),
    Size = UDim2.new(1, -120, 1, 0),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamSemibold,
    Text = "SERENITY  •  DUNGEON QUEST",
    TextColor3 = COLORS.Text,
    TextSize = compact and 13 or 15,
    TextXAlignment = Enum.TextXAlignment.Left,
}, topbar)

local minimize = create("TextButton", {
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -48, 0.5, 0),
    Size = UDim2.fromOffset(30, 30),
    BackgroundColor3 = COLORS.Panel3,
    BorderSizePixel = 0,
    Font = Enum.Font.GothamBold,
    Text = "—",
    TextColor3 = COLORS.Muted,
    TextSize = 15,
}, topbar)
corner(minimize, 7)

local close = create("TextButton", {
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -12, 0.5, 0),
    Size = UDim2.fromOffset(30, 30),
    BackgroundColor3 = COLORS.Panel3,
    BorderSizePixel = 0,
    Font = Enum.Font.GothamBold,
    Text = "×",
    TextColor3 = COLORS.Muted,
    TextSize = 18,
}, topbar)
corner(close, 7)

local body = create("Frame", {
    Position = UDim2.fromOffset(0, 48),
    Size = UDim2.new(1, 0, 1, -48),
    BackgroundTransparency = 1,
}, main)

local sidebar = create("Frame", {
    Size = UDim2.new(0, sidebarWidth, 1, 0),
    BackgroundColor3 = COLORS.Panel,
    BorderSizePixel = 0,
}, body)

create("Frame", {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, 0, 0, 0),
    Size = UDim2.new(0, 1, 1, 0),
    BackgroundColor3 = COLORS.Border,
    BorderSizePixel = 0,
}, sidebar)

local navTitle = create("TextLabel", {
    Position = UDim2.fromOffset(14, 13),
    Size = UDim2.new(1, -28, 0, 20),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    Text = "AUTOMATION",
    TextColor3 = COLORS.Muted,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left,
}, sidebar)

local content = create("Frame", {
    Position = UDim2.fromOffset(sidebarWidth, 0),
    Size = UDim2.new(1, -sidebarWidth, 1, 0),
    BackgroundTransparency = 1,
    ClipsDescendants = true,
}, body)

local navButtons = {}
local pages = {}
local activePage = "Macro"

local function navButton(id, title, y)
    local button = create("TextButton", {
        Name = id,
        Position = UDim2.fromOffset(10, y),
        Size = UDim2.new(1, -20, 0, 40),
        BackgroundColor3 = COLORS.Panel,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = Enum.Font.GothamMedium,
        Text = title,
        TextColor3 = COLORS.Muted,
        TextSize = compact and 11 or 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, sidebar)
    corner(button, 8)

    local pad = create("UIPadding", {
        PaddingLeft = UDim.new(0, 12),
    }, button)

    navButtons[id] = button
    return button
end

navButton("AutoFarm", "Auto Farm", 44)
navButton("Macro", "Macro", 90)

local currentDungeon = create("TextLabel", {
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 14, 1, -16),
    Size = UDim2.new(1, -28, 0, 44),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    Text = "Current\n" .. tostring(DQR_WORLD and DQR_WORLD.Name or "Unknown"),
    TextColor3 = COLORS.Muted,
    TextSize = 10,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Bottom,
}, sidebar)

local function pageBase(id, title, subtitle)
    local page = create("ScrollingFrame", {
        Name = id,
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = COLORS.AccentSoft,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false,
    }, content)

    local layout = create("UIListLayout", {
        Padding = UDim.new(0, 10),
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, page)

    create("UIPadding", {
        PaddingTop = UDim.new(0, 16),
        PaddingBottom = UDim.new(0, 18),
        PaddingLeft = UDim.new(0, compact and 12 or 18),
        PaddingRight = UDim.new(0, compact and 12 or 18),
    }, page)

    local header = create("Frame", {
        Size = UDim2.new(1, 0, 0, 58),
        BackgroundTransparency = 1,
        LayoutOrder = 1,
    }, page)

    create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        Text = title,
        TextColor3 = COLORS.Text,
        TextSize = compact and 18 or 22,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, header)

    create("TextLabel", {
        Position = UDim2.fromOffset(0, 30),
        Size = UDim2.new(1, 0, 0, 22),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = subtitle or "",
        TextColor3 = COLORS.Muted,
        TextSize = compact and 10 or 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
    }, header)

    pages[id] = page
    return page
end

local function section(parentPage, title, height, order)
    local frame = create("Frame", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundColor3 = COLORS.Panel2,
        BorderSizePixel = 0,
        LayoutOrder = order,
    }, parentPage)

    corner(frame, 10)
    stroke(frame, COLORS.Border, 0.45, 1)

    create("TextLabel", {
        Position = UDim2.fromOffset(14, 10),
        Size = UDim2.new(1, -28, 0, 20),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamSemibold,
        Text = title,
        TextColor3 = COLORS.Text,
        TextSize = compact and 11 or 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, frame)

    return frame
end

local function actionButton(parentFrame, text, xScale, widthScale, y, accent)
    local button = create("TextButton", {
        Position = UDim2.new(xScale, 8, 0, y),
        Size = UDim2.new(widthScale, -12, 0, 34),
        BackgroundColor3 = accent and COLORS.AccentSoft or COLORS.Panel3,
        BorderSizePixel = 0,
        AutoButtonColor = true,
        Font = Enum.Font.GothamMedium,
        Text = text,
        TextColor3 = COLORS.Text,
        TextSize = compact and 10 or 12,
    }, parentFrame)
    corner(button, 7)
    return button
end

local function valueLabel(parentFrame, label, y)
    create("TextLabel", {
        Position = UDim2.fromOffset(14, y),
        Size = UDim2.new(0.48, -18, 0, 22),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = label,
        TextColor3 = COLORS.Muted,
        TextSize = compact and 10 or 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, parentFrame)

    local value = create("TextLabel", {
        Position = UDim2.new(0.48, 0, 0, y),
        Size = UDim2.new(0.52, -14, 0, 22),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium,
        Text = "—",
        TextColor3 = COLORS.Text,
        TextSize = compact and 10 or 11,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, parentFrame)

    return value
end

local autoPage = pageBase(
    "AutoFarm",
    "Auto Farm",
    "Dungeon farming controls will be connected after the macro system is accepted."
)

local autoSection = section(autoPage, "Supported Maps", 146, 2)

local function mapRow(name, y)
    local row = create("Frame", {
        Position = UDim2.fromOffset(14, y),
        Size = UDim2.new(1, -28, 0, 42),
        BackgroundColor3 = COLORS.Panel3,
        BorderSizePixel = 0,
    }, autoSection)
    corner(row, 7)

    create("TextLabel", {
        Position = UDim2.fromOffset(12, 0),
        Size = UDim2.new(1, -105, 1, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium,
        Text = name,
        TextColor3 = COLORS.Text,
        TextSize = compact and 10 or 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    create("TextLabel", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(82, 24),
        BackgroundColor3 = COLORS.Panel2,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamMedium,
        Text = "Not wired yet",
        TextColor3 = COLORS.Warning,
        TextSize = 9,
    }, row)
end

mapRow("Samurai Palace", 40)
mapRow("The Underworld", 88)

local noteSection = section(autoPage, "Status", 76, 3)
create("TextLabel", {
    Position = UDim2.fromOffset(14, 36),
    Size = UDim2.new(1, -28, 0, 28),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    Text = "No nonfunctional Auto Farm switch is exposed yet. The proven V1.4 engine remains unchanged.",
    TextColor3 = COLORS.Muted,
    TextSize = compact and 9 or 11,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
}, noteSection)

local macroPage = pageBase(
    "Macro",
    "Macro",
    "Record your route and actions, save named macros, replay once, or loop automatically."
)

local createSection = section(macroPage, "Create & Select", 158, 2)

local nameBox = create("TextBox", {
    Position = UDim2.fromOffset(14, 38),
    Size = UDim2.new(1, -132, 0, 34),
    BackgroundColor3 = COLORS.Panel3,
    BorderSizePixel = 0,
    ClearTextOnFocus = false,
    Font = Enum.Font.Gotham,
    PlaceholderText = "Macro name",
    PlaceholderColor3 = COLORS.Muted,
    Text = "",
    TextColor3 = COLORS.Text,
    TextSize = compact and 10 or 12,
    TextXAlignment = Enum.TextXAlignment.Left,
}, createSection)
corner(nameBox, 7)
create("UIPadding", {
    PaddingLeft = UDim.new(0, 10),
    PaddingRight = UDim.new(0, 10),
}, nameBox)

local createButton = create("TextButton", {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -14, 0, 38),
    Size = UDim2.fromOffset(104, 34),
    BackgroundColor3 = COLORS.AccentSoft,
    BorderSizePixel = 0,
    Font = Enum.Font.GothamMedium,
    Text = "Create Macro",
    TextColor3 = COLORS.Text,
    TextSize = compact and 9 or 11,
}, createSection)
corner(createButton, 7)

local selectLabel = create("TextLabel", {
    Position = UDim2.fromOffset(14, 82),
    Size = UDim2.new(1, -28, 0, 18),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    Text = "Selected Macro",
    TextColor3 = COLORS.Muted,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left,
}, createSection)

local dropdownButton = create("TextButton", {
    Position = UDim2.fromOffset(14, 104),
    Size = UDim2.new(1, -28, 0, 36),
    BackgroundColor3 = COLORS.Panel3,
    BorderSizePixel = 0,
    Font = Enum.Font.GothamMedium,
    Text = "No macros yet",
    TextColor3 = COLORS.Text,
    TextSize = compact and 10 or 12,
    TextXAlignment = Enum.TextXAlignment.Left,
}, createSection)
corner(dropdownButton, 7)
create("UIPadding", {
    PaddingLeft = UDim.new(0, 10),
    PaddingRight = UDim.new(0, 28),
}, dropdownButton)

local dropdownArrow = create("TextLabel", {
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -10, 0.5, 0),
    Size = UDim2.fromOffset(18, 20),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    Text = "⌄",
    TextColor3 = COLORS.Muted,
    TextSize = 14,
    ZIndex = 25,
}, dropdownButton)

local dropdown = create("ScrollingFrame", {
    Position = UDim2.fromOffset(14, 142),
    Size = UDim2.new(1, -28, 0, 0),
    BackgroundColor3 = COLORS.Panel3,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = COLORS.AccentSoft,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    Visible = false,
    ZIndex = 30,
    ClipsDescendants = true,
}, createSection)
corner(dropdown, 7)
stroke(dropdown, COLORS.Border, 0.1, 1)

local dropdownLayout = create("UIListLayout", {
    SortOrder = Enum.SortOrder.LayoutOrder,
}, dropdown)

local recordingSection = section(macroPage, "Recording & Playback", 124, 3)
local recordButton = actionButton(recordingSection, "Start Recording", 0, 0.5, 38, true)
local stopSaveButton = actionButton(recordingSection, "Stop & Save", 0.5, 0.5, 38, false)
local playButton = actionButton(recordingSection, "Play Once", 0, 0.5, 80, false)
local stopPlayButton = actionButton(recordingSection, "Stop Playback", 0.5, 0.5, 80, false)

local autoSectionMacro = section(macroPage, "Auto Macro", 90, 4)

local autoToggle = create("TextButton", {
    Position = UDim2.fromOffset(14, 40),
    Size = UDim2.new(1, -28, 0, 36),
    BackgroundColor3 = COLORS.Panel3,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Font = Enum.Font.GothamMedium,
    Text = "Auto Macro    OFF",
    TextColor3 = COLORS.Muted,
    TextSize = compact and 10 or 12,
}, autoSectionMacro)
corner(autoToggle, 7)

local manageSection = section(macroPage, "Manage", 82, 5)
local deleteButton = actionButton(manageSection, "Delete Selected", 0, 0.5, 38, false)
deleteButton.TextColor3 = COLORS.Danger
local refreshButton = actionButton(manageSection, "Refresh List", 0.5, 0.5, 38, false)

local statusSection = section(macroPage, "Macro Status", 190, 6)
local statusValue = valueLabel(statusSection, "Status", 38)
local selectedValue = valueLabel(statusSection, "Selected", 64)
local durationValue = valueLabel(statusSection, "Duration", 90)
local eventsValue = valueLabel(statusSection, "Recorded events", 116)
local countValue = valueLabel(statusSection, "Saved macros", 142)
local storageValue = valueLabel(statusSection, "Storage", 168)

local function setPage(id)
    activePage = id
    for pageId, page in pairs(pages) do
        page.Visible = pageId == id
    end

    for buttonId, button in pairs(navButtons) do
        local selected = buttonId == id
        button.BackgroundColor3 = selected and COLORS.Panel3 or COLORS.Panel
        button.TextColor3 = selected and COLORS.Text or COLORS.Muted
    end
end

local function rebuildDropdown()
    for _, child in ipairs(dropdown:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end

    local names = Macro.List()
    local status = Macro.Status()

    dropdownButton.Text = status.Selected or (#names > 0 and names[1]) or "No macros yet"

    local count = 0
    for index, name in ipairs(names) do
        count += 1
        local item = create("TextButton", {
            Size = UDim2.new(1, 0, 0, 32),
            BackgroundColor3 = index % 2 == 0 and COLORS.Panel2 or COLORS.Panel3,
            BorderSizePixel = 0,
            Font = Enum.Font.Gotham,
            Text = name,
            TextColor3 = COLORS.Text,
            TextSize = compact and 10 or 11,
            ZIndex = 31,
        }, dropdown)

        track(item.MouseButton1Click:Connect(function()
            Macro.Select(name)
            dropdownButton.Text = name
            dropdown.Visible = false
            dropdown.Size = UDim2.new(1, -28, 0, 0)
        end))
    end

    local height = math.min(160, math.max(34, count * 32))
    dropdown:SetAttribute("OpenHeight", height)
end

local function updateStatus(status)
    if not UI.Alive then
        return
    end

    status = status or Macro.Status()

    statusValue.Text = status.Error and (status.Status .. " • " .. tostring(status.Error)) or status.Status
    statusValue.TextColor3 =
        status.Recording and COLORS.Warning
        or status.Playing and COLORS.Accent
        or status.Error and COLORS.Danger
        or COLORS.Success

    selectedValue.Text = status.Selected or "None"
    durationValue.Text = string.format("%.1fs", tonumber(status.Duration) or 0)
    eventsValue.Text = tostring(status.Events or 0)
    countValue.Text = tostring(status.Count or 0)
    storageValue.Text =
        tostring(status.Storage)
        .. (status.InputPlayback and " • input replay ready" or " • movement replay only")

    autoToggle.Text = status.Auto and "Auto Macro    ON" or "Auto Macro    OFF"
    autoToggle.BackgroundColor3 = status.Auto and COLORS.AccentSoft or COLORS.Panel3
    autoToggle.TextColor3 = status.Auto and COLORS.Text or COLORS.Muted

    if status.Selected then
        dropdownButton.Text = status.Selected
    end
end

track(navButtons.AutoFarm.MouseButton1Click:Connect(function()
    setPage("AutoFarm")
end))

track(navButtons.Macro.MouseButton1Click:Connect(function()
    setPage("Macro")
end))

track(createButton.MouseButton1Click:Connect(function()
    local ok = Macro.Create(nameBox.Text)
    if ok then
        nameBox.Text = ""
        rebuildDropdown()
    end
    updateStatus()
end))

track(dropdownButton.MouseButton1Click:Connect(function()
    rebuildDropdown()
    local opening = not dropdown.Visible
    dropdown.Visible = opening
    dropdown.Size = opening
        and UDim2.new(1, -28, 0, dropdown:GetAttribute("OpenHeight") or 80)
        or UDim2.new(1, -28, 0, 0)
end))

track(recordButton.MouseButton1Click:Connect(function()
    Macro.StartRecording()
    updateStatus()
end))

track(stopSaveButton.MouseButton1Click:Connect(function()
    Macro.StopRecording(true)
    rebuildDropdown()
    updateStatus()
end))

track(playButton.MouseButton1Click:Connect(function()
    Macro.PlayOnce()
    updateStatus()
end))

track(stopPlayButton.MouseButton1Click:Connect(function()
    Macro.StopPlayback()
    updateStatus()
end))

track(autoToggle.MouseButton1Click:Connect(function()
    local status = Macro.Status()
    Macro.SetAuto(not status.Auto)
    updateStatus()
end))

track(deleteButton.MouseButton1Click:Connect(function()
    Macro.Delete()
    rebuildDropdown()
    updateStatus()
end))

track(refreshButton.MouseButton1Click:Connect(function()
    Macro.Refresh()
    rebuildDropdown()
    updateStatus()
end))

local minimized = false
local previousSize = main.Size

track(minimize.MouseButton1Click:Connect(function()
    minimized = not minimized
    body.Visible = not minimized
    minimize.Text = minimized and "+" or "—"

    if minimized then
        previousSize = main.Size
        main.Size = UDim2.new(previousSize.X.Scale, previousSize.X.Offset, 0, 48)
    else
        main.Size = previousSize
    end
end))

local dragging = false
local dragStart
local startPosition
local dragInput

track(topbar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    then
        dragging = true
        dragStart = input.Position
        startPosition = main.Position
        dragInput = input
    end
end))

track(topbar.InputEnded:Connect(function(input)
    if input == dragInput then
        dragging = false
        dragInput = nil
    end
end))

track(game:GetService("UserInputService").InputChanged:Connect(function(input)
    if not dragging or not dragStart or not startPosition then
        return
    end

    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
    then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end
end))

Macro.IsPointOverUI = function(pos)
    if not UI.Alive or not main.Visible then
        return false
    end

    local p = main.AbsolutePosition
    local s = main.AbsoluteSize

    return pos.X >= p.X
        and pos.X <= p.X + s.X
        and pos.Y >= p.Y
        and pos.Y <= p.Y + s.Y
end

local detachStatus = Macro.OnChanged(function(status)
    updateStatus(status)
end)

function UI.Destroy()
    if not UI.Alive then
        return
    end

    UI.Alive = false

    if detachStatus then
        pcall(detachStatus)
    end

    if Macro.IsPointOverUI then
        Macro.IsPointOverUI = nil
    end

    for _, connection in ipairs(UI.Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(UI.Connections)

    if gui then
        pcall(function()
            gui:Destroy()
        end)
    end

    if UIEnv[UI_KEY] == UI then
        UIEnv[UI_KEY] = nil
    end
end

track(close.MouseButton1Click:Connect(UI.Destroy))

task.spawn(function()
    while UI.Alive do
        updateStatus()
        task.wait(0.25)
    end
end)

rebuildDropdown()
updateStatus()
setPage("Macro")

UIEnv[UI_KEY] = UI
Runtime.DQRUI = UI
