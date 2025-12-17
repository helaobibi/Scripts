local Tinkr, Bastion = ...

-- 创建模块 - 射击猎
local MarksmanHunter = Bastion.Module:New('MarksmanHunter')

-- 获取玩家和目标单位
local Player = Bastion.UnitManager:Get('player')
local Target = Bastion.UnitManager:Get('target')
local Pet = Bastion.UnitManager:Get('pet')
local PetTarget = Bastion.UnitManager:Get('pettarget')
local TargetTarget = Bastion.UnitManager:Get('targettarget')

-- 创建法术书
local SpellBook = Bastion.Globals.SpellBook
-- 创建物品书
local ItemBook = Bastion.Globals.ItemBook
-- 添加新变量来跟踪T键触发的威慑
local isTKeyIntimidationActive = false
-- 定义技能
-- 基础技能
local MendPet = SpellBook:GetSpell(136)                   -- 治疗宠物
local Intimidation = SpellBook:GetSpell(19263)            -- 威慑
local KillShot = SpellBook:GetSpell(53351)                -- 杀戮射击
local AimedShot = SpellBook:GetSpell(19434)               -- 瞄准射击
local MultiShot = SpellBook:GetSpell(2643)               -- 多重射击
local Serpent = SpellBook:GetSpell(1978)                 -- 毒蛇钉刺
local Cower = SpellBook:GetSpell(1742)                    -- 畏缩
local FeignDeath = SpellBook:GetSpell(5384)               -- 假死
local SerpentSting = SpellBook:GetSpell(118253)           -- 毒蛇钉刺debuff
local ArcaneShot = SpellBook:GetSpell(3044)               -- 奥术射击
local Fervor = SpellBook:GetSpell(82726)                  -- 热情
local MurderOfCrows = SpellBook:GetSpell(131894)          -- 夺命黑鸦
local FlyingBlade = SpellBook:GetSpell(117050)            -- 飞刃
local chimerashot = SpellBook:GetSpell(53209)             -- 奇美拉射击
local SteadyShot = SpellBook:GetSpell(56641)              -- 稳固射击
local Fire = SpellBook:GetSpell(82926)                    -- 开火
local CounterShot = SpellBook:GetSpell(147362)            -- 反制射击

-- 奇美拉射击冷却时间（秒）
local CHIMERASHOT_COOLDOWN = 9

-- 获取奇美拉射击真实冷却剩余时间（避免GCD干扰）
local function GetChimerashotRealCooldown()
    local timeSinceLastCast = chimerashot:GetTimeSinceLastCast()
    return math.max(0, CHIMERASHOT_COOLDOWN - timeSinceLastCast)
end

-- 获取瞄准射击的实际施法时间（秒）
local function GetAimedShotCastTime()
    local _, _, _, castTime = GetSpellInfo(19434)
    local hastePercent = GetRangedHaste()
    return (castTime / 1000) / (1 + hastePercent / 100)
end

-- 获取稳固射击的实际施法时间（秒）
local function GetSteadyShotCastTime()
    local _, _, _, castTime = GetSpellInfo(56641)
    local hastePercent = GetRangedHaste()
    return (castTime / 1000) / (1 + hastePercent / 100)
end

-- 获取"真实"能量值（考虑正在施法的技能消耗/回复）
-- 魔兽世界能量结算是法术读条完毕时才扣除/增加，所以读条期间显示的能量是不准确的
local function GetRealFocus()
    local currentFocus = Player:GetPower()
    
    -- 检查玩家是否正在施法或引导
    if Player:IsCastingOrChanneling() then
        local castingSpell = Player:GetCastingOrChannelingSpell()
        
        if castingSpell then
            -- 如果正在读条瞄准射击，预扣除50能量
            -- 因为读条完成后会立即扣除，所以在判断时应该提前计算
            if castingSpell:IsSpell(AimedShot) then
                return currentFocus - 50
            -- 如果正在读条稳固射击，预增加28能量
            -- 因为读条完成后会立即增加能量
            elseif castingSpell:IsSpell(SteadyShot) then
                return currentFocus + 28
            end
        end
    end
    
    return currentFocus
end

