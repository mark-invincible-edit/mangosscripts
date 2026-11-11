-- player tools ui v2 (LocalScript)
-- put this in StarterPlayer > StarterPlayerScripts. no other objects needed.
-- rightctrl (or the round "pt" button on the right edge) shows/hides the panel.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

---------------------------------------------------------------------
-- config (tweak these)
---------------------------------------------------------------------
local CONFIG = {
	FlySpeed = 80, -- studs/sec when flying at someone
	FlyStopDistance = 6, -- how close fly gets you
	OrbitRadius = 14, -- studs from the target
	OrbitSpeed = 1.6, -- radians/sec
	OrbitHeight = 2, -- studs above the target's root
	OrbitMaxSpeed = 140, -- cap while catching up to the orbit ring
	CameraDistance = 12, -- how far behind you the locked camera sits
	CameraHeight = 3,
	FlipArc = 9, -- how high the backflip goes over them (studs)
	FlipLandDistance = 4, -- how far behind them you land
	ToggleKey = Enum.KeyCode.RightControl,
}

local THEME = {
	Top = Color3.fromRGB(34, 31, 52),
	Bottom = Color3.fromRGB(10, 10, 16),
	Row = Color3.fromRGB(34, 34, 50),
	RowHover = Color3.fromRGB(46, 46, 68),
	Inset = Color3.fromRGB(13, 13, 21),
	Accent = Color3.fromRGB(128, 96, 255),
	AccentDark = Color3.fromRGB(78, 52, 190),
	Off = Color3.fromRGB(60, 60, 80),
	Text = Color3.fromRGB(240, 240, 250),
	SubText = Color3.fromRGB(150, 150, 178),
	Stroke = Color3.fromRGB(80, 74, 120),
	Good = Color3.fromRGB(80, 220, 140),
	Bad = Color3.fromRGB(240, 80, 90),
}

local FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BOUNCY = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

---------------------------------------------------------------------
-- state
---------------------------------------------------------------------
local selected = nil -- Player or nil
local actions = { fly = false, orbit = false, lock = false, spectate = false }
local orbitAngle = 0
local orbitNeedsInit = true
local spectating = false
local flip = { active = false }
local connections = {}

-- assigned further down, buttons in the ui call these
local startFlip, teleportBehind

local function track(conn)
	table.insert(connections, conn)
	return conn
end

---------------------------------------------------------------------
-- character helpers
---------------------------------------------------------------------
local function getRoot(plr)
	local char = plr and plr.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(plr)
	local char = (plr or player).Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function getAimPosition(plr)
	local char = plr and plr.Character
	local part = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
	return part and part.Position
end

local thumbCache = {}
local function getThumb(userId, callback)
	if thumbCache[userId] then
		callback(thumbCache[userId])
		return
	end
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		end)
		if ok then
			thumbCache[userId] = content
			callback(content)
		end
	end)
end

