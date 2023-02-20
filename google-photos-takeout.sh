#!/usr/bin/env bash

# configure shellscript
set -e
shopt -s globstar

# ensure dependencies are installed
for cmd in exiftool jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo >&2 "$cmd is not installed. Aborting."; exit 1; }
done

# change directory to the script directory
cd "$(dirname "$0")"

# array to store $fullpath for batch processing
fullpaths=()

# find all JSON files and enumerate over them
files=(./**/*.json)

for i in "${!files[@]}"; do
  file="${files[$i]}"

  # read the filename from the JSON file
  filename=$(jq -r .title "$file")

  # skip if filename is empty
  if [ -z "$filename" ]; then
	  continue
  fi

  # read the timestamp from the JSON file
  timestamp=$(jq -r .photoTakenTime.timestamp "$file")

  # get the directory of the JSON file
  directory=$(dirname "$file")

  # iterate over the original and edited file
  for f in "$filename" "${filename%.*}-edited.${filename##*.}"; do

    # get the full path of the file
    fullpath="$directory/$f"

    # skip if file does not exist
    if [ ! -f "$fullpath" ]; then
      continue
    fi

    # print progress
    echo "[$((i+1))/${#files[@]}] $file : $fullpath"

    # hardlink (it's fast) JSON to $fullpath.json
    if [ ! -f "$fullpath.json" ]; then
      ln "$file" "$fullpath.json"
    fi

    # set modification time from unix timestamp
    touch -m -t "$(date -d @"$timestamp" +%Y%m%d%H%M.%S)" "$fullpath"

    # append to array
    fullpaths+=("$fullpath")

  done
done

# deduplicate fullpaths (sort does not matter but is nice)
readarray -t fullpaths < <(printf "%s\n" "${fullpaths[@]}" | sort -u)

# print fullpaths size
echo "Found ${#fullpaths[@]} unique files to process"

# ask for confirmation
read -p "Looks correct? [y/N] " -n 1 -r
printf "\n"

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  exit 1
fi

# run exiftool on all files
exiftool \
  -api LargeFileSupport=1 \
  -d %s \
  -tagsfromfile "%d%f.%e.json" \
  "-GPSAltitude<GeoDataAltitude" \
  "-GPSLatitude<GeoDataLatitude" \
  "-GPSLatitudeRef<GeoDataLatitude" \
  "-GPSLongitude<GeoDataLongitude" \
  "-GPSLongitudeRef<GeoDataLongitude" \
  "-DateTimeOriginal<PhotoTakenTimeTimestamp" \
  -overwrite_original \
  -preserve \
  -progress \
  "${fullpaths[@]}" || true

# optional cleanup JSON files
read -p "Delete all JSON files? [y/N] " -n 1 -r
printf "\n"

if [[ $REPLY =~ ^[Yy]$ ]]; then
  rm --verbose ./**/*.json
fi
