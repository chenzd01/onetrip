# 给 Codex / Claude Code 的分阶段提示词

把下面的提示词按阶段复制给你的编码 Agent。每个阶段一次对话或一个任务，做完检查结果再进入下一阶段。尖括号 `<…>` 替换成你的信息。

通用前提（Agent 会自动读取仓库根目录的 `AGENTS.md`；`CLAUDE.md` 指向同一文件）：

- 内容只改 `content/`；除非你明确要求，不改 Swift / Python 代码。
- 所有事实都要来源 + 核对日期；查不到就留空并说明，**不要编造**。
- 不预订、不付款、不提交表单、不发邮件、不登录你的账号做任何改动。

---

## 阶段 1：旅行简报

```text
请阅读 AGENTS.md 和 docs/zh/new-destination.md。
我们要为 <目的地> 做这个 App。旅行信息：
- 日期：<第一天> 到 <最后一天>，<离家日期> 出发；航班 <去程航班号/时刻>，<回程航班号/时刻>
- 人数：<N> 人；节奏：<几点起床、每天步行量、体力>
- 必去：<…>；想去：<…>；不去：<…>
- 饮食：<忌口/偏好>；预算：<住宿/餐饮/门票档位>
- 当地语言：<…>
请把这些整理成 docs/research/00-brief.md，并列出你还需要我确认的问题。先不要改 content/。
```

## 阶段 2：目的地配置

```text
根据 docs/research/00-brief.md 填写 content/trip.json（字段见 docs/zh/content-schema.md）。
- id 用 <slug>-<年份>-v1
- 汇率从一个公开来源取当天数据，写 rateDate 和 rateSource
- map.bounds 只覆盖行程范围，并说明你是怎么确定的
完成后运行 python3 scripts/verify_content.py，只修 trip.json 相关的错误，报告结果。
```

## 阶段 3：地点与坐标调研

```text
请严格按照 docs/zh/research-playbook.md 的「通用证据规则」和「地点与坐标」「照片」章节，
为 <目的地> 调研地点并写入 content/places.json 和 content/locations.json：
- 候选来源：目的地官方旅游局、各景点官网（在浏览器里实际打开阅读）、攻略/社媒只用来发现候选和拍照点
- 每个地点：开放时间、官方票价与规划预算分开、建议时段、交通、雨天备选、sources、checkedAt
- 坐标：OpenStreetMap 候选按名称/类型/地址人工核对，排除车站、公交站等误匹配；必须落在 trip.json 的 map.bounds 内
- 查不到或信息冲突的，写进 docs/research/10-places.md 的「冲突与未决」，不要猜
目标数量：<N> 个。完成后运行 verify_content.py 并报告：新增地点、仍未确认的事项、所用来源清单。
```

## 阶段 4：餐饮

```text
按 research-playbook.md 的「餐饮」章节调研 <目的地> 餐饮，写入 content/dining.json：
1. 先找一份权威完整名单作为锚点（例如当年官方美食指南全名单），记录版本年份、数量和来源
2. 从中挑 <N> 家与我们行程区域和口味匹配的做 detailed：每个菜单单独写 sourceURL/checkedAt，写清税费/服务费口径
3. 订位只查询、不预订：在餐厅自己的订位系统选择日期、餐段、<人数> 人，把结果写成 observations 快照
4. recommendations 按行程天序号给出候选
完成后运行 verify_content.py，报告冲突与未确认事项（写进 docs/research/20-dining.md）。
```

## 阶段 5：行程编排

```text
根据 00-brief.md、places.json、dining.json，编排 content/itinerary.json：
- 天数与 trip.json 逐日对应；uid 唯一且以后不再改
- 同区域聚类，站间留 15–45 分钟缓冲；硬约束（航班、需预约的时段、闭馆日、演出时间）优先
- 每天在 note 里写一句当天思路和雨天替换方案
- 默认预算 budget 按简报档位估算（全程总额；机票用母国货币，其余当地货币）
完成后运行 verify_content.py，不能有时间重叠警告；把编排理由写进 docs/research/30-itinerary.md。
```

## 阶段 6：行前准备、短句、实用信息

```text
按 research-playbook.md 的「行前准备」「旅行短句」章节：
- content/preparation.json：入境要求、证件有效期、电子入境卡、通信、支付、交通卡、当地规定、返程复查；
  只用官方来源并当天阅读；按「什么时候做」分组，需要时设 dueDate；每项写方法和完成标准；不写任何个人证件号
- content/phrases.json：按场景 <N> 组，local 用 <语言>，note 解释当地特有说法
- content/references.json、content/flights.json
完成后运行 verify_content.py 并报告。
```

## 阶段 7：酒店、照片、参考帖子（可选）

```text
按 research-playbook.md 对应章节：
- hotels.json：固定查询条件 <入住>–<退房>、<人数>、<房间数>、<货币>；报价取整段总价明细，停在填写住客信息之前，绝不下单
- photo-sources.json：只用开放许可图库（如 Wikimedia Commons），逐张确认画面与许可证，写 downloadUrl 后运行
  python3 scripts/build_photos.py --download-missing
- posts.json：<有/没有> 转载授权。没有授权时只写标题、作者、链接、采集日期和你自己的摘要，封面用自己的图
完成后运行 verify_content.py。
```

## 阶段 8：发布门禁与模拟器检查

```text
1. 运行 python3 scripts/verify_content.py --require-complete，逐条修复直到 PASS
2. python3 scripts/build_ios_resources.py && python3 scripts/verify_content.py --built-catalog
3. cp -n ios/Signing.example.xcconfig ios/Signing.xcconfig; xcodegen generate --spec ios/project.yml
4. xcodebuild test（iPhone 模拟器），报告精确的通过/失败/跳过数
5. 在模拟器里逐页截图（今日、行程每一天、探索四个分段、行囊），检查空白、截断、错误日期、残留示例文字
不要声称没跑过的检查已通过；模拟器故障请如实报告。
```

## 阶段 9：发布到 TestFlight

```text
按 docs/zh/ios-delivery.md 准备 TestFlight 构建：
- 版本号：MARKETING_VERSION <x.y.z>，CURRENT_PROJECT_VERSION 加 1（App 与 Widget 一致）
- 我已在 ios/Signing.xcconfig 填好 Team 和 Bundle ID（不要读取或打印其中内容以外的任何凭据）
- 归档、导出、上传；上传前做 codesign 与 entitlements 检查
- 按 docs/templates/release-record.md 写发布记录到 docs/releases/
上传、添加测试组、通知测试员这些在 App Store Connect 上的操作，先告诉我你要做什么，得到确认再做。
```

## 旅途中的小改

```text
<日期> 的安排要改：<…>。请只改 content/itinerary.json 的 <日期> 这一天（不要改 uid），
重新构建并运行测试。注意：用户在 App 里已保存的行程不会被内容更新自动覆盖，这是有意的设计；
如果我们已经开启共享同步，请告诉我在 App 里手动调整更合适还是发新构建更合适。
```
