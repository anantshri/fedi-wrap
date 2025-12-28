#!/usr/bin/env bash
#
# Fediverse Year Wrapped
# Fetches posts and generates a beautiful HTML year-in-review report
# Works with any Mastodon-compatible server (Mastodon, GoToSocial, Pleroma, etc.)
#
# Usage: ./wrapped.sh [year] [account@instance] [--skip-ai] [--fetch-only] [--no-fetch]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
[ -f "$SCRIPT_DIR/.env" ] && source "$SCRIPT_DIR/.env"

# Defaults
DEFAULT_YEAR="${DEFAULT_YEAR:-2025}"
OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://localhost:11434}"
OLLAMA_MODEL="${OLLAMA_MODEL:-llama3.1:latest}"
AI_CHUNK_SIZE="${AI_CHUNK_SIZE:-50}"

# Parse arguments
YEAR="$DEFAULT_YEAR"
ACCOUNT=""
SKIP_AI=false
FETCH_ONLY=false
NO_FETCH=false

for arg in "$@"; do
    case $arg in
        --skip-ai) SKIP_AI=true ;;
        --fetch-only) FETCH_ONLY=true ;;
        --no-fetch) NO_FETCH=true ;;
        [0-9][0-9][0-9][0-9]) YEAR="$arg" ;;
        *@*) ACCOUNT="$arg" ;;  # Matches user@instance format
    esac
done

# Get account from toot if not specified
if [ -z "$ACCOUNT" ]; then
    ACCOUNT=$(toot auth 2>/dev/null | grep "ACTIVE" | awk '{print $2}' | head -1)
    if [ -z "$ACCOUNT" ]; then
        echo "❌ No account specified and no active toot session found."
        echo "   Either login with 'toot login' or specify account: ./wrapped.sh 2024 user@instance"
        exit 1
    fi
    echo "📍 Using active toot account: $ACCOUNT"
fi

DATA_FILE="$SCRIPT_DIR/statuses_${YEAR}_${ACCOUNT//@/_}.json"
TEMPLATE="$SCRIPT_DIR/template.html"
AVATAR_DIR="$SCRIPT_DIR/avatars"

# ============================================
# Helper Functions
# ============================================

get_year_colors() {
    case "$1" in
        2022) echo "#ec4899|#db2777" ;;
        2023) echo "#14b8a6|#0d9488" ;;
        2024) echo "#f59e0b|#d97706" ;;
        *) echo "#8b5cf6|#6366f1" ;;
    esac
}

get_ranking() {
    local score=$1
    if [ "$score" -ge 10000 ]; then echo "Top 1%|#ffd700|👑"
    elif [ "$score" -ge 5000 ]; then echo "Top 5%|#c0c0c0|🥈"
    elif [ "$score" -ge 1000 ]; then echo "Top 15%|#cd7f32|🥉"
    elif [ "$score" -ge 500 ]; then echo "Top 30%|#6366f1|⭐"
    elif [ "$score" -ge 100 ]; then echo "Top 50%|#8b5cf6|✨"
    else echo "Growing|#22c55e|🌱"
    fi
}

fmt_num() {
    local n=$1
    if [ "$n" -ge 1000000 ]; then echo "$(echo "scale=1; $n/1000000" | bc)M"
    elif [ "$n" -ge 1000 ]; then echo "$(echo "scale=1; $n/1000" | bc)K"
    else echo "$n"
    fi
}

