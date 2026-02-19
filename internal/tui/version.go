package tui

import "runtime/debug"

var Version = "dev"

func init() {
	if Version != "dev" {
		return
	}
	info, ok := debug.ReadBuildInfo()
	if !ok {
		return
	}
	var hash string
	var dirty bool
	for _, s := range info.Settings {
		if s.Key == "vcs.revision" && len(s.Value) >= 7 {
			hash = s.Value[:7]
		}
		if s.Key == "vcs.modified" && s.Value == "true" {
			dirty = true
		}
	}
	if hash != "" {
		if dirty {
			hash += "-dirty"
		}
		Version = "dev (" + hash + ")"
	}
}
