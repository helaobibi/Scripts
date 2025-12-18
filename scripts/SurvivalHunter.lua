local Tinkr, Bastion = ...

-- 创建模块 - 生存猎
local SurvivalHunter = Bastion.Module:New('SurvivalHunter')

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
local ConcussiveShot = SpellBook:GetSpell(5116)           -- 震荡射击
local kuishe = SpellBook:GetSpell(34074)                  -- 蝰蛇守护
local longying = SpellBook:GetSpell(61847)                -- 龙鹰守护
local KillShot = SpellBook:GetSpell(53351)                -- 杀戮射击
local SteadyShot = SpellBook:GetSpell(77767)              -- 稳固射击
local KillCommand = SpellBook:GetSpell(34026)             -- 杀戮命令
local BlackArrow = SpellBook:GetSpell(3674)               -- 黑箭
local AimedShot = SpellBook:GetSpell(49050)               -- 瞄准射击
local MultiShot = SpellBook:GetSpell(2643)                -- 多重射击
local Serpent = SpellBook:GetSpell(1978)                  -- 毒蛇钉刺
local HuntersMark = SpellBook:GetSpell(53338)             -- 猎人印记
local heqiang = SpellBook:GetSpell(56453)                 -- 荷枪实弹
local Cower = SpellBook:GetSpell(1742)                    -- 畏缩
local FeignDeath = SpellBook:GetSpell(5384)               -- 假死
local SerpentSting = SpellBook:GetSpell(118253)           -- 毒蛇钉刺debuff
local ArcaneShot = SpellBook:GetSpell(3044)               -- 奥术射击
local FerociousBeast = SpellBook:GetSpell(120679)         -- 凶猛野兽
local Coercion = SpellBook:GetSpell(19577)                -- 胁迫
local ExplosiveShot = SpellBook:GetSpell(53301)           -- 爆炸射击
local Fervor = SpellBook:GetSpell(82726)                  -- 热情
local MurderOfCrows = SpellBook:GetSpell(131894)          -- 夺命黑鸦
local bsxianjing = SpellBook:GetSpell(82941)              -- 冰霜陷阱
local CounterShot = SpellBook:GetSpell(147362)            -- 反制射击

-- 爆炸射击冷却时间（秒）
local EXPLOSIVESHOT_COOLDOWN = 6
-- 黑箭冷却时间（秒）
local BLACKARROW_COOLDOWN = 24

-- 获取爆炸射击真实冷却剩余时间（避免GCD干扰）
local function GetExplosiveShotRealCooldown()
    local timeSinceLastCast = ExplosiveShot:GetTimeSinceLastCast()
    return math.max(0, EXPLOSIVESHOT_COOLDOWN - timeSinceLastCast)
end

-- 获取黑箭真实冷却剩余时间（避免GCD干扰）
local function GetBlackArrowRealCooldown()
    local timeSinceLastCast = BlackArrow:GetTimeSinceLastCast()
    return math.max(0, BLACKARROW_COOLDOWN - timeSinceLastCast)
end

-- 获取"真实"能量值（考虑正在施法的技能消耗/回复）
-- 魔兽世界能量结算是法术读条完毕时才扣除/增加，所以读条期间显示的能量是不准确的
local function GetRealFocus()
    local currentFocus = Player:GetPower()
    
    -- 检查玩家是否正在施法或引导
    if Player:IsCastingOrChanneling() then
        local castingSpell = Player:GetCastingOrChannelingSpell()
        
        if castingSpell then
            -- 如果正在读条稳固射击，预增加28能量
            if castingSpell:IsSpell(SteadyShot) then
                return currentFocus + 28
            end
        end
    end
    
    return currentFocus
end

