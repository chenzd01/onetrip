# AGENTS.md — OneTrip · 一程

This file is the working contract for AI coding agents (Codex, Claude Code, …) and humans.
`CLAUDE.md` points here. 中文版在下方。

## What this repository is

A destination-agnostic, offline-first iOS travel journal (SwiftUI, iOS 26+, iPhone) plus an
optional Python backend for shared sync, day routes and partner notifications. All trip
content lives in `content/`; the app code does not know which city it is for. `content/`
currently holds a real, agent-researched Kyoto example (research records in `docs/research/kyoto/`).
The Xcode project and targets are named `TripJournal` internally.

To make the app for a new trip, use the `new-trip` skill (`.agents/skills/new-trip/SKILL.md`,
mirrored in `.claude/skills/`; keep the two copies identical).

## Rules

1. **Content goes in `content/` only.** Do not edit Swift/Python to add destination facts.
   Change code only when the user asks for a feature or fix.
2. **Research before writing.** Follow `docs/en/research-playbook.md` (or `docs/zh/`):
   official sources read in a real browser; every fact gets a source URL and `checkedAt`;
   separate official price / planning budget / estimate; record conflicts instead of guessing;
   leave gaps rather than invent. Never fabricate coordinates, prices, hours, photos or reviews.
3. **Never take irreversible or account actions**: no bookings, payments, form submissions,
   e-mails, messages, sign-ups or account changes. Stop at the step before the guest-details or
   payment page and report what you saw.
4. **Stable IDs.** Place IDs, itinerary `uid`s and preparation IDs are never renamed once used.
5. **Privacy.** Never commit `ios/Signing.xcconfig`, `ios/SharedAccess.xcconfig`, generated
   `ios/*.xcodeproj`, secrets, `.p8` keys, databases, booking references, ID numbers, personal
   paths or names. Run `scripts/privacy_check.py` before publishing anything
   (`docs/en/privacy-before-publish.md`).
6. **Copyright.** Do not add social-media images/text, hotel-platform photos or "all rights
   reserved" images without permission. Prefer openly licensed photos with attribution.
7. **Honest verification.** Report exact test counts. Simulator ≠ device; uploaded ≠ processed ≠
   available in TestFlight ≠ installed. Never claim a check passed that you did not run.

## Commands (run from the repository root)

```bash
make setup && make test                              # shortcuts for everything below (see Makefile)
python3 scripts/verify_content.py                    # structure gate
python3 scripts/verify_content.py --require-complete # real-trip gate: no sample text / placeholders
python3 scripts/build_ios_resources.py               # content/ -> app bundle content
python3 -m unittest discover -s scripts -p 'test_*.py'
python3 -m unittest discover -s server  -p 'test_*.py'
python3 -m unittest discover -s deploy  -p 'test_*.py'
cp -n ios/Signing.example.xcconfig ios/Signing.xcconfig
xcodegen generate --spec ios/project.yml
xcodebuild test -project ios/TripJournal.xcodeproj -scheme TripJournal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
python3 scripts/make_screenshots.py                  # README / sharing images into docs/assets/
```

## Definition of done for a content change

`verify_content.py` passes (with `--require-complete` for a real trip), resources rebuilt,
`verify_content.py --built-catalog` passes, iOS tests pass, and a research record exists in
`docs/research/` listing sources, read dates, conflicts and open questions.

## Map of the docs

| Need | English | 中文 |
| --- | --- | --- |
| Step-by-step for a new destination | `docs/en/new-destination.md` | `docs/zh/new-destination.md` |
| Copy-paste prompts per phase | `docs/en/agent-prompts.md` | `docs/zh/agent-prompts.md` |
| How to research each content type | `docs/en/research-playbook.md` | `docs/zh/research-playbook.md` |
| Every field in `content/` | `docs/en/content-schema.md` | `docs/zh/content-schema.md` |
| App, sync and backend architecture | `docs/en/architecture.md` | `docs/zh/architecture.md` |
| Optional backend setup | `docs/en/backend.md` | `docs/zh/backend.md` |
| Signing, TestFlight | `docs/en/ios-delivery.md` | `docs/zh/ios-delivery.md` |
| Known pitfalls | `docs/en/lessons-learned.md` | `docs/zh/lessons-learned.md` |
| Privacy & copyright before publishing | `docs/en/privacy-before-publish.md` | `docs/zh/privacy-before-publish.md` |

---

# AGENTS.md（中文）

本文件是 AI 编码 Agent（Codex、Claude Code 等）和人的共同工作约定，`CLAUDE.md` 指向这里。

## 这个仓库是什么

一个与目的地无关、离线优先的 iOS 旅行手帐（SwiftUI，iOS 26+，仅 iPhone），外加可选的 Python
后端（共享同步、全天路线、同行人互动推送）。所有旅行内容都在 `content/`，App 代码不知道自己服务哪座城市。
`content/` 目前是一份由 Agent 真实调研的京都示例（调研记录在 `docs/research/kyoto/`）。Xcode 工程与 target
内部名为 `TripJournal`。

为新旅行做 App 时使用 `new-trip` 技能（`.agents/skills/new-trip/SKILL.md`，`.claude/skills/` 下有一份相同的副本，两份保持一致）。

## 规则

1. **内容只写进 `content/`。** 不为了加目的地信息去改 Swift / Python；只有用户要求功能或修复时才改代码。
2. **先调研，后填写。** 遵循 `docs/zh/research-playbook.md`：官方来源、浏览器实读；每条事实带来源链接和
   `checkedAt`；官方价 / 规划预算 / 估算分开；冲突如实记录，不猜；宁可留空也不编造坐标、价格、时间、照片或评价。
3. **绝不做不可逆或账号操作**：不预订、不付款、不提交表单、不发邮件或消息、不注册、不改账号设置。停在填写住客信息或
   付款页之前，报告看到的内容。
4. **ID 稳定。** 地点 ID、行程 `uid`、准备项 ID 一旦使用就不改名。
5. **隐私。** 不提交 `ios/Signing.xcconfig`、`ios/SharedAccess.xcconfig`、生成的 `ios/*.xcodeproj`、密钥、`.p8`、
   数据库、订单号、证件号、个人路径或姓名。公开任何东西前运行 `scripts/privacy_check.py`
   （见 `docs/zh/privacy-before-publish.md`）。
6. **版权。** 未经授权不放社媒帖子图文、订房平台图片或「保留所有权利」的图片；优先使用开放许可并署名的照片。
7. **如实验证。** 报告精确的测试数量。模拟器 ≠ 真机；已上传 ≠ 已处理 ≠ TestFlight 可测试 ≠ 已安装。没跑过的检查不说通过。

## 常用命令

见上方英文部分的 Commands，命令相同。

## 内容改动的完成标准

`verify_content.py` 通过（真实旅行加 `--require-complete`），重新构建资源，`verify_content.py --built-catalog`
通过，iOS 测试通过，并在 `docs/research/` 留有调研记录（来源、读取日期、冲突、未决问题）。

## 文档地图

见上方英文部分的表格，中文文档在 `docs/zh/` 下同名文件。
