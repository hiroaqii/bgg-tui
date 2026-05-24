# bgg-tui

A terminal user interface for [BoardGameGeek](https://boardgamegeek.com/).

This branch is the Zig port of the original Go implementation. The port keeps
the existing feature set as the target, but the internal module layout is being
rebuilt around Zig and Chasen conventions.

> **Note:** This app uses the BGG API. The BGG API currently requires
> registration to use. You must register and obtain a bearer token at
> <https://boardgamegeek.com/applications> before using this app.

## Features

- 🔥 Browse trending (Hot) games with ratings, weight, and rank
- 🔍 Search games by name
- 📚 View user collections with status filter and ratings
- 📋 Game details: year, rating, geek rating, rank, players, play time, weight, age, owned, comments, designers, artists, categories, mechanics, description
- 💬 Browse game forums and read threads
- 🖼️ Thumbnail images via Kitty graphics protocol (currently Ghostty only — see [#10](https://github.com/hiroaqii/bgg-tui/issues/10), [#11](https://github.com/hiroaqii/bgg-tui/issues/11))
- 🔎 Filter-as-you-type on any list
- 🎨 Multiple color themes
- ✨ Screen transition effects
- 🎯 Selection animations
- 🔲 Multiple border styles
- ⚙️ Configurable list density, date format, list/thread/detail width
- 🌐 Open any game in browser

Current image support is intentionally limited. Local PNG covers can be sent to
the terminal image runtime; JPEG/WebP covers are detected before download and
shown as unsupported until the Chasen graphics image pipeline can decode them.

## Requirements

- Zig 0.16.0+
- BGG API bearer token. You must register for API access on BoardGameGeek and
  generate a token at <https://boardgamegeek.com/applications>.
- Terminal with Kitty graphics protocol support for images.

## Installation

### Build from source

```bash
git clone https://github.com/hiroaqii/bgg-tui.git
cd bgg-tui
zig build
```

Run the app:

```bash
zig build run
```

Run tests:

```bash
zig build test
```

Run the manual live API check with the configured token:

```bash
zig build check-live-api
```

## Getting Started

bgg-tui requires a BGG API bearer token. You need to register for API access on BoardGameGeek before using the app.

1. Go to <https://boardgamegeek.com/applications> and register for API access
2. Create an application and generate a bearer token
3. Launch bgg-tui — on first launch, a token setup screen will appear
4. Paste the token into the input field and press `Enter`

You can change the token later from the Settings screen.

For local development and manual checks, the app can also read the token from
`BGG_TUI_API_TOKEN`. `BGG_API_TOKEN` is accepted as a fallback.

## Configuration

Configuration file is created on first launch in your OS's default config
directory (`bgg-tui/config.toml`). You can check the exact path in the Settings
screen. Settings can also be changed from the Settings screen within the app.

During development, `BGG_TUI_CONFIG_PATH` can be used to point the app at a
specific config file path.

| Section | Key | Description |
|---------|-----|-------------|
| `interface` | `color_theme` | Color theme: `default`, `blue`, `orange`, `mono`, `matcha` |
| `interface` | `transition` | Screen transition effect such as `none`, `fade`, `sweep`, `glitch`, `random` |
| `interface` | `selection` | List selection animation: `none`, `invert`, `wave`, `blink`, `glitch`, `scan` |
| `interface` | `border_style` | Border style for panels: `none`, `rounded`, `thick`, `double`, `block`, `dots` |
| `interface` | `list_density` | List item spacing: `compact`, `normal`, `comfortable`, `relaxed` |
| `interface` | `date_format` | Date display format: `yyyy-mm-dd`, `yyyy/mm/dd`, `relative`, `YYYY-MM-DD` |
| `display` | `show_images` | Show board game thumbnail images |
| `display` | `image_protocol` | Image protocol: `auto` detects terminal support, `kitty` forces Kitty protocol, `off` disables |
| `display` | `list_width` | List screen content width |
| `display` | `thread_width` | Forum thread display width |
| `display` | `detail_width` | Game detail display width |
| `collection` | `default_username` | Default BGG username for collection lookup |
| `collection` | `status_filter` | Filter by collection status: owned, prev_owned, for_trade, want, want_to_play, want_to_buy, wishlist, preordered |
| `api` | `token` | BGG API bearer token |

If the config file is broken, bgg-tui backs it up to `{path}.broken`, recovers
defaults, and keeps the API token when it can be safely extracted.

## Special Thanks

- [Charm](https://charm.sh/) for the amazing TUI toolkit — [Bubble Tea](https://github.com/charmbracelet/bubbletea), [Bubbles](https://github.com/charmbracelet/bubbles), and [Lip Gloss](https://github.com/charmbracelet/lipgloss)
- [BoardGameGeek](https://boardgamegeek.com/) for providing the [XML API 2](https://boardgamegeek.com/wiki/page/BGG_XML_API2)

## License

MIT
