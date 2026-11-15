--[[
	fly/to - fly at a player, route around stuff, adjustable speed, own gui.
	paste into any LocalScript. needs nothing else in the place.
	rshift = hide/show the gui
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local PathfindingService = game:GetService("PathfindingService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- re-running the script cleans up the old copy first
if _G.FlyToCleanup then
	pcall(_G.FlyToCleanup)
end

---------------------------------------------------------------- settings
local SPEED_MIN, SPEED_MAX, SPEED_STEP, SPEED_START = 10, 250, 5, 70
local ARRIVE_DIST = 6 -- hover this close to the target
local BODY_RADIUS = 2 -- how fat we pretend to be when checking for walls
local HOVER_HEIGHT = 3.5 -- height above the navmesh floor while following a path
local STEER_LOOK = 18 -- how far ahead the fallback steering looks
local WIN_W = 330

---------------------------------------------------------------- palette (one accent, no gradients)
local INK = Color3.fromRGB(19, 18, 17)
local INK2 = Color3.fromRGB(32, 31, 28)
local PIT = Color3.fromRGB(13, 12, 11)
local BONE = Color3.fromRGB(233, 226, 211)
local DIM = Color3.fromRGB(125, 119, 108)
local HOT = Color3.fromRGB(255, 91, 31)
local DIM_HEX = "rgb(125,119,108)"
local MONO = Enum.Font.RobotoMono

local FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MED = TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local HIDE = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

---------------------------------------------------------------- tiny helpers
local conns = {}
local function bind(signal, fn)
	local c = signal:Connect(fn)
	table.insert(conns, c)
	return c
end

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in props do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function text(parent, props)
	local p = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = MONO,
		TextColor3 = BONE,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in props do
		p[k] = v
	end
	return new("TextLabel", p, parent)
end

-- one live tween per property so spamming never fights itself
local live = setmetatable({}, { __mode = "k" })
local function tween(inst, info, goal)
	local store = live[inst]
	if not store then
		store = {}
		live[inst] = store
	end
	for prop in goal do
		if store[prop] then
			store[prop]:Cancel()
		end
	end
	local t = TweenService:Create(inst, info, goal)
	for prop in goal do
		store[prop] = t
	end
	t:Play()
	return t
end

local function kill(o)
	if o then
		o:Destroy()
	end
end

---------------------------------------------------------------- state
local target = nil
local flying = false
local speed = SPEED_START
local mode = "IDLE"
local vel = Vector3.zero
local mover, aligner, attach = nil, nil, nil

local pts = nil -- path points (Vector3 list)
local ptIndex = 1
local pathGoal = Vector3.zero
local pathTime = 0
local pathFailAt = -math.huge
local computing = false
local pathToken = 0
local steerDir = Vector3.zero
local steerUntil = 0
local aimPoint = Vector3.zero
local arrived = false
local nextThink = 0
local sampleAt, samplePos, stuck = 0, Vector3.zero, 0

local function myParts()
	local char = LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return char, hum, root
end

local function targetRoot()
	local c = target and target.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

---------------------------------------------------------------- navigation
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = true

local function refreshFilter()
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = list
end

local function isClear(from, to)
	local d = to - from
	if d.Magnitude < 0.5 then
		return true
	end
	return workspace:Spherecast(from, BODY_RADIUS, d, rayParams) == nil
end

local function groundPoint(p)
	local hit = workspace:Raycast(p + Vector3.new(0, 2, 0), Vector3.new(0, -400, 0), rayParams)
	return hit and (hit.Position + Vector3.new(0, 0.5, 0)) or p
end

-- roblox pathfinding is a ground navmesh, so we path on the floor and lift the points up to hover height
local function computePath(from, to)
	if computing then
		return
	end
	computing = true
	local token = pathToken
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = BODY_RADIUS + 0.5,
			AgentHeight = 5.5,
			AgentCanJump = true,
			WaypointSpacing = 8,
		})
		local ok = pcall(function()
			path:ComputeAsync(groundPoint(from), groundPoint(to))
		end)
		computing = false
		if token ~= pathToken then
			return
		end
		if ok and path.Status == Enum.PathStatus.Success then
			local list = {}
			for _, wp in path:GetWaypoints() do
				table.insert(list, wp.Position + Vector3.new(0, HOVER_HEIGHT, 0))
			end
			pts, ptIndex, pathGoal, pathTime = list, 1, to, os.clock()
		else
			pts = nil
			pathFailAt = os.clock()
		end
	end)
