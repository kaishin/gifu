DEVICE ?= "iPhone 15"

test-ios:
	set -o pipefail && \
	xcodebuild test \
		-project Gifu.xcodeproj \
		-scheme Gifu \
		-destination platform="iOS Simulator,name=$(DEVICE)" \
		| xcpretty

test-tvos:
	set -o pipefail && \
	xcodebuild test \
		-project Gifu.xcodeproj \
		-scheme Gifu \
		-destination platform="tvOS Simulator,name=Apple TV" \
		| xcpretty
