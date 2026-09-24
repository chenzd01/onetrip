# iOS 构建与 TestFlight 发布

本文说明怎样把填好内容的模板构建成 App，并通过 TestFlight 发给同行的人。流程来自一次真实旅行的实战项目。踩过的坑见 [lessons-learned.md](lessons-learned.md)，每次发布的记录模板见 [release-record.md](../templates/release-record.md)。

> 文中的 `<...>` 都是占位符。命令默认在仓库根目录执行。不要把 Team ID、证书、APNs 密钥、共享访问密钥、个人路径写进仓库或发布记录。

---

## 1. 准备

| 需要 | 说明 |
| --- | --- |
| macOS + Xcode 26 或更新 | 工程最低部署目标是 iOS 26.0，仅 iPhone |
| XcodeGen | `brew install xcodegen` |
| Python 3 + Pillow | 生成内置资源、处理图片：`python3 -m pip install Pillow` |
| Apple Developer 付费账号 | 模拟器开发可以不用；真机安装和 TestFlight 需要 |
| 足够的磁盘空间 | 归档、DerivedData、模拟器会占用大量空间，建议预留 20 GB 以上；空间紧张时把构建产物放到外置盘（见 lessons-learned.md） |

---

## 2. 工程是生成出来的

仓库**不提交** `.xcodeproj`。工程定义在 `ios/project.yml`，由 XcodeGen 生成。原因：生成的工程会写入 Team ID；如果提交工程文件，机器之间的签名差异会混进提交，还可能在空 Team 下被重写（见 lessons-learned.md 第一节第 2 条）。

每次拉取代码、增删 Swift 文件、改了 `project.yml` 之后，都按下面的顺序重新生成：

```sh
# 1. 校验内容（结构门禁）
python3 scripts/verify_content.py

# 2. 从 content/ 生成 App 内置资源和 ios/Generated.xcconfig
python3 scripts/build_ios_resources.py

# 3. 确认生成物是最新的
python3 scripts/verify_content.py --built-catalog

# 4. 生成 Xcode 工程（输出 ios/TripJournal.xcodeproj）
xcodegen generate --spec ios/project.yml
```

`build_ios_resources.py` 必须在 `xcodegen` 之前运行，因为 `project.yml` 把 `ios/TripJournal/Resources/Content/` 作为资源目录引用，目录不存在时工程里就缺资源。它还会根据 `content/trip.json` 写出 `ios/Generated.xcconfig`（App 显示名）。

---

## 3. 签名配置

### 3.1 `ios/Signing.xcconfig`

从示例复制，这个文件不提交：

```sh
cp ios/Signing.example.xcconfig ios/Signing.xcconfig
```

| 键 | 值 |
| --- | --- |
| `DEVELOPMENT_TEAM` | 你的付费 Team ID。只跑模拟器可以留空；真机和归档必须填 |
| `APP_BUNDLE_ID` | 你拥有的反向域名，例如 `com.<你的域名>.<应用名>` |

由 `APP_BUNDLE_ID` 派生出：

| 用途 | 标识 |
| --- | --- |
| App | `<APP_BUNDLE_ID>` |
| Widget 扩展 | `<APP_BUNDLE_ID>.widgets` |
| App Group（App 与 Widget 共享数据） | `group.<APP_BUNDLE_ID>` |
| 单元测试 | `<APP_BUNDLE_ID>.tests` |

配置文件的加载顺序在 `ios/App.xcconfig`：先读默认值，再读 `Generated.xcconfig`、`Signing.xcconfig`（必需）、`SharedAccess.xcconfig`（可选）。

### 3.2 在 Apple Developer 后台注册

1. 注册 App ID：`<APP_BUNDLE_ID>`，勾选 App Groups。
2. 注册 App ID：`<APP_BUNDLE_ID>.widgets`，勾选 App Groups。
3. 注册 App Group：`group.<APP_BUNDLE_ID>`，并分配给上面两个 App ID。
4. 推送能力（Push Notifications）：
   - 模板的 `TripJournal.entitlements` 包含 `aps-environment`，值来自构建设置 `APNS_ENVIRONMENT`（Debug 为 `development`，Release 为 `production`）。
   - 使用自动签名并加 `-allowProvisioningUpdates` 时，Xcode 会按 entitlements 为 App ID 申请相应能力。
   - 只有部署了后端并使用“碰一下”互动时，才需要配置 APNs 签名密钥（`.p8`）。APNs 密钥和 App Store Connect API 密钥不是同一种东西，不能互换。密钥放在仓库外，只让推送 worker 账号可读。
   - 完全不部署后端时，App 离线可用；profile 与 entitlements 保持一致即可。

