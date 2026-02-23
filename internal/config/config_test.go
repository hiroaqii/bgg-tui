package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDefaultConfig(t *testing.T) {
	cfg := DefaultConfig()

	if cfg.API.Token != "" {
		t.Error("expected empty token")
	}

	if !cfg.Display.ShowImages {
		t.Error("expected ShowImages to be true by default")
	}

	if cfg.Display.ImageProtocol != "auto" {
		t.Errorf("expected ImageProtocol 'auto', got '%s'", cfg.Display.ImageProtocol)
	}

	if cfg.Collection.DefaultUsername != "" {
		t.Error("expected empty DefaultUsername")
	}

	if len(cfg.Collection.StatusFilter) != 0 {
		t.Error("expected StatusFilter to be nil by default")
	}

	if cfg.Interface.ColorTheme != "default" {
		t.Errorf("expected ColorTheme 'default', got '%s'", cfg.Interface.ColorTheme)
	}

	if cfg.Interface.Transition != "random" {
		t.Errorf("expected Transition 'random', got '%s'", cfg.Interface.Transition)
	}

	if cfg.Interface.Selection != "wave" {
		t.Errorf("expected Selection 'wave', got '%s'", cfg.Interface.Selection)
	}

	if cfg.Interface.ListDensity != "normal" {
		t.Errorf("expected ListDensity 'normal', got '%s'", cfg.Interface.ListDensity)
	}

	if cfg.Interface.DateFormat != "YYYY-MM-DD" {
		t.Errorf("expected DateFormat 'YYYY-MM-DD', got '%s'", cfg.Interface.DateFormat)
	}
}

func TestLoadFromPath_NonExistent(t *testing.T) {
	cfg, err := LoadFromPath("/nonexistent/path/config.toml")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Should return default config
	if cfg.Display.ImageProtocol != "auto" {
		t.Errorf("expected default ImageProtocol 'auto', got '%s'", cfg.Display.ImageProtocol)
	}
}

func TestSaveAndLoad(t *testing.T) {
	tmpDir := t.TempDir()
	path := filepath.Join(tmpDir, "config.toml")

	cfg := DefaultConfig()
	cfg.API.Token = "test-token-123"
	cfg.Display.ShowImages = false
	cfg.Collection.DefaultUsername = "testuser"
	if err := cfg.SaveToPath(path); err != nil {
		t.Fatalf("failed to save config: %v", err)
	}

	// Verify file was created
	if _, err := os.Stat(path); os.IsNotExist(err) {
		t.Fatal("config file was not created")
	}

	// Load and verify
	loaded, err := LoadFromPath(path)
	if err != nil {
		t.Fatalf("failed to load config: %v", err)
	}

	if loaded.API.Token != "test-token-123" {
		t.Errorf("expected token 'test-token-123', got '%s'", loaded.API.Token)
	}

	if loaded.Display.ShowImages {
		t.Error("expected ShowImages to be false")
	}

	if loaded.Collection.DefaultUsername != "testuser" {
		t.Errorf("expected DefaultUsername 'testuser', got '%s'", loaded.Collection.DefaultUsername)
	}
}

func TestHasToken(t *testing.T) {
	cfg := DefaultConfig()

	if cfg.HasToken() {
		t.Error("expected HasToken to be false for empty token")
	}

	cfg.API.Token = "some-token"
	if !cfg.HasToken() {
		t.Error("expected HasToken to be true for non-empty token")
	}
}

