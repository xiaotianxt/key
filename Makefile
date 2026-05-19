.PHONY: build check fmt clippy test install-local install release clean

build:
	cargo build --release

check:
	cargo check

fmt:
	cargo fmt --all

clippy:
	cargo clippy --all-targets -- -D warnings

test:
	cargo test

install-local: build
	mkdir -p ~/.local/bin
	cp target/release/key ~/.local/bin/
	@echo "installed: ~/.local/bin/key"

install: build
	sudo cp target/release/key /usr/local/bin/
	@echo "installed: /usr/local/bin/key"

release:
	scripts/release.sh

clean:
	cargo clean
	rm -f ~/.local/bin/key 2>/dev/null || true