发布后不要再改 Bundle ID、App Group、钥匙串服务名和工作区路径，否则测试者原地更新后会丢失本机数据。

### 3.3 可选：`ios/SharedAccess.xcconfig`

只有部署了 `server/` 后端才需要。从 `ios/SharedAccess.example.xcconfig` 复制，填：

- `TRIP_SERVER_URL`：后端地址。注意 xcconfig 里 `//` 是注释，写成 `https:/$()/<你的域名>/onetrip/<随机路径>/`。
- `TRIP_SHARED_ACCESS_KEY`：32–256 位随机字符；服务端只保存它的 SHA-256（环境变量 `TRIP_NATIVE_KEY_SHA256`）。

这个密钥会编进 App，拿到安装包的人都能访问同一份共享行程，所以它是“安装级”的访问能力，不是个人身份。不要提交它，不要写进发布记录。

---

## 4. 本地开发与测试

```sh
# 查看可用的模拟器
xcrun simctl list devices available

# 构建并运行测试（把 <模拟器名> 换成上面列出的 iPhone 模拟器）
xcodebuild test \
  -project ios/TripJournal.xcodeproj -scheme TripJournal \
  -destination 'platform=iOS Simulator,name=<模拟器名>'
```

- 模拟器运行时保持默认的临时签名，钥匙串才能正常工作；不要用 `CODE_SIGNING_ALLOWED=NO` 做运行时验证。
- 真实 HTTP 集成测试需要一次性隔离的本机服务，并在测试运行环境设置 `TRIP_INTEGRATION_URL=http://127.0.0.1:<端口>/`；它只接受回环地址，否则跳过。永远不要指向生产。
- 区域路线的在线验收测试需要 `TRIP_LIVE_ROUTES=1`，常规运行跳过。
- 跳过的测试要单独计数，不能算作通过。

内容相关的 Python 测试：

```sh
python3 scripts/test_ios_resources.py
python3 -m unittest discover -s server -p 'test_*.py'     # 使用后端时
python3 -m unittest discover -s deploy -p 'test_*.py'     # 使用部署脚本时
```

---

## 5. 版本号

版本号在 `ios/project.yml` 顶层的 `settings.base`：

```yaml
MARKETING_VERSION: '1.0.0'       # 用户看到的版本
CURRENT_PROJECT_VERSION: '1'     # 构建号
```

- App 和 Widget 共享这两个值，所以天然同步。App 与扩展版本不一致会被 App Store Connect 拒绝。
- `ios/ExportOptions-TestFlight.plist` 设置了 `manageAppVersionAndBuildNumber = false`，导出时不会自动改构建号。
- **每次上传前把 `CURRENT_PROJECT_VERSION` 加 1。** 同一个营销版本下，被 Apple 接收过的构建号不能再用；上传结果不确定时也直接用新号，省得排查。
- 改完版本号要重新 `xcodegen generate`。

---

## 6. 发布前检查

每次归档前在干净的主干上执行，把精确结果写进发布记录：

- [ ] `python3 scripts/verify_content.py --require-complete` 通过（真实旅行）。
- [ ] `python3 scripts/build_ios_resources.py` 成功，`python3 scripts/verify_content.py --built-catalog` 通过。
- [ ] `ios/Signing.xcconfig` 是正式 Team 和正式 Bundle ID（不是模拟器用的空 Team），然后重新 `xcodegen generate`。
- [ ] 原生测试：记下通过、跳过、失败的精确数量，以及跳过的原因。
- [ ] 使用后端时：服务端、部署脚本测试的精确数量。
- [ ] `git status` 干净，发布源码已提交。
- [ ] 仓库公开时：`python3 scripts/privacy_check.py` 无发现（它会扫描密钥、个人路径、公网 IP、邮箱，以及 `.privacy-denylist` 里你自己列的私密字符串）。
- [ ] 磁盘剩余空间充足（`df -h`）。

---

## 7. 归档与上传

### 7.1 归档

