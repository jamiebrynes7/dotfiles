import { useTabState, type PluginWorkspacePanelProps } from "@getpaseo/plugin/client";
import { Icon, Loading, ScrollView } from "@getpaseo/plugin/client/ui";
import { Pressable, StyleSheet, Switch, Text, View } from "react-native";
import { z } from "zod";
import { laneKey, layout, NO_EPIC_GROUP, type Lane } from "../shared/layout.ts";
import type { BoardBean } from "../shared/rpc.ts";
import { PriorityIcon, Tags, TypeBadge, type Colors } from "./badges.tsx";
import { useSelection } from "./selection.ts";
import { useBoard } from "./use-polled.ts";

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

function Card({
  bean,
  selected,
  onPress,
  colors,
}: {
  bean: BoardBean;
  selected: boolean;
  onPress(): void;
  colors: Colors;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`${bean.id}: ${bean.title}`}
      onPress={onPress}
      style={[
        styles.card,
        {
          backgroundColor: colors.surface1,
          borderColor: selected ? colors.accent : colors.border,
        },
      ]}
    >
      <Text style={[styles.cardTitle, { color: colors.foreground }]}>{bean.title}</Text>
      <View style={styles.cardRow}>
        <TypeBadge type={bean.type} />
        <View style={styles.cardIcons}>
          {bean.blocked && (
            <View style={styles.inline} accessibilityLabel="Blocked">
              <Icon name="Ban" size={12} color={colors.statusDanger} />
              <Text style={[styles.small, { color: colors.statusDanger }]}>blocked</Text>
            </View>
          )}
          <PriorityIcon priority={bean.priority} colors={colors} />
        </View>
      </View>
      <Tags tags={bean.tags} colors={colors} />
      <Text style={[styles.small, styles.cardId, { color: colors.foregroundMuted }]}>{bean.id}</Text>
    </Pressable>
  );
}

function LaneView({
  lane,
  collapsed,
  onToggle,
  selected,
  onOpenBean,
  colors,
}: {
  lane: Lane;
  collapsed: boolean;
  onToggle(): void;
  selected: string | null;
  onOpenBean(beanId: string): void;
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
                <Card
                  key={bean.id}
                  bean={bean}
                  selected={bean.id === selected}
                  onPress={() => onOpenBean(bean.id)}
                  colors={colors}
                />
              ))}
            </View>
          ))}
        </ScrollView>
      )}
    </View>
  );
}

export interface BoardPanelProps extends PluginWorkspacePanelProps {
  /** Selects the bean and reveals its detail in the Explorer. */
  onOpenBean(workspaceId: string, beanId: string): void;
}

export function BoardPanel({ workspaceId, tab, theme, onOpenBean }: BoardPanelProps) {
  const { colors } = theme;
  const { data: board, error, refresh } = useBoard(workspaceId);
  const selected = useSelection(workspaceId);
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
              selected={selected}
              onOpenBean={(beanId) => onOpenBean(workspaceId, beanId)}
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
  cardId: { alignSelf: "flex-end", fontStyle: "italic" },
  small: { fontSize: 11 },
  inline: { flexDirection: "row", alignItems: "center", gap: 2 },
});
