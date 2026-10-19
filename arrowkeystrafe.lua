-- ArrowKeyStrafe (LocalScript)
-- Left/Right arrow keys strafe the character (like A and D) instead of rotating the camera.
-- Right Ctrl also makes the character jump (same as Space).
-- Self-contained: no extra objects needed, works wherever a LocalScript can run
-- (StarterPlayerScripts, StarterCharacterScripts, StarterGui, StarterPack, etc.).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
if not player then
	return
end

local ACTION_NAME = "ArrowKeyStrafe_BlockCameraTurn"
local STEP_NAME = "ArrowKeyStrafe_Move"

---------------------------------------------------------------------
-- 1) Stop the default camera script from rotating on Left/Right arrows.
--    Binding the same keys at a higher priority and sinking them means
--    the default camera input handler never receives them.
---------------------------------------------------------------------
local function sinkArrowKeys()
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindActionAtPriority(
	ACTION_NAME,
	sinkArrowKeys,
	false,
	Enum.ContextActionPriority.High.Value + 100,
	Enum.KeyCode.Left,
	Enum.KeyCode.Right
)

---------------------------------------------------------------------
-- 2) Grab the default controls (so WASD / thumbstick / gamepad / Up+Down
--    arrows keep working exactly as normal) if the PlayerModule exists.
---------------------------------------------------------------------
local controls = nil

task.spawn(function()
	local ok, result = pcall(function()
		local playerScripts = player:WaitForChild("PlayerScripts", 10)
		local playerModule = playerScripts and playerScripts:WaitForChild("PlayerModule", 10)
		if playerModule then
			return require(playerModule):GetControls()
		end
		return nil
	end)
	if ok then
		controls = result
	end
end)

---------------------------------------------------------------------
-- 3) Each frame, add the arrow-key strafe to the normal movement vector.
--    Runs right after the default control module so we can override it.
---------------------------------------------------------------------
local function getBaseMoveVector()
	if controls then
		local ok, vec = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(vec) == "Vector3" then
			return vec
		end
	end

	-- Fallback if the default PlayerModule isn't available: read the keys ourselves.
	local x, z = 0, 0
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then x -= 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then x += 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then z -= 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then z += 1 end
	return Vector3.new(x, 0, z)
end

RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Input.Value + 1, function()
	if UserInputService:GetFocusedTextBox() then
		return
	end

	-- Right Ctrl = jump (hold to keep jumping, just like holding Space)
	if UserInputService:IsKeyDown(Enum.KeyCode.RightControl) then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Jump = true
		end
	end

	local strafe = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		strafe -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		strafe += 1
	end

	if strafe == 0 then
		return -- leave default movement completely untouched
	end

	local base = getBaseMoveVector()
	local combined = Vector3.new(base.X + strafe, 0, base.Z)

	if combined.Magnitude > 1 then
		combined = combined.Unit
	end

	-- true = relative to the camera, same as A/D
	player:Move(combined, true)
end)
