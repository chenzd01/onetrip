# 京都 3 日示例：行前准备 / 短句 / 参考信息 / 汇率 调研记录

- 调研日期：2026-09-24
- 行程假设：2027-11-16（周二）上海早班机飞关西机场，2027-11-18（周四）结束；2 人；中国大陆护照；全部中文。
- 整合时的调整：为了第一天一早去伏见稻荷，行程改为 2027-11-15 晚上抵达（`trip.json` 的 `departureDate`），「出发当天」一项的 dueDate 与保险覆盖日期随之改为 11-15。
- 产出：`trip-currency.json`、`preparation.json`（19 项）、`phrases.json`（5 组 × 6 句）、`references.json`（6 条）。
- 只读操作：没有登录、预订、提交表单或下载文件。京都市官方旅游网站 Cookie 横幅选了「Essential Only」。
- 读取方式：
  - 主要用 gstack `browse`（无头 Chromium），逐页读取正文。
  - 日本外务省、驻华使馆、驻上海总领馆、法务省入管厅、关西机场、JNTO 的页面对无头浏览器返回 Access Denied / 403（Akamai、CloudFront）。没有做任何绕过（没有改 UA，也没有开有头隐身模式）。
  - Claude 浏览器面板能打开外务省页面，但读取时一直报「Policy check temporarily unavailable」，没能读出内容。
  - 所以 JNTO 页面改用 WebFetch 读取（让它逐字引用关键句）；外务省和日本驻华使领馆页面改读 Internet Archive 的存档快照（日期见下表）。JSON 里的链接仍然指向官方原始 URL。

## 1. 汇率

| 来源 | 读取结果 |
| --- | --- |
| 中国外汇交易中心 人民币汇率中间价 https://www.chinamoney.com.cn/chinese/bkccpr/ （browse，2026-09-24） | 页面时间「2026-09-24 9:15」：**100日元/人民币 4.2590**（较上日 +164 点）。所以 homePerLocal = 0.042590，四舍五入到 4 位小数是 **0.0426**。 |
| 中国银行外汇牌价 https://www.boc.cn/sourcedb/whpj/ （browse，交叉核对） | 日元（每 100 日元）：现汇买入 4.2196、现钞买入 4.2196、现汇卖出 4.2522、现钞卖出 4.2522、中行折算价 4.259；发布时间 2026/09/24 16:55:33。和中间价一致。 |

`trip-currency.json` 的 `currency` 可以直接并入 `trip.json`。符号建议日元用 `JP¥`、人民币用 `¥`，因为 App 把符号当金额前缀，两种货币都写 ¥ 会分不清（这是编辑建议）。

## 2. 实际读过的来源与各自确认的内容

### 签证、护照、出行提醒