---------------------------------------------------------------------
-- ui helpers
---------------------------------------------------------------------
local function create(className, props, children)
	local inst = Instance.new(className)
	local parent
	for key, value in pairs(props or {}) do
		if key == "Parent" then
			parent = value
		else
			inst[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	inst.Parent = parent
	return inst
end

local function corner(radius)
	return create("UICorner", { CornerRadius = radius or UDim.new(0, 10) })
end

local function stroke(transparency, thickness)
	return create("UIStroke", {
		Color = THEME.Stroke,
		Thickness = thickness or 1,
		Transparency = transparency or 0.6,
	})
end

local function textLimit(maxSize)
	return create("UITextSizeConstraint", { MaxTextSize = maxSize, MinTextSize = 8 })
end

local function label(props, maxSize)
	props.BackgroundTransparency = 1
	props.TextScaled = true
	props.Font = props.Font or Enum.Font.GothamMedium
	props.TextColor3 = props.TextColor3 or THEME.Text
	local l = create("TextLabel", props)
	textLimit(maxSize).Parent = l
	return l
end

local function addPress(button)
	local scale = create("UIScale", { Parent = button })
	local tween
	local function to(value)
		if tween then
			tween:Cancel()
		end
		tween = TweenService:Create(scale, FAST, { Scale = value })
		tween:Play()
	end
	button.MouseButton1Down:Connect(function()
		to(0.96)
	end)
	button.MouseButton1Up:Connect(function()
		to(1)
	end)
	button.MouseLeave:Connect(function()
		to(1)
	end)
end

---------------------------------------------------------------------
-- build gui
---------------------------------------------------------------------
local old = playerGui:FindFirstChild("PlayerToolsGui")
if old then
	old:Destroy() -- re-running the script just replaces the old ui
end

local gui = create("ScreenGui", {
	Name = "PlayerToolsGui",
	ResetOnSpawn = false,
	DisplayOrder = 50,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

local main = create("Frame", {
	Name = "Main",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.18, 0.5),
	Size = UDim2.fromScale(0.26, 0.86),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
	Visible = false,
	Parent = gui,
}, {
	corner(UDim.new(0, 16)),
	create("UIStroke", { Color = THEME.Stroke, Thickness = 1.5, Transparency = 0.3 }),
	create("UIGradient", { Color = ColorSequence.new(THEME.Top, THEME.Bottom), Rotation = 120 }),
	create("UISizeConstraint", { MinSize = Vector2.new(260, 440), MaxSize = Vector2.new(360, 680) }),
})
local mainScale = create("UIScale", { Scale = 0, Parent = main })

-- header (drag handle) ------------------------------------------------
local header = create("Frame", {
	Name = "Header",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 0.07),
	Parent = main,
})

label({
	Text = "player tools",
	Font = Enum.Font.GothamBold,
	TextXAlignment = Enum.TextXAlignment.Left,
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 16, 0.5, 0),
	Size = UDim2.fromScale(0.45, 0.6),
	Parent = header,
}, 18)

-- activity chip: dot + "idle"/"active"
local chip = create("Frame", {
	Name = "Chip",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -46, 0.5, 0),
	Size = UDim2.fromOffset(64, 20),
	BackgroundColor3 = THEME.Row,
	BorderSizePixel = 0,
	Parent = header,
}, { corner(UDim.new(1, 0)), stroke(0.7) })

local chipDot = create("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 8, 0.5, 0),
	Size = UDim2.fromOffset(8, 8),
	BackgroundColor3 = THEME.Off,
	BorderSizePixel = 0,
	Parent = chip,
}, { corner(UDim.new(1, 0)) })

local chipLabel = label({
	Text = "idle",
	TextColor3 = THEME.SubText,
	Position = UDim2.new(0, 22, 0, 0),
	Size = UDim2.new(1, -26, 1, 0),
	Parent = chip,
}, 11)

local closeBtn = create("TextButton", {
	Name = "Close",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.fromOffset(26, 26),
	AutoButtonColor = false,
	BackgroundColor3 = THEME.Row,
	Text = "x",
	TextScaled = true,
	Font = Enum.Font.GothamBold,
	TextColor3 = THEME.SubText,
	Parent = header,
}, { corner(UDim.new(1, 0)), textLimit(14) })
addPress(closeBtn)

create("Frame", {
	Name = "Divider",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 1),
	Size = UDim2.new(1, -24, 0, 1),
	BackgroundColor3 = THEME.Stroke,
	BackgroundTransparency = 0.6,
	BorderSizePixel = 0,
	Parent = header,
})

-- players caption + count badge ----------------------------------------
local captionRow = create("Frame", {
	Name = "PlayersCaption",
	Position = UDim2.new(0, 12, 0.08, 0),
	Size = UDim2.new(1, -24, 0.04, 0),
	BackgroundTransparency = 1,
	Parent = main,
})

label({
	Text = "PLAYERS",
	Font = Enum.Font.GothamBold,
	TextColor3 = THEME.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.fromScale(0.5, 1),
	Parent = captionRow,
}, 11)

local countBadge = label({
	Text = "0",
	Font = Enum.Font.GothamBold,
	TextColor3 = THEME.Text,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.fromScale(1, 0.5),
	Size = UDim2.new(0, 32, 0.9, 0),
	BackgroundTransparency = 0,
	BackgroundColor3 = THEME.Accent,
	Parent = captionRow,
}, 11)
corner(UDim.new(1, 0)).Parent = countBadge

