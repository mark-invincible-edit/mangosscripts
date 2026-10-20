--[[
	Player Spectator Window  (LocalScript)
	- Works wherever it is run: StarterGui, StarterPlayerScripts, ReplicatedFirst,
	  Backpack, or any executor. It builds everything itself and parents to PlayerGui.
	- Windows-style window: drag title bar to move, drag any corner/edge to resize,
	  minimize / maximize / close buttons, double-click title bar to maximize.
	- Live-updating player list (search box included). Click a player to select,
	  then press Spectate (or double-click the player). Press Unspectate to go back.
	- Re-running the script replaces the old window cleanly.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
	task.wait()
	LocalPlayer = Players.LocalPlayer
end
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

---------------------------------------------------------------------
-- Config
---------------------------------------------------------------------
local GUI_NAME = "SpectatorWindow"
local TITLE = "Player Spectator"
local TITLE_H, TOOLBAR_H, SEARCH_H, STATUS_H, ROW_H = 32, 42, 32, 24, 46
local MIN_W, MIN_H = 320, 260
local DEFAULT_W, DEFAULT_H = 400, 440
local FONT = Enum.Font.SourceSans

local C = {
	window = Color3.fromRGB(32, 32, 32),
	title = Color3.fromRGB(38, 38, 38),
	bar = Color3.fromRGB(45, 45, 45),
	list = Color3.fromRGB(28, 28, 28),
	border = Color3.fromRGB(75, 75, 75),
	text = Color3.fromRGB(255, 255, 255),
	textDim = Color3.fromRGB(150, 150, 150),
	accent = Color3.fromRGB(0, 120, 215),
	select = Color3.fromRGB(0, 95, 184),
	hover = Color3.fromRGB(58, 58, 58),
	btn = Color3.fromRGB(58, 58, 58),
	btnHover = Color3.fromRGB(75, 75, 75),
	btnDisabled = Color3.fromRGB(42, 42, 42),
	btnStroke = Color3.fromRGB(95, 95, 95),
	closeHover = Color3.fromRGB(232, 17, 35),
	capHover = Color3.fromRGB(70, 70, 70),
	green = Color3.fromRGB(108, 203, 95),
	avatarBg = Color3.fromRGB(64, 64, 64),
}

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local conns = {}
local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(conns, c)
	return c
end

local function isPointerStart(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

-- Replace any previous copy of this window
local old = PlayerGui:FindFirstChild(GUI_NAME)
if old then
	old:Destroy()
end

---------------------------------------------------------------------
-- Window
---------------------------------------------------------------------
local gui = new("ScreenGui", {
	Name = GUI_NAME,
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 1000,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, PlayerGui)

local function screenSize()
	local s = gui.AbsoluteSize
	if s.X <= 0 or s.Y <= 0 then
		local cam = workspace.CurrentCamera
		s = cam and cam.ViewportSize or Vector2.new(1280, 720)
	end
	return s
end

local scr = screenSize()
local startW = math.min(DEFAULT_W, math.max(MIN_W, scr.X - 40))
local startH = math.min(DEFAULT_H, math.max(MIN_H, scr.Y - 80))

local window = new("Frame", {
	Name = "Window",
	BackgroundColor3 = C.window,
	BorderSizePixel = 0,
	Active = true,
	Size = UDim2.fromOffset(startW, startH),
	Position = UDim2.fromOffset(math.floor((scr.X - startW) / 2), math.floor((scr.Y - startH) / 2)),
}, gui)
new("UIStroke", { Color = C.border, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, window)

-- Title bar ----------------------------------------------------------
local titleBar = new("Frame", {
	Name = "TitleBar",
	BackgroundColor3 = C.title,
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, TITLE_H),
}, window)

local dragArea = new("Frame", {
	Name = "DragArea",
	BackgroundTransparency = 1,
	Size = UDim2.new(1, -138, 1, 0),
}, titleBar)

local appIcon = new("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(10, 8),
	Size = UDim2.fromOffset(16, 16),
}, dragArea)
for i = 0, 3 do
	new("Frame", {
		BackgroundColor3 = C.accent,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset((i % 2) * 8, math.floor(i / 2) * 8),
		Size = UDim2.fromOffset(7, 7),
	}, appIcon)
end

new("TextLabel", {
	Name = "Title",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(34, 0),
	Size = UDim2.new(1, -40, 1, 0),
	Font = FONT,
	Text = TITLE,
	TextSize = 15,
	TextColor3 = C.text,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
}, dragArea)

local caption = new("Frame", {
	Name = "Caption",
	BackgroundTransparency = 1,
	Position = UDim2.new(1, -138, 0, 0),
	Size = UDim2.fromOffset(138, TITLE_H),
}, titleBar)

local function captionButton(name, index, hoverColor)
	local b = new("TextButton", {
		Name = name,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = hoverColor,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset((index - 1) * 46, 0),
		Size = UDim2.fromOffset(46, TITLE_H),
	}, caption)
	b.MouseEnter:Connect(function()
		b.BackgroundTransparency = 0
	end)
	b.MouseLeave:Connect(function()
		b.BackgroundTransparency = 1
	end)
	return b
end

local minBtn = captionButton("Minimize", 1, C.capHover)
local maxBtn = captionButton("Maximize", 2, C.capHover)
local closeBtn = captionButton("Close", 3, C.closeHover)

-- caption icons (drawn with frames so they render on any font)
new("Frame", {
	BackgroundColor3 = C.text, BorderSizePixel = 0,
	Position = UDim2.new(0.5, -5, 0.5, 0), Size = UDim2.fromOffset(10, 1),
}, minBtn)
local maxIcon = new("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0.5, -5, 0.5, -5), Size = UDim2.fromOffset(9, 9),
}, maxBtn)
new("UIStroke", { Color = C.text, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, maxIcon)
for _, rot in ipairs({ 45, -45 }) do
	new("Frame", {
		BackgroundColor3 = C.text, BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(15, 1), Rotation = rot,
	}, closeBtn)
end

-- Content ------------------------------------------------------------
local content = new("Frame", {
	Name = "Content",
	BackgroundTransparency = 1,
	ClipsDescendants = true,
	Position = UDim2.fromOffset(0, TITLE_H),
	Size = UDim2.new(1, 0, 1, -TITLE_H),
}, window)

local function makeButton(text, pos, size, parent, onClick)
	local enabled, hover = true, false
	local btn = new("TextButton", {
		Text = text,
		Font = FONT,
		TextSize = 16,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Position = pos,
		Size = size,
	}, parent)
	new("UIStroke", { Color = C.btnStroke, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, btn)
	local function paint()
		if not enabled then
			btn.BackgroundColor3 = C.btnDisabled
			btn.TextColor3 = C.textDim
		else
			btn.BackgroundColor3 = hover and C.btnHover or C.btn
			btn.TextColor3 = C.text
		end
	end
	btn.MouseEnter:Connect(function() hover = true paint() end)
	btn.MouseLeave:Connect(function() hover = false paint() end)
	btn.MouseButton1Click:Connect(function()
		if enabled then onClick() end
	end)
	paint()
	return { Instance = btn, SetEnabled = function(v) enabled = v paint() end }
end

-- forward declarations (logic defined below)
local rows, selected, spectating, notice, prevCamType, needsReturn = {}, nil, nil, nil, nil, false
local updateUI, refreshRow, startSpectating, stopSpectating

local toolbar = new("Frame", {
	Name = "Toolbar", BackgroundColor3 = C.bar, BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, TOOLBAR_H),
}, content)

local spectateBtn = makeButton("Spectate", UDim2.fromOffset(8, 6), UDim2.fromOffset(100, 30), toolbar, function()
	if selected then startSpectating(selected) end
end)
local unspectateBtn = makeButton("Unspectate", UDim2.fromOffset(116, 6), UDim2.fromOffset(110, 30), toolbar, function()
	notice = nil
	stopSpectating()
	updateUI()
end)

local searchRow = new("Frame", {
	Name = "SearchRow", BackgroundColor3 = C.window, BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, TOOLBAR_H), Size = UDim2.new(1, 0, 0, SEARCH_H),
}, content)

local searchBox = new("TextBox", {
	Name = "Search",
	BackgroundColor3 = C.bar,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(8, 4),
	Size = UDim2.new(1, -16, 1, -8),
	Font = FONT,
	TextSize = 15,
	Text = "",
	PlaceholderText = "Search players",
	PlaceholderColor3 = C.textDim,
	TextColor3 = C.text,
	TextXAlignment = Enum.TextXAlignment.Left,
	ClearTextOnFocus = false,
}, searchRow)
new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, searchBox)
local searchStroke = new("UIStroke", {
	Color = C.btnStroke, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, searchBox)
searchBox.Focused:Connect(function() searchStroke.Color = C.accent end)
searchBox.FocusLost:Connect(function() searchStroke.Color = C.btnStroke end)

local LIST_TOP = TOOLBAR_H + SEARCH_H
local list = new("ScrollingFrame", {
	Name = "PlayerList",
	BackgroundColor3 = C.list,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, LIST_TOP),
	Size = UDim2.new(1, 0, 1, -(LIST_TOP + STATUS_H)),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 8,
	ScrollBarImageColor3 = Color3.fromRGB(120, 120, 120),
}, content)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, list)

