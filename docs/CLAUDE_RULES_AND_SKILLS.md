# Claude で使用できる Rule / Skill 一覧

このリポジトリの Claude Code（クラウドセッション）環境で利用できる **Rule（ルール）** と **Skill（スキル）** の一覧です。
（2026-10-18 時点のセッション環境をもとに作成）

---

## 1. Rule（ルール）

Claude Code における「ルール」は、Claude の振る舞いを恒常的に制御する設定・指示ファイルの総称です。

### 1-1. ルールの種類

| 種類 | 配置場所 | 役割 | 適用範囲 | このリポジトリでの状態 |
|---|---|---|---|---|
| プロジェクトメモリ (`CLAUDE.md`) | リポジトリ直下 `./CLAUDE.md` | コーディング規約・ビルド/テスト手順など、毎セッション読み込まれる指示 | プロジェクト全員 | 未作成 |
| ローカルメモリ (`CLAUDE.local.md`) | リポジトリ直下（git管理外） | 個人用のプロジェクト固有メモ | 自分のみ | 未作成 |
| ユーザーメモリ | `~/.claude/CLAUDE.md` | 全プロジェクト共通の個人ルール | 自分の全プロジェクト | 未作成 |
| ルールファイル (`.claude/rules/*.md`) | `./.claude/rules/` | トピック別・パス別に分割したルール（frontmatter の `paths` で対象ファイルを限定可能） | プロジェクト全員 | 未作成 |
| プロジェクトスキル (`.claude/skills/*/SKILL.md`) | `./.claude/skills/` | プロジェクト固有のスキル | プロジェクト全員 | **7件作成済み**（下記 2-0） |
| 権限ルール (`permissions`) | `.claude/settings.json` の `allow` / `ask` / `deny` | ツールやコマンドの実行許可・確認・禁止 | プロジェクト / ユーザー | 未作成 |
| フック (`hooks`) | `.claude/settings.json` の `hooks` | 「〜の前後に必ず〜する」等の自動処理（SessionStart, PreToolUse, PostToolUse, Stop など） | プロジェクト / ユーザー | 未作成（環境側に Stop フックあり） |
| 環境変数 (`env`) | `.claude/settings.json` の `env` | セッションに渡す環境変数 | プロジェクト / ユーザー | 未作成 |

### 1-2. 関連するスキル・コマンド

| やりたいこと | 使うもの |
|---|---|
| `CLAUDE.md` を自動生成したい | `/init` |
| 権限・フック・環境変数を設定したい | `update-config` スキル |
| 権限確認のプロンプトを減らしたい | `fewer-permission-prompts` スキル |
| クラウドセッション開始時にテスト等を準備したい | `session-start-hook` スキル |

---

## 2. Skill（スキル）

スキルは、特定タスク向けの手順・知識をまとめたパッケージです。`/<スキル名>` で明示的に呼び出すか、依頼内容に応じて Claude が自動で使用します。

### 2-0. 自作スキル（Cursor / ChatGPT から移行）

このリポジトリの `.claude/skills/` に置いた独自スキルです。claude.ai 用の ZIP は `dist/claude-skills/` にあります。

| スキル名 | 概要 | 主な使用場面 |
|---|---|---|
| `ut-setup` | ユーザーテストの環境設定・計画（00_plan.md） | 「UTの準備」「テスト計画を立てて」 |
| `ut-scenario` | テストシナリオ・タスク・質問の作成・更新（01_scenario.md） | 「テストシナリオ作って」 |
| `ut-moderator` | テストの進行支援・観察結果の記録（02_sessions/P*.md） | 「観察メモを記録にまとめて」 |
| `ut-analysis` | テスト結果の分析・レポート作成（03_report.md） | 「UTレポート作って」 |
| `ut-learning` | ユーザーテスト・UX・UI の学習サポート | 「UXを勉強したい」 |
| `ut-shared` | ut-* スキル共通のルール（用語・ファイル配置・記録形式・倫理） | 他の ut-* スキルから参照 |
| `writing-presentations` | プレゼン・発表の読み上げ原稿の作成 | 「発表原稿を作って」 |

### 2-1. 開発・Claude Code 設定系

| スキル名 | 概要 | 主な使用場面 |
|---|---|---|
| `init` | コードベースを解析し `CLAUDE.md` を作成 | プロジェクト初期設定 |
| `code-review` | 差分・PR のバグ（正確性）レビュー。effort レベル指定、`--comment` / `--fix` 対応 | PR レビュー |
| `simplify` | 変更コードの再利用・簡素化・効率化を見直して修正 | リファクタリング |
| `security-review` | 現在のブランチの変更のセキュリティレビュー | セキュリティ確認 |
| `run` | アプリを起動・操作して変更の動作を確認 | 動作確認・スクリーンショット |
| `claude-api` | Claude API / Anthropic SDK のリファレンス（モデルID、料金、ツール使用、キャッシュ等） | Claude API を使う開発 |
| `update-config` | `settings.json`（権限・フック・環境変数）の設定 | 「〜したら毎回〜して」等の自動化 |
| `fewer-permission-prompts` | よく使う読み取り系コマンドを許可リストに追加 | 確認プロンプト削減 |
| `keybindings-help` | キーボードショートカットのカスタマイズ | キー割り当て変更 |
| `session-start-hook` | クラウドセッション用の SessionStart フック作成 | テスト/リンタ実行環境の準備 |
| `loop` | プロンプトやコマンドを一定間隔で繰り返し実行 | 定期チェック・ポーリング |
| `plugin-authoring` | Claude の UI・挙動を変える mod（パネル、ステータスライン、スラッシュコマンド、フック等）の作成 | Claude Code の拡張 |

### 2-2. Artifact・可視化系

