#!/usr/bin/env bash
#
# Fetch the COCO-2017 val detection fixtures used by the waste-scanner bench.
#
# What it does
# ------------
#   1. downloads the official COCO-2017 val annotations
#      (annotations_trainval2017.zip → annotations/instances_val2017.json),
#      cached next to the images so a re-run costs nothing;
#   2. reads the *ground truth* out of instances_val2017.json and picks
#      20..25 val2017 JPEGs whose DOMINANT annotated class is one of the
#      labels the scanner maps to each stream:
#         recycle  ← bottle, wine glass, cup, bowl
#         trash    ← banana, apple, pizza, cake, donut
#         reusable ← book, laptop, cell phone, chair, backpack, tv
#      at least 5 images per stream (--per-category, default 7 → 21 images);
#   3. downloads those val2017 JPEGs from images.cocodataset.org into
#      assets/test_images/ (created at run time);
#   4. writes assets/test_images/manifest.json — per image: file name, the
#      expected primary COCO label and the expected RecycleCategory, both taken
#      from the annotations as real ground truth, never from the model.
#
# The label → stream table below mirrors lib/services/recycle_classifier.dart
# (pinned by test/recycle_classifier_test.dart): if the Dart table moves, move
# these three sets with it.
#
# Requires: bash, curl, unzip, python3 (stdlib only).
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

OUT_DIR="${ROOT_DIR}/assets/test_images"
CACHE_DIR=""
ANNOTATIONS_FILE=""
ANNOTATIONS_URL="${COCO_ANNOTATIONS_URL:-http://images.cocodataset.org/annotations/annotations_trainval2017.zip}"
IMAGE_BASE_URL="${COCO_IMAGE_BASE_URL:-http://images.cocodataset.org/val2017}"
PER_CATEGORY=7
MIN_SHARE=0.5
SELECT_ONLY=0
FORCE=0

usage() {
  cat <<'USAGE'
Fetch the COCO-2017 val fixtures for the waste-scanner detection bench.

Usage: tool/fetch_test_images.sh [options]

  --out-dir DIR         output directory (default: <repo>/assets/test_images)
  --cache-dir DIR       download cache (default: <out-dir>/.cache)
  --annotations FILE    reuse an existing instances_val2017.json, skip download
  --annotations-url URL override the annotations zip URL
  --image-base-url URL  override the val2017 image base URL
  --per-category N      images per stream (default 7 → 21 images)
  --min-share F         dominant class must hold at least this share of the
                        image's non-crowd annotations (default 0.5)
  --select-only         pick and print the selection, download nothing
  --force               re-download images that already exist
  -h, --help            this text

Examples:
  tool/fetch_test_images.sh
  tool/fetch_test_images.sh --select-only
  tool/fetch_test_images.sh --annotations /path/instances_val2017.json
USAGE
}

log()  { printf '[fetch] %s\n' "$*"; }
warn() { printf '[fetch] WARNING: %s\n' "$*" >&2; }
die()  { printf '[fetch] ERROR: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --out-dir)         OUT_DIR="${2:?--out-dir needs a value}"; shift 2 ;;
    --cache-dir)       CACHE_DIR="${2:?--cache-dir needs a value}"; shift 2 ;;
    --annotations)     ANNOTATIONS_FILE="${2:?--annotations needs a value}"; shift 2 ;;
    --annotations-url) ANNOTATIONS_URL="${2:?--annotations-url needs a value}"; shift 2 ;;
    --image-base-url)  IMAGE_BASE_URL="${2:?--image-base-url needs a value}"; shift 2 ;;
    --per-category)    PER_CATEGORY="${2:?--per-category needs a value}"; shift 2 ;;
    --min-share)       MIN_SHARE="${2:?--min-share needs a value}"; shift 2 ;;
    --select-only)     SELECT_ONLY=1; shift ;;
    --force)           FORCE=1; shift ;;
    -h|--help)         usage; exit 0 ;;
    *)                 die "unknown option: $1 (try --help)" ;;
  esac
