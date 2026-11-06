import { useTabState, type PluginWorkspacePanelProps } from "@getpaseo/plugin/client";
import { Icon, Loading, ScrollView } from "@getpaseo/plugin/client/ui";
import { Pressable, StyleSheet, Switch, Text, View } from "react-native";
import { z } from "zod";
import { laneKey, layout, NO_EPIC_GROUP, type Lane } from "../shared/layout.ts";
import type { BoardBean } from "../shared/rpc.ts";
import { useBoard } from "./use-board.ts";

type Colors = PluginWorkspacePanelProps["theme"]["colors"];

const TabState = z.object({
  showScrapped: z.boolean(),
  /** Lane key → collapsed, only for lanes the user has toggled. */
  collapsed: z.record(z.string(), z.boolean()),
});
type TabState = z.infer<typeof TabState>;
const DEFAULT_TAB_STATE: TabState = { showScrapped: false, collapsed: {} };

const COLUMN_TITLES: Record<string, string> = {
  draft: "Draft",
  todo: "Todo",
  "in-progress": "In progress",
  completed: "Completed",
  scrapped: "Scrapped",
};

// Fixed hues rather than theme colours, so a type reads the same on every theme;
// the theme supplies only four status colours, too few to tell types apart.
const TYPE_STYLES: Record<string, { icon: string; color: string }> = {
  task: { icon: "SquareCheck", color: "#3b82f6" },
  bug: { icon: "Bug", color: "#ef4444" },
  feature: { icon: "Sparkles", color: "#22c55e" },
};
const OTHER_TYPE = { icon: "Circle", color: "#94a3b8" };

// Normal priority gets no icon, so only the beans that differ stand out.
function priorityIcon(priority: string, colors: Colors): { name: string; color: string } | null {
  switch (priority) {
    case "critical":
      return { name: "ChevronsUp", color: colors.statusDanger };
    case "high":
      return { name: "ChevronUp", color: colors.statusWarning };
    case "low":
      return { name: "ChevronDown", color: colors.foregroundMuted };
    case "deferred":
      return { name: "ChevronsDown", color: colors.foregroundMuted };
    default:
      return null;
  }
}

function Card({ bean, colors }: { bean: BoardBean; colors: Colors }) {
  const type = TYPE_STYLES[bean.type] ?? OTHER_TYPE;
  const priority = priorityIcon(bean.priority, colors);
  return (
    <View style={[styles.card, { backgroundColor: colors.surface1, borderColor: colors.border }]}>
      <Text style={[styles.cardTitle, { color: colors.foreground }]}>{bean.title}</Text>
      <View style={styles.cardRow}>
        <View style={[styles.typeBadge, { backgroundColor: `${type.color}22` }]}>
          <Icon name={type.icon} size={12} color={type.color} />
          <Text style={[styles.small, styles.typeLabel, { color: type.color }]}>{bean.type}</Text>
        </View>
        <View style={styles.cardIcons}>
          {bean.blocked && (
            <View style={styles.inline} accessibilityLabel="Blocked">
              <Icon name="Ban" size={12} color={colors.statusDanger} />
              <Text style={[styles.small, { color: colors.statusDanger }]}>blocked</Text>
            </View>
          )}
          {priority && (
            <View accessibilityLabel={`${bean.priority} priority`}>
              <Icon name={priority.name} size={16} color={priority.color} />
            </View>
          )}
        </View>
      </View>
      {bean.tags.length > 0 && (
        <View style={styles.tags}>
          {bean.tags.map((tag) => (
            <Text
              key={tag}
              style={[styles.small, styles.tag, { color: colors.foregroundMuted, borderColor: colors.border }]}
            >
              {tag}
            </Text>
          ))}
        </View>
      )}
      <Text style={[styles.small, styles.cardId, { color: colors.foregroundMuted }]}>{bean.id}</Text>
    </View>
  );
}

function LaneView({
  lane,
  collapsed,
  onToggle,
  colors,
}: {
  lane: Lane;
  collapsed: boolean;
  onToggle(): void;
  colors: Colors;
}) {
  const count = lane.cells.reduce((sum, cell) => sum + cell.cards.length, 0);
  return (
    <View style={[styles.lane, { borderColor: colors.border }]}>
      <Pressable accessibilityRole="button" onPress={onToggle} style={styles.laneHeader}>
        <Icon
          name={collapsed ? "ChevronRight" : "ChevronDown"}
          size={16}
          color={colors.foregroundMuted}
        />
        <Text style={[styles.laneTitle, { color: colors.foreground }]} numberOfLines={1}>
          {lane.epic ? lane.epic.title : "No epic"}
        </Text>
        {lane.epic && (
          <Text style={[styles.small, { color: colors.foregroundMuted }]}>
            {lane.epic.id}
          </Text>
        )}
        <Text style={[styles.small, { color: colors.foregroundMuted }]}>{count}</Text>
      </Pressable>
      {!collapsed && (
        <ScrollView horizontal contentContainerStyle={styles.columns}>
          {lane.cells.map((cell) => (
            <View key={cell.column} style={styles.column}>
              <Text style={[styles.columnTitle, { color: colors.foregroundMuted }]}>
                {COLUMN_TITLES[cell.column] ?? cell.column} · {cell.cards.length}
              </Text>
              {cell.cards.map((bean) => (
                <Card key={bean.id} bean={bean} colors={colors} />
              ))}
            </View>
          ))}
        </ScrollView>
      )}
    </View>
  );
}