-- search box -----------------------------------------------------------
local searchBox = create("TextBox", {
	Name = "Search",
	Position = UDim2.new(0, 12, 0.125, 0),
	Size = UDim2.new(1, -24, 0.055, 0),
	BackgroundColor3 = THEME.Inset,
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	PlaceholderText = "search players...",
	PlaceholderColor3 = THEME.SubText,
	Text = "",
	TextColor3 = THEME.Text,
	Font = Enum.Font.GothamMedium,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = main,
}, {
	corner(UDim.new(0, 8)),
	stroke(0.7),
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
	}),
	textLimit(13),
})

-- player list -----------------------------------------------------------
local listBox = create("Frame", {
	Name = "ListBox",
	Position = UDim2.new(0, 12, 0.19, 0),
	Size = UDim2.new(1, -24, 0.24, 0),
	BackgroundColor3 = THEME.Inset,
	BackgroundTransparency = 0.2,
	BorderSizePixel = 0,
	Parent = main,
}, { corner(UDim.new(0, 12)), stroke(0.7) })

local listFrame = create("ScrollingFrame", {
	Name = "List",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = THEME.Accent,
	Parent = listBox,
}, {
	create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.Name }),
	create("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
	}),
})

local emptyLabel = label({
	Text = "nobody else is here",
	TextColor3 = THEME.SubText,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.8, 0.2),
	Parent = listBox,
}, 14)

-- target card -----------------------------------------------------------
local card = create("Frame", {
	Name = "TargetCard",
	Position = UDim2.new(0, 12, 0.44, 0),
	Size = UDim2.new(1, -24, 0.12, 0),
	BackgroundColor3 = THEME.Row,
	BorderSizePixel = 0,
	Parent = main,
}, { corner(UDim.new(0, 12)), stroke(0.6) })

local cardAvatar = create("ImageLabel", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 10, 0.5, 0),
	Size = UDim2.fromScale(1, 0.72),
	BackgroundColor3 = Color3.fromRGB(20, 20, 30),
	BorderSizePixel = 0,
	Image = "",
	Parent = card,
}, { corner(UDim.new(1, 0)), create("UIAspectRatioConstraint", { AspectRatio = 1 }) })

local cardName = label({
	Text = "no target selected",
	Font = Enum.Font.GothamBold,
	TextColor3 = THEME.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
	Position = UDim2.new(0, 74, 0.08, 0),
	Size = UDim2.new(1, -160, 0.34, 0),
	Parent = card,
}, 15)

local cardInfo = label({
	Text = "pick someone from the list",
	TextColor3 = THEME.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
	Position = UDim2.new(0, 74, 0.44, 0),
	Size = UDim2.new(1, -84, 0.24, 0),
	Parent = card,
}, 12)

local healthBar = create("Frame", {
	Name = "HealthBar",
	Position = UDim2.new(0, 74, 0.76, 0),
	Size = UDim2.new(1, -84, 0.12, 0),
	BackgroundColor3 = THEME.Inset,
	BorderSizePixel = 0,
	Parent = card,
}, { corner(UDim.new(1, 0)) })

local healthFill = create("Frame", {
	Name = "Fill",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = THEME.Good,
	BorderSizePixel = 0,
	Parent = healthBar,
}, { corner(UDim.new(1, 0)) })

local clearBtn = create("TextButton", {
	Name = "Unselect",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0.08, 0),
	Size = UDim2.new(0, 74, 0.34, 0),
	AutoButtonColor = false,
	BackgroundColor3 = THEME.Off,
	BackgroundTransparency = 0.6,
	Text = "unselect",
	TextScaled = true,
	TextTransparency = 0.6,
	Font = Enum.Font.GothamBold,
	TextColor3 = THEME.Text,
	Parent = card,
}, { corner(UDim.new(0, 8)), textLimit(11) })
addPress(clearBtn)

-- actions (scrolling): toggles + one-shot moves --------------------------
local actionsFrame = create("ScrollingFrame", {
	Name = "Actions",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Position = UDim2.new(0, 12, 0.57, 0),
	Size = UDim2.new(1, -24, 0.41, 0),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = THEME.Accent,
	Parent = main,
}, {
	create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	create("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 4) }),
})

local function caption(text, order)
	return label({
		Text = text,
		Font = Enum.Font.GothamBold,
		TextColor3 = THEME.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 16),
		Parent = actionsFrame,
	}, 11)
