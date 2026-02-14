package tui

import (
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"image"
	"image/png"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"golang.org/x/image/draw"

	_ "image/gif"
	_ "image/jpeg"
)

// Protocol represents the image display protocol.
type Protocol int

const (
	ProtocolNone  Protocol = iota
	ProtocolKitty
)

// detectProtocol determines the image protocol based on config and terminal.
func detectProtocol(configProtocol string) Protocol {
	switch strings.ToLower(configProtocol) {
	case "off":
		return ProtocolNone
	case "kitty":
		return ProtocolKitty
	}

	// auto detection
	termProgram := os.Getenv("TERM_PROGRAM")
	switch strings.ToLower(termProgram) {
	case "ghostty", "wezterm":
		return ProtocolKitty
	}

	term := os.Getenv("TERM")
	if term == "xterm-kitty" {
		return ProtocolKitty
	}

	return ProtocolNone
}

// imageCache manages downloaded images on disk.
type imageCache struct {
	dir string
}

// newImageCache creates a new image cache at ~/.cache/bgg-tui/images/.
func newImageCache() (*imageCache, error) {
	cacheDir, err := os.UserCacheDir()
	if err != nil {
		return nil, err
	}
	dir := filepath.Join(cacheDir, "bgg-tui", "images")
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, err
	}
	return &imageCache{dir: dir}, nil
}

// cacheKey returns a filename for the given URL.
func (c *imageCache) cacheKey(url string) string {
	h := sha256.Sum256([]byte(url))
	hex := fmt.Sprintf("%x", h[:8])
	ext := filepath.Ext(url)
	if ext == "" || len(ext) > 5 {
		ext = ".img"
	}
	return hex + ext
}

// Path returns the full path for a cached image.
func (c *imageCache) Path(url string) string {
	return filepath.Join(c.dir, c.cacheKey(url))
}

// Download fetches the image from url and saves to cache. Returns the path.
// If already cached, returns immediately.
func (c *imageCache) Download(url string) (string, error) {
	path := c.Path(url)
	if _, err := os.Stat(path); err == nil {
		return path, nil
	}

	resp, err := http.Get(url)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	f, err := os.Create(path)
	if err != nil {
		return "", err
	}
	defer f.Close()

	if _, err := io.Copy(f, resp.Body); err != nil {
		os.Remove(path)
		return "", err
	}

	return path, nil
}

// loadAndResize reads an image file and resizes it while maintaining aspect ratio.
func loadAndResize(path string, maxW, maxH int) (image.Image, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	src, _, err := image.Decode(f)
	if err != nil {
		return nil, err
	}

	bounds := src.Bounds()
	srcW := bounds.Dx()
	srcH := bounds.Dy()

	// Calculate target size maintaining aspect ratio
	scale := float64(maxW) / float64(srcW)
	if s := float64(maxH) / float64(srcH); s < scale {
		scale = s
	}

	dstW := int(float64(srcW) * scale)
	dstH := int(float64(srcH) * scale)
	if dstW < 1 {
		dstW = 1
	}
	if dstH < 1 {
		dstH = 1
	}

	dst := image.NewRGBA(image.Rect(0, 0, dstW, dstH))
	draw.BiLinear.Scale(dst, dst.Bounds(), src, bounds, draw.Over, nil)

	return dst, nil
}

const kittyChunkSize = 4096

// kittyDeleteSeq is the escape sequence to delete all Kitty graphics images.
const kittyDeleteSeq = "\033_Ga=d\033\\"

// kittyTransmitString generates Kitty graphics protocol escape sequences to transmit
// an image using Unicode placeholder mode (U=1). The image is stored in the terminal's
// graphics memory but not directly displayed; use kittyPlaceholder to place it.
func kittyTransmitString(img image.Image, id uint32) (string, error) {
	var buf strings.Builder
	if err := png.Encode(&buf, img); err != nil {
		return "", err
	}

	encoded := base64.StdEncoding.EncodeToString([]byte(buf.String()))

	var sb strings.Builder
	for i := 0; i < len(encoded); i += kittyChunkSize {
		end := i + kittyChunkSize
		if end > len(encoded) {
			end = len(encoded)
		}
		chunk := encoded[i:end]

		more := 1
		if end >= len(encoded) {
			more = 0
		}

		if i == 0 {
			fmt.Fprintf(&sb, "\033_Ga=T,U=1,f=100,t=d,i=%d,q=2,m=%d;%s\033\\", id, more, chunk)
		} else {
			fmt.Fprintf(&sb, "\033_Gm=%d;%s\033\\", more, chunk)
		}
	}

	return sb.String(), nil
}

// kittyRowDiacritics maps row indices to Unicode combining characters used by the
// Kitty Unicode placeholder protocol to encode which row of the image each cell belongs to.
var kittyRowDiacritics = []rune{
	0x0305, 0x030D, 0x030E, 0x0310, 0x0312, 0x033D, 0x033E, 0x033F,
	0x0346, 0x034A, 0x034B, 0x034C, 0x0350, 0x0351, 0x0352, 0x0357,
	0x035B, 0x0363, 0x0364, 0x0365, 0x0366, 0x0367, 0x0368, 0x0369,
	0x036A, 0x036B, 0x036C, 0x036D, 0x036E, 0x036F,
}

