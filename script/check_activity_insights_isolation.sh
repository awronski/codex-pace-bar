#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if grep -R -n -E 'CodexActivityInsights(Core|Mac)|ActivityInsights(Repository|ShadowController|LaunchAgentManager|ConfigurationStore)' \
  Sources/CodexPaceBarCore \
  Sources/CodexPaceBarAppSupport \
  Sources/CodexPaceBar; then
  echo "Activity Insights isolation failed: Pace Bar imports collector, storage, analysis, or control code." >&2
  exit 1
fi

if grep -R -n -E 'CodexActivityInsights(Core|Mac)' Sources/CodexActivityInsightsChartAdapter; then
  echo "Activity Insights isolation failed: the chart adapter is not contract-only." >&2
  exit 1
fi

if grep -R -n -E 'CodexActivityInsights(Core|Mac|Contract|ChartAdapter)' Sources/CodexActivityInsightsControlAdapter; then
  echo "Activity Insights isolation failed: the control adapter is not process-only." >&2
  exit 1
fi

test "$(grep -F -c 'ActivityInsightsChartRow()' Sources/CodexPaceBar/Views/PopoverView.swift)" = "1"

echo "activity_insights_isolation PASS"