end

local function makeRow(name, order)
	return create("TextButton", {
		Name = name,
		LayoutOrder = order,
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = THEME.Row,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 46),
		Parent = actionsFrame,
	}, { corner(UDim.new(0, 10)) })
end

local function rowText(row, title, desc)
	local t = label({
		Text = title,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 14, 0.1, 0),
		Size = UDim2.new(1, -80, 0.42, 0),
		Parent = row,
	}, 14)
	local d = label({
		Text = desc,
		TextColor3 = THEME.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 14, 0.54, 0),
		Size = UDim2.new(1, -80, 0.3, 0),
		Parent = row,
	}, 11)
	return t, d
end

local function makeToggle(title, desc, order, onChanged)
	local row = makeRow(title, order)
	rowText(row, title, desc)

	local pill = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(44, 24),
		BackgroundColor3 = THEME.Off,
		BorderSizePixel = 0,
		Parent = row,
	}, { corner(UDim.new(1, 0)) })

	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = pill,
	}, { corner(UDim.new(1, 0)) })

	local on = false
	row.Activated:Connect(function()
		on = not on
		TweenService:Create(pill, FAST, { BackgroundColor3 = on and THEME.Accent or THEME.Off }):Play()
		TweenService:Create(knob, BOUNCY, {
			Position = on and UDim2.new(0, 23, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
		}):Play()
		onChanged(on)
	end)
	addPress(row)
end

local actionButtons = {} -- list of setEnabled functions

local function makeButton(title, desc, order, onClick)
	local row = makeRow(title, order)
	local t, d = rowText(row, title, desc)

	local chipGo = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(44, 24),
		BackgroundColor3 = THEME.Accent,
		Text = "go",
		TextSize = 13,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.new(1, 1, 1),
		Parent = row,
	}, { corner(UDim.new(1, 0)) })

	local enabled = false
	local function setEnabled(on)
		enabled = on
		TweenService:Create(row, FAST, { BackgroundTransparency = on and 0 or 0.5 }):Play()
		TweenService:Create(chipGo, FAST, {
			BackgroundTransparency = on and 0 or 0.6,
			TextTransparency = on and 0 or 0.5,
		}):Play()
		TweenService:Create(t, FAST, { TextTransparency = on and 0 or 0.5 }):Play()
		TweenService:Create(d, FAST, { TextTransparency = on and 0 or 0.6 }):Play()
	end

	row.Activated:Connect(function()
		if enabled then
			onClick()
		end
	end)
	addPress(row)
	setEnabled(false)
	table.insert(actionButtons, setEnabled)
end

local function refreshActionButtons()
	local usable = selected ~= nil and not flip.active
	for _, setEnabled in ipairs(actionButtons) do
		setEnabled(usable)
	end
end

caption("TOGGLES", 0)
makeToggle("fly to player", "fly straight at them", 1, function(on)
	actions.fly = on
end)
makeToggle("orbit player", "circle around them (beats fly)", 2, function(on)
	actions.orbit = on
	orbitNeedsInit = true
end)
makeToggle("lock camera", "aim your camera at them", 3, function(on)
	actions.lock = on
end)
makeToggle("spectate", "see through their eyes (beats lock)", 4, function(on)
	actions.spectate = on
end)

caption("MOVES", 10)
makeButton("backflip behind", "flip over them, land at their back", 11, function()
	startFlip()
end)
makeButton("teleport behind", "instant, no style points", 12, function()
	teleportBehind()
end)

-- launcher button (always visible) -----------------------------------------
local launcher = create("TextButton", {
	Name = "Launcher",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -14, 0.5, 0),
	Size = UDim2.fromOffset(44, 44),
	AutoButtonColor = false,
	BackgroundColor3 = Color3.new(1, 1, 1),
	Text = "pt",
	TextSize = 16,
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.new(1, 1, 1),
	Parent = gui,
}, {
	corner(UDim.new(1, 0)),
	create("UIGradient", { Color = ColorSequence.new(THEME.Accent, THEME.AccentDark), Rotation = 90 }),
	create("UIStroke", { Color = THEME.Stroke, Thickness = 1.5, Transparency = 0.3 }),
})
addPress(launcher)

