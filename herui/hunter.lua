-- 猎人UI插件主类
local HunterUI = {}
HunterUI.__index = HunterUI

-- 配置常量定义
HunterUI.CONFIG = {
    FRAME = {
        NAME = "HunterMainFrame",  -- 主框架名称
        WIDTH = 300,              -- 框架宽度
        HEIGHT = 40,              -- 框架高度
        BUTTON_SIZE = 36,         -- 按钮大小
        BUTTON_SPACING = 10,      -- 按钮间距
        TEXT_OFFSET = -10         -- 文字偏移量
    },
    
    COLORS = {
        ENABLED = {1.0, 1.0, 1.0},     -- 启用状态颜色(白色)
        DISABLED = {0.4, 0.4, 0.4},    -- 禁用状态颜色(灰色)
        MESSAGE_ENABLED = "|cff00ff00",  -- 启用消息颜色(绿色)
        MESSAGE_DISABLED = "|cffff0000"  -- 禁用消息颜色(红色)
    },
    
    MESSAGES = {
        ENABLED = "启用",
        DISABLED = "禁用", 
        NOT_HUNTER = "只有猎人职业可以使用此插件",
        STATE_CHANGE = "%s 现在是 %s%s|r"  -- 状态变化消息格式
    }
}

-- 按钮配置定义 - 定义所有可用的按钮
HunterUI.BUTTON_CONFIGS = {
    {
        id = "petAttack",
        name = "PetAttackButton", 
        icon = "Interface\\Icons\\Ability_Physical_Taunt", 
        label = "攻击",
        exclusiveWith = {"petFollow"}  -- 与宠物跟随互斥
    },
    {
        id = "petFollow",
        name = "PetFollowButton", 
        icon = "Interface\\Icons\\Spell_Nature_Spiritwolf", 
        label = "跟随",
        exclusiveWith = {"petAttack"}  -- 与宠物攻击互斥
    },
    {
        id = "intimidation",
        name = "IntimidationButton", 
        icon = "Interface\\Icons\\ability_whirlwind", 
        label = "威慑"  -- 威慑
    },
    {
        id = "interrupt",
        name = "InterruptButton",
        icon = "Interface\\Icons\\inv_ammo_arrow_03",
        label = "打断"  -- 自动打断
    },
    {
        id = "switchTarget",
        name = "SwitchTargetButton",
        icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
        label = "切目标"  -- 战斗中切目标
    }
}

-- 初始状态定义 - 设置各个功能的默认开启/关闭状态
HunterUI.INITIAL_STATES = {
    normal = true,           -- 普通模式默认开启
    aoe = false,            -- AOE模式默认关闭
    simple = false,         -- 简单模式默认关闭
    petAttack = true,       -- 宠物攻击默认开启
    petFollow = false,      -- 宠物跟随默认关闭
    interrupt = true,       -- 自动打断默认开启
    intimidation = true,    -- 威慑默认开启
    switchTarget = true     -- 战斗中切目标默认开启
}

-- 构造函数 - 创建新的HunterUI实例
function HunterUI:new()
    -- 检查是否为猎人职业
    if not self:isValidClass() then
        self:showMessage(self.CONFIG.MESSAGES.NOT_HUNTER)
        return nil
    end

    local instance = setmetatable({}, self)
    instance:initialize()
    return instance
end

-- 职业验证 - 检查玩家是否为猎人
function HunterUI:isValidClass()
    local _, playerClass = UnitClass("player")
    return playerClass == "HUNTER"
end

-- 初始化函数 - 设置UI和状态
function HunterUI:initialize()
    self:initializeStates()    -- 初始化状态
    self:createMainFrame()     -- 创建主框架
    self:createButtons()       -- 创建按钮
    self:registerSlashCommands() -- 注册斜杠命令
    self:updateAllStates()     -- 更新所有状态显示
end

-- 初始化状态表 - 从默认配置复制状态
function HunterUI:initializeStates()
    self.states = {}
    for stateName, value in pairs(self.INITIAL_STATES) do
        self.states[stateName] = value
    end
    self.buttons = {}  -- 初始化按钮表
end

