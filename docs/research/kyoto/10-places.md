# 京都三日游地点调研记录（places.json / locations.json）

- 调研日期：2026-09-24（所有 `checkedAt` 均为此日）
- 行程：2027-11-16（周二）至 11-18（周四），两位成人，红叶季；货币 JPY
- 产出：`places.json`（12 个地点，含伏见稻荷 1 篇深度攻略）、`locations.json`（12 个坐标）
- 方法：官网与京都市官方页面用脚本抓取 HTML 后转成纯文本逐段阅读（会剔除 `<script>`、`<style>` 和 HTML 注释），部分页面另用 WebFetch 阅读；坐标用 OpenStreetMap Nominatim 搜索与 OSM API 核对要素标签，邮编用日本邮政邮编查询核对。全程只读，没有预订、登录、提交表单或下载文件。
- 2027 年的开放时间、特别拜观和票价都还没有公布。JSON 里写的是 2026-09-24 官网公布的内容，并注明出发前再核对。

## 一、读过的来源和各自确认的内容

证据等级按 `docs/zh/research-playbook.md` 1.1 节：A = 运营方官网 / 政府页面；B = 权威团体页面；C = 地图 POI。

### 伏见稻荷大社 `fushimi-inari`
| URL | 等级 | 确认内容 |
| --- | --- | --- |
| https://inari.jp/en/access/ | A | JR 奈良线「稲荷」站出站即到（京都站 2 站 / 约 5 分钟）；京阪「伏見稲荷」站往东步行 5 分钟；南 5 路巴士「稲荷大社前」步行 7 分钟；停车场仅供参拜者，官网建议乘公共交通 |
| https://inari.jp/en/ | A | 地址 68 Fukakusa Yabunouchi-cho, Fushimi-ku, 612-0882；稻荷山海拔 233 m |
| https://ja.kyoto.travel/tourism/single01.php?category_id=7&tourism_id=448 | A（京都市官方） | 营业时间「閉門なし」，祈祷 8:30–16:30，授与所 8:00–18:00，全年无休；お山めぐり一周 4 km、约 2 小时；参观时间约 120 分钟（含お山めぐり）；标签「無料」；11/8 火焚祭 |
| https://inari.jp/trip/map01/ | A | 千本鸟居、奥社奉拝所、おもかる石、熊鷹社（新池，火焚祭 11/17）、一ノ峰（233 m 最高点，上社神蹟）、二ノ峰、間ノ峰、三ノ峰、御劔社、御膳谷奉拝所 |
| https://inari.jp/en/map/ | A | 英文境内图的名称（Senbon Torii、Okusha Hohaisho、Kumatakasha、Ichinomine 等） |
| https://inari.jp/about/faq/ | A | 参道上约有 1 万座鸟居；神社官网没有单列参拜时间 |
| https://inari.jp/rite/?month=11%E6%9C%88 | A | 11 月主要祭礼：11/1 献花、11/8 火焚祭（13:00）与御神乐（18:00）、11/23；11/16–18 没有大型祭典 |
| https://kyoto.travel/en/info/transportation/fushimi_inari.html | A（京都市观光协会） | 京都站坐 JR 奈良线约 9 分钟；建议避开市巴士南 5 路（可能延误 24 分钟以上）；京阪祇园四条到伏见稻荷约 22 分钟；门前町有纪念品店和京都风味餐馆 |
| https://kyoto.travel/en/destinations/fushimi-inaritaisha-shrine/ | A | 鸟居「5000 座以上」；傍晚上山别有神秘气氛 |
| https://inari.jp/trip/、/office/、/grace/omamori/ | A | 已读，与本次字段无关（讲社、护身符邮购） |