---------------------------------------------------------------------
-- open / close / drag
---------------------------------------------------------------------
local isOpen = false
local panelTween

local function setOpen(open)
	if open == isOpen then
		return
	end
	isOpen = open
	if panelTween then
		panelTween:Cancel()
	end
	if open then
		main.Visible = true
		panelTween = TweenService:Create(mainScale, BOUNCY, { Scale = 1 })
		panelTween:Play()
	else
		local t = TweenService:Create(mainScale, CLOSE, { Scale = 0 })
		panelTween = t
		t.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and not isOpen then
				main.Visible = false
			end
		end)
		t:Play()
	end
end

closeBtn.Activated:Connect(function()
	setOpen(false)
end)
launcher.Activated:Connect(function()
	setOpen(not isOpen)
end)
track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.KeyCode == CONFIG.ToggleKey then
		setOpen(not isOpen)
	end
end))

local dragging = false
local dragStart, startPos
header.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = main.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)
track(UserInputService.InputChanged:Connect(function(input)
	if
		dragging
		and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch)
	then
		local delta = input.Position - dragStart
		main.Position = UDim2.new(
			startPos.X.Scale,
			startPos.X.Offset + delta.X,
			startPos.Y.Scale,
			startPos.Y.Offset + delta.Y
		)
	end
end))

---------------------------------------------------------------------
-- selection + live player list
---------------------------------------------------------------------
local rows = {} -- [Player] = { button, sub, search }
local rowCount = 0

local function refreshRowStyle(plr)
	local entry = rows[plr]
	if not entry then
		return
	end
	local isSel = selected == plr
	TweenService:Create(entry.button, FAST, { BackgroundColor3 = isSel and THEME.Accent or THEME.Row }):Play()
	TweenService:Create(entry.sub, FAST, {
		TextColor3 = isSel and Color3.fromRGB(225, 220, 255) or THEME.SubText,
	}):Play()
end

local function refreshStatus()
	local ratio = 0
	if selected then
		cardName.Text = selected.DisplayName
		cardName.TextColor3 = THEME.Text

		local mine, theirs = getRoot(player), getRoot(selected)
		local theirHum = getHumanoid(selected)
		local parts = {}
		if mine and theirs then
			table.insert(parts, math.floor((mine.Position - theirs.Position).Magnitude) .. " studs")
		end
		if theirHum then
			table.insert(parts, math.floor(theirHum.Health) .. "/" .. math.floor(theirHum.MaxHealth) .. " hp")
			if theirHum.MaxHealth > 0 then
				ratio = math.clamp(theirHum.Health / theirHum.MaxHealth, 0, 1)
			end
		end
		cardInfo.Text = #parts > 0 and table.concat(parts, "  |  ") or "no character"
	else
		cardName.Text = "no target selected"
		cardName.TextColor3 = THEME.SubText
		cardInfo.Text = "pick someone from the list"
	end

	TweenService:Create(healthFill, FAST, {
		Size = UDim2.fromScale(ratio, 1),
		BackgroundColor3 = THEME.Bad:Lerp(THEME.Good, ratio),
	}):Play()

	local active = selected ~= nil
		and (actions.fly or actions.orbit or actions.lock or actions.spectate or flip.active)
	chipDot.BackgroundColor3 = active and THEME.Good or THEME.Off
	chipLabel.Text = active and "active" or "idle"
	chipLabel.TextColor3 = active and THEME.Text or THEME.SubText
end

local function setSelected(plr)
	local previous = selected
	selected = plr
	orbitNeedsInit = true
	if previous then
		refreshRowStyle(previous)
	end
	if plr then
		refreshRowStyle(plr)
		getThumb(plr.UserId, function(img)
			if selected == plr then
				cardAvatar.Image = img
			end
		end)
	else
		cardAvatar.Image = ""
	end
	clearBtn.BackgroundTransparency = plr and 0 or 0.6
	clearBtn.TextTransparency = plr and 0 or 0.6
	refreshActionButtons()
	refreshStatus()
end

clearBtn.Activated:Connect(function()
	setSelected(nil)
end)

