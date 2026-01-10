package bgg

import (
	"encoding/json"
	"encoding/xml"
	"fmt"
	"html"
	"strconv"
	"strings"
)

// GetGame retrieves detailed information about a single game.
func (c *Client) GetGame(id int) (*Game, error) {
	if id <= 0 {
		return nil, newNotFoundError(id)
	}

	endpoint := fmt.Sprintf("/thing?id=%d&stats=1", id)

	body, err := c.doRequest(endpoint)
	if err != nil {
		return nil, err
	}

	var xmlResp xmlThing
	if err := xml.Unmarshal(body, &xmlResp); err != nil {
		return nil, newParseError("failed to parse thing response", err)
	}

	if len(xmlResp.Items) == 0 {
		return nil, newNotFoundError(id)
	}

	game := convertXMLToGame(xmlResp.Items[0])
	return &game, nil
}

// GetGameJSON retrieves detailed information about a single game and returns JSON.
func (c *Client) GetGameJSON(id int) (string, error) {
	game, err := c.GetGame(id)
	if err != nil {
		return "", err
	}

	jsonBytes, err := json.MarshalIndent(game, "", "  ")
	if err != nil {
		return "", newParseError("failed to marshal game to JSON", err)
	}

	return string(jsonBytes), nil
}

// GetGames retrieves detailed information about multiple games (max 20).
func (c *Client) GetGames(ids []int) ([]Game, error) {
	if len(ids) == 0 {
		return []Game{}, nil
	}

	if len(ids) > 20 {
		return nil, newParseError("maximum 20 games can be requested at once", nil)
	}

	// Build comma-separated ID list
	idStrs := make([]string, len(ids))
	for i, id := range ids {
		idStrs[i] = strconv.Itoa(id)
	}

	endpoint := fmt.Sprintf("/thing?id=%s&stats=1", strings.Join(idStrs, ","))

	body, err := c.doRequest(endpoint)
	if err != nil {
		return nil, err
	}

	var xmlResp xmlThing
	if err := xml.Unmarshal(body, &xmlResp); err != nil {
		return nil, newParseError("failed to parse thing response", err)
	}

	games := make([]Game, 0, len(xmlResp.Items))
	for _, item := range xmlResp.Items {
		games = append(games, convertXMLToGame(item))
	}

	return games, nil
}

// convertXMLToGame converts an XML thing item to a Game struct.
func convertXMLToGame(item xmlThingItem) Game {
	game := Game{
		ID:          item.ID,
		Year:        item.YearValue.Value,
		Description: decodeDescription(item.Description),
		Thumbnail:   item.Thumbnail,
		Image:       item.Image,
		MinPlayers:  item.MinPlayers.Value,
		MaxPlayers:  item.MaxPlayers.Value,
		PlayingTime: item.PlayingTime.Value,
		MinPlayTime: item.MinPlayTime.Value,
		MaxPlayTime: item.MaxPlayTime.Value,
		MinAge:      item.MinAge.Value,
	}

	// Get primary name
	for _, name := range item.Names {
		if name.Type == "primary" {
			game.Name = name.Value
			break
		}
	}

	// Extract links by type
	for _, link := range item.Links {
		switch link.Type {
		case "boardgamedesigner":
			game.Designers = append(game.Designers, link.Value)
		case "boardgameartist":
			game.Artists = append(game.Artists, link.Value)
		case "boardgamepublisher":
			game.Publishers = append(game.Publishers, link.Value)
		case "boardgamecategory":
			game.Categories = append(game.Categories, link.Value)
		case "boardgamemechanic":
			game.Mechanics = append(game.Mechanics, link.Value)
		}
	}

	// Extract statistics
	game.Rating = item.Statistics.Ratings.Average.Value
	game.UsersRated = item.Statistics.Ratings.UsersRated.Value
	game.Weight = item.Statistics.Ratings.AverageWeight.Value

	// Extract rank (board game rank)
	for _, rank := range item.Statistics.Ratings.Ranks.Ranks {
		if rank.Name == "boardgame" {
			if rank.Value != "Not Ranked" {
				if r, err := strconv.Atoi(rank.Value); err == nil {
					game.Rank = r
				}
			}
			break
		}
	}

	return game
}

// decodeDescription decodes HTML entities and cleans up the description.
func decodeDescription(desc string) string {
	// Decode HTML entities
	decoded := html.UnescapeString(desc)
	// Replace &#10; with newlines
	decoded = strings.ReplaceAll(decoded, "&#10;", "\n")
	return decoded
}