end

-- fallback when there's no navmesh route: cast a fan of directions and pick the clear one closest to the target (likes going up)
local YAWS = { 0, 35, -35, 70, -70, 110, -110, 150, -150 }
local PITCHES = { 0, 40, -30, 70 }
local function steer(pos, tpos)
	local dir = tpos - pos
	if dir.Magnitude < 0.1 then
		return pos
	end
	dir = dir.Unit
	local up = math.abs(dir.Y) > 0.98 and Vector3.xAxis or Vector3.yAxis
	local base = CFrame.lookAt(Vector3.zero, dir, up)
	local best, bestScore = nil, -math.huge
	for _, yaw in YAWS do
		for _, pitch in PITCHES do
			local cand = (base * CFrame.Angles(math.rad(pitch), math.rad(yaw), 0)).LookVector
			if workspace:Spherecast(pos, BODY_RADIUS, cand * STEER_LOOK, rayParams) == nil then
				local score = cand:Dot(dir) + 0.12 * cand.Y + 0.3 * cand:Dot(steerDir)
				if score > bestScore then
					best, bestScore = cand, score
				end
			end
		end
	end
	if not best then
		best = Vector3.yAxis
	end
	steerDir = best
	return pos + best * STEER_LOOK
end

local function resetNav()
	pts = nil
	ptIndex = 1
	arrived = false
	steerUntil = 0
	pathFailAt = -math.huge
	pathToken += 1
	nextThink = 0
end

