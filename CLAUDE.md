# RPi-WiFi-Fallback 项目指南

## 项目概述

树莓派 WiFi 回退机制：WiFi 连接失败时自动启动 AP 热点，通过 Web 界面配置新 WiFi。

## 架构

```
config.sh      → 用户配置（AP 热点参数）
src/           → 源文件（开发时编辑）
dist/setup.sh  → 构建输出（部署用单文件）
scripts/       → 部署、测试脚本
```

**构建命令**：`./build.sh`

## 关键原则

- 控制 CLAUDE.md 的内容长度非常重要，越短越好
- 遵循 SOLID + DRY 原则：确保职责单一，避免重复
- 避免过度设计，遵循 KISS 原则（Keep It Simple, Stupid）
- 代码可读性享有最高的优先级
- 完全放弃向前兼容，涉及到的改动应该在遵循最佳实践的情况下全部重构
- 解决或者定位问题时使用"第一性原理"进行思考

## 开发要点

- 模板变量：`{{VAR}}` → 构建时替换为 `$VAR`
- heredoc 内变量需转义：`\$1`、`\$(cmd)`
- 构建标记：`# @INCLUDE: path`、`# @TEMPLATE: file`

## 文档指引

- 工程目录结构 → `docs/PROJECT_STRUCTURE.md`
- 开发踩坑记录 → `docs/TROUBLESHOOTING.md`

