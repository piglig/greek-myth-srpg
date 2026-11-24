# 第三方美术素材来源

每加入一份外部素材，在这里记一行。**可商用**一栏写"否"的素材，在游戏商业化之前必须替换。

| 目录 | 素材 | 作者 | 许可 | 可商用 | 可随仓库分发 | 来源 | 用了哪些 |
|---|---|---|---|---|---|---|---|
| `nature/` | Stylized Nature MegaKit（免费标准版） | Quaternius | CC0 1.0 | 是 | 是 | https://opengameart.org/content/stylized-nature-megakit | TwistedTree_1–3（橄榄树）、Pine_1 / Pine_3（柏树位置）、Bush_Common、Grass_Wispy_Short。贴图缩到 512，去掉了法线贴图 |

模型只提供形状，叶片颜色由 `view/flora.gdshader` 决定。设置环境变量 `SRPG_FLORA=0` 可以切回程序生成的树，用于对比。

| 目录 | 素材 | 作者 | 许可 | 可商用 | 可随仓库分发 | 来源 | 用了哪些 |
|---|---|---|---|---|---|---|---|
| `pixelfx/` | pixelfx 0.3.1 | Patch、Hugo Duprez | MIT（须保留 `LICENSE` 和 `NOTICE.md`） | 是 | 是 | https://github.com/patch-gg/pixelfx | `impacts/hit-spark`（命中）、`melee/sword-slash`（斩击）、`impacts/heavy-landing`（落地扬尘）、`explosions/small-explosion`（火油罐炸开）、`impacts/blunt-hit`（石块和标枪落点）、`holy/blessing`（喝药）、`status/burning` `nature/toxic-puddle` `status/stunned`（灼烧、中毒、眩晕，状态持续期间一直在身上循环）。新加的几个都按亮度改成了游戏自己的色系、`fire/campfire`（燃烧格）。前三个换成了铜色和石尘色 |

`pixelfx/` 里的图由 `art/tools/bake_pixelfx.py <pixelfx 目录>` 生成，要加特效或换颜色改这个脚本。

| 目录 | 素材 | 作者 | 许可 | 可商用 | 可随仓库分发 | 来源 | 用了哪些 |
|---|---|---|---|---|---|---|---|
| `fusion-pixel/` | 缝合像素字体 Fusion Pixel 2026.11.10 | TakWolf 及各源字体作者 | SIL OFL 1.1（须保留 `OFL.txt`，不得单独售卖字体） | 是 | 是 | https://github.com/TakWolf/fusion-pixel-font | 10 像素和 12 像素的简体中文比例字体，全部界面文字都用它 |

| `game-icons/` | game-icons.net 图标 138 个 | Lorc、Delapouite、Skoll、Cathelineau、HeavenlyDog、Lucas | CC BY 3.0（**必须署名**，名单在目录里的 `CREDITS.txt`） | 是 | 是 | https://game-icons.net | 技能、装备、材料、属性、营地页签、战斗指令的图标。清单和取用脚本：`art/tools/fetch_game_icons.py` |
| `camp/props/` | Fantasy Props MegaKit 标准版（免费部分，94 件里取了 23 件） | Quaternius | CC0 | 是 | 是 | https://quaternius.com/packs/fantasypropsmegakit.html（下载自 https://opengameart.org/content/fantasy-props-megakit ） | 营地的货摊、木箱、木桶、陶罐、布袋、武器架、训练假人、盾、长凳、凳子、旗帜、箱子等。四套共用贴图从 2048 缩到 1024（颜色）/ 512（法线、ORM） |
| `camp/survival/` | Survival Kit 2.0（80 件里取了 11 件） | Kenney | CC0 | 是 | 是 | https://kenney.nl/assets/survival-kit（下载自 https://opengameart.org/content/survival-kit ） | 营地的帐篷、铺盖、原木、路牌。原配色是现代露营的橙黄，游戏里用 `view/camp_canvas.gdshader` 只取明暗，改画成亚麻布和旧木 |
| `camp/greek/` | Doric Greek Column | Victor Viña | CC BY 3.0（**必须署名**） | 是 | 是 | https://poly.pizza/m/5VD5-v8NBZ4 | 营地里一立一倒两根残柱。模型没有贴图，表面用的是游戏里地标的石灰岩质感。 |

署名要求：game-icons 和 `camp/greek/` 的许可要求在游戏里列出作者。发布前需要做一个致谢页面，目前还没有。
