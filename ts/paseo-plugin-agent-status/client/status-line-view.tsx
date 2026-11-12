import type { PluginTimelineItemProps } from "@getpaseo/plugin/client";
import { useEffect, useState } from "react";
import { StyleSheet, Text } from "react-native";
import type { StatusRow } from "../shared/status.ts";
import { formatStatusLine } from "../shared/status-line.ts";

const TICK_MS = 30_000;

function useNow(): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), TICK_MS);
    return () => clearInterval(timer);
  }, []);
  return now;
}

function CurrentStatus({ status, color }: { status: Exclude<StatusRow, { superseded: true }>; color: string }) {
  const now = useNow();
  return (
    <Text style={[styles.line, { color }]} numberOfLines={1}>
      {formatStatusLine(status, now)}
    </Text>
  );
}

export function StatusLineView({ item, theme }: PluginTimelineItemProps<StatusRow>) {
  if ("superseded" in item.data) return null;
  return <CurrentStatus status={item.data} color={theme.colors.foregroundMuted} />;
}

const styles = StyleSheet.create({
  line: { fontStyle: "italic", fontSize: 13 },
});
