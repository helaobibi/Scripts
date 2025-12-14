local Tinkr, Bastion = ...

-- ===================== 1. 创建模块 =====================
local FrostMage = Bastion.Module:New('FrostMage')

-- ===================== 2. 获取基础单位 =====================
local Player = Bastion.UnitManager:Get('player')
local Target = Bastion.UnitManager:Get('target')

-- ===================== 3. 创建基础系统 =====================
-- 创建法术书
local SpellBook = Bastion.Globals.SpellBook
-- 创建物品书
local ItemBook = Bastion.Globals.ItemBook
-- 创建计时器
local Timer = Bastion.Timer

-- ===================== 4. 定义技能 =====================
-- 基础技能
local VoidTorrent = SpellBook:GetSpell(114923)      -- 虚空风暴
local Spellsteal = SpellBook:GetSpell(30449)        -- 法术吸取
local VoidEnergy = SpellBook:GetSpell(66228)        -- 虚空之能
local IcyFloes = SpellBook:GetSpell(108839)         -- 浮冰
local Berserking = SpellBook:GetSpell(26297)        -- 狂暴
local EngineeringGloves = ItemBook:GetItem(47763)   -- 工程手套
local MirrorImage = SpellBook:GetSpell(55342)       -- 镜像
local IceBlock = SpellBook:GetSpell(45438)          -- 冰箱
local Counterspell = SpellBook:GetSpell(2139)       -- 法术反制
local VampiricEmbrace = SpellBook:GetSpell(70674)   -- 吸血鬼之力
local IceArmor = SpellBook:GetSpell(11426)          -- 寒冰护体

-- 奥术技能
local ArcaneBlast = SpellBook:GetSpell(30451)       -- 奥术冲击
local ArcaneBarrage = SpellBook:GetSpell(44425)     -- 奥术弹幕
local ArcaneMissiles = SpellBook:GetSpell(5143)     -- 奥术飞弹
local ArcaneMissilesBuff = SpellBook:GetSpell(79683) -- 奥术飞弹buff
local ArcanePower = SpellBook:GetSpell(36032)       -- 奥术充能

-- 冰霜技能
local IceLance = SpellBook:GetSpell(30455)          -- 冰枪术
local IcyVeins = SpellBook:GetSpell(12472)          -- 冰冷血脉
local FrozenOrb = SpellBook:GetSpell(84714)         -- 寒冰宝珠
local Frostbolt = SpellBook:GetSpell(116)           -- 寒冰箭
local Frostfire = SpellBook:GetSpell(44614)         -- 霜火之箭
local FocusMagicBuff = SpellBook:GetSpell(57761)    -- 冰冷智慧buff
local FingersOfFrostBuff = SpellBook:GetSpell(44544) -- 寒冰指buff
local LivingBomb = SpellBook:GetSpell(44457)        -- 活动炸弹

-- ===================== 5. 状态追踪 =====================
-- 虚空风暴施放计时器
local voidTorrentTimers = {}
-- 活动炸弹施放计时器
local livingBombTimers = {}

-- ===================== 6. 目标系统 =====================
-- 寻找可打断目标（正在施法且可打断，且在战斗中）
local InterruptTarget = Bastion.UnitManager:CreateCustomUnit('interrupttarget', function()
    -- 先检查当前目标是否满足条件
    if Target:Exists()
        and Target:IsAlive()
        and Target:IsAffectingCombat()
        and Target:IsInterruptible()
        and Frostbolt:IsInRange(Target) then
        return Target
    end

    -- 如果当前目标不满足条件，查找任意一个可打断的目标
    local interruptTarget = Bastion.ObjectManager.enemies:find(function(unit)
        return unit:IsAlive()
            and unit:IsAffectingCombat()
            and unit:IsInterruptible()
            and Frostbolt:IsInRange(unit)
            and Player:CanSee(unit)
            and Player:IsFacing(unit)
    end)

    return interruptTarget or Bastion.UnitManager:Get('none')
end)

