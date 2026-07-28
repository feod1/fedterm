APP     = dist/FedTerm.app
BINARY  = .build/release/FedTerm

.PHONY: build bundle run dev clean

build:
	swift build -c release

bundle: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp Resources/Info.plist $(APP)/Contents/
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/
	cp $(BINARY) $(APP)/Contents/MacOS/FedTerm
	codesign --force --sign - $(APP)
	@echo "Готово: $(APP)"

run: bundle
	open $(APP)

# быстрый дев-запуск без бандла
dev:
	swift run

clean:
	rm -rf .build dist
