-- Pints Shield Arcs: Ancestral Fortitude (shamans). When your Ancestral Healing talent gives someone Ancestral Fortitude
-- (+25% armor for 15 seconds after your healing spell crits), an icon sits at the top of the arcs with their name
-- and the seconds left - up to three at once.
--   Classic Era: read from the combat log (exact).
--   WoW Forever: the combat log is closed to add-ons, so the buff is looked for on your group members and target.
--   The game may hide auras in a fight there; then only what it shows can be caught.
-- /sarc af turns it on or off; /sarc af test shows an example.
local SA = _G.ShieldArcs
if not SA then return end
local _, CLASS = UnitClass("player")
if CLASS ~= "SHAMAN" then return end

local SECRET = type(issecretvalue) == "function"
local function IsSecret(v) return SECRET and issecretvalue(v) end
local GetSpellInfo = GetSpellInfo or function(s)
  local i = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(s)
  if i then return i.name, nil, i.iconID end
end
local AF_IDS = { [16177] = true, [16236] = true, [16237] = true }
local AF_NAME, _, AF_ICON = GetSpellInfo(16237)
AF_NAME = AF_NAME or "Ancestral Fortitude"
AF_ICON = AF_ICON or "Interface\\Icons\\Spell_Nature_UndyingStrength"
local DURATION, MAXN, SIZE = 15, 3, 28

local holder = CreateFrame("Frame", nil, _G.ShieldArcsFrame or UIParent)
holder:SetSize(1, 1)
local icons, active = {}, {}     -- active[name] = { expires = time, class = "SHAMAN" }

local function Icon(i)
  local b = icons[i]
  if b then return b end
  b = CreateFrame("Frame", nil, holder); b:SetSize(SIZE, SIZE)
  b.edge = b:CreateTexture(nil, "BACKGROUND"); b.edge:SetPoint("TOPLEFT", -1, 1); b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
  b.edge:SetColorTexture(0, 0, 0, 0.9)
  b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints(); b.tex:SetTexture(AF_ICON); b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.time = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal"); b.time:SetPoint("CENTER", 0, 0)
  b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); b.name:SetPoint("TOP", b, "BOTTOM", 0, -2)
  b.name:SetShadowOffset(1, -1)
  icons[i] = b
  return b
end

local function On() local db = SA.db; return db and db.ancestral ~= false end

local function Draw()
  local now = GetTime()
  local list = {}
  for name, e in pairs(active) do
    if e.expires > now then list[#list + 1] = { name, e } else active[name] = nil end
  end
  table.sort(list, function(a, b) return a[2].expires > b[2].expires end)
  local n = math.min(#list, MAXN)
  -- the top of the arcs: centred between the right and left arcs' upper ends
  local db = SA.db
  local top = (db and db.radius or 150) * math.sin(math.rad(db and db.arc or 42)) + 14
  holder:ClearAllPoints(); holder:SetPoint("CENTER", _G.ShieldArcsFrame or UIParent, "CENTER", 0, top)
  for i = 1, n do
    local b, name, e = Icon(i), list[i][1], list[i][2]
    b:ClearAllPoints(); b:SetPoint("BOTTOM", holder, "CENTER", (i - (n + 1) / 2) * (SIZE + 34), 0)
    b.time:SetText(math.ceil(e.expires - now))
    local c = e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
    b.name:SetText((name:gsub("%-.*$", "")))
    if c then b.name:SetTextColor(c.r, c.g, c.b) else b.name:SetTextColor(1, 1, 1) end
    b:Show()
  end
  for i = n + 1, #icons do icons[i]:Hide() end
  holder:SetShown(On() and n > 0)
end

local function Add(name, unitOrClass, expires)
  if not On() or not name or name == "" then return end
  local class = unitOrClass
  if unitOrClass and UnitExists(unitOrClass) then class = select(2, UnitClass(unitOrClass)) end
  local cur = active[name]
  -- (no expiry from the game: keep the countdown already running rather than restart it on every aura change)
  if not expires and cur and cur.expires > GetTime() and cur.guessed then cur.class = cur.class or class; Draw(); return end
  active[name] = { expires = expires or (GetTime() + DURATION), class = class, guessed = (expires == nil) }
  Draw()
end

-- Classic Era: the combat log says exactly whose heal gave it and to whom
local ev = CreateFrame("Frame")
local me
if not SECRET and CombatLogGetCurrentEventInfo then
  ev:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end
-- WoW Forever (and a back-up on Classic Era): look for the buff on your group and target when their auras change
local UNITS = { "player", "target", "party1", "party2", "party3", "party4" }
for i = 1, 40 do UNITS[#UNITS + 1] = "raid" .. i end
local watch = {}
for _, u in ipairs(UNITS) do watch[u] = true end
pcall(ev.RegisterEvent, ev, "UNIT_AURA")
ev:RegisterEvent("PLAYER_LOGIN")

local function Scan(u)
  if not UnitExists(u) then return end
  for i = 1, 40 do
    local ok, d = pcall(function() return C_UnitAuras and C_UnitAuras.GetAuraDataByIndex(u, i, "HELPFUL") end)
    if not ok then return end                    -- (blocked in a fight on WoW Forever: nothing to catch)
    if not d then
      -- read every buff and it's not there (any more): drop them
      local n = UnitName(u)
      if n and active[n] then active[n] = nil; Draw() end
      return
    end
    local id, name = d.spellId, d.name
    if not IsSecret(id) and not IsSecret(name) and (AF_IDS[id] or name == AF_NAME) then
      local src = d.sourceUnit
      local mine = (not IsSecret(src)) and src and UnitIsUnit(src, "player")
      if mine then
        local exp = d.expirationTime
        Add(UnitName(u), u, (not IsSecret(exp) and exp and exp > 0) and exp or nil)
      end
      return
    end
  end
end

ev:SetScript("OnEvent", function(_, e, unit)
  if e == "PLAYER_LOGIN" then me = UnitGUID("player"); return end
  if e == "COMBAT_LOG_EVENT_UNFILTERED" then
    local _, sub, _, srcGUID, _, _, _, _, destName, _, _, spellId, spellName = CombatLogGetCurrentEventInfo()
    if srcGUID ~= me then return end
    if (sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REFRESH") and (AF_IDS[spellId] or spellName == AF_NAME) then
      Add(destName, nil)
      -- the class colour, when they're in your group
      for _, u in ipairs(UNITS) do if UnitExists(u) and UnitName(u) == (destName or ""):gsub("%-.*$", "") then active[destName].class = select(2, UnitClass(u)); break end end
      Draw()
    elseif sub == "SPELL_AURA_REMOVED" and (AF_IDS[spellId] or spellName == AF_NAME) and destName then
      active[destName] = nil; Draw()
    end
    return
  end
  if e == "UNIT_AURA" and watch[unit] and SECRET then pcall(Scan, unit) end
end)

-- the countdown
local acc = 0
holder:SetScript("OnUpdate", function(_, el)
  acc = acc + el
  if acc < 0.2 then return end
  acc = 0
  Draw()
end)

-- /sarc af: on or off   /sarc af test: an example
SA.AncestralTest = function()
  Add(UnitName("player"), "player")
  local t = UnitExists("target") and UnitIsFriend("player", "target") and UnitName("target")
  if t and t ~= UnitName("player") then Add(t, "target") end
end
SA.AncestralToggle = function()
  SA.db.ancestral = (SA.db.ancestral == false) and true or false
  print("|cff66ccffPints Shield Arcs|r Ancestral Fortitude icon " .. (SA.db.ancestral and "on." or "off."))
  Draw()
end
