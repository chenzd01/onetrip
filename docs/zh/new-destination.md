# 为新目的地做一个 App：从零到 TestFlight

本文是完整流程清单。每一步都有**完成标准**；没达到就不要进入下一步。适合人照着做，也适合直接交给 Codex / Claude Code 执行：在 Claude Code 或 Codex 里输入 `/new-trip <目的地> <日期> <人数>`，Agent 会按本文和 [agent-prompts.md](agent-prompts.md) 的分阶段提示词推进。

预计投入：内容调研 1–3 天（取决于目的地和深度），工程与发布半天到一天。

## 0. 准备

| 需要 | 说明 |
| --- | --- |
| macOS + Xcode 26 或更新 | App 最低 iOS 26，仅 iPhone |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | `brew install xcodegen`；工程由 `ios/project.yml` 生成 |
| Python 3.11+ 与 Pillow | `python3 -m pip install Pillow` |
| Apple Developer 付费账号 | 只有装到真机 / TestFlight 才需要；模拟器不需要 |
| 一个 AI 编码 Agent（可选） | Codex、Claude Code 等，能读写本仓库、能用浏览器查资料 |

**完成标准**：`make setup && make open` 成功，模拟器能跑起自带的京都示例（等价的逐条命令见第 6 步）。

## 1. 新建你的仓库

1. 在 GitHub 上用本模板创建新仓库（Use this template），或 fork 后改名。**建议设为私有**：你的行程、酒店、同行人信息都会进这个仓库。
2. 新建一个工作分支，例如 `trip/kyoto-2031`。
3. 删掉京都示例内容，保留结构：`content/*.json` 里的条目、`content/media/` 下的照片、`docs/research/kyoto/` 调研记录。也可以先保留示例，边填边替换；示例本身就是每个字段怎么写的参考答案。

**完成标准**：你有一个私有仓库，`content/` 只剩你打算填写的结构。

## 2. 明确旅行需求（和同行人一起）

在 `docs/research/00-brief.md`（自建目录）里写一页简报，调研和编排都以它为准：

- 目的地、日期（第一天 / 最后一天 / 离家当天）、航班时刻（不写订单号）。
- 同行人数，节奏偏好（几点起床、几点出门、每天能走多少），体力与饮食限制。
- 必去 / 想去 / 可去清单，拍照偏好，预算档位（住宿、餐饮、门票）。
- 雨天或高温时的底线安排。
- 语言：当地语言是什么，需要哪种朗读语音。

**完成标准**：简报经过所有同行人确认。

## 3. 填 `trip.json`

