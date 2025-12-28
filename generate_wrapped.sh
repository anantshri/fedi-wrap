#!/usr/bin/env bash
#
# GoToSocial Year Wrapped Generator
# Generates a beautiful HTML report from fetched statuses
# Uses Ollama for personality and emotional analysis
#
# Requires: bash 4+, jq, curl, bc
#

set -e

# ============================================
# CONFIGURATION - Customize these variables
# ============================================

# Ollama Configuration
OLLAMA_BASE_URL="http://100.72.252.38:8080"
OLLAMA_MODEL="phi4:14b"
OLLAMA_MAX_TOKENS=2500
OLLAMA_TEMPERATURE=0.7

# Default year (can be overridden via command line)
DEFAULT_YEAR=2025

# Number of posts to sample for AI analysis
AI_SAMPLE_SIZE=50

# Year-specific theme colors
# Format: get_year_colors YEAR -> outputs "primary|secondary"
get_year_colors() {
    case "$1" in
        2022) echo "#ec4899|#db2777" ;;
        2023) echo "#14b8a6|#0d9488" ;;
        2024) echo "#f59e0b|#d97706" ;;
        2025) echo "#8b5cf6|#6366f1" ;;
        *)    echo "#8b5cf6|#6366f1" ;;  # Default
    esac
}

# ============================================
# Parse command line arguments
# ============================================

YEAR="${1:-$DEFAULT_YEAR}"
SKIP_AI=false

for arg in "$@"; do
    case $arg in
        --skip-ai)
            SKIP_AI=true
            shift
            ;;
    esac
done

DATA_FILE="statuses_${YEAR}.json"
OUTPUT_DIR="$(dirname "$0")"

echo ""
echo "🎁 Generating ${YEAR} Wrapped Report..."

# Check if data file exists
if [ ! -f "$OUTPUT_DIR/$DATA_FILE" ]; then
    echo "Error: Could not read $DATA_FILE. Run ./fetch_statuses.sh $YEAR first."
    exit 1
fi

# ============================================
# Helper Functions
# ============================================

strip_html() {
    echo "$1" | sed 's/<[^>]*>//g' | sed 's/&nbsp;/ /g' | sed 's/&amp;/\&/g' | sed 's/&lt;/</g' | sed 's/&gt;/>/g' | sed 's/&quot;/"/g'
}

format_number() {
    local num=$1
    if [ "$num" -ge 1000000 ]; then
        echo "$(echo "scale=1; $num/1000000" | bc)M"
    elif [ "$num" -ge 1000 ]; then
        echo "$(echo "scale=1; $num/1000" | bc)K"
    else
        echo "$num"
    fi
}

get_ranking_tier() {
    local score=$1
    if [ "$score" -ge 10000 ]; then
        echo "Top 1%|#ffd700|👑"
    elif [ "$score" -ge 5000 ]; then
        echo "Top 5%|#c0c0c0|🥈"
    elif [ "$score" -ge 1000 ]; then
        echo "Top 15%|#cd7f32|🥉"
    elif [ "$score" -ge 500 ]; then
        echo "Top 30%|#6366f1|⭐"
    elif [ "$score" -ge 100 ]; then
        echo "Top 50%|#8b5cf6|✨"
    else
        echo "Growing|#22c55e|🌱"
    fi
}

# ============================================
# Data Analysis with jq
# ============================================

echo "📊 Analyzing statuses..."

# Extract account info
ACCOUNT_JSON=$(jq '.account' "$OUTPUT_DIR/$DATA_FILE")
ACCOUNT_DISPLAY_NAME=$(echo "$ACCOUNT_JSON" | jq -r '.display_name // "User"' | sed 's/<[^>]*>//g')
ACCOUNT_ACCT=$(echo "$ACCOUNT_JSON" | jq -r '.acct // "user"')
ACCOUNT_AVATAR=$(echo "$ACCOUNT_JSON" | jq -r '.avatar // ""')
ACCOUNT_URL=$(echo "$ACCOUNT_JSON" | jq -r '.url // ""')
ACCOUNT_USERNAME=$(echo "$ACCOUNT_JSON" | jq -r '.username // "user"')

