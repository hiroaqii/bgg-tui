package config

import (
	"os"
	"path/filepath"

	"github.com/BurntSushi/toml"
)

// Config represents the application configuration.
type Config struct {
	API        APIConfig        `toml:"api"`
	Display    DisplayConfig    `toml:"display"`
	Collection CollectionConfig `toml:"collection"`
	Interface  InterfaceConfig  `toml:"interface"`
}

// APIConfig contains API-related configuration.
type APIConfig struct {
	Token string `toml:"token"`
}

// DisplayConfig contains display-related configuration.
type DisplayConfig struct {
	ShowImages        bool   `toml:"show_images"`
	ImageProtocol     string `toml:"image_protocol"` // "auto", "kitty", "off"
	ThreadWidth      int `toml:"thread_width"`
	DescriptionWidth int `toml:"description_width"`
}

// CollectionConfig contains collection-related configuration.
type CollectionConfig struct {
	DefaultUsername string `toml:"default_username"`
	ShowOnlyOwned   bool   `toml:"show_only_owned"`
}

// InterfaceConfig contains interface-related configuration.
type InterfaceConfig struct {
	ColorTheme  string `toml:"color_theme"`  // "default", "blue", "orange", "green"
	Transition  string `toml:"transition"`   // "none", "fade", "glitch", "dissolve", "sweep", "lines", "lines-cross", "random"
	Selection   string `toml:"selection"`    // "none", "wave", "blink", "glitch"
	ListDensity string `toml:"list_density"` // "compact", "normal", "relaxed"
	DateFormat   string `toml:"date_format"`   // "YYYY-MM-DD", "MM/DD/YYYY", "DD/MM/YYYY"
	BorderStyle  string `toml:"border_style"`  // "none", "rounded", "thick", "double", "block"
}

// DefaultConfig returns the default configuration.
func DefaultConfig() *Config {
	return &Config{
		API: APIConfig{
			Token: "",
		},
		Display: DisplayConfig{
			ShowImages:        true,
			ImageProtocol:     "auto",
			ThreadWidth:      80,
			DescriptionWidth: 100,
		},
		Collection: CollectionConfig{
			DefaultUsername: "",
			ShowOnlyOwned:   false,
		},
		Interface: InterfaceConfig{
			ColorTheme:  "default",
			Transition:  "fade",
			Selection:   "wave",
			ListDensity: "normal",
			DateFormat:  "YYYY-MM-DD",
			BorderStyle: "rounded",
		},
	}
}

// ConfigPath returns the path to the configuration file.
func ConfigPath() (string, error) {
	configDir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(configDir, "bgg-tui", "config.toml"), nil
}

// Load loads the configuration from the default path.
func Load() (*Config, error) {
	path, err := ConfigPath()
	if err != nil {
		return nil, err
	}
	return LoadFromPath(path)
}

// LoadFromPath loads the configuration from the specified path.
func LoadFromPath(path string) (*Config, error) {
	cfg := DefaultConfig()

	if _, err := os.Stat(path); os.IsNotExist(err) {
		return cfg, nil
	}

	if _, err := toml.DecodeFile(path, cfg); err != nil {
		return nil, err
	}

	return cfg, nil
}

// Save saves the configuration to the default path.
func (c *Config) Save() error {
	path, err := ConfigPath()
	if err != nil {
		return err
	}
	return c.SaveToPath(path)
}

// SaveToPath saves the configuration to the specified path.
func (c *Config) SaveToPath(path string) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}

	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()

	encoder := toml.NewEncoder(f)
	return encoder.Encode(c)
}

// HasToken returns true if a token is configured.
func (c *Config) HasToken() bool {
	return c.API.Token != ""
}
