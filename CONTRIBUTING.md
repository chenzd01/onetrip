# 参与贡献 · Contributing

中文在前，English below.

谢谢你愿意让 OneTrip 变得更好。最有价值的贡献通常是这几类：

- **修 bug、改进 App**：对任何目的地都成立的改进，而不是只为某一座城市写死的逻辑。
- **改进调研方法**：`docs/*/research-playbook.md` 里的规则、核对步骤和踩过的坑。
- **翻译**：App 界面目前只有中文，英文界面是路线图上的头号事项，欢迎认领。
- **分享你的目的地**：用 [「分享你的目的地」](https://github.com/chenzd01/onetrip/issues/new?template=showcase.yml) 模板投稿，精选会放进 README 的 Showcase。

## 开发流程

1. Fork 后新建分支，跑一遍 `make setup && make test`，确认环境正常。
2. 改动尽量小而完整：一个 PR 解决一件事，附上你跑过的测试和结果。
3. App 代码里不写城市名、日期、货币或坐标，这些都来自 `content/trip.json`；换一个目的地时测试也应当通过。
4. 提交前运行 `python3 scripts/privacy_check.py`。**不要**提交行程、住处、证件号、订单号、`ios/Signing.xcconfig`、`ios/SharedAccess.xcconfig`、`.p8` 密钥或任何个人数据。
5. 示例内容（`content/`）的文字以 CC0 贡献；照片只接受开放许可，并在 `photo-sources.json` 写清作者、许可证和来源。

用 AI Agent 写代码完全没问题，本项目本身就是这样做出来的。请让它先读 `AGENTS.md`，并由你自己核对它声称通过的检查。

---

Thanks for helping make OneTrip better. The most valuable contributions are usually:

- **Bug fixes and app improvements** that work for any destination, not logic hard-wired to one city.
- **Better research methods**: rules, checks and pitfalls in `docs/*/research-playbook.md`.
- **Translation**: the app UI is Chinese-only today; an English UI is the top roadmap item.
- **Show your trip** with the [Show your trip](https://github.com/chenzd01/onetrip/issues/new?template=showcase.yml) template; picks are featured in the README.

## Workflow

1. Fork, create a branch and run `make setup && make test` to check your environment.
2. Keep changes small and complete: one concern per pull request, with the tests you ran and their results.
3. No city names, dates, currencies or coordinates in app code; they come from `content/trip.json`, and the tests should pass with any destination's content.
4. Run `python3 scripts/privacy_check.py` before committing. **Never** commit itineraries, addresses, ID or booking numbers, `ios/Signing.xcconfig`, `ios/SharedAccess.xcconfig`, `.p8` keys or other personal data.
5. Text in the sample content (`content/`) is contributed under CC0; photos must be openly licensed, with creator, license and source in `photo-sources.json`.

Using an AI coding agent is welcome; this project was built that way. Have it read `AGENTS.md` first, and check any result it claims yourself.
