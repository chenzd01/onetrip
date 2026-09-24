# 内容数据结构（content/）

`content/` 是整个 App 唯一的内容源。换一个目的地，只需要改这个目录里的文件和 `content/media/` 里的图片，不需要改 Swift 代码。

- 字段的最终权威是 `scripts/verify_content.py`（结构校验）和 `scripts/build_ios_resources.py`（构建时校验）。本文与脚本冲突时以脚本为准，并请顺手修正本文。
- 仓库自带的京都 3 日示例是由 Agent 真实调研的内容，每个文件都可以直接对照阅读；调研记录在 `docs/research/kyoto/`。
- 所有 ID 使用小写字母、数字和连字符（`^[a-z0-9][a-z0-9-]{0,79}$`），**一旦发布就不要改**：用户的行程、收藏、打勾状态都靠 ID 关联。
- 日期一律 `yyyy-MM-dd`，时间 `HH:mm`，日期时间 `yyyy-MM-ddTHH:mm`，均为**目的地当地时间**（航班除外，见下文）。
- 事实类内容都要带来源链接（https）和核对日期 `checkedAt`，调研方法见 [research-playbook.md](research-playbook.md)。

## 文件总览

| 文件 | 必需 | 内容 | App 中的位置 |
| --- | --- | --- | --- |
| `trip.json` | 是 | 目的地配置：名称、日期、时区、货币、地图范围、朗读语言 | 全局 |
| `places.json` | 是 | 景点 / 地点目录，可内嵌深度攻略 `guides` | 探索 › 地点；行程引用 |
| `itinerary.json` | 是 | 默认行程（逐日安排）和默认预算 | 今日、行程、预算 |
| `preparation.json` | 是 | 行前准备清单 | 行囊 › 清单；今日页按日期提醒 |
| `dining.json` | 否 | 餐厅目录、菜单、订位观察、推荐与选餐指南 | 探索 › 餐饮；行程中的用餐 |
| `hotels.json` | 否 | 酒店备选与报价快照 | 探索 › 酒店 |
| `locations.json` | 否（强烈建议） | 地点坐标 | 地图、路线、「在地图中打开」 |
| `photo-sources.json` | 否 | 地点实景照片及其许可 | 地点详情相册 |
| `posts.json` | 否 | 社交平台参考帖子（小红书等） | 地点详情、探索 › 攻略 |
| `phrases.json` | 否 | 旅行短句（可朗读） | 行囊 › 旅行短句 |
| `references.json` | 否 | 实用信息（交通卡、紧急电话等） | 行囊 |
| `flights.json` | 否 | 航班时刻 | 行囊 › 航班 |
| `media/` | 按需 | 上述文件引用的图片 | — |

构建：`python3 scripts/build_ios_resources.py` 把这些文件合并成 `ios/TripJournal/Resources/Content/catalog.json`，复制并缩放图片，生成 `manifest.json`（每个文件的大小与 SHA-256），并根据 `trip.json` 写出 `ios/Generated.xcconfig`（App 显示名称）。生成物都被 git 忽略。

## trip.json

```json
{
  "id": "kyoto-2027-autumn-v1",
  "appName": "京都三日",
  "tagline": "红叶季的三天京都 · 由 AI Agent 按官方来源调研",
  "destination": { "name": "京都", "nameEn": "Kyoto", "countryCode": "JP",
                   "addressSuffix": "Kyoto", "postcodePattern": "\\d{3}-\\d{4}" },
  "timezone": "Asia/Tokyo",
  "startDate": "2027-11-16", "endDate": "2027-11-18", "departureDate": "2027-11-15",
  "homeCity": "上海", "partySize": 2,
  "currency": { "local": "JPY", "home": "CNY", "localSymbol": "JP¥", "homeSymbol": "¥",
                "homePerLocal": 0.0426, "rateDate": "2026-09-24", "rateSource": "https://www.chinamoney.com.cn/chinese/bkccpr/" },
  "map": { "center": [35.0, 135.735], "span": [0.11, 0.14],
           "bounds": { "minLat": 34.93, "maxLat": 35.06, "minLon": 135.66, "maxLon": 135.81 } },
  "speech": { "language": "ja-JP", "label": "日语" },
  "attributions": [ { "label": "地点坐标：© OpenStreetMap contributors（ODbL）", "url": "https://www.openstreetmap.org/copyright" } ]
}
```

