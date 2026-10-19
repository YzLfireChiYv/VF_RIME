# Rime association framework — source preview

实验性源码预览：提供可审阅的原生扩展与独立演示，不附完整日用方案。

目标是让来源项、关联项、杆、显示投影与实际提交保持一致，并通过有限配置实现可预测输入。
原生改动提供结构化候选、T形区域样式与实测位置导航；Lua框架管理输入状态及关联预设。

## 内容

- patches/：Weasel、librime、librime-lua三份合并补丁，来源版本与散列见SOURCE-LOCK.json。
- framework/：18份原创MIT框架模块的审阅子集，**不是完整可运行输入方案**。
- examples/association_demo/：新写、无词典的独立演示；默认平铺，支持配套本体的杆及无API降级。
- tools/prepare_sources.py：显式选择才下载，按锁定基线应用补丁，不构建、不安装。

请先阅读示例README、BUILDING.md、THIRD-PARTY.md和KNOWN-LIMITATIONS.md。
完整词库、gram、现用翻译和emoji数据、私人custom/词表/历史、二进制及系统替换工具均不附带。
新增MIT代码与原生上游GPL/BSD分开，许可证范围以LICENSE-MAP.json为准。

本预览适合审代码和运行独立演示，不能直接覆盖用户的日用配置。