### 清水寺 `kiyomizu-dera`
| URL | 等级 | 确认内容 |
| --- | --- | --- |
| https://www.kiyomizudera.or.jp/access.php | A | 「2026年の拝観時間」表：9/1–11/20 6:00–18:00；11/21–11/30 秋季夜间特别拜观 6:00–21:30（21:00 停止受理）；12 月 6:00–18:00；夜间拜观日期每年变动。地图 App 可能导航到进不了寺的路线，进寺只有两条路。交通：206/100 路「五条坂」步行 10 分钟；207 路「清水道」步行 10 分钟；清水五条站步行约 25 分钟；寺内无停车场 |
| https://www.kiyomizudera.or.jp/event/yakan.php | A | 2026 年夜间特别拜观：春 3/27–4/5，夏 8/14–16，秋 11/21–11/30；延长至 21:30；无需预约 |
| https://www.kiyomizudera.or.jp/news/open-hour.php | A | 6:00 开门、18:00 闭门（7–8 月 18:30）；授与所、纳经所约 8:00 起 |
| https://www.kiyomizudera.or.jp/en/faq/ | A | 6:00 开门；约 1,500 株樱花、1,000 株秋季变色树木；禁止用无人机、单脚架、三脚架拍摄，禁止婚纱、cosplay 和模特拍摄；禁止未经许可的商业拍摄 |
| https://www.kiyomizudera.or.jp/faq.php | A | 票价没有团体折扣，残障人士可免票；**没有写票价金额** |
| https://www.kiyomizudera.or.jp/visit/、/en/visit/、/en/location/、/en/ | A | 已读（含搜索原始 HTML），均未找到票价文字 |
| https://ja.kyoto.travel/event/single.php?event_id=3730 | A（京都市官方） | 2026-11-21 至 11-30 夜间拜观 17:30–21:00（停止受理）；票价大人 500 日元、中小学生 200 日元 |
| https://ja.kyoto.travel/tourism/single01.php?category_id=7&tourism_id=267 | A | 6:00–18:00（7–8 月到 18:30）；无休 |
| https://saikoku33.gr.jp/place/16 | B（西国三十三所札所会） | 拝観料：大人 500 日元、中小学生 200 日元 |
| https://souda-kyoto.jp/guide/spot/kiyomizudera.html | C/D（JR 东海的宣传网站） | 写 500 日元；仅作交叉参考，没有写进 sources |
| https://kyoto.travel/en/getting-around/comfortable-access-to-higashiyama-kiyomizu-dera-temple/ | A | 五条坂方向巴士常拥堵；地铁「東山」站经ねねの道・二年坂・三年坂步行约 35 分钟到清水寺；九条站换 202/207 路较空 |

### 二年坂·三年坂 `sannenzaka`
| URL | 等级 | 确认内容 |
| --- | --- | --- |
| https://ja.kyoto.travel/tourism/single01.php?category_id=8&tourism_id=691 | A | 产宁坂传统的建造物群保存地区：江户末期至大正时期的町家；地址「東山区下河原町、桝屋町辺り」；市巴士「東山安井」或「五条坂」步行约 5 分钟；营业时间「-」 |
| https://ja.kyoto.travel/tourism/single01.php?category_id=8&tourism_id=160 | A | 二年坂位于约 100 m 的三年坂石阶之后；有竹久梦二旧居遗址 |
| https://kyoto.travel/en/travel-inspiration/things-to-keep-in-mind-while-exploring-kyoto-and-its-kiyomizu-arashiyama-and-gion-areas/ | A | 清水寺门前需注意：边走边吸烟、乱丢垃圾、长时间拍照挡路；清水寺 6:00 开门，建议人少时前往 |

### 八坂神社 `yasaka-shrine`
| URL | 等级 | 确认内容 |
| --- | --- | --- |
| https://www.yasaka-jinja.or.jp/access/ | A | 24 小时可参拜；社务所 9:00–17:00；祇园四条站步行约 5 分钟、京都河原町站约 8 分钟；100/206 路「祇園」下车即到；没有停车场 |
| https://www.yasaka-jinja.or.jp/ | A | 地址〒605-0073 東山区祇園町北側625；社务所 9:00–17:00 |
| https://ja.kyoto.travel/tourism/single01.php?category_id=7&tourism_id=474 | A | 营业时间「終日」；本殿为国宝，24 小时可参拜；标签「無料」；京都河原町站步行约 10 分钟 |
| https://kyoto.travel/en/destinations/yasakajinja-shrine/ | A | 境内有时有小吃摊；英文地址写 605-8311 |

