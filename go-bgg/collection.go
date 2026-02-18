package bgg

import (
	"fmt"
	"net/url"
	"strconv"
)

const (
	// Collection API max retries for 202 responses
	collectionMaxRetries = 10
)

// GetCollection retrieves a user's game collection.
func (c *Client) GetCollection(username string, opts CollectionOptions) ([]CollectionItem, error) {
	if username == "" {
		return nil, newParseError("username is required", nil)
	}

	endpoint := fmt.Sprintf("/collection?username=%s&stats=1", url.QueryEscape(username))
	if opts.OwnedOnly {
		endpoint += "&own=1"
	}

	body, err := c.doRequestWithRetryOn202(endpoint, collectionMaxRetries)
	if err != nil {
		return nil, err
	}

	xmlResp, err := parseXML[xmlCollection](body, "failed to parse collection response")
	if err != nil {
		return nil, err
	}

	items := make([]CollectionItem, 0, len(xmlResp.Items))
	for _, item := range xmlResp.Items {
		items = append(items, convertXMLToCollectionItem(item))
	}

	return items, nil
}

// GetCollectionJSON retrieves a user's game collection and returns JSON.
func (c *Client) GetCollectionJSON(username string, opts CollectionOptions) (string, error) {
	items, err := c.GetCollection(username, opts)
	if err != nil {
		return "", err
	}
	return toJSON(items)
}

// convertXMLToCollectionItem converts an XML collection item to a CollectionItem struct.
func convertXMLToCollectionItem(item xmlCollectionItem) CollectionItem {
	ci := CollectionItem{
		ID:        item.ObjectID,
		Name:      item.Name.Value,
		Year:      item.YearValue,
		Thumbnail: item.Thumbnail,
		Image:     item.Image,
		NumPlays:  item.NumPlays,
		Owned:     item.Status.Own == "1",
		WantToPlay: item.Status.WantToPlay == "1",
		Wishlist:  item.Status.Wishlist == "1",
	}

	// Parse user rating
	if item.Stats.Rating.Value != "N/A" && item.Stats.Rating.Value != "" {
		if r, err := strconv.ParseFloat(item.Stats.Rating.Value, 64); err == nil {
			ci.Rating = r
		}
	}

	// BGG average rating
	ci.BGGRating = item.Stats.Rating.Average.Value
	ci.BayesAverage = item.Stats.Rating.BayesAverage.Value

	// Extract rank (board game rank)
	for _, rank := range item.Stats.Rating.Ranks.Ranks {
		if rank.Name == "boardgame" {
			if rank.Value != "Not Ranked" {
				if r, err := strconv.Atoi(rank.Value); err == nil {
					ci.Rank = r
				}
			}
			break
		}
	}

	return ci
}
