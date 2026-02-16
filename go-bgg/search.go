package bgg

import (
	"fmt"
	"net/url"
)

// SearchGames searches for board games by name.
// Returns a list of matching games.
func (c *Client) SearchGames(query string) ([]GameSearchResult, error) {
	if query == "" {
		return nil, newParseError("search query cannot be empty", nil)
	}

	endpoint := fmt.Sprintf("/search?query=%s&type=boardgame,boardgameexpansion", url.QueryEscape(query))

	body, err := c.doRequest(endpoint)
	if err != nil {
		return nil, err
	}

	xmlResp, err := parseXML[xmlItems](body, "failed to parse search response")
	if err != nil {
		return nil, err
	}

	results := make([]GameSearchResult, 0, len(xmlResp.Items))
	for _, item := range xmlResp.Items {
		results = append(results, GameSearchResult{
			ID:   item.ID,
			Name: item.Name.Value,
			Year: item.YearValue.Value,
			Type: item.Type,
		})
	}

	return results, nil
}

// SearchGamesJSON searches for board games by name and returns JSON.
func (c *Client) SearchGamesJSON(query string) (string, error) {
	results, err := c.SearchGames(query)
	if err != nil {
		return "", err
	}
	return toJSON(results)
}