### 祇园·花见小路 `gion-hanamikoji`
| URL | 等级 | 确认内容 |
| --- | --- | --- |
| https://www.city.kyoto.lg.jp/sankan/page/0000214071.html | A（京都市） | 2026-02-16 更新；祇园町南侧地区的礼仪启发活动（2024 年起），包括交通高札、花见小路附近的礼仪看板，附「花見小路観光マナー啓発物（提灯チラシ）」PDF |
| https://www.city.kyoto.lg.jp/sankan/cmsfiles/contents/0000214/214071/tyoutinntirasi.pdf | A（发布方：祇园町南侧地区协议会，京都市、京都市观光协会） | 四条规则：私道禁止拍照；禁止在路上驻足、禁止走到车道上；禁止拍摄艺妓・舞妓；垃圾带走。地图中花见小路主街是公道，弥生小路、南园小路、初音小路、青柳小路、小袖小路、西花见小路是私道；犬矢来、驹寄禁止触碰和坐靠；茶屋不能擅自进入。此 PDF 是用 WebFetch 读取后以图片形式查看的，没有另存 |
| https://ja.kyoto.travel/news/format.php?id=428 | A（京都市观光协会刊登，2023-12-05） | 地区居民等联名告示：不要拦截、触碰、尾随、未经许可拍摄艺妓和舞妓；不要擅闯寺社和私有地；不要堵路；不要乱丢垃圾、大声喧哗；并列出相应法律和条例的罚则；居民可能报警 |
| kyoto.travel 礼仪页（同上） | A | 禁止拍摄舞妓；不要用三脚架拍街景，不要触碰茶屋灯笼，不要倚靠栏杆；花见小路两侧石材区是步行区 |

### 岚山竹林小径 `arashiyama-bamboo`
| URL | 等级 | 确认内容 |
| --- | --- | --- |
| https://ja.kyoto.travel/tourism/single01.php?category_id=8&tourism_id=2683 | A | 野宫神社至天龙寺北门至大河内山庄约 400 m；地址右京区嵯峨天龍寺芒ノ馬場町；嵐電嵐山站 10 分钟、JR 嵯峨嵐山站 13 分钟、阪急嵐山站 21 分钟；营业时间「-」 |
| kyoto.travel 礼仪页 | A | 岚山要注意乱丢垃圾，禁止走上铁轨、禁止边走边吸烟；建议清晨前往，经龟山公园走较清静的路线进入竹林道 |
| https://kyoto.travel/en/getting-around/comfortable-access-to-saga-arashiyama/ | A | JR 嵯峨野线快速约 11 分钟到嵯峨嵐山；从京都站坐巴士又挤又慢；阪急、嵐電路线 |
| https://www.tenryuji.com/visit/ | A | 北门受理 8:30 起 |

### 天龙寺 `tenryu-ji`
| URL | 等级 | 确认内容 |
| --- | --- | --- |
| https://www.tenryuji.com/visit/ | A | 庭园 8:30–17:00（16:50 停止受理）；2026-11-14 至 11-30 特别早朝参拜 7:30 起（仅庭园受理处，北门 8:30 起）；庭园 500/300 日元；诸堂加 300 日元，8:30–16:45（16:30 停止受理）；法堂云龙图 500 日元，9:00–16:30（16:20 停止受理），仅周六日和节假日开放，春秋有每日开放期；交通；停车场 |
| https://www.tenryuji.com/en/visit/ | A | 英文版：Last admission 4:50 p.m.；嵐電嵐山站步行 5 分钟 |
| https://www.tenryuji.com/info/2025/12/2026.html | A | 2026 年法堂云龙图特别参拜：3/1–5/31、9/19–12/6 每日开放；曹源池庭园早朝参拜 11/14–11/30 7:30 起 |
| https://www.tenryuji.com/unryuzu/ | A | 春夏秋特别参拜期间每日公开，其余时间仅周六日和节假日；500 日元 |
| https://www.tenryuji.com/shigetsu/ | A | 篩月 11:00–14:00，周四定休；雪 3,800 日元（提前 2 天预约）、月 6,500 日元、花 9,000 日元（2 人以上、提前 3 天），另付庭园参拜费 500 日元 |
| https://ja.kyoto.travel/tourism/single01.php?category_id=7&tourism_id=428 | A | 8:30–17:00；受理截止：庭园 16:45、诸堂 16:30（与官网有出入，见第二节） |
| https://www.tenryuji.com/、/event/、/info/ | A | 已读，没有另外的秋季信息 |