-- 计算技能组合后的预期能量值
-- aimedCount: 瞄准射击次数
-- steadyCount: 稳固射击次数
local function CalculateFocusAfterCombo(aimedCount, steadyCount)
    -- 使用真实能量而不是当前显示的能量
    local currentFocus = GetRealFocus()
    local focusCost = aimedCount * 50  -- 瞄准射击消耗50能量
    local focusGain = steadyCount * 28  -- 稳固射击回复28能量
    
    -- 计算施法总时间
    local castTime = GetAimedShotCastTime() * aimedCount + GetSteadyShotCastTime() * steadyCount
    
    -- 获取每秒能量恢复速度
    local focusRegen = GetPowerRegen()
    
    -- 计算施法期间的自然回复
    local naturalRegen = focusRegen * castTime

    
    -- 最终能量 = 真实能量 - 消耗 + 回复 + 自然回复 + 热情加成
    return currentFocus - focusCost + focusGain + naturalRegen
end

-- 寻找最佳目标
local BestTarget = Bastion.UnitManager:CreateCustomUnit('besttarget', function()
    local bestTarget = nil
    local highestHealth = 0

    -- 遍历所有敌人，寻找最适合的目标
    Bastion.ObjectManager.enemies:each(function(unit)
        -- 检查目标是否符合条件：
        -- 1. 正在战斗中
        -- 2. 在奇美拉射击范围内
        -- 3. 玩家可以看见该目标
        -- 4. 目标存在且存活
        -- 5. 玩家面向该目标
        if unit:IsAffectingCombat() and chimerashot:IsInRange(unit)
        and Player:CanSee(unit) and unit:IsAlive() and unit:Exists() and Player:IsFacing(unit) then
            -- 如果没有最佳目标或当前单位血量更高
            if unit:GetHealth() > highestHealth then
                highestHealth = unit:GetHealth()
                bestTarget = unit
            end
        end
    end)

    -- 如果没找到合适目标，返回空目标
    return bestTarget or Bastion.UnitManager:Get('none')
end)

-- 选择目标
local function CheckAndSetTarget()
    if not Target:Exists() or Target:IsFriendly() or not Target:IsAlive() then
        if BestTarget:Exists() then -- 检查返回值有效
            -- 设置最佳目标为当前目标
            TargetUnit(BestTarget.unit)
            return true
        end
    end
    return false
end

-- 寻找可斩杀目标（生命值低于20%）
local ExecuteTarget = Bastion.UnitManager:CreateCustomUnit('executetarget', function()
    -- 先检查当前目标是否满足条件
    if Target:IsAlive() 
        and Target:GetHP() < 20
        and KillShot:IsInRange(Target) then
        return Target
    end

    -- 如果当前目标不满足条件,再查找其他目标
    local executeTarget = Bastion.ObjectManager.enemies:find(function(unit)
        return unit:IsAlive()
            and unit:GetHP() < 20
            and unit:IsAffectingCombat()
            and KillShot:IsInRange(unit)
            and Player:CanSee(unit)
            and Player:IsFacing(unit)
    end)

    return executeTarget or Bastion.UnitManager:Get('none')
end)

-- 寻找可打断目标（正在施法且可打断，且在战斗中）
local InterruptTarget = Bastion.UnitManager:CreateCustomUnit('interrupttarget', function()
    -- 先检查当前目标是否满足条件
    if Target:Exists()
        and Target:IsAlive() 
        and Target:IsAffectingCombat()
        and Target:IsInterruptible()
        and CounterShot:IsInRange(Target) then
        return Target
    end

    -- 如果当前目标不满足条件，查找任意一个可打断的目标
    local interruptTarget = Bastion.ObjectManager.enemies:find(function(unit)
        return unit:IsAlive()
            and unit:IsAffectingCombat()
            and unit:IsInterruptible()
            and CounterShot:IsInRange(unit)
            and Player:CanSee(unit)
            and Player:IsFacing(unit)
    end)

    return interruptTarget or Bastion.UnitManager:Get('none')
end)

-- ===================== APL定义 =====================
local DefaultAPL = Bastion.APL:New('default')         -- 默认输出循环
local DefensiveAPL = Bastion.APL:New('defensive')     -- 防御循环
local AoEAPL = Bastion.APL:New('aoe')                 -- AOE循环
local ResourceAPL = Bastion.APL:New('resource')       -- 资源管理循环
local ResourceAPL2 = Bastion.APL:New('resource2')     -- 资源管理循环2
local PetControlAPL = Bastion.APL:New('petcontrol')   -- 宠物控制
local DefaultSPAPL = Bastion.APL:New('DefaultSP')     -- 简单模式

-- ===================== 防御循环 =====================
-- 治疗石（血量低于50%时自动使用）
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

