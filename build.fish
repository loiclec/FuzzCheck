mkdir -p .build/x86_64-apple-macosx10.10/$argv[1]/CBuiltinsNotAvailableInSwift.build/
cat hidden/module.modulemap > .build/x86_64-apple-macosx10.10/$argv[1]/CBuiltinsNotAvailableInSwift.build/module.modulemap
swift-build-tool --no-db -f build-$argv[1].yaml main
rm (ls Corpus | ack "[^(.json)]+\$" --output="Corpus/\$&")