#!/bin/bash

update_manifest() {
  local f="$1"
  local file="images.json"
  if [ -f "$file" ]; then
    jq --arg f "$f" 'if index($f) then . else . + [$f] end' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  else
    jq -n --arg f "$f" '[$f]' > "$file"
  fi
}

update_manifest "$1"