-- 假死（按F键触发）
DefensiveAPL:AddSpell(
    FeignDeath:CastableIf(function(self)
        return GetKeyState(70) > 30000  -- 按下F键时释放
            and not Player:GetAuras():FindMy(FeignDeath):IsUp()  -- 没有假死buff
    end):SetTarget(Player):PreCast(function(self)
        if Player:IsCastingOrChanneling() then
            SpellStopCasting()  -- 打断当前施法
        end
    end)
)

-- 威慑（自动防御：血量低于30%时自动使用）
DefensiveAPL:AddSpell(
    Intimidation:CastableIf(function(self)
        return HERUIIntimidation() and  -- 检查威慑开关
               Player:GetHP() <= 30 and
               not self:IsOnCooldown() and
               Player:IsAffectingCombat() and
               not (GetKeyState(84) > 30000) -- 不在按T键时才使用自动防御逻辑
    end):SetTarget(Player):PreCast(function(self)
        if Player:IsCastingOrChanneling() then
            SpellStopCasting()
        end
    end)
)

-- 威慑（按T键触发）
DefensiveAPL:AddSpell(
    Intimidation:CastableIf(function(self)
        return HERUIIntimidation() and  -- 检查威慑开关
               GetKeyState(84) > 30000 and -- 按下T键时释放
               not Player:GetAuras():FindMy(Intimidation):IsUp() -- 没有威慑buff
    end):SetTarget(Player):PreCast(function(self)
        if Player:IsCastingOrChanneling() then
            SpellStopCasting() -- 打断当前施法
        end
    end):OnCast(function(self)
        -- 标记这是T键触发的威慑
        isTKeyIntimidationActive = true
    end)
)

-- 取消威慑（智能判断）
DefensiveAPL:AddAction("CancelTKeyIntimidation", function()
    if isTKeyIntimidationActive then
        -- T键触发的威慑：松开T键时立即取消
        if not (GetKeyState(84) > 30000) and Player:GetAuras():FindMy(Intimidation):IsUp() then
            CancelSpellByName("威慑")
            isTKeyIntimidationActive = false
            return true
        end
    else
        -- 自动触发的威慑：血量大于等于80%时取消
        if not (GetKeyState(84) > 30000) and Player:GetHP() >= 80 and Player:GetAuras():FindMy(Intimidation):IsUp() then
            CancelSpellByName("威慑")
            return true
        end
    end
    return false
end)

-- ===================== 资源管理循环 =====================
-- 反制射击（自动打断）
ResourceAPL:AddSpell(
    CounterShot:CastableIf(function(self)
        return HERUIInterrupt()  -- 检查打断开关是否开启
            and InterruptTarget:Exists()
            and InterruptTarget:IsAlive()
            and InterruptTarget:IsInterruptibleAt(30)  -- 读条超过30%时打断
            and not self:IsOnCooldown()
    end):SetTarget(InterruptTarget)
)

-- 热情（能量不足45时使用，恢复能量）
ResourceAPL:AddSpell(
    Fervor:CastableIf(function(self)
        return Player:IsAffectingCombat()
            and not self:IsOnCooldown()
            and GetRealFocus() < 35
    end):SetTarget(Player)
)
-- ===================== 宠物控制 =====================
-- 畏缩（宠物血量低于80%时使用，降低仇恨）
PetControlAPL:AddSpell(
    Cower:CastableIf(function(self)
        return Pet:Exists()
            and Pet:IsAlive()
            and Player:IsAffectingCombat()
            and not self:IsOnCooldown()
            and Pet:GetHP() <= 80
    end):SetTarget(Pet)
)

-- 宠物攻击（让宠物攻击玩家的目标）
PetControlAPL:AddAction("PetAttack", function()
    if Pet:Exists() and Pet:IsAlive()
        and Target:Exists()
        and Target:IsAlive()
        and HERUIPetAttack()
        and (not PetTarget:Exists() or not PetTarget:IsUnit(Target)) then
        PetAttack()
        return true
    end
    return false
end)

-- 宠物跟随（宠物有目标时让其跟随）
PetControlAPL:AddAction("PetFollow", function()
    if Pet:Exists() and Pet:IsAlive()
        and PetTarget:Exists()
        and HERUIPetFollow() then
        PetFollow()
        return true
    end
    return false
end)

-- 治疗宠物（血量低于75%时使用）
PetControlAPL:AddSpell(
    MendPet:CastableIf(function(self)
        return Pet:Exists()
            and Pet:IsAlive()
            and Pet:GetHP() < 75
            and Player:IsAffectingCombat()
            and not Pet:GetAuras():FindAny(MendPet):IsUp()
            and not Player:IsChanneling()
    end):SetTarget(Pet)
)

