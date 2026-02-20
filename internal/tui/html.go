package tui

import (
	"fmt"
	"html"
	"regexp"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/muesli/termenv"
	xhtml "golang.org/x/net/html"
)

type tagInfo struct {
	name     string
	href     string
	isQuote  bool
	startPos int
}

type htmlConverter struct {
	result        strings.Builder
	quoteDepth    int
	inOrderedList bool
	olCounter     int
	skipContent   bool
	tagStack      []tagInfo
	width         int
}

// htmlToText converts HTML content to formatted plain text lines with word wrapping.
// It interprets common HTML tags (<br>, <p>, <b>, <a>, <blockquote>, <li>, etc.)
// and falls back to wrapText for non-HTML content.
func htmlToText(htmlContent string, width int) []string {
	c := &htmlConverter{width: width}
	return c.convert(htmlContent)
}

// ensureNewline adds a newline if the result doesn't already end with one.
func (c *htmlConverter) ensureNewline() {
	text := c.result.String()
	if len(text) > 0 && !strings.HasSuffix(text, "\n") {
		c.result.WriteString("\n")
	}
}

// ensureBlankLine adds a blank line (double newline) if the result doesn't already have one.
func (c *htmlConverter) ensureBlankLine() {
	text := c.result.String()
	if len(text) > 0 && !strings.HasSuffix(text, "\n\n") {
		if strings.HasSuffix(text, "\n") {
			c.result.WriteString("\n")
		} else {
			c.result.WriteString("\n\n")
		}
	}
}

// writeQuotedText writes text with quote prefixes when inside blockquotes.
func (c *htmlConverter) writeQuotedText(text string) {
	if c.quoteDepth > 0 {
		prefix := strings.Repeat("│ ", c.quoteDepth)
		lines := strings.Split(text, "\n")
		for i, line := range lines {
			trimmed := strings.TrimSpace(line)
			if trimmed != "" {
				c.result.WriteString(prefix + trimmed)
			}
			if i < len(lines)-1 {
				c.result.WriteString("\n")
			}
		}
	} else {
		c.result.WriteString(text)
	}
}

// popTag removes and returns the most recent tag with the given name from the stack.
func (c *htmlConverter) popTag(name string) (tagInfo, bool) {
	for i := len(c.tagStack) - 1; i >= 0; i-- {
		if c.tagStack[i].name == name {
			info := c.tagStack[i]
			c.tagStack = append(c.tagStack[:i], c.tagStack[i+1:]...)
			return info, true
		}
	}
	return tagInfo{}, false
}

func (c *htmlConverter) convert(htmlContent string) []string {
	decoded := html.UnescapeString(htmlContent)
	tokenizer := xhtml.NewTokenizer(strings.NewReader(decoded))

	for {
		tt := tokenizer.Next()
		switch tt {
		case xhtml.ErrorToken:
			goto done
		case xhtml.StartTagToken, xhtml.SelfClosingTagToken:
			c.handleStartTag(tokenizer, tt)
		case xhtml.EndTagToken:
			c.handleEndTag(tokenizer)
		case xhtml.TextToken:
			c.handleText(tokenizer)
		}
	}

done:
	output := c.result.String()
	if strings.TrimSpace(output) == "" {
		return wrapText(decoded, c.width)
	}
	return wrapText(output, c.width)
}

func (c *htmlConverter) handleStartTag(tokenizer *xhtml.Tokenizer, tt xhtml.TokenType) {
	tn, hasAttr := tokenizer.TagName()
	tagName := string(tn)

	switch tagName {
	case "br":
		c.result.WriteString("\n")
	case "p":
		c.ensureBlankLine()
	case "blockquote", "gg-markup-quote":
		c.quoteDepth++
		c.ensureNewline()
	case "a":
		href := ""
		if hasAttr {
			for {
				key, val, more := tokenizer.TagAttr()
				if string(key) == "href" {
					href = string(val)
				}
				if !more {
					break
				}
			}
		}
		c.tagStack = append(c.tagStack, tagInfo{name: "a", href: href, startPos: c.result.Len()})
	case "ol":
		c.inOrderedList = true
		c.olCounter = 0
	case "ul":
		// nothing special, li handles prefix
	case "li":
		c.ensureNewline()
		if c.inOrderedList {
			c.olCounter++
			c.result.WriteString(fmt.Sprintf("%d. ", c.olCounter))
		} else {
			c.result.WriteString("- ")
		}
	case "div":
		c.handleDivStart(tokenizer, hasAttr)
	case "img":
		c.skipContent = false // img is self-closing, just skip
	case "script", "style":
		c.skipContent = true
	default:
		// For other tags (b, i, u, span, font, etc.), just continue
	}

	// Push non-a/div tags to stack if needed
	if tagName != "a" && tagName != "div" && tt == xhtml.StartTagToken {
		c.tagStack = append(c.tagStack, tagInfo{name: tagName})
	}
}

