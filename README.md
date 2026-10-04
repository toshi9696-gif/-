# 体組成ログ

TANITA DC-430A のレシートと Apple Watch のデータから、内臓脂肪レベルの改善を追う iPhone アプリ（本人専用）。
仕様は [docs/SPEC.md](docs/SPEC.md) を参照。

## 構成

| パス | 内容 |
|---|---|
| `BodyCompCore/` | レシートの解析と整合性チェック（iPhone に依存しない Swift パッケージ。`swift test` で単体テストできる） |
| `App/` | iPhone アプリ本体（SwiftUI / SwiftData / Vision / HealthKit） |
| `project.yml` | XcodeGen の設定。Xcode プロジェクトはここから生成する |

## ビルド手順（Mac）

初めての方は [docs/SETUP_GUIDE.md](docs/SETUP_GUIDE.md)（非エンジニア向けの詳しい手順）を参照。


1. XcodeGen を入れる：`brew install xcodegen`
2. リポジトリを取得してブランチを切り替える
   ```sh
   git clone https://github.com/toshi9696-gif/-.git body-log
   cd body-log
   git checkout claude/health-app-body-composition-3vl4z1
   ```
3. Xcode プロジェクトを生成して開く：`xcodegen generate && open HealthApp.xcodeproj`
4. Xcode で HealthApp ターゲットを選び、**Signing & Capabilities** の Team に自分のチームを選ぶ。
   毎回選び直したくない場合は、`project.yml` の `DEVELOPMENT_TEAM` に Team ID を書く。
5. iPhone を接続し、実行先に選んで ▶︎ で実行する。
   書類スキャナ（カメラ）とヘルスケアは、シミュレータでは使えない。実機で確認する。

`project.yml` を変えたとき、またはファイルを追加・削除したときは、`xcodegen generate` をやり直す。

## 単体テスト

```sh
cd BodyCompCore
swift test
```

## M1 でできること

- カメラ（書類スキャナ）または写真からレシートを読み取る
- 確認画面で全項目を表示し、整合性チェックに失敗した項目を赤く表示する。値は手で修正できる
- アプリ内に保存する。同じ日時の記録がある場合は、上書きするかを確認する
- 体重・体脂肪率・除脂肪量・BMI（初回のみ身長）をヘルスケアに書き込む
- 設定画面で誕生日を入れると、レシートの年齢と照合する