-- ===================== AOE循环 =====================
-- 斩杀射击（对低于20%血量的目标使用）
AoEAPL:AddSpell(
    KillShot:CastableIf(function(self)
        return ExecuteTarget:Exists()
            and ExecuteTarget:IsAlive()
            and Player:IsAffectingCombat()
            and not self:IsOnCooldown()
    end):SetTarget(ExecuteTarget)
)

-- 瞄准射击（AOE模式仅在Fire BUFF时使用）
AoEAPL:AddSpell(
    AimedShot:CastableIf(function(self)
        return BestTarget:Exists()
            and BestTarget:IsAlive()
            and not self:IsOnCooldown()
            and Player:GetAuras():FindAny(Fire):IsUp()
    end):SetTarget(BestTarget)
)

-- 多重射击（AOE主要技能）
AoEAPL:AddSpell(
    MultiShot:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and not self:IsOnCooldown()
    end):SetTarget(Target)
)

-- 稳固射击（AOE填充技能，能量不足40时使用）
AoEAPL:AddSpell(
    SteadyShot:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and not self:IsOnCooldown()
            and CalculateFocusAfterCombo(0, 1) < 105
            and GetRealFocus() < 40
            and not (Fervor:GetCooldownRemaining() < 1 and GetRealFocus() < 35)  -- 热情冷却时间小于1且能量小于35时不释放
    end):SetTarget(Target)
)
-- ===================== 默认循环 =====================
-- 奇美拉射击（最高优先级，高伤害主要技能）
DefaultAPL:AddSpell(
    chimerashot:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and not self:IsOnCooldown()
    end):SetTarget(Target)
)

-- 斩杀射击（对低于20%血量的目标使用）
DefaultAPL:AddSpell(
    KillShot:CastableIf(function(self)
        return ExecuteTarget:Exists()
            and ExecuteTarget:IsAlive()
            and Player:IsAffectingCombat()
            and not self:IsOnCooldown()
    end):SetTarget(ExecuteTarget)
)

-- 毒蛇钉刺（目标没有毒蛇钉刺debuff时使用）
DefaultAPL:AddSpell(
    Serpent:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and not self:IsOnCooldown()
            and not Target:GetAuras():FindMy(SerpentSting):IsUp()
    end):SetTarget(Target)
)

-- 夺命黑鸦（高伤害技能，CD好了就用）
DefaultAPL:AddSpell(
    MurderOfCrows:CastableIf(function(self)
        return self:IsKnown()
            and Target:Exists()
            and Target:IsAlive()
            and not self:IsOnCooldown()
            and GetRealFocus() > 60
    end):SetTarget(Target)
)

-- 瞄准射击（智能能量管理）
DefaultAPL:AddSpell(
    AimedShot:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and not self:IsOnCooldown()
            and (
                -- 优先级1: 有Fire buff时使用，适合爆发
                (GetChimerashotRealCooldown() > 0.5 and Player:GetAuras():FindAny(Fire):IsUp())
                -- 优先级4: 一个瞄准+两个稳固，确保奇美拉CD后有45能量（0.5秒容错）
                or (GetChimerashotRealCooldown() >= (GetAimedShotCastTime() + GetSteadyShotCastTime() * 2 - 1)
                    and (not MurderOfCrows:IsKnown() or MurderOfCrows:GetCooldownRemaining() > 1)
                    and CalculateFocusAfterCombo(1, 2) >= 45
                )
                -- 优先级3: 一个瞄准+一个稳固，确保奇美拉CD后有45能量（0.5秒容错）
                or (GetChimerashotRealCooldown() >= (GetAimedShotCastTime() + GetSteadyShotCastTime() - 1)
                    and (not MurderOfCrows:IsKnown() or MurderOfCrows:GetCooldownRemaining() > 1)
                    and CalculateFocusAfterCombo(1, 1) >= 45
                )
                -- 优先级2: 单独打一个瞄准射击，确保奇美拉CD后有45能量（0.5秒容错）
                or (GetChimerashotRealCooldown() >= (GetAimedShotCastTime() - 1)
                    and (not MurderOfCrows:IsKnown() or MurderOfCrows:GetCooldownRemaining() > 1)
                    and CalculateFocusAfterCombo(1, 0) >= 45
                )
            )
    end):SetTarget(Target)
)