export function BoardPanel({ workspaceId, tab, theme }: PluginWorkspacePanelProps) {
  const { colors } = theme;
  const { board, error, refresh } = useBoard(workspaceId);
  const [state, setState] = useTabState(tab, TabState, DEFAULT_TAB_STATE);

  const toolbar = (
    <View style={[styles.toolbar, { borderColor: colors.border }]}>
      <View style={styles.toggle}>
        <Switch
          value={state.showScrapped}
          onValueChange={(showScrapped) => setState({ ...state, showScrapped })}
        />
        <Text style={{ color: colors.foreground }}>Show scrapped</Text>
      </View>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel="Refresh"
        onPress={refresh}
        style={styles.iconButton}
      >
        <Icon name="RefreshCw" size={16} color={colors.foreground} />
      </Pressable>
    </View>
  );

  const banner = error && (
    <View style={[styles.banner, { borderColor: colors.statusDanger }]}>
      <Text style={[styles.bannerText, { color: colors.statusDanger }]}>{error}</Text>
      <Pressable accessibilityRole="button" onPress={refresh}>
        <Text style={{ color: colors.accent }}>Retry</Text>
      </Pressable>
    </View>
  );

  if (!board) {
    return error ? (
      <View style={[styles.fill, { backgroundColor: colors.surface0 }]}>{banner}</View>
    ) : (
      <Loading />
    );
  }

  if (board.kind === "none") {
    return (
      <View style={[styles.fill, { backgroundColor: colors.surface0 }]}>
        {banner}
        <View style={styles.empty}>
          <Text style={{ color: colors.foregroundMuted }}>
            No beans project in {board.directory}
          </Text>
        </View>
      </View>
    );
  }

  const lanes = layout(board.beans, state.showScrapped);
  const isCollapsed = (lane: Lane) => state.collapsed[laneKey(lane)] ?? lane.collapsedByDefault;

  return (
    <View style={[styles.fill, { backgroundColor: colors.surface0 }]}>
      {toolbar}
      {banner}
      <ScrollView contentContainerStyle={styles.lanes}>
        {lanes.length === 0 && (
          <Text style={[styles.empty, { color: colors.foregroundMuted }]}>Nothing to show</Text>
        )}
        {lanes.map((lane, index) => (
          <View key={laneKey(lane)} style={styles.laneGroup}>
            {lane.group !== lanes[index - 1]?.group && (
              <Text style={[styles.groupTitle, { color: colors.foregroundMuted }]}>
                {lane.group === NO_EPIC_GROUP ? "Not in an epic" : `${COLUMN_TITLES[lane.group] ?? lane.group} epics`}
              </Text>
            )}
            <LaneView
              lane={lane}
              collapsed={isCollapsed(lane)}
              colors={colors}
              onToggle={() =>
                setState({
                  ...state,
                  collapsed: { ...state.collapsed, [laneKey(lane)]: !isCollapsed(lane) },
                })
              }
            />
          </View>
        ))}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1 },
  toolbar: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderBottomWidth: 1,
  },
  toggle: { flexDirection: "row", alignItems: "center", gap: 8 },
  iconButton: { padding: 4 },
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
  empty: { padding: 24, alignItems: "center" },
  lanes: { padding: 12, gap: 12 },
  lane: { borderWidth: 1, borderRadius: 8, overflow: "hidden" },
  laneHeader: { flexDirection: "row", alignItems: "center", gap: 8, padding: 8 },
  laneTitle: { fontWeight: "600", flexShrink: 1 },
  // Columns share the lane's width, down to a floor below which the lane scrolls.
  columns: { flexGrow: 1, gap: 8, paddingHorizontal: 8, paddingBottom: 8 },
  column: { flex: 1, minWidth: 300, gap: 6 },
  columnTitle: { fontSize: 12, fontWeight: "600", textTransform: "uppercase" },
  laneGroup: { gap: 6 },
  groupTitle: { fontSize: 12, fontWeight: "600", textTransform: "uppercase", marginTop: 6 },
  card: { borderWidth: 1, borderRadius: 6, padding: 10, gap: 6 },
  cardTitle: { fontWeight: "500" },
  cardRow: { flexDirection: "row", alignItems: "center", justifyContent: "space-between" },
  cardIcons: { flexDirection: "row", alignItems: "center", gap: 6 },
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
  cardId: { alignSelf: "flex-end", fontStyle: "italic" },
  small: { fontSize: 11 },
  inline: { flexDirection: "row", alignItems: "center", gap: 2 },
});