# Helper function to normalize date string (remove milliseconds and timezone variations)
# Filter statuses for the target year and compute stats
STATS_JSON=$(jq --arg year "$YEAR" '
    # Helper to extract hour from ISO date string
    def get_hour: split("T")[1] | split(":")[0] | tonumber;
    # Helper to extract month (0-indexed) from ISO date string  
    def get_month: split("-")[1] | tonumber - 1;
    # Helper to get weekday (0=Sun) from date string
    def get_weekday: (split("T")[0] + "T00:00:00Z") | fromdateiso8601 | strftime("%w") | tonumber;
    
    .statuses as $all |
    ($year + "-01-01") as $start |
    ($year + "-12-31") as $end |
    
    # Filter to year (simple string comparison works for ISO dates)
    [$all[] | select(.created_at >= $start and .created_at <= ($end + "T23:59:59Z"))] as $year_statuses |
    
    # Counts
    ($year_statuses | length) as $total |
    ([$year_statuses[] | select(.reblog == null)] | length) as $original |
    ([$year_statuses[] | select(.reblog != null)] | length) as $reblogs |
    ([$year_statuses[] | select(.in_reply_to_id != null)] | length) as $replies |
    
    # Original posts for engagement stats
    [$year_statuses[] | select(.reblog == null)] as $original_posts |
    ([$original_posts[] | select(.media_attachments | length > 0)] | length) as $media |
    ($original - $media) as $text |
    
    # Engagement totals
    ([$original_posts[].favourites_count // 0] | add // 0) as $total_favorites |
    ([$original_posts[].reblogs_count // 0] | add // 0) as $total_reblogs |
    ([$original_posts[].replies_count // 0] | add // 0) as $total_replies |
    
    # Unique dates for streak calculation
    ([$year_statuses[].created_at | split("T")[0]] | unique | sort) as $dates |
    
    # Calculate longest streak using simple date diff
    (if ($dates | length) == 0 then 0
     elif ($dates | length) == 1 then 1
     else
       reduce range(1; $dates | length) as $i (
         {max: 1, current: 1};
         (($dates[$i] + "T00:00:00Z") | fromdateiso8601) as $curr |
         (($dates[$i-1] + "T00:00:00Z") | fromdateiso8601) as $prev |
         (($curr - $prev) / 86400 | floor) as $diff |
         if $diff == 1 then
           {max: ([.max, .current + 1] | max), current: (.current + 1)}
         else
           {max: .max, current: 1}
         end
       ) | .max
     end) as $streak |
    
    # Social impact score
    (($total_reblogs * 2) + $total_favorites + ($total * 0.1) + ($streak * 5) | floor) as $score |
    
    # Persona determination
    (if $total == 0 then {name: "Newcomer", desc: "A new friend to the community", emoji: "🌱"}
     elif ($original / $total) > 0.6 then {name: "The Broadcaster", desc: "You prefer sharing your own thoughts and are a voice in the community.", emoji: "📢"}
     elif ($reblogs / $total) > 0.6 then {name: "The Curator", desc: "You love sharing others great content and are a quality information filter.", emoji: "🎯"}
     elif ($replies / $total) > 0.5 then {name: "The Socialite", desc: "You are active in comments and connect the community.", emoji: "💬"}
     else {name: "The Balancer", desc: "Your balance of original posts, boosts, and replies makes you the backbone of the community.", emoji: "⚖️"}
     end) as $persona |
    
    # Chronotype - count posts by hour using string parsing
    ([$year_statuses[].created_at | get_hour | select(. >= 0 and . < 5)] | length) as $night |
    ([$year_statuses[].created_at | get_hour | select(. >= 5 and . < 10)] | length) as $morning |
    ([$year_statuses[].created_at | get_hour | select(. >= 10 and . < 18)] | length) as $work |
    
    (if $total == 0 then {name: "The Regular", desc: "Regular schedule", emoji: "☀️"}
     elif ($night / $total) > 0.15 then {name: "Night Owl", desc: "Late night is your inspiration time, with high activity.", emoji: "🦉"}
     elif ($morning / $total) > 0.30 then {name: "Early Bird", desc: "You like to start your day with social activities in the early morning.", emoji: "🐦"}
     elif ($work / $total) > 0.60 then {name: "Slacker", desc: "Extremely active during work hours... too much free time or too busy?", emoji: "😏"}
     else {name: "The Regular", desc: "Regular schedule, mainly active in your free time.", emoji: "☀️"}
     end) as $chronotype |
    
    # Monthly distribution
    ([range(12)] | map({name: (["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"][.]), count: 0})) as $months_init |
    (reduce $year_statuses[] as $s ($months_init;
      ($s.created_at | get_month) as $m |
      .[$m].count += 1
    )) as $monthly |
    
    # Hourly distribution
    ([range(24)] | map({hour: ., label: "\(.):00", count: 0})) as $hours_init |
    (reduce $year_statuses[] as $s ($hours_init;
      ($s.created_at | get_hour) as $h |
      .[$h].count += 1
    )) as $hourly |
    
    # Weekday distribution
    (["Sun","Mon","Tue","Wed","Thu","Fri","Sat"] | to_entries | map({name: .value, day: .key, count: 0})) as $days_init |
    (reduce $year_statuses[] as $s ($days_init;
      ($s.created_at | get_weekday) as $d |
      .[$d].count += 1
    )) as $weekday |
    
    # Hashtag stats
    ([$year_statuses[].tags[]? | .name | ascii_downcase] | group_by(.) | map({name: .[0], count: length}) | sort_by(-.count) | .[0:10]) as $hashtags |
    
    # Activity calendar
    (reduce $year_statuses[] as $s ({};
      ($s.created_at | split("T")[0]) as $date |
      .[$date] = ((.[$date] // 0) + 1)
    )) as $calendar |
    
    # Most active day
    ($calendar | to_entries | sort_by(-.value) | .[0] // {key: null, value: 0}) as $most_active |
    
    # Busiest hour
    ($hourly | sort_by(-.count) | .[0]) as $busiest_hour |
    
    # Most active month
    ($monthly | sort_by(-.count) | .[0]) as $most_active_month |
    
    # Top posts by engagement
    ([$original_posts[] | {
      content: (.content | gsub("<[^>]*>"; "") | .[0:200]),
      favorites: (.favourites_count // 0),
      reblogs: (.reblogs_count // 0),
      replies: (.replies_count // 0),
      engagement: ((.favourites_count // 0) + (.reblogs_count // 0) + (.replies_count // 0)),
      created_at: .created_at
    }] | sort_by(-.engagement) | .[0:5]) as $top_posts |
    
    # Content distribution
    ([
      {name: "Text", value: $text, color: "#3b82f6"},
      {name: "Boosts", value: $reblogs, color: "#22c55e"},
      {name: "Media", value: $media, color: "#f59e0b"}
    ] | map(select(.value > 0))) as $content_dist |
    
    # First and last post dates
    ($year_statuses | sort_by(.created_at) | .[0].created_at // null) as $first_post |
    ($year_statuses | sort_by(.created_at) | .[-1].created_at // null) as $last_post |
    
    # Average words per post
    (if ($original_posts | length) == 0 then 0
     else
       (([$original_posts[].content | gsub("<[^>]*>"; "") | split(" ") | map(select(length > 0)) | length] | add) / ($original_posts | length) | floor)
     end) as $avg_words |
    
    {
      year: ($year | tonumber),
      totalPosts: $total,
      originalPosts: $original,
      reblogs: $reblogs,
      replies: $replies,
      mediaPosts: $media,
      textPosts: $text,
      totalFavorites: $total_favorites,
      totalReblogs: $total_reblogs,
      totalReplies: $total_replies,
      longestStreak: $streak,
      socialImpactScore: $score,
      persona: $persona,
      chronotype: $chronotype,
      monthlyPosts: $monthly,
      hourlyPosts: $hourly,
      weekdayPosts: $weekday,
      topHashtags: $hashtags,
      uniqueHashtags: ([$year_statuses[].tags[]?.name] | unique | length),
      activityCalendar: $calendar,
      mostActiveDay: {date: $most_active.key, count: $most_active.value},
      busiestHour: $busiest_hour,
      mostActiveMonth: $most_active_month,
      topPosts: $top_posts,
      contentDistribution: $content_dist,
      firstPostDate: $first_post,
      lastPostDate: $last_post,
      avgWordsPerPost: $avg_words
    }
' "$OUTPUT_DIR/$DATA_FILE")

# Extract key stats for display
TOTAL_POSTS=$(echo "$STATS_JSON" | jq -r '.totalPosts')
ORIGINAL_POSTS=$(echo "$STATS_JSON" | jq -r '.originalPosts')
REBLOGS=$(echo "$STATS_JSON" | jq -r '.reblogs')
REPLIES=$(echo "$STATS_JSON" | jq -r '.replies')
LONGEST_STREAK=$(echo "$STATS_JSON" | jq -r '.longestStreak')
SOCIAL_IMPACT_SCORE=$(echo "$STATS_JSON" | jq -r '.socialImpactScore')
PERSONA_NAME=$(echo "$STATS_JSON" | jq -r '.persona.name')
PERSONA_DESC=$(echo "$STATS_JSON" | jq -r '.persona.desc')
PERSONA_EMOJI=$(echo "$STATS_JSON" | jq -r '.persona.emoji')
CHRONOTYPE_NAME=$(echo "$STATS_JSON" | jq -r '.chronotype.name')
CHRONOTYPE_DESC=$(echo "$STATS_JSON" | jq -r '.chronotype.desc')
CHRONOTYPE_EMOJI=$(echo "$STATS_JSON" | jq -r '.chronotype.emoji')
UNIQUE_HASHTAGS=$(echo "$STATS_JSON" | jq -r '.uniqueHashtags')
AVG_WORDS=$(echo "$STATS_JSON" | jq -r '.avgWordsPerPost')
TOTAL_FAVORITES=$(echo "$STATS_JSON" | jq -r '.totalFavorites')
TOTAL_REBLOGS_RECEIVED=$(echo "$STATS_JSON" | jq -r '.totalReblogs')
TOTAL_REPLIES_RECEIVED=$(echo "$STATS_JSON" | jq -r '.totalReplies')

if [ "$TOTAL_POSTS" -eq 0 ]; then
    echo "Error: No statuses found for $YEAR"
    exit 1
fi

echo "Found $TOTAL_POSTS posts in $YEAR"
echo "Persona: $PERSONA_NAME"
echo "Chronotype: $CHRONOTYPE_NAME"
echo "Social Impact Score: $SOCIAL_IMPACT_SCORE"

# ============================================
# AI Analysis with Ollama
# ============================================

AI_INSIGHTS_JSON="null"

if [ "$SKIP_AI" = false ]; then
    echo "🤖 Analyzing posts with AI..."
    
    # Get sample posts for AI analysis
    SAMPLE_POSTS=$(jq -r --arg year "$YEAR" --argjson size "$AI_SAMPLE_SIZE" '
        .statuses |
        map(select(.reblog == null and .content != null and .created_at >= ($year + "-01-01") and .created_at <= ($year + "-12-31"))) |
        [limit($size; .[])] |
        map(.content | gsub("<[^>]*>"; "") | .[0:500]) |
        join("\n---\n")
    ' "$OUTPUT_DIR/$DATA_FILE")
    
    # Build the prompt
    AI_PROMPT="You are analyzing social media posts from a Fediverse user for their ${YEAR} Year Wrapped report.

Here are sample posts from this user:

${SAMPLE_POSTS}

Based on these posts, provide a detailed analysis in the following JSON format (respond ONLY with valid JSON, no markdown):

{
  \"emotional_journey\": {
    \"overall_mood\": \"one word describing dominant mood (e.g., Thoughtful, Energetic, Curious, Passionate)\",
    \"mood_description\": \"2-3 sentences describing their emotional tone throughout the year\",
    \"highlights\": [\"3-4 emotional highlights or moods observed\"]
  },
  \"personality_traits\": {
    \"primary_trait\": \"Main personality trait (e.g., The Thinker, The Advocate, The Explorer)\",
    \"traits\": [\"list of 4-5 personality traits observed\"],
    \"description\": \"2-3 sentences describing their online personality\"
  },
  \"interests\": {
    \"main_topics\": [\"top 5-7 topics/interests they post about\"],
    \"expertise_areas\": [\"2-3 areas they seem knowledgeable in\"],
    \"passion_topic\": \"The topic they seem most passionate about\"
  },
  \"writing_style\": {
    \"style\": \"Brief description of their writing style\",
    \"tone\": \"one word (e.g., Professional, Casual, Humorous, Analytical)\",
    \"notable_patterns\": \"Any notable patterns in how they communicate\"
  },
  \"year_narrative\": \"A 3-4 sentence narrative summary of their year on social media, written in second person (You...). Make it personal and insightful.\",
  \"fun_fact\": \"One fun or interesting observation about their posting behavior\"
}"

    # Call Ollama API
    AI_RESPONSE=$(curl -s "${OLLAMA_BASE_URL}/api/generate" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg model "$OLLAMA_MODEL" \
            --arg prompt "$AI_PROMPT" \
            --argjson num_predict "$OLLAMA_MAX_TOKENS" \
            --argjson temperature "$OLLAMA_TEMPERATURE" \
            '{model: $model, prompt: $prompt, stream: false, options: {num_predict: $num_predict, temperature: $temperature}}')" \
        2>/dev/null | jq -r '.response // empty')
    
    if [ -n "$AI_RESPONSE" ]; then
        # Clean up response and parse JSON
        CLEANED_RESPONSE=$(echo "$AI_RESPONSE" | sed 's/^```json//; s/^```//; s/```$//' | tr -d '\n' | sed 's/  */ /g')
        
        # Try to parse as JSON
        if echo "$CLEANED_RESPONSE" | jq . >/dev/null 2>&1; then
            AI_INSIGHTS_JSON="$CLEANED_RESPONSE"
            AI_MOOD=$(echo "$AI_INSIGHTS_JSON" | jq -r '.emotional_journey.overall_mood // "Engaged"')
            AI_PERSONA=$(echo "$AI_INSIGHTS_JSON" | jq -r '.personality_traits.primary_trait // "Active Participant"')
            AI_PASSION=$(echo "$AI_INSIGHTS_JSON" | jq -r '.interests.passion_topic // "Technology"')
            
            echo ""
            echo "🤖 AI Analysis Complete!"
            echo "   Mood: $AI_MOOD"
            echo "   Persona: $AI_PERSONA"
            echo "   Passion: $AI_PASSION"
        else
            echo "Warning: Could not parse AI response as JSON, using defaults"
            AI_INSIGHTS_JSON='{"emotional_journey":{"overall_mood":"Engaged","mood_description":"Active participation in the Fediverse community.","highlights":[]},"personality_traits":{"primary_trait":"Active Participant","traits":["Engaged","Social","Thoughtful"],"description":"An active member of the Fediverse community."},"interests":{"main_topics":[],"expertise_areas":[],"passion_topic":"Technology"},"writing_style":{"style":"Varied","tone":"Conversational","notable_patterns":"Diverse topics"},"year_narrative":"You had an active year on the Fediverse, sharing thoughts and engaging with the community.","fun_fact":"You are part of the decentralized social web!"}'
        fi
    else
        echo "Warning: Could not connect to Ollama, skipping AI analysis"
    fi
else
    echo ""
    echo "⏭️  Skipping AI analysis (--skip-ai flag)"
fi

# ============================================
# Generate HTML Report
# ============================================

# Get theme colors
YEAR_COLORS=$(get_year_colors "$YEAR")
PRIMARY_COLOR=$(echo "$YEAR_COLORS" | cut -d'|' -f1)
SECONDARY_COLOR=$(echo "$YEAR_COLORS" | cut -d'|' -f2)

# Convert hex to rgba for glow
hex_to_rgba() {
    local hex="${1#\#}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    echo "rgba($r, $g, $b, 0.4)"
}
GLOW_COLOR=$(hex_to_rgba "$PRIMARY_COLOR")

# Get ranking tier
RANKING_INFO=$(get_ranking_tier "$SOCIAL_IMPACT_SCORE")
RANKING_TIER=$(echo "$RANKING_INFO" | cut -d'|' -f1)
RANKING_COLOR=$(echo "$RANKING_INFO" | cut -d'|' -f2)
RANKING_EMOJI=$(echo "$RANKING_INFO" | cut -d'|' -f3)

# Generate monthly bars HTML
MONTHLY_MAX=$(echo "$STATS_JSON" | jq '[.monthlyPosts[].count] | max')
MONTHLY_BARS=""
while IFS= read -r row; do
    name=$(echo "$row" | jq -r '.name')
    count=$(echo "$row" | jq -r '.count')
    pct=$(echo "scale=2; $count * 100 / $MONTHLY_MAX" | bc 2>/dev/null || echo "0")
    MONTHLY_BARS+="<div class=\"bar-row\"><span class=\"bar-label\">$name</span><div class=\"bar-container\"><div class=\"bar-fill\" style=\"width: ${pct}%\"></div></div><span class=\"bar-value\">$count</span></div>"
done < <(echo "$STATS_JSON" | jq -c '.monthlyPosts[]')

# Generate hourly bars HTML (every 2 hours)
HOURLY_MAX=$(echo "$STATS_JSON" | jq '[.hourlyPosts[].count] | max')
HOURLY_BARS=""
while IFS= read -r row; do
    hour=$(echo "$row" | jq -r '.hour')
    label=$(echo "$row" | jq -r '.label')
    count=$(echo "$row" | jq -r '.count')
    if [ $((hour % 2)) -eq 0 ]; then
        pct=$(echo "scale=2; $count * 100 / $HOURLY_MAX" | bc 2>/dev/null || echo "0")
        HOURLY_BARS+="<div class=\"bar-row\"><span class=\"bar-label\">$label</span><div class=\"bar-container\"><div class=\"bar-fill\" style=\"width: ${pct}%\"></div></div><span class=\"bar-value\">$count</span></div>"
    fi
done < <(echo "$STATS_JSON" | jq -c '.hourlyPosts[]')

# Generate weekday bars HTML
WEEKDAY_MAX=$(echo "$STATS_JSON" | jq '[.weekdayPosts[].count] | max')
WEEKDAY_BARS=""
while IFS= read -r row; do
    name=$(echo "$row" | jq -r '.name')
    count=$(echo "$row" | jq -r '.count')
    pct=$(echo "scale=2; $count * 100 / $WEEKDAY_MAX" | bc 2>/dev/null || echo "0")
    WEEKDAY_BARS+="<div class=\"bar-row\"><span class=\"bar-label\">$name</span><div class=\"bar-container\"><div class=\"bar-fill\" style=\"width: ${pct}%\"></div></div><span class=\"bar-value\">$count</span></div>"
done < <(echo "$STATS_JSON" | jq -c '.weekdayPosts[]')

# Generate content distribution HTML
CONTENT_DIST=""
while IFS= read -r row; do
    name=$(echo "$row" | jq -r '.name')
    value=$(echo "$row" | jq -r '.value')
    color=$(echo "$row" | jq -r '.color')
    CONTENT_DIST+="<div class=\"pie-item\"><div class=\"pie-color\" style=\"background: $color\"></div><div class=\"pie-text\"><span class=\"pie-value\">$value</span><span class=\"pie-label\">$name</span></div></div>"
done < <(echo "$STATS_JSON" | jq -c '.contentDistribution[]')

# Generate hashtags HTML
HASHTAGS_HTML=""
while IFS= read -r row; do
    name=$(echo "$row" | jq -r '.name')
    count=$(echo "$row" | jq -r '.count')
    HASHTAGS_HTML+="<span class=\"hashtag\">#$name<span class=\"hashtag-count\">×$count</span></span>"
done < <(echo "$STATS_JSON" | jq -c '.topHashtags[]')

# Generate top posts HTML
TOP_POSTS_HTML=""
while IFS= read -r row; do
    content=$(echo "$row" | jq -r '.content')
    favorites=$(echo "$row" | jq -r '.favorites')
    reblogs=$(echo "$row" | jq -r '.reblogs')
    replies=$(echo "$row" | jq -r '.replies')
    created_at=$(echo "$row" | jq -r '.created_at')
    formatted_date=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${created_at%%.*}" "+%b %d, %Y" 2>/dev/null || echo "$created_at")
    TOP_POSTS_HTML+="<div class=\"top-post\"><div class=\"top-post-content\">$content</div><div class=\"top-post-meta\"><span class=\"meta-item\">❤️ $favorites</span><span class=\"meta-item\">🔁 $reblogs</span><span class=\"meta-item\">💬 $replies</span><span class=\"meta-item\">📅 $formatted_date</span></div></div>"
done < <(echo "$STATS_JSON" | jq -c '.topPosts[]')

# Generate calendar HTML
CALENDAR_HTML=$(jq -r --arg year "$YEAR" --arg primary "$PRIMARY_COLOR" '
    .activityCalendar as $cal |
    ($cal | values | max // 1) as $max |
    
    # Generate week cells
    ($year + "-01-01") as $start_str |
    ($year + "-12-31") as $end_str |
    
    "<div class=\"calendar-grid\">" +
    ([range(371)] | map(
        (($year | tonumber) as $y |
         (. - (($start_str | strptime("%Y-%m-%d") | mktime | strftime("%w") | tonumber))) as $day_offset |
         if $day_offset >= 0 and $day_offset < 365 then
            (($start_str | strptime("%Y-%m-%d") | mktime) + ($day_offset * 86400) | strftime("%Y-%m-%d")) as $date |
            ($cal[$date] // 0) as $count |
            (if $count == 0 then 0
             elif $count <= ($max * 0.2) then 1
             elif $count <= ($max * 0.4) then 2
             elif $count <= ($max * 0.6) then 3
             elif $count <= ($max * 0.8) then 4
             else 5 end) as $level |
            "<div class=\"calendar-cell level-\($level)\" title=\"\($date): \($count) posts\"></div>"
         else ""
         end)
    ) | join("")) +
    "</div>"
' "$OUTPUT_DIR/$DATA_FILE")

# Get most active info
MOST_ACTIVE_DAY=$(echo "$STATS_JSON" | jq -r '.mostActiveDay.date // ""')
MOST_ACTIVE_COUNT=$(echo "$STATS_JSON" | jq -r '.mostActiveDay.count // 0')
BUSIEST_HOUR=$(echo "$STATS_JSON" | jq -r '.busiestHour.hour // 0')
BUSIEST_HOUR_COUNT=$(echo "$STATS_JSON" | jq -r '.busiestHour.count // 0')
MOST_ACTIVE_MONTH=$(echo "$STATS_JSON" | jq -r '.mostActiveMonth.name // ""')
MOST_ACTIVE_MONTH_COUNT=$(echo "$STATS_JSON" | jq -r '.mostActiveMonth.count // 0')
FIRST_POST=$(echo "$STATS_JSON" | jq -r '.firstPostDate // ""')
LAST_POST=$(echo "$STATS_JSON" | jq -r '.lastPostDate // ""')

# Format dates
format_date() {
    if [ -n "$1" ] && [ "$1" != "null" ]; then
        date -j -f "%Y-%m-%dT%H:%M:%S" "${1%%.*}" "+%b %d, %Y" 2>/dev/null || echo "$1"
    fi
}
MOST_ACTIVE_DAY_FMT=$(format_date "$MOST_ACTIVE_DAY")
FIRST_POST_FMT=$(format_date "$FIRST_POST")
LAST_POST_FMT=$(format_date "$LAST_POST")

# Generate AI insights section if available
AI_SECTION=""
if [ "$AI_INSIGHTS_JSON" != "null" ]; then
    AI_NARRATIVE=$(echo "$AI_INSIGHTS_JSON" | jq -r '.year_narrative // ""')
    AI_MOOD=$(echo "$AI_INSIGHTS_JSON" | jq -r '.emotional_journey.overall_mood // "Engaged"')
    AI_MOOD_DESC=$(echo "$AI_INSIGHTS_JSON" | jq -r '.emotional_journey.mood_description // ""')
    AI_PERSONA=$(echo "$AI_INSIGHTS_JSON" | jq -r '.personality_traits.primary_trait // "Active Participant"')
    AI_PERSONA_DESC=$(echo "$AI_INSIGHTS_JSON" | jq -r '.personality_traits.description // ""')
    AI_TRAITS=$(echo "$AI_INSIGHTS_JSON" | jq -r '.personality_traits.traits[:5] | map("<span class=\"trait-tag\">\(.)</span>") | join("")')
    AI_TONE=$(echo "$AI_INSIGHTS_JSON" | jq -r '.writing_style.tone // "Conversational"')
    AI_STYLE=$(echo "$AI_INSIGHTS_JSON" | jq -r '.writing_style.style // ""')
    AI_PASSION=$(echo "$AI_INSIGHTS_JSON" | jq -r '.interests.passion_topic // "Technology"')
    AI_TOPICS=$(echo "$AI_INSIGHTS_JSON" | jq -r '.interests.main_topics[:4] | map("<span class=\"trait-tag\">\(.)</span>") | join("")')
    AI_FUN_FACT=$(echo "$AI_INSIGHTS_JSON" | jq -r '.fun_fact // ""')
    
    AI_SECTION="
        <section class=\"ai-insights\">
            <h2>🤖 AI-Powered Insights</h2>
            
            <div class=\"narrative\">
                \"$AI_NARRATIVE\"
            </div>

            <div class=\"ai-grid\">
                <div class=\"ai-card\">
                    <div class=\"ai-card-title\">Emotional Vibe</div>
                    <div class=\"ai-card-value\">$AI_MOOD</div>
                    <div class=\"ai-card-desc\">$AI_MOOD_DESC</div>
                </div>

                <div class=\"ai-card\">
                    <div class=\"ai-card-title\">AI Persona</div>
                    <div class=\"ai-card-value\">$AI_PERSONA</div>
                    <div class=\"ai-card-desc\">$AI_PERSONA_DESC</div>
                    <div class=\"trait-list\">$AI_TRAITS</div>
                </div>

                <div class=\"ai-card\">
                    <div class=\"ai-card-title\">Writing Style</div>
                    <div class=\"ai-card-value\">$AI_TONE</div>
                    <div class=\"ai-card-desc\">$AI_STYLE</div>
                </div>

                <div class=\"ai-card\">
                    <div class=\"ai-card-title\">Passion Topic</div>
                    <div class=\"ai-card-value\">$AI_PASSION</div>
                    <div class=\"trait-list\">$AI_TOPICS</div>
                </div>
            </div>

            <div class=\"fun-fact\">
                <span class=\"fun-fact-icon\">💡</span>
                <span class=\"fun-fact-text\">$AI_FUN_FACT</span>
            </div>
        </section>"
fi

# Output file
OUTPUT_FILE="$OUTPUT_DIR/wrapped_${YEAR}_${ACCOUNT_USERNAME}.html"

# Generate the HTML file
cat > "$OUTPUT_FILE" << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${ACCOUNT_DISPLAY_NAME} - ${YEAR} Wrapped</title>
    <link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg-primary: #0a0a0f;
            --bg-secondary: #12121a;
            --bg-card: #1a1a25;
            --bg-hover: #252535;
            --text-primary: #f0f0f5;
            --text-secondary: #a0a0b0;
            --text-muted: #606070;
            --accent-primary: ${PRIMARY_COLOR};
            --accent-secondary: ${SECONDARY_COLOR};
            --accent-tertiary: ${PRIMARY_COLOR}cc;
            --accent-gold: #fbbf24;
            --success: #22c55e;
            --warning: #f59e0b;
            --border: ${PRIMARY_COLOR}33;
            --glow: ${GLOW_COLOR};
        }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Space Grotesk', -apple-system, sans-serif; background: var(--bg-primary); color: var(--text-primary); line-height: 1.6; min-height: 100vh; }
        .container { max-width: 1200px; margin: 0 auto; padding: 2rem; }
        .hero { text-align: center; padding: 4rem 2rem; background: linear-gradient(135deg, var(--bg-secondary) 0%, var(--bg-primary) 100%); border-radius: 24px; margin-bottom: 2rem; position: relative; overflow: hidden; }
        .hero::before { content: ''; position: absolute; top: 0; left: 0; right: 0; bottom: 0; background: radial-gradient(circle at 30% 20%, var(--glow) 0%, transparent 50%), radial-gradient(circle at 70% 80%, ${SECONDARY_COLOR}33 0%, transparent 50%); pointer-events: none; }
        .hero-content { position: relative; z-index: 1; }
        .avatar { width: 120px; height: 120px; border-radius: 50%; border: 4px solid var(--accent-primary); margin-bottom: 1.5rem; box-shadow: 0 0 40px var(--glow); }
        .year-badge { display: inline-block; background: linear-gradient(135deg, var(--accent-primary), var(--accent-secondary)); color: white; padding: 0.5rem 1.5rem; border-radius: 50px; font-size: 1.25rem; font-weight: 600; margin-bottom: 1rem; letter-spacing: 2px; }
        .display-name { font-size: 2.5rem; font-weight: 700; margin-bottom: 0.5rem; background: linear-gradient(135deg, var(--text-primary), var(--accent-tertiary)); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; }
        .handle { color: var(--text-secondary); font-size: 1.1rem; font-family: 'JetBrains Mono', monospace; }
        .ai-insights { background: linear-gradient(135deg, var(--bg-card) 0%, ${PRIMARY_COLOR}15 100%); border-radius: 20px; padding: 2rem; margin-bottom: 2rem; border: 1px solid var(--border); }
        .ai-insights h2 { font-size: 1.5rem; margin-bottom: 1.5rem; display: flex; align-items: center; gap: 0.5rem; }
        .narrative { font-size: 1.2rem; line-height: 1.8; color: var(--text-primary); padding: 1.5rem; background: var(--bg-secondary); border-radius: 12px; border-left: 4px solid var(--accent-primary); margin-bottom: 1.5rem; font-style: italic; }
        .ai-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 1.5rem; }
        .ai-card { background: var(--bg-secondary); border-radius: 12px; padding: 1.5rem; }
        .ai-card-title { font-size: 0.85rem; color: var(--text-muted); text-transform: uppercase; letter-spacing: 1px; margin-bottom: 0.75rem; }
        .ai-card-value { font-size: 1.25rem; font-weight: 600; color: var(--accent-primary); margin-bottom: 0.5rem; }
        .ai-card-desc { color: var(--text-secondary); font-size: 0.9rem; line-height: 1.6; }
        .trait-list { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-top: 0.75rem; }
        .trait-tag { background: var(--accent-primary)22; color: var(--accent-primary); padding: 0.25rem 0.75rem; border-radius: 50px; font-size: 0.85rem; }
        .fun-fact { background: var(--accent-gold)15; border: 1px solid var(--accent-gold)33; border-radius: 12px; padding: 1rem 1.5rem; margin-top: 1.5rem; display: flex; align-items: flex-start; gap: 0.75rem; }
        .fun-fact-icon { font-size: 1.5rem; }
        .fun-fact-text { color: var(--text-primary); font-size: 0.95rem; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 1.5rem; margin-bottom: 2rem; }
        .stat-card { background: var(--bg-card); border-radius: 16px; padding: 1.5rem; border: 1px solid var(--border); transition: transform 0.3s, box-shadow 0.3s; }
        .stat-card:hover { transform: translateY(-4px); box-shadow: 0 8px 30px ${PRIMARY_COLOR}22; }
        .stat-value { font-size: 2.25rem; font-weight: 700; color: var(--accent-primary); font-family: 'JetBrains Mono', monospace; }
        .stat-label { color: var(--text-secondary); font-size: 0.85rem; margin-top: 0.25rem; }
        .impact-card { background: linear-gradient(135deg, var(--bg-card) 0%, ${PRIMARY_COLOR}15 100%); border-radius: 20px; padding: 2rem; margin-bottom: 2rem; border: 1px solid var(--border); text-align: center; }
        .impact-score { font-size: 4rem; font-weight: 700; font-family: 'JetBrains Mono', monospace; background: linear-gradient(135deg, var(--accent-gold), var(--accent-primary)); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; }
        .ranking-badge { display: inline-flex; align-items: center; gap: 0.5rem; padding: 0.75rem 1.5rem; border-radius: 50px; font-weight: 600; font-size: 1.1rem; margin-top: 1rem; }
        .persona-section { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 1.5rem; margin-bottom: 2rem; }
        .persona-card { background: var(--bg-card); border-radius: 16px; padding: 2rem; border: 1px solid var(--border); }
        .persona-title { font-size: 1.75rem; font-weight: 700; margin-bottom: 0.5rem; color: var(--accent-tertiary); }
        .persona-desc { color: var(--text-secondary); line-height: 1.7; }
        .section-label { font-size: 0.85rem; color: var(--text-muted); text-transform: uppercase; letter-spacing: 1px; margin-bottom: 0.5rem; }
        .chart-section { background: var(--bg-card); border-radius: 16px; padding: 2rem; margin-bottom: 2rem; border: 1px solid var(--border); }
        .chart-title { font-size: 1.25rem; font-weight: 600; margin-bottom: 1.5rem; color: var(--text-primary); }
        .bar-chart { display: flex; flex-direction: column; gap: 0.75rem; }
        .bar-row { display: flex; align-items: center; gap: 1rem; }
        .bar-label { width: 50px; font-size: 0.85rem; color: var(--text-secondary); font-family: 'JetBrains Mono', monospace; }
        .bar-container { flex: 1; height: 24px; background: var(--bg-secondary); border-radius: 12px; overflow: hidden; }
        .bar-fill { height: 100%; background: linear-gradient(90deg, var(--accent-primary), var(--accent-secondary)); border-radius: 12px; transition: width 0.3s; }
        .bar-value { width: 40px; text-align: right; font-size: 0.85rem; color: var(--text-muted); font-family: 'JetBrains Mono', monospace; }
        .pie-chart { display: flex; justify-content: center; gap: 2rem; flex-wrap: wrap; }
        .pie-item { display: flex; align-items: center; gap: 0.75rem; }
        .pie-color { width: 16px; height: 16px; border-radius: 4px; }
        .pie-text { font-size: 0.95rem; }
        .pie-value { font-weight: 600; color: var(--text-primary); }
        .pie-label { color: var(--text-secondary); margin-left: 0.25rem; }
        .calendar-grid { display: grid; grid-template-columns: repeat(53, 1fr); gap: 3px; margin-top: 1rem; }
        .calendar-cell { aspect-ratio: 1; border-radius: 3px; background: var(--bg-secondary); }
        .calendar-cell.level-1 { background: ${PRIMARY_COLOR}33; }
        .calendar-cell.level-2 { background: ${PRIMARY_COLOR}55; }
        .calendar-cell.level-3 { background: ${PRIMARY_COLOR}88; }
        .calendar-cell.level-4 { background: ${PRIMARY_COLOR}bb; }
        .calendar-cell.level-5 { background: var(--accent-primary); }
        .calendar-legend { display: flex; align-items: center; justify-content: flex-end; gap: 0.5rem; margin-top: 1rem; font-size: 0.8rem; color: var(--text-muted); }
        .legend-cell { width: 12px; height: 12px; border-radius: 2px; }
        .hashtag-cloud { display: flex; flex-wrap: wrap; gap: 0.75rem; }
        .hashtag { background: var(--bg-secondary); padding: 0.5rem 1rem; border-radius: 50px; font-size: 0.9rem; color: var(--accent-tertiary); border: 1px solid var(--border); transition: all 0.2s; }
        .hashtag:hover { background: var(--bg-hover); border-color: var(--accent-primary); }
        .hashtag-count { color: var(--text-muted); font-size: 0.8rem; margin-left: 0.25rem; }
        .top-posts { display: flex; flex-direction: column; gap: 1rem; }
        .top-post { background: var(--bg-secondary); padding: 1.25rem; border-radius: 12px; border: 1px solid var(--border); }
        .top-post-content { color: var(--text-primary); margin-bottom: 0.75rem; line-height: 1.6; }
        .top-post-meta { display: flex; gap: 1rem; font-size: 0.85rem; color: var(--text-muted); }
        .meta-item { display: flex; align-items: center; gap: 0.25rem; }
        .footer { text-align: center; padding: 3rem 2rem; color: var(--text-muted); font-size: 0.9rem; }
        .footer a { color: var(--accent-tertiary); text-decoration: none; }
        @media (max-width: 768px) { .container { padding: 1rem; } .hero { padding: 2rem 1rem; } .display-name { font-size: 1.75rem; } .stat-value { font-size: 1.75rem; } .impact-score { font-size: 3rem; } .stats-grid { grid-template-columns: repeat(2, 1fr); } }
    </style>
</head>
<body>
    <div class="container">
        <section class="hero">
            <div class="hero-content">
                <img src="${ACCOUNT_AVATAR}" alt="Avatar" class="avatar" crossorigin="anonymous">
                <div class="year-badge">${YEAR} WRAPPED</div>
                <h1 class="display-name">${ACCOUNT_DISPLAY_NAME}</h1>
                <p class="handle">@${ACCOUNT_ACCT}</p>
            </div>
        </section>

        ${AI_SECTION}

        <section class="stats-grid">
            <div class="stat-card"><div class="stat-value">$(format_number $TOTAL_POSTS)</div><div class="stat-label">Total Posts</div></div>
            <div class="stat-card"><div class="stat-value">$(format_number $ORIGINAL_POSTS)</div><div class="stat-label">Original Posts</div></div>
            <div class="stat-card"><div class="stat-value">$(format_number $REBLOGS)</div><div class="stat-label">Boosts</div></div>
            <div class="stat-card"><div class="stat-value">$(format_number $REPLIES)</div><div class="stat-label">Replies</div></div>
            <div class="stat-card"><div class="stat-value">${LONGEST_STREAK}</div><div class="stat-label">Day Streak</div></div>
            <div class="stat-card"><div class="stat-value">${AVG_WORDS}</div><div class="stat-label">Avg Words/Post</div></div>
        </section>

        <section class="impact-card">
            <div class="section-label">Social Impact Score</div>
            <div class="impact-score">$(format_number $SOCIAL_IMPACT_SCORE)</div>
            <div class="ranking-badge" style="background: ${RANKING_COLOR}20; color: ${RANKING_COLOR}; border: 1px solid ${RANKING_COLOR}40;">
                <span>${RANKING_EMOJI}</span>
                <span>${RANKING_TIER}</span>
            </div>
            <p style="color: var(--text-secondary); margin-top: 1rem; font-size: 0.9rem;">
                ${TOTAL_FAVORITES} favorites · ${TOTAL_REBLOGS_RECEIVED} reblogs · ${TOTAL_REPLIES_RECEIVED} replies received
            </p>
        </section>

        <section class="persona-section">
            <div class="persona-card">
                <div class="section-label">Your Persona</div>
                <div class="persona-title">${PERSONA_EMOJI} ${PERSONA_NAME}</div>
                <p class="persona-desc">${PERSONA_DESC}</p>
            </div>
            <div class="persona-card">
                <div class="section-label">Your Chronotype</div>
                <div class="persona-title">${CHRONOTYPE_EMOJI} ${CHRONOTYPE_NAME}</div>
                <p class="persona-desc">${CHRONOTYPE_DESC}</p>
            </div>
        </section>

        <section class="chart-section">
            <h3 class="chart-title">📅 Monthly Activity</h3>
            <div class="bar-chart">${MONTHLY_BARS}</div>
            <p style="color: var(--text-secondary); margin-top: 1.5rem; font-size: 0.9rem;">
                📈 Most active: <strong style="color: var(--accent-tertiary)">${MOST_ACTIVE_MONTH}</strong> with ${MOST_ACTIVE_MONTH_COUNT} posts
            </p>
        </section>

        <section class="chart-section">
            <h3 class="chart-title">⏰ Posting Hours</h3>
            <div class="bar-chart">${HOURLY_BARS}</div>
            <p style="color: var(--text-secondary); margin-top: 1.5rem; font-size: 0.9rem;">
                🔥 Peak hour: <strong style="color: var(--accent-tertiary)">${BUSIEST_HOUR}:00</strong> with ${BUSIEST_HOUR_COUNT} posts
            </p>
        </section>

        <section class="chart-section">
            <h3 class="chart-title">📆 Weekly Pattern</h3>
            <div class="bar-chart">${WEEKDAY_BARS}</div>
        </section>

        <section class="chart-section">
            <h3 class="chart-title">📊 Content Distribution</h3>
            <div class="pie-chart">${CONTENT_DIST}</div>
        </section>

        <section class="chart-section">
            <h3 class="chart-title">🗓️ Activity Calendar</h3>
            ${CALENDAR_HTML}
            <div class="calendar-legend">
                <span>Less</span>
                <div class="legend-cell" style="background: var(--bg-secondary)"></div>
                <div class="legend-cell" style="background: ${PRIMARY_COLOR}33"></div>
                <div class="legend-cell" style="background: ${PRIMARY_COLOR}55"></div>
                <div class="legend-cell" style="background: ${PRIMARY_COLOR}88"></div>
                <div class="legend-cell" style="background: var(--accent-primary)"></div>
                <span>More</span>
            </div>
            <p style="color: var(--text-secondary); margin-top: 1rem; font-size: 0.9rem;">
                🎯 Most active day: <strong style="color: var(--accent-tertiary)">${MOST_ACTIVE_DAY_FMT}</strong> with ${MOST_ACTIVE_COUNT} posts
            </p>
        </section>

        <section class="chart-section">
            <h3 class="chart-title">#️⃣ Top Hashtags</h3>
            <div class="hashtag-cloud">${HASHTAGS_HTML}</div>
        </section>

        <section class="chart-section">
            <h3 class="chart-title">🏆 Top Posts by Engagement</h3>
            <div class="top-posts">${TOP_POSTS_HTML}</div>
        </section>

        <footer class="footer">
            <p>Generated with 💜 for the Fediverse</p>
            <p style="margin-top: 0.5rem">
                <a href="${ACCOUNT_URL}" target="_blank">View Profile</a> · 
                Powered by GoToSocial Wrapped
            </p>
            <p style="margin-top: 0.5rem; font-size: 0.8rem;">
                First post: ${FIRST_POST_FMT} · Last post: ${LAST_POST_FMT}
            </p>
        </footer>
    </div>
</body>
</html>
HTMLEOF

echo ""
echo "✨ Report generated: $OUTPUT_FILE"