local function applyFilter()
	local query = string.lower(searchBox.Text)
	local visible = 0
	for _, entry in pairs(rows) do
		local show = query == "" or string.find(entry.search, query, 1, true) ~= nil
		entry.button.Visible = show
		if show then
			visible += 1
		end
	end
	countBadge.Text = tostring(rowCount)
	emptyLabel.Text = rowCount == 0 and "nobody else is here" or "no matches"
	emptyLabel.Visible = visible == 0
end

track(searchBox:GetPropertyChangedSignal("Text"):Connect(applyFilter))

local function addRow(plr)
	if plr == player or rows[plr] then
		return
	end

	local button = create("TextButton", {
		Name = string.lower(plr.DisplayName) .. plr.UserId, -- list sorts by name
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = THEME.Row,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 46),
		Parent = listFrame,
	}, { corner(UDim.new(0, 10)) })

	local avatar = create("ImageLabel", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.fromScale(1, 0.72),
		BackgroundColor3 = Color3.fromRGB(20, 20, 30),
		BorderSizePixel = 0,
		Image = "",
		Parent = button,
	}, {
		corner(UDim.new(1, 0)),
		create("UIAspectRatioConstraint", { AspectRatio = 1 }),
	})

	label({
		Text = plr.DisplayName,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 54, 0.1, 0),
		Size = UDim2.new(1, -62, 0.45, 0),
		Parent = button,
	}, 14)

	local sub = label({
		Text = "@" .. plr.Name,
		TextColor3 = THEME.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 54, 0.57, 0),
		Size = UDim2.new(1, -62, 0.31, 0),
		Parent = button,
	}, 12)

	getThumb(plr.UserId, function(img)
		if avatar.Parent then
			avatar.Image = img
		end
	end)

	button.Activated:Connect(function()
		if selected == plr then
			setSelected(nil) -- click again to unselect
		else
			setSelected(plr)
		end
	end)
	button.MouseEnter:Connect(function()
		if selected ~= plr then
			TweenService:Create(button, FAST, { BackgroundColor3 = THEME.RowHover }):Play()
		end
	end)
	button.MouseLeave:Connect(function()
		refreshRowStyle(plr)
	end)
	addPress(button)

	rows[plr] = {
		button = button,
		sub = sub,
		search = string.lower(plr.DisplayName .. " " .. plr.Name),
	}
	rowCount += 1
	applyFilter()
end

local function removeRow(plr)
	local entry = rows[plr]
	if not entry then
		return
	end
	entry.button:Destroy()
	rows[plr] = nil
	rowCount -= 1
	applyFilter()
	if selected == plr then
		setSelected(nil) -- target left the game
	end
end

for _, plr in ipairs(Players:GetPlayers()) do
	addRow(plr)
end
track(Players.PlayerAdded:Connect(addRow))
track(Players.PlayerRemoving:Connect(removeRow))
applyFilter()
setSelected(nil)

---------------------------------------------------------------------
-- movement (fly + orbit) - physics based, created in code
---------------------------------------------------------------------
local mover = { root = nil, att = nil, lv = nil, align = nil, active = false }

local function destroyMovers()
	for _, key in ipairs({ "lv", "align", "att" }) do
		if mover[key] then
			mover[key]:Destroy()
			mover[key] = nil
		end
	end
	mover.root = nil
	mover.active = false
end

local function ensureMovers(root)
	if mover.root == root and mover.att and mover.att.Parent == root then
		return
	end
	destroyMovers() -- new character after respawn, rebuild
	mover.root = root
	mover.att = create("Attachment", { Name = "PTAttachment", Parent = root })
	mover.lv = create("LinearVelocity", {
		Name = "PTVelocity",
		Attachment0 = mover.att,
		VelocityConstraintMode = Enum.VelocityConstraintMode.Vector,
		RelativeTo = Enum.ActuatorRelativeTo.World,
		MaxForce = math.huge,
		VectorVelocity = Vector3.zero,
		Enabled = false,
		Parent = root,
	})
	mover.align = create("AlignOrientation", {
		Name = "PTAlign",
		Attachment0 = mover.att,
		Mode = Enum.OrientationAlignmentMode.OneAttachment,
		RigidityEnabled = false,
		MaxTorque = math.huge,
		Responsiveness = 30,
		Enabled = false,
		Parent = root,
	})
end