-- 稳固射击（基础填充技能）
DefaultAPL:AddSpell(
    SteadyShot:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and not self:IsOnCooldown()
            and CalculateFocusAfterCombo(0, 1) < 105
            and not (Fervor:GetCooldownRemaining() < 1 and GetRealFocus() < 35)  -- 热情冷却时间小于1且能量小于35时不释放
            and (
                -- 条件1: 所有主要CD都在冷却中且能量大于40
                    (GetChimerashotRealCooldown() > 0.8
                    and (not MurderOfCrows:IsKnown() or MurderOfCrows:GetCooldownRemaining() > 0.8)
                    and GetRealFocus() > 40)
                -- 条件2: 能量不足40
                or GetRealFocus() < 40
                -- 条件3: 夺命黑鸦冷却小于1秒，能量不足58
                or (MurderOfCrows:IsKnown() and MurderOfCrows:GetCooldownRemaining() < 0.8 and GetRealFocus() < 57)
            )
    end):SetTarget(Target)
)

-- ===================== 简单模式 =====================
-- 奇美拉射击（最高优先级，高伤害主要技能）
DefaultSPAPL:AddSpell(
    chimerashot:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and not self:IsOnCooldown()
    end):SetTarget(Target)
)

-- 斩杀射击（对低于20%血量的目标使用）
DefaultSPAPL:AddSpell(
    KillShot:CastableIf(function(self)
        return ExecuteTarget:Exists()
            and ExecuteTarget:IsAlive()
            and KillShot:IsInRange(ExecuteTarget)
            and Player:IsAffectingCombat()
            and not self:IsOnCooldown()
    end):SetTarget(ExecuteTarget)
)

-- 瞄准射击（智能能量管理，简化版）
DefaultSPAPL:AddSpell(
    AimedShot:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and not self:IsOnCooldown()
            and (
                -- 优先级1: 有Fire buff时使用，适合爆发
                (GetChimerashotRealCooldown() > 0.5 and Player:GetAuras():FindAny(Fire):IsUp())
                -- 优先级4: 一个瞄准+两个稳固，确保奇美拉CD后有45能量（0.5秒容错）
                or (GetChimerashotRealCooldown() >= (GetAimedShotCastTime() + GetSteadyShotCastTime() * 2 - 1)
                    and CalculateFocusAfterCombo(1, 2) >= 45
                )
                -- 优先级3: 一个瞄准+一个稳固，确保奇美拉CD后有45能量（0.5秒容错）
                or (GetChimerashotRealCooldown() >= (GetAimedShotCastTime() + GetSteadyShotCastTime() - 1)
                    and CalculateFocusAfterCombo(1, 1) >= 45
                )
                -- 优先级2: 单独打一个瞄准射击，确保奇美拉CD后有45能量（0.5秒容错）
                or (GetChimerashotRealCooldown() >= (GetAimedShotCastTime() - 1)
                    and CalculateFocusAfterCombo(1, 0) >= 45
                )
            )
    end):SetTarget(Target)
)

-- 稳固射击（基础填充技能）
DefaultSPAPL:AddSpell(
    SteadyShot:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and not self:IsOnCooldown()
            and CalculateFocusAfterCombo(0, 1) < 105
            and not (Fervor:GetCooldownRemaining() < 1 and GetRealFocus() < 35)  -- 热情冷却时间小于1且能量小于35时不释放
            and (
                -- 条件1: 所有主要CD都在冷却中且能量大于40
                    (GetChimerashotRealCooldown() > 0.8
                    and GetRealFocus() > 40)
                -- 条件2: 能量不足40
                or GetRealFocus() < 40
            )
    end):SetTarget(Target)
)

-- ===================== 模块同步 =====================
MarksmanHunter:Sync(function()
    -- 检查威慑状态，如果没有威慑buff则重置T键触发标记
    if isTKeyIntimidationActive and not Player:GetAuras():FindMy(Intimidation):IsUp() then
        isTKeyIntimidationActive = false
    end
    
    -- 优先级1：防御、资源管理和宠物控制
    DefensiveAPL:Execute()
    ResourceAPL:Execute()
    PetControlAPL:Execute()

    -- 如果按住F键（假死）或T键（威慑），则不执行输出循环
    if GetKeyState(84) > 30000 or GetKeyState(70) > 30000 then
        return
    end

    -- 战斗中自动切换目标
    if Player:IsAffectingCombat() then
        CheckAndSetTarget()
    end
    
    -- 优先级2：根据模式执行对应的输出循环
    if HERUIAOE() then
        AoEAPL:Execute()  -- AOE模式
    end
    if HERUINormal() then
        DefaultAPL:Execute()  -- 默认模式
    end
    if HERUISimple() then
        DefaultSPAPL:Execute()  -- 简单模式
    end
end)
-- ===================== 注册模块 =====================
Bastion:Register(MarksmanHunter)
