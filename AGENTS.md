# 舞记（wuji）项目级约定

> 本文件只写本项目特有内容，通用规则见全局 AGENTS.md（~/.zcode/AGENTS.md）。

## 构建范围（2026-11-14 更新）

- **构建安卓 + iOS 双平台**。iOS 线已于 2026-11-14 经用户明确恢复（任务书见本机
  docs/superpowers/plans/2026-11-14-ios-parity-task-book.md，docs 不入库）；
- **鸿蒙仍禁止**：任何会话禁止构建鸿蒙 HAP（2026-10-25 用户决定，至今未恢复）；
- iOS 构建走仓库云构建（GitHub Actions ios-build.yml，公开仓库免费），产物为未签名 IPA；
  真机装机用免费 Apple ID 侧载（Sideloadly/爱思，7 天掉签）；
- 若用户日后暂停或恢复某平台，先更新本文件再执行相关构建。

## 上下文文件位置

- 本项目**没有** `Context Engineering/` 目录，等效上下文在 `docs/superpowers/`（specs / plans / prototypes）；
- 无 changes.md / state.md，开工同步以 `git log` 与 spec/plan 文件为准。
