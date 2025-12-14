local Tinkr = ...

local Evaulator = Tinkr.Evaluator

---@class Bastion
local Bastion = {DebugMode = false}
Bastion.__index = Bastion

function Bastion:Require(file)
    -- If require starts with an @ then we require from the scripts/bastion/scripts folder
    if file:sub(1, 1) == '@' then
        file = file:sub(2)
        -- print('1')
        return require('scripts/bastion/scripts/' .. file, Bastion)
    elseif file:sub(1, 1) == "~" then
        file = file:sub(2)
        -- print("2")
        return require('scripts/bastion/' .. file, Bastion)
    else
        -- print("Normal req")
        return require(file, Bastion)
    end
end

local function Load(dir)
    local dir = dir

    if dir:sub(1, 1) == '@' then
        dir = dir:sub(2)
        dir = 'scripts/bastion/scripts/' .. dir
    end

    if dir:sub(1, 1) == '~' then
        dir = dir:sub(2)
        dir = 'scripts/bastion/' .. dir
    end

    local files = ListFiles(dir)

    for i = 1, #files do
        local file = files[i]
        if file:sub(-4) == ".lua" or file:sub(-5) == '.luac' then
            local fileName = file:sub(1, -5)  -- 移除文件扩展名
            Bastion:Require(dir .. fileName)
        end
    end
end

function Bastion.require(class)
    -- return require("scripts/bastion/src/" .. class .. "/" .. class, Bastion)
    return Bastion:Require("~/src/" .. class .. "/" .. class)
end