hex_to_rgba() {
    local hex="${1#\#}"
    printf "rgba(%d, %d, %d, 0.4)" "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

# ============================================
# Fetch Statuses
# ============================================

fetch_statuses() {
    local TEMP="$SCRIPT_DIR/.temp_${YEAR}.json"
    echo "[]" > "$TEMP"
    
    echo "📥 Fetching statuses for $ACCOUNT ($YEAR)..."
    
    local max_id="" page=1
    while true; do
        echo "   Page $page..."
        
        local cmd="toot timelines account $ACCOUNT --json --limit 40 --no-pager"
        [ -n "$max_id" ] && cmd="$cmd --max-id $max_id"
        
        local batch
        batch=$($cmd 2>/dev/null) || { echo "   Error fetching"; break; }
        
        local count=$(echo "$batch" | jq 'length')
        [ "$count" -eq 0 ] && break
        
        local oldest=$(echo "$batch" | jq -r '.[-1].created_at' | cut -d'T' -f1)
        echo "   Got $count (oldest: $oldest)"
        
        # Filter and append
        echo "$batch" | jq --arg y "$YEAR" '[.[] | select(.created_at | startswith($y))]' > "$TEMP.batch"
        jq -s 'add' "$TEMP" "$TEMP.batch" > "$TEMP.new" && mv "$TEMP.new" "$TEMP"
        rm -f "$TEMP.batch"
        
        [[ "$oldest" < "$YEAR" ]] && break
        max_id=$(echo "$batch" | jq -r '.[-1].id')
        ((page++))
        [ $page -gt 200 ] && break
        sleep 0.2
    done
    
    local total=$(jq 'length' "$TEMP")
    echo "📊 Total: $total posts"
    
    if [ "$total" -eq 0 ]; then
        rm -f "$TEMP"
        return 1
    fi
    
    # Save with account info
    jq -n --slurpfile s "$TEMP" '{account: $s[0][0].account, statuses: $s[0]}' > "$DATA_FILE"
    rm -f "$TEMP"
    echo "💾 Saved to $DATA_FILE"
}

# ============================================
# Generate Report
# ============================================

generate_report() {
    echo ""
    echo "🎁 Generating $YEAR Wrapped..."
    
    [ ! -f "$DATA_FILE" ] && { echo "❌ No data file. Run without --no-fetch"; exit 1; }
    [ ! -f "$TEMPLATE" ] && { echo "❌ Missing template.html"; exit 1; }
    
    # Get colors
    local colors=$(get_year_colors "$YEAR")
    local PRIMARY=$(echo "$colors" | cut -d'|' -f1)
    local SECONDARY=$(echo "$colors" | cut -d'|' -f2)
    local GLOW=$(hex_to_rgba "$PRIMARY")
    
    # Extract account info
    local ACCT_NAME=$(jq -r '.account.display_name // "User"' "$DATA_FILE" | sed 's/<[^>]*>//g')
    local ACCT_USER=$(jq -r '.account.username // "user"' "$DATA_FILE")
    local ACCT_AVATAR_URL=$(jq -r '.account.avatar // ""' "$DATA_FILE")
    local ACCT_URL=$(jq -r '.account.url // ""' "$DATA_FILE")
    
    # Use full handle (user@instance)
    local ACCT_HANDLE="$ACCOUNT"
    
    # Download avatar locally
    mkdir -p "$AVATAR_DIR"
    local AVATAR_EXT="${ACCT_AVATAR_URL##*.}"
    [ "$AVATAR_EXT" = "$ACCT_AVATAR_URL" ] && AVATAR_EXT="png"
    AVATAR_EXT="${AVATAR_EXT%%\?*}"  # Remove query params
    local ACCT_AVATAR="avatars/${ACCOUNT//@/_}.$AVATAR_EXT"
    local AVATAR_PATH="$SCRIPT_DIR/$ACCT_AVATAR"
    
    if [ ! -f "$AVATAR_PATH" ] && [ -n "$ACCT_AVATAR_URL" ]; then
        echo "📥 Downloading avatar..."
        curl -sL "$ACCT_AVATAR_URL" -o "$AVATAR_PATH" 2>/dev/null || ACCT_AVATAR="$ACCT_AVATAR_URL"
    fi
    [ ! -f "$AVATAR_PATH" ] && ACCT_AVATAR="$ACCT_AVATAR_URL"
    
    OUTPUT_FILE="$SCRIPT_DIR/wrapped_${YEAR}_${ACCOUNT//@/_}.html"
    
    echo "📊 Analyzing..."
    
    # Compute all stats with jq
    local STATS=$(jq --arg y "$YEAR" '
        # Helper functions
        def hour: split("T")[1][0:2] | tonumber;
        def month: split("-")[1] | tonumber - 1;
        def wday: (split("T")[0] + "T00:00:00Z") | fromdateiso8601 | strftime("%w") | tonumber;
        
        # Filter to year
        [.statuses[] | select(.created_at | startswith($y))] |
        
        # Basic counts
        length as $total |
        if $total == 0 then {total:0,orig:0,reblogs:0,replies:0,media:0,text:0,fav:0,reb:0,rep:0,streak:0,score:0,
          persona:["Newcomer","No posts this year","🌱"],chrono:["Unknown","No data","❓"],
          monthly:[],hourly:[],weekly:[],tags:[],cal:{},topDay:{key:"",value:0},
          topMonth:{n:"",c:0},topHour:{h:0,c:0},top:[],avgw:0,first:null,last:null}
        else
        
        # Store filtered statuses
        . as $posts |
        
        # Counts
        ([$posts[] | select(.reblog == null)] | length) as $orig |
        ([$posts[] | select(.reblog != null)] | length) as $reblogs |
        ([$posts[] | select(.in_reply_to_id != null)] | length) as $replies |
        [$posts[] | select(.reblog == null)] as $op |
        ([$op[] | select(.media_attachments | length > 0)] | length) as $media |
        
        # Engagement
        ([$op[].favourites_count // 0] | add // 0) as $fav |
        ([$op[].reblogs_count // 0] | add // 0) as $reb |
        ([$op[].replies_count // 0] | add // 0) as $rep |
        
        # Streak calculation
        ([$posts[].created_at[0:10]] | unique | sort) as $dates |
        (if ($dates|length) < 2 then ($dates|length)
         else reduce range(1; $dates|length) as $i ({mx:1,cur:1};
           (((($dates[$i]+"T00:00:00Z")|fromdateiso8601) - (($dates[$i-1]+"T00:00:00Z")|fromdateiso8601)) / 86400 | floor) as $diff |
           if $diff == 1 then {mx:([.mx,.cur+1]|max), cur:(.cur+1)} else {mx:.mx, cur:1} end
         ) | .mx end) as $streak |
        
        # Score
        (($reb*2) + $fav + ($total*0.1) + ($streak*5) | floor) as $score |
        
        # Persona
        (if $total == 0 then ["Newcomer","New to the community","🌱"]
         elif ($orig/$total) > 0.6 then ["The Broadcaster","You share your own thoughts","📢"]
         elif ($reblogs/$total) > 0.6 then ["The Curator","You share great content","🎯"]
         elif ($replies/$total) > 0.5 then ["The Socialite","You connect the community","💬"]
         else ["The Balancer","A backbone of the community","⚖️"] end) as $persona |
        
        # Chronotype
        ([$posts[].created_at | hour] | map(select(. >= 0 and . < 5)) | length) as $night |
        ([$posts[].created_at | hour] | map(select(. >= 5 and . < 10)) | length) as $morn |
        ([$posts[].created_at | hour] | map(select(. >= 10 and . < 18)) | length) as $work |
        
        (if $total == 0 then ["The Regular","Regular schedule","☀️"]
         elif ($night/$total) > 0.15 then ["Night Owl","Late night posting","🦉"]
         elif ($morn/$total) > 0.3 then ["Early Bird","Morning activity","🐦"]
         elif ($work/$total) > 0.6 then ["Slacker","Active during work","😏"]
         else ["The Regular","Balanced schedule","☀️"] end) as $chrono |
        
        # Monthly distribution
        (reduce $posts[] as $s (
          [range(12)] | map({n:(["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"][.]), c:0});
          ($s.created_at | month) as $m | .[$m].c += 1
        )) as $monthly |
        ($monthly | sort_by(-.c) | .[0]) as $topMonth |
        
        # Hourly distribution
        (reduce $posts[] as $s (
          [range(24)] | map({h:., c:0});
          ($s.created_at | hour) as $h | .[$h].c += 1
        )) as $hourly |
        ($hourly | sort_by(-.c) | .[0]) as $topHour |
        
        # Weekly distribution
        (reduce $posts[] as $s (
          ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"] | to_entries | map({n:.value, c:0});
          ($s.created_at | wday) as $d | .[$d].c += 1
        )) as $weekly |
        
        # Hashtags
        ([$posts[].tags[]?.name | ascii_downcase] | group_by(.) | map({n:.[0], c:length}) | sort_by(-.c) | .[0:10]) as $tags |
        
        # Calendar
        (reduce $posts[] as $s ({}; ($s.created_at[0:10]) as $d | .[$d] = ((.[$d]//0)+1))) as $cal |
        ($cal | to_entries | sort_by(-.value) | .[0] // {key:"",value:0}) as $topDay |
        
        # Top posts
        ([$op[] | {c:(.content|gsub("<[^>]*>";""))[0:200], f:(.favourites_count//0), r:(.reblogs_count//0), p:(.replies_count//0), d:.created_at, e:((.favourites_count//0)+(.reblogs_count//0)+(.replies_count//0))}] | sort_by(-.e) | .[0:5]) as $top |
        
        # Average words
        (if ($op|length) == 0 then 0 else (([$op[].content | gsub("<[^>]*>";"") | split(" ") | map(select(length>0)) | length] | add // 0) / ($op|length) | floor) end) as $avgw |
        
        # Date range
        ($posts | sort_by(.created_at) | {first: .[0].created_at, last: .[-1].created_at}) as $range |
        
        {
          total:$total, orig:$orig, reblogs:$reblogs, replies:$replies, media:$media, text:($orig-$media),
          fav:$fav, reb:$reb, rep:$rep, streak:$streak, score:$score,
          persona:$persona, chrono:$chrono,
          monthly:$monthly, hourly:$hourly, weekly:$weekly, tags:$tags,
          cal:$cal, topDay:$topDay, topMonth:$topMonth, topHour:$topHour,
          top:$top, avgw:$avgw, first:$range.first, last:$range.last
        }
        end
    ' "$DATA_FILE")
    
    # Extract values
    local TOTAL=$(echo "$STATS" | jq -r '.total')
    local ORIG=$(echo "$STATS" | jq -r '.orig')
    local REBLOGS=$(echo "$STATS" | jq -r '.reblogs')
    local REPLIES=$(echo "$STATS" | jq -r '.replies')
    local FAV=$(echo "$STATS" | jq -r '.fav')
    local REB=$(echo "$STATS" | jq -r '.reb')
    local REP=$(echo "$STATS" | jq -r '.rep')
    local STREAK=$(echo "$STATS" | jq -r '.streak')
    local SCORE=$(echo "$STATS" | jq -r '.score')
    local AVGW=$(echo "$STATS" | jq -r '.avgw')
    
    local P_NAME=$(echo "$STATS" | jq -r '.persona[0]')
    local P_DESC=$(echo "$STATS" | jq -r '.persona[1]')
    local P_EMOJI=$(echo "$STATS" | jq -r '.persona[2]')
    local C_NAME=$(echo "$STATS" | jq -r '.chrono[0]')
    local C_DESC=$(echo "$STATS" | jq -r '.chrono[1]')
    local C_EMOJI=$(echo "$STATS" | jq -r '.chrono[2]')
    
    local TOP_MONTH=$(echo "$STATS" | jq -r '.topMonth.n')
    local TOP_MONTH_C=$(echo "$STATS" | jq -r '.topMonth.c')
    local TOP_HOUR=$(echo "$STATS" | jq -r '.topHour.h')
    local TOP_HOUR_C=$(echo "$STATS" | jq -r '.topHour.c')
    local TOP_DAY=$(echo "$STATS" | jq -r '.topDay.key')
    local TOP_DAY_C=$(echo "$STATS" | jq -r '.topDay.value')
    local FIRST=$(echo "$STATS" | jq -r '.first // ""' | cut -d'T' -f1)
    local LAST=$(echo "$STATS" | jq -r '.last // ""' | cut -d'T' -f1)
    
    echo "   $TOTAL posts, Persona: $P_NAME, Score: $SCORE"
    
    # Ranking
    local RANK=$(get_ranking "$SCORE")
    local R_TIER=$(echo "$RANK" | cut -d'|' -f1)
    local R_COLOR=$(echo "$RANK" | cut -d'|' -f2)
    local R_EMOJI=$(echo "$RANK" | cut -d'|' -f3)
    
    # Generate chart HTML
    local M_MAX=$(echo "$STATS" | jq '[.monthly[].c] | max')
    local MONTHLY_BARS=$(echo "$STATS" | jq -r --arg max "$M_MAX" '.monthly[] | "<div class=\"bar-row\"><span class=\"bar-label\">\(.n)</span><div class=\"bar-container\"><div class=\"bar-fill\" style=\"width: \(if ($max|tonumber) > 0 then (.c * 100 / ($max|tonumber)) else 0 end)%\"></div></div><span class=\"bar-value\">\(.c)</span></div>"' | tr '\n' ' ')
    
    local H_MAX=$(echo "$STATS" | jq '[.hourly[].c] | max')
    local HOURLY_BARS=$(echo "$STATS" | jq -r --arg max "$H_MAX" '.hourly | to_entries | map(select(.key % 2 == 0)) | .[] | "<div class=\"bar-row\"><span class=\"bar-label\">\(.value.h):00</span><div class=\"bar-container\"><div class=\"bar-fill\" style=\"width: \(if ($max|tonumber) > 0 then (.value.c * 100 / ($max|tonumber)) else 0 end)%\"></div></div><span class=\"bar-value\">\(.value.c)</span></div>"' | tr '\n' ' ')
    
    local W_MAX=$(echo "$STATS" | jq '[.weekly[].c] | max')
    local WEEKDAY_BARS=$(echo "$STATS" | jq -r --arg max "$W_MAX" '.weekly[] | "<div class=\"bar-row\"><span class=\"bar-label\">\(.n)</span><div class=\"bar-container\"><div class=\"bar-fill\" style=\"width: \(if ($max|tonumber) > 0 then (.c * 100 / ($max|tonumber)) else 0 end)%\"></div></div><span class=\"bar-value\">\(.c)</span></div>"' | tr '\n' ' ')
    
    local TEXT=$(echo "$STATS" | jq -r '.text')
    local MEDIA=$(echo "$STATS" | jq -r '.media')
    local CONTENT_DIST="<div class=\"pie-item\"><div class=\"pie-color\" style=\"background:#3b82f6\"></div><div class=\"pie-text\"><span class=\"pie-value\">$TEXT</span><span class=\"pie-label\">Text</span></div></div><div class=\"pie-item\"><div class=\"pie-color\" style=\"background:#22c55e\"></div><div class=\"pie-text\"><span class=\"pie-value\">$REBLOGS</span><span class=\"pie-label\">Boosts</span></div></div><div class=\"pie-item\"><div class=\"pie-color\" style=\"background:#f59e0b\"></div><div class=\"pie-text\"><span class=\"pie-value\">$MEDIA</span><span class=\"pie-label\">Media</span></div></div>"
    
    local HASHTAGS=$(echo "$STATS" | jq -r '.tags[] | "<span class=\"hashtag\">#\(.n)<span class=\"hashtag-count\">×\(.c)</span></span>"' | tr '\n' ' ')
    [ -z "$HASHTAGS" ] && HASHTAGS="<span style=\"color:var(--text-muted)\">No hashtags used</span>"
    
    local TOP_POSTS=$(echo "$STATS" | jq -r '.top[] | "<div class=\"top-post\"><div class=\"top-post-content\">\(.c)</div><div class=\"top-post-meta\"><span class=\"meta-item\">❤️ \(.f)</span><span class=\"meta-item\">🔁 \(.r)</span><span class=\"meta-item\">💬 \(.p)</span><span class=\"meta-item\">📅 \(.d[:10])</span></div></div>"' | tr '\n' ' ')
    [ -z "$TOP_POSTS" ] && TOP_POSTS="<p style=\"color:var(--text-muted)\">No posts to display</p>"
    
    # Calendar - generate cells from activity data
    local CALENDAR=$(echo "$STATS" | jq -r --arg y "$YEAR" '
        .cal as $c |
        ([.cal | to_entries[].value] | max // 1) as $mx |
        
        # Get first day of year weekday (0=Sun)
        (($y + "-01-01T00:00:00Z") | fromdateiso8601 | strftime("%w") | tonumber) as $startDay |
        
        # Generate 53 weeks x 7 days grid
        "<div class=\"calendar-grid\">" +
        ([range(371)] | map(
            (. - $startDay) as $dayOfYear |
            if $dayOfYear >= 0 and $dayOfYear < 366 then
                # Calculate date
                (($y | tonumber) as $yr |
                 (if ($yr % 4 == 0 and $yr % 100 != 0) or ($yr % 400 == 0) then 366 else 365 end) as $daysInYear |
                 if $dayOfYear < $daysInYear then
                   # Build date string
                   ($dayOfYear as $d |
                    [31,28,31,30,31,30,31,31,30,31,30,31] as $m |
                    (if $daysInYear == 366 then $m | .[1] = 29 else $m end) as $months |
                    reduce range(12) as $i ({d:$d, month:0};
                      if .d >= $months[$i] then {d:(.d - $months[$i]), month:($i+1)} else . end
                    ) | "\($y)-\(.month+1 | tostring | if length == 1 then "0" + . else . end)-\(.d+1 | tostring | if length == 1 then "0" + . else . end)"
                   ) as $date |
                   ($c[$date] // 0) as $n |
                   (if $n == 0 then 0 elif $n <= ($mx*0.2) then 1 elif $n <= ($mx*0.4) then 2 elif $n <= ($mx*0.6) then 3 elif $n <= ($mx*0.8) then 4 else 5 end) as $lvl |
                   "<div class=\"calendar-cell level-\($lvl)\"></div>"
                 else "" end)
            else "" end
        ) | join("")) + "</div>"
    ')
    
    # AI Section (only if reachable)
    local AI_SECTION=""
    if [ "$SKIP_AI" = false ]; then
        echo "🤖 Checking AI..."
        if curl -s --connect-timeout 3 "$OLLAMA_BASE_URL/api/tags" >/dev/null 2>&1; then
            echo "   AI available, analyzing all posts in chunks..."
            
            # Get all original posts
            local ALL_POSTS=$(jq --arg y "$YEAR" '
                [.statuses[] | select(.reblog == null and (.created_at | startswith($y)))] |
                map(.content | gsub("<[^>]*>";""))
            ' "$DATA_FILE")
            
            local TOTAL_POSTS=$(echo "$ALL_POSTS" | jq 'length')
            local CHUNKS=$(( (TOTAL_POSTS + AI_CHUNK_SIZE - 1) / AI_CHUNK_SIZE ))
            
            echo "   Processing $TOTAL_POSTS posts in $CHUNKS chunk(s)..."
            
            local CHUNK_ANALYSES=""
            local chunk=0
            local TEMP_REQ="$SCRIPT_DIR/.ai_request.json"
            
            while [ $chunk -lt $CHUNKS ]; do
                local start=$((chunk * AI_CHUNK_SIZE))
                local end_idx=$((start + AI_CHUNK_SIZE))
                [ $end_idx -gt $TOTAL_POSTS ] && end_idx=$TOTAL_POSTS
                
                echo "   Chunk $((chunk + 1))/$CHUNKS (posts $((start + 1))-$end_idx)..."
                
                # Build prompt and request via temp file to handle escaping
                local CHUNK_POSTS=$(echo "$ALL_POSTS" | jq -r --argjson s "$start" --argjson n "$AI_CHUNK_SIZE" '.[$s:$s+$n] | join("\n---\n")')
                
                jq -n --arg m "$OLLAMA_MODEL" --arg posts "$CHUNK_POSTS" '{
                    model: $m,
                    prompt: ("Analyze these Fediverse posts. Return ONLY valid JSON:\n{\"themes\":[\"t1\",\"t2\"],\"mood\":\"word\",\"topics\":[\"t1\",\"t2\"],\"traits\":[\"t1\"],\"style\":\"brief\"}\n\nPosts:\n" + $posts),
                    stream: false
                }' > "$TEMP_REQ"
                
                local CHUNK_RESP=$(curl -s --max-time 120 "$OLLAMA_BASE_URL/api/generate" \
                    -d @"$TEMP_REQ" 2>/dev/null | jq -r '.response // empty')
                
                if [ -n "$CHUNK_RESP" ]; then
                    local CLEAN_RESP=$(echo "$CHUNK_RESP" | sed 's/^```json//;s/```$//' | tr -d '\n')
                    if echo "$CLEAN_RESP" | jq . >/dev/null 2>&1; then
                        CHUNK_ANALYSES="${CHUNK_ANALYSES}Chunk $((chunk+1)): ${CLEAN_RESP}\n"
                        echo "      ✓ Got analysis"
                    else
                        echo "      ✗ Invalid JSON"
                    fi
                else
                    echo "      ✗ No response"
                fi
                
                chunk=$((chunk + 1))
            done
            
            rm -f "$TEMP_REQ"
            
            # Synthesize all chunk analyses
            if [ -n "$CHUNK_ANALYSES" ]; then
                echo "   Synthesizing insights from all chunks..."
                
                jq -n --arg m "$OLLAMA_MODEL" --arg analyses "$CHUNK_ANALYSES" --arg total "$TOTAL_POSTS" --arg year "$YEAR" '{
                    model: $m,
                    prompt: ("You analyzed " + $total + " Fediverse posts from " + $year + " in chunks. Here are the analyses:\n\n" + $analyses + "\n\nSynthesize into FINAL analysis. Return ONLY valid JSON:\n{\"mood\":\"one word\",\"mood_desc\":\"2 sentences\",\"persona\":\"creative title\",\"persona_desc\":\"2 sentences\",\"traits\":[\"t1\",\"t2\",\"t3\"],\"passion\":\"main topic\",\"topics\":[\"t1\",\"t2\",\"t3\"],\"tone\":\"word\",\"style\":\"brief desc\",\"narrative\":\"3 sentences about their year\",\"fun_fact\":\"observation\"}"),
                    stream: false
                }' > "$SCRIPT_DIR/.ai_synth.json"
                
                local AI_RESP=$(curl -s --max-time 120 "$OLLAMA_BASE_URL/api/generate" \
                    -d @"$SCRIPT_DIR/.ai_synth.json" 2>/dev/null | jq -r '.response // empty')
                
                rm -f "$SCRIPT_DIR/.ai_synth.json"
                
                if [ -n "$AI_RESP" ]; then
                    local AI_JSON=$(echo "$AI_RESP" | sed 's/^```json//;s/```$//' | tr -d '\n')
                    
                    if echo "$AI_JSON" | jq . >/dev/null 2>&1; then
                        local AI_MOOD=$(echo "$AI_JSON" | jq -r '.mood // "Engaged"')
                        local AI_MOOD_D=$(echo "$AI_JSON" | jq -r '.mood_desc // ""')
                        local AI_PERS=$(echo "$AI_JSON" | jq -r '.persona // "Active"')
                        local AI_PERS_D=$(echo "$AI_JSON" | jq -r '.persona_desc // ""')
                        local AI_TRAITS=$(echo "$AI_JSON" | jq -r '.traits[:5] | map("<span class=\"trait-tag\">\(.)</span>") | join("")')
                        local AI_TONE=$(echo "$AI_JSON" | jq -r '.tone // "Conversational"')
                        local AI_STYLE=$(echo "$AI_JSON" | jq -r '.style // ""')
                        local AI_PASSION=$(echo "$AI_JSON" | jq -r '.passion // "Various"')
                        local AI_TOPICS=$(echo "$AI_JSON" | jq -r '.topics[:4] | map("<span class=\"trait-tag\">\(.)</span>") | join("")')
                        local AI_NARR=$(echo "$AI_JSON" | jq -r '.narrative // ""')
                        local AI_FUN=$(echo "$AI_JSON" | jq -r '.fun_fact // ""')
                        
                        echo "   ✓ Mood: $AI_MOOD, Persona: $AI_PERS"
                        
                        AI_SECTION="<section class=\"ai-insights\">
<h2>🤖 AI-Powered Insights</h2>
<p style=\"color:var(--text-muted);font-size:0.85rem;margin-bottom:1rem;\">Based on analysis of all $TOTAL_POSTS original posts</p>
<div class=\"narrative\">\"$AI_NARR\"</div>
<div class=\"ai-grid\">
<div class=\"ai-card\"><div class=\"ai-card-title\">Emotional Vibe</div><div class=\"ai-card-value\">$AI_MOOD</div><div class=\"ai-card-desc\">$AI_MOOD_D</div></div>
<div class=\"ai-card\"><div class=\"ai-card-title\">AI Persona</div><div class=\"ai-card-value\">$AI_PERS</div><div class=\"ai-card-desc\">$AI_PERS_D</div><div class=\"trait-list\">$AI_TRAITS</div></div>
<div class=\"ai-card\"><div class=\"ai-card-title\">Writing Style</div><div class=\"ai-card-value\">$AI_TONE</div><div class=\"ai-card-desc\">$AI_STYLE</div></div>
<div class=\"ai-card\"><div class=\"ai-card-title\">Passion Topic</div><div class=\"ai-card-value\">$AI_PASSION</div><div class=\"trait-list\">$AI_TOPICS</div></div>
</div>
<div class=\"fun-fact\"><span class=\"fun-fact-icon\">💡</span><span class=\"fun-fact-text\">$AI_FUN</span></div>
</section>"
                    else
                        echo "   AI synthesis invalid, skipping"
                    fi
                else
                    echo "   No synthesis response, skipping"
                fi
            else
                echo "   No chunk analyses succeeded, skipping"
            fi
        else
            echo "   AI not reachable, skipping"
        fi
    else
        echo "⏭️  Skipping AI (--skip-ai)"
    fi
    
    # Fill template
    echo "📝 Generating HTML..."
    
    sed -e "s|{{YEAR}}|$YEAR|g" \
        -e "s|{{PRIMARY_COLOR}}|$PRIMARY|g" \
        -e "s|{{SECONDARY_COLOR}}|$SECONDARY|g" \
        -e "s|{{GLOW_COLOR}}|$GLOW|g" \
        -e "s|{{ACCOUNT_DISPLAY_NAME}}|$ACCT_NAME|g" \
        -e "s|{{ACCOUNT_ACCT}}|$ACCT_HANDLE|g" \
        -e "s|{{ACCOUNT_AVATAR}}|$ACCT_AVATAR|g" \
        -e "s|{{ACCOUNT_URL}}|$ACCT_URL|g" \
        -e "s|{{TOTAL_POSTS}}|$(fmt_num $TOTAL)|g" \
        -e "s|{{ORIGINAL_POSTS}}|$(fmt_num $ORIG)|g" \
        -e "s|{{REBLOGS}}|$(fmt_num $REBLOGS)|g" \
        -e "s|{{REPLIES}}|$(fmt_num $REPLIES)|g" \
        -e "s|{{LONGEST_STREAK}}|$STREAK|g" \
        -e "s|{{AVG_WORDS}}|$AVGW|g" \
        -e "s|{{SOCIAL_IMPACT_SCORE}}|$(fmt_num $SCORE)|g" \
        -e "s|{{RANKING_TIER}}|$R_TIER|g" \
        -e "s|{{RANKING_COLOR}}|$R_COLOR|g" \
        -e "s|{{RANKING_EMOJI}}|$R_EMOJI|g" \
        -e "s|{{TOTAL_FAVORITES}}|$FAV|g" \
        -e "s|{{TOTAL_REBLOGS_RECEIVED}}|$REB|g" \
        -e "s|{{TOTAL_REPLIES_RECEIVED}}|$REP|g" \
        -e "s|{{PERSONA_NAME}}|$P_NAME|g" \
        -e "s|{{PERSONA_DESC}}|$P_DESC|g" \
        -e "s|{{PERSONA_EMOJI}}|$P_EMOJI|g" \
        -e "s|{{CHRONOTYPE_NAME}}|$C_NAME|g" \
        -e "s|{{CHRONOTYPE_DESC}}|$C_DESC|g" \
        -e "s|{{CHRONOTYPE_EMOJI}}|$C_EMOJI|g" \
        -e "s|{{MOST_ACTIVE_MONTH}}|$TOP_MONTH|g" \
        -e "s|{{MOST_ACTIVE_MONTH_COUNT}}|$TOP_MONTH_C|g" \
        -e "s|{{BUSIEST_HOUR}}|$TOP_HOUR|g" \
        -e "s|{{BUSIEST_HOUR_COUNT}}|$TOP_HOUR_C|g" \
        -e "s|{{MOST_ACTIVE_DAY}}|$TOP_DAY|g" \
        -e "s|{{MOST_ACTIVE_COUNT}}|$TOP_DAY_C|g" \
        -e "s|{{FIRST_POST}}|$FIRST|g" \
        -e "s|{{LAST_POST}}|$LAST|g" \
        "$TEMPLATE" > "$OUTPUT_FILE.tmp"
    
    # Replace multiline sections using temp files (awk can't handle newlines in -v)
    replace_placeholder() {
        local placeholder="$1"
        local content="$2"
        local tmpfile="$SCRIPT_DIR/.placeholder_content"
        echo "$content" > "$tmpfile"
        # Use perl for multiline replacement
        perl -i -pe "BEGIN{undef \$/; open(F,'$tmpfile'); \$r=<F>; chomp \$r;} s/\Q{{$placeholder}}\E/\$r/g" "$OUTPUT_FILE.tmp"
        rm -f "$tmpfile"
    }
    
    replace_placeholder "MONTHLY_BARS" "$MONTHLY_BARS"
    replace_placeholder "HOURLY_BARS" "$HOURLY_BARS"
    replace_placeholder "WEEKDAY_BARS" "$WEEKDAY_BARS"
    replace_placeholder "CONTENT_DIST" "$CONTENT_DIST"
    replace_placeholder "HASHTAGS_HTML" "$HASHTAGS"
    replace_placeholder "TOP_POSTS_HTML" "$TOP_POSTS"
    replace_placeholder "CALENDAR_HTML" "$CALENDAR"
    replace_placeholder "AI_SECTION" "$AI_SECTION"
    
    mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
    
    echo ""
    echo "✨ Report: $OUTPUT_FILE"
}

# ============================================
# Main
# ============================================

echo ""
echo "╔══════════════════════════════════════╗"
echo "║            fedi-wrap 🎁               ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "Account: $ACCOUNT"
echo "Year: $YEAR"

[ "$NO_FETCH" = false ] && { fetch_statuses || exit 1; }
[ "$FETCH_ONLY" = false ] && generate_report

echo ""
echo "🎉 Done!"
