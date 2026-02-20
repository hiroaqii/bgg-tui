package bgg

import (
	"encoding/json"
	"encoding/xml"
	"html"
	"strconv"
	"strings"
)

// toJSON marshals a value to indented JSON string.
func toJSON(v any) (string, error) {
	data, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return "", newParseError("failed to marshal to JSON", err)
	}
	return string(data), nil
}

// extractBoardGameRank returns the board game rank from a list of XML ranks.
// Returns 0 if not ranked or not found.
func extractBoardGameRank(ranks []xmlRank) int {
	for _, rank := range ranks {
		if rank.Name == "boardgame" {
			if rank.Value != "Not Ranked" {
				if r, err := strconv.Atoi(rank.Value); err == nil {
					return r
				}
			}
			break
		}
	}
	return 0
}

// decodeHTML decodes HTML entities and replaces &#10; with newlines.
func decodeHTML(s string) string {
	decoded := html.UnescapeString(s)
	decoded = strings.ReplaceAll(decoded, "&#10;", "\n")
	return decoded
}

// parseXML unmarshals XML data into a value of type T.
func parseXML[T any](body []byte, errMsg string) (*T, error) {
	var result T
	if err := xml.Unmarshal(body, &result); err != nil {
		return nil, newParseError(errMsg, err)
	}
	return &result, nil
}
