# Touch Bar Brightness for Omarchy

Apple Silicon / T2 MacBook Pro の Touch Bar の輝度を、Omarchy quattro の輝度コントロールと同じ作法で扱うためのツール一式です。Omarchy シェルのプラグイン(`kazu.touchbar`)として配布でき、Omarchy のメニューから Git の URL を指定してインストールできます。

- **ステータスバーのウィジェット**:Display ウィジェットと同じ見た目で、スライダーと同期モードの切り替えを提供
- **キー操作**:CTRL+輝度キーで ±5%、CTRL+ALT+輝度キーで ±1%(画面用の 輝度キー / ALT+輝度キー と同じ並び)
- **自動同期**:キーボードバックライト(または照度センサー)に連動。ロック画面での消灯や蓋を閉じたときは Touch Bar も消灯
- **OSD**:輝度を変えると Omarchy の OSD に表示(アイコン 󰌓)

## 動作環境

| 項目 | 内容 |
|---|---|
| OS | Omarchy quattro(Hyprland の Lua 設定、Quickshell ベースの `omarchy-shell`) |
| ハードウェア | Touch Bar 付き MacBook Pro<br>Apple Silicon(Asahi Linux、`apple,summit` の DSI バックライト)または T2 Mac(`appletb_backlight`) |
| 必要なコマンド | `brightnessctl`、`jq`、`hyprctl`(いずれも Omarchy に標準で入っています) |
| 照度センサー連動(任意) | IIO の照度センサー(Apple Silicon では `aop-sensors-als`) |

## インストール

### 1. プラグインを追加する

**メニューから:** Omarchy メニュー → **Setup → Plugins → Add Plugin** を開き、次の URL を入力します。

```
https://github.com/kazuhidet/Omarchy-Mac-TouchBarBrightnessColtrol
```

「Enable now?」で Yes を選び、置き場所に `right` を選びます。

**コマンドから:**

```bash
omarchy plugin add https://github.com/kazuhidet/Omarchy-Mac-TouchBarBrightnessColtrol --enable
omarchy bar move kazu.touchbar --after omarchy.monitor   # Display の右隣に置く場合
```

プラグインは `~/.config/omarchy/plugins/kazu.touchbar/` に clone されます。この時点でステータスバーにアイコンが出て、スライダーでの調整ができます。

### 2. セットアップを実行する

`omarchy plugin add` はセキュリティ上の理由でプラグイン内のスクリプトを実行しません。同期サービス・コマンド・キー割り当ては、次のどちらかで別途セットアップします。

- ステータスバーの Touch Bar パネルを開き、**Set up sync service and keys** を押す(ターミナルが開いて実行されます)
- またはターミナルで次を実行する

```bash
~/.config/omarchy/plugins/kazu.touchbar/bin/omarchy-brightness-touchbar-setup install --bindings
```

セットアップの内容は次のとおりです。

| 内容 | 場所 |
|---|---|
| コマンドのシンボリックリンク | `~/.local/bin/omarchy-*touchbar*` → プラグインの `bin/` |
| 同期サービス(有効化して起動) | `~/.config/systemd/user/omarchy-brightness-touchbar-sync.service` |
| キー割り当て(`--bindings` 指定時) | `~/.config/hypr/bindings.lua` の末尾にマーカー付きで追記 |

`--bindings` を付けないと、キー割り当ては追加しません。`bindings.lua` に `omarchy-brightness-touchbar` の割り当てがすでにある場合も、追記しません。

状態の確認は `omarchy-brightness-touchbar-setup status` で行えます。

### 3. tiny-dfr の自動調整を止める(推奨)

