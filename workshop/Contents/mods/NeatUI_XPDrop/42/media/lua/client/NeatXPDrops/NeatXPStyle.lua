--[[ ============================================================================
    NeatXPStyle - NeatUI-flavoured drawing helpers for Neat XP Drops.
============================================================================ ]]--

NeatXPStyle = NeatXPStyle or {}

-- ---- Palette ----------------------------------------------------------------
NeatXPStyle.accent      = { r = 0.95, g = 0.50, b = 0.10 }   -- NR_Config accent
NeatXPStyle.grey        = { r = 0.45, g = 0.45, b = 0.45 }
NeatXPStyle.panelTint   = 0.15   -- NR_Config.panelBg
NeatXPStyle.panelAlpha  = 0.70
NeatXPStyle.textDim     = 0.72

-- ---- Textures ---------------------------------------------------------------
NeatXPStyle.TEX = {
    panelRound = "media/ui/NeatUI/DefaultPanel/MainPanelBG_RoundTop.png",
    panelFlat  = "media/ui/NeatUI/DefaultPanel/MainPanelBG_FlatTop.png",
    titleBar   = "media/ui/NeatUI/DefaultPanel/MainTitle_BG.png",
    innerPanel = "media/ui/NeatUI/DefaultPanel/InnerPanel_BG.png",
    btnL       = "media/ui/NeatUI/Button/Button_FULL_L.png",
    btnM       = "media/ui/NeatUI/Button/Button_FULL_M.png",
    btnR       = "media/ui/NeatUI/Button/Button_FULL_R.png",
    barL       = "media/ui/NeatXP/bar_l.png",
    barM       = "media/ui/NeatXP/bar_m.png",
    barR       = "media/ui/NeatXP/bar_r.png",
    switchOn   = "media/ui/NeatXP/switch_on.png",
    switchOff  = "media/ui/NeatXP/switch_off.png",
}

local _tex = {}
local function tex(path)
    if _tex[path] == nil then _tex[path] = getTexture(path) or false end
    if _tex[path] == false then return nil end
    return _tex[path]
end

-- ---- 3-slice helper (crisp caps, stretched middle) --------------------------
local function draw3(el, tl, tm, tr, x, y, w, h, capW, a, r, g, b)
    capW = math.min(capW, math.floor(w / 2))
    if capW < 1 then capW = 1 end
    el:drawTextureScaled(tl, x, y, capW, h, a, r, g, b)
    local midW = w - capW * 2
    if midW > 0 and tm then el:drawTextureScaled(tm, x + capW, y, midW, h, a, r, g, b) end
    el:drawTextureScaled(tr, x + w - capW, y, capW, h, a, r, g, b)
end

-- ---- NinePatch panel (generic) ----------------------------------------------
function NeatXPStyle.drawNP(el, path, x, y, w, h, tint, alpha)
    local np = NinePatchTexture and NinePatchTexture.getSharedTexture and NinePatchTexture.getSharedTexture(path)
    if np then
        np:render(el:getAbsoluteX() + x, el:getAbsoluteY() + y, w, h, tint, tint, tint, alpha or 0.9)
    else
        el:drawRectStatic(x, y, w, h, alpha or 0.9, tint, tint, tint)
        local g = NeatXPStyle.grey
        el:drawRectBorderStatic(x, y, w, h, 0.7, g.r, g.g, g.b)
    end
end

function NeatXPStyle.drawPanel(el, x, y, w, h, rounded, alpha)
    NeatXPStyle.drawNP(el, rounded and NeatXPStyle.TEX.panelRound or NeatXPStyle.TEX.panelFlat,
        x, y, w, h, NeatXPStyle.panelTint, alpha or NeatXPStyle.panelAlpha)
end

-- Rocco window anatomy: MainTitle_BG header (rounded top) + MainPanelBG_FlatTop
-- body drawn BELOW it. Never a full-height panel under a square strip: that is
-- what leaves square corners peeking out behind the rounded ones.
function NeatXPStyle.drawWindow(el, x, y, w, h, headerH, alphaHeader, alphaBody)
    NeatXPStyle.drawNP(el, NeatXPStyle.TEX.titleBar, x, y, w, headerH, 0.08, alphaHeader or 1.0)
    NeatXPStyle.drawNP(el, NeatXPStyle.TEX.panelFlat, x, y + headerH, w, h - headerH,
        NeatXPStyle.panelTint, alphaBody or 1.0)
end

-- ---- Button (official framework 3-slice, rounded, not stretched) ------------
function NeatXPStyle.drawButton(el, x, y, w, h, state)
    local L, M, R = tex(NeatXPStyle.TEX.btnL), tex(NeatXPStyle.TEX.btnM), tex(NeatXPStyle.TEX.btnR)
    local a = NeatXPStyle.accent
    -- Same states as NI_SquareButton (framework): default 0.2, hover 0.3, pressed 0.1, alpha 0.8.
    local r, g, b, al = 0.20, 0.20, 0.20, 0.8
    if state == "pressed" then r, g, b = 0.10, 0.10, 0.10
    elseif state == "hover" then r, g, b = 0.30, 0.30, 0.30
    elseif state == "active" then r, g, b = a.r, a.g, a.b; al = 0.8 end
    if L and R then
        draw3(el, L, M, R, x, y, w, h, h, al, r, g, b)
    else
        el:drawRectStatic(x, y, w, h, al, r, g, b)
        el:drawRectBorderStatic(x, y, w, h, 1, NeatXPStyle.grey.r, NeatXPStyle.grey.g, NeatXPStyle.grey.b)
    end
