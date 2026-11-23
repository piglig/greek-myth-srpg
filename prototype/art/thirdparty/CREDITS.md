# 第三方美术素材来源

每加入一份外部素材，在这里记一行。**可商用**一栏写"否"的素材，在游戏商业化之前必须替换。

| 目录 | 素材 | 作者 | 许可 | 可商用 | 可随仓库分发 | 来源 | 用了哪些 |
|---|---|---|---|---|---|---|---|
| `nature/` | Stylized Nature MegaKit（免费标准版） | Quaternius | CC0 1.0 | 是 | 是 | https://opengameart.org/content/stylized-nature-megakit | TwistedTree_1–3（橄榄树）、Pine_1 / Pine_3（柏树位置）、Bush_Common、Grass_Wispy_Short。贴图缩到 512，去掉了法线贴图 |

模型只提供形状，叶片颜色由 `view/flora.gdshader` 决定。设置环境变量 `SRPG_FLORA=0` 可以切回程序生成的树，用于对比。

| 目录 | 素材 | 作者 | 许可 | 可商用 | 可随仓库分发 | 来源 | 用了哪些 |
|---|---|---|---|---|---|---|---|
| `pixelfx/` | pixelfx 0.3.1 | Patch、Hugo Duprez | MIT（须保留 `LICENSE` 和 `NOTICE.md`） | 是 | 是 | https://github.com/patch-gg/pixelfx | `impacts/hit-spark`（命中）、`melee/sword-slash`（斩击）、`impacts/heavy-landing`（落地扬尘）、`fire/campfire`（燃烧格）。前三个换成了铜色和石尘色 |

`pixelfx/` 里的图由 `art/tools/bake_pixelfx.py <pixelfx 目录>` 生成，要加特效或换颜色改这个脚本。

| 目录 | 素材 | 作者 | 许可 | 可商用 | 可随仓库分发 | 来源 | 用了哪些 |
|---|---|---|---|---|---|---|---|
| `fusion-pixel/` | 缝合像素字体 Fusion Pixel 2026.11.10 | TakWolf 及各源字体作者 | SIL OFL 1.1（须保留 `OFL.txt`，不得单独售卖字体） | 是 | 是 | https://github.com/TakWolf/fusion-pixel-font | 10 像素和 12 像素的简体中文比例字体，全部界面文字都用它 |

| `game-icons/` | game-icons.net 图标 107 个 | Lorc、Delapouite、Skoll、Cathelineau、HeavenlyDog、Lucas | CC BY 3.0（**必须署名**，名单在目录里的 `CREDITS.txt`） | 是 | 是 | https://game-icons.net | 技能、装备、材料、属性、营地页签的图标。清单和取用脚本：`art/tools/fetch_game_icons.py` |

署名要求：game-icons 的许可要求在游戏里列出作者。发布前需要做一个致谢页面，目前还没有。