| 来源（读取方式） | 确认的内容 |
| --- | --- |
| 中国领事服务网 安全提醒列表 https://cs.mfa.gov.cn/aqtx/ （browse） | 列表里有《提醒中国公民近期避免前往日本》（2026-03-26）和《提醒中国公民春节期间避免前往日本》（2026-01-26）。 |
| 同上正文 https://cs.mfa.gov.cn/aqtx/202607/t20260721_11988727.html （browse） | 发布时间 2026-03-26 17:59：提醒中国公民近期避免前往日本；列出 119、110、118、+86-10-12308、+86-10-65612308，以及驻大阪总领馆领事保护电话 +81-6-6445-9427 等。 |
| 中国领事服务网 日本国家页 https://cs.mfa.gov.cn/ljmdd/yz_645708/rb_647322/ （browse，点开「旅行风险等级和安全提醒」） | 日本有 1 个黄色（中风险）地区：福岛县；其他地区为蓝色（低风险）。 |
| 国家移民管理局 普通护照签发服务指南 https://s.nia.gov.cn/mps/bszy/gmcrg/slpthz/201903/t20190313_1011.html （browse） | 有效期不足 6 个月、签证页即将用完等情况可以换发；户籍地 7 个工作日签发，跨省异地 20 日；每本 120 元。 |
| 日本国驻上海总领事馆 有关签证申请的信息 https://www.shanghai.cn.emb-japan.go.jp/itpr_zh/visa_c.html （存档快照 2026-09-11） | 管辖上海、浙江、江苏、江西、安徽；中国公民赴日需要事先取得签证；须持有效护照；原则上通过指定代理机构或指定旅行社递交；领馆收件后最快第 5 个工作日签发；签证热线 400 032 7369（中文为日本时间周一至周五 9:30–18:15）。页面日期 2023/5/15。 |
| 日本外务省 Visa information for Chinese nationals https://www.mofa.go.jp/j_info/visit/visa/topics/china.html （存档快照 2026-09-17） | 团体旅游最长 15 天；个人旅游单次签证面向具备一定经济能力者及其家属、符合条件的在校生和毕业生，停留期 15 天或 30 天，须通过指定旅行社递交；另有冲绳/东北多次、经济能力充分者多次、相当高收入者多次签证。**页面日期 2022-09-28。** |
| 日本外务省 JAPAN eVISA https://www.mofa.go.jp/j_info/visit/visa/visaonline.html （存档快照 2026-06-25，页面日期 2026-05-15） | 居住在中国的中国公民须经指定代办机构申请；电子签证停留期为「15 天」或「30 天」；抵达时须在联网状态下出示 Visa issuance notice，不接受 PDF、截图或打印件；仅限乘飞机或指定航线的船入境。 |
| 日本国驻华大使馆 关于发行电子签证的相关通知 https://www.cn.emb-japan.go.jp/itpr_zh/00_000485_00224.html （存档快照 2026-09-11，页面日期 2023/6/13） | 2023-06-19 起发行电子签证；对象为 30 天内旅游目的短期单次签证，仅限居住在中国（不含港澳）的中国护照持有人。 |
| 日本国驻上海总领事馆 电子签证通知（存档快照 2026-03-14，页面日期 2023/6/15）、赴日旅游保险页（存档快照 2026-09-11，页面日期 2024/7/2）、签证 Q&A 目录（存档快照 2026-09-11） | 电子签证内容与大使馆一致。保险页**建议**购买境外旅行保险，页上列有具体保险公司，所以 JSON 没有链接这一页，以保持中立。 |
| 日本外务省 中国国籍短期滞在签证页（日文，存档快照 2026-02-12，页面日期 令和7年6月26日） | 正文只有手续概要的 PDF 链接，没有下载 PDF。 |

### 入境、海关、检疫

| 来源 | 确认的内容 |
| --- | --- |
| 日本数字厅 Visit Japan Web 说明页（日文/简中）https://services.digital.go.jp/visit-japan-web/ 、https://services.digital.go.jp/zh-cmn-hans/visit-japan-web/ （browse） | 可登记入境审查和海关申报，也可用于免税购物；二维码必须用手机或平板出示；2025-06-05 通知：有网站以手续费名义收费，VJW 不收任何费用。 |
| Visit Japan Web 使用流程 https://services.digital.go.jp/visit-japan-web/guide/ （browse） | 流程是 STEP 0–4；新建账号需要邮箱；护照剩余有效期不足 6 个月时显示警告；免税功能只限外国籍、短期滞在等身份，并且需要读取护照。 |
| 日本海关 Procedures of Passenger Clearance https://www.customs.go.jp/english/summary/passenger.htm （browse） | 推荐通过 VJW 电子申报；红/绿通道；免税额度（酒 3 瓶等）；携带现金等支付手段超过 100 万日元须申报。 |
| 农林水产省动物检疫所 肉制品等伴手礼 https://www.maff.go.jp/aqs/tetuzuki/product/aq2.html （browse） | 大多数肉制品（含肉干、火腿、香肠、肉包）不能带入；违法携带可处 300 万日元以下罚金或 3 年以下拘禁刑。 |

### 免税（退款方式）