-- 寻找最佳目标
local BestTarget = Bastion.UnitManager:CreateCustomUnit('besttarget', function()
    local bestTarget = nil
    local highestHealth = 0

    Bastion.ObjectManager.enemies:each(function(unit)
        -- 先检查单位是否存在和存活
        if not (unit:Exists() and unit:IsAlive()) then
            return false
        end

        -- 再检查其他条件
        if unit:IsAffectingCombat()
           and Frostbolt:IsInRange(unit)
           and Player:CanSee(unit)
           and Player:IsFacing(unit) then
            -- 如果没有最佳目标或当前单位血量更高
            if unit:GetHealth() > highestHealth then
                bestTarget = unit
                highestHealth = unit:GetHealth()
            end
        end
    end)

    return bestTarget or Bastion.UnitManager:Get('none')
end)

-- 获取最佳虚空风暴目标
local BestVoidTorrentTarget = Bastion.UnitManager:CreateCustomUnit('bestvoidtorrenttarget', function()
    -- 使用each方法遍历敌人列表
    local bestTarget = nil
    local highestHealth = 0

    Bastion.ObjectManager.enemies:each(function(unit)
        -- 先检查单位是否存在和存活
        if not (unit:Exists() and unit:IsAlive()) then
            return false
        end

        -- 检查目标是否在计时器记录内
        if voidTorrentTimers[unit:GetGUID()] and voidTorrentTimers[unit:GetGUID()]:GetTime() < 12 then
            return false
        end

        -- 检查目标是否符合所有条件
        if Frostbolt:IsInRange(unit)
           and not unit:GetAuras():FindMy(VoidTorrent):IsUp()
           and unit:IsAffectingCombat()
           and Player:CanSee(unit) then
            -- 如果没有最佳目标或当前单位血量更高
            if unit:GetHealth() > highestHealth then
                bestTarget = unit
                highestHealth = unit:GetHealth()
            end
        end
    end)

    return bestTarget or Bastion.UnitManager:Get('none')
end)

-- 获取最佳活动炸弹目标
local BestLivingBombTarget = Bastion.UnitManager:CreateCustomUnit('bestlivingbombtarget', function()
    local livingBombCount = 0
    local bestTarget = nil
    local highestHealth = 0

    Bastion.ObjectManager.enemies:each(function(unit)
        if not (unit:Exists() and unit:IsAlive()) then return false end

        -- 统计有活动炸弹buff的目标数量
        if unit:GetAuras():FindMy(LivingBomb):IsUp() then
            livingBombCount = livingBombCount + 1
            return false
        end

        -- 如果已有3个目标有buff，不再查找
        if livingBombCount >= 3 then return false end

        -- 查找最佳目标
        if Frostbolt:IsInRange(unit)
           and unit:IsAffectingCombat()
           and Player:CanSee(unit)
           and (not livingBombTimers[unit:GetGUID()] or livingBombTimers[unit:GetGUID()]:GetTime() >= 12)
           and unit:GetHealth() > highestHealth then
            bestTarget = unit
            highestHealth = unit:GetHealth()
        end
    end)

    return (livingBombCount < 3 and bestTarget) or Bastion.UnitManager:Get('none')
end)

-- 寻找可偷取法术的目标
local SpellstealTarget = Bastion.UnitManager:CreateCustomUnit('spellstealtarget', function()
    -- 使用find方法查找第一个符合条件的敌人
    local target = Bastion.ObjectManager.enemies:find(function(unit)
        return (unit:GetAuras():Find(VoidEnergy):IsUp() or unit:GetAuras():Find(VampiricEmbrace):IsUp())
           and unit:IsAlive()
           and unit:IsAffectingCombat()
           and Frostbolt:IsInRange(unit)
           and Player:CanSee(unit)
    end)

    return target or Bastion.UnitManager:Get('none')
end)

-- ===================== 7. 辅助函数 =====================
-- 选择目标
local function CheckAndSetTarget()
    if not Target:Exists() or Target:IsFriendly() or not Target:IsAlive() then
        if BestTarget:Exists() then -- 检查最佳目标是否存在
            -- 设置最佳目标为当前目标
            SetTargetObject(BestTarget.unit)
            return true
        end
    end
    return false