-- 创建主框架 - 设置可拖拽的主窗口
function HunterUI:createMainFrame()
    local config = self.CONFIG.FRAME
    
    -- 创建主框架
    self.frame = CreateFrame("Frame", config.NAME, UIParent)
    self.frame:SetSize(config.WIDTH, config.HEIGHT)
    self.frame:SetPoint("CENTER")  -- 居中显示
    
    self:setupFrameInteraction()  -- 设置框架交互
end

-- 设置框架交互 - 使框架可拖拽
function HunterUI:setupFrameInteraction()
    self.frame:SetMovable(true)           -- 设置可移动
    self.frame:EnableMouse(true)          -- 启用鼠标
    self.frame:RegisterForDrag("LeftButton")  -- 注册左键拖拽
    -- 开始拖拽
    self.frame:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
    -- 停止拖拽
    self.frame:SetScript("OnDragStop", function(frame) frame:StopMovingOrSizing() end)
end

-- 创建单个按钮 - 根据配置创建按钮
function HunterUI:createButton(config)
    local button = CreateFrame("Button", config.name, self.frame, "ActionButtonTemplate")
    button:SetSize(self.CONFIG.FRAME.BUTTON_SIZE, self.CONFIG.FRAME.BUTTON_SIZE)
    
    self:setupButtonAppearance(button, config)  -- 设置按钮外观
    self:setupButtonInteraction(button, config) -- 设置按钮交互
    
    return button
end

-- 设置按钮外观 - 设置图标和文字
function HunterUI:setupButtonAppearance(button, config)
    -- 设置按钮图标
    button.icon = _G[button:GetName().."Icon"]
    button.icon:SetTexture(config.icon)
    
    -- 创建文字标签
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.text:SetPoint("BOTTOM", button, "BOTTOM", 0, self.CONFIG.FRAME.TEXT_OFFSET)
    button.text:SetText(config.label)
end

-- 设置按钮交互 - 绑定点击事件
function HunterUI:setupButtonInteraction(button, config)
    button:SetScript("OnClick", function()
        self:toggleState(config.id, config.exclusiveWith)
    end)
end

-- 创建所有按钮 - 遍历配置创建并排列按钮
function HunterUI:createButtons()
    local lastButton = nil
    
    for _, config in ipairs(self.BUTTON_CONFIGS) do
        local button = self:createButton(config)
        
        -- 设置按钮位置（水平排列）
        if lastButton then
            button:SetPoint("LEFT", lastButton, "RIGHT", self.CONFIG.FRAME.BUTTON_SPACING, 0)
        else
            button:SetPoint("LEFT", self.frame, "LEFT", self.CONFIG.FRAME.BUTTON_SPACING, 0)
        end
        
        self.buttons[config.id] = button  -- 保存按钮引用
        lastButton = button
    end
end

-- 切换状态 - 处理按钮点击，包括互斥逻辑
function HunterUI:toggleState(stateName, exclusiveStates)
    if not self:isValidState(stateName) then
        return
    end
    
    local oldState = self.states[stateName]
    self.states[stateName] = not oldState  -- 切换状态
    
    -- 如果启用了该状态且有互斥状态，则禁用互斥状态
    if self.states[stateName] and exclusiveStates then
        self:disableExclusiveStates(exclusiveStates)
    end
    
    self:updateStateDisplay(stateName, oldState)  -- 更新显示
    self:updateButtonAppearance(stateName)        -- 更新按钮外观
end

-- 优化的状态切换 - 支持强制开启/关闭
function HunterUI:optimizedToggle(stateName, action)
    if not self:isValidState(stateName) then
        return
    end
    
    local oldState = self.states[stateName]
    
    -- 根据参数设置状态
    if action == "on" then
        self.states[stateName] = true
    elseif action == "off" then
        self.states[stateName] = false
    else
        self.states[stateName] = not oldState  -- 切换状态
    end
    
    self:updateStateDisplay(stateName, oldState)
    self:updateButtonAppearance(stateName)
end

-- 验证状态名称是否有效
function HunterUI:isValidState(stateName)
    return self.states[stateName] ~= nil
end

-- 禁用互斥状态 - 当启用某个状态时，禁用与之互斥的状态
function HunterUI:disableExclusiveStates(exclusiveStates)
    for _, state in ipairs(exclusiveStates) do
        if self:isValidState(state) then
            self.states[state] = false
            self:updateButtonAppearance(state)
        end
    end
end