### 金阁寺 `kinkaku-ji`
| URL | 等级 | 确认内容 |
| --- | --- | --- |
| https://www.shokoku-ji.jp/kinkakuji/access/ | A | 9:00–17:00，全年无休，特别拜观时可能不同；大人（高中生以上）500 日元，中小学生 300 日元；12/59/205/M1 路巴士「金閣寺道」；地址 603-8361 |
| https://www.shokoku-ji.jp/kinkakuji/faq/ | A | 只允许个人范围内的小型相机快拍，谢绝以公开给第三方为目的（包括社交媒体）的拍摄、商业拍摄、团体照、直播、无人机；不能寄存行李、没有储物柜；庭园内没有吃便当的地方；金阁之后有台阶 |
| https://www.shokoku-ji.jp/kinkakuji/ | A | 拜观时间 9:00–17:00；公告列表 |
| 金阁寺官网：参拝志納料改定のお知らせ（URL 见 places.json） | A | 2023-01-06 发布：2023-04-01 起调整参拜费（与交通页的现行价格一致） |
| https://ja.kyoto.travel/tourism/single01.php?category_id=7&tourism_id=490 | A | 9:00–17:00（停止受理），无休；「金閣寺道」步行 3 分钟 |
| https://kyoto.travel/en/info/transportation/kinkakuji_kinugasa.html | A | 京都站坐地铁到北大路，换 204/205 路（蓝色站台 E–G）约 11 分钟；巴士站到入口约 5 分钟；不建议从京都站直接坐 205 路 |

### 锦市场 `nishiki-market`
| URL | 等级 | 确认内容 |
| --- | --- | --- |
| https://www.kyoto-nishiki.or.jp/ | A | 全长 390 m；禁止边走边吃，在购买店铺的店前或店内吃；组合事务所地址 604-8054 西大文字町609 |
| https://www.kyoto-nishiki.or.jp/access/ | A | 四条站、乌丸站 3 分钟；京都河原町站 4 分钟；京阪祇园四条站 10 分钟；范围寺町至高仓；**没有写营业时间和定休日** |
| https://www.kyoto-nishiki.or.jp/manner/ | A | 禁止边走边吃（官网只写了这一条礼仪） |
| https://www.kyoto-nishiki.or.jp/about/ | A | 历史介绍，没有营业时间 |
| https://ja.kyoto.travel/tourism/single01.php?category_id=4&tourism_id=1174 | A | 约 400 m、130 余家店；营业时间和定休日均为「-」 |
| https://kyoto.travel/en/destinations/kyoto-nishiki-food-market/ | A | 400 m；避免边走边吃 |
| https://kyoto.travel/en/getting-around/comfortable-access-to-central-kyoto-city-nishiki-market/ | A | 拱廊商店街；从四条站和四条河原町的走法 |
| kyoto.travel 礼仪页 | A | 严禁边走边吃；垃圾丢进购买店铺的垃圾桶；有观光快适度地图和直播镜头；列举玉子烧、海鳗天妇罗、生麸、章鱼烧 |

### 二条城 `nijo-castle`
| URL | 等级 | 确认内容 |
| --- | --- | --- |
| https://nijo-jocastle.city.kyoto.lg.jp/guide/annai/ | A | 8:45–16:00（17:00 闭城）；二之丸御殿受理 8:45–16:10；本丸御殿 9:30–16:00（预约制）；休城 12/29–31；本丸御殿每月第 3 个周一及次日休（遇节假日开放）；御殿内禁止拍照，禁止饮食（指定场所除外），禁止无人机 |
| https://nijo-jocastle.city.kyoto.lg.jp/admission/fee/ | A | 入城 800 日元；入城＋二之丸 1,300 日元；本丸 1,000 日元（需预约，另需入城券，WEB 票来城日前 30 天开售）；展示收藏馆 100 日元；页面没有写生效日期 |
| https://nijo-jocastle.city.kyoto.lg.jp/event/matsuri2026/ | A | 二条城まつり 2026：白天 10/23–12/6 8:45–17:00（16:00 最后入城）；灯光活动 10/23–12/5 18:00–22:00（21:00 最后入场）；昼夜分别购票；灯光活动早鸟票 1,600/2,000 日元，普通票 2,000/2,400 日元（平日/周末节假日） |
| https://nijo-jocastle.city.kyoto.lg.jp/service/ | A | 日语、英语官方导览每天开团；收费语音导览；大休憩所商店 8:45–16:45；和楽庵茶房 9:30–16:30（16:00 最后点单） |
| https://nijo-jocastle.city.kyoto.lg.jp/access/（含 ?lang=en） | A | 地址 604-8301；巴士停车场 9:00 前后、10:30 前后、13:30 前后拥挤；持地铁一日券入城一般票便宜 100 日元。电车路线细节在折叠区或图片中，文字版未读到 |
| https://ja.kyoto.travel/tourism/single01.php?category_id=8&tourism_id=2020 | A | 地铁「二条城前」站下车即到；开放时间与休馆规则同官网；中学生、小学生的入城＋二之丸票价为 400/300 日元 |
| https://kyoto.travel/en/destinations/nijojo-castle/ | A | 狩野派障壁画、莺声地板 |
| /guide/、/corporation/aki2026/、/news/…運営について-3/ | A | 已读，与本次字段无关 |

