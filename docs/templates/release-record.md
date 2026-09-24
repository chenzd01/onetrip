# 发布记录 · Release record：<版本 / version> (<构建号 / build>)

> 复制到 `docs/releases/<版本>-<构建号>.md` 后填写。流程见 `docs/zh/ios-delivery.md`。
> Copy to `docs/releases/<version>-<build>.md`. Process: `docs/zh/ios-delivery.md`.
>
> **不要写入 / Never paste**：Team ID、App Store Connect 内部 ID、构建 UUID、证书或密钥（`.p8`、共享访问密钥）、服务器地址与路径、测试者姓名/邮箱/电话、个人电脑的绝对路径（个人主目录、外置盘路径）。
> Team ID, App Store Connect internal IDs, build UUIDs, certificates or keys (`.p8`, shared access key), server hosts and paths, tester names/emails/phones, absolute personal paths (home directory, external drives).
>
> 每一项只写实际确认过的事实；没确认的放进第 7 节。
> Record only what was actually confirmed; everything else goes to section 7.

| 项目 / Field | 内容 / Value |
| --- | --- |
| 日期 / Date | YYYY-MM-DD HH:mm（时区 / time zone） |
| 营销版本 / Marketing version | 1.0.0 |
| 构建号 / Build number | |
| 源码提交 / Source commit | 短哈希 / short hash |
| 分支 / Branch | |

## 1. 变更范围 · Scope

用户能感知到的变化（每条一句）。
User-visible changes, one line each.

-
-

涉及的主要文件 / Main files：

-

不在本次范围 / Out of scope：

-

## 2. 本地验证 · Local verification

写精确数字：通过 / 跳过 / 失败。跳过不算通过，要写原因。
Exact counts: passed / skipped / failed. Skipped is not passed — give the reason.

| 检查 / Check | 命令 / Command | 结果 / Result |
| --- | --- | --- |
| 内容门禁 / Content gate | `python3 scripts/verify_content.py --require-complete` | PASS / FAIL |
| 资源生成 / Resources | `python3 scripts/build_ios_resources.py` + `verify_content.py --built-catalog` | |
| 资源测试 / Resource tests | `python3 scripts/test_ios_resources.py` | N 通过 / passed |
| 原生测试 / Native tests | `xcodebuild test ...` | N 通过 / passed，N 跳过 / skipped，N 失败 / failed |
| 后端测试 / Server tests | `python3 -m unittest discover -s server -p 'test_*.py'` | |
| 部署测试 / Deploy tests | `python3 -m unittest discover -s deploy -p 'test_*.py'` | |
| 隐私扫描 / Privacy scan | `python3 scripts/privacy_check.py` | |

跳过原因 / Skip reasons：

-

模拟器实查 / Simulator checks（设备型号、系统版本、看了哪些页面、深色/大字号 / device, OS, screens, dark mode / large text）：

-

## 3. 后端 · Backend

- [ ] 本次无后端变更 / No backend change
- [ ] 本次发布了后端 / Backend deployed：

| 项目 / Item | 结果 / Result |
| --- | --- |
| 发布文件（白名单）/ Files (allowlist) | |
| dry-run 基线一致 / Baseline matched | 是 / 否 · yes / no |
| 发布前备份 / Backup before deploy | 已完成（不写路径）/ done (no path) |
| 共享数据指纹前后一致 / Shared data fingerprint unchanged | 是 / 否 · yes / no |
| 健康检查 / Health check | |
| 服务开关状态 / Feature flags | |

## 4. 归档与上传 · Archive and upload

| 检查 / Check | 结果 / Result |
| --- | --- |
| Release 归档 / Archive | 成功 / 失败 · succeeded / failed |
| App 与 Widget 版本一致 / App & widget versions match | 1.0.0 (N) / 1.0.0 (N) |
| `codesign --verify --deep --strict` | App ✓ / Widget ✓ |
| Team 与 App Group 为正式值 / Release team & App Group | 是 / 否 · yes / no（不写具体值 / no values） |
| 分发包 `aps-environment` / Distribution `aps-environment` | production / 未使用推送 / push not used |
| 分发包 `get-task-allow` | false |
| 内置资源与生成目录一致 / Bundled content matches | 是（N 个文件）/ yes (N files) |
| 上传回执 / Upload receipt | `Upload succeeded` / `EXPORT SUCCEEDED`，退出码 / exit 0，时间 / at HH:mm |

## 5. TestFlight 分发 · TestFlight distribution

| 步骤 / Step | 状态 / Status | 确认时间 / Confirmed at |
| --- | --- | --- |
| Apple 处理 / Processing | 完成 / 处理中 · complete / processing | |
| 测试内容已保存 / Test notes saved | | |
| 内部组 / Internal group | Testing / 未加入 · not added | |
| 外部组 / External group | Testing / 等待审核 / 审核中 · Waiting / In review | |
| Automatically notify testers | 已勾选 / checked | |

测试说明（发给测试者的原文）/ Test notes (as sent)：

```text
本次更新：……
请在 TestFlight 里直接更新，不要卸载旧版本。
What's new: …
Please update in TestFlight; do not delete the old app.
```

## 6. 状态阶梯 · Status ladder

逐级勾选，只勾实际确认的。
Tick only what was actually confirmed.

- [ ] 归档成功 / Archived
- [ ] 上传成功 / Uploaded
- [ ] Apple 处理完成 / Processed
- [ ] 已加入测试组 / Added to groups
- [ ] 外部审核通过（如需要）/ External review approved (if required)
- [ ] 测试组显示 Testing / Groups show Testing
- [ ] 测试者页面显示已安装本构建 / Tester page shows this build installed
- [ ] 真机验收通过 / Verified on physical devices

## 7. 未证明的边界 · Not proven

模拟器 ≠ 真机；上传 ≠ 已处理 ≠ 可测试 ≠ 已安装；APNs 接受 ≠ 手机响了；跳过 ≠ 通过。
Simulator ≠ device; uploaded ≠ processed ≠ testable ≠ installed; APNs accepted ≠ phone rang; skipped ≠ passed.

-
-

## 8. 产物位置 · Artifacts

只写相对仓库的路径或“本机产物目录”，不写个人绝对路径。
Repository-relative paths or "local artifact folder" only; no absolute personal paths.

| 产物 / Artifact | 位置 / Location |
| --- | --- |
| 归档 / Archive | `ios/build/TripJournal-<build>.xcarchive` |
| 归档与上传日志 / Archive & upload logs | `test-results/release-<build>/` |
| 测试结果 / Test results | `test-results/release-<build>/` |
| 截图 / Screenshots | `test-results/release-<build>/` |
