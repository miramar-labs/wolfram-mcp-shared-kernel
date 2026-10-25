# Optional NVIDIA CUDA smoke test

This test is **optional**. The shared Wolfram MCP server works for CPU-only users too. The test verifies CUDA GPU discovery and a small actual matrix multiplication through Wolfram's `CUDALink`, not GPU performance, custom kernel compilation, DGX execution, or CUDA compatibility for every feature.

## Run through any MCP client

First invoke `WolframLanguageContext` for `CUDALink` documentation, then invoke `WolframLanguageEvaluator`. Keep using the same evaluator session ID between steps, or run this code in a single call:

```wolfram
Needs["CUDALink`"];
{
  $ProcessID,
  CUDALink`CUDAQ[],
  CUDALink`$CUDADeviceCount,
  CUDALink`CUDADriverVersion[],
  CUDALink`CUDAInformation[]
}
```

**Important:** In AgentTools evaluator sessions, use fully qualified `CUDALink`FunctionName` names. Otherwise a session-local context can shadow imported package names; an unevaluated `Sessions`...`CUDAQ[]` is not a CUDA failure.

If `CUDAQ[]` is `True` and a CUDA GPU is reported, run a simple operation (again after the context tool if starting a new interaction):

```wolfram
Module[
  {a = {{1., 2.}, {3., 4.}},
   b = {{5., 6.}, {7., 8.}}, gpu, cpu},
  gpu = CUDALink`CUDADot[a, b];
  cpu = Dot[a, b];
  {$ProcessID, gpu, cpu, Max[Abs[Flatten[gpu - cpu]]]}
]
```

Expected mathematical result for both matrices: `{{19.,22.},{43.,50.}}`, with maximum absolute error `0.`. The process ID is installation-specific.

A successful `CUDADot` with `CUDAQ[] == True` is a functional CUDA-path smoke test. For a more stringent physical-GPU execution audit, inspect activity with an external NVIDIA profiler or telemetry; this minimal test does not independently capture a CUDA kernel trace.

## Verified reference system (2026-10-24)

The original Windows machine returned:

| Probe | Observed |
| --- | --- |
| Wolfram | 15.0 |
| Shared MCP Wolfram PID | `10028` |
| `CUDALink`CUDAQ[]` | `True` |
| `CUDALink`$CUDADeviceCount` | `1` |
| `CUDALink`CUDADriverVersion[]` | `"591.44"` |
| GPU | NVIDIA GeForce RTX 4060 Laptop GPU |
| Compute capability | 8.9 |
| Reported total GPU memory | 8585216000 bytes (~8.0 GiB) |
| CUDA matrix product | `{{19.,22.},{43.,50.}}` |
| CPU matrix product | `{{19.,22.},{43.,50.}}` |
| Maximum absolute difference | `0.` |

The GPU is physically attached to the **Windows host**. Running the MCP client on another machine, such as an NVIDIA DGX Spark, does **not** move CUDA computations to the client's GPU; they run where the Wolfram server executes.

## If CUDA is unavailable

- Confirm an NVIDIA CUDA-compatible GPU and driver on the **Wolfram server host**.
- Consult Wolfram's [CUDALink setup guide](https://reference.wolfram.com/language/CUDALink/tutorial/Setup).
- Check whether `CUDALink` can find a compatible CUDA toolkit/runtime, and inspect evaluation messages.
- CPU-only evaluations remain supported; CUDA is **not** a prerequisite for the MCP architecture.
