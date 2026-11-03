#!/usr/bin/env bash
set -euo pipefail

# Regenerate the display, launcher, and splash assets from the original artwork.
# Requires ImageMagick's `convert` command.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_image="$root/assets/images/app_icon_1024.png"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# Use the original framed artwork without zooming or cropping. The squirrel
# remains centered with the original dark background visible as a margin.
cp "$source_image" "$root/assets/images/app_icon_display.png"

# Extract the existing orange line art as a transparent Android foreground.
# The soft threshold keeps antialiased edges while excluding the dark backdrop.
convert "$source_image" \
  \( +clone -alpha off -channel RGB \
     -fx '((r > 0.15) && (r > g*1.1) && (g > b*1.12)) ? min(1,max(0,(r-0.08)*2)) : 0' \
  \) -compose CopyOpacity -composite \
  -trim +repage "$tmp_dir/squirrel.png"

for density in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  case "$density" in
    mdpi) size=48 ;;
    hdpi) size=72 ;;
    xhdpi) size=96 ;;
    xxhdpi) size=144 ;;
    xxxhdpi) size=192 ;;
  esac
  folder="$root/android/app/src/main/res/mipmap-$density"
  mkdir -p "$folder"
  convert "$root/assets/images/app_icon_display.png" -resize "${size}x${size}!" "$folder/ic_launcher.png"
  cp "$folder/ic_launcher.png" "$folder/ic_launcher_round.png"

  foreground_size=$((size * 9 / 4))
  # Android's adaptive-icon safe zone is about 66% of the full foreground
  # canvas. Keep the squirrel at 70% of that zone to leave a clear margin.
  mark_size=$((foreground_size * 46 / 100))
  convert "$tmp_dir/squirrel.png" -resize "x${mark_size}" \
    -gravity center -background none -extent "${foreground_size}x${foreground_size}" \
    "$folder/ic_launcher_foreground.png"
done

# The native splash uses the same framed icon and the same dark background.
convert "$root/assets/images/app_icon_display.png" -resize 384x384! \
  "$root/android/app/src/main/res/drawable-xxhdpi/splash_logo.png"
