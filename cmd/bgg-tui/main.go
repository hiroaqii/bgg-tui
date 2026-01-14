package main

import (
	"fmt"
	"os"

	"github.com/hiroaqii/bgg-tui/internal/config"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error loading config: %v\n", err)
		os.Exit(1)
	}

	if !cfg.HasToken() {
		fmt.Println("BGG TUI - Setup Required")
		fmt.Println()
		fmt.Println("No API token configured.")
		fmt.Println("Please add your BGG API token to the config file.")
		path, _ := config.ConfigPath()
		fmt.Printf("Config path: %s\n", path)
		os.Exit(0)
	}

	fmt.Println("BGG TUI")
	fmt.Println("Token configured. Ready to start.")
}
