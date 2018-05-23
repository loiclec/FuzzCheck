rm -rf .build/
mkdir -p .build/x86_64-apple-macosx10.10/release/CBuiltinsNotAvailableInSwift.build/
cat hidden/module.modulemap > .build/x86_64-apple-macosx10.10/release/CBuiltinsNotAvailableInSwift.build/module.modulemap
swift-build-tool --no-db -f build.yaml main
