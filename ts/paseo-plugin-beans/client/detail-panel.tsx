import type { PluginWorkspacePanelProps } from "@getpaseo/plugin/client";
import { copyText, Icon, Loading, Markdown, ScrollView, useToast } from "@getpaseo/plugin/client/ui";
import { Pressable, StyleSheet, Text, View } from "react-native";
import type { BeanDetail, BeanRef } from "../shared/rpc.ts";
import { PriorityIcon, Tags, TypeBadge, TypeIcon, type Colors } from "./badges.tsx";
import { select, useSelection } from "./selection.ts";
import { useBean } from "./use-polled.ts";

const UNITS: [number, string][] = [
  [365 * 24 * 3600, "y"],
  [30 * 24 * 3600, "mo"],
  [7 * 24 * 3600, "w"],
  [24 * 3600, "d"],
  [3600, "h"],
  [60, "m"],
];

// Short and relative, like "3d ago": the footer is a glance, not a record.
function ago(iso: string, now: number): string {
  const time = Date.parse(iso);
  if (Number.isNaN(time)) return iso;
  const seconds = Math.max(0, (now - time) / 1000);
  for (const [size, unit] of UNITS) {
    if (seconds >= size) return `${Math.floor(seconds / size)}${unit} ago`;
  }
  return "just now";
}

function Hint({ text, colors }: { text: string; colors: Colors }) {
  return (
    <View style={[styles.fill, styles.center, { backgroundColor: colors.surface0 }]}>
      <Text style={[styles.hint, { color: colors.foregroundMuted }]}>{text}</Text>
    </View>
  );
}

function CopyId({ id, colors }: { id: string; colors: Colors }) {
  const toast = useToast();
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`Copy ${id}`}
      onPress={() =>
        copyText(id).then(
          () => toast.show(`Copied ${id}`, { variant: "success" }),
          () => toast.error(`Couldn't copy ${id}`),
        )
      }
      style={styles.copy}
    >
      <Text style={[styles.small, styles.italic, { color: colors.foregroundMuted }]}>{id}</Text>
      <Icon name="Copy" size={12} color={colors.foregroundMuted} />
    </Pressable>
  );
}

function Relations({
  title,
  beans,
  onSelect,
  colors,
}: {
  title: string;
  beans: readonly BeanRef[];
  onSelect(beanId: string): void;
  colors: Colors;
}) {
  if (beans.length === 0) return null;
  return (
    <View style={styles.section}>
      <Text style={[styles.sectionTitle, { color: colors.foregroundMuted }]}>{title}</Text>
      {beans.map((bean) => (
        <Pressable
          key={bean.id}
          accessibilityRole="button"
          onPress={() => onSelect(bean.id)}
          style={[styles.row, { borderColor: colors.border, backgroundColor: colors.surface1 }]}
        >
          <TypeIcon type={bean.type} />
          <Text style={[styles.rowTitle, { color: colors.foreground }]} numberOfLines={1}>
            {bean.title}
          </Text>
          <Text style={[styles.small, { color: colors.foregroundMuted }]}>{bean.status}</Text>
          <Icon name="ChevronRight" size={14} color={colors.foregroundMuted} />
        </Pressable>
      ))}
    </View>
  );
}