### 哲学之道 `philosophers-path`
| URL | 等级 | 确认内容 |
| --- | --- | --- |
| https://ja.kyoto.travel/tourism/single01.php?category_id=8&tourism_id=2684 | A | 银阁寺至若王子神社约 2 km；得名于西田几多郎；沿琵琶湖疏水（自南向北流）；关雪樱；北端坐 203/204/5/7 路到「銀閣寺道」；南端从蹴上站步行约 20 分钟，或坐 5 路到「南禅寺永観堂前」；营业时间「-」；官网链接 tetsugakunomichi.jp |
| https://kyoto.travel/en/destinations/philosophers-path-tetsugakunomichi/ | A | 银阁寺至若王子桥；靠近法然院、安乐寺 |
| https://tetsugakunomichi.jp/、/about.html | A（地方保胜团体） | 哲学之道保胜会的沿革和维护活动 |

### 银阁寺 `ginkaku-ji`
| URL | 等级 | 确认内容 |
| --- | --- | --- |
| https://www.shokoku-ji.jp/ginkakuji/access/ | A | 夏期（3/1–11/30）8:30–17:00，冬期 9:00–16:30，全年无休；大人 1,000 日元、中小学生 500 日元；「銀閣寺道」「銀閣寺前」巴士站；部分区域不能使用轮椅 |
| 银阁寺官网：参拝志納料改定のお知らせ（2026年4月1日より）（URL 见 places.json） | A | 2026-04-01 起：大人 500→1,000 日元，中小学生 300→500 日元 |
| https://www.shokoku-ji.jp/ginkakuji/event/ | A | 令和 8 年（2026）秋季特别拜观 11/1–12/5；日语导览，场次 10:00/11:00/12:00/13:30/14:30/15:30，约 30 分钟，每场约 20 人，当天在本堂前登记；2,000 日元，另需普通参拜费；禁止拍照、录音和翻译（包括 App）；手机须寄存 |
| https://www.shokoku-ji.jp/ginkakuji/faq/ | A | 夏期最后入场 17:00，17:20 前离寺；参观约需 30 分钟 |
| https://www.shokoku-ji.jp/ginkakuji/ | A | 季节开放时间；秋季特别拜观 2026-11-01 至 12-05 |
| https://ja.kyoto.travel/tourism/single01.php?category_id=7&tourism_id=308 | A | 「銀閣寺道」步行约 10 分钟，「銀閣寺前」约 5 分钟；季节开放时间 |
| https://kyoto.travel/en/getting-around/comfortable-access-to-ginkaku-ji-temple-philosophers-path/ | A | 京都站坐地铁到今出川，换 203 路，约 43 分钟；从蹴上站可沿哲学之道步行过来 |

