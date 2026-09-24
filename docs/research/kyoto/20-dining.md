# 京都 3 日游餐饮调研记录（dining.json）

- 调研日期：2026-09-24（所有 `checkedAt` 均为当天实际读取的页面）
- 行程：2027-11-16（周二）至 2027-11-18（周四），2 人，货币 JPY，中文使用者
- 读取方式：gstack browse 无头浏览器（单独的 daemon，不与其他 agent 共用标签页）读取渲染后的页面；地理编码用 Nominatim / Overpass API（间隔 ≥2 秒，带 UA）。
- 只读：没有打开或查询任何预约系统（天龙寺预约表单、EPARK、Omakase 等都未打开），没有登录、没有提交表单、没有发消息。
- 校验：`dining-evidence/check_dining.py` 以只读方式导入模板的 `scripts/verify_content.py`，用京都行程参数（JPY、partySize 2、2027-11-16..18、lat 34.93–35.06 / lon 135.66–135.81）运行 `validate_dining`。结构校验与 `--require-complete` 等价校验都是 0 错误 0 警告，占位符检查通过，6 个地址都符合 `…, Kyoto ddd-dddd`。

## 1. 完整性锚点（directory）

| 项 | 结论 |
| --- | --- |
| 当前版本 | 《MICHELIN Guide Kyoto Osaka 2026》，2026-04-23 发布 |
| 官方发布文章里的京都数量 | 共 244 家：三星 6、二星 19、一星 73、必比登 47、入选 99；绿星 10 |
| 2026-09-24 动态目录（guide.michelin.com/jp/en/kyoto-region/kyoto/restaurants） | 249 家：三星 6、二星 19、一星 72、必比登 47、入选 105；6 页全部翻完，249 个名字存于 `dining-evidence/mich_all_names.txt` |
| 下一版 | 官方预告：2027 年版东京、京都大阪、奈良于 **2027-02-16** 同时公布，早于出行 |
| 写法 | `edition: 2026`，`status: partial`，**不写 `counts`** |

为什么不写 counts：`verify_content.py` 要求 `directory.counts` 与 `restaurants[]` 中 `award.kind == "stars"` 的数量逐项相等。本包只有 6 家日常预算餐厅（1 家必比登，0 家星级），如果写 `{"1":73,"2":19,"3":6}` 就会失败，除非把 98 家星级餐厅全部作为 `depth: directory` 收录。官方数字已经写进 `notes`。status 记为 partial，因为锚点数字已核实，但本包没有覆盖名单。

## 2. 来源表

置信度：高 = 运营方官网或官方机构页面，内容明确；中 = 官方但有缺口（未标日期、未写含税与否）；参考 = C 级（坐标、邮编）。

