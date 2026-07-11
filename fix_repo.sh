#!/data/data/com.termux/files/usr/bin/bash
set -e
cd ~/osias-clone_V1

echo "== removing leftover duplicate osias-clone/ folder (has its own .git, causes submodule confusion) =="
rm -rf osias-clone

echo "== increasing git buffer/timeout tolerance for flaky mobile connections =="
git config --global http.postBuffer 524288000
git config --global http.lowSpeedLimit 0
git config --global http.lowSpeedTime 999999

echo "== staging everything cleanly now =="
git add .
git status