| 字段 | 说明 |
| --- | --- |
| `id` | 行程文档 ID。共享同步、备份导入都会核对它。换一次旅行就换一个 ID（例如 `kyoto-2031-v1`）。 |
| `appName` | 主屏幕显示名称、页面标题、通知标题、Live Activity 名称。 |
| `destination.name` / `nameEn` | 中文名 / 英文名，用于文案和地图搜索。 |
| `destination.countryCode` | ISO 3166-1 两位代码。地图搜索结果只接受这个国家/地区的结果。 |
| `destination.addressSuffix` | 追加到地图搜索词和「复制英文地址」末尾，通常是城市名。 |
| `destination.postcodePattern` | 可选，英文地址中邮编的正则，例如日本 `\\d{3}-\\d{4}`。 |
| `timezone` | IANA 时区名。App 里所有行程时间都按这个时区解释，与手机当前时区无关。 |
| `startDate` / `endDate` | 行程第一天和最后一天。天数由它们推出（1–60 天），`itinerary.json` 必须逐日对应。 |
| `departureDate` | 离家的日期。红眼航班可能早于 `startDate`；倒计时和酒店入住日期允许从这一天开始。 |
| `homeCity` | 出发城市，只用于行囊页标题「从 X，到 Y」。不想写可以填「家」。 |
| `partySize` | 同行人数。门票、订位的默认人数；餐厅订位观察必须按这个人数查询。 |
| `currency` | `local` 目的地货币、`home` 母国货币（ISO 4217）。`homePerLocal` = 1 单位当地货币折合多少母国货币，必须带取数日期和来源。 |
| `map.center` / `span` | 地图默认中心与范围（纬度、经度）。 |
| `map.bounds` | 目的地的合法坐标范围。所有坐标都必须落在里面；地图搜索和路线结果也用它过滤。不要画得太大，否则邻国同名地点会混进来。 |
| `speech.language` | 旅行短句朗读语言（BCP-47，如 `en-US`、`ja-JP`、`ko-KR`、`th-TH`）；`label` 是界面上的语言名。 |
| `attributions` | 关于页显示的数据来源与许可证（地图、照片、官方数据等）。 |

## places.json

```json
{ "places": [ {
  "id": "harbor-light", "name": "港湾灯塔", "en": "Harbor Lighthouse",
  "zone": "北岸", "kind": "地标", "hours": 1, "budget": 0,
  "desc": "为什么值得去", "tip": "怎么玩最好（可执行的动作与时间段）",
  "travel": "怎么到", "rain": "下雨怎么办", "food": "附近吃什么",
  "link": "https://官方页面", "opening": "开放时间（带核对说明）", "price": "官方票价 / 规划预算",
  "bestTime": "建议时段｜理由",
  "guides": [ … ],
  "sources": [ { "label": "官方页面", "url": "https://…" } ], "checkedAt": "2030-04-01"
} ] }
```

| 字段 | 说明 |
| --- | --- |
| `zone` | 区域名，用于分组和行程编排（同区域聚类）。 |
| `kind` | 类型文字，任意，例如 地标 / 博物馆 / 街区 / 观景 / 自然 / 主题乐园。**`餐饮` 是保留值**，由 `dining.json` 自动生成，不要手写。 |
| `hours` | 建议停留小时数（行程未指定时长时用它）。 |
| `budget` | 每人门票规划预算，当地货币。免费填 0。 |
| `opening` vs `bestTime` | 开放时间是运营方的事实；建议时段是你的规划判断。两者分开写。 |
| `price` | 写清是「官方价」还是「规划预算（留余量）」，不要混在一起。 |
| `guides` | 可选，深度攻略：`{id, title, summary, updatedAt, sections:[{title, paragraphs[]}], links:[{label,url}]}`。 |
| `sources` / `checkedAt` | 构建时不进入 App，但 `verify_content.py` 要求每个地点都有。 |

