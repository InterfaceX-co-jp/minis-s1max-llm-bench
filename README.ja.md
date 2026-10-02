# minis-s1max-llm-bench

Minisforum S1 Max(AMD Ryzen AI Max+ 395、統合メモリ 128GB)で **Qwen3.8-Flash-Next** の推論速度を llama.cpp で計測するベンチ一式。加えて [TensorFold](https://github.com/ashhart/TensorFold) 版(Apple Silicon / NVIDIA 向け)も同梱。

| 言語 | README |
| --- | --- |
| 日本語 | このファイル |
| English | [README.md](README.md) |

## 2種類のベンチ

| | `run-bench.ps1` | `run-bench-tensorfold.ps1` |
| --- | --- | --- |
| エンジン | llama.cpp (GGUF) | [TensorFold](https://github.com/ashhart/TensorFold)(OpenAI互換サーバ) |
| チェックポイント | [vcruz305/Qwen3.8-Flash-Next-GGUF](https://huggingface.co/vcruz305/Qwen3.8-Flash-Next-GGUF)(K-quant + 共有BF16 PLE) | [TensorFold/Qwen3.8-Flash-Next-MLX-4bit-MTP](https://huggingface.co/TensorFold/Qwen3.8-Flash-Next-MLX-4bit-MTP)(4bit + MTP) |
| 動作環境 | Windows(この Minisforum) | macOS(Apple Silicon)または NVIDIA GPU(cc ≥ 8.9)— **この AMD iGPU ではネイティブ動作しない** |
| 指標 | llama.cpp ログから prefill / decode tok/s | ストリーミング API 経由で prefill / decode tok/s |

## セットアップ(llama.cpp、Minisforum 本体)

```powershell
# 1. llama.cpp ビルドを取得(qwen4exp 対応)
.\scripts\download-llamacpp.ps1            # 最新公式リリース
# Qwen3.8-Flash-Next 対応フォークがある場合:
# .\scripts\download-llamacpp.ps1 -ZipUrl <zip url>

# 2. モデル取得(初回: Q4_K_M 約80GB + 共有PLE 約95GB)
.\scripts\download-model.ps1 -Quant Q4_K_M -OutDir D:\models\qwen38-flash-next

# 3. ベンチ実行(コンテキスト長 × リピート、CSV出力)
.\scripts\run-bench.ps1 -Quant Q4_K_M -Contexts 1024,4096,8192 -GenTokens 256 -Repeats 3
```

## セットアップ(TensorFold、Mac / NVIDIA マシン)

```powershell
# Windows PowerShell(macOS/Linux の pwsh でも可)
.\scripts\run-bench-tensorfold.ps1
# 起動済みサーバに接続する場合(他マシンなど):
.\scripts\run-bench-tensorfold.ps1 -BaseUrl http://mac-mini.local:8080 -NoServe
# MTP 投機デコードあり/なしの比較:
.\scripts\run-bench-tensorfold.ps1 -ExtraServeArgs '--no-drafts' -CsvPath results\tf-nodraft.csv
```

スクリプトは `tensorfold serve` を起動し(初回は 4bit チェックポイントをダウンロード)、API 応答を待ってから prefill(長プロンプト + `max_tokens=1`)と decode(ストリーミング生成)を tok/s で計測して CSV に追記します。

## 出力

- `results\bench-<quant>-<時刻>.csv` — prefill/decode tok/s、ピークメモリ(llama.cpp)
- `results\tensorfold-<checkpoint>-<時刻>.csv` — prefill/decode tok/s(TensorFold)
- `results\log-*.txt` — llama.cpp 生ログ
- 集計テーブル: ctx 別 decode tok/s の中央値

## 指標

| 項目 | 意味 |
| --- | --- |
| `prefill_tps` | プロンプト処理速度(tokens/s) |
| `decode_tps` | 生成速度(tokens/s)— メモリ帯域が効く指標 |
| `peak_mem_mib` | ピーク使用メモリ |

## 注意

- GGUF 版はバックボーン shard + **共有 BF16 PLE(約95GiB)** を全量子化で shard 00007 として共有する構成。128GB 統合メモリ機では PLE を **mlock しない**こと(NVMe-backed mmap 推奨)。ディスクは NVMe 強く推奨。
- `--spec-type draft-mtp`(MTP 投機デコード)は qwen4exp 対応ビルドが必要。非対応なら `-NoMtp`。
- TensorFold はこの Minisforum(AMD Strix Halo)では動かない(CUDA でも Metal でもないため)。Mac / NVIDIA マシンで計測し、数値を比較する。