local function stopMovement()
	if not mover.active then
		return
	end
	mover.active = false
	if mover.lv then
		mover.lv.VectorVelocity = Vector3.zero
		mover.lv.Enabled = false
	end
	if mover.align then
		mover.align.Enabled = false
	end
	local hum = getHumanoid()
	if hum then
		hum.PlatformStand = false
	end
end

---------------------------------------------------------------------
-- backflip + teleport (scripted arc over the target)
---------------------------------------------------------------------
-- spot behind the target, on their facing axis
local function behindPosition(targetRoot)
	local look = targetRoot.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(0, 0, -1)
	end
	return targetRoot.Position - flat.Unit * CONFIG.FlipLandDistance
end

-- rotation-only cframe: upright, facing targetPos from pos
local function facingRotation(pos, targetPos, fallbackLook)
	local dir = Vector3.new(targetPos.X - pos.X, 0, targetPos.Z - pos.Z)
	if dir.Magnitude < 0.5 then
		dir = Vector3.new(fallbackLook.X, 0, fallbackLook.Z)
		if dir.Magnitude < 0.1 then
			dir = Vector3.new(0, 0, -1)
		end
	end
	return CFrame.lookAt(Vector3.zero, dir.Unit)
end

local function finishFlip(landing)
	flip.active = false
	local hum = getHumanoid()
	local myRoot = getRoot(player)
	if landing and myRoot then
		myRoot.AssemblyLinearVelocity = Vector3.zero
		myRoot.AssemblyAngularVelocity = Vector3.zero
		myRoot.CFrame = CFrame.new(landing.pos) * landing.rot
	end
	if hum then
		hum.PlatformStand = false
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	orbitNeedsInit = true
	refreshActionButtons()
end

startFlip = function()
	if flip.active then
		return
	end
	local targetRoot = selected and getRoot(selected)
	local myRoot = getRoot(player)
	local hum = getHumanoid()
	if not (targetRoot and myRoot and hum and hum.Health > 0) then
		return
	end

	stopMovement() -- hand control over to the flip
	local endPos = behindPosition(targetRoot)

	flip.active = true
	flip.t = 0
	flip.startPos = myRoot.Position
	flip.startRot = facingRotation(myRoot.Position, targetRoot.Position, myRoot.CFrame.LookVector)
	flip.duration = math.clamp(0.6 + (endPos - flip.startPos).Magnitude / 150, 0.6, 1.3)

	hum.PlatformStand = true
	refreshActionButtons()
end

local function updateFlip(dt, myRoot, targetRoot)
	flip.t += dt / flip.duration
	local t = math.min(flip.t, 1)
	local eased = t * t * (3 - 2 * t)

	-- quadratic bezier: start -> (high point above target) -> behind target
	local endPos = behindPosition(targetRoot)
	local ctrl = targetRoot.Position + Vector3.new(0, CONFIG.FlipArc * 2, 0)
	local pos = flip.startPos * ((1 - eased) ^ 2) + ctrl * (2 * (1 - eased) * eased) + endPos * (eased ^ 2)

	local endRot = facingRotation(endPos, targetRoot.Position, myRoot.CFrame.LookVector)
	local rot = flip.startRot:Lerp(endRot, eased)

	-- positive pitch around local X = backflip direction
	myRoot.CFrame = CFrame.new(pos) * rot * CFrame.Angles(math.pi * 2 * t, 0, 0)
	myRoot.AssemblyLinearVelocity = Vector3.zero
	myRoot.AssemblyAngularVelocity = Vector3.zero

	if flip.t >= 1 then
		finishFlip({ pos = endPos, rot = endRot })
	end
end

teleportBehind = function()
	if flip.active then
		return
	end
	local targetRoot = selected and getRoot(selected)
	local myRoot = getRoot(player)
	if not (targetRoot and myRoot) then
		return
	end
	local pos = behindPosition(targetRoot)
	myRoot.CFrame = CFrame.new(pos) * facingRotation(pos, targetRoot.Position, myRoot.CFrame.LookVector)
	myRoot.AssemblyLinearVelocity = Vector3.zero
end

---------------------------------------------------------------------
-- main loop
---------------------------------------------------------------------
local statusTimer = 0

