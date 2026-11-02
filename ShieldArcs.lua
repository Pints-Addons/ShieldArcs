-- Pints Shield Arcs: curved combat meters around your character.
-- Right side: Power Word: Shield, Ice Barrier, Health, Mana.  Left side: Mana Shield, Combo points, Energy, Rage.
-- Every arc has its own settings (show/hide, icon, number, position, distance, thickness, length, colors),
-- edited from the options window (minimap button or /sarc).
-- Shield amounts aren't reported by the game, so each shield starts from its rank value (+ spell power share),
-- subtracts every SPELL_ABSORBED from the combat log, and learns its real size when it breaks.

local ADDON = ...
local _, CLASS = UnitClass("player")
local sin, cos, rad, floor, max, min = math.sin, math.cos, math.rad, math.floor, math.max, math.min

local frame = CreateFrame("Frame", "ShieldArcsFrame", UIParent)
frame:SetSize(1, 1)
frame:SetFrameStrata("MEDIUM")
frame:EnableMouse(false)

local SA = {}            -- shared with Options.lua
_G.ShieldArcs = SA
local db

---------------------------------------------------------------- settings
SA.GENERAL = { x = 0, y = -60, radius = 150, thick = 13, arc = 42 }
SA.ORDER = { "PWS", "IB", "MS", "HEALTH", "MANA", "COMBO", "ENERGY", "RAGE" }
SA.ELEMENTS = {
  PWS    = { label = "Power Word: Shield", side = "right", shield = true, spell = 17,
             thick = 1, bg = 0.55, numSize = 14, icon = true, num = true, timer = true, ws = true,
             c = { {0.78, 0.61, 0.43}, {0.89, 0.80, 0.71}, {1.00, 1.00, 1.00} } },
  IB     = { label = "Ice Barrier", side = "right", shield = true, spell = 11426,
             thick = 1, bg = 0.55, numSize = 14, icon = true, num = true, timer = true,
             c = { {0.04, 0.18, 0.55}, {0.35, 0.65, 1.00}, {0.80, 0.94, 1.00} } },
  MS     = { label = "Mana Shield", side = "left", shield = true, spell = 1463,
             thick = 1, bg = 0.55, numSize = 14, icon = true, num = true, timer = true,
             c = { {0.10, 0.62, 0.55}, {0.50, 1.00, 0.83}, {1.00, 1.00, 1.00} } },
  HEALTH = { label = "Health", side = "right", tex = "Interface\\Icons\\INV_Potion_51",
             thick = 1, bg = 0.35, numSize = 16, icon = false, num = true, ndx = -20,
             c = { {0.55, 0.02, 0.02}, {0.78, 0.16, 0.16}, {1.00, 0.30, 0.30} } },
  MANA   = { label = "Mana", side = "right", tex = "Interface\\Icons\\INV_Potion_76",
             thick = 1, bg = 0.35, numSize = 16, icon = false, num = true,
             c = { {0.00, 0.25, 0.75}, {0.18, 0.45, 0.88}, {0.35, 0.65, 1.00} } },
  COMBO  = { label = "Combo Points", side = "left", tex = "Interface\\Icons\\Ability_Rogue_Eviscerate",
             thick = 1.5, bg = 0.10, numSize = 34, icon = false, num = true, dx = -20,
             c = { {1.00, 0.95, 0.30}, {1.00, 0.60, 0.10}, {0.95, 0.12, 0.08} } },
  ENERGY = { label = "Energy", side = "left", tex = "Interface\\Icons\\Ability_Rogue_Sprint",
             thick = 1, bg = 0.10, numSize = 20, icon = false, num = true, dx = -20,
             c = { {0.85, 0.62, 0.10}, {0.93, 0.79, 0.26}, {1.00, 0.96, 0.41} } },
  RAGE   = { label = "Rage", side = "left", tex = "Interface\\Icons\\Ability_Racial_BloodRage",
             thick = 1, bg = 0.10, numSize = 20, icon = false, num = true,
             c = { {0.50, 0.02, 0.02}, {0.75, 0.11, 0.06}, {1.00, 0.20, 0.10} } },
}
local SAVED_FIELDS = { "mode", "show", "thick", "bg", "numSize", "icon", "num", "timer", "ws", "dx", "dy", "dr", "ndx", "ndy", "arc", "iconSize", "c" }

local function CopyColors(c) return { { c[1][1], c[1][2], c[1][3] }, { c[2][1], c[2][2], c[2][3] }, { c[3][1], c[3][2], c[3][3] } } end

