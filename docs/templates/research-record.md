# 调研记录 · Research record：<主题 / Topic>

> 复制到 `docs/research/YYYY-MM-DD-<主题>.md` 后填写。规则见 `docs/zh/research-playbook.md`。
> Copy to `docs/research/YYYY-MM-DD-<topic>.md`. Rules: `docs/zh/research-playbook.md`.
>
> 不要写入证件号、订单号、账号、电话、邮箱、私人截图或个人电脑路径。
> Never include ID/order numbers, accounts, phone numbers, emails, private screenshots or personal file paths.

| 项目 / Field | 内容 / Value |
| --- | --- |
| 日期 / Date | YYYY-MM-DD（写时区 / with time zone） |
| 调研人 / Researcher | 人或 agent 类型，不写真实姓名 / role or agent type, no real names |
| 目的地 / Destination | |
| 旅行日期 / Trip dates | |
| 涉及内容类型 / Content types | 行程 / 地点 / 坐标 / 照片 / 参考帖 / 酒店 / 餐饮 / 准备 / 攻略 / 短句 / 路线 / 汇率 |

## 1. 目的 · Goal

这次要回答什么问题？完成标准是什么？
What question does this session answer? What counts as done?

- 问题 / Question：
- 完成标准 / Done when：

## 2. 约束与前提 · Constraints and assumptions

- 硬约束 / Hard constraints（航班、预约时段、闭馆日 / flights, booked slots, closures）：
- 软约束 / Soft constraints（作息、兴趣、体力 / schedule, interests, energy）：
- 待用户确认 / Waiting for the traveller：

## 3. 来源 · Sources

置信度 / Confidence：高 High = 官方页面在真实浏览器中看到 / official page seen in a real browser；中 Medium = 权威第三方或平台最终页 / authoritative third party or platform final page；低 Low = 攻略、社媒、无法完整读取 / guides, social posts, partially readable.

| # | URL | 读取时间 / Read at | 等级 / Tier (A–D) | 结论 / Finding | 置信度 / Confidence |
| --- | --- | --- | --- | --- | --- |
| 1 | https:// | YYYY-MM-DD HH:mm (TZ) | A | | 高 / High |
| 2 | | | | | |
| 3 | | | | | |

未能读取的来源 / Sources that could not be read（403、验证码、空壳页 / 403, captcha, empty shell）：

| URL | 现象 / What happened | 处理 / Handling |
| --- | --- | --- |
| | | 记为未核实，未作为事实写入 / recorded as unverified, not written as fact |

## 4. 快照观察 · Snapshot observations

价格、订位、报价等会变的信息。都是查询时的快照，不是实时状态。
Prices, reservation slots, quotes — all point-in-time snapshots, not live status.

| 对象 / Item | 查询条件 / Query（日期、人数、餐段、房数 / date, party, meal, rooms） | 结果 / Result | 查询时间 / Checked at | 来源 / Source |
| --- | --- | --- | --- | --- |
| | | 查询时显示… / Showed at query time… | | |

确认：没有提交订单、表单、订位，没有发送消息。
Confirmed: no booking, form, reservation or message was submitted.

- [ ] 是 / Yes

## 5. 冲突与未决 · Conflicts and open questions

| # | 内容 / Topic | 来源 A 说法 / Source A says | 来源 B 说法 / Source B says | 采用 / Adopted | 理由 / Why | 需要谁处理 / Owner |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | | | | 保守写法 / conservative wording | | 出发前再核对 / recheck before departure |

未决事项 / Open items（缺价格、缺照片、缺坐标、待用户选择 / missing price, photo, coordinate, traveller choice）：

- [ ]
- [ ]

## 6. 排除的候选 · Rejected candidates

| 候选 / Candidate | 类型 / Type | 排除原因 / Reason |
| --- | --- | --- |
| | 坐标 / 照片 / 帖子 / 酒店 / coordinate / photo / post / hotel | 同名异地 / 过时 / 授权不明 / 错误信息 / same name elsewhere / outdated / unclear licence / wrong facts |

## 7. 写入了哪些 content 字段 · Content fields changed

| 文件 / File | ID | 字段 / Fields | 变更 / Change |
| --- | --- | --- | --- |
| `content/places.json` | | `opening`, `price`, `sources`, `checkedAt` | |
| `content/locations.json` | | `coordinates`, `source` | |
| | | | |

没有改动已发布的 ID；没有改动用户状态。
No published IDs were changed; no user state was touched.

- [ ] 是 / Yes

## 8. 校验 · Verification

```text
python3 scripts/verify_content.py                     → PASS / FAIL（N errors, N warnings）
python3 scripts/verify_content.py --require-complete  → PASS / FAIL（N errors, N warnings）
```

未处理的警告及原因 / Remaining warnings and why：

-

## 9. 下一步 · Next steps

- [ ]
- [ ]

证据文件（不进 git）/ Evidence files (not committed)：`test-results/<目录 / folder>/`