Touch Bar の表示を担当する tiny-dfr は、既定では画面の明るさに合わせて Touch Bar の明るさを書き換えます(詳しくは「[tiny-dfr との競合](#tiny-dfr-との競合)」)。このままだと、画面の明るさを変えるたびにスライダーや同期の設定が上書きされます。

パネルに **TINY-DFR** 欄が出ている場合は **Turn off tiny-dfr adaptive brightness** を押すか、ターミナルで次を実行します。root 権限が必要なので `sudo` のパスワードを聞かれます。

```bash
~/.config/omarchy/plugins/kazu.touchbar/bin/omarchy-brightness-touchbar-setup tiny-dfr
```

このコマンドが行うことは次のとおりです。

- `/etc/tiny-dfr/config.toml` に `AdaptiveBrightness = false` を書く
  - ファイルがなければ、この 1 行だけのファイルを作ります。tiny-dfr は `/usr/share/tiny-dfr/config.toml` と項目ごとに組み合わせて読むので、ボタンの並びなど他の設定は変わりません。
  - すでにファイルがあれば、`config.toml.bak.<時刻>` にバックアップしてから、先頭にマーカー付きでこの行を足します。元の `AdaptiveBrightness` の行はコメントにします。
- tiny-dfr と同期サービスを再起動する

元に戻すには `omarchy-brightness-touchbar-setup tiny-dfr --revert` を実行します(`uninstall` でも戻ります)。手で設定する場合は、`/etc/tiny-dfr/config.toml` に `AdaptiveBrightness = false` の 1 行を書いて `sudo systemctl restart tiny-dfr` を実行してください。

## 使い方

### ステータスバー

Display ウィジェットの隣に 󰌓 が表示されます。

- **クリック**:パネルを開閉
- **ホイール**:±5%(OSD を表示)
- **パネル**
  - BRIGHTNESS スライダー:Touch Bar の輝度
  - SYNC:Keyboard / Ambient / Manual の切り替え
  - キーボード操作:j/k で項目移動、h/l で値・選択の変更、Enter で決定、Tab で隣のパネルへ

### キー

| キー | 動作 |
|---|---|
| 輝度キー / ALT+輝度キー | 画面の輝度 ±5% / ±1%(Omarchy 標準) |
| SHIFT+輝度キー | キーボードバックライト(Omarchy 標準)。Keyboard モードでは Touch Bar も連動 |
| CTRL+輝度キー | Touch Bar ±5% |
| CTRL+ALT+輝度キー | Touch Bar ±1% |

### 同期モード

| モード | 動作 |
|---|---|
| Keyboard(既定) | `Touch Bar % = 下限 + キーボード% × (100 − 下限)`。キーボードの自動調整が明るい部屋で 0% にしても、Touch Bar は下限(既定 30%)を保つ |
| Ambient | 照度センサーに連動。8 lux 以下で下限、400 lux 以上で 100%、その間は直線的に変化 |
| Manual | 同期サービスを停止。キーとスライダーだけで調整 |

どのモードでも、次の動きは共通です(Manual では同期サービス自体が止まります)。

- **消灯の連動**:内蔵画面が消えたとき(ロック画面の消灯、DPMS オフ)や蓋を閉じたときは Touch Bar を 0 にし、復帰したら元の明るさに戻します。
- **手動調整の優先**:キーやスライダーで調整すると、同期を一時停止します。キーボードの明るさ(Ambient では照度)が変わると同期を再開します。
- **手動の off**:`omarchy-brightness-touchbar off` で消した場合は、手動で `on` にするまで消えたままです。

### コマンド

```bash
omarchy-brightness-touchbar               # 現在の輝度(%)を表示
omarchy-brightness-touchbar +5% | 5%- | 50%
omarchy-brightness-touchbar --no-osd 40%
omarchy-brightness-touchbar off | on

omarchy-brightness-touchbar-sync-mode     # keyboard / ambient / off を表示
omarchy-brightness-touchbar-sync-mode ambient

omarchy-hw-touchbar                       # 検出した Touch Bar のバックライトデバイス名

omarchy-shell kazu.touchbar state         # シェル IPC(brightness <N> / syncMode <mode> / open / close / toggle)
```

`omarchy brightness touchbar` の形では呼べません。`omarchy` コマンドは、Omarchy のパッケージに含まれるコマンドしか呼び出せないためです。

### 設定

`~/.config/omarchy/touchbar-sync.env`(パネルや `sync-mode` コマンドからも書き換わります)

```sh
OMARCHY_TOUCHBAR_SYNC_MODE=keyboard   # keyboard / ambient
OMARCHY_TOUCHBAR_SYNC_MIN=30          # 連動時の下限 %(0〜100)
```

手で編集した後は `systemctl --user restart omarchy-brightness-touchbar-sync` を実行してください。

OSD のアイコンは環境変数 `OMARCHY_TOUCHBAR_OSD_ICON`(Nerd Font の文字)で変更できます。

## 更新

```bash
omarchy plugin update kazu.touchbar
```

コマンドはシンボリックリンクなので、自動で新しい版になります。サービスファイルが変わった場合は `omarchy-brightness-touchbar-setup install` を再実行してください。QML の変更が反映されない場合は `omarchy restart shell` を実行します。

## アンインストール

```bash
omarchy-brightness-touchbar-setup uninstall   # サービス・リンク・追記したキー割り当て・tiny-dfr の変更を元に戻す
omarchy plugin remove kazu.touchbar
```

`touchbar-sync.env` と、編集前のバックアップ(`*.bak.<時刻>`)は残ります。

## トラブルシューティング

| 症状 | 確認すること |
|---|---|
| パネルに「NO TOUCH BAR FOUND」と出る | `omarchy-hw-touchbar` が何も出力しない。`ls /sys/class/backlight` で `appletb_backlight` か `*.dsi.*` があるか確認 |
| 同期しない | `omarchy-brightness-touchbar-setup status`、`journalctl --user -u omarchy-brightness-touchbar-sync` |
| Ambient を選ぶと Manual に戻る | 照度センサーが見つからず、サービスの起動条件チェックで止まっている。`ls /sys/bus/iio/devices/*/in_illuminance*` で確認 |
| アイコンや QML の変更が反映されない | `omarchy restart shell` |
| 画面の明るさを変えると Touch Bar の明るさも変わる | tiny-dfr の自動調整が有効。`omarchy-brightness-touchbar-setup tiny-dfr --check` が `adaptive` なら、[手順 3](#3-tiny-dfr-の自動調整を止める推奨) を実行 |

## tiny-dfr との競合

Touch Bar の表示を担当する `tiny-dfr` は、既定の設定(`/usr/share/tiny-dfr/config.toml` の `AdaptiveBrightness = true`)で、**画面の明るさが変わるたびに Touch Bar の明るさを画面に合わせて書き換えます**。実測では、画面の明るさを変えた 1〜2 秒後に Touch Bar の値が書き換わりました。

その結果、画面の明るさを変えると次のようになります。

- Touch Bar の明るさが tiny-dfr の計算値に変わる
- 同期サービスはそれを手動調整とみなし、キーボードの明るさが次に変わるまで同期を止める

`omarchy-brightness-touchbar-setup tiny-dfr`([手順 3](#3-tiny-dfr-の自動調整を止める推奨))で tiny-dfr の自動調整を止めると、Touch Bar の明るさを書き込むのはこのツールだけになります。

`omarchy plugin add` はプラグイン内のスクリプトを実行しないので、この変更が自動で入ることはありません。root 権限が必要な手順はこれだけなので、本人が選んだときにだけ実行する形にしています。

## リポジトリ構成

```
manifest.json      Omarchy シェルプラグインのマニフェスト(kind: bar-widget)
Panel.qml          ステータスバーのウィジェットとパネル
bin/               Touch Bar 用コマンド(セットアップで ~/.local/bin にリンク)
systemd/           同期サービスのユニットファイル
docs/              実装の解説
reference/         参考にした Omarchy 本体のスクリプト(変更なしの写し)
```

実装の詳細は [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md) を参照してください。
