# 実装メモ

Touch Bar の輝度制御を Omarchy quattro の輝度まわりの仕様に合わせて実装した際の、設計と判断の記録です。

## 全体構成

```
                ┌──────────────────────────── Omarchy ────────────────────────────┐
 キー (CTRL+輝度) │ bindings.lua ─┐                                                 │
 バー (kazu.touchbar) Panel.qml ──┼─► omarchy-brightness-touchbar ─► brightnessctl ─┼─► /sys/class/backlight/<touchbar>
                                 │        │  └─► omarchy-osd (󰌓)                    │
                                 │        └─► omarchy-hw-touchbar(デバイス検出)       │
 systemd --user                  │                                                 │
   omarchy-brightness-touchbar-sync ─ 1 秒ごとに確認 ─► kbd_backlight / ALS / DPMS / 蓋 │
                                 └─ omarchy-brightness-touchbar-sync-mode ─► touchbar-sync.env + systemctl
```

どの入口(キー、スライダー、IPC、同期サービス)も、最終的には同じコマンドと sysfs を通ります。手動調整の検知(後述)が成り立つのはこのためです。

## コマンド

### `omarchy-hw-touchbar`

`omarchy-hw-display` と同じ形にしています。デバイス名を 1 行出力し、見つからなければ exit 1 で終わります。`OMARCHY_BACKLIGHT_PATH` で検索先を差し替えられます。

1. `appletb_backlight`(T2 Mac。`hid-appletb-bl` が登録するもの)
2. デバイスツリーの compatible に `apple,summit` を含むバックライト(Apple Silicon。例:`228600000.dsi.0`)

名前の順番に頼らず compatible で判定しているので、画面本体のバックライト(`apple-panel-bl`)を誤って選ぶことはありません。逆に、`omarchy-hw-display` は `appletb_backlight` を除外し `apple-panel-bl` を優先するので、2 つのスクリプトの検出結果が重なることはありません。

### `omarchy-brightness-touchbar`

`omarchy-brightness-display` と同じ仕様にしています。

| 項目 | 内容 |
|---|---|
| 引数 | `[--no-osd] [+N%\|N%-\|N%\|off\|on]`。引数なしなら現在の % を表示 |
| 排他制御 | `flock -n`。キーを押し続けたときに起動が重なったら、後から来たものを捨てる |
| `+5%` / `5%-` の扱い | 5% 以下では 1% 刻みにする。それ以外は、目標の % を計算して絶対値で設定する。Touch Bar のバックライトは 0〜255 と段階が粗いので、相対指定で丸め誤差がたまるのを避けるため |
| 下限 | 1%。0 は `off` でだけ設定する |
| `off` / `on` | 画面用の display 版は DPMS を使うが、Touch Bar 版は `brightnessctl --save` で 0 にし、`--restore` で戻す |
| OSD | `omarchy-osd -i <glyph> -p <%>`。`OsdModel.js` の `iconFor()` は登録されていない名前をそのまま文字として表示するので、Nerd Font の文字(󰌓)を直接渡している。キーボードバックライトの OSD(󰌌)とは別の文字にしている |

### `omarchy-brightness-touchbar-sync`

`omarchy-brightness-keyboard-auto` と同じ構造です(`--once`、`--available`、`ExecCondition` での起動条件チェック)。LED や backlight の `brightness` は値が変わっても通知(uevent、inotify)が来ないので、1 秒ごとに読みに行きます。

1 回の確認(`tick`)の流れは次のとおりです。

1. **消灯の判定**:`hyprctl monitors -j` の内蔵パネル(eDP/LVDS/DSI)がすべて `dpmsStatus=false` か、`omarchy-hw-laptop-closed` が真なら、現在値を退避して 0 にする。
   - ロック画面の消灯処理(`lock/Service.qml` の `omarchy-brightness-display off`)も、蓋を閉じたときや外部モニターだけで使うときも、これで拾える。
2. **復帰**:消灯状態から戻ったら、退避した値に戻す。`omarchy-system-wake` の `display on` に対応する。
3. **手動調整の検知**:前回自分が書き込んだ値(`last_set`)と現在値が違えば、誰かが手で変えたとみなし、同期を一時停止する。その時点の同期元の値(`pause_value`)を記録する。
   - キーボードの自動調整(`keyboard-auto`)の「手動で書き込まれたら一時停止する」仕組みと同じ考え方。
