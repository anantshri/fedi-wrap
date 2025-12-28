# 🎁 GoToSocial Year Wrapped

Generate beautiful, Spotify Wrapped-style year-in-review reports for your GoToSocial/Mastodon account with AI-powered personality insights.

![Year Wrapped Preview](https://img.shields.io/badge/Fediverse-Wrapped-8b5cf6?style=for-the-badge)

## ✨ Features

- **📊 Comprehensive Statistics**
  - Total posts, original content, boosts, and replies
  - Social Impact Score with ranking tier
  - Longest posting streak
  - Activity heatmap calendar
  - Monthly, hourly, and weekly distribution charts

- **🧠 AI-Powered Insights** (via Ollama)
  - Emotional journey analysis
  - Personality trait detection
  - Writing style characterization
  - Interest and passion topic identification
  - Personalized year narrative

- **🎨 Beautiful Reports**
  - Dark theme with year-specific accent colors
  - Responsive design for all devices
  - Standalone HTML files (no server required)
  - Top posts by engagement

- **🔐 Privacy-First**
  - Uses authenticated `toot` CLI (your data stays local)
  - All processing happens on your machine
  - No external services except optional AI analysis

## 📋 Prerequisites

### Required

1. **toot CLI** - Mastodon/GoToSocial command-line client
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

3. **curl** - HTTP client (usually pre-installed)
   ```bash
   curl --version
   ```

4. **bc** - Calculator (usually pre-installed)
   ```bash
   bc --version
   ```

5. **Authenticated toot session**
   ```bash
   # Login to your instance
   toot login
   
   # Verify authentication
   toot auth
   ```

### Optional (for AI Insights)

6. **Ollama** server with a language model
   - Default endpoint: `http://100.72.252.38:8080`
   - Recommended models: `phi4:14b`, `llama3.1:latest`, `deepseek-r1:32b`

## 🚀 Quick Start

### 1. Clone or Navigate to the Project

```bash
cd /path/to/wrapped-gotosocial
```

### 2. Fetch Your Posts

```bash
# Fetch posts for a specific year
./fetch_statuses.sh 2024

# Or use the default (current year)
./fetch_statuses.sh
```

This creates `statuses_YEAR.json` with all your posts for that year.

### 3. Generate the Wrapped Report

```bash
# Generate report with AI analysis
./generate_wrapped.sh 2024

# Generate without AI (faster)
./generate_wrapped.sh 2024 --skip-ai
```

### 4. View Your Report

```bash
# Open in browser (macOS)
open wrapped_2024_anant.html

# Or on Linux
xdg-open wrapped_2024_anant.html
```

## 📁 Project Structure

```
wrapped-gotosocial/
├── fetch_statuses.sh      # Fetches posts from GoToSocial via toot CLI
├── generate_wrapped.sh    # Analyzes data and generates HTML report (pure shell)
├── index.html             # Landing page linking all year reports
├── statuses_YEAR.json     # Raw post data (generated)
├── wrapped_YEAR_USER.html # Generated wrapped reports
└── README.md              # This file
```

## 🛠️ Usage

### Fetch Statuses Script

```bash
./fetch_statuses.sh [YEAR]
```

| Argument | Description | Default |
|----------|-------------|---------|
| `YEAR` | The year to fetch posts for | `2025` |

**Examples:**
```bash
./fetch_statuses.sh 2024    # Fetch 2024 posts
./fetch_statuses.sh 2023    # Fetch 2023 posts
./fetch_statuses.sh         # Fetch current year (2025)
```

**Output:** `statuses_YEAR.json`

### Generate Wrapped Script

```bash
./generate_wrapped.sh [YEAR] [OPTIONS]
```

| Argument | Description | Default |
|----------|-------------|---------|
| `YEAR` | The year to generate report for | `2025` |
| `--skip-ai` | Skip AI analysis (faster) | AI enabled |

**Examples:**
```bash
./generate_wrapped.sh 2024           # With AI analysis
./generate_wrapped.sh 2024 --skip-ai # Without AI
./generate_wrapped.sh                # Default year with AI
```

**Output:** `wrapped_YEAR_USERNAME.html`

## ⚙️ Configuration

All configurable parameters are at the top of each script for easy customization.

### Changing the Account

Edit `fetch_statuses.sh` line 5:
```bash
ACCOUNT="your_username@your.instance"
```

### Generate Script Configuration

Edit `generate_wrapped.sh` top section:
```bash
# Ollama Configuration
OLLAMA_BASE_URL="http://your-ollama-server:11434"
OLLAMA_MODEL="phi4:14b"           # AI model to use
OLLAMA_MAX_TOKENS=2500            # Max response length
OLLAMA_TEMPERATURE=0.7            # Creativity (0.0-1.0)

# Default year (can be overridden via command line)
DEFAULT_YEAR=2025

# Number of posts to sample for AI analysis
AI_SAMPLE_SIZE=50
```

### Customizing Year Theme Colors

Edit the `get_year_colors()` function in `generate_wrapped.sh`:
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

### Supported Ollama Models

Any instruction-following model works. Tested with:
- `phi4:14b` (recommended - good balance)
- `llama3.1:latest`
- `deepseek-r1:32b` (best quality, slower)
- `phi3.5:latest` (faster, smaller)

## 📊 Report Sections

### Statistics Card
- Total posts, original posts, boosts, replies
- Longest posting streak
- Average words per post

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
Based on posting behavior:
- **📢 The Broadcaster** - >60% original content
- **🎯 The Curator** - >60% boosts
- **💬 The Socialite** - >50% replies
- **⚖️ The Balancer** - Mixed posting style

### Chronotype Analysis
Based on posting hours:
- **🦉 Night Owl** - >15% posts between 0-5am
- **🐦 Early Bird** - >30% posts between 5-10am
- **😏 Slacker** - >60% posts during work hours
- **☀️ The Regular** - Balanced schedule

### AI Insights (when enabled)
- Emotional journey and mood analysis
- Personality traits detection
- Writing style characterization
- Interest areas and passion topics
- Personalized year narrative
- Fun facts about posting behavior

## 🎨 Year Themes

Each year has a unique color scheme:
- **2025** - Purple (`#8b5cf6`)
- **2024** - Amber (`#f59e0b`)
- **2023** - Teal (`#14b8a6`)
- **2022** - Pink (`#ec4899`)

## 🔧 Troubleshooting

### "toot: command not found"
```bash
# Install toot
brew install toot  # or pip install toot

# Login to your instance
toot login
```

### "No statuses found for YEAR"
- Ensure you have posts for that year
- Check if your account is correct in `fetch_statuses.sh`
- Verify authentication: `toot auth`

### AI analysis returns fallback values
- Check if Ollama server is running
- Verify the endpoint in `generate_wrapped.sh`
- Try a different model: change `OLLAMA_MODEL`

### "bc: command not found" or math errors
- Install bc: `brew install bc` (macOS) or `apt install bc` (Linux)

### "Argument list too long" error
The fetch script handles large datasets automatically. If you still see this error, ensure `jq` is up to date.

## 📝 Generate All Years

```bash
# Fetch all years
for year in 2022 2023 2024 2025; do
  ./fetch_statuses.sh $year
done

# Generate all reports
for year in 2022 2023 2024 2025; do
  ./generate_wrapped.sh $year
done

# Open index page
open index.html
```

## 🤝 Credits

- Inspired by [Mastodon Wrapped](https://github.com/Eyozy/mastodon-wrapped)
- Built for [GoToSocial](https://gotosocial.org/) and the Fediverse
- AI analysis powered by [Ollama](https://ollama.ai/)
- CLI access via [toot](https://github.com/ihabunek/toot)

## 📄 License

MIT License - Feel free to modify and share!

---

Made with 💜 for the Fediverse