end

-- ---- Toggle switch (green/red, from Rocco art) ------------------------------
function NeatXPStyle.drawSwitch(el, x, y, w, h, on)
    local t = tex(on and NeatXPStyle.TEX.switchOn or NeatXPStyle.TEX.switchOff)
    if t then
        el:drawTextureScaled(t, x, y, w, h, 1, 1, 1, 1)
    else
        if on then el:drawRectStatic(x, y, w, h, 1, 0.30, 0.70, 0.35)
        else el:drawRectStatic(x, y, w, h, 1, 0.70, 0.30, 0.30) end
    end
end

-- ---- Progress bar -----------------------------------------------------------
function NeatXPStyle.getFillColor(pct)
    local a = NeatXPStyle.accent
    if pct >= 0.85 then return a.r, a.g, a.b
    elseif pct >= 0.70 then
        local t = (pct - 0.70) / 0.15
        return 0.40 + (a.r - 0.40) * t, 0.80 + (a.g - 0.80) * t, 0.40 + (a.b - 0.40) * t
    else return 0.40, 0.80, 0.42 end
end

function NeatXPStyle.drawBar(el, x, y, w, h, pct)
    pct = math.max(0, math.min(pct or 0, 1))
    local L, M, R = tex(NeatXPStyle.TEX.barL), tex(NeatXPStyle.TEX.barM), tex(NeatXPStyle.TEX.barR)
    local cap = math.floor(h * 0.5)
    if not (L and R) then
        el:drawRectStatic(x, y, w, h, 0.55, 0.09, 0.09, 0.10)
        local fw = math.floor(w * pct)
        if fw > 1 then local fr, fg, fb = NeatXPStyle.getFillColor(pct); el:drawRectStatic(x, y, fw, h, 0.95, fr, fg, fb) end
        return
    end
    draw3(el, L, M, R, x, y, w, h, cap, 0.55, 0.09, 0.09, 0.10)
    local fw = math.floor(w * pct)
    if fw > 2 then
        local fr, fg, fb = NeatXPStyle.getFillColor(pct)
        el:setStencilRect(x, y, fw, h)
        draw3(el, L, M, R, x, y, w, h, cap, 0.95, fr, fg, fb)
        el:clearStencilRect()
    end
end

-- ---- Text helpers ------------------------------------------------------------
-- getText returns the raw key when a translation is missing: never show that.
function NeatXPStyle.tr(key, fallback)
    if not getText then return fallback end
    local t = getText(key)
    if not t or t == key then return fallback end
    return t
end

-- Truncate text with ".." so it fits maxW (framework-style truncation).
function NeatXPStyle.fitText(text, maxW, font)
    text = tostring(text or "")
    local tm = getTextManager()
    if tm:MeasureStringX(font, text) <= maxW then return text end
    local out = text
    while #out > 1 and tm:MeasureStringX(font, out .. "..") > maxW do
        out = out:sub(1, #out - 1)
    end
    return out .. ".."
end

-- ---- Skill icon (bundled OSRS set, else drawn badge) ------------------------
local _iconCache = {}
function NeatXPStyle.getSkillIcon(skillType)
    if skillType == nil then return nil end
    local key = tostring(skillType):lower():gsub(" ", "_")
    if _iconCache[key] == nil then
        local t = getTexture("media/ui/NeatXP/icon_" .. key .. ".png")
        if not t then t = getTexture("media/ui/RUNE-EXP_icon_" .. key .. ".png") end
        _iconCache[key] = t or false
    end
    if _iconCache[key] == false then return nil end
    return _iconCache[key]
end

local function initials(name)
    if not name or name == "" then return "?" end
    name = tostring(name)
    local a, b = name:match("^(%a)%a*%s+(%a)")
    if a and b then return (a .. b):upper() end
    return name:sub(1, 2):upper()
end

function NeatXPStyle.drawIcon(el, x, y, size, skillType, skillName, alpha)
    alpha = alpha or 1.0
    local icon = NeatXPStyle.getSkillIcon(skillType)
    if icon then
        el:drawTextureScaled(icon, x, y, size, size, alpha, 1, 1, 1)
        return
    end
    el:drawTextCentre(initials(skillName), x + math.floor(size / 2),
        y + math.floor((size - getTextManager():getFontHeight(UIFont.Small)) / 2),
        NeatXPStyle.accent.r, NeatXPStyle.accent.g, NeatXPStyle.accent.b, alpha, UIFont.Small)
end