done

[ -n "${CACHE_DIR}" ] || CACHE_DIR="${OUT_DIR}/.cache"

for tool in curl unzip python3; do
  command -v "${tool}" >/dev/null 2>&1 || die "'${tool}' is required but not on PATH"
done
case "${PER_CATEGORY}" in
  ''|*[!0-9]*) die "--per-category must be a positive integer, got '${PER_CATEGORY}'" ;;
esac
[ "${PER_CATEGORY}" -ge 5 ] || die "--per-category must be >= 5 (the bench needs 5+ per stream)"
[ "$(( PER_CATEGORY * 3 ))" -gt 25 ] && \
  warn "--per-category ${PER_CATEGORY} yields $(( PER_CATEGORY * 3 )) images; the bench asks for 20..25."

mkdir -p "${OUT_DIR}"
[ "${SELECT_ONLY}" -eq 1 ] || mkdir -p "${CACHE_DIR}"

PLAN="${OUT_DIR}/.selection.json"
cleanup() { rm -f "${PLAN}"; }
trap cleanup EXIT

# ── 1. annotations ───────────────────────────────────────────────────────────
ANNOTATIONS="${ANNOTATIONS_FILE}"
if [ -z "${ANNOTATIONS}" ]; then
  ANNOTATIONS="${CACHE_DIR}/instances_val2017.json"
  if [ ! -s "${ANNOTATIONS}" ]; then
    ZIP="${CACHE_DIR}/annotations_trainval2017.zip"
    if [ ! -s "${ZIP}" ]; then
      log "downloading $(basename "${ANNOTATIONS_URL}") (~241 MB, cached in ${CACHE_DIR})"
      curl -L --fail --retry 3 --retry-delay 2 --progress-bar \
        -o "${ZIP}.part" "${ANNOTATIONS_URL}" || die "annotations download failed"
      mv "${ZIP}.part" "${ZIP}"
    else
      log "reusing cached $(basename "${ZIP}")"
    fi
    log "extracting annotations/instances_val2017.json"
    unzip -p "${ZIP}" annotations/instances_val2017.json > "${ANNOTATIONS}.part" \
      || die "could not extract instances_val2017.json from ${ZIP}"
    mv "${ANNOTATIONS}.part" "${ANNOTATIONS}"
  else
    log "reusing cached $(basename "${ANNOTATIONS}")"
  fi
fi
[ -s "${ANNOTATIONS}" ] || die "annotations file '${ANNOTATIONS}' is missing or empty"
log "annotations: ${ANNOTATIONS} ($(du -h "${ANNOTATIONS}" | cut -f1))"

# ── 2. selection from the annotations (ground truth) ─────────────────────────
python3 - "${ANNOTATIONS}" "${PER_CATEGORY}" "${MIN_SHARE}" "${PLAN}" <<'PY'
"""Pick val2017 images whose dominant annotated class maps to each stream.

Ground truth only: the expectation written to the manifest comes from the COCO
annotations (category names + non-crowd instance counts), never from a model.
"""
import json
import sys
from collections import Counter

annotations_path, per_category, min_share, plan_path = sys.argv[1:5]
per_category = int(per_category)
min_share = float(min_share)

# Mirrors lib/services/recycle_classifier.dart (normaliseCocoLabel + the sets).
RECYCLE = {"bottle", "wine glass", "cup", "bowl", "fork", "knife", "spoon"}
REUSABLE = {
    "book", "backpack", "handbag", "umbrella", "suitcase", "chair", "couch",
    "bed", "dining table", "tv", "laptop", "mouse", "keyboard", "remote",
    "cell phone", "microwave", "oven", "toaster", "refrigerator", "clock",
    "vase", "scissors", "hair drier", "toothbrush", "teddy bear",
    "sports ball", "surfboard", "skateboard", "frisbee", "kite",
}

# Labels this bench wants to see as the *dominant* class of an image.
PICKS = {
    "recycle": ["bottle", "wine glass", "cup", "bowl"],
    "trash": ["banana", "apple", "pizza", "cake", "donut"],
    "reusable": ["book", "laptop", "cell phone", "chair", "backpack", "tv"],
}