4. **再開**:keyboard モードでは `pause_value` から値が変わったら再開する。ambient モードでは `keyboard-auto` と同じしきい値(±20 lux または ±40% の大きい方)を超えたら再開する。手動で 0 にしていた場合は再開しない。
5. **目標値の適用**:keyboard モードは `min + kbd% × (100 − min)`。ambient モードは 8〜400 lux を下限〜100% に直線で対応させ、4% 未満の差は無視して揺れを抑える。

同期サービスはキーボードの LED に一切書き込みません。このため `keyboard-auto` の一時停止の判定や、`omarchy-brightness-keyboard off/restore` とぶつかりません。

### `omarchy-brightness-touchbar-sync-mode`

`~/.config/omarchy/touchbar-sync.env` を唯一の設定元にしています。`keyboard` / `ambient` を指定すると、その行だけ書き換えてサービスを `enable` + `restart` します。`off` を指定すると `disable --now` します。引数なしならサービスの状態と設定ファイルから現在のモードを返します。

### `omarchy-brightness-touchbar-setup`

`omarchy plugin add` は、clone・検証・有効化しかしません(フックの実行や sudo は使わない)。それを補うのがこのコマンドです。

- **コマンド**:`~/.local/bin` にシンボリックリンクを張ります。`omarchy plugin update`(fast-forward pull)だけで新しい版になります。ただし `omarchy plugin validate` はプラグインフォルダの**中に**シンボリックリンクがあると拒否するので、リンクは必ず外向き(`~/.local/bin` → プラグイン)にしています。
- **systemd ユニット**:リンクではなくコピーします。検索パスの外にあるユニットへのリンクは、systemd では「linked unit」という別の扱いになるためです。quattro が `~/.config/systemd/user` を使わない方針にしているのはパッケージが配るユニットの話なので、ユーザーが自分で作ったユニットを置くのは問題ありません。
- **キー割り当て**:`-- >>> kazu.touchbar bindings >>>` から `<<<` までのマーカーで囲んで追記します。`uninstall` ではこの範囲だけを削除します。手で書いた割り当てがすでにある場合は触りません。
- **tiny-dfr**(`tiny-dfr [--check|--revert]`):root 権限が必要な唯一の手順なので、`install` には含めず、別のサブコマンドにしています。詳しくは次の節を参照してください。

## tiny-dfr との競合

tiny-dfr は `AdaptiveBrightness = true`(既定)のとき、画面の明るさが変わると Touch Bar の明るさを書き換えます。実測では、`apple-panel-bl` を 5 → 15 にすると Touch Bar が 79 → 22 になり、5 に戻すと 13 になりました。同期サービスはこれを手動調整と区別できないので、tiny-dfr の自動調整を止め、Touch Bar の明るさはこのツールだけが書き込む形にしています。

配布するうえでの判断は次のとおりです。

| 方法 | 採否 | 理由 |
|---|---|---|
| `setup tiny-dfr` で本人が選んだときに sudo で書く | 採用 | root が必要な変更を、内容を見せたうえで 1 回だけ行える |
| `omarchy plugin add` で自動的に書く | 不採用 | Omarchy はプラグインのスクリプトを実行しない方針 |
| パッケージで `/etc/tiny-dfr/config.toml` を配る | 不採用 | 利用者が自分で書いた設定ファイルとぶつかる |
| polkit で常に許可する | 不採用 | 一度きりの設定変更のために常時の権限を渡すことになる |

