package bgg

import (
	"fmt"
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

	xmlResp, err := parseXML[xmlThing](body, "failed to parse thing response")
	if err != nil {
		return nil, err
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
	return toJSON(game)
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

	xmlResp, err := parseXML[xmlThing](body, "failed to parse thing response")
	if err != nil {
		return nil, err
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
		Description: decodeHTML(item.Description),
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
	game.BayesAverage = item.Statistics.Ratings.BayesAverage.Value
	game.Weight = item.Statistics.Ratings.AverageWeight.Value
	game.StdDev = item.Statistics.Ratings.StdDev.Value
	game.Median = item.Statistics.Ratings.Median.Value
	game.Owned = item.Statistics.Ratings.Owned.Value
	game.NumComments = item.Statistics.Ratings.NumComments.Value
	game.NumWeights = item.Statistics.Ratings.NumWeights.Value

	// Extract rank (board game rank)
	game.Rank = extractBoardGameRank(item.Statistics.Ratings.Ranks.Ranks)

	// Extract suggested_numplayers poll
	for _, poll := range item.Polls {
		if poll.Name != "suggested_numplayers" {
			continue
		}
		pcp := &PlayerCountPoll{TotalVotes: poll.TotalVotes}
		for _, pr := range poll.Results {
			var v PlayerCountVotes
			v.NumPlayers = pr.NumPlayers
			for _, r := range pr.Results {
				switch r.Value {
				case "Best":
					v.Best = r.NumVotes
				case "Recommended":
					v.Recommended = r.NumVotes
				case "Not Recommended":
					v.NotRecommended = r.NumVotes
				}
			}
			pcp.Results = append(pcp.Results, v)
		}
		// Extract poll-summary data
		for _, ps := range item.PollSummaries {
			if ps.Name != "suggested_numplayers" {
				continue
			}
			for _, r := range ps.Results {
				switch r.Name {
				case "bestwith":
					pcp.BestWith = r.Value
				case "recommmendedwith":
					pcp.RecWith = r.Value
				}
			}
		}
		game.PlayerCountPoll = pcp
		break
	}

	return game
}
