import type { PluginHostProps } from "@getpaseo/plugin/client";
import { Icon } from "@getpaseo/plugin/client/ui";
import { StyleSheet, Text, View } from "react-native";

export type Colors = PluginHostProps["theme"]["colors"];

// Fixed hues rather than theme colours, so a type reads the same on every theme;
// the theme supplies only four status colours, too few to tell types apart.
const TYPE_STYLES: Record<string, { icon: string; color: string }> = {
  task: { icon: "SquareCheck", color: "#3b82f6" },
  bug: { icon: "Bug", color: "#ef4444" },
  feature: { icon: "Sparkles", color: "#22c55e" },
  epic: { icon: "Layers", color: "#a855f7" },
  milestone: { icon: "Flag", color: "#f59e0b" },
};
const OTHER_TYPE = { icon: "Circle", color: "#94a3b8" };

export function typeColor(type: string): string {
  return (TYPE_STYLES[type] ?? OTHER_TYPE).color;
}

/** Just the coloured icon, for compact rows; the label goes to accessibility. */
export function TypeIcon({ type }: { type: string }) {
  const style = TYPE_STYLES[type] ?? OTHER_TYPE;
  return (
    <View accessibilityLabel={type}>
      <Icon name={style.icon} size={14} color={style.color} />
    </View>
  );
}

export function TypeBadge({ type }: { type: string }) {
  const style = TYPE_STYLES[type] ?? OTHER_TYPE;
  return (
    <View style={[styles.typeBadge, { backgroundColor: `${style.color}22` }]}>
      <Icon name={style.icon} size={12} color={style.color} />
      <Text style={[styles.small, styles.typeLabel, { color: style.color }]}>{type}</Text>
    </View>
  );
}

const PRIORITY_ICONS: Record<string, { name: string; color: (colors: Colors) => string }> = {
  critical: { name: "ChevronsUp", color: (colors) => colors.statusDanger },
  high: { name: "ChevronUp", color: (colors) => colors.statusWarning },
  low: { name: "ChevronDown", color: (colors) => colors.foregroundMuted },
  deferred: { name: "ChevronsDown", color: (colors) => colors.foregroundMuted },
};

/** Nothing for normal priority, so only the beans that differ stand out. */
export function PriorityIcon({ priority, colors }: { priority: string; colors: Colors }) {
  const icon = PRIORITY_ICONS[priority];
  if (!icon) return null;
  return (
    <View accessibilityLabel={`${priority} priority`}>
      <Icon name={icon.name} size={16} color={icon.color(colors)} />
    </View>
  );
}

export function Tags({ tags, colors }: { tags: readonly string[]; colors: Colors }) {
  if (tags.length === 0) return null;
  return (
    <View style={styles.tags}>
      {tags.map((tag) => (
        <Text
          key={tag}
          style={[styles.small, styles.tag, { color: colors.foregroundMuted, borderColor: colors.border }]}
        >
          {tag}
        </Text>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  typeBadge: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
    borderRadius: 4,
    paddingHorizontal: 6,
    paddingVertical: 2,
  },
  typeLabel: { fontWeight: "600" },
  tags: { flexDirection: "row", flexWrap: "wrap", gap: 4 },
  tag: { borderWidth: 1, borderRadius: 999, paddingHorizontal: 6, paddingVertical: 1 },
  small: { fontSize: 11 },
});
