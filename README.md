# 🎁 Fediverse Year Wrapped

Generate beautiful, Spotify Wrapped-style year-in-review reports for your Fediverse account with AI-powered personality insights.

Works with **any Mastodon-compatible server**: Mastodon, GoToSocial, Pleroma, Misskey, Akkoma, etc.

![Year Wrapped Preview](https://img.shields.io/badge/Fediverse-Wrapped-8b5cf6?style=for-the-badge)

## ✨ Features

- **📊 Comprehensive Statistics**
  - Total posts, original content, boosts, and replies
  - Social Impact Score with ranking tier
  - Longest posting streak
  - Activity heatmap calendar
  - Monthly, hourly, and weekly distribution charts

- **🧠 AI-Powered Insights** (via Ollama, optional)
  - Emotional journey analysis
  - Personality trait detection
  - Writing style characterization
  - Interest and passion topic identification
  - Personalized year narrative
  - *Gracefully skipped if Ollama is unreachable*

- **🎨 Beautiful Reports**
  - Dark theme with year-specific accent colors
  - Responsive design for all devices
  - Standalone HTML files (no server required)
  - Top posts by engagement
  - Local avatar download

- **🔐 Privacy-First**
  - Uses authenticated `toot` CLI (your data stays local)
  - All processing happens on your machine
  - No external services except optional AI analysis

## 📋 Prerequisites

1. **toot CLI** - Mastodon command-line client
   ```bash
   # Install via Homebrew (macOS)
   brew install toot
   
   # Or via pip
   pip install toot
   ```

2. **jq** - JSON processor
   ```bash
   # macOS
   brew install jq
   
   # Ubuntu/Debian
   sudo apt install jq
   ```

3. **curl** & **bc** - Usually pre-installed on macOS/Linux

4. **Authenticated toot session**
   ```bash
   toot login    # Login to your instance
   toot auth     # Verify authentication
   ```

5. **Ollama** (optional, for AI insights)
   - Any Ollama server with a language model
   - Recommended models: `phi4:14b`, `llama3.1:latest`
   - If unavailable, AI section is simply omitted

## 🚀 Quick Start

### 1. Configure (Optional)

Edit `.env` if you want to customize settings:
```bash
# Default year (can be overridden via command line)
DEFAULT_YEAR=2025

# Ollama AI Configuration (optional)
OLLAMA_BASE_URL="http://localhost:11434"
OLLAMA_MODEL="phi4:14b"
```

**Note:** Account is auto-detected from your active `toot` session!

### 2. Run

```bash
# Generate wrapped report for current year
./wrapped.sh

# Generate for a specific year
./wrapped.sh 2024

# For a different account (overrides active toot session)
./wrapped.sh 2024 user@instance.social

# Skip AI analysis (faster)
./wrapped.sh 2024 --skip-ai

# Only fetch data, don't generate report
./wrapped.sh 2024 --fetch-only

# Use existing data, don't re-fetch
./wrapped.sh 2024 --no-fetch
```

### 3. View

```bash
open wrapped_2024_user_instance.social.html
```

## 📁 Project Structure

```
fediverse-wrapped/
├── wrapped.sh             # Main script (fetch + generate)
├── template.html          # HTML template with placeholders
├── .env                   # Configuration file
├── avatars/               # Downloaded profile pictures
├── index.html             # Landing page linking all reports
├── statuses_YEAR_*.json   # Fetched post data (generated)
├── wrapped_YEAR_*.html    # Generated reports
└── README.md
```

## ⚙️ Configuration

All settings are in `.env`:

```bash
# Default year (can be overridden via command line)
DEFAULT_YEAR=2025

# Ollama AI Configuration (optional - skipped if unreachable)
OLLAMA_BASE_URL="http://localhost:11434"
OLLAMA_MODEL="phi4:14b"
OLLAMA_MAX_TOKENS=2500
OLLAMA_TEMPERATURE=0.7

# Number of posts to sample for AI analysis
AI_SAMPLE_SIZE=50
```

### Customizing Year Theme Colors

Edit the `get_year_colors()` function in `wrapped.sh`:
```bash
get_year_colors() {
    case "$1" in
        2022) echo "#ec4899|#db2777" ;;  # Pink
        2023) echo "#14b8a6|#0d9488" ;;  # Teal
        2024) echo "#f59e0b|#d97706" ;;  # Amber
        2025) echo "#8b5cf6|#6366f1" ;;  # Purple
        *)    echo "#8b5cf6|#6366f1" ;;  # Default
    esac
}
```

## 🛠️ Usage

```bash
./wrapped.sh [YEAR] [ACCOUNT] [OPTIONS]
```

| Argument | Description |
|----------|-------------|
| `YEAR` | Year to generate report for (default: from .env) |
| `ACCOUNT` | Full handle like `user@instance` (default: active toot session) |
| `--skip-ai` | Skip AI analysis (faster) |
| `--fetch-only` | Only fetch statuses, don't generate report |
| `--no-fetch` | Skip fetching, use existing data file |

**Examples:**
```bash
./wrapped.sh                       # Current year, active account
./wrapped.sh 2024                  # Specific year
./wrapped.sh 2024 me@mastodon.social  # Different account
./wrapped.sh 2024 --skip-ai        # Without AI (faster)
./wrapped.sh 2024 --fetch-only     # Just download data
./wrapped.sh 2024 --no-fetch       # Regenerate from cached data
```

## 📊 Report Sections

### Social Impact Score
Calculated as: `(reblogs × 2) + favorites + (posts × 0.1) + (streak × 5)`

| Score | Tier |
|-------|------|
| ≥10,000 | 👑 Top 1% |
| ≥5,000 | 🥈 Top 5% |
| ≥1,000 | 🥉 Top 15% |
| ≥500 | ⭐ Top 30% |
| ≥100 | ✨ Top 50% |
| <100 | 🌱 Growing |

### Persona Classification
- **📢 The Broadcaster** - >60% original content
- **🎯 The Curator** - >60% boosts
- **💬 The Socialite** - >50% replies
- **⚖️ The Balancer** - Mixed posting style

### Chronotype Analysis
- **🦉 Night Owl** - >15% posts between 0-5am
- **🐦 Early Bird** - >30% posts between 5-10am
- **😏 Slacker** - >60% posts during work hours
- **☀️ The Regular** - Balanced schedule

## 📝 Generate All Years

```bash
for year in 2022 2023 2024 2025; do
  ./wrapped.sh $year
done

open index.html
```

## 🔧 Troubleshooting

### "No account specified and no active toot session"
```bash
toot login       # Login to your instance
toot auth        # Verify authentication shows ACTIVE
```

### "No statuses found for YEAR"
- Ensure you have posts for that year
- Verify authentication: `toot auth`

### AI section not appearing
- This is normal if Ollama is unreachable
- Check if Ollama server is running: `curl http://localhost:11434/api/tags`
- Verify `OLLAMA_BASE_URL` in `.env`

### "jq: command not found"
```bash
brew install jq  # macOS
apt install jq   # Linux
```

### "bc: command not found"
```bash
brew install bc  # macOS
apt install bc   # Linux
```

## 🤝 Credits

- Inspired by [Mastodon Wrapped](https://github.com/Eyozy/mastodon-wrapped)
- Built for the Fediverse
- AI analysis powered by [Ollama](https://ollama.ai/)
- CLI access via [toot](https://github.com/ihabunek/toot)

## 📄 License

MIT License - Feel free to modify and share!

---

Made with 💜 for the Fediverse
