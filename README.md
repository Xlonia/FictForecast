# 幻想气象局 · FictForecast

**A weather-forecast studio for fictional worlds.** Feed it a monthly climate table; it hands you a believable daily forecast — highs, lows, rain chance, and the sky itself — for the cities of the worlds you invent. Built with Godot 4.

## What is this?

Welcome to the weather-forecast hall of the worlds inside your mind! We bring a touch of reliable prediction to your world's climate — for the daily life of its inhabitants. Today, let's start with what to wear.

FictForecast reads a monthly climate table and simulates daily temperature and weather presentation through seeded randomness. You can customize the causes behind weather — Earth-style typhoons and monsoons, or logic that breaks every terrestrial rule. Custom weather animations/filters and city scenery wallpapers, even desktop replacement, are planned; a "tech-deviation" knob will one day let forecasts drift from the true climate. Made for worldbuilding — and for showing off to fellow enthusiasts.

To support worlds whose weather is far from Earth's, special ecologies and climates are on the roadmap. Come build this brand-new world with us.

## 欢迎来到您心灵中世界的天气预报厅！

我们将会为这个世界的气候提供一丝可靠的预测，用于国民的日常生息，今日就让我们从穿衣开始吧！

幻想气象局读取逐月气象表格数据，通过带种子的随机模拟出每一天的气温与气象表现。你可以自定义各类气象成因——诸如 OTL 的台风、季风，以此做出反常的天气逻辑；气象动画/滤镜与城市景观背景图、系统桌面替换在计划中；将来还能通过“科技偏差”模拟预报与实际气候的差异。用于创作，以及向同好炫耀。

为了支持那些天气远离地球的世界，我们还计划支持特殊生态/气候——着力构建这个崭新的世界吧！

## Current version: 0.0.1classic

- Weather forecast UI: top bar menus + clock, daily high/low & rain chance, animated sky icon (sunny / cloudy / rainy), night-dimmed backdrop
- Climate engine: date-seeded deterministic weather, cross-month 15-day blending, sunshine-weighted sky sampling, record clamping
- Two built-in cities (`Climate/*.csv`), one per file
- Settings editor (in-app, 菜单 → 设置编辑器): world settings JSON (`seed`, `base_times`, `base_dates`), city settings JSON (`long/lati/alti/times/timez/calendar/wallpaper/effects`), YAML localization
- Dev selftest suite (`scripts/dev_selftest.gd`)

## Getting started

Open the project folder (contains `project.godot`) with Godot 4.x and press Play, or:

```
godot --path "D:\path\to\FictForecast"
```

Headless selftest:

```
godot --headless --path "D:\path\to\FictForecast" --script res://scripts/dev_selftest.gd
```

## Data conventions

- `Climate/<city>.csv` — one city per file; one month per row: 12 monthly values + key + optional comment. The month header row is skipped automatically; the key column may sit first or last.
- `Cities/<city>.json` — city settings (see the settings editor).
- `Worlds/<world>.json` — world settings; cities reference them via `world`.
- `Localization/zh.yaml` — names live here (restricted YAML subset).
- Recognized climate keys: 平均日高温 / 平均日低温 / 平均日均温 / 平均降水量 / 平均日照时长 / 平均湿度 / 气象记录高温 / 气象记录低温 / 平均降水天数 / 平均降雪天数. Unmapped rows (like the future `气候表现-*` weights) are preserved untouched.

## Layout

```
Climate/          city climate tables (CSV)
Cities/           city settings (JSON)
Worlds/           world settings (JSON)
Localization/     display names (YAML)
scenes/           main + settings editor scenes
scripts/          engine, store, editor, icons, selftest
docs/             design drafts (scoring-filter mechanism, …)
幻想气象局.md      design document (the source of truth)
```

## Roadmap

Markov-style day-to-day inertia → monthly quota reconciliation (rain-day counts vs climate table) → weather phenomena (typhoons/cold waves as candidate generators + scoring) → the scoring-filter mechanism itself → world layer ("weather vocabulary": crystal rain instead of rain) → creator-facing scoring hooks, custom calendars, wallpaper/effect playback, sharing packs.

See `docs/随机评分筛选机制-设计草案.md` for the mechanism draft.

## License

MIT — see [LICENSE](LICENSE).
