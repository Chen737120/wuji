# 舞记（wuji）项目级约定

> 本文件只写本项目特有内容，通用规则见全局 AGENTS.md（~/.zcode/AGENTS.md）。

## 构建范围（2026-10-25 用户决定）

- **只构建安卓版本**。iOS 与鸿蒙的开发均已暂停（用户原话"暂时放弃这两个版本"）；
- 任何开发 / 修复 / 交付会话**禁止构建 iOS IPA 或鸿蒙 HAP**，也不要提议回归这两个平台的构建验证；
- 仓库 CI 中已有的 iOS job 维持现状，不因本约束而改动（CI 属仓库配置，用户自行决定）；
- 若用户日后明确恢复 iOS / 鸿蒙，请先更新本文件再恢复相关构建。

## 上下文文件位置

- 本项目**没有** `Context Engineering/` 目录，等效上下文在 `docs/superpowers/`（specs / plans / prototypes）；
- 无 changes.md / state.md，开工同步以 `git log` 与 spec/plan 文件为准。
