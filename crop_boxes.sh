#!/usr/bin/env bash
# crop_boxes.sh
#
# Layout expected:
#   grandparent/
#     parent_dir/
#       <folder_name>/   <- contains a *.json with {"boxes": [[x1,y1,x2,y2], ...]}
#     <folder_name>.EXT   <- actual image, sibling of parent_dir, name matches folder
#
# For each subfolder of parent_dir:
#   - find its *.json
#   - find the matching image (by folder name) one level above parent_dir
#   - if there are multiple boxes, keep only the one whose center is closest
#     to the image's center (assumed to be the main subject / insect)
#   - pad the longest side of that box by 20% (10% each side), make it
#     square using that padded length, centered on the original box, then
#     clamp to the image bounds (shifting back in-bounds first, only
#     truncating if the image itself is smaller than the target square)
#   - crop out the resulting square
#   - stamp the original photo's date/time (from EXIF) in the top-right
#     corner, small and discrete, in pale text on dark backgrounds or
#     dark text on pale backgrounds (auto-detected from that corner)
#
# Requires: ImageMagick (convert, identify), jq, awk, exiftool
#
# Usage: ./crop_boxes.sh /path/to/parent_dir [output_suffix] [pad_fraction]
#   pad_fraction defaults to 0.2 (20%)

set -euo pipefail

PARENT_DIR="${1:?Usage: $0 <parent_dir> [suffix] [pad_fraction]}"
SUFFIX="${2:-_det}"
PAD="${3:-0.2}"
IMAGE_DIR="$(dirname "$PARENT_DIR")"

# --- date stamp appearance settings ---
DATE_FORMAT="%Y-%m-%d %H:%M:%S"   # exiftool -d format string
FONT_SIZE_RATIO=0.02              # pointsize as a fraction of the crop's shorter side
MIN_FONT_SIZE=8
MARGIN_RATIO=0.02                  # margin as a fraction of the crop's shorter side
MIN_MARGIN=6
PALE_COLOR="#EDEDED"
DARK_COLOR="#202020"
BRIGHTNESS_THRESHOLD=0.5           # below = dark bg -> pale text, above = pale bg -> dark text

for cmd in jq convert identify exiftool awk; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: '$cmd' is required but not found" >&2
        exit 1
    fi
done

