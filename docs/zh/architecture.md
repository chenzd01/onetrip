# 架构

本文说明 App 的模块划分、数据流、离线与同步模型，以及可选后端。字段级说明见 [content-schema.md](content-schema.md)，后端部署见 [backend.md](backend.md)。

## 总览

```
content/*.json + content/media/          （你维护的唯一内容源）
        │  scripts/verify_content.py      结构 / 引用 / 坐标 / 日期 / 来源校验
        ▼  scripts/build_ios_resources.py
ios/TripJournal/Resources/Content/       （生成，git 忽略）
  catalog.json  trip.json  place-locations.json  media/…  manifest.json
ios/Generated.xcconfig                   （App 显示名称）
        │  xcodegen + xcodebuild
        ▼
TripJournal.app ──────────────► TripWidgets.appex（读取 trip.json 与 App Group 中的 schedule.json）
   │  本机：Application Support/TripWorkspace/workspace.json（行程、基线、修订号、待同步标记）
   │
   └── 可选：HTTPS ──► server/trip_server.py（共享行程、附件、路线偏好、路线计算、同行人互动）
                              ├─ SQLite（WAL）
                              ├─ route_engine.py → valhalla_service（自建路网）
                              └─ touch_push.py（独立进程，APNs）
```

设计原则：

1. **内容与代码分离**：换目的地只改 `content/`。Swift 代码里没有城市名、日期、货币或坐标，全部来自 `trip.json`（`TripConfig`）和 `catalog.json`（`ContentCatalog`）。
2. **离线优先**：所有内容打包进 App；地点坐标内置，不依赖出行时的地理编码（实践中曾遇到地图服务对境外区域不可用的情况，见 [lessons-learned.md](lessons-learned.md)）。
3. **本机优先、同步可选**：每次修改先原子写入本机文件，再尝试同步；没有后端时 App 完整可用。
4. **内容更新不改用户数据**：新构建带来的默认行程只在用户从未修改过时生效；用户保存过的行程、打勾状态、收藏不会被覆盖。
5. **不编造、显示不确定性**：内容里的「待确认 / 快照 / 估算」会在界面上用颜色 + 图标 + 文字明确标出。

## iOS 工程

- 工程由 `ios/project.yml`（XcodeGen）生成；`.xcodeproj` 不入库。工程与 target 名 `TripJournal` 是内部代号，项目对外名称是 OneTrip · 一程；App 在手机上显示的名字来自 `trip.json` 的 `appName`。
- iOS 26+，仅 iPhone，Swift 6，严格并发检查（`SWIFT_STRICT_CONCURRENCY: complete`）。
- 三个 target：

| Target | 内容 |
| --- | --- |
| `TripJournal` | App 本体；资源为生成的 `Resources/Content`（文件夹引用）与 `Assets.xcassets` |
| `TripWidgets` | WidgetKit 小组件 + Live Activity；编译 `TripJournal/Shared`，资源只带 `trip.json` |
| `TripJournalTests` | 单元测试与可选的本地 HTTP 集成测试 |

- 构建配置：`App.xcconfig` → `Generated.xcconfig`（显示名）→ `Signing.xcconfig`（Team、Bundle ID，必需、忽略）→ `SharedAccess.xcconfig`（后端地址与共享密钥，可选、忽略）。
- 由 Bundle ID 推导：Widget `<id>.widgets`、App Group `group.<id>`、Keychain 服务名、日志 subsystem（见 `Shared/TripConfig.swift` 的 `AppIdentity`）。

### 目录与模块

