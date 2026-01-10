package bgg

import (
	"encoding/json"
	"encoding/xml"
	"fmt"
	"html"
)

// GetForums retrieves the list of forums for a game.
func (c *Client) GetForums(gameID int) ([]Forum, error) {
	if gameID <= 0 {
		return nil, newParseError("game ID must be positive", nil)
	}

	endpoint := fmt.Sprintf("/forumlist?type=thing&id=%d", gameID)
	body, err := c.doRequest(endpoint)
	if err != nil {
		return nil, err
	}

	var xmlResp xmlForumList
	if err := xml.Unmarshal(body, &xmlResp); err != nil {
		return nil, newParseError("failed to parse forums response", err)
	}

	forums := make([]Forum, 0, len(xmlResp.Forums))
	for _, f := range xmlResp.Forums {
		forums = append(forums, Forum{
			ID:           f.ID,
			Title:        f.Title,
			Description:  f.Description,
			NumThreads:   f.NumThreads,
			NumPosts:     f.NumPosts,
			LastPostDate: f.LastPostDate,
		})
	}

	return forums, nil
}

// GetForumsJSON retrieves the list of forums for a game and returns JSON.
func (c *Client) GetForumsJSON(gameID int) (string, error) {
	forums, err := c.GetForums(gameID)
	if err != nil {
		return "", err
	}

	jsonBytes, err := json.MarshalIndent(forums, "", "  ")
	if err != nil {
		return "", newParseError("failed to marshal forums to JSON", err)
	}

	return string(jsonBytes), nil
}

// GetForumThreads retrieves threads in a forum.
// Page is 1-indexed. Each page returns up to 50 threads.
func (c *Client) GetForumThreads(forumID int, page int) (*ThreadList, error) {
	if forumID <= 0 {
		return nil, newParseError("forum ID must be positive", nil)
	}
	if page <= 0 {
		page = 1
	}

	endpoint := fmt.Sprintf("/forum?id=%d&page=%d", forumID, page)
	body, err := c.doRequest(endpoint)
	if err != nil {
		return nil, err
	}

	var xmlResp xmlForumPage
	if err := xml.Unmarshal(body, &xmlResp); err != nil {
		return nil, newParseError("failed to parse forum threads response", err)
	}

	threads := make([]ThreadSummary, 0, len(xmlResp.Threads.Threads))
	for _, t := range xmlResp.Threads.Threads {
		threads = append(threads, ThreadSummary{
			ID:           t.ID,
			Subject:      t.Subject,
			Author:       t.Author,
			NumArticles:  t.NumArticles,
			PostDate:     t.PostDate,
			LastPostDate: t.LastPostDate,
		})
	}

	// Calculate total pages (50 threads per page)
	threadsPerPage := 50
	totalPages := (xmlResp.NumThreads + threadsPerPage - 1) / threadsPerPage
	if totalPages == 0 {
		totalPages = 1
	}

	return &ThreadList{
		Threads:    threads,
		Page:       page,
		TotalPages: totalPages,
	}, nil
}

// GetForumThreadsJSON retrieves threads in a forum and returns JSON.
func (c *Client) GetForumThreadsJSON(forumID int, page int) (string, error) {
	threadList, err := c.GetForumThreads(forumID, page)
	if err != nil {
		return "", err
	}

	jsonBytes, err := json.MarshalIndent(threadList, "", "  ")
	if err != nil {
		return "", newParseError("failed to marshal thread list to JSON", err)
	}

	return string(jsonBytes), nil
}

// GetThread retrieves a thread with its articles.
func (c *Client) GetThread(threadID int) (*Thread, error) {
	if threadID <= 0 {
		return nil, newParseError("thread ID must be positive", nil)
	}

	endpoint := fmt.Sprintf("/thread?id=%d", threadID)
	body, err := c.doRequest(endpoint)
	if err != nil {
		return nil, err
	}

	var xmlResp xmlThread
	if err := xml.Unmarshal(body, &xmlResp); err != nil {
		return nil, newParseError("failed to parse thread response", err)
	}

	articles := make([]Article, 0, len(xmlResp.Articles))
	for _, a := range xmlResp.Articles {
		articles = append(articles, Article{
			ID:       a.ID,
			Username: a.Username,
			PostDate: a.PostDate,
			Body:     html.UnescapeString(a.Body),
		})
	}

	return &Thread{
		ID:       xmlResp.ID,
		Subject:  xmlResp.Subject,
		Articles: articles,
	}, nil
}

// GetThreadJSON retrieves a thread with its articles and returns JSON.
func (c *Client) GetThreadJSON(threadID int) (string, error) {
	thread, err := c.GetThread(threadID)
	if err != nil {
		return "", err
	}

	jsonBytes, err := json.MarshalIndent(thread, "", "  ")
	if err != nil {
		return "", newParseError("failed to marshal thread to JSON", err)
	}

	return string(jsonBytes), nil
}
