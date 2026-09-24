# 可选后端：自建共享同步、路线与互动推送

App 不需要后端也能完整使用。只有下面这些功能需要它：

| 功能 | 需要的组件 |
| --- | --- |
| 两部（或多部）手机共享同一份行程、门票原件同步 | `server/trip_server.py` + Nginx（HTTPS） |
| 全天路线（步行 / 驾车路线、地点搜索、英文地址共享） | 上面 + Valhalla 路网与 OSM 地点索引 |
| 同行人互动（「戳一下」、爱心推送） | 上面 + `server/touch_push.py` + APNs 密钥 |

接口、表结构与同步模型见 [architecture.md](architecture.md)；命令与环境变量的速查表见 `server/README.md`。

## 1. 先在本机跑起来

```bash
python3 scripts/build_ios_resources.py
python3 server/trip_server.py init --data-dir /tmp/trip-dev
TRIP_NATIVE_KEY_SHA256=$(printf %s tttttttttttttttttttttttttttttttttttttttttttttttt | shasum -a 256 | cut -d' ' -f1) \
  python3 server/trip_server.py serve --data-dir /tmp/trip-dev --port 8765
curl -s http://127.0.0.1:8765/healthz
```

iOS 集成测试：在 Xcode 测试 scheme 里设置环境变量 `TRIP_INTEGRATION_URL=http://127.0.0.1:8765/`。Debug 构建检测到指向本机的地址时会使用 48 个 `t` 作为测试密钥；只接受 `127.0.0.1` / `localhost`，**绝不让写入型测试连接真实服务**。

## 2. 服务器准备

一台能跑 Python 3.10+ 的 Linux 服务器（systemd、Nginx、已有 HTTPS 证书的域名）。后端只监听 `127.0.0.1`，由 Nginx 反向代理。

```bash
sudo useradd --system --home /var/lib/trip-journal --shell /usr/sbin/nologin trip-journal
sudo install -d -o trip-journal -g trip-journal -m 700 /var/lib/trip-journal
sudo install -d -m 755 /opt/trip-journal
# 上传：server/ 目录，以及本机生成的 ios/TripJournal/Resources/Content/catalog.json → /opt/trip-journal/catalog.json
```

## 3. 生成共享密钥

```bash
key=$(openssl rand -base64 36 | tr '+/' '-_' | tr -d '=')
printf %s "$key" | shasum -a 256     # Linux 用 sha256sum
```

- `$key` 写进本机的 `ios/SharedAccess.xcconfig`（`TRIP_SHARED_ACCESS_KEY`），随 App 构建一起分发给你的测试员。
- 64 位十六进制哈希写进服务器 `/etc/trip-journal.env` 的 `TRIP_NATIVE_KEY_SHA256`。服务器只存哈希。
- 这是「安装级」密钥：持有这个 App 构建的人都能访问这份共享行程。只通过 TestFlight 分发给同行人。

## 4. 配置与启动

1. 复制 `deploy/trip-server.env.example` 为 `/etc/trip-journal.env`（`chmod 600`），逐项填写：
   - `TRIP_ORIGIN`：App 请求时的来源，例如 `https://trip.example.com`；
   - `TRIP_COOKIE_PATH`：随机路径，例如 `/onetrip/<随机串>/`；
   - `TRIP_NATIVE_KEY_SHA256`、`TRIP_CATALOG=/opt/trip-journal/catalog.json`。
2. 初始化数据库（用目录里的默认行程；已存在时拒绝覆盖）：

   ```bash
   sudo -u trip-journal TRIP_CATALOG=/opt/trip-journal/catalog.json \
     python3 /opt/trip-journal/server/trip_server.py init --data-dir /var/lib/trip-journal
   ```

3. 安装 systemd 单元：`deploy/trip-journal.service`、`trip-journal-backup.service`、`trip-journal-backup.timer`（每日备份），然后 `sudo systemctl enable --now trip-journal.service trip-journal-backup.timer`。
4. Nginx：参考 `deploy/nginx-location.example.conf`，在 HTTPS 的 `server {}` 里加一段 `location ^~ /onetrip/<随机串>/`（限流、`client_max_body_size 12m`、`proxy_pass http://127.0.0.1:8765/`），`nginx -t` 后 reload。改 Nginx 配置前先备份原文件。
5. App 侧：`ios/SharedAccess.xcconfig` 中

   ```
   TRIP_SERVER_URL = https:/$()/trip.example.com/onetrip/<随机串>/
   TRIP_SHARED_ACCESS_KEY = <$key>
   ```

   （xcconfig 里 `//` 是注释，所以要写成 `https:/$()/`。）重新构建 App。

**验证**：`curl https://trip.example.com/onetrip/<随机串>/healthz` 返回 `{"ok":true}`；两台设备分别修改同一天的不同安排，几秒内互相可见。

服务器启动时会核对数据库中的行程 ID 与 `catalog.json` 的 `trip.id` 一致；换一次旅行请换新的数据目录重新 `init`。

## 5. App 审核用的隔离数据库（可选）