### 坐标与邮编
| URL | 等级 | 确认内容 |
| --- | --- | --- |
| https://nominatim.openstreetmap.org/search（每个地点 1–3 次查询）、/lookup、/reverse | C | 候选要素与中心点（见第四节） |
| https://api.openstreetmap.org/api/0.6/way/{id}.json、relation/17656638、map.json（祇园小范围） | C | 已选要素的名称、类型、`tourism`/`amenity` 标签 |
| https://www.post.japanpost.jp/cgi-zip/zipcode.php?zip=…（16 个邮编） | A（日本邮政） | 605-0862 清水、605-0074 祇園町南側、605-0073 祇園町北側、606-8402 銀閣寺町、606-8405 浄土寺上南田町、616-8385 嵯峨天龍寺芒ノ馬場町、604-8054 西大文字町、604-8301 二条城町、603-8361 金閣寺町、612-0882 深草薮之内町；用来否定 Nominatim 给出的错误邮编（605-0062、606-8402〔哲学之道〕、616-0000、604-8375、600-8006、612-0807） |

## 二、冲突与处理

1. **天龙寺最后受理时间**：官网（日文、英文）写庭园 16:50 停止受理、诸堂 16:30；京都観光Navi 写庭园 16:45、诸堂 16:30。以官网为准。
2. **八坂神社步行时间**：官网写京都河原町站步行约 8 分钟，京都観光Navi 写约 10 分钟。两者都写进了 travel。
3. **八坂神社邮编**：官网 605-0073（日本邮政：祇園町北側）；kyoto.travel 英文页写 605-8311（很可能是事业所个别邮编）；Nominatim 给 605-0062（林下町）。采用官网 605-0073。
4. **金阁寺巴士站到入口的步行时间**：京都観光Navi 写 3 分钟，kyoto.travel 写约 5 分钟。travel 里两个都写。
5. **伏见稻荷鸟居数量**：官网 FAQ 写约 1 万座，kyoto.travel 写 5000 座以上。攻略采用官网数字。
6. **锦市场长度**：官网 390 m，京都市两个官方页面写 400 m。desc 写「约 400 米」。
7. **天龙寺交通**：官网日文页写嵐電嵐山站「下車前」（出站即到），英文页写步行 5 分钟。两个都写进 travel。
8. **清水寺票价**：清水寺官网（日文和英文的 visit、access、FAQ、首页）都没有票价金额。采用京都市官方京都観光Navi 活动页（2026 年秋季夜间拜观）和西国三十三所札所会页面的「大人 500 日元、中小学生 200 日元」，并在 price 里写明来源。
9. **邮编**：Nominatim 多处给出不准确的邮编（见上表）。一律以运营方地址或日本邮政查询为准；哲学之道的所选路段位于浄土寺上南田町（Nominatim 反查），日本邮政对应 606-8405。
10. **HTML 注释中的旧内容**：银阁寺活动页 HTML 注释里残留「本年度の秋の特別拝観を中止」和旧的停开场次；天龙寺参拜页注释里残留 2025 年夏季的时间。这些内容浏览器里看不到，已剔除，没有写进 JSON。

## 三、无法核实 / 留给出发前核对的事项

- **2027 年全部安排**：清水寺秋季夜间拜观日期、天龙寺特别早朝参拜和法堂每日开放期、银阁寺秋季特别拜观、二条城まつり和夜间灯光活动，都只有 2026 年的数据。按 2026 年的规律，清水寺夜间拜观（11/21 起）不会覆盖 11/16–18。
- **二条城本丸御殿**：按现行规则（每月第 3 个周一及次日休），2027-11-15（周一）和 11-16（周二）不开放。已写进 tip。
- **锦市场**：官网和京都市页面都没有统一营业时间和定休日。
- **伏见稻荷**：神社官网没有写山道的夜间照明，也没有单列参拜时间（参拜时间取自京都市官方京都観光Navi）。
- **祇园私道**：媒体报道（未作为来源）说 2024 年起部分私道禁止游客通行、罚款 1 万日元。本次读到的官方材料只写私道禁止拍照，没有找到通行禁令和罚款金额的官方原文，所以 JSON 只写「现场如有禁止通行告示请勿进入」。
- **周边餐饮**：金阁寺、哲学之道、银阁寺、岚山主街、祇园、清水坂一带的具体餐厅没有逐家核实，food 里写的是官方页面的笼统描述，或注明「未核实」。只有二条城（商店、和楽庵茶房）和天龙寺（篩月）写了具体营业信息。
- **Gion Corner 演出时间**、永观堂和南禅寺的开放时间与票价：本次没有核对，文中已注明。
- **二条城入城电车路线细节**：官网交通页的路线说明在图片或折叠区里，文字版没有读到。travel 采用京都観光Navi「二条城前站下车即到」。
- **坐标没有做实地抽查**，也没有用日本国土地理院地图做第二来源比对。

