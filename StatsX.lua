--[[
	StatsX - Premium Multi-Feature UI
	-------------------------------------------------------------
	States:
	  * OPEN       - full window
	  * MINIMIZED  - collapses into a slim top bar (click to expand)
	  * CLOSED     - window hides, leaving a small arrow at the bottom
	                 of the screen. Click it to pop up a Sirius-style dock
	                 with quick toggles + a button to restore the window.

	Features (all client-side, each with its own config panel via the > arrow):
	  * Fullbright    - brightness slider
	  * Player ESP    - fill transparency slider + name tags toggle
	  * Speed Readout - include-vertical-velocity toggle
	  * WalkSpeed     - speed slider
	  * Jump Power    - power slider
	  * Infinite Jump - no config
	  * FOV Changer   - field-of-view slider
	  * Anti-AFK      - prevents idle kick (no config)
	  * Rainbow UI    - speed + saturation sliders

	Run in an executor (paste & execute) or as a LocalScript in StarterPlayerScripts.
	Pure ASCII - safe to copy/paste.
]]

----------------------------------------------------------------------
-- Services
----------------------------------------------------------------------
local Players          = game:GetService("Players")
local Lighting         = game:GetService("Lighting")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")
local StarterGui       = game:GetService("StarterGui")

local Stats = game:FindService("Stats")
local VirtualUser
pcall(function() VirtualUser = game:GetService("VirtualUser") end)

local LocalPlayer = Players.LocalPlayer

----------------------------------------------------------------------
-- Account Login (key gate)
-- Talks to the StatsX Accounts API (Cloudflare Worker). Nothing below
-- this block runs until the server says the key is valid.
----------------------------------------------------------------------
local GATE = {
	API_URL      = "https://statsx-api.YOURNAME.workers.dev", -- your Worker URL, no trailing slash
	SITE_URL     = "https://synchronizingframes.github.io/StatsX/account.html",
	WORK_INK_URL = "https://work.ink/2EPc/statsx-key-12hr",
	BUILD        = "1.17",
	CACHE_FILE   = "StatsX_session.dat",
	REQUIRE_ACCOUNT_MATCH = true, -- the typed username must be the Roblox account you are playing on
}

local gateDone, gateOK = false, false

do
	local HttpService = game:GetService("HttpService")

	local C = {
		Bg      = Color3.fromRGB(16, 16, 22),
		Bg2     = Color3.fromRGB(22, 22, 30),
		Field   = Color3.fromRGB(29, 29, 39),
		Stroke  = Color3.fromRGB(45, 45, 59),
		Text    = Color3.fromRGB(242, 242, 250),
		Sub     = Color3.fromRGB(140, 140, 158),
		Accent  = Color3.fromRGB(132, 106, 255),
		Ok      = Color3.fromRGB(110, 220, 130),
		Bad     = Color3.fromRGB(235, 90, 100),
	}

	-- ---------- helpers ----------
	local function enc(s) return HttpService:UrlEncode(tostring(s)) end

	local function httpGet(url)
		local ok, body = pcall(function() return game:HttpGet(url, true) end)
		if ok and type(body) == "string" and #body > 0 then return body end
		local req = (typeof(request) == "function" and request)
			or (typeof(http_request) == "function" and http_request)
			or (typeof(syn) == "table" and syn.request)
			or (typeof(fluxus) == "table" and fluxus.request)
		if req then
			local ok2, res = pcall(req, { Url = url, Method = "GET" })
			if ok2 and type(res) == "table" and type(res.Body) == "string" then return res.Body end
		end
		return nil
	end

	local function deviceId()
		local ok, id = pcall(function() return game:GetService("RbxAnalyticsService"):GetClientId() end)
		if ok and type(id) == "string" and #id > 0 then return id end
		if typeof(gethwid) == "function" then
			local ok2, hw = pcall(gethwid)
			if ok2 and type(hw) == "string" and #hw > 0 then return hw end
		end
		return "uid-" .. tostring(LocalPlayer.UserId)
	end
	local HWID = deviceId()

	local function checkKey(user, key)
		if GATE.API_URL:find("YOURNAME", 1, true) then
			return { ok = false, error = "not_configured", message = "API_URL is not set in the script yet." }
		end
		local url = GATE.API_URL .. "/v1/check?u=" .. enc(user) .. "&k=" .. enc(key) .. "&h=" .. enc(HWID) .. "&v=" .. enc(GATE.BUILD)
		local body = httpGet(url)
		if not body then
			return { ok = false, error = "network", message = "Could not reach the StatsX server. Check your connection and try again." }
		end
		local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
		if not ok or type(data) ~= "table" then
			return { ok = false, error = "bad_response", message = "The server sent an unreadable reply. Try again." }
		end
		return data
	end

	local canFile = (typeof(writefile) == "function") and (typeof(readfile) == "function") and (typeof(isfile) == "function")
	local function loadCache()
		if not canFile then return nil end
		local ok, raw = pcall(function() if isfile(GATE.CACHE_FILE) then return readfile(GATE.CACHE_FILE) end end)
		if not ok or type(raw) ~= "string" then return nil end
		local u, k = raw:match("^([^|]+)|([^|\r\n]+)")
		if u and k then return { user = u, key = k } end
		return nil
	end
	local function saveCache(user, key)
		if canFile then pcall(function() writefile(GATE.CACHE_FILE, user .. "|" .. key) end) end
	end
	local function clearCache()
		if canFile and typeof(delfile) == "function" then pcall(function() delfile(GATE.CACHE_FILE) end)
		elseif canFile then pcall(function() writefile(GATE.CACHE_FILE, "") end) end
	end

	local function fmtLeft(ms)
		local s = math.max(0, math.floor((tonumber(ms) or 0) / 1000))
		local h = math.floor(s / 3600); local m = math.floor((s % 3600) / 60)
		if h > 0 then return string.format("%dh %02dm", h, m) end
		return string.format("%dm", m)
	end

	-- ---------- gui ----------
	local ggui = Instance.new("ScreenGui")
	ggui.Name = "StatsXLogin"
	ggui.ResetOnSpawn = false
	ggui.IgnoreGuiInset = true
	ggui.DisplayOrder = 10000
	ggui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	do
		local parentedG = false
		if typeof(gethui) == "function" then
			local ok, h = pcall(gethui)
			if ok and h then ggui.Parent = h; parentedG = true end
		end
		if not parentedG then
			local protector = (typeof(syn) == "table" and syn.protect_gui) or protectgui
			if typeof(protector) == "function" then pcall(protector, ggui) end
			local ok = pcall(function() ggui.Parent = game:GetService("CoreGui") end)
			if ok and ggui.Parent then parentedG = true end
		end
		if not parentedG then ggui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
		for _, g in ipairs(ggui.Parent:GetChildren()) do
			if g ~= ggui and g.Name == "StatsXLogin" then g:Destroy() end
		end
	end

	local function corner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = o; return c end
	local function stroke(o, col, t) local s = Instance.new("UIStroke"); s.Color = col or C.Stroke; s.Thickness = t or 1; s.Parent = o; return s end
	local function gtween(o, ti, props) local tw = game:GetService("TweenService"):Create(o, ti, props); tw:Play(); return tw end
	local TI = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

	local dim = Instance.new("Frame")
	dim.Name = "Dim"; dim.Size = UDim2.fromScale(1, 1); dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1; dim.BorderSizePixel = 0; dim.Parent = ggui
	gtween(dim, TI, { BackgroundTransparency = 0.45 })

	local card = Instance.new("Frame")
	card.Name = "Card"; card.AnchorPoint = Vector2.new(0.5, 0.5); card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(380, 440); card.BackgroundColor3 = C.Bg; card.BorderSizePixel = 0; card.Parent = ggui
	corner(card, 12); local cardStroke = stroke(card, C.Stroke, 1)
	card.BackgroundTransparency = 1
	local scale = Instance.new("UIScale"); scale.Scale = 0.94; scale.Parent = card
	gtween(card, TI, { BackgroundTransparency = 0 }); gtween(scale, TI, { Scale = 1 })

	local topbar = Instance.new("Frame"); topbar.Size = UDim2.new(1, 0, 0, 3); topbar.BackgroundColor3 = C.Accent; topbar.BorderSizePixel = 0; topbar.Parent = card
	corner(topbar, 2)

	local function label(txt, size, col, font, parent)
		local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; l.Text = txt; l.TextSize = size or 13
		l.TextColor3 = col or C.Text; l.Font = font or Enum.Font.Gotham; l.TextXAlignment = Enum.TextXAlignment.Left
		l.Parent = parent or card; return l
	end

	local brand = label("STATSX", 22, C.Text, Enum.Font.GothamBold); brand.Position = UDim2.fromOffset(28, 26); brand.Size = UDim2.fromOffset(200, 26); brand.RichText = true
	brand.Text = 'STATS<font color="#846AFF">X</font>'
	local sub = label("Account login  -  Build " .. GATE.BUILD, 12, C.Sub); sub.Position = UDim2.fromOffset(28, 54); sub.Size = UDim2.fromOffset(300, 16)

	local closeBtn = Instance.new("TextButton"); closeBtn.Size = UDim2.fromOffset(28, 28); closeBtn.Position = UDim2.new(1, -40, 0, 22)
	closeBtn.BackgroundColor3 = C.Field; closeBtn.Text = "x"; closeBtn.TextSize = 14; closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextColor3 = C.Sub; closeBtn.AutoButtonColor = false; closeBtn.Parent = card
	corner(closeBtn, 6)

	local function field(y, cap, ph, default)
		local c = label(cap, 10, C.Sub, Enum.Font.GothamBold); c.Position = UDim2.fromOffset(28, y); c.Size = UDim2.fromOffset(320, 14)
		local box = Instance.new("TextBox"); box.Position = UDim2.fromOffset(28, y + 20); box.Size = UDim2.new(1, -56, 0, 40)
		box.BackgroundColor3 = C.Field; box.TextColor3 = C.Text; box.PlaceholderColor3 = Color3.fromRGB(90, 90, 108); box.PlaceholderText = ph
		box.Text = default or ""; box.Font = Enum.Font.Code; box.TextSize = 14; box.ClearTextOnFocus = false; box.TextXAlignment = Enum.TextXAlignment.Left
		box.Parent = card; corner(box, 8); local st = stroke(box, C.Stroke, 1)
		local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 12); pad.PaddingRight = UDim.new(0, 12); pad.Parent = box
		box.Focused:Connect(function() gtween(st, TI, { Color = C.Accent }) end)
		box.FocusLost:Connect(function() gtween(st, TI, { Color = C.Stroke }) end)
		return box
	end

	local cache = loadCache()
	local userBox = field(90, "ROBLOX USERNAME", "your Roblox username", (cache and cache.user) or LocalPlayer.Name)
	local keyBox  = field(160, "KEY", "STATSX-XXXX-XXXX-XXXX", (cache and cache.key) or "")

	local status = label("", 12, C.Sub); status.Position = UDim2.fromOffset(28, 228); status.Size = UDim2.new(1, -56, 0, 34); status.TextWrapped = true; status.TextYAlignment = Enum.TextYAlignment.Top

	local unlockBtn = Instance.new("TextButton"); unlockBtn.Position = UDim2.fromOffset(28, 268); unlockBtn.Size = UDim2.new(1, -56, 0, 42)
	unlockBtn.BackgroundColor3 = C.Accent; unlockBtn.Text = "UNLOCK"; unlockBtn.TextSize = 13; unlockBtn.Font = Enum.Font.GothamBold
	unlockBtn.TextColor3 = Color3.fromRGB(22, 22, 30); unlockBtn.AutoButtonColor = false; unlockBtn.Parent = card; corner(unlockBtn, 8)

	local getBtn = Instance.new("TextButton"); getBtn.Position = UDim2.fromOffset(28, 318); getBtn.Size = UDim2.new(1, -56, 0, 42)
	getBtn.BackgroundColor3 = C.Bg2; getBtn.Text = "GET FREE KEY  (12H)"; getBtn.TextSize = 12; getBtn.Font = Enum.Font.GothamBold
	getBtn.TextColor3 = C.Text; getBtn.AutoButtonColor = false; getBtn.Parent = card; corner(getBtn, 8); stroke(getBtn, C.Stroke, 1)

	local hint = label("Copies the work.ink link. Finish it, log in on the StatsX site with this username, copy your key back here.", 11, C.Sub)
	hint.Position = UDim2.fromOffset(28, 368); hint.Size = UDim2.new(1, -56, 0, 30); hint.TextWrapped = true; hint.TextYAlignment = Enum.TextYAlignment.Top

	local siteBtn = Instance.new("TextButton"); siteBtn.Position = UDim2.fromOffset(28, 404); siteBtn.Size = UDim2.new(1, -56, 0, 20); siteBtn.BackgroundTransparency = 1
	siteBtn.Text = "copy account page link"; siteBtn.TextSize = 11; siteBtn.Font = Enum.Font.GothamMedium; siteBtn.TextColor3 = C.Accent; siteBtn.TextXAlignment = Enum.TextXAlignment.Left; siteBtn.Parent = card

	local function hover(btn, base, hi)
		btn.MouseEnter:Connect(function() gtween(btn, TI, { BackgroundColor3 = hi }) end)
		btn.MouseLeave:Connect(function() gtween(btn, TI, { BackgroundColor3 = base }) end)
	end
	hover(unlockBtn, C.Accent, Color3.fromRGB(150, 128, 255))
	hover(getBtn, C.Bg2, Color3.fromRGB(32, 32, 44))
	hover(closeBtn, C.Field, Color3.fromRGB(220, 70, 80))

	local function setStatus(txt, kind)
		status.Text = txt or ""
		status.TextColor3 = (kind == "bad" and C.Bad) or (kind == "ok" and C.Ok) or C.Sub
	end

	local function copyText(t)
		local fn = (typeof(setclipboard) == "function" and setclipboard) or (typeof(toclipboard) == "function" and toclipboard)
		if fn then local ok = pcall(fn, t); return ok end
		return false
	end

	getBtn.MouseButton1Click:Connect(function()
		if copyText(GATE.WORK_INK_URL) then
			setStatus("work.ink link copied. Paste it in your browser, finish the steps, then log in on the site to see your key.", "ok")
		else
			setStatus("Open this in your browser: " .. GATE.WORK_INK_URL, "ok")
		end
	end)
	siteBtn.MouseButton1Click:Connect(function()
		if copyText(GATE.SITE_URL) then setStatus("Account page link copied: " .. GATE.SITE_URL, "ok")
		else setStatus(GATE.SITE_URL, "ok") end
	end)

	local function finish(ok)
		gateOK = ok
		gtween(dim, TI, { BackgroundTransparency = 1 })
		gtween(card, TI, { BackgroundTransparency = 1 }); gtween(scale, TI, { Scale = 0.96 })
		for _, d in ipairs(card:GetDescendants()) do
			pcall(function()
				if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then gtween(d, TI, { TextTransparency = 1, BackgroundTransparency = 1 })
				elseif d:IsA("Frame") then gtween(d, TI, { BackgroundTransparency = 1 })
				elseif d:IsA("UIStroke") then gtween(d, TI, { Transparency = 1 }) end
			end)
		end
		task.delay(0.32, function() card:Destroy() end)
		gateDone = true
	end

	local function toast(text)
		local t = Instance.new("TextLabel"); t.AnchorPoint = Vector2.new(0.5, 0); t.Position = UDim2.new(0.5, 0, 0, -40); t.Size = UDim2.fromOffset(420, 34)
		t.BackgroundColor3 = C.Bg; t.Text = text; t.TextSize = 12; t.Font = Enum.Font.GothamMedium; t.TextColor3 = C.Text; t.Parent = ggui
		corner(t, 8); stroke(t, C.Accent, 1)
		gtween(t, TI, { Position = UDim2.new(0.5, 0, 0, 18) })
		task.delay(4, function()
			gtween(t, TI, { Position = UDim2.new(0.5, 0, 0, -40), TextTransparency = 1, BackgroundTransparency = 1 })
			task.delay(0.4, function() ggui:Destroy() end)
		end)
	end

	local busy = false
	local function tryUnlock(silent)
		if busy then return end
		local user = (userBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("^@", "")
		local key = (keyBox.Text or ""):gsub("%s+", ""):upper()
		if user == "" then setStatus("Type your Roblox username.", "bad"); return end
		if GATE.REQUIRE_ACCOUNT_MATCH and user:lower() ~= LocalPlayer.Name:lower() then
			setStatus("You are playing as @" .. LocalPlayer.Name .. ". Keys only work on the account they were made for.", "bad"); return
		end
		if not key:match("^STATSX%-%w%w%w%w%-%w%w%w%w%-%w%w%w%w$") then
			if not silent then setStatus("That does not look like a StatsX key. Copy it from your account page.", "bad") end
			return
		end
		busy = true
		unlockBtn.Text = "CHECKING..."; setStatus("Asking the server...", nil)
		task.spawn(function()
			local res = checkKey(user, key)
			busy = false
			if res.ok then
				saveCache(user, key)
				unlockBtn.Text = "UNLOCKED"; unlockBtn.BackgroundColor3 = C.Ok
				setStatus("Welcome, @" .. tostring(res.user or user) .. ". " .. fmtLeft(res.left) .. " left on this key.", "ok")
				local motd = (type(res.motd) == "string" and res.motd ~= "") and ("  -  " .. res.motd) or ""
				task.delay(0.55, function()
					finish(true)
					toast("StatsX unlocked  -  @" .. tostring(res.user or user) .. "  -  " .. fmtLeft(res.left) .. " left" .. motd)
				end)
			else
				unlockBtn.Text = "UNLOCK"
				if res.error == "expired" or res.error == "invalid_key" or res.error == "revoked" then clearCache() end
				setStatus(tostring(res.message or "Could not verify the key."), "bad")
			end
		end)
	end

	unlockBtn.MouseButton1Click:Connect(function() tryUnlock(false) end)
	keyBox.FocusLost:Connect(function(enter) if enter then tryUnlock(false) end end)
	closeBtn.MouseButton1Click:Connect(function() finish(false); task.delay(0.4, function() ggui:Destroy() end) end)

	if GATE.API_URL:find("YOURNAME", 1, true) then
		setStatus("Setup needed: set GATE.API_URL at the top of the script to your Cloudflare Worker URL.", "bad")
	elseif cache and cache.key ~= "" then
		setStatus("Saved key found. Checking...", nil)
		tryUnlock(true)
	end
end

repeat task.wait() until gateDone
if not gateOK then return end

----------------------------------------------------------------------
-- Robust, executor-safe parenting
----------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "StatsX"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.DisplayOrder = 9999

local parented = false
if typeof(gethui) == "function" then
	local ok, h = pcall(gethui)
	if ok and h then gui.Parent = h; parented = true end
end
if not parented then
	local CoreGui = game:GetService("CoreGui")
	local protector = (typeof(syn) == "table" and syn.protect_gui) or protectgui
	if typeof(protector) == "function" then pcall(protector, gui) end
	local ok = pcall(function() gui.Parent = CoreGui end)
	if ok and gui.Parent then parented = true end
end
if not parented then
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end
for _, g in ipairs(gui.Parent:GetChildren()) do
	if g ~= gui and g.Name == "StatsX" then g:Destroy() end
end

----------------------------------------------------------------------
-- Theme + animation presets
----------------------------------------------------------------------
local THEME = {
	Background = Color3.fromRGB(16, 16, 22),
	Background2= Color3.fromRGB(22, 22, 30),
	Row        = Color3.fromRGB(29, 29, 39),
	RowHover   = Color3.fromRGB(37, 37, 49),
	RowActive  = Color3.fromRGB(33, 33, 45),
	Stroke     = Color3.fromRGB(45, 45, 59),
	Text       = Color3.fromRGB(242, 242, 250),
	SubText    = Color3.fromRGB(140, 140, 158),
	TrackOff   = Color3.fromRGB(55, 55, 70),
}

local DEFAULT_ACCENT = Color3.fromRGB(132, 106, 255)
local accent = DEFAULT_ACCENT

local EASE = {
	Smooth = TweenInfo.new(0.40, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Snappy = TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
	Knob   = TweenInfo.new(0.28, Enum.EasingStyle.Back,  Enum.EasingDirection.Out),
	Hover  = TweenInfo.new(0.16, Enum.EasingStyle.Sine,  Enum.EasingDirection.Out),
	Open   = TweenInfo.new(0.50, Enum.EasingStyle.Back,  Enum.EasingDirection.Out),
	Morph  = TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
}

local destroyed = false
local function tween(obj, info, props)
	local tw = TweenService:Create(obj, info, props)
	tw:Play()
	return tw
end
local function corner(parent, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = parent; return c
end
local function stroke(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color; s.Thickness = thickness or 1; s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent; return s
end
local function gradient(parent, c1, c2, rot)
	local g = Instance.new("UIGradient")
	g.Rotation = rot or 90
	g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, c1), ColorSequenceKeypoint.new(1, c2) })
	g.Parent = parent; return g
end

-- Accent recolor registry
local accentTargets = {}
local function registerAccent(obj) accentTargets[obj] = true end

----------------------------------------------------------------------
-- Feature state (declared up front so loops can see them)
----------------------------------------------------------------------
local fbActive, fbBright = false, 2
local savedLighting

local espActive, espNames, espFill = false, false, 0.55
local espBoxes, espDistance, espHealth = false, false, false
local espStore = {}   -- char -> { hl, tag, nameLbl, distLbl, healthBg, healthFill, box, boxStroke }
local espConns = {}

local showSpeed, speedVertical = false, false

local walkOn,  walkVal = false, 50
local jumpOn,  jumpVal = false, 100
local fovOn,   fovVal  = false, 90
local infOn            = false
local afkConn

local rbConn, rbSpeed, rbSat = nil, 0.12, 0.70

local Features = {}   -- key -> { set=fn, get=fn, color=Color3, short=string }

----------------------------------------------------------------------
-- Main window
----------------------------------------------------------------------
local OPEN_SIZE = UDim2.fromOffset(404, 506)
local OPEN_POS  = UDim2.fromScale(0.5, 0.5)
local BAR_SIZE  = UDim2.fromOffset(280, 54)
local BAR_POS   = UDim2.new(0.5, 0, 0, 42)

local main = Instance.new("Frame")
main.Name = "Main"
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.Position = OPEN_POS
main.Size = OPEN_SIZE
main.BackgroundColor3 = THEME.Background
main.BorderSizePixel = 0
main.ClipsDescendants = true
main.Parent = gui
corner(main, 18)
local mainStroke = stroke(main, accent, 1.5, 0.25)
registerAccent(mainStroke)
gradient(main, THEME.Background2, THEME.Background, 90)

local topBar = Instance.new("Frame")
topBar.Size = UDim2.new(1, -36, 0, 3)
topBar.Position = UDim2.fromOffset(18, 0)
topBar.BackgroundColor3 = accent
topBar.BorderSizePixel = 0
topBar.Parent = main
corner(topBar, 2)
registerAccent(topBar)

-- Header
local header = Instance.new("Frame")
header.Name = "Header"
header.BackgroundTransparency = 1
header.Size = UDim2.new(1, 0, 0, 54)
header.Position = UDim2.fromOffset(0, 4)
header.Parent = main

local dot = Instance.new("Frame")
dot.Size = UDim2.fromOffset(10, 10)
dot.Position = UDim2.fromOffset(20, 22)
dot.BackgroundColor3 = accent
dot.BorderSizePixel = 0
dot.Parent = header
corner(dot, 5)
registerAccent(dot)
stroke(dot, accent, 4, 0.6)

local brand = Instance.new("TextLabel")
brand.BackgroundTransparency = 1
brand.Position = UDim2.fromOffset(40, 14)
brand.Size = UDim2.new(1, -130, 0, 26)
brand.Font = Enum.Font.GothamBold
brand.Text = "StatsX"
brand.TextColor3 = THEME.Text
brand.TextSize = 20
brand.TextXAlignment = Enum.TextXAlignment.Left
brand.Parent = header

local function headerBtn(symbol, xoff)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(30, 30)
	b.Position = UDim2.new(1, xoff, 0, 13)
	b.BackgroundColor3 = THEME.Row
	b.Text = symbol
	b.TextColor3 = THEME.Text
	b.TextSize = 18
	b.Font = Enum.Font.GothamBold
	b.AutoButtonColor = false
	b.Parent = header
	corner(b, 8)
	stroke(b, THEME.Stroke, 1, 0.3)
	return b
end
local closeBtn = headerBtn("X", -42)
local minBtn   = headerBtn("-", -80)
closeBtn.MouseEnter:Connect(function() tween(closeBtn, EASE.Hover, { BackgroundColor3 = Color3.fromRGB(220, 70, 80) }) end)
closeBtn.MouseLeave:Connect(function() tween(closeBtn, EASE.Hover, { BackgroundColor3 = THEME.Row }) end)
minBtn.MouseEnter:Connect(function() tween(minBtn, EASE.Hover, { BackgroundColor3 = Color3.fromRGB(235, 185, 60) }) end)
minBtn.MouseLeave:Connect(function() tween(minBtn, EASE.Hover, { BackgroundColor3 = THEME.Row }) end)

-- Body (clipped; collapses for minimize)
local body = Instance.new("Frame")
body.Name = "Body"
body.BackgroundTransparency = 1
body.ClipsDescendants = true
body.Position = UDim2.fromOffset(0, 54)
body.Size = UDim2.new(1, 0, 1, -54)
body.Parent = main

-- Welcome banner with circled profile picture
local welcome = Instance.new("Frame")
welcome.BackgroundTransparency = 1
welcome.Position = UDim2.fromOffset(0, 6)
welcome.Size = UDim2.new(1, 0, 0, 58)
welcome.Parent = body

local pfp = Instance.new("ImageLabel")
pfp.Size = UDim2.fromOffset(46, 46)
pfp.Position = UDim2.fromOffset(20, 6)
pfp.BackgroundColor3 = THEME.Row
pfp.Parent = welcome
corner(pfp, 23)
local pfpRing = stroke(pfp, accent, 2.5, 0)
registerAccent(pfpRing)
task.spawn(function()
	local ok, content = pcall(function()
		return Players:GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size180x180)
	end)
	if ok and content then pfp.Image = content end
end)