- **書く内容**:`/etc/tiny-dfr/config.toml` は `/usr/share/tiny-dfr/config.toml` に項目ごとに重ねて読まれるので、`AdaptiveBrightness = false` の 1 行だけで済みます。新しく作るファイルの先頭には `# Created by kazu.touchbar` の行を入れ、`--revert` ではファイルごと削除します。
- **既存のファイルがある場合**:先頭に `# >>> kazu.touchbar >>>` 〜 `<<<` のブロックを足し、元の `AdaptiveBrightness` 行の先頭に `#kazu.touchbar# ` を付けてコメントにします。TOML ではキーの重複がエラーになるためです。ブロックを先頭に置くのは、`[table]` より前のトップレベルのキーとして読ませるためです。`--revert` ではブロックを消し、コメントを外します。
- **反映**:書き換えたら `systemctl try-restart tiny-dfr` を実行します。tiny-dfr は起動時に Touch Bar を `ActiveBrightness` にするので、続けて同期サービスも再起動し、同期の値に戻します。
- **パネル**:状態を読むときに `tiny-dfr --check`(`adaptive` / `static` / `none`)も実行します。`adaptive` なら TINY-DFR 欄とボタンを出します。ボタンを押すと、sudo のパスワードを入力できるようにターミナルで実行します。

## キー割り当ての方針

Omarchy の Mac 向け版(`default/hypr/bindings/media.lua`)は、SHIFT+輝度キーをキーボードバックライトに割り当てています。Touch Bar はこれを上書きせず、修飾キーの並びを画面用に合わせました。

| 修飾キー | 画面 | Touch Bar |
|---|---|---|
| なし | ±5% | CTRL ±5% |
| ALT | ±1% | CTRL+ALT ±1% |

## シェルプラグイン(`Panel.qml`)

組み込みの Display ウィジェット(`plugins/panels/monitor/Panel.qml`)の構造をそのまま使っています。

- `Panel` を元にし、`manageIpc: false` にして独自の `IpcHandler`(`brightness` / `syncMode` / `state` / `open` / `close` / `toggle`)を持たせている。
- `BarIconButton`:クリックでパネルを開閉し、ホイールで ±5%。OSD は `bar.shell.summon("omarchy.osd", …)` で出す。
- `KeyboardPanel` + `PanelKeyCatcher`:j/k/h/l/Enter のカーソル操作。sections は `brightness`(スライダー、selectedIndex は -1)と `sync`(ボタン 3 つ)の 2 つ。
- スライダーは Display と同じく、180ms のデバウンスと実行中の書き込みのキューイングで値を送る。書き込み中とデバウンス中は状態の読み直しをせず、スライダーが一瞬古い値に戻るのを防いでいる。
- 同期サービスが Touch Bar の値を変えるので、パネルを開いている間は 2 秒ごとに状態を読み直す(Display は 5 秒ごと)。
- コマンドは `Qt.resolvedUrl("bin")` で得たプラグイン内の `bin/` を PATH の先頭に置いて実行する。セットアップ前でも、`~/.local/bin` にある古い版があっても、プラグインに同梱した版が使われる。
- 同期サービスのユニットがなければ、SYNC 欄にモード切替ボタンの代わりにセットアップボタンを出す。押すと `omarchy-launch-floating-terminal-with-presentation` で、ターミナル上でセットアップを実行する。

### ホットリロードについて

`~/.config/omarchy/plugins/` 以下のファイルを保存すると「Local plugin changed, reloading」とログに出て再読み込みされます。ただし、QML のコンポーネントキャッシュのせいで変更が描画に反映されないことがありました。その場合は `omarchy restart shell` を実行してください。

## 確認方法

- `hyprctl` を偽物に差し替える:PATH の先頭に置いたスクリプトで、DPMS オフの JSON を返す。こうすると実際の画面を消さずに、消灯と復帰の流れを確認できる。
- `OMARCHY_BACKLIGHT_PATH` / `OMARCHY_LEDS_DIR` / `OMARCHY_IIO_DEVICES_DIR`:sysfs を偽のディレクトリに差し替えて、デバイス検出を確認できる。
- `OMARCHY_TINY_DFR_DEFAULT` / `OMARCHY_TINY_DFR_CONF`:tiny-dfr の設定ファイルの場所を差し替えられる。`sudo` と `systemctl` を、引数をそのまま実行するだけの偽物に PATH で差し替えると、root 権限なしで `tiny-dfr` / `--revert` の動きを確認できる。
- `omarchy-shell kazu.touchbar state`:パネルが持っている状態を JSON で確認できる。

## 今後の課題

- tiny-dfr の `backlight_high.svg`(Material Symbols)を、バーとパネルのアイコンに使う。`BarIconButton.iconComponent` に画像を差し込めば実現できる。OSD は文字しか表示できないので、OSD プラグインを複製しないと使えない。