-- 寻找最佳目标
local BestTarget = Bastion.UnitManager:CreateCustomUnit('besttarget', function()
    local bestTarget = nil
    local highestHealth = 0

    -- 遍历所有敌人，寻找最适合的目标
    Bastion.ObjectManager.enemies:each(function(unit)
        -- 检查目标是否符合条件：
        -- 1. 正在战斗中
        -- 2. 在35码范围内
        -- 3. 玩家可以看见该目标
        -- 4. 目标距离玩家至少5码
        -- 5. 玩家面向该目标
        if unit:IsAffectingCombat() and ExplosiveShot:IsInRange(unit)
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
        local unitName = unit:GetName()
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

-- 假死
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

-- 威慑（原有逻辑）
DefensiveAPL:AddSpell(
    Intimidation:CastableIf(function(self)
        return HERUIIntimidation() and  -- 检查威慑开关
               Player:GetHP() <= 30 and
               not self:IsOnCooldown() and
               Player:IsAffectingCombat() and
               not (GetKeyState(84) > 30000) -- 不在按T键时才使用原有逻辑
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

-- 取消威慑（松开T键时）
DefensiveAPL:AddAction("CancelTKeyIntimidation", function()
    if isTKeyIntimidationActive then
        -- T键触发的威慑，按原有逻辑处理
        if not (GetKeyState(84) > 30000) and Player:GetAuras():FindMy(Intimidation):IsUp() then
            CancelSpellByName("威慑")
            isTKeyIntimidationActive = false
            return true
        end
    else
        -- 非T键触发的威慑，血量大于等于80%时取消
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

-- 热情
ResourceAPL:AddSpell(
    Fervor:CastableIf(function(self)
        return Player:IsAffectingCombat()
            and not self:IsOnCooldown()
            and GetRealFocus() < 35
    end):SetTarget(Player)
)

-- 陷阱
ResourceAPL:AddSpell(
    bsxianjing:CastableIf(function(self)
        return Target:Exists()
            and GetKeyState(164) > 30000
            and not Player:IsChanneling()
            and Target:IsAlive()
            and Target:IsEnemy()
            and not self:IsOnCooldown()
    end):SetTarget(Target):PreCast(function(self)
        -- 检查是否正在读条稳固射击，如果是则停止施法
        if Player:IsCastingOrChanneling() then
            SpellStopCasting()
        end
    end):OnCast(function(self)
        -- 使用GetEnemyClosestToCentroid函数找到最密集敌人群中最接近质心的敌人
        -- 参数：半径10码，范围40码，最少需要3个敌人才使用质心定位
        local centralEnemy = Bastion.UnitManager:GetEnemyClosestToCentroid(10, 40, 3)
        local position

        if centralEnemy then
            position = centralEnemy:GetPosition()
        else
            -- 如果没有找到足够密集的敌人群（少于3个敌人），退回到目标位置
            position = Target:GetPosition()
        end

        self:Click(position)
    end)
)

-- 胁迫
ResourceAPL:AddSpell(
    Coercion:CastableIf(function(self)
        return Pet:Exists()
            and GetKeyState(164) > 30000
            and Pet:IsAlive()
            and Player:IsAffectingCombat()
            and not self:IsOnCooldown()
    end):SetTarget(Target)
)

-- 震荡射击
ResourceAPL:AddSpell(
    ConcussiveShot:CastableIf(function(self)
        return Target:Exists()
            and GetKeyState(164) > 30000
            and Target:IsAlive()
            and not self:IsOnCooldown()
    end):SetTarget(Target)
)

-- ===================== 防御循环 =====================
-- 畏缩
PetControlAPL:AddSpell(
    Cower:CastableIf(function(self)
        return Pet:Exists()
            and Pet:IsAlive()
            and Player:IsAffectingCombat()
            and not self:IsOnCooldown()
            and Pet:GetHP() <= 80
    end):SetTarget(Pet)
)

-- 宠物攻击
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

-- 宠物跟随
PetControlAPL:AddAction("PetFollow", function()
    if Pet:Exists() and Pet:IsAlive()
        and PetTarget:Exists()
        and HERUIPetFollow() then
        PetFollow()
        return true
    end
    return false
end)

-- 治疗宠物
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
-- 斩杀射击（斩杀阶段使用）
AoEAPL:AddSpell(
    KillShot:CastableIf(function(self)
        return ExecuteTarget:Exists()
            and ExecuteTarget:IsAlive()
            and Player:IsAffectingCombat()
            and not self:IsOnCooldown()
    end):SetTarget(ExecuteTarget)
)

-- 多重射击（AOE主要技能）
AoEAPL:AddSpell(
    MultiShot:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and not self:IsOnCooldown()
    end):SetTarget(Target)
)

-- 稳固射击（AOE填充技能）
AoEAPL:AddSpell(
    SteadyShot:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and not self:IsOnCooldown()
            and GetRealFocus() <= 95  -- 能量大于95时不打稳固射击
            and GetRealFocus() < 40
    end):SetTarget(Target)
)
-- ===================== 默认循环 =====================
-- 斩杀射击（斩杀阶段使用）
DefaultAPL:AddSpell(
    KillShot:CastableIf(function(self)
        return ExecuteTarget:Exists()
            and ExecuteTarget:IsAlive()
            and KillShot:IsInRange(ExecuteTarget)
            and Player:IsAffectingCombat()
            and not self:IsOnCooldown()
    end):SetTarget(ExecuteTarget)
)

-- 奥术射击（荷枪实弹buff时高优先级使用）
DefaultAPL:AddSpell(
    ArcaneShot:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and not self:IsOnCooldown()
            and Player:GetAuras():FindAny(heqiang):IsUp()
            and GetRealFocus() > 90
    end):SetTarget(Target)
)

-- 爆炸射击（最高优先级输出技能）
DefaultAPL:AddSpell(
    ExplosiveShot:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and not self:IsOnCooldown()
    end):SetTarget(Target)
)

-- 黑箭（在爆炸射击冷却时使用）
DefaultAPL:AddSpell(
    BlackArrow:CastableIf(function(self)
        return Target:Exists()
		    and Target:IsAlive()
            and not self:IsOnCooldown()
            and GetExplosiveShotRealCooldown() > 0.5
    end):SetTarget(Target)
)

-- 毒蛇钉刺
DefaultAPL:AddSpell(
    Serpent:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and not self:IsOnCooldown()
            and not Target:GetAuras():FindMy(SerpentSting):IsUp()
    end):SetTarget(Target)
)