local wTitle = Instance.new("TextLabel")
wTitle.BackgroundTransparency = 1
wTitle.Position = UDim2.fromOffset(78, 10)
wTitle.Size = UDim2.new(1, -98, 0, 22)
wTitle.Font = Enum.Font.GothamBold
wTitle.Text = "Welcome, " .. (LocalPlayer.DisplayName or LocalPlayer.Name) .. "!"
wTitle.TextColor3 = THEME.Text
wTitle.TextSize = 16
wTitle.TextXAlignment = Enum.TextXAlignment.Left
wTitle.Parent = welcome

local wSub = Instance.new("TextLabel")
wSub.BackgroundTransparency = 1
wSub.Position = UDim2.fromOffset(78, 30)
wSub.Size = UDim2.new(1, -98, 0, 16)
wSub.Font = Enum.Font.Gotham
wSub.Text = "@" .. LocalPlayer.Name
wSub.TextColor3 = THEME.SubText
wSub.TextSize = 12
wSub.TextXAlignment = Enum.TextXAlignment.Left
wSub.Parent = welcome

local wDivider = Instance.new("Frame")
wDivider.Size = UDim2.new(1, -40, 0, 1)
wDivider.Position = UDim2.fromOffset(20, 64)
wDivider.BackgroundColor3 = THEME.Stroke
wDivider.BorderSizePixel = 0
wDivider.Parent = body

-- Scrolling list of features
local list = Instance.new("ScrollingFrame")
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.Position = UDim2.fromOffset(0, 148)
list.Size = UDim2.new(1, 0, 1, -186)
list.ScrollBarThickness = 4
list.ScrollBarImageColor3 = accent
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ScrollingDirection = Enum.ScrollingDirection.Y
list.Parent = body
local listPad = Instance.new("UIPadding")
listPad.PaddingLeft = UDim.new(0, 18); listPad.PaddingRight = UDim.new(0, 18)
listPad.PaddingTop = UDim.new(0, 2);  listPad.PaddingBottom = UDim.new(0, 10)
listPad.Parent = list
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 10)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

-- Footer (live stats)
local footer = Instance.new("Frame")
footer.BackgroundTransparency = 1
footer.AnchorPoint = Vector2.new(0, 1)
footer.Position = UDim2.new(0, 0, 1, 0)
footer.Size = UDim2.new(1, 0, 0, 34)
footer.Parent = body
local statusLbl = Instance.new("TextLabel")
statusLbl.BackgroundTransparency = 1
statusLbl.Position = UDim2.fromOffset(20, 0)
statusLbl.Size = UDim2.new(1, -40, 1, 0)
statusLbl.Font = Enum.Font.Gotham
statusLbl.Text = "FPS: --   Ping: -- ms"
statusLbl.TextColor3 = THEME.SubText
statusLbl.TextSize = 12
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Parent = footer

----------------------------------------------------------------------
-- Tabs (genre groups) + row registry
----------------------------------------------------------------------
local TAB_NAMES = { "Visuals", "Movement", "Player", "Hubs" }
local TAB_OF = {
	fullbright = "Visuals", esp = "Visuals", fov = "Visuals", rainbow = "Visuals", clean = "Visuals",
	walk = "Movement", jump = "Movement", infjump = "Movement", fly = "Movement", noclip = "Movement", gravity = "Movement",
	speed = "Player", afk = "Player", visibility = "Player", aimlock = "Player",
}
local tabRows = {}
local tabButtons = {}
local allRows = {}
local activeTab = "Visuals"

local tabBar = Instance.new("Frame")
tabBar.Name = "TabBar"
tabBar.BackgroundColor3 = THEME.Row
tabBar.BorderSizePixel = 0
tabBar.Position = UDim2.fromOffset(18, 72)
tabBar.Size = UDim2.new(1, -76, 0, 34)
tabBar.Parent = body
corner(tabBar, 10)
local tabBarPad = Instance.new("UIPadding")
tabBarPad.PaddingLeft = UDim.new(0, 4); tabBarPad.PaddingRight = UDim.new(0, 4)
tabBarPad.PaddingTop = UDim.new(0, 4); tabBarPad.PaddingBottom = UDim.new(0, 4)
tabBarPad.Parent = tabBar
local tabBarLayout = Instance.new("UIListLayout")
tabBarLayout.FillDirection = Enum.FillDirection.Horizontal
tabBarLayout.Padding = UDim.new(0, 4)
tabBarLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabBarLayout.Parent = tabBar

local function selectTab(name)
	activeTab = name
	for tabName, rows in pairs(tabRows) do
		for _, c in ipairs(rows) do c.Visible = (tabName == name) end
	end
	for tabName, btn in pairs(tabButtons) do
		local on = tabName == name
		tween(btn, EASE.Hover, { BackgroundColor3 = on and accent or THEME.Row })
		btn.TextColor3 = on and Color3.fromRGB(22, 22, 30) or THEME.SubText
		if on then accentTargets[btn] = true else accentTargets[btn] = nil end
	end
	list.CanvasPosition = Vector2.new(0, 0)
end

for i, name in ipairs(TAB_NAMES) do
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = UDim2.new(1 / #TAB_NAMES, -4, 1, 0)
	btn.BackgroundColor3 = THEME.Row
	btn.Text = name
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 13
	btn.TextColor3 = THEME.SubText
	btn.AutoButtonColor = false
	btn.LayoutOrder = i
	btn.Parent = tabBar
	corner(btn, 8)
	tabButtons[name] = btn
	btn.MouseButton1Click:Connect(function() selectTab(name) end)
end

----------------------------------------------------------------------
-- Hubs tab: external game hubs that load through StatsX
-- Wrapped in an IIFE so its locals do not count against Luau's 200 main-chunk register limit
----------------------------------------------------------------------
;(function()
	local HUB_LIST = {
		{
			name = "TSB Hub",
			by = "The Strongest Battlegrounds",
			icon = "\240\159\145\138",
			url = "https://gist.githubusercontent.com/SynchronizingFrames/ef4bce240bb0ac17a19186dc265b9234/raw/Build1.16TSBHub.obf.lua",
		},
	}
	local function registerHubRow(frame, order)
		frame.LayoutOrder = order
		frame.Parent = list
		tabRows["Hubs"] = tabRows["Hubs"] or {}
		table.insert(tabRows["Hubs"], frame)
		table.insert(allRows, frame)
		frame.Visible = (activeTab == "Hubs")
	end

	local note = Instance.new("Frame")
	note.Name = "HubsNote"
	note.Size = UDim2.new(1, 0, 0, 50)
	note.BackgroundColor3 = THEME.Row
	note.BorderSizePixel = 0
	corner(note, 12)
	local noteLbl = Instance.new("TextLabel")
	noteLbl.BackgroundTransparency = 1
	noteLbl.Position = UDim2.fromOffset(14, 0)
	noteLbl.Size = UDim2.new(1, -28, 1, 0)
	noteLbl.Font = Enum.Font.Gotham
	noteLbl.TextSize = 12
	noteLbl.Text = "Game-specific hubs by StatsX. Open the matching game, then press Load."
	noteLbl.TextColor3 = THEME.SubText
	noteLbl.TextWrapped = true
	noteLbl.TextXAlignment = Enum.TextXAlignment.Left
	noteLbl.Parent = note
	registerHubRow(note, 1)

	for i, hub in ipairs(HUB_LIST) do
		local card = Instance.new("Frame")
		card.Name = hub.name
		card.Size = UDim2.new(1, 0, 0, 64)
		card.BackgroundColor3 = THEME.Row
		card.BorderSizePixel = 0
		corner(card, 12)
		stroke(card, accent, 1.2, 0.55)

		local ic = Instance.new("TextLabel")
		ic.BackgroundTransparency = 1
		ic.Position = UDim2.fromOffset(14, 0)
		ic.Size = UDim2.fromOffset(40, 64)
		ic.Font = Enum.Font.GothamBold
		ic.TextSize = 26
		ic.Text = hub.icon
		ic.TextColor3 = THEME.Text
		ic.Parent = card

		local nm = Instance.new("TextLabel")
		nm.BackgroundTransparency = 1
		nm.Position = UDim2.fromOffset(60, 13)
		nm.Size = UDim2.new(1, -180, 0, 20)
		nm.Font = Enum.Font.GothamBold
		nm.TextSize = 15
		nm.Text = hub.name
		nm.TextColor3 = THEME.Text
		nm.TextXAlignment = Enum.TextXAlignment.Left
		nm.Parent = card

		local byLbl = Instance.new("TextLabel")
		byLbl.BackgroundTransparency = 1
		byLbl.Position = UDim2.fromOffset(60, 33)
		byLbl.Size = UDim2.new(1, -180, 0, 16)
		byLbl.Font = Enum.Font.GothamMedium
		byLbl.TextSize = 12
		byLbl.Text = hub.by
		byLbl.TextColor3 = THEME.SubText
		byLbl.TextXAlignment = Enum.TextXAlignment.Left
		byLbl.Parent = card

		local loadBtn = Instance.new("TextButton")
		loadBtn.AnchorPoint = Vector2.new(1, 0.5)
		loadBtn.Position = UDim2.new(1, -14, 0.5, 0)
		loadBtn.Size = UDim2.fromOffset(96, 34)
		loadBtn.BackgroundColor3 = accent
		loadBtn.AutoButtonColor = false
		loadBtn.Font = Enum.Font.GothamBold
		loadBtn.TextSize = 13
		loadBtn.Text = "Load"
		loadBtn.TextColor3 = Color3.fromRGB(22, 22, 30)
		loadBtn.Parent = card
		corner(loadBtn, 8)
		loadBtn.MouseEnter:Connect(function() tween(loadBtn, EASE.Hover, { Size = UDim2.fromOffset(102, 36) }) end)
		loadBtn.MouseLeave:Connect(function() tween(loadBtn, EASE.Hover, { Size = UDim2.fromOffset(96, 34) }) end)
		loadBtn.MouseButton1Click:Connect(function()
			loadBtn.Text = "..."
			local ok, err = pcall(function()
				loadstring(game:HttpGet(hub.url))()
			end)
			loadBtn.Text = ok and "Loaded" or "Failed"
			if not ok then warn("[StatsX] Hub load failed: " .. tostring(err)) end
			task.wait(1.5)
			loadBtn.Text = "Load"
		end)

		registerHubRow(card, i + 1)
	end
end)()

----------------------------------------------------------------------
-- Components: slider + checkbox
----------------------------------------------------------------------
local function createSlider(parent, opts)
	-- opts: name, min, max, default, suffix, decimals, onChange, order
	local holder = Instance.new("Frame")
	holder.Name = "Slider"
	holder.Size = UDim2.new(1, 0, 0, 40)
	holder.BackgroundTransparency = 1
	holder.LayoutOrder = opts.order or 1
	holder.Parent = parent

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, -64, 0, 16)
	name.Font = Enum.Font.Gotham
	name.Text = opts.name
	name.TextColor3 = THEME.SubText
	name.TextSize = 12
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = holder

	local valLbl = Instance.new("TextLabel")
	valLbl.BackgroundTransparency = 1
	valLbl.AnchorPoint = Vector2.new(1, 0)
	valLbl.Position = UDim2.new(1, 0, 0, 0)
	valLbl.Size = UDim2.new(0, 64, 0, 16)
	valLbl.Font = Enum.Font.GothamMedium
	valLbl.TextColor3 = THEME.Text
	valLbl.TextSize = 12
	valLbl.TextXAlignment = Enum.TextXAlignment.Right
	valLbl.Parent = holder

	local track = Instance.new("Frame")
	track.Position = UDim2.fromOffset(0, 24)
	track.Size = UDim2.new(1, 0, 0, 8)
	track.BackgroundColor3 = THEME.TrackOff
	track.BorderSizePixel = 0
	track.Parent = holder
	corner(track, 4)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = accent
	fill.BorderSizePixel = 0
	fill.Parent = track
	corner(fill, 4)
	registerAccent(fill)

	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.new(0, 0, 0.5, 0)
	knob.Size = UDim2.fromOffset(14, 14)
	knob.BackgroundColor3 = Color3.fromRGB(245, 245, 250)
	knob.BorderSizePixel = 0
	knob.ZIndex = 2
	knob.Parent = track
	corner(knob, 7)

	local decimals = opts.decimals or 0
	local function roundv(v)
		local m = 10 ^ decimals
		return math.floor(v * m + 0.5) / m
	end
	local value = opts.default
	local dragging = false
	local function render(v)
		local rel = math.clamp((v - opts.min) / (opts.max - opts.min), 0, 1)
		fill.Size = UDim2.new(rel, 0, 1, 0)
		knob.Position = UDim2.new(rel, 0, 0.5, 0)
		valLbl.Text = tostring(roundv(v)) .. (opts.suffix or "")
	end
	local function setFromX(px)
		local rel = math.clamp((px - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		value = roundv(opts.min + (opts.max - opts.min) * rel)
		render(value)
		if opts.onChange then opts.onChange(value) end
	end
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true; tween(knob, EASE.Hover, { Size = UDim2.fromOffset(18, 18) }); setFromX(input.Position.X)
		end
	end)
	track.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false; tween(knob, EASE.Hover, { Size = UDim2.fromOffset(14, 14) })
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	render(value)
	return holder
end

local function createCheckbox(parent, opts)
	-- opts: name, default, onChange, order
	local holder = Instance.new("TextButton")
	holder.AutoButtonColor = false
	holder.Text = ""
	holder.Size = UDim2.new(1, 0, 0, 26)
	holder.BackgroundTransparency = 1
	holder.LayoutOrder = opts.order or 1
	holder.Parent = parent

	local box = Instance.new("Frame")
	box.Size = UDim2.fromOffset(18, 18)
	box.Position = UDim2.fromOffset(0, 4)
	box.BackgroundColor3 = THEME.TrackOff
	box.BorderSizePixel = 0
	box.Parent = holder
	corner(box, 5)
	local check = Instance.new("Frame")
	check.AnchorPoint = Vector2.new(0.5, 0.5)
	check.Position = UDim2.new(0.5, 0, 0.5, 0)
	check.Size = UDim2.fromOffset(0, 0)
	check.BackgroundColor3 = accent
	check.BorderSizePixel = 0
	check.Parent = box
	corner(check, 3)
	registerAccent(check)

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Position = UDim2.fromOffset(28, 0)
	lbl.Size = UDim2.new(1, -28, 1, 0)
	lbl.Font = Enum.Font.Gotham
	lbl.Text = opts.name
	lbl.TextColor3 = THEME.SubText
	lbl.TextSize = 12
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = holder

	local state = opts.default or false
	local function render() tween(check, EASE.Snappy, { Size = state and UDim2.fromOffset(11, 11) or UDim2.fromOffset(0, 0) }) end
	holder.MouseButton1Click:Connect(function()
		state = not state; render()
		if opts.onChange then opts.onChange(state) end
	end)
	render()
	return holder
end

local function createButton(parent, opts)
	-- opts: name, onClick, order
	local btn = Instance.new("TextButton")
	btn.AutoButtonColor = false
	btn.Size = UDim2.new(1, 0, 0, 30)
	btn.BackgroundColor3 = THEME.Row
	btn.Text = opts.name
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 13
	btn.TextColor3 = THEME.Text
	btn.LayoutOrder = opts.order or 1
	btn.Parent = parent
	corner(btn, 8)
	stroke(btn, THEME.Stroke, 1, 0.3)
	btn.MouseEnter:Connect(function() tween(btn, EASE.Hover, { BackgroundColor3 = THEME.RowHover }) end)
	btn.MouseLeave:Connect(function() tween(btn, EASE.Hover, { BackgroundColor3 = THEME.Row }) end)
	btn.MouseButton1Click:Connect(function() if opts.onClick then opts.onClick() end end)
	return btn
end

local capturingKey = false
local function keyName(code)
	if not code then return "None" end
	return (tostring(code):gsub("Enum.KeyCode.", ""))
end
local function createKeybindButton(parent, opts)
	-- opts: name, default (Enum.KeyCode or nil), onChange(code), order
	local holder = Instance.new("TextButton")
	holder.AutoButtonColor = false
	holder.Text = ""
	holder.Size = UDim2.new(1, 0, 0, 30)
	holder.BackgroundTransparency = 1
	holder.LayoutOrder = opts.order or 1
	holder.Parent = parent

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(1, -150, 1, 0)
	lbl.Font = Enum.Font.Gotham
	lbl.Text = opts.name
	lbl.TextColor3 = THEME.SubText
	lbl.TextSize = 12
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = holder

	local current = opts.default

	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, 0, 0.5, 0)
	btn.Size = UDim2.fromOffset(72, 26)
	btn.BackgroundColor3 = THEME.TrackOff
	btn.AutoButtonColor = false
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 13
	btn.TextColor3 = current and THEME.Text or THEME.SubText
	btn.Text = keyName(current)
	btn.Parent = holder
	corner(btn, 7)
	local bStroke = stroke(btn, accent, 1.2, 1)

	local clearBtn = Instance.new("TextButton")
	clearBtn.AnchorPoint = Vector2.new(1, 0.5)
	clearBtn.Position = UDim2.new(1, -82, 0.5, 0)
	clearBtn.Size = UDim2.fromOffset(24, 24)
	clearBtn.BackgroundColor3 = THEME.TrackOff
	clearBtn.AutoButtonColor = false
	clearBtn.Font = Enum.Font.GothamBold
	clearBtn.TextSize = 14
	clearBtn.TextColor3 = THEME.SubText
	clearBtn.Text = "x"
	clearBtn.Parent = holder
	corner(clearBtn, 7)

	local function setKey(code)
		current = code
		btn.Text = keyName(current)
		btn.TextColor3 = current and THEME.Text or THEME.SubText
		if opts.onChange then opts.onChange(current) end
	end
	clearBtn.MouseEnter:Connect(function() tween(clearBtn, EASE.Hover, { BackgroundColor3 = Color3.fromRGB(220, 70, 80) }) end)
	clearBtn.MouseLeave:Connect(function() tween(clearBtn, EASE.Hover, { BackgroundColor3 = THEME.TrackOff }) end)
	clearBtn.MouseButton1Click:Connect(function()
		setKey(nil)
		tween(bStroke, EASE.Snappy, { Transparency = 1 })
	end)
	btn.MouseButton1Click:Connect(function()
		btn.Text = "..."
		capturingKey = true
		tween(bStroke, EASE.Snappy, { Transparency = 0 })
		local conn
		conn = UserInputService.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
			local code = input.KeyCode
			if code == Enum.KeyCode.Escape then
				btn.Text = keyName(current)
			elseif code == Enum.KeyCode.Backspace or code == Enum.KeyCode.Delete then
				setKey(nil)
			else
				setKey(code)
			end
			tween(bStroke, EASE.Snappy, { Transparency = 1 })
			capturingKey = false
			conn:Disconnect()
		end)
	end)
	return holder
