#!/usr/bin/env bash
# Build main.tex with the standard pdflatex + bibtex cycle (same toolchain as
# Overleaf), then report anything that would change how the paper looks:
# errors, unresolved references, boxes that overflow the text block, and the
# page count against the ICLR limit.
#
#   ./build.sh            # build and report
#   ./build.sh --clean    # remove build artefacts first
set -uo pipefail
cd "$(dirname "$0")"

DOC=${DOC:-main}
PAGE_LIMIT=${PAGE_LIMIT:-9}          # ICLR 2027: 9 pages of main text + references

if [[ "${1:-}" == "--clean" ]]; then
    rm -f "$DOC".{aux,bbl,blg,log,out,pdf,toc}
fi

run() {  # run a latex pass quietly; keep going so we can read the log
    "$@" -interaction=nonstopmode -halt-on-error "$DOC" > /dev/null 2>&1
}

echo "==> pdflatex (1/3)"
run pdflatex || { echo "FAILED — errors:"; grep -A3 '^!' "$DOC".log | head -40; exit 1; }
echo "==> bibtex"
bibtex "$DOC" > /dev/null 2>&1
echo "==> pdflatex (2/3)"; run pdflatex
echo "==> pdflatex (3/3)"
run pdflatex || { echo "FAILED — errors:"; grep -A3 '^!' "$DOC".log | head -40; exit 1; }

echo
echo "── diagnostics ─────────────────────────────────────────────"

undef=$(grep -c "LaTeX Warning: \(Citation\|Reference\).*undefined" "$DOC".log)
echo "unresolved citations/references : $undef"
[[ $undef -gt 0 ]] && grep "LaTeX Warning: \(Citation\|Reference\).*undefined" "$DOC".log | head -10

# Only hbox overflow actually reaches the margin; report the width so small
# overshoots (< 5pt, invisible in print) can be told from real ones.
over=$(grep -c "^Overfull \\\\hbox" "$DOC".log)
echo "overfull hboxes (text in margin): $over"
[[ $over -gt 0 ]] && grep "^Overfull \\\\hbox" "$DOC".log | head -10

fonts=$(grep -c "LaTeX Font Warning" "$DOC".log)
echo "font substitutions             : $fonts"
[[ $fonts -gt 0 ]] && grep "LaTeX Font Warning" "$DOC".log | sort -u | head -5

python3 - "$DOC.pdf" "$PAGE_LIMIT" <<'PY'
import sys
try:
    import fitz
except ImportError:
    sys.exit(0)
pdf, limit = sys.argv[1], int(sys.argv[2])
d = fitz.open(pdf)
refs = next((i + 1 for i, p in enumerate(d)
             if "REFERENCES" in p.get_text().upper()), None)
body = (refs or d.page_count)
print(f"pages                          : {d.page_count} "
      f"(main text ends p{body}, limit {limit})")
if body > limit:
    print(f"  !! main text exceeds the {limit}-page limit by {body - limit}")
PY

echo "────────────────────────────────────────────────────────────"
ls -l "$DOC".pdf