-- 夺命黑鸦
DefaultAPL:AddSpell(
    MurderOfCrows:CastableIf(function(self)
        return self:IsKnown()
            and Target:Exists()
            and Target:IsAlive()
            and not self:IsOnCooldown()
            and ExplosiveShot:GetCooldownRemaining() > 0.5
    end):SetTarget(Target)
)

-- 奥术射击（能量倾泻，当主技能都在CD时使用）
DefaultAPL:AddSpell(
    ArcaneShot:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and not self:IsOnCooldown()
            and (not MurderOfCrows:IsKnown() or MurderOfCrows:GetCooldownRemaining() > 1)
            and GetExplosiveShotRealCooldown() > 0.5
            and GetBlackArrowRealCooldown() > 0.5
            and GetRealFocus() > 50
    end):SetTarget(Target)
)

-- 稳固射击（基础填充技能，能量回复）
DefaultAPL:AddSpell(
    SteadyShot:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and not self:IsOnCooldown()
            and not (Fervor:GetCooldownRemaining() < 1 and GetRealFocus() < 35)  -- 热情冷却时间小于1且能量小于35时不释放
            and GetRealFocus() <= 95  -- 能量大于95时不打稳固射击
            and (
                -- 条件1: 所有主要CD都在冷却中且能量大于40
                (GetExplosiveShotRealCooldown() > 0.5
                    and GetBlackArrowRealCooldown() > 0.5
                    and (not MurderOfCrows:IsKnown() or MurderOfCrows:GetCooldownRemaining() > 1))
                -- 条件2: 能量不足25
                or GetRealFocus() < 22
                -- 条件3: 能量<35且黑箭即将转好，爆炸射击还在CD
                or (GetRealFocus() < 32
                    and GetBlackArrowRealCooldown() < 0.5
                    and GetExplosiveShotRealCooldown() > 0.5)
                -- 条件4: 夺命黑鸦冷却<1秒且能量<58
                or (MurderOfCrows:IsKnown()
                    and MurderOfCrows:GetCooldownRemaining() < 1
                    and GetRealFocus() < 58)
            )
    end):SetTarget(Target)
)

-- ===================== 简单模式 =====================
-- 斩杀射击（斩杀阶段使用）
DefaultSPAPL:AddSpell(
    KillShot:CastableIf(function(self)
        return ExecuteTarget:Exists()
            and ExecuteTarget:IsAlive()
            and KillShot:IsInRange(ExecuteTarget)
            and Player:IsAffectingCombat()
            and not self:IsOnCooldown()
    end):SetTarget(ExecuteTarget)
)

-- 奥术射击（荷枪实弹buff时高优先级使用）
DefaultSPAPL:AddSpell(
    ArcaneShot:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and not self:IsOnCooldown()
            and Player:GetAuras():FindAny(heqiang):IsUp()
            and GetRealFocus() > 90
    end):SetTarget(Target)
)

-- 爆炸射击（最高优先级输出技能）
DefaultSPAPL:AddSpell(
    ExplosiveShot:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and not self:IsOnCooldown()
    end):SetTarget(Target)
)

-- 奥术射击（能量倾泻，当主技能在CD时使用）
DefaultSPAPL:AddSpell(
    ArcaneShot:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and not self:IsOnCooldown()
            and GetExplosiveShotRealCooldown() > 0.5
            and GetRealFocus() > 50
    end):SetTarget(Target)
)

-- 稳固射击（基础填充技能，能量回复）
DefaultSPAPL:AddSpell(
    SteadyShot:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and not self:IsOnCooldown()
            and not (Fervor:GetCooldownRemaining() < 1 and GetRealFocus() < 35)  -- 热情冷却时间小于1且能量小于35时不释放
            and GetRealFocus() <= 95  -- 能量大于95时不打稳固射击
            and (
                -- 条件1: 主要CD都在冷却中且能量大于40
                GetExplosiveShotRealCooldown() > 0.5
                -- 条件2: 能量不足25
                or GetRealFocus() < 22
            )
    end):SetTarget(Target)
)

-- ===================== 模块同步 =====================
SurvivalHunter:Sync(function()
    -- 检查威慑状态，如果没有威慑buff则重置T键状态
    if isTKeyIntimidationActive and not Player:GetAuras():FindMy(Intimidation):IsUp() then
        isTKeyIntimidationActive = false
    end
    -- 最高优先级：防御和资源管理
    DefensiveAPL:Execute()
    ResourceAPL:Execute()
    PetControlAPL:Execute()

    -- 如果按住F键（假死状态）或T键（威慑状态），则不执行其他循环
    if GetKeyState(84) > 30000 or GetKeyState(70) > 30000 then
        return
    end

    -- 战斗中切目标
    if Player:IsAffectingCombat() and HERUISwitchTarget() then
        CheckAndSetTarget()
    end
    if HERUIAOE() then
        AoEAPL:Execute()
    end
    if HERUINormal() then
        DefaultAPL:Execute()
    end
    if HERUISimple() then
        DefaultSPAPL:Execute()
    end
end)
-- ===================== 注册模块 =====================
Bastion:Register(SurvivalHunter)
