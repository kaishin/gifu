PLATFORM ?= "iOS Simulator,name=iPhone 16"

test-ios:
	set -o pipefail && \
	xcodebuild test \
		-project Gifu.xcodeproj \
		-scheme Gifu \
		-destination platform=$(PLATFORM) \
		| xcbeautify

test-tvos:
	set -o pipefail && \
	xcodebuild test \
		-project Gifu.xcodeproj \
		-scheme Gifu \
		-destination platform="tvOS Simulator,name=Apple TV" \
		| xcbeautify