end

local function createSegmented(parent, opts)
	-- opts: name, options (array), default, onChange, order
	local holder = Instance.new("Frame")
	holder.Name = "Segmented"
	holder.Size = UDim2.new(1, 0, 0, 48)
	holder.BackgroundTransparency = 1
	holder.LayoutOrder = opts.order or 1
	holder.Parent = parent

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 16)
	name.Font = Enum.Font.Gotham
	name.Text = opts.name
	name.TextColor3 = THEME.SubText
	name.TextSize = 12
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = holder

	local bar = Instance.new("Frame")
	bar.Position = UDim2.fromOffset(0, 20)
	bar.Size = UDim2.new(1, 0, 0, 26)
	bar.BackgroundColor3 = THEME.TrackOff
	bar.BorderSizePixel = 0
	bar.Parent = holder
	corner(bar, 8)
	local bpad = Instance.new("UIPadding")
	bpad.PaddingLeft = UDim.new(0, 3); bpad.PaddingRight = UDim.new(0, 3)
	bpad.PaddingTop = UDim.new(0, 3); bpad.PaddingBottom = UDim.new(0, 3)
	bpad.Parent = bar
	local blay = Instance.new("UIListLayout")
	blay.FillDirection = Enum.FillDirection.Horizontal
	blay.Padding = UDim.new(0, 3)
	blay.SortOrder = Enum.SortOrder.LayoutOrder
	blay.Parent = bar

	local btns = {}
	local current = opts.default
	local function refresh()
		for opt, b in pairs(btns) do
			local on = opt == current
			tween(b, EASE.Hover, { BackgroundColor3 = on and accent or THEME.Row })
			b.TextColor3 = on and Color3.fromRGB(22, 22, 30) or THEME.SubText
			if on then accentTargets[b] = true else accentTargets[b] = nil end
		end
	end
	for i, opt in ipairs(opts.options) do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1 / #opts.options, -3, 1, 0)
		b.BackgroundColor3 = THEME.Row
		b.Text = opt
		b.Font = Enum.Font.GothamMedium
		b.TextSize = 12
		b.TextColor3 = THEME.SubText
		b.AutoButtonColor = false
		b.LayoutOrder = i
		b.Parent = bar
		corner(b, 6)
		btns[opt] = b
		b.MouseButton1Click:Connect(function()
			current = opt
			refresh()
			if opts.onChange then opts.onChange(opt) end
		end)
	end
	refresh()
	return holder
end

----------------------------------------------------------------------
-- Component: toggle row with expandable config
----------------------------------------------------------------------
local function createToggle(opts)
	-- opts: key, name, desc, color, short, onEnable, onDisable, buildConfig, order
	local container = Instance.new("Frame")
	container.Name = opts.key
	container.Size = UDim2.new(1, 0, 0, 56)
	container.BackgroundColor3 = THEME.Row
	container.BorderSizePixel = 0
	container.ClipsDescendants = true
	container.LayoutOrder = opts.order
	container.Parent = list
	corner(container, 12)
	local _tab = TAB_OF[opts.key] or "Player"
	tabRows[_tab] = tabRows[_tab] or {}
	table.insert(tabRows[_tab], container)
	table.insert(allRows, container)
	local cStroke = stroke(container, accent, 1.2, 1)

	local hit = Instance.new("TextButton")
	hit.AutoButtonColor = false
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.new(1, 0, 0, 56)
	hit.Parent = container

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(16, 10)
	label.Size = UDim2.new(1, -110, 0, 20)
	label.Font = Enum.Font.GothamMedium
	label.Text = opts.name
	label.TextColor3 = THEME.Text
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = hit

	if opts.badge then
		local tw = 0
		pcall(function()
			tw = game:GetService("TextService"):GetTextSize(opts.name, 14, Enum.Font.GothamMedium, Vector2.new(400, 20)).X
		end)
		local badge = Instance.new("TextLabel")
		badge.BackgroundColor3 = accent
		badge.Position = UDim2.fromOffset(16 + tw + 8, 11)
		badge.Size = UDim2.fromOffset(38, 16)
		badge.Font = Enum.Font.GothamBold
		badge.Text = opts.badge
		badge.TextColor3 = Color3.fromRGB(255, 255, 255)
		badge.TextSize = 9
		badge.Parent = hit
		corner(badge, 5)
		registerAccent(badge)
	end

	local desc = Instance.new("TextLabel")
	desc.BackgroundTransparency = 1
	desc.Position = UDim2.fromOffset(16, 30)
	desc.Size = UDim2.new(1, -110, 0, 16)
	desc.Font = Enum.Font.Gotham
	desc.Text = opts.desc
	desc.TextColor3 = THEME.SubText
	desc.TextSize = 11
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.Parent = hit

	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.new(1, -16, 0, 28)
	track.Size = UDim2.fromOffset(50, 26)
	track.BackgroundColor3 = THEME.TrackOff
	track.BorderSizePixel = 0
	track.ZIndex = 2
	track.Parent = container
	corner(track, 13)
	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Position = UDim2.new(0, 3, 0.5, 0)
	knob.Size = UDim2.fromOffset(20, 20)
	knob.BackgroundColor3 = Color3.fromRGB(245, 245, 250)
	knob.BorderSizePixel = 0
	knob.Parent = track
	corner(knob, 10)
	local knobGlow = stroke(knob, accent, 0, 1)

	local gear
	local cfg, cfgLayout
	if opts.buildConfig then
		gear = Instance.new("TextButton")
		gear.AutoButtonColor = false
		gear.Text = ">"
		gear.Font = Enum.Font.GothamBold
		gear.TextSize = 16
		gear.TextColor3 = THEME.SubText
		gear.BackgroundTransparency = 1
		gear.AnchorPoint = Vector2.new(1, 0.5)
		gear.Position = UDim2.new(1, -74, 0, 28)
		gear.Size = UDim2.fromOffset(24, 24)
		gear.ZIndex = 3
		gear.Parent = container

		cfg = Instance.new("Frame")
		cfg.Name = "Config"
		cfg.BackgroundTransparency = 1
		cfg.Position = UDim2.fromOffset(0, 58)
		cfg.Size = UDim2.new(1, 0, 0, 300)
		cfg.Parent = container
		local cp = Instance.new("UIPadding")
		cp.PaddingLeft = UDim.new(0, 16); cp.PaddingRight = UDim.new(0, 16)
		cp.PaddingTop = UDim.new(0, 2);  cp.PaddingBottom = UDim.new(0, 12)
		cp.Parent = cfg
		cfgLayout = Instance.new("UIListLayout")
		cfgLayout.Padding = UDim.new(0, 6)
		cfgLayout.SortOrder = Enum.SortOrder.LayoutOrder
		cfgLayout.Parent = cfg
		opts.buildConfig(cfg)
	end

	local state = false
	local function applyVisual(on)
		tween(track, EASE.Snappy, { BackgroundColor3 = on and accent or THEME.TrackOff })
		tween(knob, EASE.Knob, { Position = on and UDim2.new(1, -23, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) })
		tween(container, EASE.Snappy, { BackgroundColor3 = on and THEME.RowActive or THEME.Row })
		tween(cStroke, EASE.Snappy, { Transparency = on and 0.35 or 1 })
		tween(knobGlow, EASE.Snappy, { Transparency = on and 0.1 or 1, Thickness = on and 2.5 or 0 })
		if on then
			accentTargets[track] = true
			accentTargets[cStroke] = true
			accentTargets[knobGlow] = true
		else
			accentTargets[track] = nil
			accentTargets[cStroke] = nil
			accentTargets[knobGlow] = nil
		end
	end
	local function setState(on)
		if on == state then return end
		state = on
		applyVisual(on)
		local ok, err = pcall(function()
			if on then
				if opts.onEnable then opts.onEnable() end
			else
				if opts.onDisable then opts.onDisable() end
			end
		end)
		if not ok then warn("[StatsX] " .. opts.name .. " error: " .. tostring(err)) end
	end
	hit.MouseButton1Click:Connect(function() setState(not state) end)
	hit.MouseEnter:Connect(function()
		if not state then
			tween(container, EASE.Hover, { BackgroundColor3 = THEME.RowHover })
			tween(cStroke, EASE.Hover, { Transparency = 0.6 })
		end
	end)
	hit.MouseLeave:Connect(function()
		if not state then
			tween(container, EASE.Hover, { BackgroundColor3 = THEME.Row })
			tween(cStroke, EASE.Hover, { Transparency = 1 })
		end
	end)

	if gear then
		local open = false
		gear.MouseButton1Click:Connect(function()
			open = not open
			local h = open and (cfgLayout.AbsoluteContentSize.Y + 16) or 0
			tween(container, EASE.Smooth, { Size = UDim2.new(1, 0, 0, 56 + h) })
			tween(gear, EASE.Smooth, { Rotation = open and 90 or 0, TextColor3 = open and accent or THEME.SubText })
		end)
		gear.MouseEnter:Connect(function() tween(gear, EASE.Hover, { TextColor3 = THEME.Text }) end)
		gear.MouseLeave:Connect(function() tween(gear, EASE.Hover, { TextColor3 = open and accent or THEME.SubText }) end)
	end

	Features[opts.key] = {
		set = setState,
		get = function() return state end,
		color = opts.color or accent,
		short = opts.short or string.sub(opts.name, 1, 2),
		name = opts.name,
		key = opts.key,
	}
	return setState
end

----------------------------------------------------------------------
-- Helper: recolor everything to current accent
----------------------------------------------------------------------
local function recolorAll()
	for obj in pairs(accentTargets) do
		if obj and obj.Parent then
			if obj:IsA("UIStroke") then
				obj.Color = accent
			else
				obj.BackgroundColor3 = accent
			end
		end
	end
	list.ScrollBarImageColor3 = accent
	if espActive then
		for _, rec in pairs(espStore) do
			if rec.hl then rec.hl.FillColor = accent end
			if rec.boxStroke then rec.boxStroke.Color = accent end
		end
	end
end

----------------------------------------------------------------------
-- Feature implementations
----------------------------------------------------------------------
local function getHumanoid()
	local char = LocalPlayer.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

-- Fullbright
----------------------------------------------------------------------
-- Feature implementations + toggle definitions.
-- Wrapped in an IIFE so these ~64 locals live in this function's own
-- 200-register frame instead of the main chunk's. Without this the main
-- chunk sits at 199/200 and the obfuscator's own added locals overflow it.
-- cleanOn / applyClean are declared above the wrapper because
-- closeToArrow() further down reads them.
----------------------------------------------------------------------
local cleanOn, applyClean
;(function()
local function applyFullbright()
	Lighting.Brightness = fbBright
	Lighting.ClockTime = 14
	Lighting.FogEnd = 1e9
	Lighting.GlobalShadows = false
	Lighting.Ambient = Color3.fromRGB(178, 178, 178)
	Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
end
local function fbOn()
	fbActive = true
	savedLighting = {
		Brightness = Lighting.Brightness,
		ClockTime = Lighting.ClockTime,
		FogEnd = Lighting.FogEnd,
		GlobalShadows = Lighting.GlobalShadows,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
	}
	applyFullbright()
end
local function fbOff()
	fbActive = false
	if savedLighting then
		Lighting.Brightness = savedLighting.Brightness
		Lighting.ClockTime = savedLighting.ClockTime
		Lighting.FogEnd = savedLighting.FogEnd
		Lighting.GlobalShadows = savedLighting.GlobalShadows
		Lighting.Ambient = savedLighting.Ambient
		Lighting.OutdoorAmbient = savedLighting.OutdoorAmbient
	end
end

-- ESP
local function makeInfo(char)
	local head = char:FindFirstChild("Head")
	if not head then return end
	local plr = Players:GetPlayerFromCharacter(char)
	local bb = Instance.new("BillboardGui")
	bb.Name = "StatsXTag"
	bb.Size = UDim2.fromOffset(170, 48)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = head
	bb.Parent = head

	local nameLbl = Instance.new("TextLabel")
	nameLbl.BackgroundTransparency = 1
	nameLbl.Size = UDim2.new(1, 0, 0, 16)
	nameLbl.Font = Enum.Font.GothamBold
	nameLbl.TextSize = 14
	nameLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLbl.TextStrokeTransparency = 0.4
	nameLbl.Text = plr and (plr.DisplayName or plr.Name) or "?"
	nameLbl.Parent = bb

	local distLbl = Instance.new("TextLabel")
	distLbl.BackgroundTransparency = 1
	distLbl.Position = UDim2.fromOffset(0, 16)
	distLbl.Size = UDim2.new(1, 0, 0, 12)
	distLbl.Font = Enum.Font.Gotham
	distLbl.TextSize = 11
	distLbl.TextColor3 = Color3.fromRGB(205, 205, 218)
	distLbl.TextStrokeTransparency = 0.5
	distLbl.Text = ""
	distLbl.Parent = bb

	local healthBg = Instance.new("Frame")
	healthBg.AnchorPoint = Vector2.new(0.5, 0)
	healthBg.Position = UDim2.new(0.5, 0, 0, 33)
	healthBg.Size = UDim2.fromOffset(74, 5)
	healthBg.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	healthBg.BorderSizePixel = 0
	healthBg.Parent = bb
	corner(healthBg, 3)
	local healthFill = Instance.new("Frame")
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BackgroundColor3 = Color3.fromRGB(80, 220, 120)
	healthFill.BorderSizePixel = 0
	healthFill.Parent = healthBg
	corner(healthFill, 3)

	return bb, nameLbl, distLbl, healthBg, healthFill
end
local function makeBox(char)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local bb = Instance.new("BillboardGui")
	bb.Name = "StatsXBox"
	bb.Adornee = hrp
	bb.Size = UDim2.fromScale(4, 6)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Parent = hrp
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 1)
	f.Parent = bb
	local bs = Instance.new("UIStroke")
	bs.Thickness = 2
	bs.Color = accent
	bs.Parent = f
	return bb, bs
end
local function espSetVis(rec)
	if rec.nameLbl then rec.nameLbl.Visible = espNames end
	if rec.distLbl then rec.distLbl.Visible = espDistance end
	if rec.healthBg then rec.healthBg.Visible = espHealth end
	if rec.tag then rec.tag.Enabled = (espNames or espDistance or espHealth) end
	if rec.box then rec.box.Enabled = espBoxes end
