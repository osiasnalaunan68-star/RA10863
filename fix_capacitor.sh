#!/data/data/com.termux/files/usr/bin/bash
set -e
cd ~/osias-clone_V1

echo "== installing @capacitor/cli (this was missing, root cause of npx cap error) =="
npm install --save-dev @capacitor/cli@^8.4.1

echo "== adding android platform (skips if already added) =="
[ -d android ] || npx cap add android

echo "== syncing dist/ web build into android project =="
npx cap sync android

echo ""
echo "Done. android/ folder is now ready."