func TestLoadFromPath_BrokenConfig(t *testing.T) {
	tmpDir := t.TempDir()
	path := filepath.Join(tmpDir, "config.toml")

	// 壊れた TOML を書き込む
	brokenTOML := []byte("[api\ntoken = broken\n")
	if err := os.WriteFile(path, brokenTOML, 0644); err != nil {
		t.Fatalf("failed to write broken config: %v", err)
	}

	cfg, err := LoadFromPath(path)
	if err != nil {
		t.Fatalf("expected no error for broken config, got: %v", err)
	}

	// デフォルト設定が返ること
	if cfg.Display.ImageProtocol != "auto" {
		t.Errorf("expected default ImageProtocol 'auto', got '%s'", cfg.Display.ImageProtocol)
	}
	if cfg.Interface.ColorTheme != "default" {
		t.Errorf("expected default ColorTheme 'default', got '%s'", cfg.Interface.ColorTheme)
	}

	// .bak ファイルが作成されること
	bakPath := path + ".bak"
	if _, err := os.Stat(bakPath); os.IsNotExist(err) {
		t.Error("expected .bak file to be created")
	}

	// 元のファイルがリネームされていること
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Error("expected original config file to be renamed")
	}
}

func TestLoadFromPath_BrokenConfigWithToken(t *testing.T) {
	tmpDir := t.TempDir()
	path := filepath.Join(tmpDir, "config.toml")

	// token を含む壊れた TOML
	brokenTOML := []byte("[api]\ntoken = \"my-secret-token\"\n\n[display\ninvalid line\n")
	if err := os.WriteFile(path, brokenTOML, 0644); err != nil {
		t.Fatalf("failed to write broken config: %v", err)
	}

	cfg, err := LoadFromPath(path)
	if err != nil {
		t.Fatalf("expected no error for broken config, got: %v", err)
	}

	// token が復旧されること
	if cfg.API.Token != "my-secret-token" {
		t.Errorf("expected token 'my-secret-token', got '%s'", cfg.API.Token)
	}

	// その他はデフォルト
	if cfg.Display.ImageProtocol != "auto" {
		t.Errorf("expected default ImageProtocol 'auto', got '%s'", cfg.Display.ImageProtocol)
	}
}

func TestExtractToken(t *testing.T) {
	tests := []struct {
		name     string
		raw      string
		expected string
	}{
		{
			name:     "valid token line",
			raw:      "[api]\ntoken = \"abc123\"\n",
			expected: "abc123",
		},
		{
			name:     "token with spaces",
			raw:      "  token = \"spaced-token\"  \n",
			expected: "spaced-token",
		},
		{
			name:     "no token",
			raw:      "[api]\nother = \"value\"\n",
			expected: "",
		},
		{
			name:     "completely broken",
			raw:      "!!!garbage data!!!",
			expected: "",
		},
		{
			name:     "empty input",
			raw:      "",
			expected: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := extractToken([]byte(tt.raw))
			if got != tt.expected {
				t.Errorf("extractToken() = %q, want %q", got, tt.expected)
			}
		})
	}
}

func TestLoadFromPath_MigrateShowOnlyOwned(t *testing.T) {
	tmpDir := t.TempDir()
	path := filepath.Join(tmpDir, "config.toml")

	oldConfig := []byte("[collection]\nshow_only_owned = true\ndefault_username = \"testuser\"\n")
	if err := os.WriteFile(path, oldConfig, 0644); err != nil {
		t.Fatalf("failed to write config: %v", err)
	}

	cfg, err := LoadFromPath(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if cfg.Collection.ShowOnlyOwned {
		t.Error("expected ShowOnlyOwned to be cleared after migration")
	}
	if len(cfg.Collection.StatusFilter) != 1 || cfg.Collection.StatusFilter[0] != "owned" {
		t.Errorf("expected StatusFilter [owned], got %v", cfg.Collection.StatusFilter)
	}
}

func TestSaveCreatesDirectory(t *testing.T) {
	tmpDir := t.TempDir()
	path := filepath.Join(tmpDir, "nested", "dir", "config.toml")

	cfg := DefaultConfig()
	if err := cfg.SaveToPath(path); err != nil {
		t.Fatalf("failed to save config: %v", err)
	}

	if _, err := os.Stat(path); os.IsNotExist(err) {
		t.Fatal("config file was not created in nested directory")
	}
}
