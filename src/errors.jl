# Error translation for IRM_RESULT return codes.
#
# Every wrapped C call goes through `check_result`, which queries
# `RM_GetErrorString` for the human-readable message and throws a
# `PhreeqcRMError` if the return code is anything other than `IRM_OK`.

"""
    IRMResult

Alias for the generated `LibPhreeqcRM.IRM_RESULT` enum. Values:

    IRM_OK            =  0
    IRM_OUTOFMEMORY   = -1
    IRM_BADVARTYPE    = -2
    IRM_INVALIDARG    = -3
    IRM_INVALIDROW    = -4
    IRM_INVALIDCOL    = -5
    IRM_BADINSTANCE   = -6
    IRM_FAIL          = -7
"""
const IRMResult = Lib.IRM_RESULT

"""
    PhreeqcRMError <: Exception

Thrown by any wrapped `RM_*` call that returns a non-`IRM_OK` `IRM_RESULT`.
Fields:

  - `code::IRMResult` — the underlying error code.
  - `message::String` — the message accumulated by `RM_GetErrorString`.
"""
struct PhreeqcRMError <: Exception
    code::IRMResult
    message::String
end

function Base.showerror(io::IO, e::PhreeqcRMError)
    print(io, "PhreeqcRMError($(e.code)): ")
    print(io, e.message)
end

# Internal: pull the accumulated error log out of the library and throw.
function _error_message(id::Cint)
    len = Lib.RM_GetErrorStringLength(id)
    len <= 0 && return ""
    # +1 for safety; library writes null-terminated string up to len chars.
    buf = Vector{UInt8}(undef, len + 1)
    # Caller-allocated output buffer; Clang.jl typed it as Cstring so we
    # bypass with a direct @ccall.
    GC.@preserve buf @ccall Lib.libphreeqcrm.RM_GetErrorString(
        id::Cint, pointer(buf)::Ptr{UInt8}, Cint(length(buf))::Cint)::Cint
    return GC.@preserve buf unsafe_string(pointer(buf))
end

# Internal: assert an IRM_RESULT is OK, otherwise throw with the library's
# error message. Takes a raw id so it can be used before / after instance
# construction — the wrapper passes `rm.id`.
function _check(rc, id::Cint)
    code = rc isa IRMResult ? rc : IRMResult(rc)
    code == Lib.IRM_OK && return code
    throw(PhreeqcRMError(code, _error_message(id)))
end

# Convenience overload for when we have an instance already.
_check(rc, rm) = _check(rc, rm.id)
