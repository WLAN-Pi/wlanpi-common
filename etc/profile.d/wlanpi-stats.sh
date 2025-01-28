# Run wlanpi-stats for SSH sessions only
if [ -n "$SSH_TTY" ] && [ -z "$WLANPI_STATS_RUN" ]; then
    export WLANPI_STATS_RUN=1
    wlanpi-stats
fi