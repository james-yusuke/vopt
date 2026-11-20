# vopt

[English](README.md) · 日本語

V のネイティブバックエンド向けに、整数 SSA と機械語生成を最適化する実験です。
対象は macOS arm64（Mach-O）と Linux amd64（ELF）です。コンパイラは上流の
エミッタとリンク経路を使います。Clang/LLVM はビルドと性能比較に使います。

## ビルドと実行

最近の V、Git、Clang をインストールし、このリポジトリのルートで実行します。
コンパイラのソースとバイナリは `.build/` 内に作成します。

```sh
v -gc none run tools/build.v
compiler=$(cat .build/vopt.path)

# macOS arm64
"$compiler" -b arm64 -prod -d vopt -o hello hello.v

# Linux amd64
"$compiler" -b amd64 -prod -d vopt -o hello hello.v
```

`-d vopt` の有無で追加の最適化を切り替えられます。`v -gc none run tools/build.v baseline`
は未改変の比較用コンパイラだけをビルドします。`patches/` の差分はファイル名順に
[固定した上流 V](https://github.com/vlang/v/commit/e85e785e034bf570113bb46ec6aaea85e628aa4e)
に適用します。上流の著作権表記は [UPSTREAM-LICENSE](UPSTREAM-LICENSE) にあります。

## 確認と性能計測

macOS では Xcode Command Line Tools、Linux では `llvm-objdump` と GNU `time` が必要です。

```sh
v -gc none run tools/bench.v --verify   # 生成形式、終了コード、実行結果を比較
v -gc none run tools/bench.v            # 4 方式の性能と逆アセンブルを保存
v -gc none run tools/bench.v --check    # 合格基準に達しない場合は終了コード 1
```

計測は同じ V ソースと入力で行い、上流 native `-prod`、vopt、スカラー Clang `-O3`、
通常の Clang `-O3` を比較します。ウォームアップ後に順番をずらしながら各ケースを
12 回計測します。生データ、コンパイラのステージ別時間、ピーク RSS、テキストサイズ、
逆アセンブルは表示された `.build/bench-*` に保存されます。

各 ISA の目標は、スカラー Clang 比で中央値の幾何平均 1.15 以下、全ケース 1.35 以下です。
上流 native 比では実行時間のケース別悪化 5% 以内、コンパイル時間とピーク RSS の悪化
各 20% 以内とします。性能判定は同一の対象実機上で行ってください。
