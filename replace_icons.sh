#!/data/data/com.termux/files/usr/bin/bash

# Replace Android launcher icons (all densities)
for dir in android/app/src/main/res/mipmap-*; do
  if [[ -d "$dir" ]]; then
    # Determine density
    case "$dir" in
      *-mdpi)   size=48 ;;
      *-hdpi)   size=72 ;;
      *-xhdpi)  size=96 ;;
      *-xxhdpi) size=144 ;;
      *-xxxhdpi) size=192 ;;
      *)        size=192 ;;  # fallback
    esac
    echo "Resizing to ${size}x${size} for $dir"
    convert new_logo.png -resize ${size}x${size} "$dir/ic_launcher.png"
    convert new_logo.png -resize ${size}x${size} "$dir/ic_launcher_round.png"
  fi
done

# Replace adaptive icon foreground
# Copy the PNG to drawable-nodpi (so we can reference it in XML)
mkdir -p android/app/src/main/res/drawable-nodpi
cp new_logo.png android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png

# Update ic_launcher_foreground.xml to use a <bitmap> instead of the vector path
cat > android/app/src/main/res/drawable-v24/ic_launcher_foreground.xml << 'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#FFFFFF"
        android:pathData="M0,0h108v108h-108z" />
    <bitmap
        android:src="@drawable/ic_launcher_foreground"
        android:gravity="center" />
</vector>
EOF

# Replace web icons (PWA)
cp new_logo.png frontend/public/favicon.ico
cp new_logo.png frontend/public/logo192.png
cp new_logo.png frontend/public/logo512.png

echo "All icons replaced successfully!"