end
local function applyEsp(char)
	if not char or espStore[char] then return end
	local rec = {}
	local hl = Instance.new("Highlight")
	hl.Name = "StatsXESP"
	hl.FillColor = accent
	hl.OutlineColor = Color3.fromRGB(255, 255, 255)
	hl.FillTransparency = espFill
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = char
	rec.hl = hl
	rec.tag, rec.nameLbl, rec.distLbl, rec.healthBg, rec.healthFill = makeInfo(char)
	rec.box, rec.boxStroke = makeBox(char)
	espStore[char] = rec
	espSetVis(rec)
end
local function espStart()
	espActive = true
	local function hook(plr)
		if plr == LocalPlayer then return end
		espConns[plr] = plr.CharacterAdded:Connect(function(char)
			task.wait(0.2); if espActive then applyEsp(char) end
		end)
		if plr.Character then applyEsp(plr.Character) end
	end
	for _, plr in ipairs(Players:GetPlayers()) do hook(plr) end
	espConns._added = Players.PlayerAdded:Connect(hook)
end
local function espStop()
	espActive = false
	for _, c in pairs(espConns) do pcall(function() c:Disconnect() end) end
	espConns = {}
	for _, rec in pairs(espStore) do
		if rec.hl then rec.hl:Destroy() end
		if rec.tag then rec.tag:Destroy() end
		if rec.box then rec.box:Destroy() end
	end
	espStore = {}
end
local function espRefresh()
	if not espActive then return end
	for _, rec in pairs(espStore) do
		if rec.hl then rec.hl.FillTransparency = espFill end
		espSetVis(rec)
	end
end
RunService.Heartbeat:Connect(function()
	if destroyed or not espActive then return end
	local cam = Workspace.CurrentCamera
	local myPos = cam and cam.CFrame.Position
	for char, rec in pairs(espStore) do
		local hum = char:FindFirstChildOfClass("Humanoid")
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if espHealth and rec.healthFill and hum then
			local pct = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
			rec.healthFill.Size = UDim2.fromScale(pct, 1)
			rec.healthFill.BackgroundColor3 = Color3.fromRGB(math.floor(225 * (1 - pct)) + 30, math.floor(190 * pct) + 50, 90)
		end
		if espDistance and rec.distLbl and myPos and hrp then
			local d = math.floor((hrp.Position - myPos).Magnitude + 0.5)
			rec.distLbl.Text = "[" .. d .. "m]"
		end
	end
end)

-- WalkSpeed / Jump / FOV reset helpers
local function resetWalk()
	local hum = getHumanoid()
	if hum then hum.WalkSpeed = 16 end
end
local function resetJump()
	local hum = getHumanoid()
	if hum then
		if hum.UseJumpPower then hum.JumpPower = 50 else hum.JumpHeight = 7.2 end
	end
end
local function resetFov()
	local cam = Workspace.CurrentCamera
	if cam then cam.FieldOfView = 70 end
end

-- Anti-AFK
local function afkStart()
	if not VirtualUser then return end
	afkConn = LocalPlayer.Idled:Connect(function()
		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new())
		end)
	end)
end
local function afkStop()
	if afkConn then afkConn:Disconnect(); afkConn = nil end
end

-- Rainbow UI
local function rainbowStart()
	rbConn = RunService.RenderStepped:Connect(function()
		local hue = (tick() * rbSpeed) % 1
		accent = Color3.fromHSV(hue, rbSat, 1)
		recolorAll()
	end)
end
local function rainbowStop()
	if rbConn then rbConn:Disconnect(); rbConn = nil end
	accent = DEFAULT_ACCENT
	recolorAll()
end

-- Fly (BodyVelocity based; WASD relative to camera, Space up, Shift down)
local flying, flySpeed = false, 60
local flyTrail, flyTrailLen = true, 0.5
local flyBV, flyConn, flyFX, flyT0, flyBG

-- Build the cinematic flight FX (whoosh trail + thrust glow + aura light).
local function buildFlyFX(hrp)
	local parts = {}
	local a0 = Instance.new("Attachment"); a0.Name = "StatsXFly0"; a0.Position = Vector3.new(0, 1.6, 0); a0.Parent = hrp
	local a1 = Instance.new("Attachment"); a1.Name = "StatsXFly1"; a1.Position = Vector3.new(0, -1.6, 0); a1.Parent = hrp
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = flyTrailLen
	trail.MinLength = 0.05
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(accent, Color3.fromRGB(150, 190, 255))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Enabled = false
	trail.Parent = hrp
	local thrust = Instance.new("ParticleEmitter")
	thrust.Color = ColorSequence.new(accent)
	thrust.LightEmission = 1
	thrust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	thrust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	thrust.Lifetime = NumberRange.new(0.25, 0.45)
	thrust.Speed = NumberRange.new(6, 12)
	thrust.SpreadAngle = Vector2.new(18, 18)
	thrust.Rate = 0
	thrust.Parent = a1
	local glow = Instance.new("PointLight")
	glow.Color = accent
	glow.Range = 14
	glow.Brightness = 0
	glow.Parent = hrp
	parts.a0, parts.a1, parts.trail, parts.thrust, parts.glow = a0, a1, trail, thrust, glow
	return parts
end

local function startFly()
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	flying = true
	flyT0 = tick()
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.PlatformStand = true
		pcall(function() hum.AutoRotate = false end)
	end
	local bv = Instance.new("BodyVelocity")
	bv.Name = "StatsXFly"
	bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
	bv.P = 9e4
	bv.Velocity = Vector3.zero
	bv.Parent = hrp
	flyBV = bv
	local bg = Instance.new("BodyGyro")
	bg.Name = "StatsXFlyGyro"
	bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
	bg.P = 9e4
	bg.D = 800
	bg.CFrame = hrp.CFrame
	bg.Parent = hrp
	flyBG = bg
	flyFX = buildFlyFX(hrp)
	flyConn = RunService.RenderStepped:Connect(function(dt)
		if not flying or not bv.Parent then return end
		local cam = Workspace.CurrentCamera
		if not cam then return end
		local fwd = (UserInputService:IsKeyDown(Enum.KeyCode.W) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.S) and 1 or 0)
		local strafe = (UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
		local vert = (UserInputService:IsKeyDown(Enum.KeyCode.Space) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and 1 or 0)
		local dir = cam.CFrame.LookVector * fwd + cam.CFrame.RightVector * strafe + Vector3.new(0, 1, 0) * vert
		if dir.Magnitude > 0 then dir = dir.Unit * flySpeed else dir = Vector3.zero end
		bv.Velocity = dir

		-- Hero pose: bank + dive into the direction of travel, with a living idle sway.
		local hrp2 = bv.Parent
		local look = cam.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.05 then flat = hrp2.CFrame.LookVector end
		flat = flat.Unit
		local t = tick() - (flyT0 or 0)
		local horiz = (fwd ~= 0 or strafe ~= 0)
		local goal
		if horiz then
			local lean = math.rad(74)            -- dive toward a horizontal hero pose
			local bank = math.rad(-24) * strafe  -- roll into the turns
			goal = CFrame.lookAt(hrp2.Position, hrp2.Position + flat) * CFrame.Angles(-lean, 0, bank)
		else
			local sway = math.rad(4) * math.sin(t * 1.8)
			goal = CFrame.lookAt(hrp2.Position, hrp2.Position + flat) * CFrame.Angles(math.rad(-10), 0, sway)
		end
		if flyBG then
			local alpha = math.clamp((dt or 1 / 60) * 12, 0, 1)
			flyBG.CFrame = flyBG.CFrame:Lerp(goal, alpha)
		end

		-- Drive the FX off of how fast we are moving.
		if flyFX then
			local moving = dir.Magnitude > 1
			flyFX.trail.Enabled = moving and flyTrail
			flyFX.thrust.Rate = moving and 60 or 0
			flyFX.glow.Brightness = moving and (1.5 + 0.5 * math.sin(t * 10)) or 0
		end
	end)
end

local function stopFly()
	flying = false
	if flyConn then flyConn:Disconnect(); flyConn = nil end
	if flyBV then flyBV:Destroy(); flyBV = nil end
	if flyBG then flyBG:Destroy(); flyBG = nil end
	if flyFX then
		for _, inst in pairs(flyFX) do
			if typeof(inst) == "Instance" then inst:Destroy() end
		end
		flyFX = nil
	end
	local hum = getHumanoid()
	if hum then
		hum.PlatformStand = false
		pcall(function() hum.AutoRotate = true end)
	end
end

-- Noclip
local noclipping, noclipConn = false, nil
local function startNoclip()
	noclipping = true
	noclipConn = RunService.Stepped:Connect(function()
		local char = LocalPlayer.Character
		if not char then return end
		for _, p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
		end
	end)
end
local function stopNoclip()
	noclipping = false
	if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
end

-- Gravity
local defaultGravity = Workspace.Gravity
local gravOn, gravVal = false, Workspace.Gravity

-- Visibility
-- Roblox replication filtering (permanently on, no longer switchable) means NO
-- property a client changes is ever sent to the server. Transparency,
-- LocalTransparencyModifier and deleting your own body parts are therefore
-- cosmetic on YOUR screen only -- everyone else still sees you completely
-- normally. The old comment here claimed Transparency replicates. It does not.
-- The one thing a client can genuinely push to the server is PHYSICS on parts
-- it owns, which is what "Server" mode below abuses.
local visOn = false
local visStore = {}
-- Mode + loop handles. A global rather than locals because the main chunk sits
-- at 199 of Luau's 200 local registers.
StatsXVis = { mode = "Local", render = nil, phys = nil, joints = {} }
local function applyInvisible()
	local char = LocalPlayer.Character
	if not char then return end
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") then
			-- LocalTransparencyModifier is the right API for this. It is
			-- local-only by design and, unlike Transparency, the game's own
			-- scripts never fight you for it.
			p.LocalTransparencyModifier = 1
		elseif p:IsA("Decal") or p:IsA("Texture") then
			if visStore[p] == nil then visStore[p] = p.Transparency end
			p.Transparency = 1
		elseif p:IsA("BillboardGui") or p:IsA("SurfaceGui") then
			if visStore[p] == nil then visStore[p] = p.Enabled end
			p.Enabled = false
		elseif p:IsA("ParticleEmitter") or p:IsA("Trail") or p:IsA("Beam")
			or p:IsA("Smoke") or p:IsA("Fire") or p:IsA("Sparkles") then
			if visStore[p] == nil then visStore[p] = p.Enabled end
			p.Enabled = false
		end
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.NameDisplayDistance = 0
		hum.HealthDisplayDistance = 0
	end
end

-- Server mode. Disable the rig's joints so the animator cannot drag the limbs
-- back, then shove every loose part far under the map each physics step. Part
-- movement is PHYSICS, and a client owns its own character, so unlike a
-- property change this genuinely replicates: other players stop seeing a body
-- at your position. Joints are only disabled, never destroyed, so it reverses.
-- Hung off the global table rather than declared as a local: the main chunk
-- has exactly zero spare local registers.
StatsXVis.ghost = function()
	local char = LocalPlayer.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	for _, j in ipairs(char:GetDescendants()) do
		if j:IsA("Motor6D") or j:IsA("Weld") or j:IsA("WeldConstraint") then
			if StatsXVis.joints[j] == nil then StatsXVis.joints[j] = j.Enabled end
			j.Enabled = false
		end
	end
	for _, p in ipairs(char:GetDescendants()) do
		-- The root part is left alone: it is invisible anyway, and it is what
		-- the Humanoid walks around with, so you keep control of your player.
		if p:IsA("BasePart") and p ~= root then
			p.CanCollide = false
			p.Massless = true
			p.CFrame = CFrame.new(0, -900, 0)
			p.AssemblyLinearVelocity = Vector3.zero
		end
	end
end
local function startVisibility()
	visOn = true
	visStore = {}
	StatsXVis.joints = {}
	pcall(applyInvisible)
	-- The camera resets LocalTransparencyModifier every frame (that is how first
	-- person works), so it has to be re-asserted on RenderStepped rather than
	-- polled on a timer like the old version did.
	if StatsXVis.render then StatsXVis.render:Disconnect() end
	StatsXVis.render = RunService.RenderStepped:Connect(function()
		if not visOn or destroyed then return end
		pcall(applyInvisible)
	end)
	if StatsXVis.phys then StatsXVis.phys:Disconnect(); StatsXVis.phys = nil end
	if StatsXVis.mode == "Server" then
		StatsXVis.phys = RunService.Heartbeat:Connect(function()
			if not visOn or destroyed then return end
			pcall(StatsXVis.ghost)
		end)
	end
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = "StatsX",
			Text = StatsXVis.mode == "Server"
				and "Server ghost on. Respawn to restore your body."
				or "Hidden from your own camera only.",
			Duration = 5,
		})
	end)
end
local function stopVisibility()
	visOn = false
	if StatsXVis.render then StatsXVis.render:Disconnect(); StatsXVis.render = nil end
	if StatsXVis.phys then StatsXVis.phys:Disconnect(); StatsXVis.phys = nil end
	local char = LocalPlayer.Character
	if char then
		for _, p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") then
				pcall(function() p.LocalTransparencyModifier = 0 end)
			end
		end
	end
	for j, en in pairs(StatsXVis.joints) do
		if j and j.Parent then pcall(function() j.Enabled = en end) end
	end
	StatsXVis.joints = {}
	for p, v in pairs(visStore) do
		if p and p.Parent then
			pcall(function()
				if typeof(v) == "boolean" then p.Enabled = v else p.Transparency = v end
			end)
		end
	end
	visStore = {}
end
LocalPlayer.CharacterAdded:Connect(function()
	if destroyed then return end
	if visOn then
		task.wait(0.6)
		-- Fresh character: the old instance table is stale.
		visStore = {}
		StatsXVis.joints = {}
		pcall(applyInvisible)
	end
end)

-- Clean / transparent UI mode
----------------------------------------------------------------------
-- AimLock (lock the camera onto a target body part)
----------------------------------------------------------------------
local aimPart = "Head"
local aimSmooth = 0.65
local aimMaxDist = 1000
local aimFov = 250
local aimTeamCheck = true
local aimWallCheck = false
local aimHold = true
local aimKey = nil
local aimConn, aimTarget
-- Toggle-mode state. A global rather than two locals on purpose: the main
-- chunk sits at 199 of Luau's 200 local registers, and one more top-level
-- local throws "Out of local registers". Zero registers this way.
StatsXAim = { toggleMode = false, toggled = false }
local AIM_PARTS = {
	Head = { "Head" },
	Torso = { "UpperTorso", "Torso", "HumanoidRootPart" },
	Leg = { "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "Left Leg", "Right Leg", "LeftFoot", "RightFoot" },
}
local function aimGetPart(char)
	for _, n in ipairs(AIM_PARTS[aimPart] or AIM_PARTS.Head) do
		local p = char:FindFirstChild(n)
		if p then return p end
	end
	return char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
end
local function aimVisible(part, char)
	if not aimWallCheck then return true end
	local cam = Workspace.CurrentCamera
	if not cam then return true end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { LocalPlayer.Character, cam }
	local origin = cam.CFrame.Position
	local res = Workspace:Raycast(origin, part.Position - origin, params)
	if not res then return true end
	return res.Instance:IsDescendantOf(char)
end
local function aimFindTarget()
	local cam = Workspace.CurrentCamera
	if not cam then return nil end
	local mouse = UserInputService:GetMouseLocation()
	local best, bestDist = nil, aimFov
	local myPos = cam.CFrame.Position
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and plr.Character then
			local char = plr.Character
			local hum = char:FindFirstChildOfClass("Humanoid")
			local sameTeam = aimTeamCheck and plr.Team and LocalPlayer.Team and plr.Team == LocalPlayer.Team
			if hum and hum.Health > 0 and not sameTeam then
				local part = aimGetPart(char)
				if part and (part.Position - myPos).Magnitude <= aimMaxDist then
					local sp, onScreen = cam:WorldToViewportPoint(part.Position)
					if onScreen then
						local d = (Vector2.new(sp.X, sp.Y) - mouse).Magnitude
						if d < bestDist and aimVisible(part, char) then
							best, bestDist = part, d
						end
					end
				end
			end
		end
	end
	return best
end
local function startAimlock()
	if aimConn then aimConn:Disconnect() end
	aimConn = RunService.RenderStepped:Connect(function(dt)
		local cam = Workspace.CurrentCamera
		if not cam then return end
		local engaged
		if StatsXAim.toggleMode then
			-- Toggle mode: tap the bound key (or RMB if nothing is bound) to
			-- latch the lock on. Stays engaged until tapped again.
			engaged = StatsXAim.toggled
		elseif aimHold and aimKey then
			engaged = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) or UserInputService:IsKeyDown(aimKey)
		elseif aimHold then
			engaged = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
		elseif aimKey then
			engaged = UserInputService:IsKeyDown(aimKey)
		else
			engaged = true
		end
		if not engaged then aimTarget = nil; return end
		aimTarget = aimFindTarget()
		if aimTarget and aimTarget.Parent then
			local goal = CFrame.new(cam.CFrame.Position, aimTarget.Position)
			local a = math.clamp((1 - aimSmooth) * (dt * 60), 0.02, 1)
			cam.CFrame = cam.CFrame:Lerp(goal, a)
		end
	end)
end
local function stopAimlock()
	if aimConn then aimConn:Disconnect(); aimConn = nil end
	aimTarget = nil
	StatsXAim.toggled = false
end