def category_of(label):
    label = " ".join(label.strip().lower().replace("_", " ").split())
    if label in RECYCLE:
        return "recycle"
    if label in REUSABLE:
        return "reusable"
    return "trash"


with open(annotations_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

names = {category["id"]: category["name"] for category in data["categories"]}
known = set(names.values())
for wanted in sorted({label for labels in PICKS.values() for label in labels}):
    if wanted not in known:
        sys.exit('[fetch] annotation file has no COCO class named "%s"' % wanted)

# Non-crowd instances only: a crowd of bottles is not "this image is a bottle".
counts = {}
for annotation in data["annotations"]:
    if annotation.get("iscrowd", 0):
        continue
    counter = counts.setdefault(annotation["image_id"], Counter())
    counter[names[annotation["category_id"]]] += 1

images = {image["id"]: image for image in data["images"]}
selected = []
used_files = set()

for category, labels in PICKS.items():
    wanted = set(labels)
    candidates = []
    for image_id, counter in counts.items():
        if image_id not in images:
            continue
        total = sum(counter.values())
        if total == 0:
            continue
        top_count = max(counter.values())
        # Deterministic dominant class: most instances, ties broken by COCO name.
        top_label = sorted(name for name, n in counter.items() if n == top_count)[0]
        if top_label not in wanted:
            continue
        expected = category_of(top_label)
        assert expected == category, (top_label, expected, category)
        candidates.append({
            "file": images[image_id]["file_name"],
            "image_id": image_id,
            "label": top_label,
            "category": category,
            "target_count": top_count,
            "instance_count": total,
            "share": round(top_count / total, 4),
            "width": images[image_id].get("width"),
            "height": images[image_id].get("height"),
        })

    # Cleanest first: few instances of the dominant class, then the largest
    # share, then image id — so the same annotations always pick the same set.
    def rank(candidate):
        return (candidate["target_count"], -candidate["share"], candidate["image_id"])

    strong = sorted((c for c in candidates if c["share"] >= min_share), key=rank)
    relaxed = sorted((c for c in candidates if c["share"] < min_share), key=rank)

    chosen = [c for c in strong if c["file"] not in used_files][:per_category]
    if len(chosen) < per_category:
        sys.stderr.write(
            "[fetch] %s: only %d image(s) with a dominant class >= %.2f of the "
            "annotations; relaxing the share for %d more\n"
            % (category, len(chosen), min_share, per_category - len(chosen))
        )
        for candidate in relaxed:
            if candidate["file"] in used_files or candidate in chosen:
                continue
            chosen.append(candidate)
            if len(chosen) >= per_category:
                break
    if len(chosen) < per_category:
        sys.exit(
            "[fetch] only %d '%s' image(s) found, %d needed — relax --min-share "
            "or lower --per-category" % (len(chosen), category, per_category)
        )

    used_files.update(c["file"] for c in chosen)
    selected.extend(chosen)
    print(
        "[fetch] %s: %d image(s) — %s"
        % (category, len(chosen), ", ".join(sorted({c["label"] for c in chosen}))),
        file=sys.stderr,
    )

order = {"recycle": 0, "trash": 1, "reusable": 2}
selected.sort(key=lambda c: (order[c["category"]], c["file"]))
with open(plan_path, "w", encoding="utf-8") as handle:
    json.dump({"images": selected, "per_category": per_category,
               "min_share": min_share}, handle, indent=1)

summary = Counter(c["category"] for c in selected)
print(
    "[fetch] selected %d image(s): %s"
    % (len(selected), ", ".join("%d %s" % (n, cat) for cat, n in sorted(summary.items()))),
    file=sys.stderr,
)
PY

if [ "${SELECT_ONLY}" -eq 1 ]; then
  log "--select-only: nothing downloaded; selection below is from the annotations."
  python3 -c '
import json, sys
plan = json.load(open(sys.argv[1], encoding="utf-8"))
print("%-20s %-14s %-9s %s" % ("file", "primary label", "category", "instances"))
for row in plan["images"]:
    print("%-20s %-14s %-9s %d/%d (%.2f)"
          % (row["file"], row["label"], row["category"],
             row["target_count"], row["instance_count"], row["share"]))
' "${PLAN}"
  exit 0
fi

# ── 3. images ────────────────────────────────────────────────────────────────
is_jpeg() {
  [ -s "$1" ] && [ "$(head -c 2 "$1" | od -An -tx1 | tr -d ' \n')" = "ffd8" ]
}

IMAGE_COUNT="$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1],encoding="utf-8"))["images"]))' "${PLAN}")"
log "downloading ${IMAGE_COUNT} val2017 JPEG(s) into ${OUT_DIR}"

while IFS='|' read -r file label category; do
  [ -n "${file}" ] || continue
  dest="${OUT_DIR}/${file}"
  if [ "${FORCE}" -eq 0 ] && is_jpeg "${dest}"; then
    printf '[fetch] %-20s %-14s %-9s kept (cached)\n' "${file}" "${label}" "${category}"
    continue
  fi
  curl -L --fail --retry 3 --retry-delay 2 --silent --show-error \
    -o "${dest}.part" "${IMAGE_BASE_URL}/${file}" \
    || die "download failed: ${IMAGE_BASE_URL}/${file}"
  mv "${dest}.part" "${dest}"
  is_jpeg "${dest}" || die "${dest} is not a JPEG (truncated or an error page?)"
  printf '[fetch] %-20s %-14s %-9s %s\n' "${file}" "${label}" "${category}" "$(du -h "${dest}" | cut -f1)"
done < <(python3 -c '
import json, sys
plan = json.load(open(sys.argv[1], encoding="utf-8"))
for row in plan["images"]:
    print("%s|%s|%s" % (row["file"], row["label"], row["category"]))
' "${PLAN}")

# ── 4. manifest.json ─────────────────────────────────────────────────────────
python3 - "${PLAN}" "${OUT_DIR}" "${ANNOTATIONS_URL}" "${IMAGE_BASE_URL}" "${MIN_SHARE}" <<'PY'
"""Write assets/test_images/manifest.json, straight off the annotations."""
import json
import os
import sys
from collections import Counter
from datetime import datetime, timezone

plan_path, out_dir, annotations_url, image_base_url, min_share = sys.argv[1:6]
with open(plan_path, "r", encoding="utf-8") as handle:
    plan = json.load(handle)

images = []
for row in plan["images"]:
    path = os.path.join(out_dir, row["file"])
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        sys.exit("[fetch] %s is missing — refusing to write a manifest" % row["file"])
    images.append({
        "file": row["file"],
        "path": "assets/test_images/%s" % row["file"],
        "image_id": row["image_id"],
        "label": row["label"],
        "category": row["category"],
        "target_count": row["target_count"],
        "instance_count": row["instance_count"],
        "dominant_share": row["share"],
        "coco_url": "%s/%s" % (image_base_url, row["file"]),
        "annotated_width": row["width"],
        "annotated_height": row["height"],
    })

by_category = Counter(image["category"] for image in images)
manifest = {
    "source": "COCO 2017 val (instances_val2017.json)",
    "annotations_url": annotations_url,
    "image_base_url": image_base_url,
    "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    "selection": {
        "rule": "dominant non-crowd COCO class of the image, per stream",
        "min_dominant_share": float(min_share),
        "per_category": plan["per_category"],
        "total": len(images),
    },
    "category_threshold": 0.8,
    "counts": {name: by_category.get(name, 0) for name in ("recycle", "trash", "reusable")},
    "images": images,
}
manifest_path = os.path.join(out_dir, "manifest.json")
with open(manifest_path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")
print("[fetch] wrote %s (%d images)" % (manifest_path, len(images)))
PY

log "done — now run: flutter test tool/detection_bench.dart"