function SA.DefaultElement(key)
  local d = SA.ELEMENTS[key]
  return { mode = "auto", show = true, thick = d.thick, bg = d.bg, numSize = d.numSize, icon = d.icon, num = d.num,
           timer = d.timer, ws = d.ws, dx = d.dx or 0, dy = 0, dr = 0, ndx = d.ndx or 0, ndy = 0,
           arc = nil, iconSize = nil, c = CopyColors(d.c) }
end

local function InitDB()
  ShieldArcsDB = ShieldArcsDB or {}
  db = ShieldArcsDB
  SA.db = db
  for k, v in pairs(SA.GENERAL) do if db[k] == nil then db[k] = v end end
  db.learn = db.learn or {}
  db.minimap = db.minimap or { hide = false }
  db.el = db.el or {}
  for _, key in ipairs(SA.ORDER) do
    local cur, def = db.el[key], SA.DefaultElement(key)
    if type(cur) ~= "table" then
      db.el[key] = def
    else
      if cur.mode == nil and cur.show == false then cur.mode = "off" end   -- older "show" checkbox
      for _, f in ipairs(SAVED_FIELDS) do if cur[f] == nil then cur[f] = def[f] end end
    end
  end
end

---------------------------------------------------------------- helpers
local function SpellName(id)
  return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and GetSpellInfo(id))
end
local function SpellTex(id)
  return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or (GetSpellTexture and GetSpellTexture(id))
end
local function Grad(c, t)                 -- 3 stops: bottom, middle, top
  local s = 2 * t
  local i = min(floor(s) + 1, 2)
  local f = s - (i - 1)
  local a, b = c[i], c[i + 1]
  return a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f
end
local function Angle(side, t, arcDeg)     -- t = 0 bottom end, 1 top end
  local arc = rad(arcDeg)
  if side == "right" then return -arc + t * 2 * arc end
  return math.pi + arc - t * 2 * arc
end

---------------------------------------------------------------- arc objects
local N = 60
local MAXP, PER, GAP = 5, 10, 2           -- combo: 5 pips of 10 squares, 2-square gaps
local A = {}                              -- runtime pieces per element

