#!/bin/bash
set -e

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
7zr x package/Windows.zip -o./windows/

# new player
player_commit_hash=$(git submodule status NineChronicles | awk '{print $1}')

# sign new APV with APV_NO
passphrase="$(LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 32 | head -n 1)"
key_id="$(planet key import --passphrase="$passphrase" "${APV_SIGN_KEY_INTERNAL%%*( )}" \
          | awk '{print $1}')"
apv="$( \
  planet apv sign \
    --passphrase="$passphrase" \
    --extra player=$player_commit_hash \
    --extra launcher=$COMMIT_HASH \
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
7zr a -r package/Windows.zip windows/*
tar cvfz package/MacOS.tar.gz macos/*
tar cvfz package/Linux.tar.gz linux/*

aws s3 cp package/ s3://9c-release.planetariumhq.com/internal/v$APV_NO/launcher/v1/ --recursive
aws s3 cp package/ s3://9c-release.planetariumhq.com/internal/v$APV_NO/launcher/$COMMIT_HASH/ --recursive

rm -rf windows linux macos package