// kittyPlaceholder generates a grid of U+10EEEE placeholder characters that the
// terminal replaces with the image identified by id. rows and cols specify the grid size.
func kittyPlaceholder(id uint32, rows, cols int) string {
	var sb strings.Builder

	// Encode image ID as 24-bit foreground color (R=high byte, G=mid, B=low)
	r := (id >> 16) & 0xFF
	g := (id >> 8) & 0xFF
	b := id & 0xFF
	placeholder := "\U0010EEEE"
	for row := 0; row < rows; row++ {
		fmt.Fprintf(&sb, "\033[38;2;%d;%d;%dm", r, g, b)
		for col := 0; col < cols; col++ {
			sb.WriteString(placeholder)
			if row < len(kittyRowDiacritics) {
				sb.WriteRune(kittyRowDiacritics[row])
			}
		}
		sb.WriteString("\033[39m")
		if row < rows-1 {
			sb.WriteString("\n")
		}
	}
	return sb.String()
}

// imageLoadedMsg is sent when an image has been loaded and rendered (Detail view).
type imageLoadedMsg struct {
	url            string
	imgTransmit    string // APC transmit sequence
	imgPlaceholder string // Unicode placeholder grid
	err            error
}

const listImageID uint32 = 2 // Detail uses 1

// listImageMsg is sent when a list thumbnail has been loaded (Hot/Collection views).
type listImageMsg struct {
	url            string
	imgTransmit    string
	imgPlaceholder string
	err            error
}

const listImageCols = 14
const listImageRows = 8

// padPlaceholder pads a placeholder string to exactly rows lines of cols width.
// Each line is right-padded with spaces to cols width, and missing rows are filled
// with cols-width blank lines.
func padPlaceholder(s string, rows, cols int) string {
	lines := strings.Split(s, "\n")
	blank := strings.Repeat(" ", cols)
	var sb strings.Builder
	for i := 0; i < rows; i++ {
		if i > 0 {
			sb.WriteString("\n")
		}
		if i < len(lines) {
			sb.WriteString(lines[i])
			// Pad to cols width if the line is shorter
			// Use lipgloss.Width to measure visible width (ignoring ANSI escapes)
			w := lipgloss.Width(lines[i])
			if w < cols {
				sb.WriteString(strings.Repeat(" ", cols-w))
			}
		} else {
			sb.WriteString(blank)
		}
	}
	return sb.String()
}

// fixedSizeLoadingPanel returns a fixed-size block for the loading state.
// The block is rows lines tall and cols columns wide, with "Loading..." centered
// vertically in the first line and the rest filled with spaces.
func fixedSizeLoadingPanel(cols, rows int) string {
	blank := strings.Repeat(" ", cols)
	var sb strings.Builder
	for i := 0; i < rows; i++ {
		if i > 0 {
			sb.WriteString("\n")
		}
		if i == 0 {
			label := "Loading..."
			if len(label) < cols {
				sb.WriteString(label)
				sb.WriteString(strings.Repeat(" ", cols-len(label)))
			} else {
				sb.WriteString(label[:cols])
			}
		} else {
			sb.WriteString(blank)
		}
	}
	return sb.String()
}

// fixedSizeNoImagePanel returns a fixed-size block for the error/no-image state.
func fixedSizeNoImagePanel(cols, rows int) string {
	blank := strings.Repeat(" ", cols)
	var sb strings.Builder
	for i := 0; i < rows; i++ {
		if i > 0 {
			sb.WriteString("\n")
		}
		if i == 0 {
			label := "No Image"
			if len(label) < cols {
				sb.WriteString(label)
				sb.WriteString(strings.Repeat(" ", cols-len(label)))
			} else {
				sb.WriteString(label[:cols])
			}
		} else {
			sb.WriteString(blank)
		}
	}
	return sb.String()
}

// loadListImage loads a thumbnail image for list views (hot/collection).
func loadListImage(cache *imageCache, url string) tea.Cmd {
	return func() tea.Msg {
		path, err := cache.Download(url)
		if err != nil {
			return listImageMsg{url: url, err: err}
		}

		cellW, cellH := termCellSize()
		pixW := listImageCols * cellW
		pixH := listImageRows * cellH

		img, err := loadAndResize(path, pixW, pixH)
		if err != nil {
			return listImageMsg{url: url, err: err}
		}

		bounds := img.Bounds()
		actualCols := (bounds.Dx() + cellW - 1) / cellW
		actualRows := (bounds.Dy() + cellH - 1) / cellH
		if actualCols < 1 {
			actualCols = 1
		}
		if actualRows < 1 {
			actualRows = 1
		}

		transmit, err := kittyTransmitString(img, listImageID)
		if err != nil {
			return listImageMsg{url: url, err: err}
		}

		placeholder := kittyPlaceholder(listImageID, actualRows, actualCols)
		placeholder = padPlaceholder(placeholder, listImageRows, listImageCols)
		return listImageMsg{url: url, imgTransmit: transmit, imgPlaceholder: placeholder}
	}
}