```sh
BUILD=<构建号>
xcodebuild -project ios/TripJournal.xcodeproj -scheme TripJournal \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "ios/build/TripJournal-$BUILD.xcarchive" \
  -allowProvisioningUpdates archive
```

`-allowProvisioningUpdates` 允许 Xcode 用本机已登录的 Apple 账号自动创建或更新描述文件。

### 7.2 归档检查

```sh
APP="ios/build/TripJournal-$BUILD.xcarchive/Products/Applications/TripJournal.app"
WIDGET="$APP/PlugIns/TripWidgets.appex"

# 签名完整性
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --verify --deep --strict --verbose=2 "$WIDGET"

# 版本号：App 与 Widget 必须一致
/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' -c 'Print CFBundleVersion' "$APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' -c 'Print CFBundleVersion' "$WIDGET/Info.plist"

# Bundle ID、Team、App Group
codesign -d --entitlements :- "$APP"
codesign -d --entitlements :- "$WIDGET"

# 内置资源与生成目录逐文件一致（无输出即一致）
diff -rq ios/TripJournal/Resources/Content "$APP/Content"
```

核对：

- App 与 Widget 的营销版本、构建号一致，且是本次要发的号。
- entitlements 里的 Team 前缀、`application-groups` 是正式值。
- `Content/` 与生成目录一致（其中 `manifest.json` 记录了每个文件的长度和 SHA-256）。

### 7.3 上传

```sh
xcodebuild -exportArchive \
  -archivePath "ios/build/TripJournal-$BUILD.xcarchive" \
  -exportOptionsPlist ios/ExportOptions-TestFlight.plist \
  -exportPath "ios/build/upload-$BUILD" \
  -allowProvisioningUpdates
```

- `ExportOptions-TestFlight.plist` 的 `destination` 是 `upload`，这条命令会直接上传到 App Store Connect。只对检查通过的归档执行。
- plist 里**没有 `teamID`**，签名 Team 来自 `Signing.xcconfig` 和本机登录的账号，因此这个文件可以安全地提交。
- 成功的标志：输出里有 `Upload succeeded` 和 `EXPORT SUCCEEDED`，且退出码为 0。把这段输出存进本地日志（不进 git）。
- 上传很慢或中途断开：没有成功回执就视为没上传，换新构建号重新归档上传。不要并行跑两个上传。

### 7.4 检查分发包的生产 entitlement

归档本身通常是开发签名，里面的 `aps-environment` 不能作为生产证据。要确认分发签名后的 entitlement，另外导出一份 IPA（不上传）：

```sh
cp ios/ExportOptions-TestFlight.plist "ios/build/ExportOptions-IPA-$BUILD.plist"
plutil -replace destination -string export "ios/build/ExportOptions-IPA-$BUILD.plist"
xcodebuild -exportArchive \
  -archivePath "ios/build/TripJournal-$BUILD.xcarchive" \
  -exportOptionsPlist "ios/build/ExportOptions-IPA-$BUILD.plist" \
  -exportPath "ios/build/ipa-$BUILD" -allowProvisioningUpdates

cd "ios/build/ipa-$BUILD" && unzip -q -o *.ipa
codesign -d --entitlements :- Payload/TripJournal.app
```

期望：`aps-environment` 为 `production`（使用推送时），`get-task-allow` 为 `false`，Team 与 App Group 正确。

---

## 8. App Store Connect 与 TestFlight

### 8.1 创建 App 记录（只做一次）

在 App Store Connect →「App」→ 新建：平台 iOS、名称、主要语言、Bundle ID（选第 3.2 节注册的 `<APP_BUNDLE_ID>`）、SKU（自定义唯一字符串）。

`Info.plist` 里已经声明 `ITSAppUsesNonExemptEncryption = false`（只使用系统提供的传输加密），上传后不需要每次回答出口合规问题。如果你加入了自定义加密，要重新评估。

### 8.2 测试组

| 类型 | 谁 | 审核 | 适合 |
| --- | --- | --- | --- |
| 内部测试组 | App Store Connect 团队成员（需要账号角色） | 不需要 Beta 审核 | 你自己先装、先验收 |
| 外部测试组 | 任何人，用邮箱邀请（或公开链接） | 每个营销版本的第一个构建需要 Beta App Review | 同行的朋友 |

- 建议先建一个内部组给自己预览，确认没问题再加进外部组。
- 外部组用**邮箱定向邀请**，不要随手开公开链接。
- 不要为了加测试者而给别人扩大 App Store Connect 角色。