-- fenv for all required files
function Bastion.Bootstrap()
    -- 创建状态图标框架
    local statusFrame = CreateFrame("Frame", "BastionStatusFrame", UIParent)
    statusFrame:SetSize(48, 48)  -- 图标尺寸从32x32改为48x48
    statusFrame:SetPoint("CENTER", UIParent, "CENTER", -500, 300)
    statusFrame:SetMovable(true)
    statusFrame:EnableMouse(true)
    statusFrame:RegisterForDrag("LeftButton")
    statusFrame:SetScript("OnDragStart", statusFrame.StartMoving)
    statusFrame:SetScript("OnDragStop", statusFrame.StopMovingOrSizing)

    -- 创建图标纹理
    local texture = statusFrame:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints()
    texture:SetTexture("Interface\\Icons\\Ability_Hunter_RunningShot")

    local LIBRARIES = {}
    local MODULES = {}

    function Bastion:UpdateStatusDisplay()
        statusFrame:Show()

        local anyModuleEnabled = false
        for i = 1, #MODULES do
            if MODULES[i].enabled then
                anyModuleEnabled = true
                break
            end
        end

        -- 移除全局开关依赖，只基于模块状态显示
        if anyModuleEnabled then
            texture:SetDesaturated(false)
            texture:SetVertexColor(1, 2, 1, 1)
        else
            texture:SetDesaturated(true)
            texture:SetVertexColor(0.4, 0.4, 0.4, 0.8)
        end
    end

    Bastion.Globals = {}

    ---@type ClassMagic
    Bastion.ClassMagic = Bastion.require("ClassMagic")
    ---@type List
    Bastion.List = Bastion.require("List")
    ---@type Library
    Bastion.Library = Bastion.require("Library")
    ---@type NotificationsList, Notification
    Bastion.NotificationsList, Bastion.Notification = Bastion.require(
                                                          "NotificationsList")
    ---@type Vector3
    Bastion.Vector3 = Bastion.require("Vector3")
    ---@type Sequencer
    Bastion.Sequencer = Bastion.require("Sequencer")
    ---@type Command
    Bastion.Command = Bastion.require("Command")
    ---@type Cache
    Bastion.Cache = Bastion.require("Cache")
    ---@type Cacheable
    Bastion.Cacheable = Bastion.require("Cacheable")
    ---@type Refreshable
    Bastion.Refreshable = Bastion.require("Refreshable")
    ---@type Unit
    Bastion.Unit = Bastion.require("Unit")
    ---@type Aura
    Bastion.Aura = Bastion.require("Aura")
    ---@type APL, APLActor, APLTrait
    Bastion.APL, Bastion.APLActor, Bastion.APLTrait = Bastion.require("APL")
    ---@type Module
    Bastion.Module = Bastion.require("Module")
    ---@type UnitManager
    Bastion.UnitManager = Bastion.require("UnitManager"):New()
    ---@type ObjectManager
    Bastion.ObjectManager = Bastion.require("ObjectManager"):New()
    ---@type EventManager
    Bastion.EventManager = Bastion.require("EventManager")
    Bastion.Globals.EventManager = Bastion.EventManager:New()
    ---@type Spell
    Bastion.Spell = Bastion.require("Spell")
    ---@type SpellBook
    Bastion.SpellBook = Bastion.require("SpellBook")
    Bastion.Globals.SpellBook = Bastion.SpellBook:New()
    ---@type Item
    Bastion.Item = Bastion.require("Item")
    ---@type ItemBook
    Bastion.ItemBook = Bastion.require("ItemBook")
    Bastion.Globals.ItemBook = Bastion.ItemBook:New()
    ---@type AuraTable
    Bastion.AuraTable = Bastion.require("AuraTable")
    ---@type Class
    Bastion.Class = Bastion.require("Class")
    ---@type Timer
    Bastion.Timer = Bastion.require("Timer")
    ---@type Timer
    Bastion.CombatTimer = Bastion.Timer:New('combat')
    ---@type NotificationsList
    Bastion.Notifications = Bastion.NotificationsList:New()

    -- ===================== 核心系统初始化完成 =====================

    -- 初始化游戏单位引用（依赖 UnitManager）
    local Player = Bastion.UnitManager:Get('player')
    local Focus = Bastion.UnitManager:Get('focus')

    -- 初始化法术引用（依赖 SpellBook）

    -- 初始化战斗日志相关变量
    local pguid = UnitGUID("player")
    local missed = {}

    -- ===================== 状态显示初始化 =====================
    -- 插件默认启用，只通过模块级别控制，无需全局开关
    Bastion:UpdateStatusDisplay()

    -- ===================== 事件注册 =====================
    -- 注册单位光环更新事件
    Bastion.Globals.EventManager:RegisterWoWEvent('UNIT_AURA',
                                                  function(unit, auras)
        local u = Bastion.UnitManager[unit]

        if u then u:GetAuras():OnUpdate(auras) end
    end)

    -- 注册法术施放成功事件
    Bastion.Globals.EventManager:RegisterWoWEvent("UNIT_SPELLCAST_SUCCEEDED",
                                                  function(...)
        local unit, _, spellID = ...

        local spell = Bastion.Globals.SpellBook:GetIfRegistered(spellID)

        if unit == "player" and spell then
            spell.lastCastAt = GetTime()

            if spell:GetPostCastFunction() then
                spell:GetPostCastFunction()(spell)
            end
        end
    end)

    -- 注册战斗日志事件
    Bastion.Globals.EventManager:RegisterWoWEvent("COMBAT_LOG_EVENT_UNFILTERED",
                                                  function()
        local args = {CombatLogGetCurrentEventInfo()}

        local subEvent = args[2]
        local sourceGUID = args[4]
        local destGUID = args[8]
        local spellID = args[12]

        local u = Bastion.UnitManager[sourceGUID]
        local u2 = Bastion.UnitManager[destGUID]

        local t = GetTime()

        if u then u:SetLastCombatTime(t) end

        if u2 then
            u2:SetLastCombatTime(t)

            if subEvent == "SPELL_MISSED" and sourceGUID == pguid and spellID == 408 then
                local missType = args[15]

                if missType == "IMMUNE" then
                    local castingSpell = u:GetCastingOrChannelingSpell()

                    if castingSpell then
                        if not missed[castingSpell:GetID()] then
                            missed[castingSpell:GetID()] = true
                        end
                    end
                end
            end
        end
    end)

    -- ===================== 主循环定时器 =====================
    Bastion.Ticker = C_Timer.NewTicker(0.1, function()
        -- 战斗计时器管理
        if not Bastion.CombatTimer:IsRunning() and UnitAffectingCombat("player") then
            Bastion.CombatTimer:Start()
        elseif Bastion.CombatTimer:IsRunning() and not UnitAffectingCombat("player") then
            Bastion.CombatTimer:Reset()
        end


        -- 对象管理器刷新
        Bastion.ObjectManager:Refresh()

        -- 执行所有已注册的模块（每个模块内部检查自己的enabled状态）
        for i = 1, #MODULES do
            MODULES[i]:Tick()
        end
    end)

    -- ===================== 模块管理函数 =====================
    function Bastion:_ActivateExclusive(module)
        if not module then return false end

        for i = 1, #MODULES do
            local other = MODULES[i]
            if other ~= module and other.enabled then
                other:Disable()
                Bastion:Print("已自动禁用", other.name)
            end
        end

        module.enabled = true
        Bastion:UpdateStatusDisplay()
        return true
    end

    function Bastion:ActivateModule(target)
        local module = target
        if type(target) == 'string' then
            module = Bastion:FindModule(target)
        end

        if not module then
            return false, "Module not found"
        end

        if module.enabled then
            Bastion:UpdateStatusDisplay()
            return true
        end

        Bastion:_ActivateExclusive(module)
        Bastion:Print("Enabled", module.name)
        return true
    end

    function Bastion:Register(module)
        table.insert(MODULES, module)
        Bastion:Print("Registered", module)
    end

    -- 根据名称查找模块
    function Bastion:FindModule(name)
        for i = 1, #MODULES do
            if MODULES[i].name == name then return MODULES[i] end
        end

        return nil
    end

    -- ===================== 日志输出函数 =====================
    function Bastion:Print(...)
        local args = {...}
        local str = "|cFFDF362D[Bastion]|r |cFFFFFFFF"
        for i = 1, #args do str = str .. tostring(args[i]) .. " " end
        print(str)
    end

    function Bastion:Debug(...)
        if not Bastion.DebugMode then return end
        local args = {...}
        local str = "|cFFDF6520[Bastion]|r |cFFFFFFFF"
        for i = 1, #args do str = str .. tostring(args[i]) .. " " end
        print(str)
    end

    local Command = Bastion.Command:New('bastion')

    -- 移除全局 toggle 命令，插件默认启用，只通过模块级别控制
    -- Command:Register('toggle', 'Toggle bastion on/off', function()
    --     Bastion.Enabled = not Bastion.Enabled
    --     if Bastion.Enabled then
    --         Bastion:Print("Enabled")
    --     else
    --         Bastion:Print("Disabled")
    --     end
    --     Bastion:UpdateStatusDisplay()
    -- end)

    Command:Register('debug', 'Toggle debug mode on/off', function()
        Bastion.DebugMode = not Bastion.DebugMode
        if Bastion.DebugMode then
            Bastion:Print("Debug mode enabled")
        else
            Bastion:Print("Debug mode disabled")
        end
    end)

    Command:Register('dumpspells', 'Dump spells to a file', function()
        Bastion:Print('DumpSpells: started')
        local success, err = pcall(function()
            local i = 1
            local rand = math.random(100000, 999999)
            local filename = 'bastion-' .. UnitClass('player') .. '-' .. rand .. '.lua'
            local count = 0
            local BOOKTYPE_SPELL = BOOKTYPE_SPELL or (Enum.SpellBookSpellBank.Player and Enum.SpellBookSpellBank.Player or 'spell')
            local seen = {}

            while true do
                local spellName, spellSubName

                if C_SpellBook and C_SpellBook.GetSpellBookItemName then
                    spellName, spellSubName = C_SpellBook.GetSpellBookItemName(i, BOOKTYPE_SPELL)
                elseif GetSpellBookItemName then
                    spellName, spellSubName = GetSpellBookItemName(i, BOOKTYPE_SPELL)
                end

                if not spellName then do break end end

                -- use spellName and spellSubName here
                local spellID
                local skip = false
                local rawSpellName = spellName

                -- First try the new SpellBook API (Dragonflight+)
                if not spellID and C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
                    local bookInfo = C_SpellBook.GetSpellBookItemInfo(i, BOOKTYPE_SPELL)
                    if bookInfo then
                        spellID = bookInfo.spellID
                        if bookInfo.name then rawSpellName = bookInfo.name end
                    end
                end

                -- Fallback to legacy API
                if not spellID and GetSpellBookItemInfo then
                    local skillType, legacySpellID = GetSpellBookItemInfo(i, BOOKTYPE_SPELL)
                    if legacySpellID and legacySpellID > 0 then
                        spellID = legacySpellID
                    end
                end

                -- Last resort: resolve via spell name lookup
                if not spellID then
                    if C_Spell and C_Spell.GetSpellInfo then
                        local info = C_Spell.GetSpellInfo(spellName)
                        if info then
                            spellID = info.spellID
                        end
                    elseif GetSpellInfo then
                        spellID = select(7, GetSpellInfo(spellName))
                    end
                end

                if not spellID then
                    Bastion:Print('DumpSpells: failed to resolve spell info for', rawSpellName)
                    skip = true
                end

                if not skip and spellID and seen[spellID] then
                    skip = true
                end

                if not skip and spellID then
                    seen[spellID] = true

                    local safeName = (spellName or rawSpellName or 'Spell')
                    safeName = safeName:gsub("[^%w_]+", "")
                    if safeName == '' or safeName:match('^%d') then
                        safeName = 'Spell' .. tostring(spellID)
                    end

                    local commentName = rawSpellName or ('Spell ' .. tostring(spellID))
                    local line = string.format(
                                      "local %s = Bastion.Globals.SpellBook:GetSpell(%d) -- %s\n",
                                      safeName, spellID, commentName)

                    local ok, writeErr = pcall(WriteFile, filename, line, true)
                    if not ok then
                        Bastion:Print('DumpSpells: WriteFile error', tostring(writeErr))
                        if UIErrorsFrame then
                            UIErrorsFrame:AddMessage('DumpSpells WriteFile error: ' .. tostring(writeErr), 1, 0, 0)
                        end
                        break
                    end

                    count = count + 1
                end
                i = i + 1
            end

            if count == 0 then
                Bastion:Print('DumpSpells: no spells exported')
            else
                Bastion:Print('DumpSpells: exported', count, 'spells to', filename)
            end
        end)

        if not success then
            Bastion:Print('DumpSpells: error', err)
            if UIErrorsFrame then UIErrorsFrame:AddMessage('DumpSpells error: ' .. tostring(err), 1, 0, 0) end
        end
    end)

    Command:Register('module', 'Toggle a module on/off', function(args)
        local name = args[2]
        if not name or name == '' then
            Bastion:Print('Module name required')
            return
        end

        local module = Bastion:FindModule(name)
        if not module then
            Bastion:Print('Module not found')
            return
        end

        if module.enabled then
            module:Disable()
            Bastion:Print('Disabled', module.name)
            Bastion:UpdateStatusDisplay()
            return
        end

        local ok, err = Bastion:ActivateModule(module)
        if not ok and err then
            Bastion:Print(err)
        end
    end)

    

    Command:Register('missed', 'Dump the list of immune kidney shot spells',
                     function()
        for k, v in pairs(missed) do Bastion:Print(k) end
    end)

    ---@param library Library
    function Bastion:RegisterLibrary(library)
        LIBRARIES[library.name] = library
    end

    function Bastion:CheckLibraryDependencies()
        for k, v in pairs(LIBRARIES) do
            if v.dependencies then
                for i = 1, #v.dependencies do
                    local dep = v.dependencies[i]
                    if LIBRARIES[dep] then
                        if LIBRARIES[dep].dependencies then
                            for j = 1, #LIBRARIES[dep].dependencies do
                                if LIBRARIES[dep].dependencies[j] == v.name then
                                    Bastion:Print(
                                        "Circular dependency detected between " ..
                                            v.name .. " and " .. dep)
                                    return false
                                end
                            end
                        end
                    else
                        Bastion:Print("Library " .. v.name .. " depends on " ..
                                          dep .. " but it's not registered")
                        return false
                    end
                end
            end
        end

        return true
    end

    function Bastion:Import(library)
        local lib = self:GetLibrary(library)

        if not lib then error("Library " .. library .. " not found") end

        return lib:Resolve()
    end

    function Bastion:GetLibrary(name)
        if not LIBRARIES[name] then
            error("Library " .. name .. " not found")
        end

        local library = LIBRARIES[name]

        -- if library.dependencies then
        --     for i = 1, #library.dependencies do
        --         local dep = library.dependencies[i]
        --         if LIBRARIES[dep] then
        --             if LIBRARIES[dep].dependencies then
        --                 for j = 1, #LIBRARIES[dep].dependencies do
        --                     if LIBRARIES[dep].dependencies[j] == library.name then
        --                         Bastion:Print("Circular dependency detected between " .. library.name .. " and " .. dep)
        --                         return false
        --                     end
        --                 end
        --             end
        --         else
        --             Bastion:Print("Library " .. v.name .. " depends on " .. dep .. " but it's not registered")
        --             return false
        --         end
        --     end
        -- end

        return library
    end

    -- ===================== 外部文件加载 =====================
    -- 依赖检查（当前已注释）
    -- if not Bastion:CheckLibraryDependencies() then
    --     return
    -- end

    -- 按顺序加载外部文件
    Load("@Libraries/")  -- 加载库文件
    Load("@Modules/")    -- 加载模块文件
    Load("@")            -- 加载脚本根目录文件
    
    -- ===================== HERUI 组件加载 =====================
    -- 根据玩家职业加载对应的 HERUI UI 插件
    local _, playerClass = UnitClass("player")
    
    if playerClass == "HUNTER" then
        -- 加载猎人UI插件
        Bastion:Require("~/src/herui/hunter")
        Bastion:Print("已加载猎人UI插件")
    elseif playerClass == "MAGE" then
        -- 加载冰霜法师UI插件
        Bastion:Require("~/src/herui/frost")
        Bastion:Print("已加载冰霜法师UI插件")
        
        -- 奥术专精（暂时注释）
        -- Bastion:Require("~/src/herui/arcane")
        -- Bastion:Print("已加载奥术法师UI插件")
    end
    
    -- 为Cube等外部插件提供Tinkr访问接口
    -- _G.__HERUItest__ = Tinkr
    -- Bastion:Print("HERUItest已暴露到全局变量 __HERUItest__")

    -- 将Objects函数暴露为全局函数
    -- _G.HERUIObjectRawPosition = ObjectRawPosition

    -- 将整个Bastion对象暴露为全局变量
    -- _G.HERUIBastion = Bastion
    -- Bastion:Print("Bastion对象已暴露到全局变量 _G.HERUIBastion")
end

-- ===================== 启动 Bastion 系统 =====================
Bastion.Bootstrap()