| 来源 | 确认的内容 |
| --- | --- |
| 观光厅 免税店网站首页 https://www.mlit.go.jp/kankocho/tax-free/ （browse） | 2026-02-12 公开旅行者向新制度（退款方式）特设页；2026-04-15 公开多语言宣传单和视频。 |
| 观光厅 旅行者向特设页 https://www.mlit.go.jp/kankocho/tax-free/page01_000001_00021.html （browse） | **2026-11-01 购买分起改为退款方式**：先按含税价购买，出境时在机场/港口经海关确认带出后退还消费税相当额。须在购买日起 90 天内出境时确认；绿色/红色判定；须在托运行李前办理；关西等 7 个机场可用 VJW 在线办理；按收据为单位确认；门槛是同一店铺一天 5,000 日元（不含税）以上；消耗品不再特殊包装，但境内用掉就不退；退款由免税店或受托事业者支付。 |
| 观光厅 旅行者向 FAQ https://www.mlit.go.jp/kankocho/tax-free/page01_000001_00023.html （browse） | 托运后不能取回行李；退款方式因店而异（银行转账、信用卡、App、机场现金等）；自行邮寄出境的「别送」方式已于 2025-03-31 废止。 |
| 国税厅 リファンド方式への見直し https://www.nta.go.jp/publication/pamph/shohi/menzei/201805/format/002.htm （browse） | 根据令和 7 年度税制改正，自令和 8 年（2026 年）11 月 1 日起实施退款方式；Q&A 最近一次更新是 2026-07-08。 |
| 京都市官方旅游指南 Currency Exchange & Taxes https://kyoto.travel/en/tax-rules/ （browse） | 很多消费和寺院参观费只收现金；免税制度链接分成「2026-10-31 前」和「2026-11-01 起」两套；住宿税按新档位；温泉税。 |

### 交通

| 来源 | 确认的内容 |
| --- | --- |
| JR 西日本 ICOCA 首页、购买方法页 https://www.jr-odekake.net/icoca/ 、/purchase/ 、/purchase/icoca.html （browse） | 每张 2,000 日元（含 500 日元押金），不能用信用卡买；一次乘车只能用一张 ICOCA，不能合并使用。 |
| JR 西日本 Apple Pay 的 ICOCA：首页、新规发行、充值、对应机型（/icoca/applepay/…）（browse） | 可以从 iPhone 钱包新建 ICOCA；充值和买定期券需要在 Apple Pay 里设置有效的信用卡；充值可用 ICOCA App、钱包或现金（部分售票机、能充值的商店、Seven 银行和 Lawson 银行 ATM）；余额上限 2 万日元；2:00–4:00 不能充值；需要 iPhone 8 及以上、iOS 16 及以上，并把设备地区设为日本。 |
| JR 西日本 ICOCA 指南（简中）https://www.westjr.co.jp/global/sc/howto/icoca/ （browse） | 访日游客限定设计 ICOCA：外国护照、短期滞在入境、每人限一张，在关西机场站 JR 绿色窗口出售，2,000 日元（含押金）。 |
| Apple 支持 108772（简中/英文）https://support.apple.com/zh-cn/108772 （browse，发布日期 2026-03-30） | 可添加 Suica、PASMO、ICOCA、TOICA；需要双重认证的 Apple 账户、iPhone 8 及以上，以及钱包里有符合条件的支付卡。 |
| JR 西日本 特急 HARUKA https://www.jr-odekake.net/railroad/train/haruka/ （browse） | 停车站包括京都和关西空港（页面注明各班次停站不同）。 |
| 京都市交通局 首页 https://www.city.kyoto.lg.jp/kotsu/ （browse） | 公告里有「市バスの市民優先価格の制度概要」、地铁外币兑换机等。 |
| 京都市交通局 市民優先価格 https://www.city.kyoto.lg.jp/kotsu/page/0000351261.html （browse，页面日期 2026-06-03） | 均一区间计划在**令和 9 年度（2027 年 4 月–2028 年 3 月）内实施**；非市民普通票价方案约 350–400 日元，市民 200 日元；须国家认可；一日券和回数券的价格仍在研究；现金和回数券不适用市民价。 |
| 京都市交通局 お得な乗車券 https://www.city.kyoto.lg.jp/kotsu/page/0000019521.html （browse，页面日期 2024-04-01） | 巴士一日券 2023-09-30 停售；地铁·巴士一日券可乘「土休日に運行する観光特急バス」。 |
| 京都市交通局 地下鉄・バス1日券 https://www.city.kyoto.lg.jp/kotsu/page/0000028378.html （browse） | 成人 1,100 日元、儿童 550 日元；适用范围；发售地点。 |
| 京都市交通局 バス1日券（停售）https://www.city.kyoto.lg.jp/kotsu/page/0000028337.html （browse） | 2023-09 末停售，2024-03 末停止使用。 |
| 京都市交通局 市バスの運賃 https://www.city.kyoto.lg.jp/kotsu/page/0000240682.html （browse，页面日期 2024-06-01） | 均一区间成人 230 日元、儿童 120 日元；可用 IC 卡。 |
| 京都市交通局 ICカード https://www.city.kyoto.lg.jp/kotsu/page/0000214550.html （browse） | 可用 10 种 IC 卡；地铁各站售票机可买 ICOCA；可在车站售票机和便利店充值。 |
| 京都市交通局 クレジットカード決済… https://www.city.kyoto.lg.jp/kotsu/page/0000334479.html （browse，页面日期 2024-11-07） | 地铁不能用信用卡支付。 |
| 京都市交通局 外貨両替機 https://www.city.kyoto.lg.jp/kotsu/page/0000356988.html （browse，页面日期 2026-09-08） | 8 个站设有外币兑换机，受理人民币；只收纸币；每次最多折合 10 万日元；只能兑换成日元。 |
| 京都市营巴士·地铁导游指南（简中）乘坐方法 https://www2.city.kyoto.lg.jp/kotsu/webguide/sc/bus/howtoride_bus.html （browse） | 普通路线后门上、前门下，下车付费；EX100/EX101 前门上、上车付费；票价 230 日元和 500 日元；不收信用卡和储蓄卡；不能用 JR Pass。 |
| 同指南 观光特急巴士（英文）https://www2.city.kyoto.lg.jp/kotsu/webguide/en/bus/limited_express.html （browse） | EX100/EX101 的路线和票价 500 日元；页面只写「operation day」，没写具体哪几天运行。 |

