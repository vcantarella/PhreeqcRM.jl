using Documenter
using PhreeqcRM

makedocs(
    sitename = "PhreeqcRM.jl",
    modules  = [PhreeqcRM],
    authors  = "vcantarella <vcantarella@gmail.com>",
    remotes  = nothing,                 # don't probe git HEAD locally
    format   = Documenter.HTML(
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical  = "https://vcantarella.github.io/PhreeqcRM.jl/stable",
        edit_link  = "main",
    ),
    pages = [
        "Home" => "index.md",
        "Installation" => "installation.md",
        "Concepts" => [
            "PHREEQC vs PhreeqcRM" => "concepts/phreeqc_vs_phreeqcrm.md",
            "Memory & layout"      => "concepts/memory_model.md",
            "Threading"            => "concepts/threading.md",
            "Lifecycle"            => "concepts/lifecycle.md",
        ],
        "Reference" => "reference/api.md",
        "Developer notes" => [
            "Regenerating bindings" => "devnotes/regenerating_bindings.md",
        ],
    ],
    checkdocs = :none,                          # tighten to :exports once every export has a docstring
    warnonly  = [:missing_docs, :cross_references],   # keep the build warnings, don't fail on first miss
)

# Only deploy when running in CI (GitHub Actions sets CI=true).
if get(ENV, "CI", "false") == "true"
    deploydocs(
        repo      = "github.com/vcantarella/PhreeqcRM.jl.git",
        devbranch = "main",
        push_preview = true,
    )
end
