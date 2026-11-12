import type { PluginTimelineItemProps } from "@getpaseo/plugin/client";
import { Icon } from "@getpaseo/plugin/client/ui";
import { useEffect, useState } from "react";
import { StyleSheet, Text, View } from "react-native";
import type { StatusRow } from "../shared/status.ts";
import { formatAge } from "../shared/age.ts";

const TICK_MS = 30_000;

type Status = Exclude<StatusRow, { superseded: true }>;
type Colors = PluginTimelineItemProps["theme"]["colors"];

function useNow(): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), TICK_MS);
    return () => clearInterval(timer);
  }, []);
  return now;
}

function StatusCard({ status, colors }: { status: Status; colors: Colors }) {
  const now = useNow();
  return (
    <View style={[styles.card, { backgroundColor: colors.surface1, borderColor: colors.border }]}>
      <View style={styles.row}>
        <Icon name="Activity" size={14} color={colors.accent} />
        <Text style={[styles.summary, { color: colors.foreground }]} numberOfLines={2}>
          {status.summary}
        </Text>
        <Text style={[styles.age, { color: colors.foregroundMuted }]}>{formatAge(now - status.setAt)}</Text>
      </View>
      {status.waitingOn ? (
        <View style={styles.row}>
          <Icon name="Hourglass" size={12} color={colors.statusWarning} />
          <Text style={[styles.waiting, { color: colors.statusWarning }]} numberOfLines={2}>
            Waiting on {status.waitingOn}
          </Text>
        </View>
      ) : null}
    </View>
  );
}

export function StatusCardView({ item, theme }: PluginTimelineItemProps<StatusRow>) {
  if ("superseded" in item.data) return null;
  return <StatusCard status={item.data} colors={theme.colors} />;
}

const styles = StyleSheet.create({
  card: {
    gap: 4,
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 10,
    paddingVertical: 8,
  },
  // Icons sit on the first line of text rather than centring on a wrapped block.
  row: { flexDirection: "row", alignItems: "flex-start", gap: 8 },
  summary: { fontSize: 13, fontWeight: "600", lineHeight: 18, flex: 1 },
  age: { fontSize: 11, lineHeight: 18 },
  waiting: { fontSize: 12, fontWeight: "500", lineHeight: 16, flex: 1 },
});
