# Regenerating the low-level bindings

`src/LibPhreeqcRM.jl` is **generated** by Clang.jl from the
vendored C header `gen/include/RM_interface_C.h`. The generated
file is committed, so users do **not** regenerate at install time — only
maintainers do, when upstream changes.

## When to regenerate

- Upstream `usgs-coupled/phreeqcrm` ships a new release.
- A new C function is needed by the high-level wrapper.

## How

```bash
# 1. Bump the PHREEQCRM_TAG in deps/build_phreeqcrm.sh and rebuild.
PHREEQCRM_TAG=v3.10.0 bash deps/build_phreeqcrm.sh

# 2. Re-vendor the header.
cp deps/usr/include/RM_interface_C.h    gen/include/
cp deps/usr/include/IrmResult.h         gen/include/
cp deps/usr/include/irm_dll_export.h    gen/include/

# 3. Regenerate the bindings.
julia --project=gen gen/generator.jl

# 4. Verify the diff in src/LibPhreeqcRM.jl makes sense.
git diff src/LibPhreeqcRM.jl
```

## What can go wrong

- **Caller-allocated `char*` typed as `Cstring`**: Clang.jl turns every
  `char *` in the header into `Cstring`, which only accepts NUL-terminated
  strings on the way *in*. Output buffers we caller-allocate (component
  names, selected-output headings, error strings) need to bypass this and
  pass `pointer(buf)::Ptr{UInt8}` instead. The wrapper does this in a few
  spots — search for `@ccall Lib.libphreeqcrm.RM_GetComponent` etc.
- **Macro definitions**: `IRM_DLL_EXPORT` and friends are visibility
  attributes that don't translate. `generator.toml` sets
  `macro_mode = "disable"` to skip all `#define` translation.