track(RunService.Heartbeat:Connect(function(dt)
	statusTimer += dt
	if statusTimer >= 0.25 then
		statusTimer = 0
		refreshStatus()
	end

	local camera = workspace.CurrentCamera
	local targetRoot = selected and getRoot(selected)
	local myRoot = getRoot(player)
	local hum = getHumanoid()

	-- spectate: point the camera subject at their humanoid, restore after
	if actions.spectate and selected and camera then
		local theirHum = getHumanoid(selected)
		if theirHum and camera.CameraSubject ~= theirHum then
			camera.CameraSubject = theirHum
		end
		spectating = true
	elseif spectating then
		spectating = false
		if camera and hum then
			camera.CameraSubject = hum
		end
	end

	-- backflip owns the character while it runs
	if flip.active then
		if targetRoot and myRoot and hum and hum.Health > 0 then
			updateFlip(dt, myRoot, targetRoot)
		else
			finishFlip(nil) -- target or you vanished mid-flip
		end
		return
	end

	local wantsMove = actions.fly or actions.orbit
	if not (wantsMove and targetRoot and myRoot and hum and hum.Health > 0) then
		stopMovement()
		return
	end

	ensureMovers(myRoot)
	if not mover.active then
		mover.active = true
		mover.lv.Enabled = true
		mover.align.Enabled = true
	end
	hum.PlatformStand = true

	local myPos, targetPos = myRoot.Position, targetRoot.Position
	local velocity

	if actions.orbit then
		-- orbit wins over fly: it also flies you to the ring first
		if orbitNeedsInit then
			orbitAngle = math.atan2(myPos.Z - targetPos.Z, myPos.X - targetPos.X)
			orbitNeedsInit = false
		end
		orbitAngle += CONFIG.OrbitSpeed * dt
		local ring = Vector3.new(math.cos(orbitAngle), 0, math.sin(orbitAngle)) * CONFIG.OrbitRadius
		local goal = targetPos + ring + Vector3.new(0, CONFIG.OrbitHeight, 0)
		velocity = (goal - myPos) * 12
		if velocity.Magnitude > CONFIG.OrbitMaxSpeed then
			velocity = velocity.Unit * CONFIG.OrbitMaxSpeed
		end
	else
		local offset = targetPos - myPos
		local dist = offset.Magnitude
		if dist > CONFIG.FlyStopDistance then
			velocity = offset.Unit * math.min(CONFIG.FlySpeed, (dist - CONFIG.FlyStopDistance) * 6)
		else
			velocity = Vector3.zero
		end
	end

	mover.lv.VectorVelocity = velocity

	local flatTarget = Vector3.new(targetPos.X, myPos.Y, targetPos.Z)
	if (flatTarget - myPos).Magnitude > 0.5 then
		mover.align.CFrame = CFrame.lookAt(myPos, flatTarget)
	end
end))

---------------------------------------------------------------------
-- camera lock (runs right after the default camera script)
---------------------------------------------------------------------
local RENDER_NAME = "PlayerToolsCameraLock"
pcall(function()
	RunService:UnbindFromRenderStep(RENDER_NAME)
end)

RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, function()
	if not actions.lock or actions.spectate or not selected then
		return
	end
	local camera = workspace.CurrentCamera
	local aim = getAimPosition(selected)
	if not camera or not aim then
		return
	end

	local myRoot = getRoot(player)
	if myRoot then
		local focus = myRoot.Position + Vector3.new(0, 2, 0)
		local toTarget = aim - focus
		if toTarget.Magnitude < 1 then
			return
		end
		local camPos = focus - toTarget.Unit * CONFIG.CameraDistance + Vector3.new(0, CONFIG.CameraHeight, 0)
		camera.CFrame = CFrame.lookAt(camPos, aim)
	else
		camera.CFrame = CFrame.lookAt(camera.CFrame.Position, aim)
	end
end)

---------------------------------------------------------------------
-- cleanup + go
---------------------------------------------------------------------
gui.Destroying:Connect(function()
	pcall(function()
		RunService:UnbindFromRenderStep(RENDER_NAME)
	end)
	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	if flip.active then
		finishFlip(nil)
	end
	if spectating then
		local camera = workspace.CurrentCamera
		local hum = getHumanoid()
		if camera and hum then
			camera.CameraSubject = hum
		end
	end
	stopMovement()
	destroyMovers()
end)

setOpen(true)
