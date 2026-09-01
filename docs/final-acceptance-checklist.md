# 一览 Yilan 一次性最终验收清单

> 这是发布前的一次性验收，不是日常 CI。自动门禁与人工真机验收均通过后，才可签字。所有步骤都必须在**真实 Android 手机和真实 iPhone**上执行；模拟器、Chrome、截图回放不能替代真机结果。

## 0. 验收规则

- [ ] 在 `yilan/` 目录执行 `tools/final_acceptance.sh`。
- [ ] 脚本按顺序执行：Flutter 环境、依赖、format、analyze、全测试、UI 响应式回归门禁、Android release、iOS release、macOS release、设备清单。
- [ ] 任一步命令退出码非 0，立即停止；不得继续人工验收或签字。修复后删除旧证据目录并从头重跑。
- [ ] `dart format --set-exit-if-changed` 非 0 即失败；不能先自动格式化再宣称通过。
- [ ] `flutter analyze` 有 error、`flutter test` 有失败、任一平台构建失败，均为失败。普通 warning 只有在命令退出码为 0 且已记录时才可接受。
- [ ] 人工步骤任一预期不成立、出现崩溃/白屏/卡死/数据丢失，立即停止并标记 FAIL；不得用“基本可用”替代。
- [ ] 每项人工步骤都要有：设备型号与 OS、App 版本/构建号、时间、操作视频或连续截图、结果说明。证据不能只放在聊天窗口。

## 1. 自动门禁

```bash
cd /Users/rex/codes/linkbook/yilan
FINAL_ACCEPTANCE_EVIDENCE_DIR="$PWD/artifacts/final-acceptance/<UTC时间>" \
  tools/final_acceptance.sh
```

脚本成功时会打印 `FINAL ACCEPTANCE: PASS`。证据目录结构如下（实际时间戳由脚本生成）：

```text
artifacts/final-acceptance/<UTC时间>/
  automated/summary.tsv
  automated/environment.log
  automated/dependencies.log
  automated/format.log
  automated/analyze.log
  automated/tests.log
  automated/android_release.log
  automated/ios_release.log
  automated/macos_release.log
  automated/devices.log
  automated/README.txt
  manual/FA-01/ ... FA-08/
```

> 自动脚本使用 `set -Eeuo pipefail`，并从 `PIPESTATUS[0]` 读取真实命令退出码。不要把它改成 `command || true`、`... | tee ...; exit 0` 或忽略 `PIPESTATUS`。

## 1.1 UI 响应式回归门禁

日常开发可单独执行：

```bash
tools/ui_regression_gate.sh
```

门禁在 `1280x800` 桌面和 `390x844` 移动尺寸下验证：统一 `AppShell`、底部导航栏固定 80dp 与安全区、书签/浏览/设置切换、浏览器地址栏与标签卡片、历史记录/阅读清单卡片入口、设置中的隐私说明入口，并断言无 `OverflowBar` 或 Flutter 渲染异常。

## 2. 人工真机验收（8 项）

在 `<证据根>` 下为每项建立对应目录，例如：
`artifacts/final-acceptance/20260830T120000Z/manual/FA-01/`。

### FA-01 启动与底部导航

- 设备：Android 真机、iPhone 真机各执行一次。
- 操作：冷启动 App；依次点击“桌面 / 浏览 / 设置”三个底部 tab，再返回桌面。
- 预期：启动无崩溃、无白屏；三个 tab 均可进入，返回桌面状态正常。
- 证据：`manual/FA-01/android.mp4`、`manual/FA-01/ios.mp4`，并附 `result.md`（型号、OS、构建号、结论）。

### FA-02 书签网格、翻页与打开

- 设备：Android 真机、iPhone 真机。
- 操作：确认 4x5 书签网格；左右滑动翻页；点开一个书签。
- 预期：网格排列、页数/圆点指示正确；翻页不丢项；书签可打开对应页面。
- 证据：`manual/FA-02/android.mp4`、`manual/FA-02/ios.mp4`、`result.md`。

### FA-03 长按编辑与拖动重排

- 设备：Android 真机、iPhone 真机。
- 操作：长按书签（至少 280ms）进入编辑态；拖到另一位置；双指轻点进出编辑态。
- 预期：出现抖动/编辑态；拖动后插入让位且顺序正确；双指手势能进出编辑态。
- 证据：`manual/FA-03/android.mp4`、`manual/FA-03/ios.mp4`、`result.md`。

### FA-04 停留合并与文件夹吸入

- 设备：Android 真机、iPhone 真机。
- 操作：编辑态拖一个书签到另一个书签上停留至少 350ms；打开文件夹；再拖入一个书签。
- 预期：生成文件夹且两项都在；文件夹内可查看；��入后数量和内容正确。
- 证据：`manual/FA-04/android.mp4`、`manual/FA-04/ios.mp4`、`result.md`。

### FA-05 边缘跨页投放与整组搬运

- 设备：Android 真机、iPhone 真机。
- 操作：拖动书签到屏幕边缘停留至少 480ms 完成翻页投放；多选多项后整体拖到另一页或文件夹。
- 预期：自动翻页且目标项落在目标页；多选项作为整组移动，不重复、不丢失。
- 证据：`manual/FA-05/android.mp4`、`manual/FA-05/ios.mp4`、`result.md`。

### FA-06 浏览器导航与收藏当前页

- 设备：Android 真机、iPhone 真机。
- 操作：在地址栏输入 `https://example.com`；打开页面；执行前进、后退、刷新；点击星号收藏；回桌面查看。
- 预期：网页加载成功；导航按钮行为正确；收藏后桌面出现当前页面书签，标题/URL 正确。
- 证据：`manual/FA-06/android.mp4`、`manual/FA-06/ios.mp4`、`result.md`（网络条件也要记录）。

### FA-07 设置项与深色/无痕行为

- 设备：Android 真机、iPhone 真机。
- 操作：修改搜索引擎、广告拦截、无痕和深色模式；退出设置后重新进入并重启 App 检查。
- 预期：开关/选项即时生效；深色模式视觉切换完整；重启后设置保持；无痕会话不把该会话内容写入历史/书签。
- 证据：`manual/FA-07/android.mp4`、`manual/FA-07/ios.mp4`、`result.md`。

### FA-08 删除确认与持久化恢复

- 设备：Android 真机、iPhone 真机。
- 操作：删除普通书签并取消一次确认；再确认删除；对含多个项目的文件夹重复一次；强制结束 App 后重启。
- 预期：取消不会删除；确认后项目消失；文件夹确认提示包含数量；重启后剩余书签、文件夹及设置仍在。
- 证据：`manual/FA-08/android.mp4`、`manual/FA-08/ios.mp4`、`result.md`。

## 3. 最终签字

- 自动证据目录：`<证据根>`
- Android 真机：型号 `____________`，OS `____________`，结果 `PASS / FAIL`
- iPhone 真机：型号 `____________`，iOS `____________`，结果 `PASS / FAIL`
- 自动门禁 summary：`<证据根>/automated/summary.tsv`
- 验收人：`____________`  日期（UTC）：`____________`
- [ ] 8/8 人工步骤均有证据且 PASS
- [ ] 自动门禁所有步骤均为 PASS
- [ ] 最终结论：`PASS / FAIL`
