//go:build windows

package tui

func termCellSize() (cellW, cellH int) {
	return 8, 16
}