-- 更新状态显示 - 在聊天窗口显示状态变化消息
function HunterUI:updateStateDisplay(stateName, oldState)
    local newState = self.states[stateName]
    if newState ~= oldState then
        local stateText = newState and self.CONFIG.MESSAGES.ENABLED or self.CONFIG.MESSAGES.DISABLED
        local color = newState and self.CONFIG.COLORS.MESSAGE_ENABLED or self.CONFIG.COLORS.MESSAGE_DISABLED
        
        local message = string.format(self.CONFIG.MESSAGES.STATE_CHANGE, stateName, color, stateText)
        self:showMessage(message)
    end
end

-- 更新按钮外观 - 根据状态改变按钮颜色
function HunterUI:updateButtonAppearance(stateName)
    local button = self.buttons[stateName]
    if button then
        local state = self.states[stateName]
        local colors = state and self.CONFIG.COLORS.ENABLED or self.CONFIG.COLORS.DISABLED
        button.icon:SetVertexColor(colors[1], colors[2], colors[3])  -- 设置图标颜色
    end
end

-- 更新所有状态 - 初始化时更新所有按钮外观
function HunterUI:updateAllStates()
    for stateName, _ in pairs(self.states) do
        self:updateButtonAppearance(stateName)
    end
end

-- 显示消息 - 在聊天窗口输出消息
function HunterUI:showMessage(message)
    print(message)
end

-- 注册斜杠命令 - 设置聊天命令
function HunterUI:registerSlashCommands()
    -- 显示UI的测试命令
    self:registerCommand("TEST", "/testbuttons", function() 
        self.frame:Show() 
    end)
    
    -- 普通模式切换命令
    self:registerCommand("NORMAL", "/normal", function(msg) 
        self:optimizedToggle("normal", msg) 
    end)
    
    -- AOE模式切换命令
    self:registerCommand("AOE", "/aoe", function(msg) 
        self:optimizedToggle("aoe", msg) 
    end)
    
    -- 简单模式切换命令
    self:registerCommand("SIMPLE", "/simple", function(msg) 
        self:optimizedToggle("simple", msg) 
    end)
end

-- 注册单个命令 - 辅助函数用于注册斜杠命令
function HunterUI:registerCommand(key, command, handler)
    _G["SLASH_"..key.."1"] = command      -- 设置命令字符串
    SlashCmdList[key] = handler           -- 设置命令处理函数
end

-- 获取状态函数 - 返回获取指定状态的函数
function HunterUI:getState(stateName)
    if not self:isValidState(stateName) then
        return function() return false end  -- 无效状态返回false
    end
    
    return function()
        return self.states[stateName]
    end
end

-- 获取AOE状态 - 专门用于AOE模式判断
function HunterUI:getAOEState()
    return self.states.aoe
end

-- 显示UI - 显示主框架
function HunterUI:show()
    if self.frame then
        self.frame:Show()
    end
end

-- 隐藏UI - 隐藏主框架
function HunterUI:hide()
    if self.frame then
        self.frame:Hide()
    end
end

-- 销毁UI - 清理资源
function HunterUI:destroy()
    if self.frame then
        self.frame:Hide()
        self.frame = nil
    end
    self.buttons = nil
    self.states = nil
end

-- 创建插件实例
local hunterInstance = HunterUI:new()

-- 如果实例创建成功，导出全局函数供其他插件使用
if hunterInstance then
    -- 导出各种状态检查函数
    _G.HERUINormal = hunterInstance:getState("normal")                -- 普通模式状态
    _G.HERUISimple = hunterInstance:getState("simple")                -- 简单模式状态
    _G.HERUIPetAttack = hunterInstance:getState("petAttack")          -- 宠物攻击状态
    _G.HERUIPetFollow = hunterInstance:getState("petFollow")          -- 宠物跟随状态
    _G.HERUIInterrupt = hunterInstance:getState("interrupt")          -- 自动打断状态
    _G.HERUIIntimidation = hunterInstance:getState("intimidation")    -- 威慑状态
    _G.HERUISwitchTarget = hunterInstance:getState("switchTarget")    -- 切目标状态
    _G.HERUIAOE = function() return hunterInstance:getAOEState() end  -- AOE模式状态

    -- 导出插件实例供直接访问
    _G.HunterUI = hunterInstance
end