local statusBar = new("Frame", {
	Name = "StatusBar", BackgroundColor3 = C.bar, BorderSizePixel = 0,
	Position = UDim2.new(0, 0, 1, -STATUS_H), Size = UDim2.new(1, 0, 0, STATUS_H),
}, content)
local countLabel = new("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(100, STATUS_H),
	Font = FONT, TextSize = 14, TextColor3 = C.textDim, TextXAlignment = Enum.TextXAlignment.Left, Text = "",
}, statusBar)
local statusLabel = new("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(112, 0), Size = UDim2.new(1, -120, 1, 0),
	Font = FONT, TextSize = 14, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Right,
	TextTruncate = Enum.TextTruncate.AtEnd, Text = "",
}, statusBar)

---------------------------------------------------------------------
-- Maximize / minimize / handles
---------------------------------------------------------------------
local maximized, minimized = false, false
local restorePos, restoreSize, minRestoreSize
local handles = {}
local setMaximized, setMinimized

local function updateHandles()
	for _, h in ipairs(handles) do
		h.Visible = not maximized and not minimized
	end
end

setMaximized = function(v)
	if minimized then setMinimized(false) end
	if v == maximized then return end
	maximized = v
	if v then
		restorePos, restoreSize = window.Position, window.Size
		window.Position = UDim2.fromOffset(0, 0)
		window.Size = UDim2.fromScale(1, 1)
	else
		window.Position, window.Size = restorePos, restoreSize
	end
	updateHandles()
