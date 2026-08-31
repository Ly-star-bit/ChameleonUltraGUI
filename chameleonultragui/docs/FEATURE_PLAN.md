# 增强功能实施计划 (Feature Enhancement Plan)

围绕"自动化/无感操作、视觉认知、新手容错、硬件交互"四大方向的增强功能实施路线图。
按投入产出与依赖关系分四期,每期交付可运行增量。

## 贯穿全局的两个硬约束
1. **加密 Mifare Classic 需先有密钥** —— 限制"一键克隆"的通用性,加密卡需降级为"先解密"流程。
2. **BLE 后台连接稳定性** —— 限制所有"无感/微件/常驻"功能;蓝牙一断则无法下发指令。

---

## 统一架构决策 (让多个功能共享同一套代码)

### A. 自动化规则引擎 (Automation Rules)
把"位置切卡 (GPS)"和"定时切卡 (Time)"统一成一套**触发器 → 动作**模型,而不是各写各的。
- 新模型 `AutomationRule { id, name, enabled, trigger, slot }`
- `trigger` 为 sealed 类型:`LocationTrigger(lat,lng,radius)` / `TimeTrigger(startMinutes,endMinutes,weekdays)`
- 已有的 `LocationSlot` 迁移为 `AutomationRule` 的一种触发器(保留旧数据读取兼容)。
- `LocationSlotMonitor` 升级为 `AutomationEngine`:同时监听 GPS 流 + 一个周期性时间检查(Timer),命中规则即 `activateSlot`。
- 前台服务/后台保活复用三阶段已实现的机制。

### B. 卡片模型扩展 (CardSave)
现有 `CardSave` 已有 `color` / `folderId`。新增(全部向后兼容,`fromJson` 给默认值):
- `skinId` (String?) —— 预设卡皮
- `imagePath` (String?) —— 用户上传卡面图
- `pinned` (bool) —— 置顶
- `tags` (List<String>) —— 多标签

### C. 回收站数据层 (Recycle Bin)
- 删除不物理删除,移入 `deleted_cards`(带 `deletedAt` 时间戳)。
- 启动时清理超过 30 天的条目。
- 覆盖已有槽位数据时弹高亮警告。

### D. 触觉与反馈层
- 新建 `helpers/feedback.dart`:封装 `HapticFeedback` + 可选 `vibration` 插件的不同节奏。
- 在连接成功/读卡成功/切槽/错误等关键事件调用。

---

## 第一期 —— 快速见效 (纯前端 / 复用现有代码)

| # | 功能 | 关键文件 | 复用 |
|---|---|---|---|
| 1 | **触觉反馈** | `helpers/feedback.dart`(新) | `HapticFeedback`(已 import) |
| 2 | **天线对准图形引导** | `gui/component/antenna_guide.dart`(新)→ 嵌入 `read_card.dart` | 纯 UI |
| 3 | **定时切卡** | 升级 `location_slot.dart`→`automation.dart`,UI 复用 `location_slots.dart` | 三阶段的前台服务 |
| 4 | **卡片置顶 + 标签** | `sharedprefsprovider.dart`(CardSave 扩展)、`saved_cards.dart` | 已有文件夹系统 `CardFolder` |

## 第二期 —— 中等 (数据 + 交互)

| # | 功能 | 关键文件 | 复用 |
|---|---|---|---|
| 5 | **卡皮/自定义卡面/拍照上传** | CardSave 扩展、`saved_cards.dart`、卡皮资源 | `file_picker`(已有) |
| 6 | **回收站 (30天恢复) + 覆盖警告** | `sharedprefsprovider.dart`、新回收站页 | `getConfirmDelete()` |
| 7 | **智能克隆按钮 (Smart Copy)** | `gui/page/read_card.dart`、复用 `slot_manager.dart` 的 `onTap` 写入链路 | 读卡+写槽逻辑已存在 |
| 8 | **智能排错诊断助手** | `gui/component/troubleshooter.dart`(新) | 连接/权限/DFU 状态已知 |

## 第三期 —— 重活 (原生代码,受 BLE 后台约束)

| # | 功能 | 关键文件 | 风险 |
|---|---|---|---|
| 9 | **Android 通知栏快捷切卡** | 扩展三阶段前台通知加 action | 中,复用现有服务 |
| 10 | **Android 桌面微件** | 原生 Kotlin + `home_widget` 插件 | 高,BLE 后台约束 |
| 11 | **桌面托盘图标** | `tray_manager`/`system_tray` 插件 | 中 |
| 12 | **iOS 锁屏组件/灵动岛** | 原生 Swift WidgetKit/`live_activities` | 最高,App Store 审核 |

---

## 交付顺序
第一期(1→2→3→4)→ 第二期(5→6→7→8)→ 第三期(9→11→10→12)。
每完成一个功能:补中英文 arb 文案、更新本文件勾选进度。

## 已知限制 / 待验证
- 本仓库环境无 flutter/dart,所有改动**未经编译验证**,需 `flutter pub get` + 真机自测。
- iOS 后台 + 微件功能上架需向 App Store 说明后台定位/蓝牙用途。