-- runs ~10x a second: decides mode + where to aim
local function think(now, root, tRoot)
	refreshFilter()
	local pos, tpos = root.Position, tRoot.Position
	local dist = (tpos - pos).Magnitude
	local clear = isClear(pos, tpos)

	-- stuck check: commanded to move but barely did
	if now - sampleAt >= 0.6 then
		if mode ~= "ARRIVED" and vel.Magnitude > 8 and (pos - samplePos).Magnitude < vel.Magnitude * 0.6 * 0.2 then
			stuck += 1
		else
			stuck = 0
		end
		sampleAt, samplePos = now, pos
		if stuck >= 2 then
			stuck = 0
			steerUntil = now + 1.5
			pts = nil
		end
	end

	if arrived then
		if dist > ARRIVE_DIST + 4 or not clear then
			arrived = false
		end
	elseif dist <= ARRIVE_DIST and clear then
		arrived = true
	end
	if arrived then
		mode = "ARRIVED"
		return
	end

	if clear then
		mode = "DIRECT"
		pts = nil
		return
	end

	if now < steerUntil then
		mode = "STEER"
		aimPoint = steer(pos, tpos)
		return
	end

	local stale = pts == nil or now - pathTime > 4 or (tpos - pathGoal).Magnitude > 20
	if stale and not computing and now - pathFailAt > 1.5 then
		computePath(pos, tpos)
	end

	if pts then
		mode = "PATH"
		while ptIndex < #pts and (pts[ptIndex] - pos).Magnitude < 4 do
			ptIndex += 1
		end
		-- string pulling: skip ahead to the furthest point we can see
		for i = math.min(#pts, ptIndex + 12), ptIndex + 1, -1 do
			if isClear(pos, pts[i]) then
				ptIndex = i
				break
			end
		end
		if ptIndex == #pts and (pts[ptIndex] - pos).Magnitude < 4 then
			mode = "STEER" -- path ended but target still not reachable by line (ledge, air, etc)
			aimPoint = steer(pos, tpos)
		else
			aimPoint = pts[ptIndex]
		end
	else
		mode = "STEER"
		aimPoint = steer(pos, tpos)
	end
end

-- runs every frame: turns the aim point into smooth velocity
local function drive(dt, root, tRoot)
	local pos, tpos = root.Position, tRoot.Position
	local desired = Vector3.zero
	if mode ~= "ARRIVED" then
		local aim = (mode == "DIRECT") and tpos or aimPoint
		local to = aim - pos
		if to.Magnitude > 0.1 then
			local brake = math.max(0, (tpos - pos).Magnitude - ARRIVE_DIST) * 5 + 4
			desired = to.Unit * math.min(speed, brake)
		end
	end
	vel = vel:Lerp(desired, 1 - math.exp(-dt * 10))
	mover.VectorVelocity = vel

	local face = Vector3.new(vel.X, 0, vel.Z)
	if face.Magnitude < 2 then
		face = Vector3.new(tpos.X - pos.X, 0, tpos.Z - pos.Z)
	end
	if face.Magnitude > 0.1 then
		aligner.CFrame = CFrame.lookAt(pos, pos + face)
	end
end

local function stopFly()
	flying = false
	kill(mover)
	kill(aligner)
	kill(attach)
	mover, aligner, attach = nil, nil, nil
	local _, hum = myParts()
	if hum then
		hum.PlatformStand = false
	end
	vel = Vector3.zero
	mode = "IDLE"
	arrived = false
end

local function startFly()
	local char, hum, root = myParts()
	if not (char and hum and root) or hum.Health <= 0 then
		return false
	end
	for _, n in { "FlyToMover", "FlyToAlign", "FlyToAttach" } do
		local old = root:FindFirstChild(n)
		if old then
			old:Destroy()
		end
	end
	attach = new("Attachment", { Name = "FlyToAttach" }, root)
	mover = new("LinearVelocity", {
		Name = "FlyToMover",
		Attachment0 = attach,
		RelativeTo = Enum.ActuatorRelativeTo.World,
		VelocityConstraintMode = Enum.VelocityConstraintMode.Vector,
		MaxForce = 1e8,
		VectorVelocity = Vector3.zero,
	}, root)
	aligner = new("AlignOrientation", {
		Name = "FlyToAlign",
		Mode = Enum.OrientationAlignmentMode.OneAttachment,
		Attachment0 = attach,
		RigidityEnabled = false,
		MaxTorque = 1e8,
		Responsiveness = 40,
		CFrame = root.CFrame,
	}, root)
	hum.PlatformStand = true
	vel = root.AssemblyLinearVelocity
	resetNav()
	flying = true
	mode = "IDLE"
	return true
end

---------------------------------------------------------------- gui
local selectPlayer, refreshUI

local gui = new("ScreenGui", {
	Name = "FlyToUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 50,
}, PlayerGui)

local holder = new("Frame", {
	Name = "Holder",
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(0, 0),
	Position = UDim2.fromScale(0.02, 0.2),
}, gui)
local root = new("Frame", {
	Name = "Root",
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(WIN_W, 10),
}, holder)
local uiScale = new("UIScale", { Scale = 0.02 }, root)

local shadow = new("Frame", {
	Name = "Shadow",
	BackgroundColor3 = HOT,
	BorderSizePixel = 0,
	ZIndex = 1,
	Size = UDim2.fromOffset(WIN_W, 100),
}, root)
local window = new("Frame", {
	Name = "Window",
	BackgroundColor3 = INK,
	BorderSizePixel = 0,
	ZIndex = 2,
	Size = UDim2.fromOffset(WIN_W, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
}, root)
new("UIStroke", { Color = BONE, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, window)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, window)

local function syncShadow()
	local s = math.max(uiScale.Scale, 0.001)
	local a = window.AbsoluteSize
	shadow.Size = UDim2.fromOffset(a.X / s, a.Y / s)
end
window:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncShadow)
uiScale:GetPropertyChangedSignal("Scale"):Connect(syncShadow)

-- header (also the drag handle)
local header = new("Frame", {
	Name = "Header",
	LayoutOrder = 1,
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundColor3 = BONE,
	BorderSizePixel = 0,
}, window)
local pulse = new("Frame", {
	Size = UDim2.fromOffset(10, 10),
	Position = UDim2.new(0, 12, 0.5, -5),
	BackgroundColor3 = INK,
	BorderSizePixel = 0,
}, header)
text(header, {
	Text = "FLY/TO",
	TextColor3 = INK,
	TextSize = 16,
	Position = UDim2.new(0, 32, 0, 0),
	Size = UDim2.new(1, -100, 1, 0),
})

local function headerButton(label, xOff)
	local b = new("TextButton", {
		Text = label,
		Font = MONO,
		TextSize = 18,
		TextColor3 = INK,
		BackgroundColor3 = BONE,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Size = UDim2.new(0, 34, 1, 0),
		Position = UDim2.new(1, xOff, 0, 0),
	}, header)
	b.MouseEnter:Connect(function()
		tween(b, FAST, { BackgroundColor3 = INK, TextColor3 = BONE })
	end)
	b.MouseLeave:Connect(function()
		tween(b, FAST, { BackgroundColor3 = BONE, TextColor3 = INK })
	end)
	return b
end
local collapseBtn = headerButton("-", -68)
local closeBtn = headerButton("x", -34)

-- body
local body = new("Frame", {
	Name = "Body",
	LayoutOrder = 2,
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	ClipsDescendants = true,
}, window)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, body)

