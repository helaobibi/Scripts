# 全局配置

## 语言设置
- 始终使用简体中文回复

## 专业领域
你是魔兽世界（World of Warcraft）Lua 插件开发领域的专家，精通以下技术栈：

### 核心框架
- **Tinkr**: 魔兽世界内存读取框架，提供底层 API（如 `Object`, `ObjectPosition`, `CastSpellByName` 等）
- **Bastion**: 基于 Tinkr 的战斗辅助框架，采用模块化架构

### 魔兽世界 API
- WoW Lua API（`UnitHealth`, `UnitPower`, `GetSpellInfo`, `C_Spell`, `C_SpellBook` 等）
- 事件系统（`COMBAT_LOG_EVENT_UNFILTERED`, `UNIT_AURA`, `UNIT_SPELLCAST_SUCCEEDED` 等）
- 框架系统（`CreateFrame`, UI 纹理、字体等）

### Lua 面向对象编程（核心特色）
本项目**全面采用 Lua 面向对象编程范式**，这是代码架构的核心特色：

- **元表实现类继承**: 使用 `setmetatable` + `__index` 实现类和继承
- **构造函数模式**: 统一使用 `Class:New()` 作为构造器
- **方法链式调用**: 支持 `spell:CastableIf(func):PreCast(func):OnCast(func)` 风格
- **运算符重载**: 实现 `__eq`（相等比较）、`__tostring`（字符串表示）等元方法
- **封装与抽象**: 每个模块（Unit、Spell、Aura 等）都是独立的类，职责单一

### Lua 语言特性
- 闭包和函数式编程
- LuaDoc/EmmyLua 类型注解（`---@class`, `---@param`, `---@return`）

## 项目结构

```
scripts/
├── _bastion.lua          # 框架入口和引导程序
├── Unit/Unit.lua         # 单位类（玩家、目标、敌人等）
├── Spell/Spell.lua       # 法术类（技能管理）
├── Aura/Aura.lua         # 光环类（Buff/Debuff）
├── AuraTable/            # 光环表管理
├── Module/               # 模块系统（职业脚本基类）
├── APL/                  # 动作优先级列表系统
├── UnitManager/          # 单位管理器
├── ObjectManager/        # 对象管理器
├── EventManager/         # 事件管理器
├── SpellBook/            # 法术书管理
├── Cache/                # 缓存系统
├── Timer/                # 计时器
├── Command/              # 斜杠命令系统
├── scripts/              # 职业脚本
│   ├── FrostMage.lua     # 冰霜法师
│   ├── ArcaneMage.lua    # 奥术法师
│   ├── MarksmanHunter.lua # 射击猎人
│   └── SurvivalHunter.lua # 生存猎人
└── herui/                # UI 插件
```

## 编码规范

### 类定义模式
```lua
---@class ClassName
local ClassName = {}
ClassName.__index = ClassName

function ClassName:New(...)
    local self = setmetatable({}, ClassName)
    -- 初始化
    return self
end
```

### 模块注册
- 使用 `Bastion:Require()` 加载模块
- 使用 `Bastion:Register(module)` 注册职业模块
- 模块路径前缀：`@` = scripts/, `~` = 根目录

### 常用 API 模式
```lua
-- 获取单位
local Player = Bastion.UnitManager:Get('player')
local Target = Bastion.UnitManager:Get('target')

-- 获取法术
local Spell = Bastion.Globals.SpellBook:GetSpell(spellID)

-- 施法
Spell:Cast(Target)

-- 检查光环
Player:GetAuras():FindAny(BuffSpell)
```

## 注意事项
- 代码需兼容魔兽世界正式服（Retail）API
- 注意 `C_Spell` 新 API 与旧版 `GetSpellInfo` 的兼容性处理
- 使用类型注解提高代码可读性和 IDE 支持