### 支付、行李、礼仪、安全、气候、电源

| 来源 | 确认的内容 |
| --- | --- |
| Seven 银行 Overseas Cards Usable at ATMs https://www.sevenbank.co.jp/intlcard/card2.html （browse） | 受理银联（00:10–23:50）、Visa、Mastercard 等；境外卡每笔上限 10 万日元；手续费因卡组织而异；同一标识的卡也可能无法使用。 |
| 中国驻大阪总领馆 首页、领区概况、私下换汇提醒（2026-08-13）（browse） | 领区包括京都府；领事保护 06-6445-9427；工作时间外可拨 12308；紧急电话 110、119、118。 |
| HANDS FREE KYOTO https://hands-free.kyoto.travel/?lang=en （browse） | 由京都市拥有和运营；请勿把大件行李带上市营巴士；京都站各柜台和受理时间；机场寄送、出租车运送行李等服务入口。 |
| 京都市官方旅游指南 Luggage Services、Responsible Travel、Gion manner（2024-01-09）、Smoking on the Street、Safety Information（browse） | 艺伎舞伎拍摄、禁拍区域、堵路、垃圾、吸烟罚款 1,000 日元、竹子刻字最高 30 万日元、脱鞋、绿色车牌出租车；祇园告示列出的罚则。 |
| 京都市 宿泊税の見直し https://www.city.kyoto.lg.jp/gyozai/page/0000345893.html （browse，页面日期 2025-10-03） | 2026-03-01 起分为 200、400、1,000、4,000、10,000 日元五档。 |
| 日本气象厅 京都平年值 https://www.data.jma.go.jp/stats/etrn/view/nml_sfc_ym.php?prec_no=61&block_no=47759… （browse） | 11 月：平均 12.5°C，日最高 17.3°C，日最低 8.4°C，降水 73.9 mm（1991–2020 年）。 |
| JNTO Japan Visitor Hotline https://www.japan.travel/en/plan/hotline/ （WebFetch） | 050-3816-2787 / +81-50-3816-2787，24 小时全年无休，支持英、中、韩；110、119。 |
| JNTO Staying Safe https://www.japan.travel/en/plan/emergencies/ （WebFetch） | 热线同上，本页写的是支持英、中、韩、日四种语言；本页没有提到 119。 |
| JNTO Travel Insurance https://www.japan.travel/en/plan/travel-insurance-in-japan/ （WebFetch） | 不是强制，但强烈建议；医疗费可能很高；2021 年起，在日本有未付医疗费的外国人可能被限制或拒绝入境。 |
| JNTO FAQ https://www.japan.travel/en/faq/ （WebFetch） | 100V，50/60Hz，插座为 A 型；可在机场买或租 SIM、eSIM，也可提前预订，或租随身 Wi-Fi；日本仍然是现金文化；没有小费习惯。 |
| JNTO Japan Electrical Outlet https://www.japan.travel/en/plan/plug-and-electricity/ （WebFetch） | 100V；京都属 60Hz 地区；部分电器需要降压变压器。本页正文**没有**写「A 型」，A 型出自 JNTO FAQ。 |

