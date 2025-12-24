#!/bin/bash
# Continuous Test Monitoring Script
# Monitors test execution and logs critical issues

LOG_DIR="/tmp/sanevideo_monitoring"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/monitor_${TIMESTAMP}.log"
ERROR_LOG="$LOG_DIR/errors_${TIMESTAMP}.log"
WARNING_LOG="$LOG_DIR/warnings_${TIMESTAMP}.log"

echo "🔍 Starting test monitoring at $(date)" | tee -a "$LOG_FILE"

# Monitor for critical patterns
monitor_patterns() {
    local input_file="$1"
    
    # Permission issues
    grep -iE "permission|tcc|denied|granted|camera.*access|microphone.*access|screen.*recording" "$input_file" >> "$ERROR_LOG" 2>/dev/null
    
    # Crashes
    grep -iE "signal.*11|signal.*9|segfault|exc_bad_access|crash|killed|abort" "$input_file" >> "$ERROR_LOG" 2>/dev/null
    
    # Memory issues
    grep -iE "memory.*leak|retain.*cycle|memory.*pressure|out.*of.*memory" "$input_file" >> "$ERROR_LOG" 2>/dev/null
    
    # Concurrency issues
    grep -iE "actor.*isolat|race.*condition|data.*race|sendable|main.*actor" "$input_file" >> "$WARNING_LOG" 2>/dev/null
    
    # Window issues
    grep -iE "window.*nil|pip.*window|restore.*window|zombie.*window" "$input_file" >> "$ERROR_LOG" 2>/dev/null
    
    # Security scope issues
    grep -iE "security.*scope|file.*access.*denied|bookmark.*invalid" "$input_file" >> "$ERROR_LOG" 2>/dev/null
    
    # Test failures
    grep -iE "test.*failed|test.*error|assertion.*failed" "$input_file" >> "$ERROR_LOG" 2>/dev/null
}

# Run tests with monitoring
run_tests_with_monitoring() {
    echo "🧪 Running test suite..." | tee -a "$LOG_FILE"
    
    cd /Users/sj/SaneVideo || exit 1
    
    # Run diagnostics first
    echo "📊 Running diagnostics..." | tee -a "$LOG_FILE"
    ./Scripts/SaneMaster.rb diagnose --dump 2>&1 | tee -a "$LOG_FILE" | monitor_patterns /dev/stdin
    
    # Run tests
    echo "▶️  Running tests..." | tee -a "$LOG_FILE"
    xcodebuild test \
        -scheme SaneVideo \
        -destination 'platform=macOS,arch=arm64' \
        2>&1 | tee -a "$LOG_FILE" | monitor_patterns /dev/stdin
    
    # Analyze results
    echo "📈 Analyzing results..." | tee -a "$LOG_FILE"
    
    # Count errors
    ERROR_COUNT=$(wc -l < "$ERROR_LOG" 2>/dev/null || echo "0")
    WARNING_COUNT=$(wc -l < "$WARNING_LOG" 2>/dev/null || echo "0")
    
    echo "⚠️  Found $ERROR_COUNT errors and $WARNING_COUNT warnings" | tee -a "$LOG_FILE"
    
    # Generate summary
    echo "" >> "$LOG_FILE"
    echo "=== ERROR SUMMARY ===" >> "$LOG_FILE"
    if [ -f "$ERROR_LOG" ] && [ -s "$ERROR_LOG" ]; then
        cat "$ERROR_LOG" >> "$LOG_FILE"
    else
        echo "No errors found" >> "$LOG_FILE"
    fi
    
    echo "" >> "$LOG_FILE"
    echo "=== WARNING SUMMARY ===" >> "$LOG_FILE"
    if [ -f "$WARNING_LOG" ] && [ -s "$WARNING_LOG" ]; then
        cat "$WARNING_LOG" >> "$LOG_FILE"
    else
        echo "No warnings found" >> "$LOG_FILE"
    fi
}

# Continuous monitoring loop
continuous_monitor() {
    while true; do
        # Check for running processes
        if pgrep -f "xcodebuild.*test" > /dev/null; then
            echo "⏳ Tests still running..." | tee -a "$LOG_FILE"
        else
            echo "✅ Tests completed, analyzing..." | tee -a "$LOG_FILE"
            run_tests_with_monitoring
            break
        fi
        sleep 30
    done
}

# Main execution
if [ "$1" == "--continuous" ]; then
    continuous_monitor
else
    run_tests_with_monitoring
fi

echo "🏁 Monitoring complete at $(date)" | tee -a "$LOG_FILE"
echo "📁 Logs saved to: $LOG_DIR" | tee -a "$LOG_FILE"