## itinerary.json

```json
{
  "days": [ { "date": "2030-05-01", "title": "抵达与北岸", "area": "北岸 → 老城", "note": "当天说明",
              "items": [ { "uid": "d1-museum", "place": "maritime-museum", "time": "11:00",
                           "note": "", "durationMinutes": 120 } ] } ],
  "budget": { "flightOut": 0, "flightReturn": 0, "hotel": 600, "food": 300, "transport": 80, "other": 0 }
}
```

- `days` 必须与 `trip.json` 的日期逐日一一对应。
- `uid` 在整份行程中唯一，**发布后不要改**（共享同步用它合并两台手机的修改）。
- `place` 可以是 `places.json` 或 `dining.json` 里的任何 ID。
- `time` 可为空字符串（时间待定）；`durationMinutes` 可省略（使用地点的 `hours`），填写时必须有 `time`。
- `budget` 是**全程总额**：`flightOut`、`flightReturn` 用母国货币，其余用当地货币。用户可以在 App 里修改。

## preparation.json

```json
{ "items": [ { "id": "arrival-card", "group": "出发前 3 天", "dueDate": "2030-04-27",
               "title": "电子入境卡", "summary": "一句话",
               "body": ["怎么做……", "完成标准：……"],
               "copy": "可一键复制的模板（可选）",
               "links": [ { "label": "官方页面", "url": "https://…" } ],
               "guideImage": "media/preparation/xxx.jpg" } ] }
```

- `group` 按「什么时候做」分组（现在确认 / 出发前 3 天 / 出发当天打包 / 出门前 / 当地注意 / 返程前一晚……），App 按出现顺序显示。
- `dueDate` 可选：到这一天，今日页才开始提醒这一项；省略表示随时可做。
- `body` 每段一句话以上，最后一段写**完成标准**。
- 不要写证件号、订单号、手机号等个人信息（校验脚本会拦截疑似护照号）。

## dining.json

结构与示例见 `content/dining.json`，要点：

| 字段 | 取值 |
| --- | --- |
| `currency` | 必须等于 `trip.currency.local` |
| `directory` | 完整性锚点：`{edition, status, sourceURL, notes, counts?}`；`status` 为 `verified / partial / unverified`（示例可用 `sample`）；有星级时 `counts` 写官方名单中各星级数量，校验会逐项对数 |
| `restaurants[].type` | `restaurant / foodCourt / stall / casual` |
| `restaurants[].depth` | `detailed`（完整菜单与订位）/ `light`（基本信息）/ `directory`（只在目录中） |
| `award.kind` | `stars / bibGourmand / selected / none / unverified`；非 none 时 `year` 必须等于 `directory.edition` 且带来源 |
| `menus[].meal` | `breakfast / lunch / dinner / snack / allDay / both / any` |
| `menus[].basis` | `perPerson / estimate / perDish / perSet / perTable / marketPrice` |
| `menus[].tax` | `nett`（含税服务费）/ `++`（另加）/ `unknown`；写了 `serviceChargePercent` 或 `taxPercent` 时必须是 `++` |
| `menus[].price` | 可为 null，但名称或说明里要写明「未核实」还是「未公布」 |
| `pricingStatus` | `verified / estimate / unverified / unknown / notPublished` |
| `booking.availability` | `notChecked / unknown / notRequired / walkIn / available / full / soldOut`；`available/full/soldOut` 必须附 `observations` |
| `booking.observations[]` | `{date, meal, partySize, status, detail, checkedAt, sourceURL}`；`date` 在行程内，`partySize` 等于 `trip.partySize`；`status` 取 `available / full / soldOut / waitlist / closed / notReleased / notChecked / unknown / blocked`；这是**查询快照**，不能写成实时或保证有位 |
| `closedWeekdays` | ISO 星期：1=周一 … 7=周日 |
| `recommendations[]` | `{id, title, day（从 0 开始的行程天序号）, meal, restaurantIDs, reason}` |
| `guides[]` | `{id, title, summary, body[], restaurantIDs, sources[]}` |