end

-- ===================== 8. APL定义 =====================
local DefensiveAPL = Bastion.APL:New('defensive')  -- 防御循环
local SingleTargetAPL = Bastion.APL:New('singletarget')  -- 单体循环
local BurstAPL = Bastion.APL:New('burst')  -- 爆发循环
local AoeAPL = Bastion.APL:New('aoe')      -- AOE循环
local SimpleAPL = Bastion.APL:New('simple')  -- 简单循环

-- ===================== 9. 防御循环 =====================
-- 治疗石
DefensiveAPL:AddAction("UseHealingStone", function()
    -- 先检查血量，避免不必要的背包搜索
    if Player:GetHP() <= 50 and Player:IsAffectingCombat() then
        local healingStone = ItemBook:GetItemByName("治疗石")
        if healingStone and not healingStone:IsOnCooldown() then
            healingStone:Use(Player)
            return true
        end
    end
    return false
end)

-- 冰箱
DefensiveAPL:AddSpell(
    IceBlock:CastableIf(function(self)
        return GetKeyState(3)  -- 按下F键时释放
            and not Player:GetAuras():FindMy(IceBlock):IsUp()    -- 没有冰箱buff
    end):SetTarget(Player):PreCast(function(self)
        if Player:IsCastingOrChanneling() then
            SpellStopCasting()  -- 打断当前施法
        end
    end)
)

-- 取消冰箱
DefensiveAPL:AddAction("CancelIceBlock", function()
    if not GetKeyState(3)  -- F键松开时
        and Player:GetAuras():FindMy(IceBlock):IsUp() then   -- 有冰箱buff
        CancelSpellByName("寒冰屏障")
        return true
    end
    return false
end)

-- 法术反制（自动打断）
DefensiveAPL:AddSpell(
    Counterspell:CastableIf(function(self)
        return HERUIInterrupt()  -- 检查打断开关是否开启
            and InterruptTarget:Exists()
            and InterruptTarget:IsAlive()
            and InterruptTarget:IsInterruptibleAt(30)  -- 读条超过30%时打断
            and not self:IsOnCooldown()
    end):SetTarget(InterruptTarget)
)

-- 寒冰护体（没有寒冰护体buff时）
DefensiveAPL:AddSpell(
    IceArmor:CastableIf(function(self)
        return HERUIIceArmor()  -- 检查寒冰护体开关是否开启
            and not self:IsOnCooldown()
            and not Player:GetAuras():FindMy(IceArmor):IsUp()  -- 玩家没有寒冰护体buff
    end):SetTarget(Player)
)

-- ===================== 10. 爆发循环 =====================
-- 狂暴
BurstAPL:AddSpell(
    Berserking:CastableIf(function(self)
        return Target:Exists()
            and not self:IsOnCooldown()
    end):SetTarget(Player)
)

-- 镜像
BurstAPL:AddSpell(
    MirrorImage:CastableIf(function(self)
        return Target:Exists()
            and not self:IsOnCooldown()
    end):SetTarget(Player)
)

-- 冰冷血脉
BurstAPL:AddSpell(
    IcyVeins:CastableIf(function(self)
        return Target:Exists()
            and not self:IsOnCooldown()
    end):SetTarget(Player)
)

-- ===================== 11. AOE循环 =====================
-- 冰枪术
AoeAPL:AddSpell(
    IceLance:CastableIf(function(self)
        return Target:Exists()
            and not self:IsOnCooldown()
            and Player:GetAuras():FindMy(FingersOfFrostBuff):GetCount() == 2  -- 寒冰指buff为2层
    end):SetTarget(Target)
)

-- 霜火箭
AoeAPL:AddSpell(
    Frostfire:CastableIf(function(self)
        return Target:Exists()
            and not self:IsOnCooldown()
            and Player:GetAuras():FindMy(FocusMagicBuff):IsUp() -- 冰冷智慧buff存在
    end):SetTarget(Target)
)

