# vopt

[English](README.md) · 日本語

vopt は Linux amd64・arm64 向けの独立した V コンパイラです。`v.token`、`v.scanner`、
`v.parser` で V ソースを解析して `v.flat` の AST を作成し、import の解決、型検査、
AST の変換を行います。そこから SSA を構築して最適化し、ELF に機械語を直接出力します。
生成したオブジェクトは Linux の C ツールチェーンでランタイムとリンクします。

## ビルドと実行

最近の V、Git、Clang、Linux の C ツールチェーンをインストールし、このリポジトリの
ルートで実行します。コンパイラと固定した V 標準ライブラリは `.build/` に配置します。

```sh
v -gc none run tools/build.v

# Linux arm64
.build/vopt --arch arm64 -o hello hello.v

# Linux amd64
.build/vopt --arch amd64 -o hello hello.v
```

入力には `.v` ファイル、または `main` プログラムを含むディレクトリを指定します。
最適化は既定で有効です。`--arch` を省略するとホストのアーキテクチャを選びます。
同じアーキテクチャの Linux 上では `cc` を使います。クロスリンク時はターゲットに応じて
`aarch64-linux-gnu-gcc` または `x86_64-linux-gnu-gcc` を探し、`--cc` で実行ファイルを
指定できます。

vopt は固定した上流 V のソースをそのまま使い、上流の SSA 最適化器とネイティブ
コード生成器を呼び出します。比較用の上流コンパイラだけをビルドするには
`v -gc none run tools/build.v baseline` を使います。
[固定した上流 V](https://github.com/vlang/v/commit/e85e785e034bf570113bb46ec6aaea85e628aa4e) · [上流の MIT ライセンス](https://github.com/vlang/v/blob/e85e785e034bf570113bb46ec6aaea85e628aa4e/LICENSE)

## 確認と性能計測

`llvm-objdump` と GNU `time` をインストールした Linux amd64・arm64 上で実行します。

```sh
v -gc none run tools/bench.v --verify   # 生成形式、終了コード、実行結果を比較
v -gc none run tools/bench.v            # 4 方式の性能と逆アセンブルを保存
v -gc none run tools/bench.v --check    # 合格基準に達しない場合は終了コード 1
```

計測は同じ V ソースと入力で行い、上流 native `-prod`、vopt、スカラー Clang `-O3`、
通常の Clang `-O3` を比較します。ウォームアップ後に順番をずらしながら各ケースを
12 回計測します。生データ、ビルドログ、コンパイル時間、ピーク RSS、テキストサイズ、
逆アセンブルは表示された `.build/bench-*` に保存されます。

各 ISA の目標は、スカラー Clang 比で中央値の幾何平均 1.15 以下、全ケース 1.35 以下です。
上流 native 比では実行時間のケース別悪化 5% 以内、コンパイル時間とピーク RSS の悪化
各 20% 以内とします。性能判定は同一の対象実機上で行ってください。
