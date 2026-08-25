APP = DerivedData/Build/Products/Release/HueBar.app
LSREGISTER = /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister

.PHONY: test app install clean

test:
	swift test

app:
	xcodegen generate
	xcodebuild -project HueBar.xcodeproj -scheme HueBar -configuration Release -derivedDataPath DerivedData build

install: app
	killall HueBar 2>/dev/null || true
	rm -rf /Applications/HueBar.app
	ditto "$(APP)" /Applications/HueBar.app
	$(LSREGISTER) -f -R -trusted /Applications/HueBar.app
	open /Applications/HueBar.app

clean:
	rm -rf .build build DerivedData HueBar.xcodeproj
