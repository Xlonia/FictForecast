# 幻想气象局 · FictForecast

[中文](#中文) · [English](#english) · [日本語](#日本語)

Current version / 当前版本 / 現在のバージョン: **0.0.1classic (m2)**

---

## 中文

欢迎来到您心灵中世界的天气预报厅！我们将会为这个世界的气候提供一丝可靠的预测，用于国民的日常生息，今日就让我们从穿衣开始吧。

幻想气象局读取逐月气象表格数据，通过带种子的随机模拟出每一天的气温与气象表现。你可以自定义各类气象成因——诸如 OTL 的台风、季风，以此做出反常的天气逻辑；气象动画/滤镜与城市景观背景图、系统桌面替换在计划中；将来还能通过“科技偏差”模拟预报与实际气候的差异。用于创作，以及向同好炫耀。

为了支持那些天气远离地球的世界，我们还计划支持特殊生态/气候——着力构建这个崭新的世界吧。

### 功能（0.0.1classic m2）

- 天气预报主界面：顶栏菜单/帮助/时钟，左上日高温、低温、降雨可能，中央动画天空图标（晴/阴/雨），夜间背景变暗
- 气候引擎：随机种子来自日期；跨月 15 天加权；按日照时长加权抽取晴/阴/雨；气象记录硬钳制
- 设置编辑器（内嵌独立窗口）：世界设置 JSON（种子、基准时间/日期、波动与日照参数、现象日期离散、年度补偿）、气候现象模板 JSON（规模/形状/规则/持续/速度/路径关键帧/起源纬度带/现象关系）、城市设置 JSON（经纬度/海拔/时区/历法/壁纸/效果）、本地化 YAML
- 两座搭载城市（`Climate/*.csv`，一城一文件）
- 开发自检套件与世界随机搭台层（恒定公历锚点 + 镜像折返、世界三层种子、世界名数字码、城市柏林噪点）

### 运行

用 Godot 4.x 打开工程目录（含 `project.godot`）后运行，或：

```
godot --path "D:\path\to\FictForecast"
```

设置编辑器：主界面「菜单 → 设置编辑器」，或批处理 `open_editor.bat`，或命令行：

```
godot --path "D:\path\to\FictForecast" -- --open-editor
```

开发自检：

```
godot --headless --path "D:\path\to\FictForecast" --script res://scripts/dev_selftest.gd
```

### 数据约定

- `Climate/<城市>.csv`：一城一文件；逐行一个月＝12 个月值＋键名＋注释（可省略）；月份表头行自动跳过，键名首列或末列均可。
- `Cities/<城市>.json`：城市设置；`Worlds/<世界>.json`：世界设置；`Worlds/<世界>.phenomena.json`：气候现象模板；`Localization/zh.yaml`：显示名（受限 YAML 子集）。
- 已识别键：平均日高温 / 平均日低温 / 平均日均温 / 平均降水量 / 平均日照时长 / 平均湿度 / 气象记录高温 / 气象记录低温 / 平均降水天数 / 平均降雪天数；未映射行（如未来的「气候表现-*」权重）原样保留。

### 许可

MIT —— 见 [LICENSE](LICENSE)。

---

## English

Welcome to the weather-forecast hall of the worlds inside your mind! We bring a touch of reliable prediction to your world's climate — for the daily life of its inhabitants. Today, let's start with what to wear.

FictForecast reads a monthly climate table and simulates daily temperature and weather presentation through seeded randomness. You can customize the causes behind weather — Earth-style typhoons and monsoons, or logic that breaks every terrestrial rule. Custom weather animations/filters and city scenery wallpapers, even desktop replacement, are planned; a "tech-deviation" knob will one day let forecasts drift from the true climate. Made for worldbuilding — and for showing off to fellow enthusiasts.

To support worlds whose weather is far from Earth's, special ecologies and climates are on the roadmap. Come build this brand-new world with us.

### Features (0.0.1classic m2)

- Forecast UI: top-bar menus/help/clock, daily high & low plus rain chance, animated sky icon (sunny/cloudy/rainy), night-dimmed backdrop
- Climate engine: date-seeded deterministic weather, cross-month 15-day blending, sunshine-weighted sky sampling, record clamping
- Settings editor (native window): world JSON (seed, base times/dates, fluctuation & daylight params, phenomena spread, annual compensation), climate-phenomenon templates JSON (scale/shape/rules/duration/speed/path keyframes/origin latitude band/inter-phenomenon relations), city JSON (coords/altitude/timezone/calendar/wallpaper/effects), YAML localization
- Two bundled cities (`Climate/*.csv`, one file per city)
- Dev selftest suite and the world-randomness scaffolding (constant Gregorian anchor with mirrored dates, world year/month/day seeds, world-name numeric code, Perlin city noise)

### Getting started

Open the project folder (contains `project.godot`) with Godot 4.x and run, or:

```
godot --path "D:\path\to\FictForecast"
```

Settings editor: in-app menu → 设置编辑器, batch file `open_editor.bat`, or:

```
godot --path "D:\path\to\FictForecast" -- --open-editor
```

Headless selftest:

```
godot --headless --path "D:\path\to\FictForecast" --script res://scripts/dev_selftest.gd
```

### Data conventions

- `Climate/<city>.csv` — one city per file; one month per row: 12 monthly values + key + optional comment. Month header rows are skipped automatically; the key column may sit first or last.
- `Cities/<city>.json` — city settings; `Worlds/<world>.json` — world settings; `Worlds/<world>.phenomena.json` — climate-phenomenon templates; `Localization/zh.yaml` — display names (restricted YAML subset).
- Recognized keys: 平均日高温 / 平均日低温 / 平均日均温 / 平均降水量 / 平均日照时长 / 平均湿度 / 气象记录高温 / 气象记录低温 / 平均降水天数 / 平均降雪天数. Unmapped rows (like the future `气候表现-*` weights) are preserved untouched.

### License

MIT — see [LICENSE](LICENSE).

---

## 日本語

ようこそ、あなたの心の中の世界の天気予報ホールへ！この世界の気候に少し信頼できる予報をお届けします——国民の暮らしのために。今日はまず、服装の話から始めましょう。

幻想気象局は月ごとの気候表を読み込み、シード付きの乱数で毎日の気温と天気をシミュレートします。台風やモンスーンのような現実の気象成因から、地球の法則を破る異常な気象ロジックまで、自由にカスタマイズ可能。気象アニメーション/フィルター、都市の風景壁紙、デスクトップ置き換えは計画中で、将来は「技術偏差」で予報と実際の気候のずれも表現できます。創作のために、そして仲間に自慢するために。

地球から遠い空を持つ世界を支えるため、特殊な生態・気候もロードマップに含まれています。この新しい世界を一緒に作りましょう。

### 機能（0.0.1classic m2）

- 予報 UI：メニュー/ヘルプ/時計バー、日最高・最低気温と降水確率、アニメーションする空アイコン（晴/曇/雨）、夜は背景が暗くなる
- 気候エンジン：日付シードの決定論的乱数、月跨ぎ 15 日の加重補間、日照時間による晴/曇/雨の加重抽選、観測記録によるクランプ
- 設定エディタ（独立ウィンドウ）：世界設定 JSON（シード、基準時刻/日付、変動と日照パラメータ、現象日付のばらつき、年次補償）、気候現象テンプレート JSON（規模/形状/規則/持続/速度/経路キーフレーム/発生緯度帯/現象間の関係）、都市設定 JSON（経緯度/標高/タイムゾーン/暦/壁紙/エフェクト）、YAML ローカライズ
- 同梱都市 2 つ（`Climate/*.csv`、1 都市 1 ファイル）
- 開発用セルフテストと、世界乱数の足場（恒定グレゴリオ暦アンカー＋ミラー折返し、世界の年/月/日シード、世界名の数値コード、都市のパーリンノイズ）

### 使い方

`project.godot` を含むフォルダを Godot 4.x で開いて実行、または：

```
godot --path "D:\path\to\FictForecast"
```

設定エディタ：アプリ内メニュー → 设置编辑器、バッチ `open_editor.bat`、または：

```
godot --path "D:\path\to\FictForecast" -- --open-editor
```

ヘッドレス・セルフテスト：

```
godot --headless --path "D:\path\to\FictForecast" --script res://scripts/dev_selftest.gd
```

### データ規約

- `Climate/<都市>.csv` — 1 都市 1 ファイル。1 行 = 1 か月：月値 12 個＋キー＋注釈（省略可）。月ヘッダー行は自動スキップ、キー列は先頭/末尾どちらも可。
- `Cities/<都市>.json` — 都市設定。`Worlds/<世界>.json` — 世界設定。`Worlds/<世界>.phenomena.json` — 気候現象テンプレート。`Localization/zh.yaml` — 表示名（限定 YAML サブセット）。
- 認識するキー：平均日高温 / 平均日低温 / 平均日均温 / 平均降水量 / 平均日照時長 / 平均湿度 / 気象記録高温 / 気象記録低温 / 平均降水日数 / 平均降雪日数。未マッピング行（将来の「気候表現-*」重みなど）はそのまま保持されます。

### ライセンス

MIT —— [LICENSE](LICENSE) を参照。
