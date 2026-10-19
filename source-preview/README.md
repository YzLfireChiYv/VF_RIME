# 源码预览

本目录提供配套小狼毫、librime 与 Lua 绑定的修改补丁，以及输入状态和候选关联框架。

- `patches/`：原生组件补丁，基线与校验值见 `SOURCE-LOCK.json`。
- `framework/`：Lua 框架源码。
- `examples/association_demo/`：可独立部署的候选关联演示。
- `tools/prepare_sources.py`：获取指定上游源码并应用补丁。

构建方法见 `BUILDING.md`，许可范围见 `LICENSE-MAP.json`。完整日用方案仍在整理。
