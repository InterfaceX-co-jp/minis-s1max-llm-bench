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

## クイックスタート(Vulkan、MS-S1 MAX)

Windows での最初の1測定は公式 llama.cpp **Windows x64 (Vulkan)** ビルドが最短。ROCm 不要で、`llama-bench` が重要な2数値(pp512=prefill / tg256=decode)を直接出します。

```powershell
# 1. 公式 Vulkan ビルドを取得(llama-cli / llama-bench / llama-server が bin\ に入る)
.\scripts\download-llamacpp.ps1

# 2. iGPU が見えているか確認(期待: Vulkan0 - AMD Radeon 8060S)
.\bin\**\llama-cli.exe --list-devices

# 3. 単一 gguf をベンチ(models\ から自動選択も可)
.\scripts\run-bench-vulkan.ps1 -Model C:\models\model.gguf -ngl 999
# プロンプト長/生成長スイープ、3リピート:
.\scripts\run-bench-vulkan.ps1 -Model C:\models\model.gguf -PromptSizes 512,4096 -GenSizes 256 -Repeats 3

# 4. サーバとして起動(OpenAI互換、Cursor/OpenCode から利用可)
.\bin\**\llama-server.exe -m C:\models\model.gguf -ngl 999 -c 32768 --port 8080
```

Strix Halo では `-ngl 999` が基本。128GB UMA を共有するため、BIOS の VRAM carve-out なしでモデル全体を 8060S 側に置けます。ビルドが MTP/投機デコード対応なら **あり/なし両方**測ってください(このハードでは decode が 3〜6割変わります)。

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

## 参考数値(Strix Halo、128GB)

AMD Strix Halo での Qwen3.8-Flash-Next エンジン比較(70W、[r/LocalLLM 投稿](https://www.reddit.com/r/LocalLLM/comments/1wu0m53/benchmarks_best_engine_for_qwen_38flashnext_on/)):

| エンジン | 重み | Prefill t/s | Decode t/s | MTP accept |
| --- | --- | ---: | ---: | ---: |
| Halogen 0.15.1(.hgn、クローズド) | native v2 | 1,191 | 39.4 | 85% |
| [gufo 0.3.0](https://github.com/gufo-org/gufo)(ROCm) | UD-Q4_K_XL | 1,075 | 34.1 | 77% |
| CIRU(MTP 3) | CIRU IU4 | 808 | 30.2 | 64% |
| strixllama(llama.cpp フォーク) | UD-Q4_K_XL | 716 | 29.7 | 71% |
| llama.cpp(Vulkan、Unsloth ビルド) | UD-Q4_K_XL | 314 | 28.4 | 56% |
| llama.cpp(ROCm、Unsloth ビルド) | UD-Q4_K_XL | 285 | 20.5 | 50% |

要点: このハードでは [gufo](https://github.com/gufo-org/gufo)(Strix Halo 専用エンジン、[Windows ポート](https://github.com/pixmaate/gufo)あり)がオープンソース最速で、素の llama.cpp を大きく上回る。gufo 用重みは **Unsloth UD-Q4_K_XL + 共有 MTP ヘッド**で、本リポジトリからもダウンロード可能:

```powershell
.\scripts\download-model.ps1 -Unsloth -OutDir D:\models\qwen38-flash-next
```

## 注意

- GGUF 版はバックボーン shard + **共有 BF16 PLE(約95GiB)** を全量子化で shard 00007 として共有する構成。128GB 統合メモリ機では PLE を **mlock しない**こと(NVMe-backed mmap 推奨)。ディスクは NVMe 強く推奨。
- `--spec-type draft-mtp`(MTP 投機デコード)は qwen4exp 対応ビルドが必要。非対応なら `-NoMtp`。
- TensorFold はこの Minisforum(AMD Strix Halo)では動かない(CUDA でも Metal でもないため)。Mac / NVIDIA マシンで計測し、数値を比較する。
