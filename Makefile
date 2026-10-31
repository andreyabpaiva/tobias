# Developer shortcuts. Users install with install.sh / the tobias CLI instead.
CLT_DEV := /Library/Developer/CommandLineTools/Library/Developer
TEST_FLAGS := $(shell if xcode-select -p 2>/dev/null | grep -q CommandLineTools && [ -d "$(CLT_DEV)/Frameworks/Testing.framework" ]; then echo "-Xswiftc -F$(CLT_DEV)/Frameworks -Xlinker -F$(CLT_DEV)/Frameworks -Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks -Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib"; fi)

.PHONY: build test scan run clean

build:
	swift build

test:
	swift test $(TEST_FLAGS)

# Read-only table of sizes, no window.
scan: build
	.build/debug/Tobias --scan

run:
	swift run Tobias

clean:
	swift package clean