| 路径 | 职责 |
| --- | --- |
| `App/TripJournalApp.swift` | 入口与四个页签：今日、行程、探索、行囊；同步入口；（有后端时）同行人互动悬浮球 |
| `App/Design.swift` | 配色、字体、图片加载 |
| `Shared/TripConfig.swift` | 目的地配置 `TripConfig.current`、`AppIdentity`（App 与 Widget 共用） |
| `Shared/TripClock.swift` | 按目的地时区解释所有时间；Widget 快照与日程时间线 |
| `Core/Models.swift` | 内容模型与行程文档 `TripPlan`（天、安排、自定义地点、清单、预算、住宿、门票） |
| `Core/TripStore.swift` | 主状态：本机保存、撤销、同步循环、三方合并、Widget / 提醒 / Live Activity 刷新、备份 |
| `Core/TripAPI.swift` | 后端传输（`TripService` 协议）、Keychain 凭据 |
| `Core/PlanMerge.swift` | 通用 JSON 三方合并与冲突列表 |
| `Core/PlanValidation.swift` | 行程文档校验（日期、ID、数量、格式），与后端校验一致 |
| `Core/AttachmentStore.swift` | 门票原件（按 SHA-256 存储） |
| `Core/Dining.swift` | 餐饮模型、用餐与预约、休息日与时间冲突提示 |
| `Core/BudgetCalculator.swift` | 两种货币的预算行与编辑草稿 |
| `Core/DestinationMaps.swift` | 地图区域、坐标范围校验、地图搜索、打开系统地图 |
| `Core/DayRoute*.swift`、`RoutePreferenceStore.swift`、`RouteEnglishAddress.swift` | 全天路线（需要后端）、路线偏好同步、复制英文地址 |
| `Core/Touch*.swift` | 同行人互动：配对、事件、推送（需要后端） |
| `Core/ReminderController.swift`、`LiveActivityController.swift` | 本地通知、实时活动 |
| `Core/PhraseSpeechPlayer.swift` | 旅行短句朗读（系统语音，语言来自 `trip.speech.language`） |
| `Core/ExternalLinks.swift` | 外链处理（含小红书原帖 deep link） |
| `Features/*` | 各页面视图 |

### 内容加载

`ContentCatalog.load()` 从 App 包内 `Content/catalog.json` 解码；图片路径相对于 `Content/`。`manifest.json` 记录每个文件的字节数与 SHA-256，测试会逐一核对，行囊页也会显示离线内容完整性。

### 行程文档与本机存储

`TripPlan` 是会被同步的唯一文档：

```
{ version, id, days:[{date,title,area,note,items:[Stop]}], custom:[Place], checks:{id:Bool},
  budget:{flightOut, flightReturn, hotel, food, transport, other},
  hotelFavorites:[id], stays:[Stay], tickets:{placeID:[Ticket]} }
```

本机文件（`Application Support/TripWorkspace/`）：

| 文件 | 内容 |
| --- | --- |
| `workspace.json` | `{plan, base, revision, pending}`：当前行程、上次同步的基线、服务器修订号、是否有待同步修改 |
| `ticket-drafts.json` | 未完成的门票草稿 |
| `route-preferences.json` | 路线偏好（单独同步） |
| `Attachments/` | 门票原件 |

写入全部是原子写，并使用文件保护。App Group 容器中的 `schedule.json` 只含公开的地点名与时间，供 Widget 读取，不含备注、订单或票号。

### 同步模型（有后端时）

1. 用安装级共享密钥换取会话 cookie（`POST api/native-session`），再取 CSRF（`GET api/session`）。
2. 前台约每 3 秒轮询 `GET api/plan?since=<revision>`：无变化返回 204。
3. 本机有修改时 `PUT api/plan {revision, state, device}`；服务器按修订号做比较并交换（CAS），冲突返回 409 与最新版本。
4. 客户端以「上次同步的基线」为共同祖先做**三方合并**：两端改了不同字段自动合并；改了同一字段时，界面并排显示「本机 / 共享」让用户选择。
5. 第一次编辑时冻结基线，避免新构建里的默认内容被误认为用户修改。
6. 不认识的新字段一律拒绝写入（fail closed），并提示更新 App，绝不覆盖共享内容。
7. 表单打开时暂停同步；连接失败指数退避（最长 60 秒），修改始终保存在本机。

