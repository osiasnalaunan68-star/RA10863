#!/data/data/com.termux/files/usr/bin/bash

# Assuming new_logo.png is in the current directory
# Kung wala, kopyahin muna:
# cp "/storage/emulated/0/Pictures/Canva/ITC Avant Garde Gothic_20260712_140025_0000.png" ./new_logo.png

# 1. Resize para sa mipmap folders (traditional launcher icons)
for dir in android/app/src/main/res/mipmap-*; do
  if [[ -d "$dir" ]]; then
    case "$dir" in
      *-mdpi)   size=48 ;;
      *-hdpi)   size=72 ;;
      *-xhdpi)  size=96 ;;
      *-xxhdpi) size=144 ;;
      *-xxxhdpi) size=192 ;;
      *)        size=192 ;;
    esac
    convert new_logo.png -resize ${size}x${size} "$dir/ic_launcher.png"
    convert new_logo.png -resize ${size}x${size} "$dir/ic_launcher_round.png"
  fi
done

# 2. Maglagay ng 192x192 version para sa adaptive icon foreground
mkdir -p android/app/src/main/res/drawable-nodpi
convert new_logo.png -resize 192x192 android/app/src/main/res/drawable-nodpi/ic_launcher_foreground_image.png

# 3. Gumawa ng tamang bitmap drawable (sa drawable folder)
mkdir -p android/app/src/main/res/drawable
cat > android/app/src/main/res/drawable/ic_launcher_foreground.xml << 'EOF'
<bitmap xmlns:android="http://schemas.android.com/apk/res/android"
    android:src="@drawable/ic_launcher_foreground_image"
    android:gravity="center" />
EOF

# 4. I‑update ang adaptive icon XML (mipmap-anydpi-v26)
for file in android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml; do
  cat > "$file" << 'EOF'
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
EOF
done

# 5. Palitan din ang web icons (PWA)
cp new_logo.png frontend/public/favicon.ico
cp new_logo.png frontend/public/logo192.png
cp new_logo.png frontend/public/logo512.png

echo "✅ All icons replaced successfully!"
