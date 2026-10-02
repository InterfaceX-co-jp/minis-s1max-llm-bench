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

## Notes

- The GGUF repo splits the model into backbone shards + a **shared BF16 PLE (~95 GiB)** used as shard 00007 of every quant. Do **not** mlock the PLE on 128 GB unified-memory machines — keep it NVMe-backed via mmap. An NVMe drive is strongly recommended.
- `--spec-type draft-mtp` (MTP speculative decoding) needs a qwen4exp-capable llama.cpp build; pass `-NoMtp` on builds without it.
- TensorFold cannot run natively on this Minisforum (AMD Strix Halo has neither CUDA nor Metal); benchmark there on a Mac or NVIDIA machine and compare numbers.