-- 寒冰宝珠
AoeAPL:AddSpell(
    FrozenOrb:CastableIf(function(self)
        return HERUIFrozenOrb()  -- 检查寒冰宝珠开关是否开启
            and Target:Exists()
            and not self:IsOnCooldown()
    end):SetTarget(Target)
)

-- 冰枪术
AoeAPL:AddSpell(
    IceLance:CastableIf(function(self)
        return Target:Exists()
            and not self:IsOnCooldown()
            and Player:GetAuras():FindMy(FingersOfFrostBuff):GetCount() == 1  -- 寒冰指buff为1层
    end):SetTarget(Target)
)

-- 虚空风暴（多目标优先）
AoeAPL:AddSpell(
    VoidTorrent:CastableIf(function(self)
        return self:IsKnown()
            and BestVoidTorrentTarget:Exists()
            and not self:IsOnCooldown()
    end):SetTarget(BestVoidTorrentTarget)
)

-- 活动炸弹（多目标优先）
AoeAPL:AddSpell(
    LivingBomb:CastableIf(function(self)
        return self:IsKnown()
            and BestLivingBombTarget:Exists()
            and not self:IsOnCooldown()
    end):SetTarget(BestLivingBombTarget)
)

-- 寒冰箭
AoeAPL:AddSpell(
    Frostbolt:CastableIf(function(self)
        return Target:Exists() and not self:IsOnCooldown()
    end):SetTarget(Target):PreCast(function(self)
        -- 在施放前检查：如果玩家在移动且没有浮冰buff，先施放浮冰
        if HERUIIcyFloes() 
            and Player:IsMoving() 
            and not Player:GetAuras():FindMy(IcyFloes):IsUp()
            and not IcyFloes:IsOnCooldown() then
            IcyFloes:Cast(Player)
        end
    end)
)

-- ===================== 12. 单体循环 =====================
-- 冰枪术
SingleTargetAPL:AddSpell(
    IceLance:CastableIf(function(self)
        return Target:Exists()
            and not self:IsOnCooldown()
            and Player:GetAuras():FindMy(FingersOfFrostBuff):GetCount() == 2  -- 寒冰指buff为2层
    end):SetTarget(Target)
)

-- 霜火箭
SingleTargetAPL:AddSpell(
    Frostfire:CastableIf(function(self)
        return Target:Exists()
            and not self:IsOnCooldown()
            and Player:GetAuras():FindMy(FocusMagicBuff):IsUp() -- 冰冷智慧buff存在
    end):SetTarget(Target)
)

-- 虚空风暴（单目标）
SingleTargetAPL:AddSpell(
    VoidTorrent:CastableIf(function(self)
        -- 检查目标是否存在且可以使用技能
        if not (self:IsKnown() and Target:Exists() and not self:IsOnCooldown()) then
            return false
        end

        -- 检查目标是否已有debuff
        if Target:GetAuras():FindMy(VoidTorrent):IsUp() then
            return false
        end

        return true
    end):SetTarget(Target)
)

-- 活动炸弹（单目标）
SingleTargetAPL:AddSpell(
    LivingBomb:CastableIf(function(self)
        -- 检查目标是否存在且可以使用技能
        if not (self:IsKnown() and Target:Exists() and not self:IsOnCooldown()) then
            return false
        end

        -- 检查目标是否已有debuff
        if Target:GetAuras():FindMy(LivingBomb):IsUp() then
            return false
        end

        return true
    end):SetTarget(Target)
)

-- 冰枪术
SingleTargetAPL:AddSpell(
    IceLance:CastableIf(function(self)
        return Target:Exists()
            and not self:IsOnCooldown()
            and Player:GetAuras():FindMy(FingersOfFrostBuff):GetCount() == 1  -- 寒冰指buff为1层
    end):SetTarget(Target)
)

-- 寒冰宝珠
SingleTargetAPL:AddSpell(
    FrozenOrb:CastableIf(function(self)
        return HERUIFrozenOrb()  -- 检查寒冰宝珠开关是否开启
            and Target:Exists()
            and not self:IsOnCooldown()
    end):SetTarget(Target)
)

