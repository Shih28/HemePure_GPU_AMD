# What We Changed

## Background

Crashed during execution with `exit code 139` (segmentation fault).

After debugging, we found that the issue was related to two ROCm 7.x bugs on `gfx1201` (RDNA4). These bugs caused GPU constant symbols and communication-related data access to fail under specific conditions.

---

## Change 1: Move `__constant__` Symbols to Global Scope

**Files modified:**

* `cuda_params.h`
* `cuda_params.cu`

### Problem

In ROCm 7.x on `gfx1201`, `__constant__` symbols declared inside:

```cpp
namespace hemelb {}
```

failed when accessed across different translation units (cross-TU) using:

```cpp
hipMemcpyToSymbol(...)
hipGetSymbolAddress(...)
```

The failure returned:

```cpp
hipErrorInvalidKernelFile
```

As a result, the GPU constant variables were not initialized correctly, which caused the program to crash around `NLookup`.

### Fix

We moved all `__constant__` symbol declarations and definitions outside the `hemelb` namespace, placing them in the global scope.

We also added a new function:

```cpp
hemelb::initGPUSymbolConstants(...)
```

This function is implemented in `cuda_params.cu` and handles all GPU constant initialization inside the same translation unit.

The function performs:

```cpp
hipGetSymbolAddress(...)
hipMemcpy(...)
```

inside `cuda_params.cu`, avoiding the ROCm cross-TU symbol lookup issue.

---

## Change 2: Use a Unified Function to Copy GPU Constants

**File modified:**

* `lb.hpp` around line `5867`

### Problem

Originally, `lb.hpp` directly called:

```cpp
deviceMemcpyToSymbol(hemelb::_xxx, ...)
```

for 11 different `__constant__` symbols.

However, these operations accessed symbols across translation units. On ROCm 7.x with `gfx1201`, this caused symbol lookup failures and prevented the constants from being initialized correctly.

### Fix

We replaced the 11 separate `deviceMemcpyToSymbol(...)` calls with a single call to:

```cpp
hemelb::initGPUSymbolConstants(...)
```

Since this function is defined in `cuda_params.cu`, the symbol address lookup and memory copy are performed in the same translation unit where the constants are defined.

This avoids the ROCm/gfx1201 cross-TU constant symbol issue.

---

## Change 3: Add Global Scope Prefix for `dev_smag_cnst`

**File modified:**

* `lb.hpp` around line `6034`

### Problem

The Smagorinsky constant symbol:

```cpp
dev_smag_cnst
```

was moved from the `hemelb` namespace to the global scope.

However, the original code still referenced it as:

```cpp
&hemelb::dev_smag_cnst
```

After moving the symbol, this reference was no longer valid.

### Fix

We changed the reference to explicitly use the global scope:

```cpp
&::dev_smag_cnst
```

This correctly points to the global `dev_smag_cnst` symbol.

---

## Result After Changes 1–3

After applying Changes 1–3, the program successfully passed the previous crash point near `NLookup`.

The program completed initialization and printed:

```text
Relaxation Time = 0.70000
```

It also successfully reached:

```text
SIMULATION STARTING
```

This confirmed that the GPU constant initialization issue was resolved.

---

## Change 4: Guard Against Empty `neighbouringProcs` in 1-GPU Case

**File modified:**

* `lb.hpp` around line `255`

### Problem

When running with 1 GPU and 2 MPI ranks, Rank 1 does not have any GPU neighboring process.

In this case:

```cpp
neighbouringProcs
```

is an empty vector.

However, inside `PostReceive()`, the function:

```cpp
Read_DistrFunctions_CPU_to_GPU_totalSharedFs()
```

was still called.

That function accessed:

```cpp
neighbouringProcs[0].FirstSharedDistribution
```

Since `neighbouringProcs` was empty, its internal data pointer was null.

Accessing the first element caused the program to read from an invalid address:

```text
0x10
```

This happened because `FirstSharedDistribution` is located at offset 16 bytes inside the struct. Therefore, accessing it from a null pointer resulted in:

```text
NULL + 0x10 = 0x10
```

and caused a segmentation fault.

### Fix

We added a guard at the beginning of the function:

```cpp
if (totSharedFs == 0 || mLatDat->neighbouringProcs.empty()) return;
```

This prevents the function from accessing `neighbouringProcs[0]` when there are no shared distributions or no neighboring GPU processes.

---

## Summary

The main fixes include:

1. Moved all GPU `__constant__` symbols from `namespace hemelb` to global scope.
2. Added `hemelb::initGPUSymbolConstants(...)` to initialize GPU constants inside `cuda_params.cu`.
3. Replaced cross-TU `deviceMemcpyToSymbol(...)` calls in `lb.hpp` with one unified initialization function.
4. Updated `dev_smag_cnst` access to use the global scope prefix `::`.
5. Added a safety guard for empty `neighbouringProcs` in the 1-GPU case.

These changes fixed the ROCm/gfx1201 constant symbol initialization issue and prevented a segmentation fault caused by accessing an empty `neighbouringProcs` vector.