function Detail({
  bean,
  onSelect,
  colors,
}: {
  bean: BeanDetail;
  onSelect(beanId: string): void;
  colors: Colors;
}) {
  const status = bean.implicitStatus
    ? `${bean.status} (${bean.implicitStatus} via ancestor)`
    : bean.status;
  return (
    <ScrollView contentContainerStyle={styles.content}>
      <Text style={[styles.title, { color: colors.foreground }]}>{bean.title}</Text>
      <CopyId id={bean.id} colors={colors} />
      <View style={styles.meta}>
        <TypeBadge type={bean.type} />
        <Text style={[styles.small, { color: colors.foreground }]}>{status}</Text>
        <PriorityIcon priority={bean.priority} colors={colors} />
        {bean.priority !== "normal" && (
          <Text style={[styles.small, { color: colors.foregroundMuted }]}>{bean.priority}</Text>
        )}
      </View>
      <Tags tags={bean.tags} colors={colors} />
      <Relations
        title="Parent"
        beans={bean.parent ? [bean.parent] : []}
        onSelect={onSelect}
        colors={colors}
      />
      <Relations title="Blocked by" beans={bean.blockedBy} onSelect={onSelect} colors={colors} />
      <Relations title="Children" beans={bean.children} onSelect={onSelect} colors={colors} />
      {bean.body.trim() !== "" && (
        <View style={[styles.section, styles.body, { borderColor: colors.border }]}>
          <Markdown>{bean.body}</Markdown>
        </View>
      )}
      <View style={[styles.footer, { borderColor: colors.border }]}>
        <Text style={[styles.small, { color: colors.foregroundMuted }]}>
          updated {ago(bean.updatedAt, Date.now())} · created {ago(bean.createdAt, Date.now())}
        </Text>
      </View>
    </ScrollView>
  );
}

function Selected({
  workspaceId,
  beanId,
  colors,
}: {
  workspaceId: string;
  beanId: string;
  colors: Colors;
}) {
  const { data, error, refresh } = useBean(workspaceId, beanId);
  const onSelect = (id: string) => select(workspaceId, id);

  // A ternary, not `&&`: an empty string would render bare text, which crashes
  // React Native.
  const banner = error ? (
    <View style={[styles.banner, { borderColor: colors.statusDanger }]}>
      <Text style={[styles.bannerText, { color: colors.statusDanger }]}>{error}</Text>
      <Pressable accessibilityRole="button" onPress={refresh}>
        <Text style={{ color: colors.accent }}>Retry</Text>
      </Pressable>
    </View>
  ) : null;

  let content;
  if (!data) content = error ? null : <Loading />;
  else if (data.kind === "none")
    content = <Hint text={`No beans project in ${data.directory}`} colors={colors} />;
  // The selection stays put, so the bean reappears if it comes back (a branch switch).
  else if (!data.bean) content = <Hint text={`Bean ${beanId} not found`} colors={colors} />;
  else content = <Detail bean={data.bean} onSelect={onSelect} colors={colors} />;

  return (
    <View style={[styles.fill, { backgroundColor: colors.surface0 }]}>
      {banner}
      {content}
    </View>
  );
}

export function DetailPanel({ workspaceId, theme }: PluginWorkspacePanelProps) {
  const beanId = useSelection(workspaceId);
  if (!beanId) {
    return <Hint text="Pick a card on the Beans board to see it here." colors={theme.colors} />;
  }
  // Keyed so a new selection starts clean rather than painting the old bean once.
  return (
    <Selected key={beanId} workspaceId={workspaceId} beanId={beanId} colors={theme.colors} />
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1 },
  center: { alignItems: "center", justifyContent: "center", padding: 24 },
  hint: { textAlign: "center" },
  content: { padding: 12, gap: 10 },
  title: { fontSize: 16, fontWeight: "600" },
  meta: { flexDirection: "row", flexWrap: "wrap", alignItems: "center", gap: 8 },
  small: { fontSize: 11 },
  italic: { fontStyle: "italic" },
  copy: { flexDirection: "row", alignItems: "center", gap: 4, alignSelf: "flex-start" },
  section: { gap: 4 },
  sectionTitle: { fontSize: 11, fontWeight: "600", textTransform: "uppercase" },
  row: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    borderWidth: 1,
    borderRadius: 6,
    paddingHorizontal: 8,
    paddingVertical: 6,
  },
  rowTitle: { flex: 1 },
  body: { borderTopWidth: 1, paddingTop: 10 },
  footer: {
    flexDirection: "row",
    flexWrap: "wrap",
    justifyContent: "space-between",
    gap: 8,
    borderTopWidth: 1,
    paddingTop: 8,
    marginTop: 8,
  },
  banner: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
    margin: 12,
    padding: 8,
    borderWidth: 1,
    borderRadius: 6,
  },
  bannerText: { flex: 1 },
});