## 四、坐标选取（全部在 lat 34.93–35.06、lon 135.66–135.81 范围内）

| 地点 | 采用的 OSM 要素 | 坐标 | 拒绝的候选 |
| --- | --- | --- | --- |
| fushimi-inari | way 899425893（本殿，`amenity=place_of_worship`，`name:en`=Fushimi Inari Taisha） | 34.967173, 135.7733546 | way 96291583（整个境内的 landuse，中心在山上）；node 11778213202（告示板）；node 11174591021（竹田街道上的同名石碑）；三重县鸟羽的同名石碑 |
| kiyomizu-dera | way 336641107（寺域，`tourism=attraction`） | 34.994303, 135.7844389 | node 11810261530（东大路通的巴士站） |
| sannenzaka | way 179116810（三年坂石阶，`tourism=attraction`） | 34.9963406, 135.7808783 | way 710696944（八坂上町的同名路段，没有 `name:en`）；二年坂各路段（取三年坂作为代表点） |
| yasaka-shrine | way 328903218（`amenity=place_of_worship`） | 35.0036027, 135.7782611 | 鹿儿岛、北九州、鹤冈、千叶的同名神社 |
| gion-hanamikoji | way 27908626（花見小路，四条以南，Gionmachi-Minamigawa） | 35.0026541, 135.7748676 | 四条以北的「花見小路通」三段（28020529、470237770、547229146）；way 28020523（西花见小路，`access=private`） |
| arashiyama-bamboo | relation 17656638（嵐山竹林，`tourism=attraction`） | 35.0167419, 135.6711482 | 秋田男鹿、静冈伊豆的同名步道；Nominatim 搜「竹林の道」得到的陵墓、地图板、餐厅节点 |
| tenryu-ji | way 409723494（天龍寺） | 35.0162243, 135.6729408 | 东京品川、八王子、足立、新宿的同名寺院和巴士站 |
| kinkaku-ji | way 98115917（金閣寺） | 35.0395293, 135.7295373 | 无其他候选 |
| nishiki-market | way 772134672（`amenity=marketplace`） | 35.0050244, 135.7655699 | 无其他候选（OSM 标签 opening_hours「Mo-Su,PH 10:00-18:00+」为地图数据，没有采用） |
| nijo-castle | way 57111281（`historic=castle`） | 35.0140076, 135.7485369 | 无其他候选 |
| philosophers-path | way 593317542（Philosopher's Walk 北段，近银阁寺桥） | 35.026151, 135.7955238 | 金泽、宇都宫、挂川的同名路；南段 way 593317511 与中段 593317547（为贴近银阁寺一侧的起点而改选北段） |
| ginkaku-ji | way 105817561（銀閣寺） | 35.0268996, 135.7983714 | 大阪熊取、石川羽咋、长野伊那的同名「慈照寺」 |

## 五、工作量

- 本人阅读并提取正文的网页：92 个 URL（脚本抓取，其中 21 个是日本邮政邮编查询页，5 个按地址查询的请求没有返回有效结果，已弃用）。另用 WebFetch 读了 12 个上表之外的 URL（含京都市祇园礼仪传单 PDF）。合计约 104 个网页 URL。
- OSM：Nominatim 查询约 20 次，OSM API 读取要素约 20 次，读取小范围地图数据 1 次；Overpass 查询 2 次，都因服务器繁忙失败。
- 网页搜索约 16 次，只用来找官方页面的 URL；搜索摘要没有作为证据。
- 结构校验：把 repo 的 `scripts/verify_content.py` 复制到 scratchpad，内容也放在副本里（trip.json 的 bounds 临时改成京都范围，itinerary 引用改成新 ID），分别跑了默认模式和 `--require-complete`。与 places.json、locations.json 相关的检查全部通过（每个地点都有坐标、sources、checkedAt、https 链接，没有占位词）；报错全部来自未替换的示例文件（hotels、dining、posts、photo-sources 等）。没有改动 repo。
