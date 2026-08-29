.PHONY: build test icon app run clean

build:
	swift build

test:
	swift test

icon:
	./scripts/build-icon.sh

app:
	./scripts/build-app.sh

run: app
	open -n dist/LidSwitch.app

clean:
	swift package clean
