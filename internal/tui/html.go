package tui

import (
	"fmt"
	"html"
	"strings"

	xhtml "golang.org/x/net/html"
)

// htmlToText converts HTML content to formatted plain text lines with word wrapping.
// It interprets common HTML tags (<br>, <p>, <b>, <a>, <blockquote>, <li>, etc.)
// and falls back to wrapText for non-HTML content.
func htmlToText(htmlContent string, width int) []string {
	// Decode HTML entities first
	decoded := html.UnescapeString(htmlContent)

	tokenizer := xhtml.NewTokenizer(strings.NewReader(decoded))

	var (
		result       strings.Builder
		inBlockquote bool
		inOrderedList bool
		olCounter    int
		skipContent  bool
	)

	// tagStack tracks open tags for context
	type tagInfo struct {
		name string
		href string
	}
	var tagStack []tagInfo

	for {
		tt := tokenizer.Next()

		switch tt {
		case xhtml.ErrorToken:
			// End of input or parse error
			goto done

		case xhtml.StartTagToken, xhtml.SelfClosingTagToken:
			tn, hasAttr := tokenizer.TagName()
			tagName := string(tn)

			switch tagName {
			case "br":
				result.WriteString("\n")
			case "p":
				// Add paragraph break (blank line) if there's already content
				text := result.String()
				if len(text) > 0 && !strings.HasSuffix(text, "\n\n") {
					if strings.HasSuffix(text, "\n") {
						result.WriteString("\n")
					} else {
						result.WriteString("\n\n")
					}
				}
			case "blockquote":
				inBlockquote = true
				text := result.String()
				if len(text) > 0 && !strings.HasSuffix(text, "\n") {
					result.WriteString("\n")
				}
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
				tagStack = append(tagStack, tagInfo{name: "a", href: href})
			case "ol":
				inOrderedList = true
				olCounter = 0
			case "ul":
				// nothing special, li handles prefix
			case "li":
				text := result.String()
				if len(text) > 0 && !strings.HasSuffix(text, "\n") {
					result.WriteString("\n")
				}
				if inOrderedList {
					olCounter++
					result.WriteString(fmt.Sprintf("%d. ", olCounter))
				} else {
					result.WriteString("- ")
				}
			case "img":
				skipContent = false // img is self-closing, just skip
			case "script", "style":
				skipContent = true
			default:
				// For other tags (b, i, u, span, div, etc.), just continue
			}

			// Push non-a tags to stack if needed
			if tagName != "a" && tt == xhtml.StartTagToken {
				tagStack = append(tagStack, tagInfo{name: tagName})
			}

		case xhtml.EndTagToken:
			tn, _ := tokenizer.TagName()
			tagName := string(tn)

			switch tagName {
			case "a":
				// Pop the tag stack and append URL if present
				for i := len(tagStack) - 1; i >= 0; i-- {
					if tagStack[i].name == "a" {
						if tagStack[i].href != "" {
							result.WriteString(" (" + tagStack[i].href + ")")
						}
						tagStack = append(tagStack[:i], tagStack[i+1:]...)
						break
					}
				}
			case "blockquote":
				inBlockquote = false
			case "ol":
				inOrderedList = false
				olCounter = 0
			case "p":
				text := result.String()
				if len(text) > 0 && !strings.HasSuffix(text, "\n\n") {
					if strings.HasSuffix(text, "\n") {
						result.WriteString("\n")
					} else {
						result.WriteString("\n\n")
					}
				}
			case "script", "style":
				skipContent = false
			default:
				// Pop from tag stack
				for i := len(tagStack) - 1; i >= 0; i-- {
					if tagStack[i].name == tagName {
						tagStack = append(tagStack[:i], tagStack[i+1:]...)
						break
					}
				}
			}

		case xhtml.TextToken:
			if skipContent {
				continue
			}
			text := string(tokenizer.Text())
			if strings.TrimSpace(text) == "" {
				// Preserve a single space for whitespace-only text between inline elements
				if len(text) > 0 {
					current := result.String()
					if len(current) > 0 && !strings.HasSuffix(current, " ") && !strings.HasSuffix(current, "\n") {
						result.WriteString(" ")
					}
				}
				continue
			}

			if inBlockquote {
				// Prefix each line with "> "
				lines := strings.Split(text, "\n")
				for i, line := range lines {
					trimmed := strings.TrimSpace(line)
					if trimmed != "" {
						result.WriteString("> " + trimmed)
					}
					if i < len(lines)-1 {
						result.WriteString("\n")
					}
				}
			} else {
				result.WriteString(text)
			}
		}
	}

done:
	output := result.String()
	if strings.TrimSpace(output) == "" {
		// Fallback: if tokenizer produced nothing useful, use wrapText on decoded input
		return wrapText(decoded, width)
	}

	// Apply word wrapping to the final text
	return wrapText(output, width)
}