| # | URL | 确认了什么 | 置信度 |
| --- | --- | --- | --- |
| 1 | https://guide.michelin.com/jp/en/article/michelin-guide-ceremony/michelin-guide-kyoto-osaka-2026-stars-reveal | 2026 版 2026-04-23 发布；京都各级数量（见上表） | 高 |
| 2 | https://guide.michelin.com/jp/en/kyoto-region/kyoto/restaurants （含 /page/1..6、/bib-gourmand、/obanzai、/ramen） | 动态目录 249 家与各级分面数量；必比登 47 家名单；其余 5 家入选餐厅都不在名单里 | 高（目录快照） |
| 3 | https://guide.michelin.com/jp/en/article/news-and-views/michelin-guide-ceremony-tokyo-kyoto-osaka-nara-2027-selection-save-the-date | 2027 年版于 2027-02-16 公布（文章日期 2026-06-10） | 高 |
| 4 | https://guide.michelin.com/jp/en/kyoto-region/kyoto/restaurant/shigetsu | 篩月：Bib Gourmand，页面 meta 写「2026 MICHELIN Guide Japan」，JSON-LD `dateAwarded: 2026`，另有绿星；地址 68 Sagatenryuji Susukinobabacho, 616-8385；周四休息，其他日 11:00–14:00；JSON-LD 坐标 35.015281, 135.673591 | 高 |
| 5 | https://www.tenryuji.com/shigetsu/ | 篩月官方：11:00–14:00，周四定休；雪 3,800 日元（提前 2 天预约）、月 6,500 日元（2 人起，提前 3 天）、花 9,000 日元（2 人起，提前 3 天）；另付庭园参拜费 500 日元；「サービス料は頂戴いたしません」；**没写税込**；预约表单链接 contact.html（未打开）；公告写明入选米其林京都大阪 2026 必比登与绿星 | 高 |
| 6 | https://kyoto-sagano.jp/cuisine | 汤豆腐定食 4,400 日元（税込）、嵯峨野御膳 6,600 日元（税込）及组成 | 高 |
| 7 | https://kyoto-sagano.jp/access | 地址 〒616-8385 嵯峨天竜寺芒ノ馬場町45；不定休 11:00–17:30、最后点餐 16:30；随季节变动；豆腐卖完即止；交通时间 | 高 |
| 8 | https://kyoto-sagano.jp/ | 取消规定（2 天前免费、前一天/当天 50%、当天无联络 100%）；取消或改期打电话、发邮件 | 高 |
| 9 | https://omen.co.jp/pages/shops | 四条先斗町店：〒604-8014 中京区柏屋町171番地の2；昼 11:00–16:00（LO 15:00）、夜 17:00–21:00（LO 20:00）；「木曜不定休」、12/30–1/2；**不接受预约**；支付方式。银阁寺本店营业时间不含周四 | 高 |
| 10 | https://omen.co.jp/pages/menus | 令和8年9月菜单，「※すべて税込価格です」；先斗町店 おめん 1,520、大碗 1,670、天ぷらセット 2,400、精進おめん 1,580 等 | 高 |
| 11 | https://www.nomurafoods.jp/shops/karasuma/ | 乌丸本店：〒604-8151 中京区蛸薬師通烏丸西入橋弁慶町224；7:00–14:30（LO 14:00）；无定休日；**不接受预约**；おばんざいセット 850 日元（税込）、雅ご膳 1,800 日元（税込） | 高 |
| 12 | https://www.nomurafoods.jp/shops/nishiki/ | 锦店（备选，未收录）：8:00–14:30 LO、15:00 闭店；无定休；雅ご膳 1,800、八坂セット 1,100、ちょい飲みセット 1,000（均税込）；只有锦店经 EPARK 预约（未打开） | 高 |
| 13 | https://www.kyotofu.co.jp/shoplist/monjya/monjya-access | こんなもんじゃ：京都市中京区錦小路堺町通角中魚屋町494；10:00–18:00（随季节变动）；不定休 | 高 |
| 14 | https://www.kyotofu.co.jp/shoplist/monjya/monjya-menu | 菜单品项与过敏原；**页面上没有显示价格**（截图 `dining-evidence/konnamonja_menu.png`）；页面写明锦市场禁止边走边吃 | 高 |
| 15 | https://www.kagizen.co.jp/pages/shops-honten | 四条本店：京都市东山区祇园町北侧264番地；菓子销售 9:30–18:00，喫茶 10:00–18:00（LO 17:30，视拥挤可能提前）；**喫茶不接受预约**；每周一定休（遇节假日改为次个工作日） | 高 |
| 16 | https://www.kagizen.co.jp/cdn/shop/files/shops-honten.pdf?v=2246264515925565724 | 四条本店喫茶菜单：くずきり（黒蜜・白蜜）1,600、わらびもち 1,400、おうす或グリーンティー配上生菓子 1,530、グリーンティー 850、おうす 850；夏季限定甘露竹 1,390 已标注「今季販売終了」；**没标日期，没写税込/税別** | 中 |
| 17 | https://www.kagizen.co.jp/pages/faq | 四条本店喫茶与 ZEN CAFE 不接受预约；高台寺店可付席料 2,000 日元（税込）预约；东山区祇园町北侧的邮编是 〒605-0073（官方停车场地址里） | 高 |
| 18 | https://www.kyoto-nishiki.or.jp/en/manner/ | 锦市场请求：不要边走边吃；在购买的店门前或店内吃 | 高 |
| 19 | https://www.nta.go.jp/taxes/shiraberu/taxanswer/shohi/6902.htm | 总额表示义务（令和8年4月1日现行法令）：对消费者预先标示价格时必须是含税价；并注明 2027-04-01 至 2029-03-31 下调饮食料品消费税率 | 高 |
| 20 | https://www.nta.go.jp/taxes/shiraberu/taxanswer/shohi/6102.htm | 标准税率 10%、轻减税率 8%；轻减税率适用于饮食料品（不含酒类），外食与餐饮外送不适用 | 高 |
| 21 | https://www.nta.go.jp/taxes/shiraberu/zeimokubetsu/shohi/keigenzeiritsu/zeiritsuhikisage.htm | 2026-09-15 开设的特设网站：内阁决定大纲拟下调饮食料品税率 2 年，**要等法案通过**；细则在 PDF 里（未读取） | 高 |
| 22 | https://www.post.japanpost.jp/cgi-zip/zipcode.php?pref=26&city=1261040 | 中京区：中魚屋町 604-8125、柏屋町 604-8014、橋弁慶町 604-8151 | 高（邮编） |
| 23 | https://www.post.japanpost.jp/cgi-zip/zipcode.php?pref=26&city=1261050 | 东山区：祇園町北側 605-0073 | 高（邮编） |
| 24 | OSM way 319336315 / node 4264122379 / node 5163420190 / node 13859503801 / way 348101164 / way 291412090（经 Nominatim lookup） | 6 家的坐标（见第 3 节） | 参考（C 级） |
| 25 | https://www.shoraian.jp/ | 松籁庵（落选）：每周三定休；2025 年 11 月的周三曾临时营业；2026-08-01 起菜单涨价 | 高 |
| 26 | https://to-fu.co.jp/ （www 与 http 版本、/menu/、/en/ 等路径） | 南禅寺 順正（落选）：2026-09-24 全站返回 HTTP 500（WordPress fatal error），**未能读取** | 未能读取 |
| 27 | https://www.giontsujiri.co.jp/store/saryotsujiri-honten/ 、/products/food/ | 茶寮都路里（落选）：营业时间 10:30–20:30、不定休；菜单只放在 Instagram，官网没有价格 | 高（无价格） |
| 28 | https://guide.michelin.com/jp/en/kyoto-region/kyoto/restaurant/gion-yorozuya 、/kyogoku-kaneyo 、/pontocho-masuda | 必比登或入选候选的地址与营业日（落选原因见第 5 节） | 高（目录） |