没有配置后端时：同步入口显示「仅本机」，不轮询、不报错；路线和同行人互动入口隐藏或提示需要自建后端。

### Widget 与 Live Activity

App 每次修改后写 `schedule.json` 并刷新时间线；Widget 根据当前时间显示「还有几天出发 / 接下来 / 今天的完整安排 / 旅行结束」。Live Activity 在前台手动开始、按时间线更新，不使用推送。

## 后端（可选）

`server/` 只依赖 Python 标准库（推送进程另需 `httpx[http2]` 与 `PyJWT[crypto]`），数据在 SQLite（WAL 模式，文件权限 0600）。详见 [backend.md](backend.md)。

### 接口一览

| 接口 | 鉴权 | 说明 |
| --- | --- | --- |
| `GET /healthz` | 无 | 健康检查 |
| `POST /api/native-session` | Origin | 安装级共享密钥（服务器只存 SHA-256）换会话 |
| `GET /api/session` | cookie | CSRF 与过期时间 |
| `GET /api/plan?since=N` | cookie | 204 或 `{revision, state, updatedAt}` |
| `PUT /api/plan` | cookie + Origin + CSRF | 修订号 CAS；409 返回最新版本；校验引用的附件存在 |
| `POST /api/attachments`、`GET /api/attachments/<sha256>` | 同上 | JPEG/PNG/WebP/PDF，按内容寻址，单个 ≤10 MiB |
| `GET/PUT /api/route-preferences` | 同上 | 路线偏好文档，同样的 CAS 语义 |
| `GET /api/route-address-status` | cookie | 英文地址共享的功能开关 |
| `POST /api/routes` | 同上 | 步行 / 驾车路线，返回编码折线 |
| `GET /api/route-places?query=` | cookie | 基于 OpenStreetMap 的地点搜索 |
| `/api/touch/*` | 同上 + 设备密钥 | 同行人配对（邀请码）、事件、推送状态 |

### 数据表

`trip`（单行行程文档与修订号）、`revisions`（最近约 100 个版本）、`sessions`（令牌只存哈希）、`attempts`（限流）、`attachments`、`route_preferences`、`touch_*`（成员、配对、邀请、事件、推送队列、限流）。新功能只新增表；`init` 拒绝覆盖已有数据库。

### 推送（同行人互动）

独立的 `touch_push.py` 进程每秒领取待发送事件：ES256 JWT、HTTP/2、只在 429/500/503 时重试（最多 5 次，指数退避，遵守 Retry-After）；进程在发送中途崩溃的事件标为「不确定」且**不重发**，避免重复提醒。「APNs 已接受」不等于「手机已响」。

### 路线

`route_engine.py` 以子进程调用 `valhalla_service`（信号量 2、超时 12 秒），坐标只在目的地范围内吸附（≤100 米）；算不出的路段如实标注，绝不画假直线。路网与地点索引由 `deploy/build_route_artifact.py`、`scripts/build_route_places.py` 从 OpenStreetMap 区域数据构建，发布为不可变版本目录并原子切换。

## 测试

| 范围 | 命令 |
| --- | --- |
| 内容管线 | `python3 -m unittest discover -s scripts -p 'test_*.py'` |
| 后端 | `python3 -m unittest discover -s server -p 'test_*.py'` |
| 部署脚本 | `python3 -m unittest discover -s deploy -p 'test_*.py'` |
| 截图 | `python3 scripts/make_screenshots.py`（`TripJournalUITests` 中的 UI 测试，只由 `Screenshots` scheme 运行；App 时钟用仅 Debug 生效的 `-TripNow` 启动参数冻结） |
| iOS | `xcodebuild test …`（`HTTPIntegrationTests` 需要设置 `TRIP_INTEGRATION_URL` 指向本机测试服务，只接受 127.0.0.1 / localhost，未设置时自动跳过） |

**写入型测试永远不要连接真实服务。**
