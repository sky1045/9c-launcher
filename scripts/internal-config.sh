#!/bin/bash
set -ex

if [[ "$APV_SIGN_KEY_INTERNAL" = "" ]]; then
  echo "APV_SIGN_KEY_INTERNAL is not configured." > /dev/stderr
  exit 1
elif command -v npx > /dev/null && \
     npx --no-install -q planet --version > /dev/null; then
  function planet {
    npx --no-install -q planet "$@"
  }
elif ! command -v planet > /dev/null; then
  {
    echo "The planet command does not exist."
    echo "Please install Libplanet.Tools first:"
    echo "  dotnet tool install --global Libplanet.Tools"
  } >&2
  exit 1
fi

APV_NO=$(expr $(cat scripts/internal.json | jq -r ".Apv") + 1)

COMMIT_HASH="$(git rev-parse HEAD)"
aws s3 cp s3://9c-artifacts/9c-launcher/$COMMIT_HASH/ package --recursive

mkdir linux && tar -xvf package/Linux.tar.gz -C linux
mkdir macos && tar -xvf package/MacOS.tar.gz -C macos
unzip package/Windows.zip -d ./windows

# new player
player_commit_hash=$(git submodule status NineChronicles | awk '{print $1}')
default_url_base=https://release.nine-chronicles.com/internal/v
macos_url="${APV_MACOS_URL:-$default_url_base$APV_NO/player/$player_commit_hash/macOS.tar.gz}"
linux_url="${APV_LINUX_URL:-$default_url_base$APV_NO/player/$player_commit_hash/Linux.tar.gz}"
windows_url="${APV_WINDOWS_URL:-$default_url_base$APV_NO/player/$player_commit_hash/Windows.zip}"

# sign new APV with APV_NO
passphrase="$(LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 32 | head -n 1)"
key_id="$(planet key import --passphrase="$passphrase" "${APV_SIGN_KEY_INTERNAL%%*( )}" \
          | awk '{print $1}')"
apv="$( \
  planet apv sign \
    --passphrase="$passphrase" \
    --extra macOSBinaryUrl="$macos_url" \
    --extra LinuxBinaryUrl="$linux_url" \
    --extra WindowsBinaryUrl="$windows_url" \
    --extra timestamp="$(date --iso-8601=sec)" \
    "$key_id" \
    "$APV_NO"
)"
echo "$apv"
planet key remove --passphrase="$passphrase" "$key_id"

# overwrite new APV on config.json
jq -r ".AppProtocolVersion = \"$apv\"" 'windows/resources/app/config.json' > config.json
cp config.json windows/resources/app/config.json
cp config.json linux/resources/app/config.json
cp config.json macos/Nine\ Chronicles.app/Contents/Resources/app/config.json
rm config.json

# upload(overwrite) to s3
7zr a -r package/win.zip windows/*
tar cvfz package/mac.tar.gz macos/*
tar cvfz package/linux.tar.gz linux/*

aws s3 cp package/ s3://9c-release.planetariumhq.com/internal/$APV_NO/launcher/v1/ --recursive
aws s3 cp package/ s3://9c-release.planetariumhq.com/internal/$APV_NO/launcher/$COMMIT_HASH/ --recursive

rm -rf windows linux macos package