local function NewPiece(key)
  local p = { bg = {}, fg = {}, slots = {}, pip = {} }
  if key == "COMBO" then
    local total = MAXP * PER + (MAXP - 1) * GAP
    local idx = 0
    for pip = 1, MAXP do
      for _ = 1, PER do
        idx = idx + 1
        p.slots[#p.slots + 1] = (idx - 0.5) / total
        p.pip[#p.slots] = pip
      end
      idx = idx + (pip < MAXP and GAP or 0)
    end
  else
    for i = 1, N do p.slots[i] = (i - 0.5) / N end
  end
  for i = 1, #p.slots do
    p.bg[i] = frame:CreateTexture(nil, "BACKGROUND")
    p.fg[i] = frame:CreateTexture(nil, "ARTWORK")
  end
  p.icon = frame:CreateTexture(nil, "OVERLAY")
  p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  p.text = frame:CreateFontString(nil, "OVERLAY")
  local d = SA.ELEMENTS[key]
  if d.shield then
    p.ttext = frame:CreateFontString(nil, "OVERLAY")     -- seconds left
    p.ttext:SetTextColor(0.92, 0.92, 0.92)
    p.wtext = frame:CreateFontString(nil, "OVERLAY")     -- Weakened Soul (PW:S)
    p.wtext:SetTextColor(0.85, 0.55, 0.55)
  end
  p.shown = true
  return p
end

local function HidePiece(p)
  if not p.shown then return end
  for i = 1, #p.bg do p.bg[i]:Hide(); p.fg[i]:Hide() end
  p.icon:Hide(); p.text:Hide()
  if p.ttext then p.ttext:Hide() end
  if p.wtext and not p.keepWS then p.wtext:Hide() end
  p.shown = false
end

-- Lay out one element. r = radius of the arc's center line, th = thickness, (cx, cy) = center offset
local function LayoutPiece(key, r, th, extra)
  local p, e, d = A[key], db.el[key], SA.ELEMENTS[key]
  local arcDeg = e.arc or db.arc
  local cx, cy = e.dx, e.dy
  p.r, p.th, p.cx, p.cy = r, th, cx, cy
  for i, t in ipairs(p.slots) do
    local a = Angle(d.side, t, arcDeg)
    local x, y = cx + r * cos(a), cy + r * sin(a)
    for _, tx in ipairs({ p.bg[i], p.fg[i] }) do
      tx:ClearAllPoints()
      tx:SetPoint("CENTER", frame, "CENTER", x, y)
      if tx.SetRotation then tx:SetRotation(a) end
    end
    p.bg[i]:SetColorTexture(0, 0, 0, e.bg)
    p.bg[i]:SetSize(th + 2, th + 2)
    p.fg[i]:SetSize(th, th)
    if key == "COMBO" then
      p.fg[i]:SetColorTexture(Grad(e.c, (p.pip[i] - 1) / (MAXP - 1)))
    else
      p.fg[i]:SetColorTexture(Grad(e.c, t))
    end
  end
  -- icon just past the top end of the arc
  local isz = e.iconSize or max(14, th + 6)
  local ia = Angle(d.side, 1, arcDeg) + ((d.side == "right") and 1 or -1) * ((isz / 2 + 4) / max(r, 1))
  p.icon:SetTexture((d.spell and SpellTex(d.spell)) or d.tex or 134400)
  p.icon:SetSize(isz, isz)
  p.icon:ClearAllPoints()
  p.icon:SetPoint("CENTER", frame, "CENTER", cx + r * cos(ia), cy + r * sin(ia))
  -- numbers
  local fs = e.numSize
  local tr, tg, tb = Grad(e.c, 1)
  p.text:SetFont(STANDARD_TEXT_FONT, fs, (key == "COMBO" or not d.shield) and "THICKOUTLINE" or "OUTLINE")
  p.text:SetTextColor(tr, tg, tb)
  p.text:ClearAllPoints()
  local a0 = Angle(d.side, 0, arcDeg)
  if d.shield then
    local a = Angle(d.side, -0.07, arcDeg)
    p.text:SetPoint("CENTER", frame, "CENTER", cx + r * cos(a) + e.ndx, cy + r * sin(a) - 4 + e.ndy)
    local ma = Angle(d.side, 0.5, arcDeg)
    local ir = r - th / 2 - fs * 1.4
    p.ttext:SetFont(STANDARD_TEXT_FONT, fs + 4, "THICKOUTLINE")
    p.ttext:ClearAllPoints()
    p.ttext:SetPoint("CENTER", frame, "CENTER", cx + ir * cos(ma), cy + ir * sin(ma))
    p.wtext:SetFont(STANDARD_TEXT_FONT, fs, "OUTLINE")
    p.wtext:ClearAllPoints()
    p.wtext:SetPoint("TOP", p.ttext, "BOTTOM", 0, -2)
  elseif key == "HEALTH" then
    p.text:SetPoint("TOPLEFT", frame, "CENTER", cx + r * cos(a0) - th / 2 + e.ndx, cy + r * sin(a0) - th / 2 - 3 + e.ndy)
  elseif key == "MANA" then
    local hy = extra and extra.healthTextY or (cy + r * sin(a0) - th / 2 - 3)
    p.text:SetPoint("TOPLEFT", frame, "CENTER", cx + r * cos(a0) - th / 2 + e.ndx, hy - (db.el.HEALTH.numSize + 1) + e.ndy)
  elseif key == "COMBO" then
    p.text:SetPoint("CENTER", frame, "CENTER", cx - (r - th - fs * 0.6) + e.ndx, cy + e.ndy)
  else -- ENERGY, RAGE: number outside the arc
    p.text:SetPoint("CENTER", frame, "CENTER", cx - (r + th / 2 + fs * 1.1) + e.ndx, cy + e.ndy)
  end
end

---------------------------------------------------------------- shields (absorb tracking)
local SH = {
  PWS = { nameId = 17, kind = "heal",
          ranks = { [17]=48, [592]=94, [600]=166, [3747]=244, [6065]=313, [6066]=394,
                    [10898]=499, [10899]=622, [10900]=783, [10901]=964 } },
  IB  = { nameId = 11426, kind = "frost", ranks = { [11426]=438, [13031]=549, [13032]=678, [13033]=818 } },
  MS  = { nameId = 1463, kind = "none", ranks = { [1463]=120, [8494]=210, [8495]=300, [10191]=390, [10192]=480, [10193]=570 } },
}
local SHIELD_KEYS = { "PWS", "IB", "MS" }
local pguid
local testMode, selectedKey, optionsOpen = false, nil, false
local layoutDirty, lastRing = true, nil

local function NewShield(sh, a)
  sh.iid, sh.sid, sh.used = a.auraInstanceID, a.spellId, 0
  local bonus = 0
  if sh.kind == "heal" then bonus = (GetSpellBonusHealing and GetSpellBonusHealing() or 0) * 0.1
  elseif sh.kind == "frost" then bonus = (GetSpellBonusDamage and GetSpellBonusDamage(5) or 0) * 0.1 end
  sh.est = (sh.ranks[a.spellId] or 0) + bonus
  sh.max = sh.est * (db.learn["r" .. tostring(a.spellId)] or 1)
end

local function EndShield(sh)
  if sh.lastAbs and GetTime() - sh.lastAbs < 0.5 and sh.est and sh.est > 0 and sh.used >= 0.85 * (sh.max or 0) then
    local r = sh.used / sh.est
    if r > 0.8 and r < 1.8 then db.learn["r" .. tostring(sh.sid)] = r end
  end
  sh.iid, sh.sid, sh.exp, sh.active = nil, nil, nil, false
end

local function ScanAuras()
  for _, key in ipairs(SHIELD_KEYS) do
    local sh = SH[key]
    sh.name = sh.name or SpellName(sh.nameId)
    local a = sh.name and C_UnitAuras.GetAuraDataBySpellName("player", sh.name, "HELPFUL")
    if a then
      local exp = a.expirationTime or 0
      if a.auraInstanceID ~= sh.iid or (exp > 0 and sh.exp and exp > sh.exp + 0.5) then NewShield(sh, a) end
      sh.exp, sh.dur, sh.active = exp, a.duration, true
    elseif sh.iid then
      EndShield(sh)
    else
      sh.active = false
    end
  end
end

local function OnAbsorb()
  local t = { CombatLogGetCurrentEventInfo() }
  if t[2] ~= "SPELL_ABSORBED" or t[8] ~= pguid then return end
  local amt = t[#t]
  if type(amt) ~= "number" then amt = t[#t - 1] end
  if type(amt) ~= "number" then return end
  for _, key in ipairs(SHIELD_KEYS) do
    local sh = SH[key]
    if sh.active and sh.name then
      for i = 12, #t do
        if t[i] == sh.name then sh.used = sh.used + amt; sh.lastAbs = GetTime(); return end
      end
    end
  end
end

local wsName
local function WeakenedSoulLeft()
  if testMode or (optionsOpen and selectedKey == "PWS") then return 9 end
  wsName = wsName or SpellName(6788)
  local d = wsName and C_UnitAuras.GetAuraDataBySpellName("player", wsName, "HARMFUL")
  if d and d.expirationTime and d.expirationTime > 0 then
    local left = d.expirationTime - GetTime()
    if left > 0 then return left end
  end
end

---------------------------------------------------------------- which arcs apply to this character
local function PowerType() return UnitPowerType("player") end
local function Relevant(key)
  if key == "PWS" or key == "HEALTH" then return true end
  if key == "IB" or key == "MS" then return CLASS == "MAGE" end
  if key == "MANA" then return (UnitPowerMax("player", 0) or 0) > 0 end
  if key == "COMBO" or key == "ENERGY" then return CLASS == "ROGUE" or CLASS == "DRUID" end
  if key == "RAGE" then return CLASS == "WARRIOR" or CLASS == "DRUID" end
end
local function Preview(key)
  if optionsOpen and selectedKey == key then return true end
  return testMode and Relevant(key)
end
-- Visibility mode per arc: "auto" (combat / when not full / shield up), "always", "off"
local function Mode(key) return db.el[key].mode or "auto" end
local function Always(key) return Mode(key) == "always" and Relevant(key) end
local function Off(key) return Mode(key) == "off" end

---------------------------------------------------------------- layout
local function Layout()
  layoutDirty = false
  local R, th = db.radius, db.thick
  local el = db.el
  local function T(k) return th * el[k].thick end
  local ibUp = SH.IB.active or Preview("IB")
  lastRing = ibUp
  -- right side, inside -> out
  LayoutPiece("IB", R + el.IB.dr, T("IB"))
  local pwsR = R + (ibUp and (T("IB") / 2 + 6 + T("PWS") / 2) or 0)
  LayoutPiece("PWS", pwsR + el.PWS.dr, T("PWS"))
  local outer = ibUp and (pwsR + T("PWS") / 2) or (R + th / 2)
  local hBase = outer + 4 + T("HEALTH") / 2
  LayoutPiece("HEALTH", hBase + el.HEALTH.dr, T("HEALTH"))
  local hp = A.HEALTH
  local a0 = Angle("right", 0, el.HEALTH.arc or db.arc)
  local healthTextY = hp.cy + hp.r * sin(a0) - hp.th / 2 - 3 + el.HEALTH.ndy
  LayoutPiece("MANA", hBase + T("HEALTH") / 2 + 4 + T("MANA") / 2 + el.MANA.dr, T("MANA"), { healthTextY = healthTextY })
  -- left side
  LayoutPiece("MS", R + el.MS.dr, T("MS"))
  LayoutPiece("COMBO", R + el.COMBO.dr, T("COMBO"))
  LayoutPiece("ENERGY", R + T("COMBO") / 2 + 4 + T("ENERGY") / 2 + el.ENERGY.dr, T("ENERGY"))
  LayoutPiece("RAGE", R + th * 1.5 / 2 + 4 + T("RAGE") / 2 + el.RAGE.dr, T("RAGE"))
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
  for _, p in pairs(A) do p.shown = true end   -- force a fresh show/hide pass
end

---------------------------------------------------------------- drawing
local function Fill(p, frac)
  local n = #p.slots
  local filled = floor(frac * n + 0.5)
  for i = 1, n do
    p.bg[i]:Show()
    if i <= filled then p.fg[i]:Show() else p.fg[i]:Hide() end
  end
  p.shown = true
end

local function ShowExtras(key, value)
  local p, e = A[key], db.el[key]
  if e.icon then p.icon:Show() else p.icon:Hide() end
  if e.num and value then p.text:SetText(value); p.text:Show() else p.text:Hide() end
end

local function DrawShield(key)
  local p, e, sh = A[key], db.el[key], SH[key]
  local frac, value, left
  if Preview(key) then
    frac, value, left = 0.65, 325, 18
  elseif sh.active and sh.max and sh.max > 0 then
    if sh.used > sh.max then sh.max = sh.used end
    local rem = sh.max - sh.used
    frac, value = rem / sh.max, floor(rem + 0.5)
    if sh.exp and sh.exp > 0 then left = max(0, sh.exp - GetTime()) end
  end
  if not frac and Always(key) then frac = 0 end           -- always on: empty arc when no shield
  if Off(key) then frac = nil end
  local ws = (key == "PWS") and not Off(key) and e.ws and WeakenedSoulLeft()
  if not frac then
    p.keepWS = ws and true or false
    HidePiece(p)
    if p.ttext then p.ttext:Hide() end
    if ws then p.wtext:SetText(("(%d)"):format(math.ceil(ws))); p.wtext:Show() else p.wtext:Hide() end
    return false
  end
  Fill(p, frac)
  ShowExtras(key, value)
  if e.timer and left then
    p.ttext:SetText(left >= 10 and tostring(floor(left + 0.5)) or ("%.1f"):format(left)); p.ttext:Show()
  else
    p.ttext:Hide()
  end
  if ws then p.wtext:SetText(("(%d)"):format(math.ceil(ws))); p.wtext:Show() else p.wtext:Hide() end
  return true
end

local function DrawBar(key, show, cur, mx)
  local p, e = A[key], db.el[key]
  if Off(key) then show = false elseif Always(key) then show = true end
  if not show then HidePiece(p); return false end
  Fill(p, mx > 0 and min(1, cur / mx) or 0)
  ShowExtras(key, cur)
  return true
end

local function ComboPoints()
  local p = 0
  if GetComboPoints then p = GetComboPoints("player", "target") or 0 end
  if p == 0 and Enum and Enum.PowerType and Enum.PowerType.ComboPoints then p = UnitPower("player", Enum.PowerType.ComboPoints) or 0 end
  return p
end

local function Tick()
  if not db then return end
  local ring = SH.IB.active or Preview("IB")
  if layoutDirty or ring ~= lastRing then Layout() end
  local combat = InCombatLockdown()
  local anyShield = false
  for _, key in ipairs(SHIELD_KEYS) do
    DrawShield(key)
    if SH[key].active then anyShield = true end
  end
  -- mana
  local cur, mx = UnitPower("player", 0) or 0, UnitPowerMax("player", 0) or 0
  local isMana = PowerType() == 0
  local showMana = Preview("MANA") or (isMana and mx > 0 and (combat or cur < mx or anyShield))
  if Preview("MANA") and mx <= 0 then cur, mx = 700, 1000 end
  DrawBar("MANA", showMana, cur, mx)
  -- health
  local h, hm = UnitHealth("player") or 0, UnitHealthMax("player") or 0
  local showHp = Preview("HEALTH") or (hm > 0 and (combat or h < hm or anyShield or showMana))
  DrawBar("HEALTH", showHp, h, hm > 0 and hm or 1)
  -- combo + energy (rogues, cat form)
  local ptype = PowerType()
  local energyUser = CLASS == "ROGUE" or (CLASS == "DRUID" and ptype == 3)
  local pts = ComboPoints()
  local target = UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")
  local comboOn = energyUser and (pts > 0 or target)
  local ce = db.el.COMBO
  if Always("COMBO") then comboOn = true end
  if Preview("COMBO") then pts, comboOn = 3, true end
  if Off("COMBO") then comboOn = false end
  if comboOn then
    local p = A.COMBO
    for i = 1, #p.slots do
      p.bg[i]:Show()
      if p.pip[i] <= pts then p.fg[i]:Show() else p.fg[i]:Hide() end
    end
    p.shown = true
    ShowExtras("COMBO", pts > 0 and pts or "")
    local r, g, b = Grad(ce.c, (max(pts, 1) - 1) / (MAXP - 1))
    p.text:SetTextColor(r, g, b)
  else
    HidePiece(A.COMBO)
  end
  local en, enMax = UnitPower("player", 3) or 0, UnitPowerMax("player", 3) or 100
  if Preview("ENERGY") then en, enMax = 60, 100 end
  local energyAuto = energyUser and (pts > 0 or target)
  DrawBar("ENERGY", energyAuto or Preview("ENERGY"), en, enMax > 0 and enMax or 100)
  -- rage (warriors, bear form)
  local rg, rgMax = UnitPower("player", 1) or 0, UnitPowerMax("player", 1) or 100
  local rageOn = ptype == 1 and (combat or rg > 0)
  if Preview("RAGE") then rg, rgMax, rageOn = 45, 100, true end
  DrawBar("RAGE", rageOn, rg, rgMax > 0 and rgMax or 100)
end

---------------------------------------------------------------- API for the options window
function SA.Changed() layoutDirty = true; Tick() end
function SA.SetTest(v) testMode = v and true or false; layoutDirty = true; Tick() end
function SA.IsTest() return testMode end
function SA.SetSelected(key) selectedKey = key; layoutDirty = true; Tick() end
function SA.SetOptionsOpen(v) optionsOpen = v and true or false; layoutDirty = true; Tick() end
function SA.Relevant(key) return Relevant(key) end
function SA.ResetElement(key) db.el[key] = SA.DefaultElement(key); SA.Changed() end
function SA.ResetAll()
  for k, v in pairs(SA.GENERAL) do db[k] = v end
  for _, key in ipairs(SA.ORDER) do db.el[key] = SA.DefaultElement(key) end
  SA.Changed()
end

---------------------------------------------------------------- events
local tick = 0
frame:SetScript("OnUpdate", function(_, dt)
  tick = tick + dt
  if tick < 0.1 then return end
  tick = 0
  Tick()
end)

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    InitDB()
    for _, key in ipairs(SA.ORDER) do A[key] = NewPiece(key) end
    layoutDirty = true
    self:UnregisterEvent("ADDON_LOADED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterUnitEvent("UNIT_AURA", "player")
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  elseif event == "PLAYER_ENTERING_WORLD" then
    pguid = UnitGUID("player")
    ScanAuras(); layoutDirty = true; Tick()
  elseif event == "UNIT_AURA" then
    ScanAuras(); Tick()
  elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
    OnAbsorb()
  end
end)

SLASH_SHIELDARCS1 = "/sarc"
SLASH_SHIELDARCS2 = "/shieldarcs"
SLASH_SHIELDARCS3 = "/carc"
SlashCmdList.SHIELDARCS = function(msg)
  msg = (msg or ""):lower():match("^%s*(%S*)")
  if msg == "test" then
    SA.SetTest(not testMode)
    print("|cff66ccffPints Shield Arcs|r test mode " .. (testMode and "ON" or "OFF"))
  elseif msg == "reset" then
    SA.ResetAll()
    print("|cff66ccffPints Shield Arcs|r all settings reset.")
  elseif SA.OpenOptions then
    SA.OpenOptions()
  end
end