| スキル名 | 概要 | 主な使用場面 |
|---|---|---|
| `artifact-design` | Artifact（Webページ）作成時のデザイン指針 | Artifact 作成前に必読 |
| `artifact-diagramming` | 図解の考え方とインライン SVG の作り方 | 図・ダイアグラム作成 |
| `artifact-capabilities` | Artifact に持たせられる実行時機能（共有状態、データ連携、ファイル保存等） | 動的な Artifact |
| `dataviz` | グラフ・チャート・ダッシュボードのデザイン手法と配色 | あらゆるデータ可視化 |

### 2-3. ドキュメント・ファイル形式系

| スキル名 | 概要 | 主な使用場面 |
|---|---|---|
| `anthropic-skills:docs` | 共有・コメント可能な Claude Docs の作成（Word/PDF/Markdown/Google Docs へエクスポート可） | 文書全般のデフォルト |
| `anthropic-skills:docx` | Word ファイル（.docx / .dotx）の作成・編集 | Word 形式指定時 |
| `anthropic-skills:pdf` | PDF の読取・結合・分割・作成・フォーム入力・OCR など | PDF 操作 |
| `anthropic-skills:pptx` | PowerPoint（.pptx / .potx）の作成・編集・読取 | PowerPoint 形式指定時 |
| `anthropic-skills:xlsx` | Excel / CSV / TSV の作成・編集・整形 | スプレッドシート |
| `anthropic-skills:google-workspace` | Google ドキュメント/スプレッドシート/スライドの作成・編集 | Google ファイル操作 |
| `anthropic-skills:qa-pptx-generator` | テンプレートから4択クイズと解説スライドを PPTX で生成 | クイズ作成 |

### 2-4. 文章作成・要約・整理系

| スキル名 | 概要 | 主な使用場面 |
|---|---|---|
| `anthropic-skills:summarizer` | 3行要約 → 原則 → 具体例 の3層で要約 | 「要約して」 |
| `anthropic-skills:notes-to-onepager` | 雑多なメモを A4 一枚（結論→やること→経緯→要確認）に清書 | 「1枚にまとめて」 |
| `anthropic-skills:research-organizer` | 複数の URL・資料・メモを 要点→比較→結論 に整理 | 「リサーチ整理して」 |
| `anthropic-skills:deep-research` | 複数ソースを調査し包括的なレポートを作成 | 本格的な調査 |
| `anthropic-skills:blog-post-writer` | 文字起こしやメモからブログ記事を作成 | 「ブログ記事書いて」 |
| `anthropic-skills:proposal-drafter` | 要件から提案書ドラフトを作成 | 「提案書作って」 |
| `anthropic-skills:customer-reply` | 顧客・取引先への返信文面を作成 | 「返信作って」 |
| `anthropic-skills:checklist-maker` | 作業説明を手順書＋品質チェックリストに変換 | 「チェックリスト化して」 |
| `anthropic-skills:weekly-report` | 1週間の活動メモから週次活動報告書を作成 | 「週報を作って」 |

### 2-5. 生活・スケジュール系

| スキル名 | 概要 | 主な使用場面 |
|---|---|---|
| `anthropic-skills:morning` | 朝のブリーフィングを HTML で表示／平日の定期タスクとして設定 | `/morning` |
| `anthropic-skills:schedule-screenshot-register` | 予定のスクショを読み取り、移動・準備時間込みで Google カレンダーに登録 | 予定スクショ送付時 |
| `anthropic-skills:weekend-dinner-planner` | 土日の夕食献立・買い物リスト・段取り・カレンダー登録 | 「今週末の献立」 |
| `anthropic-skills:weekly-side-prep` | 平日の副菜・弁当用の作り置き（5〜6品）計画 | 「今週の作り置き」 |

### 2-6. ブラウザ・PC 操作系

| スキル名 | 概要 | 主な使用場面 |
|---|---|---|
| `anthropic-skills:built-in-browser` | Claude デスクトップアプリ内蔵ブラウザの使い方 | 内蔵ブラウザ操作 |
| `anthropic-skills:chrome-browser` | Claude in Chrome 拡張機能の使い方 | 自分の Chrome での操作 |
| `anthropic-skills:computer-use` | デスクトップのスクリーンショット取得・クリック・入力操作 | PC 上のアプリ操作 |

### 2-7. スキル・プラグイン管理系

| スキル名 | 概要 | 主な使用場面 |
|---|---|---|
| `anthropic-skills:skill-creator` | スキルの新規作成・改良・評価 | 自作スキル |
| `anthropic-skills:import-memory` | 他の AI アシスタントのメモリを Claude のメモリへ取り込み | メモリ移行 |
| `cowork-plugin-management:create-cowork-plugin` | Cowork 用プラグインをゼロから作成 | プラグイン作成 |
| `cowork-plugin-management:cowork-plugin-customizer` | 既存プラグインを組織のツール・ワークフロー向けにカスタマイズ | プラグイン調整 |

---

## 補足

- スキル一覧はアカウントや有効化しているプラグイン、セッション種別（CLI / デスクトップ / Web）によって変わります。
- 自作スキルを他の場所でも使う方法：
  - **Claude Code（Mac の全プロジェクト）**：`.claude/skills/` の各フォルダを `~/.claude/skills/` にコピー
  - **claude.ai / Claude デスクトップアプリ**：設定 → 機能（Capabilities）→ スキル で `dist/claude-skills/*.zip` をアップロード
- このリポジトリにはまだ `CLAUDE.md` や `.claude/rules/` がありません。Swift のビルド・テスト手順（`BodyCompCore` の `swift test` など）を `/init` で `CLAUDE.md` にまとめておくと、今後のセッションで Claude がプロジェクトを理解しやすくなります。