func (c *htmlConverter) handleDivStart(tokenizer *xhtml.Tokenizer, hasAttr bool) {
	isQuote := false
	if hasAttr {
		for {
			key, val, more := tokenizer.TagAttr()
			if string(key) == "class" && string(val) == "quote" {
				isQuote = true
			}
			if !more {
				break
			}
		}
	}
	if isQuote {
		c.quoteDepth++
		c.ensureNewline()
	}
	c.tagStack = append(c.tagStack, tagInfo{name: "div", isQuote: isQuote})
}

func (c *htmlConverter) handleEndTag(tokenizer *xhtml.Tokenizer) {
	tn, _ := tokenizer.TagName()
	tagName := string(tn)

	switch tagName {
	case "a":
		c.handleAnchorEnd()
	case "blockquote", "gg-markup-quote":
		if c.quoteDepth > 0 {
			c.quoteDepth--
		}
		c.ensureNewline()
	case "ol":
		c.inOrderedList = false
		c.olCounter = 0
	case "p":
		c.ensureBlankLine()
	case "div":
		c.handleDivEnd()
	case "script", "style":
		c.skipContent = false
	default:
		c.popTag(tagName)
	}
}

func (c *htmlConverter) handleAnchorEnd() {
	info, ok := c.popTag("a")
	if !ok {
		return
	}
	href := info.href
	if href == "" {
		return
	}

	linkText := c.result.String()[info.startPos:]
	// Extract URL portion (may have quote prefix like "│ │ ")
	urlText := linkText
	prefix := ""
	if idx := strings.Index(linkText, "http"); idx > 0 {
		prefix = linkText[:idx]
		urlText = linkText[idx:]
	}
	trimmed := strings.TrimSuffix(urlText, "...")
	if strings.HasPrefix(href, trimmed) {
		// Link text is a (possibly truncated) URL → replace with full URL
		s := c.result.String()[:info.startPos]
		c.result.Reset()
		c.result.WriteString(s)
		c.result.WriteString(prefix)
		c.result.WriteString(href)
	} else {
		c.result.WriteString(" (" + href + ")")
	}
}

func (c *htmlConverter) handleDivEnd() {
	info, ok := c.popTag("div")
	if !ok {
		return
	}
	if info.isQuote {
		if c.quoteDepth > 0 {
			c.quoteDepth--
		}
		c.ensureNewline()
	}
}

func (c *htmlConverter) handleText(tokenizer *xhtml.Tokenizer) {
	if c.skipContent {
		return
	}
	text := string(tokenizer.Text())
	if strings.TrimSpace(text) == "" {
		// Preserve a single space for whitespace-only text between inline elements
		if len(text) > 0 {
			current := c.result.String()
			if len(current) > 0 && !strings.HasSuffix(current, " ") && !strings.HasSuffix(current, "\n") {
				c.result.WriteString(" ")
			}
		}
		return
	}

	c.writeQuotedText(text)
}

var urlRegex = regexp.MustCompile(`https?://[^\s)]+`)

func linkifyLines(lines []string) []string {
	linkStyle := lipgloss.NewStyle().Foreground(ColorLink).Underline(true)
	result := make([]string, len(lines))
	for i, line := range lines {
		result[i] = urlRegex.ReplaceAllStringFunc(line, func(rawURL string) string {
			url := strings.TrimRight(rawURL, ".,;:!?")
			suffix := rawURL[len(url):]
			styledText := linkStyle.Render(url)
			return termenv.Hyperlink(url, styledText) + suffix
		})
	}
	return result
}
