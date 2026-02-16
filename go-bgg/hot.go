package bgg

// GetHotGames retrieves the current hot games list.
func (c *Client) GetHotGames() ([]HotGame, error) {
	endpoint := "/hot?type=boardgame"

	body, err := c.doRequest(endpoint)
	if err != nil {
		return nil, err
	}

	xmlResp, err := parseXML[xmlHot](body, "failed to parse hot games response")
	if err != nil {
		return nil, err
	}

	games := make([]HotGame, 0, len(xmlResp.Items))
	for _, item := range xmlResp.Items {
		games = append(games, HotGame{
			ID:        item.ID,
			Rank:      item.Rank,
			Name:      item.Name.Value,
			Year:      item.YearValue.Value,
			Thumbnail: item.Thumbnail.Value,
		})
	}

	return games, nil
}

// GetHotGamesJSON retrieves the current hot games list and returns JSON.
func (c *Client) GetHotGamesJSON() (string, error) {
	games, err := c.GetHotGames()
	if err != nil {
		return "", err
	}
	return toJSON(games)
}
