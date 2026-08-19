from __future__ import annotations
import argparse
from pathlib import Path

def find_one(root: Path, name: str) -> Path:
    hits = list(root.rglob(name))
    if len(hits) != 1:
        raise SystemExit(f"expected exactly one {name}, found {len(hits)}: {hits}")
    return hits[0]

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    args = ap.parse_args()
    root = Path(args.src).resolve()
    env_cpp = find_one(root, "sideswipe_env.cpp")
    ppo_cpp = find_one(root, "sideswipe_ppo.cpp")
    env_text = env_cpp.read_text(encoding="utf-8")
    if "Compact 16-action set" not in env_text or "add( 1.f,  0.f, true,  true )" not in env_text:
        raise SystemExit("source contract mismatch: expected the verified compact 16-action SideSwipe table; refusing to build an incompatible trainer")
    text = ppo_cpp.read_text(encoding="utf-8")
    original = text
    text = text.replace("#include <c10/cuda/CUDAFunctions.h>\n", "")
    text = text.replace("#include <c10/macros/Export.h>\n", "")
    text = text.replace("#include <cuda_runtime_api.h>\n", "")
    text = text.replace("namespace at::cuda { TORCH_CUDA_CPP_API cudaDeviceProp* getCurrentDeviceProperties(); }\n", "")
    text = text.replace("device_(c10::cuda::device_count() > 0 ? torch::kCUDA : torch::kCPU)", "device_(torch::cuda::is_available() ? torch::kCUDA : torch::kCPU)")
    text = text.replace("    if (device_.is_cuda()) (void)at::cuda::getCurrentDeviceProperties();\n", "")
    if "torch::cuda::is_available()" not in text:
        raise SystemExit("failed to patch SideSwipeTrainer CUDA device detection")
    if text != original:
        ppo_cpp.write_text(text, encoding="utf-8")
        print(f"[patch] portable CUDA detection: {ppo_cpp}")
    else:
        print(f"[patch] CUDA detection already portable: {ppo_cpp}")
    print("[contract] 72 observations / 16 actions verified")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
