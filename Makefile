APP = build/HueBar.app
BINARY = .build/release/HueBarApp

.PHONY: test app install clean

test:
	swift test

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp $(BINARY) $(APP)/Contents/MacOS/HueBar
	cp Support/Info.plist $(APP)/Contents/Info.plist
	codesign --force -s - $(APP)

install: app
	killall HueBar 2>/dev/null || true
	rm -rf /Applications/HueBar.app
	cp -R $(APP) /Applications/
	open /Applications/HueBar.app

clean:
	rm -rf .build build