-- Toggle-mode latch. Only listens while Aim Lock is actually running, and
-- ignores input the game already consumed (so typing in chat won't fire it).
UserInputService.InputBegan:Connect(function(input, gp)
	if destroyed or gp then return end
	if not StatsXAim.toggleMode or not aimConn then return end
	local hit
	if aimKey then
		hit = (input.KeyCode == aimKey)
	else
		hit = (input.UserInputType == Enum.UserInputType.MouseButton2)
	end
	if hit then StatsXAim.toggled = not StatsXAim.toggled end
end)

cleanOn = false
applyClean = function(on)
	cleanOn = on
	tween(main, EASE.Smooth, { BackgroundTransparency = on and 0.35 or 0 })
	tween(mainStroke, EASE.Smooth, { Transparency = on and 0.1 or 0.25 })
	tween(tabBar, EASE.Smooth, { BackgroundTransparency = on and 0.5 or 0 })
	for _, c in ipairs(allRows) do
		tween(c, EASE.Smooth, { BackgroundTransparency = on and 0.5 or 0 })
	end
end

----------------------------------------------------------------------
-- Persistent loops
----------------------------------------------------------------------
local frameTimes = {}
RunService.RenderStepped:Connect(function()
	if destroyed then return end
	local now = tick()
	frameTimes[#frameTimes + 1] = now
	while frameTimes[1] and frameTimes[1] < now - 1 do table.remove(frameTimes, 1) end
end)
local function getPing()
	if not Stats then return 0 end
	local ok, v = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
	return ok and math.floor(v) or 0
end
RunService.Heartbeat:Connect(function()
	if destroyed then return end
	-- footer stats
	local txt = "FPS: " .. #frameTimes .. "    Ping: " .. getPing() .. " ms"
	if showSpeed then
		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local v = hrp.AssemblyLinearVelocity
			local mag = speedVertical and v.Magnitude or Vector3.new(v.X, 0, v.Z).Magnitude
			txt = txt .. "    Speed: " .. math.floor(mag + 0.5)
		end
	end
	statusLbl.Text = txt
	-- value-maintaining features
	local hum = getHumanoid()
	if hum then
		if walkOn then hum.WalkSpeed = walkVal end
		if jumpOn then
			if hum.UseJumpPower then hum.JumpPower = jumpVal else hum.JumpHeight = jumpVal / 14 end
		end
	end
	local cam = Workspace.CurrentCamera
	if cam and fovOn then cam.FieldOfView = fovVal end
end)
UserInputService.JumpRequest:Connect(function()
	if destroyed then return end
	if infOn then
		local hum = getHumanoid()
		if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
	end
end)

----------------------------------------------------------------------
-- Build the feature toggles (with config panels)
----------------------------------------------------------------------
createToggle({
	key = "fullbright", name = "Fullbright", desc = "Removes darkness and fog",
	color = Color3.fromRGB(255, 214, 102), short = "FB", order = 1,
	onEnable = fbOn, onDisable = fbOff,
	buildConfig = function(cfg)
		createSlider(cfg, { name = "Brightness", min = 0, max = 5, default = fbBright, decimals = 1, order = 1,
			onChange = function(v) fbBright = v; if fbActive then applyFullbright() end end })
	end,
})
createToggle({
	key = "esp", name = "Player ESP", desc = "Highlights other players",
	color = Color3.fromRGB(96, 165, 250), short = "ESP", order = 2,
	onEnable = espStart, onDisable = espStop,
	buildConfig = function(cfg)
		createSlider(cfg, { name = "Fill transparency", min = 0, max = 1, default = espFill, decimals = 2, order = 1,
			onChange = function(v) espFill = v; espRefresh() end })
		createCheckbox(cfg, { name = "Show name tags", default = espNames, order = 2,
			onChange = function(v) espNames = v; espRefresh() end })
		createCheckbox(cfg, { name = "Show boxes", default = espBoxes, order = 3,
			onChange = function(v) espBoxes = v; espRefresh() end })
		createCheckbox(cfg, { name = "Show distance", default = espDistance, order = 4,
			onChange = function(v) espDistance = v; espRefresh() end })
		createCheckbox(cfg, { name = "Show health bar", default = espHealth, order = 5,
			onChange = function(v) espHealth = v; espRefresh() end })
	end,
})

createToggle({
	key = "speed", name = "Speed Readout", desc = "Shows live speed in footer",
	color = Color3.fromRGB(248, 113, 113), short = "SPD", order = 3,
	onEnable = function() showSpeed = true end, onDisable = function() showSpeed = false end,
	buildConfig = function(cfg)
		createCheckbox(cfg, { name = "Include vertical velocity", default = speedVertical, order = 1,
			onChange = function(v) speedVertical = v end })
	end,
})

createToggle({
	key = "walk", name = "WalkSpeed", desc = "Sets your walk speed",
	color = Color3.fromRGB(52, 211, 153), short = "WS", order = 4,
	onEnable = function() walkOn = true end, onDisable = function() walkOn = false; resetWalk() end,
	buildConfig = function(cfg)
		createSlider(cfg, { name = "Speed", min = 16, max = 250, default = walkVal, decimals = 0, order = 1,
			onChange = function(v) walkVal = v end })
	end,
})

createToggle({
	key = "jump", name = "Jump Power", desc = "Sets your jump strength",
	color = Color3.fromRGB(167, 139, 250), short = "JP", order = 5,
	onEnable = function() jumpOn = true end, onDisable = function() jumpOn = false; resetJump() end,
	buildConfig = function(cfg)
		createSlider(cfg, { name = "Power", min = 50, max = 400, default = jumpVal, decimals = 0, order = 1,
			onChange = function(v) jumpVal = v end })
	end,
})

createToggle({
	key = "infjump", name = "Infinite Jump", desc = "Jump again in mid-air",
	color = Color3.fromRGB(56, 189, 248), short = "IJ", order = 6,
	onEnable = function() infOn = true end, onDisable = function() infOn = false end,
})

createToggle({
	key = "fov", name = "FOV Changer", desc = "Adjusts camera field of view",
	color = Color3.fromRGB(251, 146, 60), short = "FOV", order = 7,
	onEnable = function() fovOn = true end, onDisable = function() fovOn = false; resetFov() end,
	buildConfig = function(cfg)
		createSlider(cfg, { name = "Field of view", min = 70, max = 120, default = fovVal, decimals = 0, order = 1,
			onChange = function(v) fovVal = v end })
	end,
})

createToggle({
	key = "afk", name = "Anti-AFK", desc = "Prevents the idle kick",
	color = Color3.fromRGB(45, 212, 191), short = "AFK", order = 8,
	onEnable = afkStart, onDisable = afkStop,
})

createToggle({
	key = "fly", name = "Fly", desc = "WASD to move, Space up / Shift down",
	color = Color3.fromRGB(125, 211, 252), short = "FLY", order = 9,
	onEnable = startFly, onDisable = stopFly,
	buildConfig = function(cfg)
		createSlider(cfg, { name = "Fly speed", min = 20, max = 250, default = flySpeed, decimals = 0, order = 1,
			onChange = function(v) flySpeed = v end })
		createSlider(cfg, { name = "Trail length", min = 0, max = 1.5, default = flyTrailLen, decimals = 2, suffix = "s", order = 2,
			onChange = function(v) flyTrailLen = v; if flyFX and flyFX.trail then flyFX.trail.Lifetime = v end end })
		createCheckbox(cfg, { name = "Glowing trail", default = flyTrail, order = 3,
			onChange = function(v) flyTrail = v; if flyFX and flyFX.trail then flyFX.trail.Enabled = v and flying end end })
	end,
})

createToggle({
	key = "noclip", name = "Noclip", desc = "Walk through walls and floors",
	color = Color3.fromRGB(148, 163, 184), short = "NC", order = 10,
	onEnable = startNoclip, onDisable = stopNoclip,
})

createToggle({
	key = "gravity", name = "Gravity Control", desc = "Adjust the world gravity",
	color = Color3.fromRGB(192, 132, 252), short = "GRV", order = 11,
	onEnable = function() gravOn = true; Workspace.Gravity = gravVal end,
	onDisable = function() gravOn = false; Workspace.Gravity = defaultGravity end,
	buildConfig = function(cfg)
		createSlider(cfg, { name = "Gravity", min = 5, max = 196, default = gravVal, decimals = 0, order = 1,
			onChange = function(v) gravVal = v; if gravOn then Workspace.Gravity = v end end })
	end,
})

createToggle({
	key = "visibility", name = "Visibility", desc = "Hide your character -- pick the scope below",
	color = Color3.fromRGB(129, 140, 248), short = "INV", order = 12,
	onEnable = startVisibility, onDisable = stopVisibility,
	buildConfig = function(cfg)
		-- "Local" is guaranteed but only affects your own screen. "Server" is the
		-- only option that can change what other players see, because it moves
		-- parts with physics instead of setting a property.
		createSegmented(cfg, { name = "Hide from", options = { "Local", "Server" }, default = StatsXVis.mode, order = 1,
			onChange = function(v)
				StatsXVis.mode = v
				if visOn then stopVisibility(); startVisibility() end
			end })
	end,
})

createToggle({
	key = "aimlock", name = "Aim Lock", desc = "Snap aim onto the nearest target",
	color = Color3.fromRGB(255, 99, 132), short = "AIM", order = 13,
	onEnable = startAimlock, onDisable = stopAimlock,
	buildConfig = function(cfg)
		createSegmented(cfg, { name = "Target part", options = { "Head", "Torso", "Leg" }, default = aimPart, order = 1,
			onChange = function(v) aimPart = v end })
		createSlider(cfg, { name = "Smoothness", min = 0, max = 1, default = aimSmooth, decimals = 2, order = 2,
			onChange = function(v) aimSmooth = v end })
		createSlider(cfg, { name = "Aim FOV", min = 30, max = 600, default = aimFov, decimals = 0, suffix = "px", order = 3,
			onChange = function(v) aimFov = v end })
		createSlider(cfg, { name = "Max distance", min = 50, max = 5000, default = aimMaxDist, decimals = 0, order = 4,
			onChange = function(v) aimMaxDist = v end })
		createCheckbox(cfg, { name = "Toggle mode (tap key, stays locked)", default = StatsXAim.toggleMode, order = 5,
			onChange = function(v) StatsXAim.toggleMode = v; StatsXAim.toggled = false end })
		createCheckbox(cfg, { name = "Hold right mouse to aim", default = aimHold, order = 6,
			onChange = function(v) aimHold = v end })
		createCheckbox(cfg, { name = "Team check (skip teammates)", default = aimTeamCheck, order = 7,
			onChange = function(v) aimTeamCheck = v end })
		createCheckbox(cfg, { name = "Visible only (wall check)", default = aimWallCheck, order = 8,
			onChange = function(v) aimWallCheck = v end })
		createKeybindButton(cfg, { name = "Aim key (hold, or tap in Toggle mode)", default = aimKey, order = 9,
			onChange = function(code) aimKey = code end })
	end,
})

----------------------------------------------------------------------
-- Teleport / player tools
----------------------------------------------------------------------
local clickTpOn = false
local tpOffset = 3
local tpMouse = LocalPlayer:GetMouse()
local function teleportTo(cf)
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then hrp.CFrame = cf end
end
local function teleportToPlayer(plr)
	local tchar = plr and plr.Character
	local thrp = tchar and tchar:FindFirstChild("HumanoidRootPart")
	if thrp then teleportTo(thrp.CFrame * CFrame.new(0, 0, 3)) end
end
UserInputService.InputBegan:Connect(function(input, gp)
	if destroyed or not clickTpOn or gp then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		if tpMouse.Target then
			teleportTo(CFrame.new(tpMouse.Hit.Position + Vector3.new(0, tpOffset, 0)))
		end
	end
end)

createToggle({
	key = "teleport", name = "Teleport", desc = "Click-to-teleport + go to players",
	color = Color3.fromRGB(96, 205, 255), short = "TP", order = 18,
	onEnable = function() clickTpOn = true end,
	onDisable = function() clickTpOn = false end,
	buildConfig = function(cfg)
		createSlider(cfg, { name = "Teleport height offset", min = 0, max = 12, default = tpOffset, decimals = 1, order = 1,
			onChange = function(v) tpOffset = v end })

		local plrLbl = Instance.new("TextLabel")
		plrLbl.BackgroundTransparency = 1
		plrLbl.Size = UDim2.new(1, 0, 0, 18)
		plrLbl.Font = Enum.Font.GothamMedium
		plrLbl.Text = "Teleport to player"
		plrLbl.TextColor3 = THEME.SubText
		plrLbl.TextSize = 12
		plrLbl.TextXAlignment = Enum.TextXAlignment.Left
		plrLbl.LayoutOrder = 2
		plrLbl.Parent = cfg

		local plrScroll = Instance.new("ScrollingFrame")
		plrScroll.Size = UDim2.new(1, 0, 0, 116)
		plrScroll.BackgroundTransparency = 1
		plrScroll.BorderSizePixel = 0
		plrScroll.ScrollBarThickness = 3
		plrScroll.ScrollBarImageColor3 = accent
		plrScroll.CanvasSize = UDim2.new()
		plrScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		plrScroll.ScrollingDirection = Enum.ScrollingDirection.Y
		plrScroll.LayoutOrder = 3
		plrScroll.Parent = cfg
		local psLayout = Instance.new("UIListLayout")
		psLayout.Padding = UDim.new(0, 4)
		psLayout.SortOrder = Enum.SortOrder.LayoutOrder
		psLayout.Parent = plrScroll

		local function refreshPlayers()
			for _, ch in ipairs(plrScroll:GetChildren()) do
				if ch:IsA("TextButton") or ch:IsA("TextLabel") then ch:Destroy() end
			end
			local i = 0
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= LocalPlayer then
					i = i + 1
					createButton(plrScroll, { name = plr.Name, order = i, onClick = function() teleportToPlayer(plr) end })
				end
			end
			if i == 0 then
				local none = Instance.new("TextLabel")
				none.BackgroundTransparency = 1
				none.Size = UDim2.new(1, 0, 0, 24)
				none.Font = Enum.Font.Gotham
				none.Text = "No other players"
				none.TextColor3 = THEME.SubText
				none.TextSize = 12
				none.Parent = plrScroll
			end
		end
		refreshPlayers()
		Players.PlayerAdded:Connect(function() if not destroyed then task.defer(refreshPlayers) end end)
		Players.PlayerRemoving:Connect(function() if not destroyed then task.defer(refreshPlayers) end end)

		createButton(cfg, { name = "Refresh list", order = 4, onClick = refreshPlayers })
	end,
})

createToggle({
	key = "clean", name = "Transparent UI", desc = "Glassy, transparent interface",
	color = Color3.fromRGB(94, 234, 212), short = "UI", order = 17,
	onEnable = function() applyClean(true) end, onDisable = function() applyClean(false) end,
})

createToggle({
	key = "rainbow", name = "Rainbow UI", desc = "Cycles the accent color",
	color = Color3.fromRGB(244, 114, 182), short = "RGB", order = 16,
	onEnable = rainbowStart, onDisable = rainbowStop,
	buildConfig = function(cfg)
		createSlider(cfg, { name = "Cycle speed", min = 0.05, max = 0.5, default = rbSpeed, decimals = 2, order = 1,
			onChange = function(v) rbSpeed = v end })
		createSlider(cfg, { name = "Saturation", min = 0.2, max = 1, default = rbSat, decimals = 2, order = 2,
			onChange = function(v) rbSat = v; if rbConn then recolorAll() end end })
	end,
})
end)()

----------------------------------------------------------------------
-- Bottom arrow tab (CLOSED state)
----------------------------------------------------------------------
local arrow = Instance.new("TextButton")
arrow.Name = "ArrowTab"
arrow.AnchorPoint = Vector2.new(0.5, 1)
arrow.Position = UDim2.new(0.5, 0, 1, 50)
arrow.Size = UDim2.fromOffset(58, 28)
arrow.BackgroundColor3 = THEME.Background
arrow.Text = "^"
arrow.TextColor3 = THEME.Text
arrow.Font = Enum.Font.GothamBold
arrow.TextSize = 18
arrow.AutoButtonColor = false
arrow.Visible = false
arrow.Parent = gui
corner(arrow, 12)
local arrowStroke = stroke(arrow, accent, 1.5, 0.2)
registerAccent(arrowStroke)

----------------------------------------------------------------------
-- Sirius-style dock
----------------------------------------------------------------------
local DOCK_KEYS = { "fullbright", "esp", "fly", "noclip", "walk", "fov", "visibility", "rainbow" }
local _dockIconCount = #DOCK_KEYS
local _dockWidth = 84 + (_dockIconCount * 42 + (_dockIconCount - 1) * 8) + 58 + 40
local dock = Instance.new("Frame")
dock.Name = "Dock"
dock.AnchorPoint = Vector2.new(0.5, 1)
dock.Position = UDim2.new(0.5, 0, 1, 140)
dock.Size = UDim2.fromOffset(_dockWidth, 62)
dock.BackgroundColor3 = THEME.Background
dock.Visible = false
dock.Parent = gui
corner(dock, 18)
local dockStroke = stroke(dock, accent, 1.5, 0.25)
registerAccent(dockStroke)
gradient(dock, THEME.Background2, THEME.Background, 90)

-- collapse chevron sitting above the dock
local dockChevron = Instance.new("TextButton")
dockChevron.AnchorPoint = Vector2.new(0.5, 1)
dockChevron.Position = UDim2.new(0.5, 0, 0, -6)
dockChevron.Size = UDim2.fromOffset(36, 18)
dockChevron.BackgroundTransparency = 1
dockChevron.Text = "v"
dockChevron.TextColor3 = THEME.SubText
dockChevron.Font = Enum.Font.GothamBold
dockChevron.TextSize = 16
dockChevron.AutoButtonColor = false
dockChevron.Parent = dock

-- live clock on the left
local dockClock = Instance.new("TextLabel")
dockClock.BackgroundTransparency = 1
dockClock.Position = UDim2.fromOffset(18, 0)
dockClock.Size = UDim2.fromOffset(58, 62)
dockClock.Font = Enum.Font.GothamBold
dockClock.Text = os.date("%H:%M")
dockClock.TextColor3 = THEME.Text
dockClock.TextSize = 18
dockClock.TextXAlignment = Enum.TextXAlignment.Left
dockClock.Parent = dock

-- quick-toggle icon buttons
local dockHolder = Instance.new("Frame")
dockHolder.BackgroundTransparency = 1
dockHolder.AnchorPoint = Vector2.new(0.5, 0.5)
dockHolder.Position = UDim2.new(0.5, 12, 0.5, 0)
dockHolder.Size = UDim2.new(1, -150, 1, -16)
dockHolder.Parent = dock
local dockLayout = Instance.new("UIListLayout")
dockLayout.FillDirection = Enum.FillDirection.Horizontal
dockLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
dockLayout.VerticalAlignment = Enum.VerticalAlignment.Center
dockLayout.Padding = UDim.new(0, 8)
dockLayout.SortOrder = Enum.SortOrder.LayoutOrder
dockLayout.Parent = dockHolder

-- Vector icon factory (white glyphs drawn in code, no image assets needed)
local function iconPart(parent, w, h, x, y, rot)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.Rotation = rot or 0
	f.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end
local function addIcon(button, kind, scale)
	local holder = Instance.new("Frame")
	holder.Name = "Icon"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.new(0.5, 0, 0.5, 0)
	holder.Size = UDim2.fromOffset(24, 24)
	holder.BackgroundTransparency = 1
	holder.Parent = button
	if scale then
		local us = Instance.new("UIScale")
		us.Scale = scale
		us.Parent = holder
	end
	local cx, cy = 12, 12
	if kind == "sun" then
		local core = iconPart(holder, 10, 10, cx, cy)
		corner(core, 5)
		for i = 0, 7 do
			local ang = math.rad(i * 45)
			local ray = iconPart(holder, 2.5, 5, cx + math.sin(ang) * 10, cy - math.cos(ang) * 10, i * 45)
			corner(ray, 1)
		end
	elseif kind == "target" then
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.new(0.5, 0, 0.5, 0)
		ring.Size = UDim2.fromOffset(22, 22)
		ring.BackgroundTransparency = 1
		ring.Parent = holder
		corner(ring, 11)
		stroke(ring, Color3.fromRGB(255, 255, 255), 2, 0)
		local dot = iconPart(holder, 6, 6, cx, cy)
		corner(dot, 3)
		iconPart(holder, 2, 5, cx, cy - 11)
		iconPart(holder, 2, 5, cx, cy + 11)
		iconPart(holder, 5, 2, cx - 11, cy)
		iconPart(holder, 5, 2, cx + 11, cy)
	elseif kind == "speed" then
		for _, ox in ipairs({ 7, 14 }) do
			local up = iconPart(holder, 3, 11, ox, cy - 4, 40)
			corner(up, 2)
			local dn = iconPart(holder, 3, 11, ox, cy + 4, -40)
			corner(dn, 2)
		end
	elseif kind == "eye" then
		local lens = Instance.new("Frame")
		lens.AnchorPoint = Vector2.new(0.5, 0.5)
		lens.Position = UDim2.new(0.5, 0, 0.5, 0)
		lens.Size = UDim2.fromOffset(24, 15)
		lens.BackgroundTransparency = 1
		lens.Parent = holder
		corner(lens, 7)
		stroke(lens, Color3.fromRGB(255, 255, 255), 2, 0)
		local pupil = iconPart(holder, 7, 7, cx, cy)
		corner(pupil, 4)
	elseif kind == "rainbow" then
		local circ = Instance.new("Frame")
		circ.AnchorPoint = Vector2.new(0.5, 0.5)
		circ.Position = UDim2.new(0.5, 0, 0.5, 0)
		circ.Size = UDim2.fromOffset(22, 22)
		circ.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		circ.BorderSizePixel = 0
		circ.Parent = holder
		corner(circ, 11)
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
			ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 215, 90)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(90, 230, 130)),
			ColorSequenceKeypoint.new(0.8, Color3.fromRGB(90, 170, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(205, 120, 255)),
		})
		g.Rotation = 45
		g.Parent = circ
	elseif kind == "window" then
		local box = Instance.new("Frame")
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.new(0.5, 0, 0.5, 0)
		box.Size = UDim2.fromOffset(22, 17)
		box.BackgroundTransparency = 1
		box.Parent = holder
		corner(box, 4)
		stroke(box, Color3.fromRGB(255, 255, 255), 2, 0)
		local bar = iconPart(holder, 22, 5, cx, cy - 6)
		corner(bar, 2)
	elseif kind == "fly" then
		-- upward double chevron (ascend / flight)
		local l1 = iconPart(holder, 3, 10, cx - 4, cy + 4, 45)
		corner(l1, 1)
		local r1 = iconPart(holder, 3, 10, cx + 4, cy + 4, -45)
		corner(r1, 1)
		local l2 = iconPart(holder, 3, 10, cx - 4, cy - 2, 45)
		corner(l2, 1)
		local r2 = iconPart(holder, 3, 10, cx + 4, cy - 2, -45)
		corner(r2, 1)
	elseif kind == "phase" then
		local s1 = Instance.new("Frame")
		s1.AnchorPoint = Vector2.new(0.5, 0.5)
		s1.Position = UDim2.fromOffset(cx - 3, cy - 3)
		s1.Size = UDim2.fromOffset(13, 13)
		s1.BackgroundTransparency = 1
		s1.Parent = holder
		corner(s1, 3)
		stroke(s1, Color3.fromRGB(255, 255, 255), 2, 0)
		local s2 = Instance.new("Frame")
		s2.AnchorPoint = Vector2.new(0.5, 0.5)
		s2.Position = UDim2.fromOffset(cx + 3, cy + 3)
		s2.Size = UDim2.fromOffset(13, 13)
		s2.BackgroundColor3 = THEME.Background
		s2.BorderSizePixel = 0
		s2.Parent = holder
		corner(s2, 3)
		stroke(s2, Color3.fromRGB(255, 255, 255), 2, 0)
	elseif kind == "eyeoff" then
		local lens = Instance.new("Frame")
		lens.AnchorPoint = Vector2.new(0.5, 0.5)
		lens.Position = UDim2.new(0.5, 0, 0.5, 0)
		lens.Size = UDim2.fromOffset(24, 15)
		lens.BackgroundTransparency = 1
		lens.Parent = holder
		corner(lens, 7)
		stroke(lens, Color3.fromRGB(255, 255, 255), 2, 0)
		local pupil = iconPart(holder, 7, 7, cx, cy)
		corner(pupil, 4)
		local slash = iconPart(holder, 30, 2.5, cx, cy, 32)
		corner(slash, 1)
	elseif kind == "gear" then
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.new(0.5, 0, 0.5, 0)
		ring.Size = UDim2.fromOffset(14, 14)
		ring.BackgroundTransparency = 1
		ring.Parent = holder
		corner(ring, 7)
		stroke(ring, Color3.fromRGB(255, 255, 255), 2.5, 0)
		for i = 0, 7 do
			local ang = math.rad(i * 45)
			local tooth = iconPart(holder, 3.5, 4, cx + math.sin(ang) * 10, cy - math.cos(ang) * 10, i * 45)
			corner(tooth, 1)
		end
		local hub = iconPart(holder, 5, 5, cx, cy)
		corner(hub, 3)
	end
	return holder
