package bgg

import (
	"encoding/json"
	"encoding/xml"
)

// toJSON marshals a value to indented JSON string.
func toJSON(v any) (string, error) {
	data, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return "", newParseError("failed to marshal to JSON", err)
	}
	return string(data), nil
}

// parseXML unmarshals XML data into a value of type T.
func parseXML[T any](body []byte, errMsg string) (*T, error) {
	var result T
	if err := xml.Unmarshal(body, &result); err != nil {
		return nil, newParseError(errMsg, err)
	}
	return &result, nil
}