## 3. 冲突与处理

1. **电子签证的停留期**：驻华使馆和驻上海总领馆的 2023 年通知写「30 天内旅游目的短期单次」，外务省 eVISA 页（2026-05-15 版）写「15 天」或「30 天」。JSON 采用外务省较新的说法，并提示递交前再看一次管辖使领馆页面。
2. **JNTO 热线的语言**：热线页写英、中、韩，安全页写英、中、韩、日。JSON 只写「可用中文」，两页都支持这个说法。
3. **观光特急巴士的运行日**：交通局「お得な乗車券」页（2024-04-01）写「土休日に運行」，EX 专页没写具体日期。JSON 写「交通局页面写明周末和节假日运行」，并提醒 11/16–18 是工作日，出发前以时刻表为准。
4. **外务省中国签证英文页**的页面日期是 2022-09-28，偏旧。签证细节以「代办旅行社清单 + 管辖使领馆页面」为准，JSON 里已这样写。
5. **Apple Pay ICOCA 的设备地区**：JR 西日本写「设备地区需设为日本」，Apple 支持页没有这个要求。JSON 两边都照写，没有下结论。

## 4. 未解决 / 未核实

- **护照最短剩余有效期**：没有找到日本官方写明的固定期限（法务省入管厅页面被拦截，没能读到）。JSON 写「官方页面没有写明」，另给出 VJW 的 6 个月警告，并把「晚于 2028-05-18」标为编辑建议值。
- **VJW 的登记窗口**（最早和最晚提前几天）：数字厅页面没有写；VJW 本站的 FAQ 和手册在无头浏览器下返回 404 或拦截，没有读到。
- **国内发行的银行卡能否在 Apple 钱包给 ICOCA 充值**：官方没有针对中国发卡行的说明，JSON 写「以发卡行和 Apple 规则为准」，并给出现金充值的替代办法。
- **免税新制度的 PDF**（手续变更对照表、旅行者宣传单、购买对象一览）按「不下载文件」的要求没有打开，所以一般物品和消耗品的合并规则、上限金额等细节没有写进 JSON。
- **关西机场官网**（交通方式、行李寄送）被 Akamai 拦截，没能读取。机场到京都只写了 JR 西日本 HARUKA 停车站这一条已核实的信息，没有写时长和票价。
- **法务省入管厅**的入境审查页面（指纹、面部照片等）没能读取，没有写进 JSON。
- **回国时的中国海关规定**（免税额度等）没有调研，没有写进 JSON。
- **2027 年的规则**：市巴士「市民优先价格」须国家认可，一日券价格还在研究；签证政策、免税制度的运行细节、住宿税、外交部提醒都可能变化。JSON 各处已写明出发前再核对。
- 外务省和使领馆页面没能实时读取，读的是 2026-02 到 2026-09 之间的 Internet Archive 快照（日期见上表）。正式发布前，建议有人在普通浏览器里重新打开这些官方 URL 核对一遍。

## 5. 编辑建议（不是官方规定，JSON 里已标注「编辑建议」）

- 签证从出发前 2 个月开始办；VJW 在出发前 3 天填好；落地前安排好网络；刷卡时选日元结算；带 A 型转换插头；穿容易穿脱的鞋。
- 符号用 `JP¥` / `¥`。
