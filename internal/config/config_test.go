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

	if cfg.Collection.ShowOnlyOwned {
		t.Error("expected ShowOnlyOwned to be false by default")
	}

	if cfg.Interface.ColorTheme != "default" {
		t.Errorf("expected ColorTheme 'default', got '%s'", cfg.Interface.ColorTheme)
	}

	if cfg.Interface.Transition != "fade" {
		t.Errorf("expected Transition 'fade', got '%s'", cfg.Interface.Transition)
	}

	if cfg.Interface.Selection != "wave" {
		t.Errorf("expected Selection 'wave', got '%s'", cfg.Interface.Selection)
	}

	if cfg.Interface.ListDensity != "normal" {
		t.Errorf("expected ListDensity 'normal', got '%s'", cfg.Interface.ListDensity)
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
