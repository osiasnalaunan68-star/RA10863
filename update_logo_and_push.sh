#!/bin/bash

echo "Hahanapin ang 11928.jpg sa phone storage mo. Sandali lang..."

# Hahanapin nang kusa sa buong internal storage ng phone
LOGO_PATH=$(find /storage/emulated/0 -name "11928.jpg" -type f 2>/dev/null | head -n 1)

# Kung sakaling hindi nakita agad, susubukan sa Termux storage shortcut
if [ -z "$LOGO_PATH" ]; then
  LOGO_PATH=$(find ~/storage -name "11928.jpg" -type f 2>/dev/null | head -n 1)
fi

# Kung wala talaga, baka kailangan ng storage permission
if [ -z "$LOGO_PATH" ]; then
  echo "Error: Hindi pa rin makita ang 11928.jpg."
  echo "Baka wala pang storage permission ang Termux mo."
  echo "I-type ito: termux-setup-storage (tapos i-allow sa popup)"
  echo "At i-paste ulit ang script na ito."
  exit 1
fi

echo "Nakita ang logo sa: $LOGO_PATH"

echo "Papalitan ang mga logo sa Android..."
for dir in android/app/src/main/res/mipmap-*; do
  if [ -d "$dir" ]; then
    cp -f "$LOGO_PATH" "$dir/ic_launcher.png"
    cp -f "$LOGO_PATH" "$dir/ic_launcher_round.png"
  fi
done

echo "Papalitan ang mga logo sa Web/Frontend..."
if [ -d "frontend/public" ]; then
  cp -f "$LOGO_PATH" frontend/public/favicon.ico 2>/dev/null
  cp -f "$LOGO_PATH" frontend/public/logo192.png 2>/dev/null
  cp -f "$LOGO_PATH" frontend/public/logo512.png 2>/dev/null
fi

echo "Sini-save ang mga changes sa Git..."
git add .

echo "Kino-commit ang bagong logo..."
git commit -m "chore: update app logo using 11928.jpg from storage"

echo "Pina-push sa GitHub..."
git push

echo "SUCCESS! Na-push na ang bagong logo sa GitHub. Hintayin mo na lang sa Codemagic!"
