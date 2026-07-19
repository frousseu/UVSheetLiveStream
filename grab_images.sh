#!/bin/bash

WATCH_DIR="."
LOG="./pipeline.log"

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
    fb_predict -i $filepath -o outputs -s 0.15
    ./crop_boxes.sh outputs _insect 0.15
    fp=$(find outputs -type f -iname "*_insect*")
    full=$(basename "$fp")
    thumb="${full%.*}_thumbnail.${full##*.}"
    find outputs -type f -iname "*_insect*" -exec mv {} crops \;
    rm -r outputs
    echo "crops/{$filename}_insect000.JPG"
    #base="${filename%.JPG}"
    convert "crops/${full}" -resize 'x300>' "crops/${thumb}"
    convert "crops/${full}" -resize 'x2000>' "crops/${full}"
    s5cmd --profile do-tor1 --endpoint-url https://nyc3.digitaloceanspaces.com cp --acl public-read "crops/${full}" s3://uvsheetlivestream/
    s5cmd --profile do-tor1 --endpoint-url https://nyc3.digitaloceanspaces.com cp --acl public-read "crops/${thumb}" s3://uvsheetlivestream/
    ./image_list.sh "${full}"
    s5cmd --profile do-tor1 --endpoint-url https://nyc3.digitaloceanspaces.com cp --acl public-read images.json s3://uvsheetlivestream/
done

#impressive -a 1 -s -d 00:00:05 --nologo $filepath
#for f in *.JPG; do darktable-cli "$f" "$f_processed.jpg" --style "shadows" --style-overwrite; done

# s5cmd --profile do-tor1 --endpoint-url https://nyc3.digitaloceanspaces.com rm 's3://uvsheetlivestream/*.JPG'