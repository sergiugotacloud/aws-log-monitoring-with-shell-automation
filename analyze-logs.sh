#!/bin/bash

# =========================
# CONFIGURATION
# =========================
LOG_DIR="$HOME/logs"
REPORT_FILE="$HOME/logs/log_analysis_report.txt"
ERROR_PATTERNS=("ERROR" "FATAL" "CRITICAL")
THRESHOLD=10

# =========================
# INIT REPORT
# =========================
echo "Log Analysis Report" > "$REPORT_FILE"
echo "======================" >> "$REPORT_FILE"

echo -e "\nLog files modified in last 24h:" >> "$REPORT_FILE"
LOG_FILES=$(find "$LOG_DIR" -name "*.log" -mtime -1)
echo "$LOG_FILES" >> "$REPORT_FILE"

# =========================
# PROCESS LOG FILES
# =========================
for LOG_FILE in $LOG_FILES; do

    echo -e "\n===================================" >> "$REPORT_FILE"
    echo "Processing: $LOG_FILE" >> "$REPORT_FILE"
    echo "===================================" >> "$REPORT_FILE"

    for PATTERN in "${ERROR_PATTERNS[@]}"; do

        echo -e "\nChecking: $PATTERN" >> "$REPORT_FILE"

        # Print matching lines
        grep "$PATTERN" "$LOG_FILE" >> "$REPORT_FILE"

        # Count occurrences
        COUNT=$(grep -c "$PATTERN" "$LOG_FILE")
        echo "Count: $COUNT" >> "$REPORT_FILE"

        # ALERT LOGIC
        if [ "$COUNT" -gt "$THRESHOLD" ]; then
            echo "WARNING: High number of $PATTERN in $LOG_FILE" >> "$REPORT_FILE"
            echo "ALERT: $PATTERN issue detected in $LOG_FILE"
        fi

    done

done

# =========================
# FINAL OUTPUT
# =========================
echo -e "\nLog analysis completed."
echo "Report saved at: $REPORT_FILE"
