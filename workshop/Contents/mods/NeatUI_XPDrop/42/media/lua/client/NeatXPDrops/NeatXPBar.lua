--[[ ============================================================================
    NeatXPBar - standalone XP-drops bar (NeatUI themed).
============================================================================ ]]--

require "ISUI/ISPanel"

NeatXPBar = ISPanel:derive("NeatXPBar")

local FONT_SMALL  = UIFont.Small
local FONT_MEDIUM = UIFont.Medium
local FONT_LARGE  = UIFont.Large

local DEFAULT_OFF = { Fitness = true, Strength = true, Lightfoot = true, Sneak = true, Maintenance = true }

function NeatXPBar:new(playerIndex, player)
    local fh = getTextManager():getFontHeight(FONT_SMALL)
    local fhMed = getTextManager():getFontHeight(FONT_MEDIUM)
    local fontSize = getCore():getOptionFontSize()

    local pad = 6
    local headerH = math.max(22, fh + 8)
    local iconSize = math.max(16, headerH - 6)
    local barH = math.floor(fh * 0.7) + 5
    local w = 190 + (14 * (fontSize - 1))
    local h = headerH + math.floor(pad * 0.5) + fh + 4 + barH + pad

    local o = ISPanel:new(getCore():getScreenWidth() - 360, 180, w, h)
    setmetatable(o, self)
    self.__index = self

    o.playerIndex = playerIndex
    o.player = player
    o.player_isDead = false

    o.pad = pad
    o.headerH = headerH
    o.iconSize = iconSize
    o.barH = barH
    o.baseWidth = w
    o.baseHeight = h

    o.moveWithMouse = true
    o.background = false
    o:setCapture(false)

    o.tracked = {}
    o.expTables = {}
    o.perkIndices = {}
    o.skillOrder = {}

    o.currentSkill = nil
    o.currentName = ""

    o.drops = {}
    o.tooltipVisible = false
    o.collapsed = false

    o.pillW = fhMed * 2 + 16
    o.pillH = fhMed + 10

    o.dropdown = nil
    o.configPanel = nil

    return o
end

function NeatXPBar:initialise()
    ISPanel.initialise(self)
    self:buildSkillData()
    self:readConfig()
end

function NeatXPBar:buildSkillData()
    for i = 1, Perks.getMaxIndex() do
        local perk = PerkFactory.getPerk(Perks.fromIndex(i - 1))
        if perk and perk:getParent() ~= Perks.None then
            local t = tostring(perk:getType())
            self.perkIndices[t] = i - 1
            self.expTables[t] = {
                tonumber(perk:getXp1()), tonumber(perk:getXp2()), tonumber(perk:getXp3()),
                tonumber(perk:getXp4()), tonumber(perk:getXp5()), tonumber(perk:getXp6()),
                tonumber(perk:getXp7()), tonumber(perk:getXp8()), tonumber(perk:getXp9()),
                tonumber(perk:getXp10()),
            }
            table.insert(self.skillOrder, t)
            if self.tracked[t] == nil then
                self.tracked[t] = not DEFAULT_OFF[t]
            end
        end
    end
    if self.currentSkill == nil and self.skillOrder[1] then
        self:setSkill(self.skillOrder[1])
    end
end

function NeatXPBar:getPerk(skillType)
    local idx = self.perkIndices[skillType]
    if idx == nil then return nil end
    return PerkFactory.getPerk(Perks.fromIndex(idx))
end

function NeatXPBar:isTracked(skillType)
    if self.tracked[skillType] ~= nil then return self.tracked[skillType] end
    return true
end

function NeatXPBar:setTracked(skillType, v) self.tracked[skillType] = v end

function NeatXPBar:cleanExp(expTable, level, exp)
    for i = 1, level do exp = exp - (expTable[i] or 0) end
    return exp
end

function NeatXPBar:getExpMax(skillType, level)
    local t = self.expTables[skillType]
    if not t then return 1 end
    level = math.max(0, math.min(level + 1, 10))
    return t[level] or 1
end