end

local ICON_KINDS = { fullbright = "sun", esp = "target", walk = "speed", fov = "eye", rainbow = "rainbow", fly = "fly", noclip = "phase", visibility = "eyeoff", aimlock = "target", speed = "speed", clean = "window", jump = "fly", infjump = "fly", gravity = "phase", afk = "eye" }
local function makeDockIcon(key, order)
	local feat = Features[key]
	if not feat then return end
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromOffset(42, 42)
	btn.BackgroundColor3 = feat.color
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.LayoutOrder = order
	btn.Parent = dockHolder
	corner(btn, 12)
	local icon = addIcon(btn, ICON_KINDS[key] or "target")
	local glow = stroke(btn, Color3.fromRGB(255, 255, 255), 1.5, 1)
	local function sync()
		local on = feat.get()
		tween(btn, EASE.Snappy, { BackgroundTransparency = on and 0 or 0.5 })
		tween(glow, EASE.Snappy, { Transparency = on and 0.2 or 1 })
	end
	btn.MouseButton1Click:Connect(function() feat.set(not feat.get()); sync() end)
	btn.MouseEnter:Connect(function() tween(btn, EASE.Hover, { Size = UDim2.fromOffset(46, 46) }) end)
	btn.MouseLeave:Connect(function() tween(btn, EASE.Hover, { Size = UDim2.fromOffset(42, 42) }) end)
	sync()
end
for i, k in ipairs(DOCK_KEYS) do makeDockIcon(k, i) end

-- restore-window button on the right
local restoreBtn = Instance.new("TextButton")
restoreBtn.AnchorPoint = Vector2.new(1, 0.5)
restoreBtn.Position = UDim2.new(1, -16, 0.5, 0)
restoreBtn.Size = UDim2.fromOffset(42, 42)
restoreBtn.BackgroundColor3 = THEME.Row
restoreBtn.Text = ""
restoreBtn.AutoButtonColor = false
restoreBtn.Parent = dock
corner(restoreBtn, 12)
addIcon(restoreBtn, "window")
local restoreStroke = stroke(restoreBtn, accent, 1.5, 0.3)
registerAccent(restoreStroke)
restoreBtn.MouseEnter:Connect(function() tween(restoreBtn, EASE.Hover, { BackgroundColor3 = THEME.RowHover }) end)
restoreBtn.MouseLeave:Connect(function() tween(restoreBtn, EASE.Hover, { BackgroundColor3 = THEME.Row }) end)

----------------------------------------------------------------------
-- State machine: minimize / close / arrow / dock
----------------------------------------------------------------------
local grip
local minimized = false
local resetGear -- assigned by buildSettings; snaps the settings gear back to idle (kills hover glitch on minimize)
local function setMinimized(m)
	minimized = m
	if grip then grip.Visible = not m end
	if resetGear then resetGear() end
	if m then
		tween(body, EASE.Morph, { Size = UDim2.new(1, 0, 0, 0) })
		tween(main, EASE.Morph, { Size = BAR_SIZE, Position = BAR_POS })
		minBtn.Text = "+"
	else
		tween(main, EASE.Morph, { Size = OPEN_SIZE, Position = OPEN_POS })
		tween(body, EASE.Morph, { Size = UDim2.new(1, 0, 1, -54) })
		minBtn.Text = "-"
	end
end
minBtn.MouseButton1Click:Connect(function() setMinimized(not minimized) end)

local function showArrow()
	arrow.Visible = true
	arrow.Position = UDim2.new(0.5, 0, 1, 50)
	tween(arrow, EASE.Open, { Position = UDim2.new(0.5, 0, 1, -12) })
end
local function hideArrow()
	tween(arrow, EASE.Snappy, { Position = UDim2.new(0.5, 0, 1, 50) })
	task.delay(0.22, function() arrow.Visible = false end)
end
local function showDock()
	dock.Visible = true
	dock.Position = UDim2.new(0.5, 0, 1, 140)
	tween(dock, EASE.Open, { Position = UDim2.new(0.5, 0, 1, -18) })
end
local function hideDock()
	tween(dock, EASE.Snappy, { Position = UDim2.new(0.5, 0, 1, 140) })
	task.delay(0.22, function() dock.Visible = false end)
end
local function showMain()
	minimized = false
	minBtn.Text = "-"
	if grip then grip.Visible = true end
	body.Visible = true
	header.Visible = true
	body.Size = UDim2.new(1, 0, 1, -54)
	main.Visible = true
	main.Position = OPEN_POS
	main.Size = UDim2.fromOffset(OPEN_SIZE.X.Offset * 0.85, OPEN_SIZE.Y.Offset * 0.85)
	tween(main, EASE.Open, { Size = OPEN_SIZE })
	if cleanOn then applyClean(true) end
end
local function closeToArrow()
	if resetGear then resetGear() end
	-- hide content instantly so only the empty rounded frame animates (no glyph reflow flicker)
	body.Visible = false
	header.Visible = false
	local t = tween(main, EASE.Smooth, { Size = UDim2.fromOffset(0, 0), Position = UDim2.new(0.5, 0, 1, -20), BackgroundTransparency = 0.15 })
	t.Completed:Connect(function()
		main.Visible = false
		main.BackgroundTransparency = 0
		main.Size = OPEN_SIZE
		main.Position = OPEN_POS
		body.Visible = true
		header.Visible = true
		showArrow()
	end)
end
closeBtn.MouseButton1Click:Connect(closeToArrow)
arrow.MouseButton1Click:Connect(function() hideArrow(); showDock() end)
dockChevron.MouseButton1Click:Connect(function() hideDock(); showArrow() end)
restoreBtn.MouseButton1Click:Connect(function() hideDock(); showMain() end)
arrow.MouseEnter:Connect(function() tween(arrow, EASE.Hover, { Size = UDim2.fromOffset(66, 30) }) end)
arrow.MouseLeave:Connect(function() tween(arrow, EASE.Hover, { Size = UDim2.fromOffset(58, 28) }) end)

----------------------------------------------------------------------
-- Dragging (header + dock)
----------------------------------------------------------------------
local function makeDraggable(handle, target)
	local dragging, startPos, startMouse
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			startPos = target.Position
			startMouse = input.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - startMouse
			target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
end
makeDraggable(header, main)

----------------------------------------------------------------------
-- Settings + keybinds (wrapped in a function so these locals do NOT
-- count against the main chunk's Luau 200-local-register limit)
----------------------------------------------------------------------
local function buildSettings()
----------------------------------------------------------------------
-- Settings: performance helpers
----------------------------------------------------------------------
local fpsCap = 60
local function applyFpsCap(n)
	fpsCap = n
	pcall(function() if setfpscap then setfpscap(n) end end)
end
local function applyLowQuality(on)
	pcall(function()
		settings().Rendering.QualityLevel = on and Enum.QualityLevel.Level01 or Enum.QualityLevel.Automatic
	end)
end
local function applyShadows(off)
	pcall(function() Lighting.GlobalShadows = not off end)
end
local setFxStore
local function applyPostFx(disable)
	pcall(function()
		if disable then
			setFxStore = {}
			for _, e in ipairs(Lighting:GetDescendants()) do
				if e:IsA("PostEffect") and e.Enabled then
					table.insert(setFxStore, e)
					e.Enabled = false
				end
			end
		elseif setFxStore then
			for _, e in ipairs(setFxStore) do
				if e and e.Parent then e.Enabled = true end
			end
			setFxStore = nil
		end
	end)
end
local setFogStore
local function applyNoFog(on)
	pcall(function()
		if on then
			setFogStore = Lighting.FogEnd
			Lighting.FogEnd = 1e9
		elseif setFogStore then
			Lighting.FogEnd = setFogStore
			setFogStore = nil
		end
	end)
end

----------------------------------------------------------------------
-- Keybind state: feature key -> Enum.KeyCode (rebindable in Settings)
----------------------------------------------------------------------
local keybinds = {} -- every keybind disabled by default; assign a key in Settings > Keybinds to enable
local listeningKey = nil
local kbBinds = {}

----------------------------------------------------------------------
-- Settings: floating animated gear + movable popup
----------------------------------------------------------------------
local gearBtn = Instance.new("TextButton")
gearBtn.Name = "SettingsGear"
gearBtn.AnchorPoint = Vector2.new(1, 0.5)
gearBtn.Position = UDim2.new(1, -20, 0, 34)
gearBtn.Size = UDim2.fromOffset(34, 34)
gearBtn.BackgroundColor3 = THEME.Row
gearBtn.AutoButtonColor = false
gearBtn.Text = ""
gearBtn.Parent = body
corner(gearBtn, 10)
local gearStroke = stroke(gearBtn, accent, 1.2, 0.4)
registerAccent(gearStroke)
local gearIcon = addIcon(gearBtn, "gear")
local gearTwA, gearTwB
resetGear = function()
	if gearTwA then gearTwA:Cancel() end
	if gearTwB then gearTwB:Cancel() end
	gearBtn.Size = UDim2.fromOffset(34, 34)
	gearBtn.BackgroundColor3 = THEME.Row
	gearIcon.Rotation = 0
end
gearBtn.MouseEnter:Connect(function()
	if minimized then return end
	gearTwA = tween(gearBtn, EASE.Hover, { Size = UDim2.fromOffset(38, 38), BackgroundColor3 = THEME.RowHover })
	gearTwB = tween(gearIcon, EASE.Smooth, { Rotation = 120 })
end)
gearBtn.MouseLeave:Connect(function()
	if minimized then return end
	gearTwA = tween(gearBtn, EASE.Hover, { Size = UDim2.fromOffset(34, 34), BackgroundColor3 = THEME.Row })
	gearTwB = tween(gearIcon, EASE.Smooth, { Rotation = 0 })
end)

local setSize = UDim2.fromOffset(540, 484)
local setOpen = false
local setPanel = Instance.new("Frame")
setPanel.Name = "SettingsPanel"
setPanel.AnchorPoint = Vector2.new(0.5, 0.5)
setPanel.Position = UDim2.fromScale(0.64, 0.5)
setPanel.Size = setSize
setPanel.BackgroundColor3 = THEME.Background
setPanel.BorderSizePixel = 0
setPanel.ClipsDescendants = true
setPanel.Visible = false
setPanel.Parent = gui
corner(setPanel, 16)
local setStroke = stroke(setPanel, accent, 1.5, 0.25)
registerAccent(setStroke)
gradient(setPanel, THEME.Background2, THEME.Background, 90)

local setGrip = Instance.new("TextButton")
setGrip.Name = "SettingsResize"
setGrip.AnchorPoint = Vector2.new(1, 1)
setGrip.Position = UDim2.new(1, -3, 1, -3)
setGrip.Size = UDim2.fromOffset(20, 20)
setGrip.BackgroundTransparency = 1
setGrip.Text = ""
setGrip.AutoButtonColor = false
setGrip.ZIndex = 8
setGrip.Parent = setPanel
for i = 1, 3 do
	local ln = Instance.new("Frame")
	ln.AnchorPoint = Vector2.new(1, 1)
	ln.Position = UDim2.new(1, -3, 1, -3 - (i - 1) * 5)
	ln.Size = UDim2.fromOffset((4 - i) * 5, 2)
	ln.BackgroundColor3 = THEME.SubText
	ln.BackgroundTransparency = 0.25
	ln.BorderSizePixel = 0
	ln.ZIndex = 8
	ln.Parent = setGrip
	corner(ln, 1)
end
local setSizing, setSizeMouse, setSizeStart
setGrip.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		setSizing = true
		setSizeMouse = input.Position
		setSizeStart = setPanel.AbsoluteSize
	end
end)
setGrip.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		setSizing = false
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if setSizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - setSizeMouse
		local nw = math.clamp(setSizeStart.X + delta.X * 2, 380, 760)
		local nh = math.clamp(setSizeStart.Y + delta.Y * 2, 320, 760)
		setSize = UDim2.fromOffset(math.floor(nw), math.floor(nh))
		if setOpen then setPanel.Size = setSize end
	end
end)

local setTopBar = Instance.new("Frame")
setTopBar.Size = UDim2.new(1, -32, 0, 3)
setTopBar.Position = UDim2.fromOffset(16, 0)
setTopBar.BackgroundColor3 = accent
setTopBar.BorderSizePixel = 0
setTopBar.Parent = setPanel
corner(setTopBar, 2)
registerAccent(setTopBar)

local setHeader = Instance.new("Frame")
setHeader.Name = "Header"
setHeader.BackgroundTransparency = 1
setHeader.Size = UDim2.new(1, 0, 0, 46)
setHeader.Position = UDim2.fromOffset(0, 4)
setHeader.Parent = setPanel

local setTitle = Instance.new("TextLabel")
setTitle.BackgroundTransparency = 1
setTitle.Position = UDim2.fromOffset(18, 12)
setTitle.Size = UDim2.new(1, -70, 0, 24)
setTitle.Font = Enum.Font.GothamBold
setTitle.Text = "Settings"
setTitle.TextColor3 = THEME.Text
setTitle.TextSize = 17
setTitle.TextXAlignment = Enum.TextXAlignment.Left
setTitle.Parent = setHeader

local setClose = Instance.new("TextButton")
setClose.AnchorPoint = Vector2.new(1, 0.5)
setClose.Position = UDim2.new(1, -14, 0.5, 0)
setClose.Size = UDim2.fromOffset(28, 28)
setClose.BackgroundColor3 = THEME.Row
setClose.Text = "X"
setClose.TextColor3 = THEME.Text
setClose.TextSize = 15
setClose.Font = Enum.Font.GothamBold
setClose.AutoButtonColor = false
setClose.Parent = setHeader
corner(setClose, 8)
setClose.MouseEnter:Connect(function() tween(setClose, EASE.Hover, { BackgroundColor3 = Color3.fromRGB(220, 70, 80) }) end)
setClose.MouseLeave:Connect(function() tween(setClose, EASE.Hover, { BackgroundColor3 = THEME.Row }) end)

-- settings sub-tabs (General | Keybinds)
local selectSetTab
local setTabActive = "General"
local setTabBtns = {}
local setTabBar = Instance.new("Frame")
setTabBar.Name = "SetTabBar"
setTabBar.BackgroundColor3 = THEME.Row
setTabBar.BorderSizePixel = 0
setTabBar.Position = UDim2.fromOffset(18, 50)
setTabBar.Size = UDim2.new(1, -36, 0, 30)
setTabBar.Parent = setPanel
corner(setTabBar, 9)
local stPad = Instance.new("UIPadding")
stPad.PaddingLeft = UDim.new(0, 4); stPad.PaddingRight = UDim.new(0, 4)
stPad.PaddingTop = UDim.new(0, 4); stPad.PaddingBottom = UDim.new(0, 4)
stPad.Parent = setTabBar
local stLayout = Instance.new("UIListLayout")
stLayout.FillDirection = Enum.FillDirection.Horizontal
stLayout.Padding = UDim.new(0, 4)
stLayout.SortOrder = Enum.SortOrder.LayoutOrder
stLayout.Parent = setTabBar
local function makeSetTab(name, order)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0.5, -6, 1, 0)
	b.BackgroundColor3 = THEME.Row
	b.AutoButtonColor = false
	b.Font = Enum.Font.GothamMedium
	b.Text = name
	b.TextSize = 13
	b.TextColor3 = THEME.SubText
	b.LayoutOrder = order
	b.Parent = setTabBar
	corner(b, 7)
	setTabBtns[name] = b
	b.MouseButton1Click:Connect(function() if selectSetTab then selectSetTab(name) end end)
	return b
end
makeSetTab("General", 1)
makeSetTab("Keybinds", 2)

local setList = Instance.new("ScrollingFrame")
setList.BackgroundTransparency = 1
setList.BorderSizePixel = 0
setList.Position = UDim2.fromOffset(0, 88)
setList.Size = UDim2.new(1, 0, 1, -96)
setList.ScrollBarThickness = 4
setList.ScrollBarImageColor3 = accent
setList.CanvasSize = UDim2.new()
setList.AutomaticCanvasSize = Enum.AutomaticSize.Y
setList.ScrollingDirection = Enum.ScrollingDirection.Y
setList.Parent = setPanel
local setListPad = Instance.new("UIPadding")
setListPad.PaddingLeft = UDim.new(0, 18); setListPad.PaddingRight = UDim.new(0, 18)
setListPad.PaddingTop = UDim.new(0, 4); setListPad.PaddingBottom = UDim.new(0, 12)
setListPad.Parent = setList
local setListLayout = Instance.new("UIListLayout")
setListLayout.Padding = UDim.new(0, 8)
setListLayout.SortOrder = Enum.SortOrder.LayoutOrder
setListLayout.Parent = setList

createSlider(setList, { name = "FPS cap", min = 30, max = 360, default = fpsCap, decimals = 0, order = 1,
	onChange = function(v) applyFpsCap(v) end })
