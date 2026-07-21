.PHONY: all test cli gui app clean

all: test

test:
	swift test

cli:
	swift build --product vader5-cli

gui:
	swift build --product Vader5GUI

app:
	./scripts/package-app.sh

clean:
	swift package clean
	rm -rf build