end

setMinimized = function(v)
	if maximized then setMaximized(false) end
	if v == minimized then return end
	minimized = v
	if v then
		minRestoreSize = window.Size
		content.Visible = false
		window.Size = UDim2.fromOffset(window.AbsoluteSize.X, TITLE_H)
	else
		content.Visible = true
		window.Size = minRestoreSize
	end
	updateHandles()
end

minBtn.MouseButton1Click:Connect(function() setMinimized(not minimized) end)
maxBtn.MouseButton1Click:Connect(function() setMaximized(not maximized) end)
closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)

-- Resize handles (4 corners + 4 edges) --------------------------------
local resizing
local OUT, INN, CS = 4, 12, 16

local function makeHandle(name, dx, dy, pos, size)
	local h = new("Frame", {
		Name = name, BackgroundTransparency = 1, Active = true, ZIndex = 50,
		Position = pos, Size = size,
	}, window)
	h.InputBegan:Connect(function(input)
		if not isPointerStart(input) or maximized or minimized then return end
		resizing = {
			dx = dx, dy = dy,
			mouse = Vector2.new(input.Position.X, input.Position.Y),
			pos = window.AbsolutePosition,
			size = window.AbsoluteSize,
		}
	end)
	table.insert(handles, h)
end

-- corners
makeHandle("TopLeft", -1, -1, UDim2.new(0, -OUT, 0, -OUT), UDim2.fromOffset(CS, CS))
makeHandle("TopRight", 1, -1, UDim2.new(1, -INN, 0, -OUT), UDim2.fromOffset(CS, CS))
makeHandle("BottomLeft", -1, 1, UDim2.new(0, -OUT, 1, -INN), UDim2.fromOffset(CS, CS))
makeHandle("BottomRight", 1, 1, UDim2.new(1, -INN, 1, -INN), UDim2.fromOffset(CS, CS))
-- edges
makeHandle("Top", 0, -1, UDim2.new(0, INN, 0, -OUT), UDim2.new(1, -2 * INN, 0, OUT + INN - 8))
makeHandle("Bottom", 0, 1, UDim2.new(0, INN, 1, -INN + 8), UDim2.new(1, -2 * INN, 0, OUT + INN - 8))
makeHandle("Left", -1, 0, UDim2.new(0, -OUT, 0, INN), UDim2.new(0, OUT + INN - 8, 1, -2 * INN))
makeHandle("Right", 1, 0, UDim2.new(1, -INN + 8, 0, INN), UDim2.new(0, OUT + INN - 8, 1, -2 * INN))