### 8.3 第一次外部提审

在 TestFlight →「测试信息」填写：

- Beta 版 App 描述、反馈邮箱。
- 联系人信息（姓名、电话、邮箱）——填在 App Store Connect 里，**不要写进仓库**。
- 审核说明（英文）：App 是做什么的、需要登录吗、离线内容在哪、有哪些入口。
- 如需演示账号：使用后端时，可以用 `server/trip_server.py serve --review-db <审核数据库>` 配合环境变量 `TRIP_REVIEW_KEY_SHA256`，让审核员进入一份独立的演示数据；演示数据只用公开的示例内容生成，附件明确标注“仅供演示”。**不要把真实行程或真实凭证交给审核**。

外部审核员会运行真实的发布包。任何“首次打开就占用资源”的功能（例如配对名额）都要假设审核员会点到（见 lessons-learned.md 第一节第 3 条）。

### 8.4 每个构建的分发

上传成功后：

1. 等 Apple 处理完成（构建状态从“处理中”变为可用）。
2. 在该构建的「测试内容」里填写本次更新说明（中文即可）。每次都写上：**“请在 TestFlight 里直接更新，不要卸载旧版本，否则本机草稿和票据会丢失。”**
3. 把构建加入内部组和外部组，提交时勾选 **Automatically notify testers**。
4. 分别打开每个测试组的 Builds 页面，确认本构建显示 **Testing** 和有效期。

规则与观察：

- **同一个营销版本同时只能有一个构建在 Beta 审核中。** 前一个还在审核时，后一个只能先发内部组，等前一个通过后再提交外部。
- 一个营销版本的首个构建通过外部审核后，后续构建提交外部组时常常直接进入 Testing，但这不是保证，以页面状态为准。
- 构建 90 天后过期。
- 分组请求偶尔失败，刷新页面后重试；浏览器会话过期时由用户重新登录，记录里写“最后确认的状态”。

### 8.5 状态阶梯

每一级都要单独确认、单独记录，不能跳级下结论：

```text
归档成功
  → 上传成功（Upload succeeded / EXPORT SUCCEEDED，退出码 0）
    → Apple 处理完成
      → 已加入测试组（内部 / 外部）
        → 外部审核通过（如需要）
          → 测试组 Builds 页面显示 Testing
            → 测试者页面显示“已安装 <本构建>”
              → 真机上实际验收通过
```

TestFlight 显示“已通知”不代表测试者收到了；测试者页面显示的已安装版本可能还是旧构建。

---

## 9. 发布记录

每个构建写一份发布记录，放在 `docs/releases/`（或你习惯的位置），从 [release-record.md](../templates/release-record.md) 复制。至少包含：

- 变更范围（用户能感知的变化）。
- 本地验证：精确的测试数量（通过 / 跳过 / 失败）和跳过原因。
- 后端：是否发布；发布了哪些文件；数据指纹前后是否一致。
- 归档与上传：版本号、签名检查结果、上传回执时间。
- TestFlight：处理状态、加入的组、是否需要审核、页面上确认到的状态。
- 未证明的边界：真机、通知送达、安装情况等还没验证的部分。
- 产物位置：只写相对仓库的路径或“本机产物目录”，不写个人绝对路径。

**不要在记录里写**：Team ID、App Store Connect 内部 ID、构建 UUID、证书和密钥、共享访问密钥、服务器地址与路径、测试者邮箱和电话、个人电脑路径。

---

## 10. 可选：后端

模板的 `server/` 提供共享行程同步、全天路线和“碰一下”互动；`deploy/` 提供 systemd 单元、备份定时器和窄范围发布脚本。App 在没有后端时完全离线可用。

部署后端时的原则（详见 lessons-learned.md）：

- 发布前用 SQLite 备份 API 做一致快照（`python3 server/trip_server.py backup --output <备份文件>`），并记录共享数据指纹。
- 只安装白名单内的文件，先 `--dry-run`，核对生产旧文件与预期基线一致。
- 发布后比对数据指纹、检查健康接口；健康接口正常不等于功能正常。
- 回滚只恢复本次代码，不用旧整库覆盖新数据。
- 新增共享数据类型时两阶段启用：先部署能读的服务端和 App，确认所有手机都装好兼容版本后再打开写入开关。