createCheckbox(setList, { name = "Unlock FPS (999)", default = false, order = 2,
	onChange = function(on) applyFpsCap(on and 999 or fpsCap) end })
createCheckbox(setList, { name = "Low quality (boost FPS)", default = false, order = 3,
	onChange = function(on) applyLowQuality(on) end })
createCheckbox(setList, { name = "Disable shadows", default = false, order = 4,
	onChange = function(on) applyShadows(on) end })
createCheckbox(setList, { name = "Disable post-processing", default = false, order = 5,
	onChange = function(on) applyPostFx(on) end })
createCheckbox(setList, { name = "Remove fog", default = false, order = 6,
	onChange = function(on) applyNoFog(on) end })

-- Fully unload / destroy the script
local destroyDiv = Instance.new("Frame")
destroyDiv.Size = UDim2.new(1, 0, 0, 1)
destroyDiv.BackgroundColor3 = THEME.Stroke
destroyDiv.BorderSizePixel = 0
destroyDiv.LayoutOrder = 90
destroyDiv.Parent = setList

local destroyBtn = Instance.new("TextButton")
destroyBtn.Size = UDim2.new(1, 0, 0, 38)
destroyBtn.BackgroundColor3 = Color3.fromRGB(45, 24, 28)
destroyBtn.AutoButtonColor = false
destroyBtn.Font = Enum.Font.GothamBold
destroyBtn.TextSize = 14
destroyBtn.Text = "Unload / Destroy StatsX"
destroyBtn.TextColor3 = Color3.fromRGB(255, 120, 130)
destroyBtn.LayoutOrder = 91
destroyBtn.Parent = setList
corner(destroyBtn, 9)
stroke(destroyBtn, Color3.fromRGB(220, 70, 80), 1.2, 0.4)

local destroyHint = Instance.new("TextLabel")
destroyHint.BackgroundTransparency = 1
destroyHint.Size = UDim2.new(1, 0, 0, 28)
destroyHint.Font = Enum.Font.Gotham
destroyHint.TextSize = 11
destroyHint.Text = "Turns every feature off (restores your character) and removes the UI. Re-run the script to use it again."
destroyHint.TextColor3 = THEME.SubText
destroyHint.TextXAlignment = Enum.TextXAlignment.Left
destroyHint.TextYAlignment = Enum.TextYAlignment.Top
destroyHint.TextWrapped = true
destroyHint.LayoutOrder = 92
destroyHint.Parent = setList

local function destroyAll()
	if destroyed then return end
	destroyed = true
	for _, f in pairs(Features) do
		pcall(function() if f.get and f.get() then f.set(false) end end)
	end
	pcall(function() gui:Destroy() end)
end
local armed = false
destroyBtn.MouseEnter:Connect(function() tween(destroyBtn, EASE.Hover, { BackgroundColor3 = Color3.fromRGB(220, 70, 80) }) end)
destroyBtn.MouseLeave:Connect(function() tween(destroyBtn, EASE.Hover, { BackgroundColor3 = armed and Color3.fromRGB(150, 40, 48) or Color3.fromRGB(45, 24, 28) }) end)
destroyBtn.MouseButton1Click:Connect(function()
	if not armed then
		armed = true
		destroyBtn.Text = "Click again to confirm"
		tween(destroyBtn, EASE.Snappy, { BackgroundColor3 = Color3.fromRGB(150, 40, 48) })
		task.delay(2.5, function()
			if armed and not destroyed then
				armed = false
				destroyBtn.Text = "Unload / Destroy StatsX"
				tween(destroyBtn, EASE.Snappy, { BackgroundColor3 = Color3.fromRGB(45, 24, 28) })
			end
		end)
		return
	end
	destroyAll()
end)

-- Keybinds tab: every function with its icon + a rebind button
local kbList = Instance.new("ScrollingFrame")
kbList.Name = "KeybindList"
kbList.BackgroundTransparency = 1
kbList.BorderSizePixel = 0
kbList.Position = UDim2.fromOffset(0, 106)
kbList.Size = UDim2.new(1, 0, 1, -114)
kbList.ScrollBarThickness = 4
kbList.ScrollBarImageColor3 = accent
kbList.CanvasSize = UDim2.new()
kbList.AutomaticCanvasSize = Enum.AutomaticSize.None
kbList.ScrollingDirection = Enum.ScrollingDirection.Y
kbList.Visible = false
kbList.Parent = setPanel
local kbPad = Instance.new("UIPadding")
kbPad.PaddingLeft = UDim.new(0, 18); kbPad.PaddingRight = UDim.new(0, 18)
kbPad.PaddingTop = UDim.new(0, 4); kbPad.PaddingBottom = UDim.new(0, 12)
kbPad.Parent = kbList
local kbLayout = Instance.new("UIGridLayout")
kbLayout.CellSize = UDim2.fromOffset(150, 96)
kbLayout.CellPadding = UDim2.fromOffset(10, 10)
kbLayout.FillDirection = Enum.FillDirection.Horizontal
kbLayout.FillDirectionMaxCells = 0 -- auto: fit as many tiles per row as the width allows
kbLayout.StartCorner = Enum.StartCorner.TopLeft
kbLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
kbLayout.SortOrder = Enum.SortOrder.LayoutOrder
kbLayout.Parent = kbList
-- Fixed canvas instead of AutomaticCanvasSize: stops the grid from re-measuring
-- every frame while scrolling, which was what made the tile icons shimmer/glitch.
kbLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	kbList.CanvasSize = UDim2.new(0, 0, 0, kbLayout.AbsoluteContentSize.Y + 16)
end)

local kbHint = Instance.new("TextLabel")
kbHint.BackgroundTransparency = 1
kbHint.Position = UDim2.fromOffset(18, 86)
kbHint.Size = UDim2.new(1, -36, 0, 16)
kbHint.Visible = false
kbHint.Font = Enum.Font.Gotham
kbHint.Text = "Click a key to rebind  -  Backspace clears  -  Esc cancels"
kbHint.TextColor3 = THEME.SubText
kbHint.TextSize = 11
kbHint.TextXAlignment = Enum.TextXAlignment.Left
kbHint.Parent = setPanel

local function buildKeybindRow(fkey, order)
	local feat = Features[fkey]
	if not feat then return end
	local row = Instance.new("Frame")
	row.Name = fkey
	row.Size = UDim2.fromOffset(150, 96)
	row.BackgroundColor3 = THEME.Row
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Parent = kbList
	corner(row, 12)

	local chip = Instance.new("Frame")
	chip.AnchorPoint = Vector2.new(0, 0)
	chip.Position = UDim2.fromOffset(12, 12)
	chip.Size = UDim2.fromOffset(36, 36)
	chip.BackgroundColor3 = feat.color
	chip.BorderSizePixel = 0
	chip.Parent = row
	corner(chip, 10)
	addIcon(chip, ICON_KINDS[fkey] or "target")

	local nameLbl = Instance.new("TextLabel")
	nameLbl.BackgroundTransparency = 1
	nameLbl.Position = UDim2.fromOffset(56, 18)
	nameLbl.Size = UDim2.fromOffset(82, 24)
	nameLbl.Font = Enum.Font.GothamMedium
	nameLbl.Text = feat.name or fkey
	nameLbl.TextColor3 = THEME.Text
	nameLbl.TextSize = 14
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
	nameLbl.Parent = row

	local bind = Instance.new("TextButton")
	bind.AnchorPoint = Vector2.new(0, 1)
	bind.Position = UDim2.new(0, 12, 1, -12)
	bind.Size = UDim2.fromOffset(66, 32)
	bind.BackgroundColor3 = THEME.TrackOff
	bind.AutoButtonColor = false
	bind.Font = Enum.Font.GothamBold
	bind.TextSize = 15
	bind.TextColor3 = THEME.Text
	bind.TextTruncate = Enum.TextTruncate.AtEnd
	bind.Text = keyName(keybinds[fkey])
	bind.Parent = row
	corner(bind, 9)
	local bStroke = stroke(bind, accent, 1.2, 1)
	kbBinds[fkey] = { btn = bind, st = bStroke }
	bind.TextColor3 = keybinds[fkey] and THEME.Text or THEME.SubText

	local clearBtn = Instance.new("TextButton")
	clearBtn.AnchorPoint = Vector2.new(1, 1)
	clearBtn.Position = UDim2.new(1, -12, 1, -12)
	clearBtn.Size = UDim2.fromOffset(48, 32)
	clearBtn.BackgroundColor3 = THEME.TrackOff
	clearBtn.AutoButtonColor = false
	clearBtn.Font = Enum.Font.GothamBold
	clearBtn.TextSize = 12
	clearBtn.TextColor3 = THEME.SubText
	clearBtn.Text = "Clear"
	clearBtn.Parent = row
	corner(clearBtn, 9)
	clearBtn.MouseEnter:Connect(function() tween(clearBtn, EASE.Hover, { BackgroundColor3 = Color3.fromRGB(220, 70, 80) }) end)
	clearBtn.MouseLeave:Connect(function() tween(clearBtn, EASE.Hover, { BackgroundColor3 = THEME.TrackOff }) end)
	clearBtn.MouseButton1Click:Connect(function()
		if listeningKey == fkey then listeningKey = nil end
		keybinds[fkey] = nil
		bind.Text = "None"
		bind.TextColor3 = THEME.SubText
		tween(bStroke, EASE.Snappy, { Transparency = 1 })
	end)

	bind.MouseEnter:Connect(function()
		if listeningKey ~= fkey then tween(bStroke, EASE.Hover, { Transparency = 0.35 }) end
	end)
	bind.MouseLeave:Connect(function()
		if listeningKey ~= fkey then tween(bStroke, EASE.Hover, { Transparency = 1 }) end
	end)
	bind.MouseButton1Click:Connect(function()
		if listeningKey and kbBinds[listeningKey] then
			kbBinds[listeningKey].btn.Text = keyName(keybinds[listeningKey])
			tween(kbBinds[listeningKey].st, EASE.Snappy, { Transparency = 1 })
		end
		listeningKey = fkey
		bind.Text = "..."
		tween(bStroke, EASE.Snappy, { Transparency = 0 })
	end)
end

local KB_ORDER = { "fullbright", "esp", "fov", "rainbow", "clean", "walk", "jump", "infjump", "fly", "noclip", "gravity", "speed", "afk", "visibility", "aimlock" }
for i, k in ipairs(KB_ORDER) do buildKeybindRow(k, i) end

selectSetTab = function(name)
	setTabActive = name
	setList.Visible = (name == "General")
	kbList.Visible = (name == "Keybinds")
	kbHint.Visible = (name == "Keybinds")
	for n, b in pairs(setTabBtns) do
		local on = (n == name)
		tween(b, EASE.Snappy, { BackgroundColor3 = on and accent or THEME.Row, TextColor3 = on and Color3.fromRGB(22, 22, 30) or THEME.SubText })
	end
end
selectSetTab("General")

-- keep the whole popup above the main window + grip
setPanel.ZIndex = 50
for _, d in ipairs(setPanel:GetDescendants()) do
	if d:IsA("GuiObject") then d.ZIndex = d.ZIndex + 50 end
end

makeDraggable(setHeader, setPanel)

local function toggleSettings()
	setOpen = not setOpen
	if setOpen then
		setPanel.Visible = true
		setPanel.Size = UDim2.fromOffset(380, 220)
		setPanel.BackgroundTransparency = 0.45
		setStroke.Transparency = 1
		tween(setPanel, EASE.Open, { Size = setSize, BackgroundTransparency = 0 })
		tween(setStroke, EASE.Smooth, { Transparency = 0.25 })
	else
		-- clean fold-and-fade close: hide glyph content instantly so only the empty rounded frame folds (kills icon reflow flicker)
		setList.Visible = false
		kbList.Visible = false
		kbHint.Visible = false
		tween(setPanel, EASE.Smooth, { Size = UDim2.fromOffset(math.max(setSize.X.Offset - 14, 120), 0), BackgroundTransparency = 0.7 })
		tween(setStroke, EASE.Smooth, { Transparency = 1 })
		task.delay(0.42, function()
			if not setOpen then
				setPanel.Visible = false
				setPanel.Size = setSize
				setPanel.BackgroundTransparency = 0
				setStroke.Transparency = 0.25
				selectSetTab(setTabActive)
			end
		end)
	end
end
gearBtn.MouseButton1Click:Connect(toggleSettings)
setClose.MouseButton1Click:Connect(function() if setOpen then toggleSettings() end end)

----------------------------------------------------------------------
-- Global keybind listener: toggle features by key / capture rebinds
----------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if destroyed then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if listeningKey then
		local fkey = listeningKey
		local code = input.KeyCode
		if code == Enum.KeyCode.Escape then
			-- cancel: keep existing bind
		elseif code == Enum.KeyCode.Backspace or code == Enum.KeyCode.Delete then
			keybinds[fkey] = nil
		else
			for k, c in pairs(keybinds) do
				if c == code and k ~= fkey then
					keybinds[k] = nil
					if kbBinds[k] then
						kbBinds[k].btn.Text = "None"
						kbBinds[k].btn.TextColor3 = THEME.SubText
					end
				end
			end
			keybinds[fkey] = code
		end
		if kbBinds[fkey] then
			kbBinds[fkey].btn.Text = keyName(keybinds[fkey])
			kbBinds[fkey].btn.TextColor3 = keybinds[fkey] and THEME.Text or THEME.SubText
			tween(kbBinds[fkey].st, EASE.Snappy, { Transparency = 1 })
		end
		listeningKey = nil
		return
	end
	if capturingKey then return end
	if gameProcessed then return end
	for fkey, code in pairs(keybinds) do
		if code and input.KeyCode == code then
			local feat = Features[fkey]
			if feat and feat.set then feat.set(not feat.get()) end
		end
	end
end)

-- ============================================================
-- Config save/load (persists toggles + keybinds). Wrapped in its
-- own function so its locals don't count against buildSettings.
-- ============================================================
local function setupConfigIO()
	local HttpService = game:GetService("HttpService")
	local CONFIG_PATH = "StatsX_config.json"
	local hasWrite = (writefile ~= nil)
	local hasRead = (readfile ~= nil) and (isfile ~= nil)
	local saveBtn, loadBtn

	local function flash(btn, base, msg)
		if not btn then return end
		btn.Text = msg
		task.delay(1.1, function()
			if btn and btn.Parent then btn.Text = base end
		end)
	end

	local function saveConfig()
		local cfg = { toggles = {}, binds = {} }
		for key, feat in pairs(Features) do
			local ok, v = pcall(feat.get)
			cfg.toggles[key] = (ok and v) and true or false
		end
		for fkey, code in pairs(keybinds) do
			if code then cfg.binds[fkey] = code.Name end
		end
		cfg.aimToggleMode = StatsXAim.toggleMode and true or false
		local ok, json = pcall(function() return HttpService:JSONEncode(cfg) end)
		if not (ok and hasWrite) then flash(saveBtn, "Save config", "Unsupported"); return end
		local wok = pcall(function() writefile(CONFIG_PATH, json) end)
		flash(saveBtn, "Save config", wok and "Saved!" or "Failed")
	end

	local function loadConfig(silent)
		if not hasRead then if not silent then flash(loadBtn, "Load config", "Unsupported") end return end
		local exists = false
		pcall(function() exists = isfile(CONFIG_PATH) end)
		if not exists then if not silent then flash(loadBtn, "Load config", "No save") end return end
		local rok, raw = pcall(function() return readfile(CONFIG_PATH) end)
		if not rok or type(raw) ~= "string" then return end
		local dok, cfg = pcall(function() return HttpService:JSONDecode(raw) end)
		if not dok or type(cfg) ~= "table" then return end
		if type(cfg.toggles) == "table" then
			for key, on in pairs(cfg.toggles) do
				local feat = Features[key]
				if feat and feat.set then pcall(function() feat.set(on and true or false) end) end
			end
		end
		if type(cfg.binds) == "table" then
			for fkey, name in pairs(cfg.binds) do
				if type(name) == "string" then
					local okc, code = pcall(function() return Enum.KeyCode[name] end)
					if okc and code then
						keybinds[fkey] = code
						if kbBinds[fkey] then
							kbBinds[fkey].btn.Text = keyName(code)
							kbBinds[fkey].btn.TextColor3 = THEME.Text
						end
					end
				end
			end
		end
		if type(cfg.aimToggleMode) == "boolean" then
			StatsXAim.toggleMode = cfg.aimToggleMode
			StatsXAim.toggled = false
		end
		if not silent then flash(loadBtn, "Load config", "Loaded!") end
	end

	-- UI row: Save / Load buttons (sit just above the destroy divider)
	local cfgRow = Instance.new("Frame")
	cfgRow.Name = "ConfigRow"
	cfgRow.BackgroundTransparency = 1
	cfgRow.Size = UDim2.new(1, 0, 0, 34)
	cfgRow.LayoutOrder = 80
	cfgRow.Parent = setList
	local cfgBtnLayout = Instance.new("UIListLayout")
	cfgBtnLayout.FillDirection = Enum.FillDirection.Horizontal
	cfgBtnLayout.Padding = UDim.new(0, 8)
	cfgBtnLayout.SortOrder = Enum.SortOrder.LayoutOrder
	cfgBtnLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	cfgBtnLayout.Parent = cfgRow

	local function mkBtn(text, order)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0.5, -4, 1, 0)
		b.BackgroundColor3 = THEME.Row
		b.AutoButtonColor = false
		b.Font = Enum.Font.GothamMedium
		b.TextSize = 13
		b.Text = text
		b.TextColor3 = THEME.Text
		b.LayoutOrder = order
		b.Parent = cfgRow
		corner(b, 8)
		stroke(b, THEME.Stroke, 1, 0.3)
		b.MouseEnter:Connect(function() tween(b, EASE.Hover, { BackgroundColor3 = THEME.RowHover }) end)
		b.MouseLeave:Connect(function() tween(b, EASE.Hover, { BackgroundColor3 = THEME.Row }) end)
		return b
	end

	saveBtn = mkBtn("Save config", 1)
	loadBtn = mkBtn("Load config", 2)
	saveBtn.MouseButton1Click:Connect(saveConfig)
	loadBtn.MouseButton1Click:Connect(function() loadConfig(false) end)

	-- Auto-load saved config once the full UI (incl. Stage 4) has built.
	task.spawn(function()
		task.wait(0.7)
		pcall(loadConfig, true)
	end)
end
setupConfigIO()

end -- buildSettings
buildSettings()

----------------------------------------------------------------------
-- Live clock loop for the dock
----------------------------------------------------------------------
task.spawn(function()
	while gui.Parent do
		dockClock.Text = os.date("%H:%M")
		task.wait(5)
	end
end)

----------------------------------------------------------------------
-- Entrance animation
----------------------------------------------------------------------
main.Visible = false

local function playEntrance()
	main.Visible = true
	main.Position = OPEN_POS
	main.Size = UDim2.fromOffset(OPEN_SIZE.X.Offset * 0.8, OPEN_SIZE.Y.Offset * 0.8)
	main.BackgroundTransparency = 0.3
	tween(main, EASE.Open, { Size = OPEN_SIZE })
	tween(main, EASE.Smooth, { BackgroundTransparency = 0 })
end

