.PHONY: build test clean archive

SCHEME = UkrainianVoices
CONFIGURATION = Release
DEVICE_SDK = iphoneos
SIMULATOR_SDK = iphonesimulator

build:
	@echo "🔨 Building for device..."
	xcodebuild -scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-sdk $(DEVICE_SDK) \
		-destination 'generic/platform=iOS' \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO

test:
	@echo "🧪 Running tests..."
	swift test

clean:
	@echo "🧹 Cleaning..."
	rm -rf .build build

archive:
	@echo "📦 Creating archive..."
	xcodebuild archive \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-sdk $(DEVICE_SDK) \
		-archivePath build/UkrainianVoices.xcarchive \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO

ipa: archive
	@echo "📱 Creating IPA..."
	mkdir -p build/Payload
	cp -r build/UkrainianVoices.xcarchive/Products/Applications/*.app build/Payload/
	cd build && zip -r UkrainianVoices.ipa Payload
	@echo "✅ IPA created: build/UkrainianVoices.ipa"
