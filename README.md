# minis-s1max-llm-bench

Benchmark **Qwen3.8-Flash-Next** inference speed on a Minisforum S1 Max (AMD Ryzen AI Max+ 395, 128 GB unified memory) with llama.cpp — plus a [TensorFold](https://github.com/ashhart/TensorFold) variant for Apple Silicon / NVIDIA machines.

| Language | README |
| --- | --- |
| English | this file |
| 日本語 | [README.ja.md](README.ja.md) |

## Two benchmarks

| | `run-bench.ps1` | `run-bench-tensorfold.ps1` |
| --- | --- | --- |
| Engine | llama.cpp (GGUF) | [TensorFold](https://github.com/ashhart/TensorFold) (OpenAI-compatible server) |
| Checkpoint | [vcruz305/Qwen3.8-Flash-Next-GGUF](https://huggingface.co/vcruz305/Qwen3.8-Flash-Next-GGUF) (K-quant + shared BF16 PLE) | [TensorFold/Qwen3.8-Flash-Next-MLX-4bit-MTP](https://huggingface.co/TensorFold/Qwen3.8-Flash-Next-MLX-4bit-MTP) (4-bit + MTP) |
| Runs on | Windows (this Minisforum) | macOS (Apple Silicon) or NVIDIA GPU (cc ≥ 8.9) — **not** natively on this AMD iGPU |
| Metrics | prefill / decode tok/s from llama.cpp logs | prefill / decode tok/s via streamed API |

## Quick start (Vulkan, MS-S1 MAX)

The simplest first measurement on Windows: the official llama.cpp **Windows x64 (Vulkan)** build — no ROCm needed, and `llama-bench` gives the two key numbers (pp512 prefill / tg256 decode) directly.

```powershell
# 1. Get the official Vulkan build (llama-cli / llama-bench / llama-server land in bin\)
.\scripts\download-llamacpp.ps1

# 2. Verify the iGPU is visible (expect: Vulkan0 - AMD Radeon 8060S)
.\bin\**\llama-cli.exe --list-devices

# 3. Benchmark any single gguf (auto-picks one from models\ if omitted)
.\scripts\run-bench-vulkan.ps1 -Model C:\models\model.gguf -ngl 999
# sweep prompt sizes / decode sizes, 3 repeats:
.\scripts\run-bench-vulkan.ps1 -Model C:\models\model.gguf -PromptSizes 512,4096 -GenSizes 256 -Repeats 3

# 4. Serve it (OpenAI-compatible, for Cursor/OpenCode etc.)
.\bin\**\llama-server.exe -m C:\models\model.gguf -ngl 999 -c 32768 --port 8080
```

`-ngl 999` is right on Strix Halo: the 128 GB UMA is shared, so the whole model can go to the 8060S without a BIOS VRAM carve-out. If your build supports MTP/speculative decoding, measure with and without (`-ExtraArgs '--spec-type','draft-mtp'` vs. default) — on this hardware MTP changes decode by ~30-60%.

## Setup (llama.cpp, on the Minisforum)

```powershell
# 1. Fetch a llama.cpp build (qwen4exp-capable)
.\scripts\download-llamacpp.ps1            # latest official release
# Or point at a fork build that supports Qwen3.8-Flash-Next:
# .\scripts\download-llamacpp.ps1 -ZipUrl <zip url>

# 2. Download the model (Q4_K_M ~80 GB backbone + ~95 GB shared PLE on first run)
.\scripts\download-model.ps1 -Quant Q4_K_M -OutDir D:\models\qwen38-flash-next

# 3. Run the benchmark (context-length matrix x repeats, CSV output)
.\scripts\run-bench.ps1 -Quant Q4_K_M -Contexts 1024,4096,8192 -GenTokens 256 -Repeats 3
```

## Setup (TensorFold, on a Mac / NVIDIA box)

```powershell
# Windows PowerShell (also works in pwsh on macOS/Linux)
.\scripts\run-bench-tensorfold.ps1
# Attach to an already-running server (e.g. on another machine):
.\scripts\run-bench-tensorfold.ps1 -BaseUrl http://mac-mini.local:8080 -NoServe
# Compare MTP drafting vs serial:
.\scripts\run-bench-tensorfold.ps1 -ExtraServeArgs '--no-drafts' -CsvPath results\tf-nodraft.csv
```

The script starts `tensorfold serve`, waits for the API (first run downloads the 4-bit checkpoint), then measures prefill (long prompt, `max_tokens=1`) and decode (streamed generation) in tok/s, appending to a CSV.

## Output

- `results\bench-<quant>-<timestamp>.csv` — prefill/decode tok/s, peak memory (llama.cpp)
- `results\tensorfold-<checkpoint>-<timestamp>.csv` — prefill/decode tok/s (TensorFold)
- `results\log-*.txt` — raw llama.cpp logs
- Summary table: median decode tok/s per context length

## Reference numbers (Strix Halo, 128 GB)

Community benchmark of engines for Qwen3.8-Flash-Next on AMD Strix Halo (70 W, [r/LocalLLM post](https://www.reddit.com/r/LocalLLM/comments/1wu0m53/benchmarks_best_engine_for_qwen_38flashnext_on/)):

| Engine | Weights | Prefill t/s | Decode t/s | MTP accept |
| --- | --- | ---: | ---: | ---: |
| [Halogen 0.15.1](https://github.com/) (.hgn, closed) | native v2 | 1,191 | 39.4 | 85% |
| [gufo 0.3.0](https://github.com/gufo-org/gufo) (ROCm) | UD-Q4_K_XL | 1,075 | 34.1 | 77% |
| CIRU (MTP 3) | CIRU IU4 | 808 | 30.2 | 64% |
| strixllama (llama.cpp fork) | UD-Q4_K_XL | 716 | 29.7 | 71% |
| llama.cpp (Vulkan, Unsloth build) | UD-Q4_K_XL | 314 | 28.4 | 56% |
| llama.cpp (ROCm, Unsloth build) | UD-Q4_K_XL | 285 | 20.5 | 50% |

Takeaways: on this hardware [gufo](https://github.com/gufo-org/gufo) — a Strix-Halo-specific engine with a [Windows port](https://github.com/pixmaate/gufo) — is the fastest open option and far ahead of stock llama.cpp. Its checkpoint is **Unsloth UD-Q4_K_XL + shared MTP head**, which this repo can also download:

```powershell
.\scripts\download-model.ps1 -Unsloth -OutDir D:\models\qwen38-flash-next
```

## Notes

- The GGUF repo splits the model into backbone shards + a **shared BF16 PLE (~95 GiB)** used as shard 00007 of every quant. Do **not** mlock the PLE on 128 GB unified-memory machines — keep it NVMe-backed via mmap. An NVMe drive is strongly recommended.
- `--spec-type draft-mtp` (MTP speculative decoding) needs a qwen4exp-capable llama.cpp build; pass `-NoMtp` on builds without it.
- TensorFold cannot run natively on this Minisforum (AMD Strix Halo has neither CUDA nor Metal); benchmark there on a Mac or NVIDIA machine and compare numbers.