## 3. 坐标

都在要求范围内（lat 34.93–35.06，lon 135.66–135.81）。

| id | 坐标 | 来源 | 备注 |
| --- | --- | --- | --- |
| yudofu-sagano | 35.014476, 135.6745122 | OSM way 319336315 | `name` 拼成 "Yudofu Sagana"（拼写错误），`name:ja` 为「湯豆腐 嵯峨野」，位置在天龙寺东南，与官网地址吻合 |
| shigetsu-tenryuji | 35.0151336, 135.6736022 | OSM node 4264122379 | 与米其林 JSON-LD（35.015281, 135.673591）相差约 16 m |
| omen-pontocho | 35.0039253, 135.7708737 | OSM node 5163420190「おめん (先斗町)」 | website 标签为 omen.co.jp |
| kyosaimi-nomura-karasuma | 35.006045, 135.7587476 | OSM node 13859503801「京菜味 のむら」 | 在蛸薬師通、乌丸以西，对应官网「蛸薬師通烏丸西入」；OSM `check_date` 2026-05-22 |
| konnamonja-nishiki | 35.0051134, 135.7632372 | OSM way 348101164（建筑轮廓中心） | 位于锦小路与堺町通交叉口；Nominatim 反推的町名是「菊屋町」，与官网「中魚屋町」不同，属于路口地块的归属差异，坐标本身在交叉口 |
| kagizen-yoshifusa-shijo | 35.0040119, 135.7747439 | OSM way 291412090 | OSM 门牌 264、邮编 605-0073，与官网一致 |

## 4. 价格与税费口径

- **nett（含税）**：只用于官网明确写了「税込」的价格：嵯峨野（每项标「税込」）、おめん（「すべて税込価格です」）、京菜味のむら（每项标「税込」）。
- **unknown**：篩月（官网只写不收服务费，没写税込）和鍵善良房（PDF 没写）。日本的总额表示义务（国税厅 No.6902）要求对消费者标示含税价，所以这些价格**大概率**已含税，但页面没写明，按规则不记为 nett。
- **price: null**：こんなもんじゃ，官网没显示价格，`pricingStatus: notPublished`。
- 本包没有任何 `++` 价格，也没有写 `serviceChargePercent` / `taxPercent`。
- 出行在国税厅特设网站所说的 2027-04 至 2029-03 饮食料品减税期内（前提是法案通过）。按现行定义，外食不属于「饮食料品の譲渡」，堂食价格可能不受影响，外带食品（甜甜圈、和果子外带）的价签可能变。PDF 细则没读，JSON 里只写了保守提示。

## 5. 候选与取舍

