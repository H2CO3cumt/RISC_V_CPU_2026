# Agent 接班协议

本文件补充根目录 `AGENTS.md`，用于 Codex GPT、DeepSeek Harness 或其他 Agent 在同一仓库中接续工作。根目录 `AGENTS.md` 的项目目标、Gate、正确性、验证和文档规则始终优先适用。

## 1. 新会话接班审计

新 Agent 收到“接续”“接班”“继续当前工作”或等价请求时，必须先完成以下只读审计，再进行任何文件修改：

1. 完整读取根目录 `AGENTS.md`、`docs/roadmap.md` 和 `docs/progress.md`。
2. 根据任务涉及范围，继续读取 `docs/interfaces.md`、`docs/architecture.md`、`docs/debug_log.md`、`docs/application_logic_analyzer.md` 或 `docs/competition_scoring.md` 中的相关部分。
3. 检查当前分支、`git status --short --branch`、完整的工作区差异以及最近 5 条提交。不得把未提交改动默认视为自己产生，也不得清理、回退或覆盖这些改动。
4. 若任务涉及 RTL 或仿真，定位相关 RTL、Testbench、构建脚本和既有测试入口；不得只读单个源文件就开始修改。
5. 在首次修改前，先向用户简要报告：当前 Gate、已确认完成的内容、当前未提交改动、尚未验证或存在风险的内容，以及本次准备继续的最小范围工作。

完成上述审计后，如果用户目标已经明确且工作仍在当前 Gate 内，应直接继续执行，不必为一般实现步骤再次请求确认。若缺少会改变架构或验收结果的关键选择，才暂停并询问用户。

## 2. 接班后的工作边界

- 严格遵循 `docs/roadmap.md` 的当前 Gate，不提前实现后续 Gate，不恢复本届已冻结的 RLE、BTB、Cache、异常/中断等功能。
- 保留用户和前一个 Agent 的已有改动；修改保持最小、可审查，不因风格偏好重写或大规模重构。
- Core/SoC 边界以 `docs/interfaces.md` 为准，不得把外设专用逻辑引入 CPU Core。
- Debug 必须从第一个错误周期和第一个错误信号开始，沿 `IF -> ID -> EX -> MEM -> WB` 定位，不得先猜根因。
- 若前一个 Agent 留下的结论与代码、测试或项目文档不一致，以可复现证据为准，并明确指出差异。

## 3. 验证与回交

修改核心 RTL 后，必须运行受影响模块的 Testbench 或 Regression，并记录：

- 实际执行的命令；
- PASS/FAIL 结果；
- 首个失败点或关键证据；
- 尚未覆盖的内容。

测试未通过时不得宣称完成，也不得进入下一 Gate。重要工作完成后，按根目录规则更新 `docs/progress.md`；重要 Bug、架构决定或接口变化分别更新对应项目文档。

最终回复必须给出可供下一个 Agent 继续接班的简短交接摘要，至少包含：修改文件、验证命令与结果、已知风险、下一步和是否满足当前 Gate 的验收条件。
