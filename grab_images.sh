#!/bin/bash

WATCH_DIR="/home/frousseu/Downloads/r5"
LOG="/home/frousseu/Downloads/r5/pipeline.log"

mkdir crops

inotifywait -m -e close_write -e moved_to --format '%f' "$WATCH_DIR" |
while read filename; do
    filepath="$WATCH_DIR/$filename"

    # skip if not a file we care about (adjust extension as needed)
    case "$filename" in
        *.JPG|*.jpg) ;;
        *) continue ;;
    esac

    echo "$(date '+%F %T') - New file: $filename" >> "$LOG"

    # run your pipeline scripts here
    echo $filepath
    fb_predict -i $filepath -o outputs -s 0.10
    ./crop_boxes.sh outputs _insect 0.1
    find outputs -type f -iname "*_insect*" -exec mv {} crops \;
    rm -r outputs
    echo "crops/{$filename}_insect000.JPG"
    #impressive -a 1 -s -d 00:00:05 --nologo crops/{$filename}_insect000.JPG
    #your_exif_script "$filepath"
done

#impressive -a 1 -s -d 00:00:05 --nologo $filepath

#for f in *.JPG; do darktable-cli "$f" "$f_processed.jpg" --style "shadows" --style-overwrite; done