--[[ ============================================================================
    NeatXPMenu   - right-click menu on the bar (Configure / Hide)
    NeatXPConfig - config window: grid of skill icon + on/off switch (NeatUI)
============================================================================ ]]--

require "ISUI/ISPanel"

local FONT_SMALL  = UIFont.Small
local FONT_MEDIUM = UIFont.Medium

-- =============================================================================
-- NeatXPMenu
-- =============================================================================
NeatXPMenu = ISPanel:derive("NeatXPMenu")

function NeatXPMenu.openFor(bar, x, y)
    local m = bar._menu
    if not m then
        m = NeatXPMenu:new(bar)
        m:initialise()
        bar._menu = m
    end
    m:rebuild()
    m:setX(x)
    m:setY(y)
    m:setVisible(true)
    m:addToUIManager()
    m:bringToTop()
end

function NeatXPMenu:new(bar)
    local itemH = getTextManager():getFontHeight(FONT_MEDIUM) + 10
    local o = ISPanel:new(0, 0, 150, itemH * 2)
    setmetatable(o, self)
    self.__index = self
    o.bar = bar
    o.itemH = itemH
    o.background = false
    o.items = {}
    return o
end

function NeatXPMenu:rebuild()
    self.items = {
        { label = NeatXPStyle.tr("IGUI_NeatXP_Configure", "Configure"), action = function() self.bar:openConfig() end },
        { label = NeatXPStyle.tr("IGUI_NeatXP_Hide", "Hide"),      action = function() self.bar:setCollapsed(true) end },
    }
    local wMax = 120
    for _, it in ipairs(self.items) do
        wMax = math.max(wMax, getTextManager():MeasureStringX(FONT_MEDIUM, it.label) + 24)
    end
    self:setWidth(wMax)
    self:setHeight(self.itemH * #self.items)
end

function NeatXPMenu:prerender()
    NeatXPStyle.drawPanel(self, 0, 0, self.width, self.height, true, 1.0)
    local my = self:getMouseY()
    for i, it in ipairs(self.items) do
        local y = (i - 1) * self.itemH
        if self:isMouseOver() and my >= y and my < y + self.itemH then
            NeatXPStyle.drawButton(self, 3, y + 2, self.width - 6, self.itemH - 4, "hover")
        end
        self:drawText(it.label, 12, y + math.floor((self.itemH - getTextManager():getFontHeight(FONT_MEDIUM)) / 2),
            1, 1, 1, 1, FONT_MEDIUM)
    end
end

function NeatXPMenu:onMouseDown(x, y)
    local idx = math.floor(y / self.itemH) + 1
    local it = self.items[idx]
    self:close()
    if it then it.action() end
end

function NeatXPMenu:onMouseMoveOutside(dx, dy) self:close() end

function NeatXPMenu:close()
    self:setVisible(false)
    self:removeFromUIManager()
end

-- =============================================================================
-- NeatXPConfig
-- =============================================================================
NeatXPConfig = ISPanel:derive("NeatXPConfig")

function NeatXPConfig:new(bar)
    local fhMed = getTextManager():getFontHeight(FONT_MEDIUM)

    local pad      = 12
    local iconS    = 30
    local switchW  = 38
    local switchH  = 19
    local cellW    = iconS + 8 + switchW + 14
    local cols     = 4
    local rowH     = 40
    local n        = #bar.skillOrder
    local rows     = math.ceil(n / cols)

    local titleH  = fhMed + 16
    local footerH = fhMed + 26
    local listTop = titleH + pad
    local w = pad + cols * cellW + pad
    local h = listTop + rows * rowH + pad + footerH

    local o = ISPanel:new(
        math.floor((getCore():getScreenWidth() - w) / 2),
        math.floor((getCore():getScreenHeight() - h) / 2),
        w, h)
    setmetatable(o, self)
    self.__index = self

    o.bar = bar
    o.pad = pad
    o.iconS = iconS
    o.switchW = switchW
    o.switchH = switchH
    o.rowH = rowH
    o.titleH = titleH
    o.footerH = footerH
    o.listTop = listTop
    o.moveWithMouse = true
    o.background = false
    o.closeSize = math.floor(fhMed)   -- NR_Config.buttonSize

    o.cells = {}
    for i, skill in ipairs(bar.skillOrder) do
        local perk = bar:getPerk(skill)
        local name = perk and perk:getName() or skill
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local cx = pad + col * cellW
        local cy = listTop + 4 + row * rowH
        table.insert(o.cells, { skill = skill, name = name, x = cx, y = cy, w = cellW - 4, h = rowH })
    end

    local bw = 92
    o.btnClose = { x = w - pad - bw,  y = h - footerH + 10, w = bw, h = fhMed + 10, label = NeatXPStyle.tr("IGUI_NeatXP_Close", "Close") }
    o.btnAll   = { x = pad,           y = h - footerH + 10, w = bw, h = fhMed + 10, label = NeatXPStyle.tr("IGUI_NeatXP_All", "All") }
    o.btnNone  = { x = pad + bw + 8,  y = h - footerH + 10, w = bw, h = fhMed + 10, label = NeatXPStyle.tr("IGUI_NeatXP_None", "None") }
    return o
end

function NeatXPConfig:initialise() ISPanel.initialise(self) end

-- Rocco header anatomy: [title] ... [red X close] (NI_SquareButton, activeColor 0.8,0.2,0.2)
function NeatXPConfig:createChildren()
    ISPanel.createChildren(self)
    local bsz = self.closeSize
    local bx = self.width - self.pad - bsz
    local by = math.floor((self.titleH - bsz) / 2)
    local icon = getTexture("media/ui/NeatUI/ICON/Icon_False.png")
    local SB = rawget(_G, "NI_SquareButton")
    if SB then
        self.closeButton = SB:new(bx, by, bsz, icon, self, function() self:close() end)
        self.closeButton:initialise()
        self.closeButton:setActive(true)
        self.closeButton:setActiveColor(0.8, 0.2, 0.2)
        self:addChild(self.closeButton)
    else
        self.btnX = { x = bx, y = by, w = bsz, h = bsz, icon = icon }
    end
end

local function inRect(mx, my, r)
    return mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h
end

function NeatXPConfig:prerender()
    local w, h = self.width, self.height
    local mx, my = self:getMouseX(), self:getMouseY()
    local over = self:isMouseOver()

    -- Rocco anatomy: rounded MainTitle_BG header + FlatTop body below it (opaque)
    NeatXPStyle.drawWindow(self, 0, 0, w, h, self.titleH, 1.0, 1.0)
    self:drawText(NeatXPStyle.tr("IGUI_NeatXP_ConfigTitle", "Tracked skills"), self.pad,
        math.floor((self.titleH - getTextManager():getFontHeight(FONT_MEDIUM)) / 2),
        1, 1, 1, 1, FONT_MEDIUM)

    -- inner list panel
    local listBot = h - self.footerH
    NeatXPStyle.drawNP(self, NeatXPStyle.TEX.innerPanel, self.pad, self.listTop,
        w - self.pad * 2, listBot - self.listTop, 0.16, 0.93)

    -- rows: icon + switch
    local hoveredName = nil
    for _, c in ipairs(self.cells) do
        local hover = over and inRect(mx, my, c)
        if hover then
            self:drawRect(c.x + 2, c.y, c.w - 4, c.h, 0.10, 1, 1, 1)
            hoveredName = c.name
        end
        local tracked = self.bar:isTracked(c.skill)
        local ix = c.x + 6
        local iy = c.y + math.floor((c.h - self.iconS) / 2)
        NeatXPStyle.drawIcon(self, ix, iy, self.iconS, c.skill, c.name, tracked and 1 or 0.45)
        local sx = ix + self.iconS + 8
        local sy = c.y + math.floor((c.h - self.switchH) / 2)
        NeatXPStyle.drawSwitch(self, sx, sy, self.switchW, self.switchH, tracked)
    end

    -- fallback close X (only when NI_SquareButton is unavailable)
    if self.btnX then
        local bxHover = over and inRect(mx, my, self.btnX)
        local cr = { r = 0.8, g = 0.2, b = 0.2 }   -- NeatUI close red
        if bxHover then cr = { r = math.min(0.8 * 1.2, 1), g = 0.24, b = 0.24 } end
        local bgT = getTexture("media/ui/NeatUI/Button/Background.png")
        if bgT then
            self:drawTextureScaled(bgT, self.btnX.x, self.btnX.y, self.btnX.w, self.btnX.h, 0.8, cr.r, cr.g, cr.b)
        else
            self:drawRect(self.btnX.x, self.btnX.y, self.btnX.w, self.btnX.h, 0.8, cr.r, cr.g, cr.b)
        end
        if self.btnX.icon then
            local isz = math.floor(self.btnX.w * 0.8)
            local io_ = math.floor((self.btnX.w - isz) / 2)
            self:drawTextureScaled(self.btnX.icon, self.btnX.x + io_, self.btnX.y + io_, isz, isz, 1, 1, 1, 1)
        end
    end

    -- hovered skill name in the title bar (right side, clear of the X button)
    if hoveredName then
        self:drawTextRight(hoveredName, w - self.pad * 2 - self.closeSize,
            math.floor((self.titleH - getTextManager():getFontHeight(FONT_SMALL)) / 2),
            NeatXPStyle.accent.r, NeatXPStyle.accent.g, NeatXPStyle.accent.b, 1, FONT_SMALL)
    end

    -- footer buttons
    for _, b in ipairs({ self.btnAll, self.btnNone, self.btnClose }) do
        local hover = over and inRect(mx, my, b)
        NeatXPStyle.drawButton(self, b.x, b.y, b.w, b.h, hover and "hover" or nil)
        self:drawTextCentre(b.label, b.x + math.floor(b.w / 2),
            b.y + math.floor((b.h - getTextManager():getFontHeight(FONT_SMALL)) / 2),
            1, 1, 1, 1, FONT_SMALL)
    end
end

function NeatXPConfig:onMouseDown(x, y)
    if self.btnX and inRect(x, y, self.btnX) then self:close(); return end
    if inRect(x, y, self.btnClose) then self:close(); return end
    if inRect(x, y, self.btnAll) then
        for _, s in ipairs(self.bar.skillOrder) do self.bar:setTracked(s, true) end
        return
    end
    if inRect(x, y, self.btnNone) then
        for _, s in ipairs(self.bar.skillOrder) do self.bar:setTracked(s, false) end
        return
    end
    for _, c in ipairs(self.cells) do
        if inRect(x, y, c) then
            self.bar:setTracked(c.skill, not self.bar:isTracked(c.skill))
            return
        end
    end
    ISPanel.onMouseDown(self, x, y)
end

function NeatXPConfig:close()
    self.bar:writeConfig()
    self:setVisible(false)
    self:removeFromUIManager()
end

function NeatXPConfig:isKeyConsumed(key)
    return key == Keyboard.KEY_ESCAPE
end

function NeatXPConfig:onKeyRelease(key)
    if key == Keyboard.KEY_ESCAPE then self:close() end
end
