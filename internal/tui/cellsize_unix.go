//go:build !windows

package tui

import (
	"os"

	"golang.org/x/sys/unix"
)

func termCellSize() (cellW, cellH int) {
	ws, err := unix.IoctlGetWinsize(int(os.Stdout.Fd()), unix.TIOCGWINSZ)
	if err == nil && ws.Col > 0 && ws.Row > 0 && ws.Xpixel > 0 && ws.Ypixel > 0 {
		cellW = int(ws.Xpixel) / int(ws.Col)
		cellH = int(ws.Ypixel) / int(ws.Row)
	}
	if cellW < 1 {
		cellW = 8
	}
	if cellH < 1 {
		cellH = 16
	}
	return
}