function NeatXPBar:getExpCurrent(skillType, level, exp)
    local t = self.expTables[skillType]
    if not t then return 0 end
    level = math.max(0, math.min(level, 10))
    return self:cleanExp(t, level, exp)
end

function NeatXPBar:setSkill(skillType)
    local perk = self:getPerk(skillType)
    if perk then
        self.currentSkill = skillType
        self.currentName = perk:getName()
    end
end

function NeatXPBar:onAddXP(perk, amount)
    if perk == nil or amount == nil or amount == 0 then return end
    local skillType = tostring(perk:getType())
    if not self:isTracked(skillType) then return end

    self:setSkill(skillType)
    if self.collapsed then return end

    local last = self.drops[#self.drops]
    if last and last.skill == skillType and last.age < 0.15 then
        last.amount = last.amount + amount
    else
        table.insert(self.drops, { skill = skillType, name = perk:getName(), amount = amount, age = 0 })
    end
end

local DROP_LIFETIME = 1.0   -- seconds a drop stays on screen (frame-rate independent)

function NeatXPBar:update()
    ISPanel.update(self)
    local now = getTimestampMs()
    local dt = 0
    if self._lastMs then dt = (now - self._lastMs) / 1000 end
    self._lastMs = now
    if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end
    local step = dt / DROP_LIFETIME
    local i = 1
    while i <= #self.drops do
        local d = self.drops[i]
        d.age = d.age + step
        if d.age >= 1 then
            table.remove(self.drops, i)
        else
            i = i + 1
        end
    end
end

function NeatXPBar:prerender()
    if self.collapsed then
        self:renderCollapsed()
        return
    end

    local pad, iconSize, barH, hh = self.pad, self.iconSize, self.barH, self.headerH
    local w, h = self.width, self.height

    local skillType = self.currentSkill
    local perk = skillType and self:getPerk(skillType)
    local level, cur, max, pct = 0, 0, 1, 0
    if perk then
        level = self.player:getPerkLevel(perk)
        local total = self.player:getXp():getXP(perk)
        max = math.max(1, self:getExpMax(skillType, level))
        cur = self:getExpCurrent(skillType, level, total)
        pct = (level >= 10) and 1 or math.max(0, math.min(cur / max, 1))
    end
    self._pct = pct

    self:renderDrops()

    -- Neat window anatomy: rounded MainTitle_BG header + FlatTop body below it.
    NeatXPStyle.drawWindow(self, 0, 0, w, h, hh, 0.95, NeatXPStyle.panelAlpha)

    -- header: [icon] [skill name] ... [level]
    local fhS = getTextManager():getFontHeight(FONT_SMALL)
    local iy = math.floor((hh - iconSize) / 2)
    NeatXPStyle.drawIcon(self, pad, iy, iconSize, skillType, self.currentName, 1.0)
    local lvlStr = NeatXPStyle.tr("IGUI_NeatXP_Level", "Lv") .. " " .. tostring(level)
    local lvlW = getTextManager():MeasureStringX(FONT_SMALL, lvlStr)
    local nameX = pad + iconSize + 5
    local textY = math.floor((hh - fhS) / 2)
    local name = NeatXPStyle.fitText(self.currentName, w - nameX - lvlW - pad * 2, FONT_SMALL)
    self:drawText(name, nameX, textY, 1, 1, 1, 1, FONT_SMALL)
    self:drawTextRight(lvlStr, w - pad, textY, 1, 1, 1, NeatXPStyle.textDim, FONT_SMALL)

    -- body: readout + progress bar
    local yRead = hh + math.floor(pad * 0.5)
    if level >= 10 then
        self:drawTextRight(NeatXPStyle.tr("IGUI_NeatXP_Max", "MAX"), w - pad, yRead, 1, 1, 1, NeatXPStyle.textDim, FONT_SMALL)
    else
        local readout = string.format("%.1f", cur) .. " / " .. string.format("%.0f", max)
        self:drawTextRight(readout, w - pad, yRead, 1, 1, 1, 0.85, FONT_SMALL)
    end

    NeatXPStyle.drawBar(self, pad, h - pad - barH, w - pad * 2, barH, pct)

    if self.tooltipVisible then
        self:renderTooltip(level, cur, max, pct)
    end
end

function NeatXPBar:renderCollapsed()
    local state = self:isMouseOver() and "hover" or nil
    NeatXPStyle.drawButton(self, 0, 0, self.pillW, self.pillH, state)
    self:drawTextCentre("XP", math.floor(self.pillW / 2),
        math.floor((self.pillH - getTextManager():getFontHeight(FONT_MEDIUM)) / 2),
        1, 1, 1, 1, FONT_MEDIUM)
end

function NeatXPBar:renderDrops()
    local w = self.width
    local size = math.floor(self.iconSize * 0.58)
    local fr, fg, fb = NeatXPStyle.getFillColor(self._pct or 0)
    for _, d in ipairs(self.drops) do
        local a = math.min(1, (1 - d.age) * 1.8)
        local rise = 30 * d.age
        local dy = -18 - rise

        local amount = "+" .. string.format("%.1f", d.amount)
        local tw = getTextManager():MeasureStringX(FONT_LARGE, amount)
        self:drawTextRight(amount, w - 6 + 1, dy + 1, 0, 0, 0, a * 0.7, FONT_LARGE)
        self:drawTextRight(amount, w - 6, dy, fr, fg, fb, a, FONT_LARGE)

        local ih = getTextManager():getFontHeight(FONT_LARGE)
        local ix = w - 6 - tw - size - 2
        NeatXPStyle.drawIcon(self, ix, dy + math.floor((ih - size) / 2), size, d.skill, d.name, a)
    end
end

function NeatXPBar:renderTooltip(level, cur, max, pct)
    local w = self.width
    local fh = getTextManager():getFontHeight(FONT_SMALL)
    self._ttHeaderH = fh + 8
    local tw = math.max(w + 40, 190)
    local th = self._ttHeaderH + 6 + 4 * (fh + 2) + 8
    local ty = self.height + 6
    if self:getY() + ty + th > getCore():getScreenHeight() then
        ty = -6 - th   -- not enough room below: show above the bar
    end
    local tx = math.floor((w - tw) / 2)

    local minX = -self:getX()
    local maxX = getCore():getScreenWidth() - self:getX()
    if tx < minX then tx = minX end
    if tx + tw > maxX then tx = maxX - tw end

    -- Rocco anatomy: rounded MainTitle_BG header + FlatTop body below it
    -- (drawing a square strip over a full-height panel leaves stray corners).
    NeatXPStyle.drawWindow(self, tx, ty, tw, th, self._ttHeaderH, 1.0, 1.0)
    local acc = NeatXPStyle.accent
    local hy = ty + math.floor((self._ttHeaderH - fh) / 2)
    self:drawText(self.currentName, tx + 8, hy, acc.r, acc.g, acc.b, 1, FONT_SMALL)
    self:drawTextRight(NeatXPStyle.tr("IGUI_NeatXP_Level", "Lv") .. " " .. tostring(level), tx + tw - 8, hy, 1, 1, 1, 1, FONT_SMALL)

    local remaining = math.max(0, max - cur)
    local rows = {
        { NeatXPStyle.tr("IGUI_NeatXP_Current", "Current:"),   string.format("%.1f", cur) },
        { NeatXPStyle.tr("IGUI_NeatXP_NextLevel", "Next level:"), string.format("%.0f", max) },
        { NeatXPStyle.tr("IGUI_NeatXP_Remaining", "Remaining:"), string.format("%.1f", remaining) },
        { NeatXPStyle.tr("IGUI_NeatXP_Progress", "Progress:"),  tostring(math.floor(pct * 100)) .. "%" },
    }
    local py = ty + self._ttHeaderH + 5
    for i, row in ipairs(rows) do
        local ry = py + (i - 1) * (fh + 2)
        self:drawText(row[1], tx + 8, ry, 1, 1, 1, NeatXPStyle.textDim, FONT_SMALL)
        self:drawTextRight(row[2], tx + tw - 8, ry, 1, 1, 1, 1, FONT_SMALL)
    end
end

function NeatXPBar:onMouseMove(dx, dy)
    self.tooltipVisible = not self.collapsed
    ISPanel.onMouseMove(self, dx, dy)
end

function NeatXPBar:onMouseMoveOutside(dx, dy)
    self.tooltipVisible = false
    ISPanel.onMouseMoveOutside(self, dx, dy)
end

function NeatXPBar:onMouseDown(x, y)
    -- remember where we started so onMouseUp can tell a click from a drag
    self._pressX, self._pressY = self:getX(), self:getY()
    ISPanel.onMouseDown(self, x, y)
end

function NeatXPBar:onMouseUp(x, y)
    ISPanel.onMouseUp(self, x, y)
    local moved = math.abs(self:getX() - (self._pressX or self:getX()))
                + math.abs(self:getY() - (self._pressY or self:getY()))
    -- a click (barely moved) on the collapsed pill re-opens the panel in place
    if self.collapsed and moved < 4 then
        self:setCollapsed(false)
    end
    self:writeConfig()   -- persist position / state after any drag or toggle
end

function NeatXPBar:onMouseUpOutside(x, y)
    ISPanel.onMouseUpOutside(self, x, y)
    self:writeConfig()
end

function NeatXPBar:onRightMouseDown(x, y)
    if self.collapsed then return end
    if NeatXPMenu then
        NeatXPMenu.openFor(self, self:getX() + x, self:getY() + y)
    end
end

function NeatXPBar:setCollapsed(v)
    if self.collapsed == v then return end
    self.collapsed = v
    self.tooltipVisible = false
    if v then
        self:setWidth(self.pillW)
        self:setHeight(self.pillH)
        self.drops = {}
    else
        self:setWidth(self.baseWidth)
        self:setHeight(self.baseHeight)
    end
end

function NeatXPBar:openConfig()
    if self.configPanel == nil and NeatXPConfig then
        self.configPanel = NeatXPConfig:new(self)
        self.configPanel:initialise()
        self.configPanel:addToUIManager()
    elseif self.configPanel then
        self.configPanel:setVisible(true)
        self.configPanel:addToUIManager()
        self.configPanel:bringToTop()
    end
end

function NeatXPBar:getPlayer() return self.player end
function NeatXPBar:setPlayer(idx, player)
    self.playerIndex = idx
    self.player = player
    self.player_isDead = false
end
function NeatXPBar:getPlayerIsDead() return self.player_isDead end
function NeatXPBar:setPlayerIsDead(v) self.player_isDead = v end

function NeatXPBar:writeConfig()
    local f = getFileWriter("NeatXPDrops.ini", true, false)
    if f == nil then return end
    f:write("pos_x=" .. tostring(self:getX()) .. "\n")
    f:write("pos_y=" .. tostring(self:getY()) .. "\n")
    f:write("collapsed=" .. tostring(self.collapsed) .. "\n")
    f:write("lastSkill=" .. tostring(self.currentSkill) .. "\n")
    for skillType, v in pairs(self.tracked) do
        f:write("track_" .. skillType .. "=" .. tostring(v) .. "\n")
    end
    f:close()
end

function NeatXPBar:readConfig()
    local f = getFileReader("NeatXPDrops.ini", false)
    if f == nil then return end
    local line = f:readLine()
    while line ~= nil do
        local kv = string.split(line, "=")
        if kv and #kv == 2 then
            local k = kv[1]
            local v = kv[2]
            if k == "pos_x" then
                self:setX(tonumber(v) or self:getX())
            elseif k == "pos_y" then
                self:setY(tonumber(v) or self:getY())
            elseif k == "collapsed" then
                self:setCollapsed(v == "true")
            elseif k == "lastSkill" then
                if self.perkIndices[v] then self:setSkill(v) end
            elseif string.sub(k, 1, 6) == "track_" then
                local s = string.sub(k, 7)
                if self.perkIndices[s] then self.tracked[s] = (v == "true") end
            end
        end
        line = f:readLine()
    end
    f:close()
end