local function sep(order)
	return new("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Color3.fromRGB(58, 55, 50),
		BorderSizePixel = 0,
	}, body)
end

-- 1. target label
local labelRow = new("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1 }, body)
text(labelRow, {
	Text = "TARGET",
	TextColor3 = DIM,
	TextSize = 11,
	Position = UDim2.new(0, 12, 0, 0),
	Size = UDim2.new(0.5, -12, 1, 0),
})
text(labelRow, {
	Text = "STUDS",
	TextColor3 = DIM,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Right,
	Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.new(0.5, -12, 1, 0),
})

-- 2. player list
local listWrap = new("Frame", {
	LayoutOrder = 2,
	Size = UDim2.new(1, 0, 0, 132),
	BackgroundColor3 = PIT,
	BorderSizePixel = 0,
}, body)
local list = new("ScrollingFrame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = HOT,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
}, listWrap)
new("UIListLayout", { SortOrder = Enum.SortOrder.Name }, list)
local empty = text(listWrap, {
	Text = "nobody else here...",
	TextColor3 = DIM,
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 2,
})

local rows = {}

local function paintRow(plr, on)
	local r = rows[plr]
	if not r then
		return
	end
	tween(r.bar, MED, { Size = UDim2.new(0, on and 5 or 0, 1, 0) })
	tween(r.name, FAST, { TextColor3 = on and HOT or BONE })
	tween(r.btn, FAST, { BackgroundTransparency = on and 0 or 1 })
end

local function addRow(plr)
	if plr == LocalPlayer or rows[plr] then
		return
	end
	local btn = new("TextButton", {
		Name = string.lower(plr.DisplayName) .. plr.UserId,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = INK2,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 30),
	}, list)
	local bar = new("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = HOT, BorderSizePixel = 0 }, btn)
	local nameL = text(btn, {
		Text = plr.DisplayName,
		TextSize = 14,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.new(0, 14, 0, 0),
		Size = UDim2.new(1, -80, 1, 0),
		TextTransparency = 1,
	})
	local distL = text(btn, {
		Text = "--",
		TextColor3 = DIM,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 0),
		Size = UDim2.new(0, 56, 1, 0),
	})
	rows[plr] = { btn = btn, bar = bar, name = nameL, dist = distL }
	tween(nameL, MED, { TextTransparency = 0 })
	btn.MouseEnter:Connect(function()
		if target ~= plr then
			tween(btn, FAST, { BackgroundTransparency = 0.5 })
		end
	end)
	btn.MouseLeave:Connect(function()
		if target ~= plr then
			tween(btn, FAST, { BackgroundTransparency = 1 })
		end
	end)
	btn.Activated:Connect(function()
		selectPlayer(plr)
	end)
	empty.Visible = false
end

sep(3)

-- 4. speed
local speedBox = new("Frame", { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 78), BackgroundTransparency = 1 }, body)
text(speedBox, {
	Text = "SPEED",
	TextColor3 = DIM,
	TextSize = 11,
	Position = UDim2.new(0, 12, 0, 10),
	Size = UDim2.new(0, 80, 0, 14),
})
local function fmtSpeed(n)
	return string.format('%03d<font size="11" color="%s"> st/s</font>', n, DIM_HEX)
end
local readout = text(speedBox, {
	RichText = true,
	Text = fmtSpeed(SPEED_START),
	TextSize = 24,
	TextColor3 = HOT,
	TextXAlignment = Enum.TextXAlignment.Right,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 4),
	Size = UDim2.new(0, 160, 0, 28),
})

