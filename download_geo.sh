#!/usr/bin/env bash
# download_geo.sh
# Usage: ./download_geo.sh [-f] <GSE_accession> <output_dir>
#
#   -f    Force overwrite all files
# Example:
#   ./download_geo.sh GSE165045 ./data/GSE165045
#   ./download_geo.sh -f GSE165045 ./data/GSE165045

set -euo pipefail
export PATH="$HOME/edirect:$PATH"

# parse options
FORCE=0
usage() {
  echo "Usage: $0 [-f] <GSE_accession> <output_dir>"
  echo "  -f    Force overwrite existing files"
  exit 1
}
while getopts "f" opt; do
  case $opt in
    f) FORCE=1 ;;
    *) usage ;;
  esac
done
shift $((OPTIND-1))

# check args
if [[ $# -ne 2 ]]; then
  usage
fi

GSE="$1"
OUTDIR="$2"

# prepare output dir
mkdir -p "$OUTDIR"

# 1. Fetch the GEO Series FTP base
echo "1. Fetching FTP base for $GSE …"
SERIES_PATH=$(esearch -db gds -query "${GSE}[ACCN]" \
  | efetch -format docsum \
  | xtract -pattern DocumentSummary -element FTPLink \
  | grep "/geo/series/" )

if [[ -z "$SERIES_PATH" ]]; then
  echo "Error: could not find series FTP for $GSE"
  exit 1
fi
echo "Found series FTP: $SERIES_PATH"

# 2. List supplementary files
SUPP_URL="${SERIES_PATH}/suppl"
echo
echo "2. Listing supplementary files …"
mapfile -t rawfiles < <(curl -s -l "${SUPP_URL}/")

file_list=()
for f in "${rawfiles[@]}"; do
  [[ -z "$f" || "${f: -1}" == "/" ]] && continue
  file_list+=("$f")
done

total=${#file_list[@]}
if (( total == 0 )); then
  echo "No supplementary files found in ${SUPP_URL}/"
else
  echo "Found $total supplementary files."
  echo
  echo "3. Downloading supplementary files to $OUTDIR …"
  i=0
  for fname in "${file_list[@]}"; do
    i=$((i+1))
    TARGET="$OUTDIR/$fname"
    echo "  → [$i/$total] $fname"

    # if force, remove any existing file (including zero-byte)
    if [[ $FORCE -eq 1 && -f "$TARGET" ]]; then
      rm -f "$TARGET"
    fi

    # skip if file exists and is non-zero size
    if [[ -s "$TARGET" ]]; then
      echo "     [Skip] already exists and non-zero size"
    else
      wget -c "${SUPP_URL}/${fname}" -P "$OUTDIR"
    fi
  done
fi

# 4. Download series matrix (_series_matrix.txt.gz)
echo
echo "4. Downloading series matrix …"
IDNUM=${GSE#GSE}
PREFIX=${IDNUM:0:3}
MATRIX_URL="ftp://ftp.ncbi.nlm.nih.gov/geo/series/GSE${PREFIX}nnn/${GSE}/matrix/${GSE}_series_matrix.txt.gz"
TARGET="$OUTDIR/$(basename "$MATRIX_URL")"

echo "  → $MATRIX_URL"
if [[ $FORCE -eq 1 && -f "$TARGET" ]]; then
  rm -f "$TARGET"
fi

if [[ -s "$TARGET" ]]; then
  echo "     [Skip] already exists and non-zero size"
else
  wget -c -O "$TARGET" "$MATRIX_URL"
fi

echo
echo "All done! Files are in $OUTDIR"