每家餐厅会自动变成一个 `kind: "餐饮"` 的地点，可以直接放进行程；坐标写在 `coordinates` 里即可，不必再写进 `locations.json`。

## hotels.json

- 顶层：`checkIn`、`checkOut`、`adults`、`rooms`、`currency`（报价货币，一般是母国货币）和 `hotels[]`。
- 每家酒店：`id, name, en, region, reason, notice, rating, address, coords [lat, lon], coordinateSource, source, checkedAt, policies[], transport[], photo {file, source}, rooms[], tier`。
- `rooms[].quote`：`{status, totalHome?, breakfast, cancel, confirmation, extraFees}`；`status` 为 `available / pending / unavailable`；`totalHome` 是**整段入住总价**（母国货币），不是每晚价 × 晚数。带条件的优惠标 `pending`，不写 `totalHome`。
- 有无窗、装修等问题写进 `notice`，App 会醒目显示。

## locations.json

```json
{ "attribution": "© OpenStreetMap contributors", "license": "ODbL-1.0", "checkedAt": "…",
  "locations": { "harbor-light": { "name": "Harbor Lighthouse", "address": "…",
                                   "coordinates": [20.018, -150.03], "source": "https://www.openstreetmap.org/way/…" } } }
```

坐标是参考点，不保证是入口；必须在 `trip.map.bounds` 内。英文 `name` / `address` 会用于「复制英文地址」给司机或打车软件。

## photo-sources.json

```json
{ "albums": { "harbor-light": { "photos": [ {
  "file": "media/photos/harbor-light-1.jpg", "caption": "说明", "sourceUrl": "https://commons.wikimedia.org/…",
  "creator": "作者", "license": "CC BY-SA 4.0", "licenseUrl": "https://…", "date": "拍摄日期",
  "downloadUrl": "https://upload.wikimedia.org/…（可选，供 build_photos.py 下载）" } ] } } }
```

`scripts/build_photos.py --download-missing` 会下载带 `downloadUrl` 的原图（缓存目录不入库），压缩到最长边 1200 px、180 KB 以内并去掉元数据，写到 `file`。第一张图同时生成封面缩略图。

## posts.json

```json
{ "posts": [ { "id": "…", "platform": "xiaohongshu", "title": "…", "author": "…", "date": "平台显示的日期",
               "heat": "点赞/收藏快照", "url": "https://…", "capturedAt": "2030-04-01",
               "categories": ["整体" | "目的地" | "拍照" | "酒店" | …], "summary": "你自己写的摘要",
               "body": "原文（仅在获得授权时）", "images": [ { "file": "media/posts/<id>/01.jpg", "order": 1 } ],
               "guidePlaces": ["harbor-light"] } ] }
```

- `platform` 为 `xiaohongshu` 时，App 会尝试用小红书 App 打开原帖（`xhsdiscover://item/<noteId>`），失败再用浏览器。
- **版权**：公开仓库不要放未经授权的原帖图片和正文。自用私有分支可以保存，但要保留作者、链接和采集日期。
- `images` 至少一张（可以是你自己拍的或自绘的封面）；`order` 从 1 连续编号。

## phrases.json

```json
{ "sections": [ { "id": "restaurant", "title": "餐厅",
                  "items": [ { "native": "请结账。", "local": "お会計をお願いします。", "note": "当地用法说明（可选）" } ] } ] }
```

`local` 是会被朗读的目的地语言原文，朗读语言由 `trip.speech.language` 决定。

## references.json / flights.json

- `references`：`[{id, title, body, links:[{label,url}]}]`，放交通卡、紧急电话、退税等实用信息。
- `flights`：`[{id, number, from, to, departure, arrival}]`，时间写**各自机场的当地时间**。只写航班号和时刻，不写订单号、票号、座位或票价。

## 校验与构建命令

```bash
python3 scripts/verify_content.py                    # 结构、引用、坐标、日期、枚举、来源
python3 scripts/build_ios_resources.py               # 生成 App 内容
python3 scripts/verify_content.py --built-catalog    # 确认生成物是最新的
python3 scripts/verify_content.py --require-complete # 真实旅行的发布门禁：不允许示例文字、example.com、待核实/TODO
```