local function stepButton(label, pos)
	local b = new("TextButton", {
		Text = label,
		Font = MONO,
		TextSize = 16,
		TextColor3 = BONE,
		BackgroundColor3 = INK2,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Size = UDim2.fromOffset(26, 26),
		Position = pos,
	}, speedBox)
	local stroke = new("UIStroke", { Color = DIM, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	b.MouseEnter:Connect(function()
		tween(stroke, FAST, { Color = BONE })
	end)
	b.MouseLeave:Connect(function()
		tween(stroke, FAST, { Color = DIM })
	end)
	b.MouseButton1Down:Connect(function()
		tween(b, FAST, { BackgroundColor3 = HOT, TextColor3 = INK })
	end)
	local function up()
		tween(b, FAST, { BackgroundColor3 = INK2, TextColor3 = BONE })
	end
	b.MouseButton1Up:Connect(up)
	b.MouseLeave:Connect(up)
	return b
end
local minus = stepButton("-", UDim2.new(0, 12, 0, 40))
local plus = stepButton("+", UDim2.new(1, -38, 0, 40))

local track = new("Frame", {
	Position = UDim2.new(0, 46, 0, 40),
	Size = UDim2.new(1, -92, 0, 26),
	BackgroundColor3 = PIT,
	BorderSizePixel = 0,
}, speedBox)
new("UIStroke", { Color = DIM, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, track)
local fill = new("Frame", { BackgroundColor3 = HOT, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), ZIndex = 2 }, track)
for i = 1, 19 do
	new("Frame", {
		BackgroundColor3 = PIT,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 2, 1, 0),
		Position = UDim2.new(i / 20, -1, 0, 0),
		ZIndex = 3,
	}, track)
end
local handle = new("Frame", {
	BackgroundColor3 = BONE,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0.5, 0),
	Size = UDim2.new(0, 6, 1, 12),
	ZIndex = 4,
}, track)

local shown = new("NumberValue", { Value = SPEED_START }, gui)
shown.Changed:Connect(function(v)
	readout.Text = fmtSpeed(math.floor(v + 0.5))
end)

local function paintSlider()
	local f = (speed - SPEED_MIN) / (SPEED_MAX - SPEED_MIN)
	fill.Size = UDim2.fromScale(f, 1)
	handle.Position = UDim2.new(f, 0, 0, -6)
end
paintSlider()

local function setSpeed(v)
	v = math.clamp(math.floor(v / SPEED_STEP + 0.5) * SPEED_STEP, SPEED_MIN, SPEED_MAX)
	if v == speed then
		return
	end
	speed = v
	paintSlider()
	tween(shown, FAST, { Value = v })
end

minus.Activated:Connect(function()
	setSpeed(speed - SPEED_STEP * 2)
end)
plus.Activated:Connect(function()
	setSpeed(speed + SPEED_STEP * 2)
end)

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end
local function isMove(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

local sliding = false
local function fromX(x)
	local f = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
	setSpeed(SPEED_MIN + f * (SPEED_MAX - SPEED_MIN))
end
track.InputBegan:Connect(function(input)
	if isPress(input) then
		sliding = true
		tween(handle, FAST, { Size = UDim2.new(0, 10, 1, 12) })
		fromX(input.Position.X)
	end
end)

sep(5)

-- 6. status strip
local statusRow = new("Frame", {
	LayoutOrder = 6,
	Size = UDim2.new(1, 0, 0, 28),
	BackgroundColor3 = PIT,
	BorderSizePixel = 0,
}, body)
local modeLabel = text(statusRow, {
	RichText = true,
	TextSize = 12,
	Position = UDim2.new(0, 12, 0, 0),
	Size = UDim2.new(0.55, -12, 1, 0),
})
local distLabel = text(statusRow, {
	RichText = true,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Right,
	Position = UDim2.new(0.55, 0, 0, 0),
	Size = UDim2.new(0.45, -12, 1, 0),
})

-- 7. action button (sits on a hard shadow, sinks into it when pressed)
local actionWrap = new("Frame", { LayoutOrder = 7, Size = UDim2.new(1, 0, 0, 62), BackgroundTransparency = 1 }, body)
local ACT_POS = UDim2.new(0, 12, 0, 10)
local ACT_PRESSED = UDim2.new(0, 16, 0, 14)
local ACT_SIZE = UDim2.new(1, -29, 0, 40)
local actionShadow = new("Frame", {
	Position = UDim2.new(0, 17, 0, 15),
	Size = ACT_SIZE,
	BackgroundColor3 = HOT,
	BorderSizePixel = 0,
	ZIndex = 1,
}, actionWrap)
local action = new("TextButton", {
	Position = ACT_POS,
	Size = ACT_SIZE,
	BackgroundColor3 = BONE,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Font = MONO,
	TextSize = 16,
	TextColor3 = INK,
	Text = "PICK A TARGET",
	ZIndex = 2,
}, actionWrap)
action.MouseButton1Down:Connect(function()
	tween(action, FAST, { Position = ACT_PRESSED })
end)
local function releaseAction()
	tween(action, FAST, { Position = ACT_POS })
end
action.MouseButton1Up:Connect(releaseAction)
action.MouseLeave:Connect(releaseAction)

local function shake(obj, base)
	task.spawn(function()
		for _, dx in { -5, 5, -3, 3, 0 } do
			local t = tween(obj, TweenInfo.new(0.04, Enum.EasingStyle.Linear), { Position = base + UDim2.fromOffset(dx, 0) })
			t.Completed:Wait()
		end
	end)
end

-- 8. footer
local footer = text(body, {
	LayoutOrder = 8,
	Text = "RSHIFT hides  /  drag the top bar",
	TextColor3 = DIM,
	TextSize = 10,
	Size = UDim2.new(1, 0, 0, 22),
})
new("UIPadding", { PaddingLeft = UDim.new(0, 12) }, footer)

---------------------------------------------------------------- gui behaviour
local pulseTween = nil
local function setPulse(on)
	if pulseTween then
		pulseTween:Cancel()
		pulseTween = nil
	end
	pulse.BackgroundTransparency = 0
	if on then
		pulse.BackgroundColor3 = HOT
		pulseTween = TweenService:Create(
			pulse,
			TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ BackgroundTransparency = 0.85 }
		)
		pulseTween:Play()
	else
		pulse.BackgroundColor3 = INK
	end
