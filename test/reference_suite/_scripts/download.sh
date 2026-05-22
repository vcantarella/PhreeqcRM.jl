#!/usr/bin/env bash
# Download upstream PHREEQC example scripts.
# Maintainer-only; the downloaded scripts ARE committed.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="$(dirname "$HERE")"
BASE="https://raw.githubusercontent.com/phreeqc-dev/phreeqc3/master/examples"

# Skip ex16, ex18 (inverse modeling — batch-only, not PhreeqcRM-suitable)
CASES=(
    ex1 ex2 ex2b ex3 ex4 ex5 ex6 ex7 ex8 ex9 ex10
    ex11 ex12 ex12a ex12b ex13a ex13b ex13c ex13ac
    ex14 ex15 ex15a ex15b
    ex17 ex17b ex19 ex19b ex20a ex20b ex21 ex22
)

for c in "${CASES[@]}"; do
    dir="$SUITE/$c"
    mkdir -p "$dir/reference"
    if [[ ! -f "$dir/input.pqi" ]]; then
        echo "  fetching $c"
        curl -sf "$BASE/$c" -o "$dir/input.pqi"
    fi
done

# Auxiliary INCLUDE files referenced by some scripts. Land them next to the
# .pqi so the relative `INCLUDE$ name` directive resolves.
declare -A AUX
AUX[ex8]="Zn1e_4 Zn1e_7"
AUX[ex20b]="current1"
AUX[ex21]="radial"

for c in "${!AUX[@]}"; do
    for f in ${AUX[$c]}; do
        dst="$SUITE/$c/$f"
        if [[ ! -f "$dst" ]]; then
            echo "  fetching $c/$f"
            curl -sf "$BASE/$f" -o "$dst" || echo "    (not found, skipping)"
        fi
    done
done
echo "Done. $(find $SUITE -mindepth 2 -maxdepth 2 -name input.pqi | wc -l) cases."
