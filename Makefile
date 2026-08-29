.PHONY: gen build test check run clean all

PROJECT := Notebar.xcodeproj
SCHEME  := Notebar
CONFIG  := Debug
APP     := $(HOME)/Library/Developer/Xcode/DerivedData/Notebar-*/Build/Products/$(CONFIG)/Notebar.app

all: check test build

gen:
	xcodegen generate

build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) build -quiet

# Core tests need no Xcode and finish in about a second. Use these constantly.
test:
	cd Packages/NotebarCore && swift test

check:
	./scripts/check-core-purity.sh

run: build
	@pkill -x Notebar || true
	@open $(APP)

clean:
	rm -rf $(PROJECT) .build Packages/NotebarCore/.build
