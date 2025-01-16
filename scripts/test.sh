#!/bin/bash

set -e

cd Monal
git submodule update -f --init --remote
bash ../rust/build-rust.sh
pod install --repo-update
xcodebuild \
    -workspace Monal.xcworkspace \
    -scheme Monal \
    -sdk iphoneos \
    -configuration Beta \
    -allowProvisioningUpdates \
    -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' \
    ARCHS=x86_64 \
    test