end

local shownMode = ""
local function paintMode()
	shownMode = mode
	modeLabel.Text = string.format('<font color="%s">MODE </font>%s', DIM_HEX, mode)
	modeLabel.TextColor3 = (flying and mode ~= "ARRIVED") and HOT or BONE
	modeLabel.TextTransparency = 0.85
	tween(modeLabel, MED, { TextTransparency = 0 })
end

refreshUI = function()
	if flying then
		action.Text = "ABORT"
		tween(action, MED, { BackgroundColor3 = HOT, TextColor3 = INK })
		tween(actionShadow, MED, { BackgroundColor3 = BONE })
	elseif target then
		action.Text = "ENGAGE"
		tween(action, MED, { BackgroundColor3 = BONE, TextColor3 = INK })
		tween(actionShadow, MED, { BackgroundColor3 = HOT })
	else
		action.Text = "PICK A TARGET"
		tween(action, MED, { BackgroundColor3 = Color3.fromRGB(58, 56, 51), TextColor3 = DIM })
		tween(actionShadow, MED, { BackgroundColor3 = Color3.fromRGB(38, 36, 33) })
	end
	setPulse(flying)
	paintMode()
end

selectPlayer = function(plr)
	if target == plr then
		return
	end
	if target then
		paintRow(target, false)
	end
	target = plr
	paintRow(plr, true)
	resetNav()
	refreshUI()
end

action.Activated:Connect(function()
	if flying then
		stopFly()
		refreshUI()
	elseif not target then
		shake(action, ACT_POS)
	elseif startFly() then
		refreshUI()
	end
end)

-- collapse / close
local collapsed = false
local savedFull = 0
collapseBtn.Activated:Connect(function()
	collapsed = not collapsed
	if collapsed then
		savedFull = body.AbsoluteSize.Y / math.max(uiScale.Scale, 0.001)
		body.AutomaticSize = Enum.AutomaticSize.None
		body.Size = UDim2.new(1, 0, 0, savedFull)
		tween(body, MED, { Size = UDim2.new(1, 0, 0, 0) })
		collapseBtn.Text = "+"
	else
		collapseBtn.Text = "-"
		local t = tween(body, MED, { Size = UDim2.new(1, 0, 0, savedFull) })
		t.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and not collapsed then
				body.AutomaticSize = Enum.AutomaticSize.Y
			end
		end)
	end
end)