按 [content-schema.md](content-schema.md#tripjson) 逐字段填写。要点：

- `id` 用新的、从没用过的值，例如 `kyoto-2031-v1`。App 为了不覆盖用户数据，遇到另一趟旅行（另一个 `id`）留下的本机存档会拒绝打开：同一台手机上装过上一趟旅行的版本时，先在旧版里导出备份再删除旧 App，或者给新旅行换一个 Bundle ID。
- `timezone` 用 IANA 名称（`Asia/Tokyo`）。
- `map.bounds` 画成**刚好覆盖行程范围**的矩形，别把邻国/邻城大片包进来。
- 汇率：从一个公开来源取数，写 `rateDate` 与 `rateSource`，这是规划参考，不是银行结算价。
- `speech.language`：日语 `ja-JP`，韩语 `ko-KR`，泰语 `th-TH`，英语 `en-US` / `en-GB`。

**完成标准**：`python3 scripts/verify_content.py` 对 `trip.json` 没有报错（其他文件的错误此时可以先忽略）。

## 4. 内容调研与填充

严格按 [research-playbook.md](research-playbook.md) 的证据规则来做。推荐顺序（后面的依赖前面的 ID）：

| 顺序 | 文件 | 最低要求 | 建议 |
| --- | --- | --- | --- |
| 1 | `places.json` + `locations.json` | ≥5 个地点，全部有坐标、来源、核对日期 | 每个地点写清开放时间、票价、建议时段、雨天备选 |
| 2 | `dining.json` | 可选 | 先找一份权威完整名单做锚点，再挑 10–20 家细化 |
| 3 | `itinerary.json` | 每天都有安排，时间递增不重叠 | 同区域聚类，留 15–45 分钟交通缓冲，每天有雨天替换 |
| 4 | `preparation.json` | ≥10 项，按「何时做」分组 | 入境、证件、通信、支付、交通卡、当地规定都来自官方页面 |
| 5 | `hotels.json` | 可选 | 固定同一组查询条件比价，报价取整段总价 |
| 6 | `photo-sources.json` | 可选 | 开放许可图库，每个地点 2–3 张不同角度 |
| 7 | `posts.json` | 可选 | 只放有授权的内容；否则只保留标题、链接和自己的摘要 |
| 8 | `phrases.json` | 可选 | 按场景 4–8 组，写当地特有说法的含义 |
| 9 | `references.json` / `flights.json` | 可选 | 交通卡、紧急电话、退税；航班只写航班号与时刻 |

每做完一类内容，在 `docs/research/` 里留一份调研记录（模板：[../templates/research-record.md](../templates/research-record.md)），写清读了哪些来源、什么时候读的、冲突怎么处理、还有什么没确认。

**完成标准**：

```bash
python3 scripts/verify_content.py --require-complete
```

输出 `PASS`（不允许残留 `【示例】`、`example.com`、`待核实`、`TODO`）。

## 5. 构建内容与本地检查

```bash
python3 scripts/build_ios_resources.py
python3 scripts/verify_content.py --built-catalog
python3 -m unittest discover -s scripts -p 'test_*.py'
```

构建输出里会列出天数、地点数、图片数和总字节数。内容包一般在几 MB 到几十 MB；照片越多越大。

**完成标准**：三条命令都通过。

## 6. 在模拟器里跑

```bash
cp -n ios/Signing.example.xcconfig ios/Signing.xcconfig   # 模拟器可以不填 Team
xcodegen generate --spec ios/project.yml
xcodebuild test -project ios/TripJournal.xcodeproj -scheme TripJournal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
open ios/TripJournal.xcodeproj   # 或在 Xcode 里直接运行
```

逐页检查：今日、行程（每一天）、探索（地点 / 餐饮 / 攻略 / 酒店）、行囊（清单、预算、航班、短句朗读）。用最大字号和深色模式各看一遍。

想看「旅途中」的今日页，在 Xcode scheme 的启动参数里加 `-TripNow 2031-04-02T10:30`（目的地当地时间，仅 Debug 构建生效）。

`make screenshots` 会用你的内容截取各页，在 `docs/assets/` 生成首图、单屏图、社交预览图和动图，可以顺便当作检查清单逐张看一遍，也可以拿去分享。

**完成标准**：测试通过；四个页签没有空白、截断、错误日期或残留的示例文字。

## 7.（可选）双人共享与路线后端

App 默认完全离线：行程改动只保存在本机。需要两部手机共享同一份行程、全天路线计算或情侣互动推送时，按 [backend.md](backend.md) 自建后端，再创建 `ios/SharedAccess.xcconfig`（参考 `SharedAccess.example.xcconfig`）。

**完成标准**：两台设备修改同一天的不同安排，都能看到对方的修改；同时改同一项时出现冲突对比而不是覆盖。

## 8. 签名与 TestFlight

按 [ios-delivery.md](ios-delivery.md)：

1. 在 `ios/Signing.xcconfig` 填 `DEVELOPMENT_TEAM` 和你自己的 `APP_BUNDLE_ID`（反向域名）。
2. 在 Apple Developer 注册 App ID、Widget 扩展 ID（`<bundle id>.widgets`）和 App Group（`group.<bundle id>`）；用后端推送时再开启 Push Notifications。
3. 在 App Store Connect 建应用记录，归档上传，建内部 / 外部测试组，把同行人加进去。
4. 每次上传都留一份发布记录（模板：[../templates/release-record.md](../templates/release-record.md)）。

**完成标准**：同行人的手机上 TestFlight 显示新构建为「可测试」，并且真的装上打开过。

## 9. 出发前与旅途中

- 出发前 3–5 天：重新核对开放时间、临时关闭、票价和天气，更新 `checkedAt`，再发一个构建。
- 飞行模式下全新安装一次，确认离线内容完整、门票附件可打开。
- 旅途中只做小修；内容大改会让两台设备的共享行程产生冲突。

## 10. 旅行结束后

- 导出行程备份（行囊 › 备份），和门票原件一起归档。
- 若自建了后端：停服务、备份数据库、删除公网入口，保留还是删除数据由你决定。
- 把这次踩到的坑补进 [lessons-learned.md](lessons-learned.md)，下一次会更快。