-- 寒冰箭
SingleTargetAPL:AddSpell(
    Frostbolt:CastableIf(function(self)
        return Target:Exists() and not self:IsOnCooldown()
    end):SetTarget(Target):PreCast(function(self)
        -- 在施放前检查：如果玩家在移动且没有浮冰buff，先施放浮冰
        if HERUIIcyFloes() 
            and Player:IsMoving() 
            and not Player:GetAuras():FindMy(IcyFloes):IsUp()
            and not IcyFloes:IsOnCooldown() then
            IcyFloes:Cast(Player)
        end
    end)
)

-- ===================== 13. 简单循环 =====================
-- 冰枪术
SimpleAPL:AddSpell(
    IceLance:CastableIf(function(self)
        return Target:Exists()
            and not self:IsOnCooldown()
            and Player:GetAuras():FindMy(FingersOfFrostBuff):GetCount() == 2  -- 寒冰指buff为2层
    end):SetTarget(Target)
)

-- 霜火箭
SimpleAPL:AddSpell(
    Frostfire:CastableIf(function(self)
        return Target:Exists()
            and not self:IsOnCooldown()
            and Player:GetAuras():FindMy(FocusMagicBuff):IsUp() -- 冰冷智慧buff存在
    end):SetTarget(Target)
)

-- 冰枪术
SimpleAPL:AddSpell(
    IceLance:CastableIf(function(self)
        return Target:Exists()
            and not self:IsOnCooldown()
            and Player:GetAuras():FindMy(FingersOfFrostBuff):GetCount() == 1  -- 寒冰指buff为1层
    end):SetTarget(Target)
)

-- 寒冰箭
SimpleAPL:AddSpell(
    Frostbolt:CastableIf(function(self)
        return Target:Exists() and not self:IsOnCooldown()
    end):SetTarget(Target):PreCast(function(self)
        -- 在施放前检查：如果玩家在移动且没有浮冰buff，先施放浮冰
        if HERUIIcyFloes() 
            and Player:IsMoving() 
            and not Player:GetAuras():FindMy(IcyFloes):IsUp()
            and not IcyFloes:IsOnCooldown() then
            IcyFloes:Cast(Player)
        end
    end)
)
-- ===================== 14. 模块同步 =====================
FrostMage:Sync(function()
    if Player:IsAffectingCombat() then
        CheckAndSetTarget()
    end

    DefensiveAPL:Execute()


    if GetKeyState(58) then
        BurstAPL:Execute()
    end

    if HERUIAOE() then
        AoeAPL:Execute()
    end

    if HERUINormal() then
        SingleTargetAPL:Execute()
    end

    if HERUISimple() then
        SimpleAPL:Execute()
    end
end)

Bastion:Register(FrostMage)


-- ===================== 15. 战斗事件 =====================
Bastion.Globals.EventManager:RegisterWoWEvent('COMBAT_LOG_EVENT_UNFILTERED', function()
    local _, class = UnitClass("player")
    if class ~= "MAGE" then return end
    if IsPlayerSpell(31687) ~= true then return end

    local _, event, _, sourceGUID, _, _, _, destGUID, _, _, _, spellId = CombatLogGetCurrentEventInfo()
    if sourceGUID ~= Player:GetGUID() then return end

    -- 检测虚空风暴施放
    if spellId == 114923 and event == "SPELL_CAST_SUCCESS" then
        if not voidTorrentTimers[destGUID] then
            voidTorrentTimers[destGUID] = Timer:New('voidtorrent')
        else
            voidTorrentTimers[destGUID]:Reset()
        end
        voidTorrentTimers[destGUID]:Start()
    end

    -- 检测活动炸弹施放
    if spellId == 44457 and event == "SPELL_CAST_SUCCESS" then
        if not livingBombTimers[destGUID] then
            livingBombTimers[destGUID] = Timer:New('livingbomb')
        else
            livingBombTimers[destGUID]:Reset()
        end
        livingBombTimers[destGUID]:Start()
    end
end)