local function destroyAll()
	if flying then
		stopFly()
	end
	for _, c in conns do
		c:Disconnect()
	end
	gui:Destroy()
	if _G.FlyToCleanup == destroyAll then
		_G.FlyToCleanup = nil
	end
end
_G.FlyToCleanup = destroyAll

closeBtn.Activated:Connect(function()
	if flying then
		stopFly()
	end
	local t = tween(uiScale, HIDE, { Scale = 0.02 })
	t.Completed:Connect(function()
		destroyAll()
	end)
end)

-- show / hide
local visible = false
local function baseScale()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 760)
	return math.clamp(vp.Y / 760, 0.78, 1.1)
end
local function setVisible(v)
	visible = v
	if v then
		gui.Enabled = true
		tween(uiScale, POP, { Scale = baseScale() })
		tween(shadow, POP, { Position = UDim2.fromOffset(7, 7) })
	else
		local t = tween(uiScale, HIDE, { Scale = 0.02 })
		tween(shadow, HIDE, { Position = UDim2.fromOffset(0, 0) })
		t.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and not visible then
				gui.Enabled = false
			end
		end)
	end
end

do
	local cam = workspace.CurrentCamera
	if cam then
		bind(cam:GetPropertyChangedSignal("ViewportSize"), function()
			if visible then
				uiScale.Scale = baseScale()
			end
		end)
	end
end

-- dragging the window by the header
local moving = false
local dragStart, startPos
header.InputBegan:Connect(function(input)
	if isPress(input) then
		moving = true
		dragStart = input.Position
		startPos = holder.Position
	end
end)

bind(UserInputService.InputChanged, function(input)
	if not isMove(input) then
		return
	end
	if sliding then
		fromX(input.Position.X)
	elseif moving then
		local d = input.Position - dragStart
		holder.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
	end
end)

bind(UserInputService.InputEnded, function(input)
	if isPress(input) then
		moving = false
		if sliding then
			sliding = false
			tween(handle, FAST, { Size = UDim2.new(0, 6, 1, 12) })
		end
	end
end)

bind(UserInputService.InputBegan, function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.RightShift then
		setVisible(not visible)
	end
end)

---------------------------------------------------------------- players + main loop
for _, p in Players:GetPlayers() do
	addRow(p)
end
if next(rows) == nil then
	empty.Visible = true
end
bind(Players.PlayerAdded, addRow)
bind(Players.PlayerRemoving, function(p)
	local r = rows[p]
	if r then
		r.btn:Destroy()
		rows[p] = nil
	end
	if next(rows) == nil then
		empty.Visible = true
	end
	if target == p then
		target = nil
		if flying then
			stopFly()
		end
		resetNav()
		refreshUI()
	end
end)
bind(LocalPlayer.CharacterAdded, function()
	if flying then
		stopFly()
		refreshUI()
	end
end)

local function updateDistances()
	local _, _, myRoot = myParts()
	for plr, r in rows do
		local c = plr.Character
		local pr = c and c:FindFirstChild("HumanoidRootPart")
		r.dist.Text = (pr and myRoot) and tostring(math.floor((pr.Position - myRoot.Position).Magnitude)) or "--"
	end
	local d = "--"
	local tr = targetRoot()
	if tr and myRoot then
		d = tostring(math.floor((tr.Position - myRoot.Position).Magnitude))
	end
	distLabel.Text = string.format('<font color="%s">DIST </font>%s', DIM_HEX, d)
end

local uiAccum = 0
bind(RunService.Heartbeat, function(dt)
	uiAccum += dt
	if uiAccum >= 0.2 then
		uiAccum = 0
		updateDistances()
	end
	if not flying then
		return
	end

	local now = os.clock()
	local _, hum, myRoot = myParts()
	if not (hum and myRoot and mover and mover.Parent) or hum.Health <= 0 then
		stopFly()
		refreshUI()
		return
	end

	local tRoot = targetRoot()
	if not tRoot then
		mode = "LOST" -- target is respawning or gone, just hover
		vel = vel:Lerp(Vector3.zero, 0.2)
		mover.VectorVelocity = vel
	else
		if now >= nextThink then
			nextThink = now + 0.1
			think(now, myRoot, tRoot)
		end
		drive(dt, myRoot, tRoot)
	end

	if mode ~= shownMode then
		paintMode()
	end
end)

refreshUI()
updateDistances()
setVisible(true)