TestFlight 外部测试需要苹果审核时，审核员也会打开 App。可以给审核员一个**不同的**密钥，指向一份独立的演示数据库，避免他们看到或改动你的真实行程：

```bash
sudo -u trip-journal python3 /opt/trip-journal/server/trip_server.py init --db /var/lib/trip-journal/review.sqlite3
# /etc/trip-journal.env：TRIP_REVIEW_DB=…/review.sqlite3，TRIP_REVIEW_KEY_SHA256=<审核密钥的哈希>
```

两个密钥的哈希相同时服务器拒绝启动。

## 6. 全天路线（可选）

1. 选区域数据：路网用覆盖行程范围的 OSM 提取（Geofabrik / BBBike 等），行政区与地点搜索用包含**完整国界**的提取。
2. 用 Valhalla 构建路网（tiles、admins 数据库），准备 pyvalhalla 3.8.3 Linux wheel（服务器不需要安装 Python 包）。
3. 地点索引：

   ```bash
   python3 scripts/build_route_places.py region.osm.pbf places-region.json --country <ISO两位代码> --native-name name:zh
   ```

   只保留 `trip.json` 范围内、并且在该国国界内的地点，避免邻国同名地点混入。
4. 打包与安装（所有文件带哈希，安装为不可变版本目录，`--activate` 原子切换，保留上一版用于回滚）：

   ```bash
   python3 deploy/build_route_artifact.py --probe probe --output artifact \
     --routing-pbf-url <提取的 URL> --bounds <minLat,maxLat,minLon,maxLon> --drive-on-left|--drive-on-right --snapshot-date <日期>
   python3 deploy/install_route_artifact.py …   # 见 --help
   ```

5. 默认路线目录 `/opt/trip-journal/routes/current`（`TRIP_ROUTE_ROOT`）。
6. 英文地址共享（`TRIP_ROUTE_ENGLISH_ADDRESS_SHARING`）：等所有手机都装上支持它的 App 版本后再设为 `1`，否则旧版本会因为不认识新字段而拒绝同步。

实测参考：单条路线通常不到 1 秒，内存占用在一两百 MiB 量级。算不出的路段会如实标注「部分计算」，不画假直线。

## 7. 同行人互动推送（可选）

1. Apple Developer → Keys：新建 APNs 认证密钥，下载 `.p8`（只能下载一次）。放到服务器，只有 `trip-journal` 用户可读。**永远不要提交到仓库。**
2. App ID 开启 Push Notifications；`project.yml` 已按 Debug / Release 设置 `aps-environment`。
3. 推送进程的依赖：

   ```bash
   python3 -m venv /opt/trip-journal/.venv-touch
   /opt/trip-journal/.venv-touch/bin/pip install -r /opt/trip-journal/server/requirements-touch.txt
   ```

4. 复制 `deploy/trip-touch.env.example` 为 `/etc/trip-journal-touch.env`（团队 ID、密钥 ID、`.p8` 路径、`TOUCH_APNS_TOPIC` = App 的 Bundle ID），启用 `deploy/trip-journal-touch-push.service`。
5. 配对需要邀请码：第一台设备生成邀请码，第二台输入并确认。这样可以避免外部测试的审核设备抢占配对名额（真实踩过的坑）。需要重置时：`trip_server.py reset-touch`（只清配对，不动行程）。

「APNs 已接受」只代表苹果收下了请求，不代表对方手机已经响了；在 App 的诊断页可以看到每条事件的状态。

## 8. 发布更新（只换代码，不碰数据）

`deploy/publish.py` 提供一个可审计的发布流程：

```bash
# 服务器：记录当前线上文件的哈希
python3 deploy/publish.py hashes --root /opt/trip-journal > base.json
# 本机：按白名单打包，生成 manifest，记下它的 SHA-256
python3 deploy/publish.py bundle --source . --base base.json --output release/
# 上传 release/ 到服务器，先演练再执行
python3 deploy/publish.py publish --bundle release --expected-manifest <sha256> --dry-run
python3 deploy/publish.py publish --bundle release --expected-manifest <sha256>
```

`publish` 会：核对上传文件与 manifest、核对线上文件仍是打包时的基线（防止并行发布互相覆盖）、备份所有数据库并比对指纹、停服务、原子替换文件、重启、轮询 `/healthz`；失败时**只回滚这次替换的代码，绝不回滚数据库**，遇到被别人改过的文件会停下并报告，而不是覆盖。

## 9. 旅行结束后

1. `systemctl stop` 并 `disable` 三个单元；对数据库做一次 WAL checkpoint 和完整性检查。
2. 打包 `/var/lib/trip-journal`、`/opt/trip-journal`（可不含路网）、`/etc/trip-journal*.env`、`.p8`、systemd 单元与 Nginx 片段，下载到本机并核对 SHA-256。
3. 删除 Nginx 中的 `location` 段（先备份），`nginx -t` 后 reload，确认公网路径已返回 404。
4. 在 Apple Developer 撤销 APNs 密钥。
5. 服务器上的数据保留还是删除，由你决定；备份包含密钥，只存放在私密位置。