local function doResize(pos)
	local r = resizing
	local delta = pos - r.mouse
	local s = screenSize()
	local x, y, w, h = r.pos.X, r.pos.Y, r.size.X, r.size.Y

	if r.dx == 1 then
		w = math.max(MIN_W, math.min(r.size.X + delta.X, s.X - r.pos.X))
	elseif r.dx == -1 then
		w = math.max(MIN_W, math.min(r.size.X - delta.X, r.pos.X + r.size.X))
		x = r.pos.X + (r.size.X - w)
	end
	if r.dy == 1 then
		h = math.max(MIN_H, math.min(r.size.Y + delta.Y, s.Y - r.pos.Y))
	elseif r.dy == -1 then
		h = math.max(MIN_H, math.min(r.size.Y - delta.Y, r.pos.Y + r.size.Y))
		y = r.pos.Y + (r.size.Y - h)
	end

	window.Position = UDim2.fromOffset(x, y)
	window.Size = UDim2.fromOffset(w, h)
end

-- Dragging the window by its title bar ---------------------------------
local dragging, dragStart, dragOrigin = false, Vector2.zero, Vector2.zero
local lastTitleClick = 0

dragArea.InputBegan:Connect(function(input)
	if not isPointerStart(input) then return end
	local now = os.clock()
	if now - lastTitleClick < 0.35 then
		lastTitleClick = 0
		setMaximized(not maximized)
		return
	end
	lastTitleClick = now
	if maximized then return end
	dragging = true
	dragStart = Vector2.new(input.Position.X, input.Position.Y)
	dragOrigin = window.AbsolutePosition
end)

connect(UserInputService.InputChanged, function(input)
	local t = input.UserInputType
	if t ~= Enum.UserInputType.MouseMovement and t ~= Enum.UserInputType.Touch then return end
	local pos = Vector2.new(input.Position.X, input.Position.Y)
	if resizing then
		doResize(pos)
	elseif dragging then
		local s = screenSize()
		local size = window.AbsoluteSize
		local p = dragOrigin + (pos - dragStart)
		local x = math.max(-(size.X - 100), math.min(p.X, s.X - 100))
		local y = math.max(0, math.min(p.Y, s.Y - TITLE_H))
		window.Position = UDim2.fromOffset(x, y)
	end
end)

connect(UserInputService.InputEnded, function(input)
	if isPointerStart(input) then
		dragging = false
		resizing = nil
	end
end)

-- keep the window on screen if the viewport changes
connect(gui:GetPropertyChangedSignal("AbsoluteSize"), function()
	if maximized then return end
	local s = screenSize()
	local p, sz = window.AbsolutePosition, window.AbsoluteSize
	local nx = math.max(0, math.min(p.X, s.X - sz.X))
	local ny = math.max(0, math.min(p.Y, s.Y - sz.Y))
	if nx ~= p.X or ny ~= p.Y then
		window.Position = UDim2.fromOffset(nx, ny)
	end
end)

---------------------------------------------------------------------
-- Player list + spectating logic
---------------------------------------------------------------------
local function getSubject(plr)
	local char = plr and plr.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid") or char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
end

updateUI = function()
	local count = 0
	for _ in pairs(rows) do count += 1 end
	countLabel.Text = count .. (count == 1 and " player" or " players")

	spectateBtn.SetEnabled(selected ~= nil and selected ~= LocalPlayer and selected ~= spectating)
	unspectateBtn.SetEnabled(spectating ~= nil)

	if notice then
		statusLabel.Text = notice
	elseif spectating then
		statusLabel.Text = "Spectating: " .. spectating.DisplayName .. " (@" .. spectating.Name .. ")"
	elseif selected == LocalPlayer then
		statusLabel.Text = "You can't spectate yourself"
	else
		statusLabel.Text = "Not spectating"
	end
end

refreshRow = function(plr)
	local r = plr and rows[plr]
	if not r then return end
	local isSel = selected == plr
	r.frame.BackgroundColor3 = isSel and C.select or C.hover
	r.frame.BackgroundTransparency = (isSel or r.hover) and 0 or 1
	r.tag.Visible = spectating == plr
end

local function selectPlayer(plr)
	local prev = selected
	selected = plr
	notice = nil
	refreshRow(prev)
	refreshRow(plr)
	updateUI()
end

startSpectating = function(plr)
	if not plr or plr == LocalPlayer or plr.Parent ~= Players then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	if not spectating then
		prevCamType = cam.CameraType
	end
	local prev = spectating
	spectating = plr
	notice = nil
	needsReturn = false
	cam.CameraType = Enum.CameraType.Custom
	local subject = getSubject(plr)
	if subject then
		cam.CameraSubject = subject
	end
	refreshRow(prev)
	refreshRow(plr)
	updateUI()
end

