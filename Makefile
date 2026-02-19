VERSION := $(shell git describe --tags --always --dirty 2>/dev/null | sed 's/^v//' || echo "dev")
LDFLAGS := -s -w -X github.com/hiroaqii/bgg-tui/internal/tui.Version=$(VERSION)

.PHONY: build clean

build:
	go build -ldflags "$(LDFLAGS)" -o bgg-tui ./cmd/bgg-tui

clean:
	rm -f bgg-tui
