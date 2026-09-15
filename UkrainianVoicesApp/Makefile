.PHONY: generate build test clean archive

# Проєкт описаний у project.yml; UkrainianVoices.xcodeproj — згенерований.
# Без цього кроку нові файли (зокрема en.lproj/uk.lproj з перекладом інтерфейсу)
# у бандл НЕ потраплять, і збірка мовчки вийде без англійської локалізації.
generate:
	@echo "🧩 Generating Xcode project from project.yml..."
	xcodegen generate

SCHEME = UkrainianVoices
CONFIGURATION = Release
DEVICE_SDK = iphoneos
SIMULATOR_SDK = iphonesimulator

build: generate
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

archive: generate
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