stopSpectating = function()
	local prev = spectating
	spectating = nil
	local cam = workspace.CurrentCamera
	if cam then
		local mine = getSubject(LocalPlayer)
		if mine then
			cam.CameraSubject = mine
			needsReturn = false
		else
			needsReturn = true
		end
		if prevCamType then
			cam.CameraType = prevCamType
		end
	end
	prevCamType = nil
	refreshRow(prev)
	updateUI()
end

local function sortRows()
	local arr = {}
	for plr in pairs(rows) do
		arr[#arr + 1] = plr
	end
	table.sort(arr, function(a, b)
		if a == b then return false end
		if a == LocalPlayer then return true end
		if b == LocalPlayer then return false end
		return a.DisplayName:lower() < b.DisplayName:lower()
	end)
	for i, plr in ipairs(arr) do
		rows[plr].frame.LayoutOrder = i
	end
end

local function applyFilter()
	local q = searchBox.Text:lower()
	for plr, r in pairs(rows) do
		local match = q == ""
			or plr.Name:lower():find(q, 1, true) ~= nil
			or plr.DisplayName:lower():find(q, 1, true) ~= nil
		r.frame.Visible = match
	end
end
searchBox:GetPropertyChangedSignal("Text"):Connect(applyFilter)

local function createRow(plr)
	local frame = new("TextButton", {
		Name = plr.Name,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.hover,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, ROW_H),
	}, list)

	local avatar = new("ImageLabel", {
		BackgroundColor3 = C.avatarBg,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(8, 5),
		Size = UDim2.fromOffset(36, 36),
		Image = "rbxthumb://type=AvatarHeadShot&id=" .. plr.UserId .. "&w=48&h=48",
	}, frame)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, avatar)

	local nameLabel = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(54, 5),
		Size = UDim2.new(1, -150, 0, 20),
		Font = FONT, TextSize = 17, TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
	}, frame)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(54, 25),
		Size = UDim2.new(1, -150, 0, 16),
		Font = FONT, TextSize = 14, TextColor3 = C.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "@" .. plr.Name,
	}, frame)
	local tag = new("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(84, 20),
		Font = FONT, TextSize = 14, TextColor3 = C.green,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "Spectating",
		Visible = false,
	}, frame)

	local function setName()
		nameLabel.Text = plr.DisplayName .. (plr == LocalPlayer and " (You)" or "")
	end
	setName()

	local row = { frame = frame, tag = tag, hover = false, lastClick = 0 }
	row.nameConn = plr:GetPropertyChangedSignal("DisplayName"):Connect(function()
		setName()
		sortRows()
		applyFilter()
	end)
	rows[plr] = row

	frame.MouseEnter:Connect(function() row.hover = true refreshRow(plr) end)
	frame.MouseLeave:Connect(function() row.hover = false refreshRow(plr) end)
	frame.MouseButton1Click:Connect(function()
		local now = os.clock()
		local double = (now - row.lastClick) < 0.4
		row.lastClick = now
		selectPlayer(plr)
		if double then startSpectating(plr) end
	end)

	refreshRow(plr)
end

local function addPlayer(plr)
	if rows[plr] then return end
	createRow(plr)
	sortRows()
	applyFilter()
	updateUI()
end

local function removePlayer(plr)
	local r = rows[plr]
	if r then
		r.nameConn:Disconnect()
		r.frame:Destroy()
		rows[plr] = nil
	end
	if selected == plr then
		selected = nil
	end
	if spectating == plr then
		stopSpectating()
		notice = plr.DisplayName .. " left the game"
	end
	updateUI()
end

connect(Players.PlayerAdded, addPlayer)
connect(Players.PlayerRemoving, removePlayer)
for _, plr in ipairs(Players:GetPlayers()) do
	addPlayer(plr)
end

-- Keep the camera locked on the spectated player (handles their respawns)
connect(RunService.Heartbeat, function()
	if not spectating then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	local subject = getSubject(spectating)
	if subject and cam.CameraSubject ~= subject then
		cam.CameraSubject = subject
	end
	if cam.CameraType ~= Enum.CameraType.Custom then
		cam.CameraType = Enum.CameraType.Custom
	end
end)

-- If we unspectated while our own character was missing, snap back once it spawns
connect(LocalPlayer.CharacterAdded, function(char)
	if not needsReturn or spectating then return end
	local hum = char:WaitForChild("Humanoid", 10)
	local cam = workspace.CurrentCamera
	if hum and cam and not spectating then
		cam.CameraSubject = hum
		needsReturn = false
	end
end)

-- Cleanup whenever the GUI is destroyed (close button or script re-run)
gui.Destroying:Connect(function()
	if spectating then
		stopSpectating()
	end
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	table.clear(conns)
end)

updateUI()
