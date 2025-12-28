#!/bin/bash
# Fetch all statuses from GoToSocial using toot CLI for a specific year
# Usage: ./fetch_statuses.sh [year]

ACCOUNT="anant@anantshri.info"
YEAR="${1:-2025}"
OUTPUT_FILE="statuses_${YEAR}.json"
TEMP_FILE="statuses_temp_${YEAR}.json"
START_DATE="${YEAR}-01-01"
END_DATE="${YEAR}-12-31"

echo "Fetching statuses for $ACCOUNT for year $YEAR..."

# Initialize - start with empty array
echo "[]" > "$TEMP_FILE"

max_id=""
page=1

while true; do
    echo "Fetching page $page..."
    
    # Build the command with optional max_id for pagination
    if [ -z "$max_id" ]; then
        statuses=$(toot timelines account "$ACCOUNT" --json --limit 40 --no-pager 2>/dev/null)
    else
        statuses=$(toot timelines account "$ACCOUNT" --json --limit 40 --max-id "$max_id" --no-pager 2>/dev/null)
    fi
    
    # Check if we got any results
    count=$(echo "$statuses" | jq 'length')
    if [ "$count" -eq 0 ]; then
        echo "No more statuses found."
        break
    fi
    
    echo "  Got $count statuses"
    
    # Get the date range of this batch
    newest_date=$(echo "$statuses" | jq -r '.[0].created_at' | cut -d'T' -f1)
    oldest_date=$(echo "$statuses" | jq -r '.[-1].created_at' | cut -d'T' -f1)
    echo "  Date range: $oldest_date to $newest_date"
    
    # Filter statuses for the target year
    year_statuses=$(echo "$statuses" | jq --arg start "$START_DATE" --arg end "$END_DATE" '
        [.[] | select(.created_at >= ($start + "T00:00:00") and .created_at <= ($end + "T23:59:59"))]
    ')
    
    year_count=$(echo "$year_statuses" | jq 'length')
    echo "  $year_count statuses from $YEAR"
    
    # Append to temp file using file-based approach
    if [ "$year_count" -gt 0 ]; then
        # Read existing, merge, write back
        jq -s 'add' "$TEMP_FILE" <(echo "$year_statuses") > "${TEMP_FILE}.new"
        mv "${TEMP_FILE}.new" "$TEMP_FILE"
    fi
    
    # Check if we've gone past the target year (found older statuses)
    if [[ "$oldest_date" < "$START_DATE" ]]; then
        echo "Reached statuses older than $YEAR, stopping."
        break
    fi
    
    # Get the last status ID for pagination
    max_id=$(echo "$statuses" | jq -r '.[-1].id')
    
    ((page++))
    
    # Safety limit
    if [ $page -gt 200 ]; then
        echo "Reached page limit, stopping."
        break
    fi
    
    # Small delay to be nice to the server
    sleep 0.2
done

# Get total count
final_count=$(jq 'length' "$TEMP_FILE")
echo ""
echo "Total $YEAR statuses collected: $final_count"

if [ "$final_count" -eq 0 ]; then
    echo "No statuses found for $YEAR"
    rm -f "$TEMP_FILE"
    exit 1
fi

# Get account info from the first status in the temp file
account_file="account_temp_${YEAR}.json"
jq '.[0].account' "$TEMP_FILE" > "$account_file"

# Create the final output using files
jq -n --slurpfile statuses "$TEMP_FILE" --slurpfile account "$account_file" \
    '{account: $account[0], statuses: $statuses[0]}' > "$OUTPUT_FILE"

# Cleanup
rm -f "$TEMP_FILE" "$account_file"

echo "Saved to $OUTPUT_FILE"
