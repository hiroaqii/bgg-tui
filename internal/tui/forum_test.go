package tui

import (
	"testing"

	bgg "github.com/hiroaqii/go-bgg"
)

func TestFormatDate(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  string
	}{
		{"RFC 2822 format", "Tue, 10 Feb 2025 14:30:00 +0000", "2025-02-10 14:30"},
		{"RFC 2822 with offset", "Fri, 20 Dec 2024 08:32:00 -0600", "2024-12-20 08:32"},
		{"RFC 3339 format", "2024-12-20T08:32:00-06:00", "2024-12-20 08:32"},
		{"RFC 3339 UTC", "2025-01-15T00:00:00Z", "2025-01-15 00:00"},
		{"empty string", "", ""},
		{"unparseable fallback", "unknown", "unknown"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := formatDate(tt.input)
			if got != tt.want {
				t.Errorf("formatDate(%q) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}

func TestFormatForumColumns(t *testing.T) {
	t.Run("aligns titles and thread counts", func(t *testing.T) {
		forums := []bgg.Forum{
			{Title: "Play By Forum", NumThreads: 2, LastPostDate: "2025-01-15T00:00:00Z"},
			{Title: "News", NumThreads: 11, LastPostDate: "2025-01-15T00:00:00Z"},
			{Title: "Find Players", NumThreads: 6, LastPostDate: "2025-01-15T00:00:00Z"},
		}

		titles, metas := formatForumColumns(forums)

		// All titles should have the same width (padded to "Play By Forum" = 13 chars)
		for i, title := range titles {
			if len(title) != 13 {
				t.Errorf("titles[%d] = %q (len %d), want len 13", i, title, len(title))
			}
		}

		// Thread counts should be right-aligned (2 digits)
		if metas[0] != " 2 threads · 2025-01-15 00:00" {
			t.Errorf("metas[0] = %q, want %q", metas[0], " 2 threads · 2025-01-15 00:00")
		}
		if metas[1] != "11 threads · 2025-01-15 00:00" {
			t.Errorf("metas[1] = %q, want %q", metas[1], "11 threads · 2025-01-15 00:00")
		}
	})

	t.Run("single forum", func(t *testing.T) {
		forums := []bgg.Forum{
			{Title: "General", NumThreads: 5, LastPostDate: "2025-01-15T00:00:00Z"},
		}

		titles, metas := formatForumColumns(forums)

		if len(titles) != 1 || titles[0] != "General" {
			t.Errorf("titles = %v, want [\"General\"]", titles)
		}
		if len(metas) != 1 || metas[0] != "5 threads · 2025-01-15 00:00" {
			t.Errorf("metas = %v, want [\"5 threads · 2025-01-15 00:00\"]", metas)
		}
	})

	t.Run("empty slice", func(t *testing.T) {
		titles, metas := formatForumColumns(nil)

		if titles != nil || metas != nil {
			t.Errorf("expected nil slices, got titles=%v, metas=%v", titles, metas)
		}
	})
}