| 候选 | 结论 | 原因 |
| --- | --- | --- |
| 南禅寺 順正（汤豆腐，南禅寺） | 落选 | 官网全站 HTTP 500，拿不到官方菜单和营业时间；搜索摘要里的价格与时间不能用 |
| 奥丹 南禅寺 / 奥丹 清水 | 落选 | 没找到餐厅自己的官网；二手来源说南禅寺店周四休息，与第 3 天（周四）冲突 |
| 松籁庵（岚山豆腐怀石） | 落选 | 官网写每周三定休（第 2 天是周三；2025 年 11 月曾临时营业，但 2027 年未知）；2026-08 涨价后没有核对新菜单 |
| おめん 银阁寺本店 | 改用先斗町店 | 银阁寺本店营业时间不含周四（「木曜不定休」），第 3 天去不了；先斗町店排到第 2 天晚餐 |
| 京菜味のむら 锦店 | 改用乌丸本店 | 锦店在 OSM 里没有坐标（Overpass 在麩屋町・锦小路 80 m 内没找到），而规则是不凑坐标；乌丸本店有 OSM 点位，菜单与价格官方可查，而且更顺第 3 天「二条城→地铁东西线→南禅寺」的路线 |
| 茶寮都路里 祇园本店（抹茶） | 落选 | 官网没有价格（菜单只在 Instagram） |
| 祇園 萬屋（必比登乌冬） | 落选 | 米其林页面的营业日显示只有周五 12:30–15:00，看起来不可靠，也没找到官网 |
| 京极かねよ（必比登鳗鱼） | 未采用 | 本包已有 1 家必比登（篩月）；米其林页面描述被截断，未核对官网 |
| 先斗町 ますだ（米其林唯一的 obanzai） | 落选 | 米其林页面没有官网链接，拿不到官方菜单 |

## 6. 冲突记录

1. **米其林数量**：发布文章写京都一星 73、入选 99、共 244；2026-09-24 动态目录显示一星 72、入选 105、共 249。以发布文章为锚点，两组数字都写进了 `notes`。
2. **こんなもんじゃ 隐藏价格**：菜单页 HTML 源码里有被注释掉（`-->` 包裹、不显示）的「8個300円／18個600円」「6個350円」。页面上看不到这些价格，可能是旧价，**不采用**，JSON 写「官网未公布」。
3. **篩月营业日**：OSM 标签 `opening_hours: Mo-Su 11:00-14:00`；天龙寺官网与米其林都写周四休息。以官网为准。
4. **京菜味のむら 锦店价格**：搜索摘要写八坂セット 1,000 日元、雅ご膳 1,750（4 月起 1,800）；官网现为八坂セット 1,100、雅ご膳 1,800。以官网为准（锦店最终没收录）。
5. **消费税下调的确定性**：国税厅 No.6902 / No.6102 直接写「引き下げられます」；特设网站写要等法案通过才生效。JSON 采用保守措辞「拟…需法案通过」。
6. **おめん「木曜不定休」**：官网意思是部分周四休息，不是每周四都休。`closedWeekdays` 保守记 `[4]`，文字里说明原意。

## 7. 未解决 / 出发前要复核

- 米其林 2027 年版（2027-02-16）：复核篩月的必比登是否延续；`directory.edition` 也要随之更新到 2027。
- 篩月、鍵善良房：官网没写价格是否含税（`tax: unknown`）。
- 鍵善良房菜单 PDF 没标日期。
- こんなもんじゃ：官网未公布价格。
- 邮编：こんなもんじゃ（604-8125）和鍵善良房（605-0073）的邮编来自日本邮政一览，官网店铺页没写；其余 4 家邮编来自官网。
- おめん菜单是 2026 年 9 月版，季节菜和价格到 2027-11 可能变。
- 嵯峨野、こんなもんじゃ的营业时间随季节调整；嵯峨野、こんなもんじゃ不定休。
- 饮食料品消费税下调的细则（新税率、价签过渡）本轮没读 PDF。
- 预约状况全部未查询（`notChecked` / `walkIn`），没有任何订位快照。
- 11 月中旬红叶季的排队情况只是规划判断，没有官方依据。

## 8. 地址格式说明

地址写成 `…, Kyoto ddd-dddd`（例如 `45 Saga-Tenryuji Susukinobaba-cho, Ukyo-ku, Kyoto 616-8385`）。iOS 端 `RouteEnglishAddress` 会把最后一段 `Kyoto 616-8385` 识别为「addressSuffix + postcode」（需要 trip.json 里设 `addressSuffix: "Kyoto"`、`postcodePattern: "\\d{3}-\\d{4}"`）。如果改成 `…, 616-8385 Kyoto`，邮编会被拆成单独一段，复制出来的地址就不干净了。

## 9. 过程说明

- 用 WebFetch 读取鍵善良房菜单 PDF 时，工具自动把 PDF（860.6KB）缓存到了本机的工具缓存目录（不在仓库里）。这不是有意下载；之后我读了这份缓存来核对价格（第 16 行）。没有其他文件下载。
- `dining-evidence/` 下存有各页面的渲染文本、こんなもんじゃ菜单页截图、米其林京都 249 家名单和校验脚本，仅作证据，不进产品包。