task.spawn(function()
	for _, g in ipairs(gui.Parent:GetChildren()) do
		if g.Name == "StatsXSplash" then g:Destroy() end
	end

	local splash = Instance.new("ScreenGui")
	splash.Name = "StatsXSplash"
	splash.ResetOnSpawn = false
	splash.IgnoreGuiInset = true
	splash.DisplayOrder = 100000
	splash.Parent = gui.Parent

	local scrim = Instance.new("Frame")
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = THEME.Background
	scrim.BackgroundTransparency = 1
	scrim.BorderSizePixel = 0
	scrim.Parent = splash

	local center = Instance.new("Frame")
	center.AnchorPoint = Vector2.new(0.5, 0.5)
	center.Position = UDim2.fromScale(0.5, 0.5)
	center.Size = UDim2.fromOffset(440, 220)
	center.BackgroundTransparency = 1
	center.Parent = scrim

	local logo = Instance.new("Frame")
	logo.AnchorPoint = Vector2.new(0.5, 0.5)
	logo.Position = UDim2.fromScale(0.5, 0.34)
	logo.Size = UDim2.fromOffset(460, 112)
	logo.BackgroundTransparency = 1
	logo.Parent = center
	local logoRow = Instance.new("UIListLayout")
	logoRow.FillDirection = Enum.FillDirection.Horizontal
	logoRow.HorizontalAlignment = Enum.HorizontalAlignment.Center
	logoRow.VerticalAlignment = Enum.VerticalAlignment.Center
	logoRow.SortOrder = Enum.SortOrder.LayoutOrder
	logoRow.Padding = UDim.new(0, 1)
	logoRow.Parent = logo
	local logoScale = Instance.new("UIScale")
	logoScale.Scale = 0.8
	logoScale.Parent = logo

	local statsLbl = Instance.new("TextLabel")
	statsLbl.AutomaticSize = Enum.AutomaticSize.XY
	statsLbl.LayoutOrder = 1
	statsLbl.BackgroundTransparency = 1
	statsLbl.Font = Enum.Font.GothamBlack
	statsLbl.Text = "STATS"
	statsLbl.TextSize = 60
	statsLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	statsLbl.TextTransparency = 1
	statsLbl.Parent = logo
	local sg = Instance.new("UIGradient")
	sg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(90, 140, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(124, 110, 255)),
	})
	sg.Parent = statsLbl

	local xLbl = Instance.new("TextLabel")
	xLbl.AutomaticSize = Enum.AutomaticSize.XY
	xLbl.LayoutOrder = 2
	xLbl.BackgroundTransparency = 1
	xLbl.Font = Enum.Font.GothamBlack
	xLbl.Text = "X"
	xLbl.TextSize = 96
	xLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	xLbl.TextTransparency = 1
	xLbl.Parent = logo
	local xg = Instance.new("UIGradient")
	xg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(124, 110, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 60, 230)),
	})
	xg.Parent = xLbl

	local loadingLbl = Instance.new("TextLabel")
	loadingLbl.AnchorPoint = Vector2.new(0.5, 0.5)
	loadingLbl.Position = UDim2.fromScale(0.5, 0.66)
	loadingLbl.Size = UDim2.fromOffset(320, 26)
	loadingLbl.BackgroundTransparency = 1
	loadingLbl.Font = Enum.Font.GothamBold
	loadingLbl.Text = "loading.."
	loadingLbl.TextSize = 18
	loadingLbl.TextColor3 = THEME.SubText
	loadingLbl.TextTransparency = 1
	loadingLbl.Parent = center

	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.Position = UDim2.fromScale(0.5, 0.8)
	track.Size = UDim2.fromOffset(280, 8)
	track.BackgroundColor3 = THEME.Row
	track.BackgroundTransparency = 1
	track.BorderSizePixel = 0
	track.Parent = center
	corner(track, 4)
	local tStroke = stroke(track, THEME.Stroke, 1, 1)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = accent
	fill.BackgroundTransparency = 1
	fill.BorderSizePixel = 0
	fill.Parent = track
	corner(fill, 4)
	gradient(fill, Color3.fromRGB(90, 140, 255), Color3.fromRGB(120, 60, 230), 0)

	-- intro: logo fades + scales up (no backdrop)
	tween(statsLbl, EASE.Open, { TextTransparency = 0 })
	tween(xLbl, EASE.Open, { TextTransparency = 0 })
	tween(logoScale, EASE.Open, { Scale = 1 })
	task.wait(0.55)
	-- loading label + progress bar appear
	tween(loadingLbl, EASE.Smooth, { TextTransparency = 0 })
	tween(track, EASE.Smooth, { BackgroundTransparency = 0 })
	tween(tStroke, EASE.Smooth, { Transparency = 0.4 })
	tween(fill, EASE.Smooth, { BackgroundTransparency = 0 })
	-- fill the bar over ~1.8s
	tween(fill, TweenInfo.new(1.8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = UDim2.new(1, 0, 1, 0) })
	task.wait(1.95)
	-- everything fades out
	tween(statsLbl, EASE.Smooth, { TextTransparency = 1 })
	tween(xLbl, EASE.Smooth, { TextTransparency = 1 })
	tween(logoScale, EASE.Smooth, { Scale = 1.08 })
	tween(loadingLbl, EASE.Smooth, { TextTransparency = 1 })
	tween(track, EASE.Smooth, { BackgroundTransparency = 1 })
	tween(tStroke, EASE.Smooth, { Transparency = 1 })
	tween(fill, EASE.Smooth, { BackgroundTransparency = 1 })
	task.wait(0.45)
	splash:Destroy()
	-- UI pops up after the splash has faded
	playEntrance()
	task.wait(0.5)
	if Features["clean"] then Features["clean"].set(true) end
end)

----------------------------------------------------------------------
-- Resize grip (bottom-right of the main window)
----------------------------------------------------------------------
grip = Instance.new("TextButton")
grip.Name = "ResizeGrip"
grip.AnchorPoint = Vector2.new(1, 1)
grip.Position = UDim2.new(1, -5, 1, -5)
grip.Size = UDim2.fromOffset(22, 22)
grip.BackgroundTransparency = 1
grip.Text = ""
grip.AutoButtonColor = false
grip.ZIndex = 6
grip.Parent = main
for i = 1, 3 do
	local g = Instance.new("Frame")
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.Position = UDim2.fromOffset(20 - i * 4, 20 - i * 4)
	g.Size = UDim2.fromOffset(2, i * 6)
	g.Rotation = 45
	g.BackgroundColor3 = THEME.SubText
	g.BorderSizePixel = 0
	g.ZIndex = 7
	g.Parent = grip
	corner(g, 1)
end

local resizing, resizeStartMouse, resizeStartSize
grip.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		resizing = true
		resizeStartMouse = input.Position
		resizeStartSize = main.AbsoluteSize
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then resizing = false end
		end)
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - resizeStartMouse
		local nw = math.clamp(resizeStartSize.X + delta.X * 2, 360, 760)
		local nh = math.clamp(resizeStartSize.Y + delta.Y * 2, 380, 780)
		OPEN_SIZE = UDim2.fromOffset(nw, nh)
		if not minimized then
			main.Size = OPEN_SIZE
			main.Position = OPEN_POS
		end
	end
end)

----------------------------------------------------------------------
-- Credits footer (pinned to the bottom of the window)
----------------------------------------------------------------------
local creditLbl = Instance.new("TextLabel")
creditLbl.Name = "Credits"
creditLbl.AnchorPoint = Vector2.new(1, 1)
creditLbl.Position = UDim2.new(1, -32, 1, -7)
creditLbl.Size = UDim2.fromOffset(190, 13)
creditLbl.BackgroundTransparency = 1
creditLbl.Font = Enum.Font.GothamMedium
creditLbl.Text = "Credits: @cammyisafemboy"
creditLbl.TextSize = 10
creditLbl.TextColor3 = THEME.SubText
creditLbl.TextXAlignment = Enum.TextXAlignment.Right
creditLbl.ZIndex = 40
creditLbl.Parent = body

----------------------------------------------------------------------
-- Search bar (filters feature rows by name across all tabs)
----------------------------------------------------------------------
local searchBox = Instance.new("Frame")
searchBox.Name = "SearchBar"
searchBox.BackgroundColor3 = THEME.Row
searchBox.BorderSizePixel = 0
searchBox.Position = UDim2.fromOffset(18, 110)
searchBox.Size = UDim2.new(1, -36, 0, 30)
searchBox.Parent = body
corner(searchBox, 9)
local searchStroke = stroke(searchBox, THEME.Stroke, 1, 0.3)

local searchInput = Instance.new("TextBox")
searchInput.Name = "Input"
searchInput.BackgroundTransparency = 1
searchInput.Position = UDim2.fromOffset(12, 0)
searchInput.Size = UDim2.new(1, -24, 1, 0)
searchInput.Font = Enum.Font.Gotham
searchInput.PlaceholderText = "Search features..."
searchInput.PlaceholderColor3 = THEME.SubText
searchInput.Text = ""
searchInput.TextColor3 = THEME.Text
searchInput.TextSize = 13
searchInput.TextXAlignment = Enum.TextXAlignment.Left
searchInput.ClearTextOnFocus = false
searchInput.Parent = searchBox

searchInput.Focused:Connect(function()
	tween(searchStroke, EASE.Hover, { Color = accent, Transparency = 0.2 })
end)
searchInput.FocusLost:Connect(function()
	tween(searchStroke, EASE.Hover, { Color = THEME.Stroke, Transparency = 0.3 })
end)

local function applySearch(q)
	q = string.lower(q or "")
	if q == "" then
		selectTab(activeTab)
		return
	end
	for _, container in ipairs(allRows) do
		local feat = Features[container.Name]
		local nm = feat and string.lower(feat.name) or string.lower(container.Name)
		container.Visible = (string.find(nm, q, 1, true) ~= nil)
	end
	list.CanvasPosition = Vector2.new(0, 0)
end
searchInput:GetPropertyChangedSignal("Text"):Connect(function()
	applySearch(searchInput.Text)
end)

-- Search toggle: fades the bar out and reflows the function list up/down
-- Wrapped in a function so its locals do not count against Luau's 200 main-chunk register limit
local function setupSearchToggle()
local searchToggle = Instance.new("TextButton")
searchToggle.Name = "SearchToggle"
searchToggle.AnchorPoint = Vector2.new(1, 0)
searchToggle.Position = UDim2.new(1, -18, 0, 72)
searchToggle.Size = UDim2.fromOffset(34, 34)
searchToggle.BackgroundColor3 = THEME.Row
searchToggle.Text = ""
searchToggle.AutoButtonColor = false
searchToggle.Parent = body
corner(searchToggle, 10)
stroke(searchToggle, THEME.Stroke, 1, 0.4)

local magRing = Instance.new("Frame")
magRing.AnchorPoint = Vector2.new(0.5, 0.5)
magRing.Position = UDim2.new(0.5, -2, 0.5, -2)
magRing.Size = UDim2.fromOffset(13, 13)
magRing.BackgroundTransparency = 1
magRing.Parent = searchToggle
corner(magRing, 7)
local magStroke = stroke(magRing, accent, 2, 0)
local magHandle = Instance.new("Frame")
magHandle.AnchorPoint = Vector2.new(0.5, 0.5)
magHandle.Position = UDim2.new(0.5, 7, 0.5, 7)
magHandle.Size = UDim2.fromOffset(2, 7)
magHandle.Rotation = 45
magHandle.BorderSizePixel = 0
magHandle.BackgroundColor3 = accent
magHandle.Parent = searchToggle
corner(magHandle, 1)

local SEARCH_FADE = TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local LIST_SHOWN = { Position = UDim2.fromOffset(0, 148), Size = UDim2.new(1, 0, 1, -186) }
local LIST_HIDDEN = { Position = UDim2.fromOffset(0, 112), Size = UDim2.new(1, 0, 1, -150) }
local searchHidden = false
local searchSeq = 0
local function setSearchHidden(hide)
	searchHidden = hide
	searchSeq = searchSeq + 1
	local token = searchSeq
	tween(magStroke, EASE.Hover, { Color = hide and THEME.SubText or accent })
	tween(magHandle, EASE.Hover, { BackgroundColor3 = hide and THEME.SubText or accent })
	if hide then
		searchInput.TextEditable = false
		searchInput.Text = ""
		tween(searchBox, SEARCH_FADE, { BackgroundTransparency = 1 })
		tween(searchStroke, SEARCH_FADE, { Transparency = 1 })
		tween(searchInput, SEARCH_FADE, { TextTransparency = 1 })
		task.spawn(function()
			task.wait(0.1)
			if token ~= searchSeq then return end
			searchBox.Visible = false
			tween(list, EASE.Smooth, LIST_HIDDEN)
		end)
	else
		searchBox.Visible = true
		tween(list, EASE.Smooth, LIST_SHOWN)
		task.spawn(function()
			task.wait(0.14)
			if token ~= searchSeq then return end
			searchInput.TextEditable = true
			tween(searchBox, SEARCH_FADE, { BackgroundTransparency = 0 })
			tween(searchStroke, SEARCH_FADE, { Transparency = 0.3 })
			tween(searchInput, SEARCH_FADE, { TextTransparency = 0 })
		end)
	end
end
searchToggle.MouseButton1Click:Connect(function() setSearchHidden(not searchHidden) end)
searchToggle.MouseEnter:Connect(function() tween(searchToggle, EASE.Hover, { BackgroundColor3 = THEME.RowHover }) end)
searchToggle.MouseLeave:Connect(function() tween(searchToggle, EASE.Hover, { BackgroundColor3 = THEME.Row }) end)
end
setupSearchToggle()

----------------------------------------------------------------------
-- Stage 4: overpowered extras (fling, hitbox)
-- Wrapped in one function so all its locals stay out of the main chunk
-- (Luau caps a function at 200 local registers).
----------------------------------------------------------------------
local function setupOverpowered()

	-- Fling: pick a player; we briefly snap onto them with huge velocity to
	-- launch THEM, then restore our own position/velocity so we don't fly off.
	local flingPower = 1
	local flingBusy = false
	local function flingStop()
		flingBusy = false
		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			pcall(function()
				hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
				hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			end)
		end
	end
	local function flingAtPlayer(plr)
		if not plr or flingBusy then return end
		local char = LocalPlayer.Character
		local myh = char and char:FindFirstChild("HumanoidRootPart")
		local th = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if not (myh and th) then return end
		flingBusy = true
		local origCFrame = myh.CFrame
		task.spawn(function()
			local frames = math.floor(12 + flingPower * 6)
			for _ = 1, frames do
				if destroyed or not flingBusy then break end
				local tnow = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
				if not tnow then break end
				pcall(function()
					myh.CFrame = tnow.CFrame
					myh.AssemblyLinearVelocity = Vector3.new(9999, 9999, 9999) * flingPower
					myh.AssemblyAngularVelocity = Vector3.new(9000, 9000, 9000) * flingPower
				end)
				RunService.Heartbeat:Wait()
			end
			-- snap ourselves back so the fling doesn't throw us too
			pcall(function()
				myh.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
				myh.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
				if origCFrame then myh.CFrame = origCFrame end
			end)
			flingBusy = false
		end)
	end

	createToggle({
		key = "fling", name = "Fling", desc = "Teleport to a player and spin-fling them",
		color = Color3.fromRGB(255, 150, 60), short = "FLG", order = 21,
		onEnable = function() end,
		onDisable = flingStop,
		buildConfig = function(cfg)
			createSlider(cfg, { name = "Fling power", min = 1, max = 10, default = flingPower, decimals = 1, order = 1,
				onChange = function(v) flingPower = v end })

			createButton(cfg, { name = "Stop fling", order = 2, onClick = function() flingStop() end })

			local flLbl = Instance.new("TextLabel")
			flLbl.BackgroundTransparency = 1
			flLbl.Size = UDim2.new(1, 0, 0, 18)
			flLbl.Font = Enum.Font.GothamMedium
			flLbl.Text = "Select a player to fling"
			flLbl.TextColor3 = THEME.SubText
			flLbl.TextSize = 12
			flLbl.TextXAlignment = Enum.TextXAlignment.Left
			flLbl.LayoutOrder = 3
			flLbl.Parent = cfg

			local flScroll = Instance.new("ScrollingFrame")
			flScroll.Size = UDim2.new(1, 0, 0, 116)
			flScroll.BackgroundTransparency = 1
			flScroll.BorderSizePixel = 0
			flScroll.ScrollBarThickness = 3
			flScroll.ScrollBarImageColor3 = accent
			flScroll.CanvasSize = UDim2.new()
			flScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
			flScroll.ScrollingDirection = Enum.ScrollingDirection.Y
			flScroll.LayoutOrder = 4
			flScroll.Parent = cfg
			local flLayout = Instance.new("UIListLayout")
			flLayout.Padding = UDim.new(0, 4)
			flLayout.SortOrder = Enum.SortOrder.LayoutOrder
			flLayout.Parent = flScroll

			local function refreshFlingPlayers()
				for _, ch in ipairs(flScroll:GetChildren()) do
					if ch:IsA("TextButton") or ch:IsA("TextLabel") then ch:Destroy() end
				end
				local i = 0
				for _, plr in ipairs(Players:GetPlayers()) do
					if plr ~= LocalPlayer then
						i = i + 1
						createButton(flScroll, { name = plr.Name, order = i, onClick = function() flingAtPlayer(plr) end })
					end
				end
				if i == 0 then
					local none = Instance.new("TextLabel")
					none.BackgroundTransparency = 1
					none.Size = UDim2.new(1, 0, 0, 24)
					none.Font = Enum.Font.Gotham
					none.Text = "No other players"
					none.TextColor3 = THEME.SubText
					none.TextSize = 12
					none.Parent = flScroll
				end
			end
			refreshFlingPlayers()
			Players.PlayerAdded:Connect(function() if not destroyed then task.defer(refreshFlingPlayers) end end)
			Players.PlayerRemoving:Connect(function() if not destroyed then task.defer(refreshFlingPlayers) end end)

			createButton(cfg, { name = "Refresh list", order = 5, onClick = refreshFlingPlayers })

			local flNote = Instance.new("TextLabel")
			flNote.BackgroundTransparency = 1
			flNote.Size = UDim2.new(1, 0, 0, 30)
			flNote.Font = Enum.Font.Gotham
			flNote.Text = "Spam TP to a player to fling them to the farlands"
			flNote.TextColor3 = THEME.SubText
			flNote.TextSize = 11
			flNote.TextWrapped = true
			flNote.TextXAlignment = Enum.TextXAlignment.Left
			flNote.LayoutOrder = 6
			flNote.Parent = cfg
		end,
	})

	-- Hitbox expander: enlarge other players' root parts for easier hits.
	local hitboxOn = false
	local hitboxSize = 10
	local hitboxConn = nil
	local hitboxStore = {}
	local function hitboxStop()
		hitboxOn = false
		if hitboxConn then hitboxConn:Disconnect(); hitboxConn = nil end
		for hrp, size in pairs(hitboxStore) do
			if hrp and hrp.Parent then
				pcall(function()
					hrp.Size = size
					hrp.Transparency = 1
				end)
			end
		end
		hitboxStore = {}
	end
	local function hitboxStart()
		hitboxOn = true
		if hitboxConn then hitboxConn:Disconnect() end
		hitboxConn = RunService.Heartbeat:Connect(function()
			if destroyed or not hitboxOn then return end
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= LocalPlayer and plr.Character then
					local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
					if hrp then
						if hitboxStore[hrp] == nil then hitboxStore[hrp] = hrp.Size end
						pcall(function()
							hrp.Size = Vector3.new(hitboxSize, hitboxSize, hitboxSize)
							hrp.Transparency = 0.7
							hrp.CanCollide = false
						end)
					end
				end
			end
		end)
	end

	createToggle({
		key = "hitbox", name = "Hitbox Expander", desc = "Enlarge other players' hitboxes",
		color = Color3.fromRGB(180, 120, 255), short = "HB", order = 22,
		onEnable = hitboxStart,
		onDisable = hitboxStop,
		buildConfig = function(cfg)
			createSlider(cfg, { name = "Hitbox size", min = 3, max = 30, default = hitboxSize, decimals = 0, order = 1,
				onChange = function(v) hitboxSize = v end })
		end,
	})
end
setupOverpowered()

-- Start on the first tab
selectTab(activeTab)

print("[StatsX] Loaded successfully into: " .. tostring(gui.Parent))