for dir in "$PARENT_DIR"/*/; do
    dir="${dir%/}"
    folder_name="$(basename "$dir")"

    json_file=$(find "$dir" -maxdepth 1 -iname "*.json" | head -n1)
    if [[ -z "$json_file" ]]; then
        echo "[$folder_name] no JSON metadata file found, skipping" >&2
        continue
    fi

    n_boxes=$(jq '.boxes | length' "$json_file")
    if [[ "$n_boxes" -eq 0 ]]; then
        echo "[$folder_name] JSON has no boxes, skipping" >&2
        continue
    fi

    mapfile -t images < <(find "$IMAGE_DIR" -maxdepth 1 -type f \
        -iname "${folder_name}.*" \
        \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
           -o -iname "*.tif" -o -iname "*.tiff" \) | sort)

    if [[ "${#images[@]}" -eq 0 ]]; then
        echo "[$folder_name] no matching image found in $IMAGE_DIR, skipping" >&2
        continue
    fi
    if [[ "${#images[@]}" -gt 1 ]]; then
        echo "[$folder_name] WARNING: multiple matching images found, using the first: $(basename "${images[0]}")" >&2
    fi

    img="${images[0]}"
    ext="${img##*.}"
    base="${img%.*}"

    read -r img_w img_h <<< "$(identify -format "%w %h" "$img")"

    # pick the box whose center is closest to the image center
    if [[ "$n_boxes" -eq 1 ]]; then
        best_i=0
    else
        best_i=$(jq -r --argjson iw "$img_w" --argjson ih "$img_h" '
            (.boxes | to_entries | map(
                . as $e |
                (($e.value[0] + $e.value[2]) / 2) as $cx |
                (($e.value[1] + $e.value[3]) / 2) as $cy |
                {index: $e.key, dist: (( $cx - ($iw/2) )*( $cx - ($iw/2) ) + ( $cy - ($ih/2) )*( $cy - ($ih/2) ))}
            ) | sort_by(.dist) | .[0].index)
        ' "$json_file")
        echo "[$folder_name] $n_boxes boxes found, keeping box $best_i (closest to image center)"
    fi

    read -r x1 y1 x2 y2 <<< "$(jq -r ".boxes[$best_i] | @tsv" "$json_file")"

    w=$(( x2 - x1 ))
    h=$(( y2 - y1 ))

    if (( w <= 0 || h <= 0 )); then
        echo "[$folder_name] box $best_i is invalid (w=$w h=$h), skipping" >&2
        continue
    fi

    read -r nx ny nw nh <<< "$(awk -v x1="$x1" -v y1="$y1" -v x2="$x2" -v y2="$y2" \
        -v imgw="$img_w" -v imgh="$img_h" -v pad="$PAD" 'BEGIN{
        w=x2-x1; h=y2-y1;
        longest=(w>h)?w:h;
        side=longest*(1+pad);
        cx=(x1+x2)/2.0; cy=(y1+y2)/2.0;
        left=cx-side/2; right=cx+side/2;
        top=cy-side/2; bottom=cy+side/2;
        if(left<0){right+=-left; left=0}
        if(right>imgw){left-=(right-imgw); right=imgw}
        if(left<0){left=0}
        if(top<0){bottom+=-top; top=0}
        if(bottom>imgh){top-=(bottom-imgh); bottom=imgh}
        if(top<0){top=0}
        nw=right-left; nh=bottom-top;
        printf "%d %d %d %d\n", left, top, nw, nh;
    }')"

    idx=$(printf "%03d" "$best_i")
    out="${dir}/$(basename "$base")${SUFFIX}${idx}.${ext}"

    convert "$img" -crop "${nw}x${nh}+${nx}+${ny}" +repage "$out"
    echo "[$folder_name] kept box $idx -> $(basename "$out")  (box: ${nw}x${nh}+${nx}+${ny})"

    # --- date/time stamp ---
    date_text=$(exiftool -DateTimeOriginal -d "$DATE_FORMAT" -s3 "$img" 2>/dev/null)
    if [[ -z "$date_text" ]]; then
        date_text=$(exiftool -CreateDate -d "$DATE_FORMAT" -s3 "$img" 2>/dev/null)
    fi

    if [[ -z "$date_text" ]]; then
        echo "[$folder_name] no EXIF date found on $(basename "$img"), skipping stamp" >&2
    else
        shorter_side=$(( nw < nh ? nw : nh ))
        pointsize=$(awk -v s="$shorter_side" -v r="$FONT_SIZE_RATIO" -v m="$MIN_FONT_SIZE" \
            'BEGIN{v=s*r; print (v<m)?m:int(v)}')
        margin=$(awk -v s="$shorter_side" -v r="$MARGIN_RATIO" -v m="$MIN_MARGIN" \
            'BEGIN{v=s*r; print (v<m)?m:int(v)}')

        # sample the corner region roughly where the text will sit
        sample_w=$(( nw * 45 / 100 ))
        sample_h=$(( pointsize * 2 ))
        mean=$(convert "$out" -gravity NorthEast -crop "${sample_w}x${sample_h}+${margin}+${margin}" \
            +repage -colorspace Gray -format "%[fx:mean]" info: 2>/dev/null || echo 0.5)
        text_color=$(awk -v m="$mean" -v t="$BRIGHTNESS_THRESHOLD" -v pale="$PALE_COLOR" -v dark="$DARK_COLOR" \
            'BEGIN{print (m<t)?pale:dark}')

        convert "$out" -gravity NorthEast -pointsize "$pointsize" -fill "$text_color" \
            -annotate "+${margin}+${margin}" "$date_text" "$out"
        echo "[$folder_name] stamped date '$date_text' (color: $text_color, size: ${pointsize}px)"
    fi
done