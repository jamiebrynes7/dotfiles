import { useTabState, type PluginWorkspacePanelProps } from "@getpaseo/plugin/client";
import { Icon, Loading, ScrollView } from "@getpaseo/plugin/client/ui";
import { useEffect, useState } from "react";
import { Pressable, StyleSheet, Switch, Text, TextInput, View } from "react-native";
import { z } from "zod";
import {
  columnCounts,
  columnOf,
  laneCount,
  laneKey,
  layout,
  NO_EPIC_GROUP,
  progress,
  type Lane,
  type Progress,
  type Row,
} from "../shared/layout.ts";
import { MAX_SEARCH_LENGTH, type BoardBean } from "../shared/rpc.ts";
import { PriorityIcon, Tags, TypeBadge, typeColor, type Colors } from "./badges.tsx";
import { useSelection } from "./selection.ts";
import { useBoard } from "./use-polled.ts";

const TabState = z.object({
  showScrapped: z.boolean(),
  // Tabs saved before this field existed must still parse: useTabState discards the
  // whole state on a parse failure, which would reset showScrapped and collapsed.
  showArchived: z.boolean().default(false),
  /** Lane key or feature id → collapsed, only for lanes and rows the user has toggled. */
  collapsed: z.record(z.string(), z.boolean()),
});
type TabState = z.infer<typeof TabState>;
const DEFAULT_TAB_STATE: TabState = { showScrapped: false, showArchived: false, collapsed: {} };

const SEARCH_DEBOUNCE_MS = 300;
// The CLI's Bleve query syntax; whole words match, so prefixes need `*`.
const SEARCH_HINT =
  "Whole words · log* prefix · login~ fuzzy · a AND b · a OR b · title: body: slug: id:";

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
  progress,
  heading = false,
  context = false,
}: {
  bean: BoardBean;
  selected: boolean;
  onPress(): void;
  colors: Colors;
  progress?: Progress;
  /** Leads its feature row, so it gets the feature's accent edge. */
  heading?: boolean;
  /** Shown only to head its row: dimmed, still pressable. */
  context?: boolean;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      // The Pressable's label replaces its children's, so progress and context go here.
      accessibilityLabel={[
        `${bean.id}: ${bean.title}`,
        progress && `${progress.done} of ${progress.total} done`,
        context && "shown for context",
      ]
        .filter(Boolean)
        .join(", ")}
      onPress={onPress}
      style={[
        styles.card,
        {
          backgroundColor: colors.surface1,
          borderColor: selected ? colors.accent : colors.border,
        },
        heading && { borderLeftWidth: 3, borderLeftColor: typeColor(bean.type) },
        context && styles.context,
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
          {progress && (
            <Text style={[styles.small, { color: colors.foregroundMuted }]}>
              {progress.done}/{progress.total}
            </Text>
          )}
          <PriorityIcon priority={bean.priority} colors={colors} />
        </View>
      </View>
      <Tags tags={bean.tags} colors={colors} />
      <Text style={[styles.small, styles.cardId, { color: colors.foregroundMuted }]}>{bean.id}</Text>
    </Pressable>
  );
}

/** A feature row's header, which toggles it; a collapsed row shows only this. */
function RowHeader({
  feature,
  collapsed,
  searching,
  progress,
  onToggle,
  colors,
}: {
  feature: BoardBean;
  collapsed: boolean;
  searching: boolean;
  progress?: Progress;
  onToggle(): void;
  colors: Colors;
}) {
  const muted = { color: colors.foregroundMuted };
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`${collapsed ? "Expand" : "Collapse"} ${feature.title}`}
      onPress={onToggle}
      disabled={searching}
      style={styles.rowHeader}
    >
      {!searching && (
        <Icon name={collapsed ? "ChevronRight" : "ChevronDown"} size={14} color={colors.foregroundMuted} />
      )}
      <Text style={[styles.rowTitle, { color: colors.foreground }]} numberOfLines={1}>
        {feature.title}
      </Text>
      <Text style={[styles.small, muted]}>{feature.id}</Text>
      <Text style={[styles.small, styles.rowStatus, muted]}>
        {COLUMN_TITLES[columnOf(feature)] ?? columnOf(feature)}
      </Text>
      {progress && (
        <Text style={[styles.small, muted]}>
          {progress.done}/{progress.total}
        </Text>
      )}
    </Pressable>
  );
}

function LaneView({
  lane,
  collapsed,
  searching,
  onToggle,
  isRowCollapsed,
  onToggleRow,
  progressOf,
  selected,
  onOpenBean,
  colors,
}: {
  lane: Lane;
  collapsed: boolean;
  /** Lanes and rows are held open while searching, so their headers do not toggle. */
  searching: boolean;
  onToggle(): void;
  isRowCollapsed(row: Row): boolean;
  onToggleRow(row: Row): void;
  progressOf: ReadonlyMap<string, Progress>;
  selected: string | null;
  onOpenBean(beanId: string): void;
  colors: Colors;
}) {
  const counts = columnCounts(lane);
  // A lane with no feature rows keeps today's single row, with no "Other" header.
  const hasFeatureRows = lane.rows.some((row) => row.feature !== null);
  return (
    <View style={[styles.lane, { borderColor: colors.border }]}>
      <Pressable
        accessibilityRole="button"
        onPress={onToggle}
        disabled={searching}
        style={styles.laneHeader}
      >
        {!searching && (
          <Icon
            name={collapsed ? "ChevronRight" : "ChevronDown"}
            size={16}
            color={colors.foregroundMuted}
          />
        )}
        <Text style={[styles.laneTitle, { color: colors.foreground }]} numberOfLines={1}>
          {lane.epic ? lane.epic.title : "No epic"}
        </Text>
        {lane.epic && (
          <Text style={[styles.small, { color: colors.foregroundMuted }]}>
            {lane.epic.id}
          </Text>
        )}
        <Text style={[styles.small, { color: colors.foregroundMuted }]}>{laneCount(lane)}</Text>
      </Pressable>
      {!collapsed && (
        <ScrollView horizontal contentContainerStyle={styles.laneBody}>
          <View style={styles.row}>
            {lane.rows[0].cells.map((cell, index) => (
              <Text
                key={cell.column}
                style={[styles.column, styles.columnTitle, { color: colors.foregroundMuted }]}
              >
                {COLUMN_TITLES[cell.column] ?? cell.column} · {counts[index]}
              </Text>
            ))}
          </View>
          {lane.rows.map((row) => {
            const feature = row.feature;
            const rowCollapsed = feature !== null && isRowCollapsed(row);
            return (
              <View
                key={feature?.id ?? "other"}
                style={[styles.rowBlock, hasFeatureRows && { borderTopWidth: 1, borderColor: colors.border }]}
              >
                {feature !== null ? (
                  <RowHeader
                    feature={feature}
                    collapsed={rowCollapsed}
                    searching={searching}
                    progress={progressOf.get(feature.id)}
                    onToggle={() => onToggleRow(row)}
                    colors={colors}
                  />
                ) : hasFeatureRows ? (
                  <Text style={[styles.columnTitle, { color: colors.foregroundMuted }]}>Other</Text>
                ) : null}
                {!rowCollapsed && (
                  <View style={styles.row}>
                    {row.cells.map((cell) => (
                      <View key={cell.column} style={[styles.column, styles.cell]}>
                        {cell.cards.map((bean) => (
                          <Card
                            key={bean.id}
                            bean={bean}
                            selected={bean.id === selected}
                            onPress={() => onOpenBean(bean.id)}
                            colors={colors}
                            progress={progressOf.get(bean.id)}
                            heading={bean.id === feature?.id}
                            context={bean.id === feature?.id && row.featureIsContext}
                          />
                        ))}
                      </View>
                    ))}
                  </View>
                )}
              </View>
            );
          })}
        </ScrollView>
      )}
    </View>
  );
}

export interface BoardPanelProps extends PluginWorkspacePanelProps {
  /** Selects the bean and reveals its detail in the Explorer. */
  onOpenBean(workspaceId: string, beanId: string): void;
}

/**
 * The query to search for: `text` once it has been still for SEARCH_DEBOUNCE_MS, but
 * blank at once when `text` is cleared.
 */
function useDebouncedSearch(text: string): string {
  const trimmed = text.trim();
  const [query, setQuery] = useState(trimmed);
  useEffect(() => {
    if (!trimmed) {
      setQuery("");
      return;
    }
    const timer = setTimeout(() => setQuery(trimmed), SEARCH_DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [trimmed]);
  return trimmed ? query : "";
}

export function BoardPanel({ workspaceId, tab, theme, onOpenBean }: BoardPanelProps) {
  const { colors } = theme;
  // Plain state, not tab state: a forgotten filter must not outlive the tab.
  const [searchText, setSearchText] = useState("");
  const query = useDebouncedSearch(searchText);
  const { data: board, error, refresh } = useBoard(workspaceId, query);
  const selected = useSelection(workspaceId);
  const [state, setState] = useTabState(tab, TabState, DEFAULT_TAB_STATE);

  // Like `matches` below, only while a query is active, so clearing the box drops it.
  const searchError = query && board?.kind === "project" ? board.searchError : null;

  const toolbar = (
    <View style={[styles.toolbar, { borderColor: colors.border }]}>
      <View style={styles.toggles}>
        <View style={styles.searchGroup}>
          <View
            style={[styles.search, { backgroundColor: colors.surface1, borderColor: colors.border }]}
          >
            <Icon name="Search" size={14} color={colors.foregroundMuted} />
            <TextInput
              value={searchText}
              onChangeText={setSearchText}
              placeholder="Search beans"
              placeholderTextColor={colors.foregroundMuted}
              maxLength={MAX_SEARCH_LENGTH}
              autoCapitalize="none"
              autoCorrect={false}
              accessibilityLabel="Search beans"
              style={[styles.searchInput, { color: colors.foreground }]}
            />
            {searchText ? (
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Clear search"
                onPress={() => setSearchText("")}
              >
                <Icon name="X" size={14} color={colors.foregroundMuted} />
              </Pressable>
            ) : null}
          </View>
          <Text
            style={[
              styles.small,
              { color: searchError ? colors.statusDanger : colors.foregroundMuted },
            ]}
          >
            {searchError ? `Can't parse search: ${searchError}` : SEARCH_HINT}
          </Text>
        </View>
        <View style={styles.toggle}>
          <Switch
            value={state.showScrapped}
            onValueChange={(showScrapped) => setState({ ...state, showScrapped })}
          />
          <Text style={{ color: colors.foreground }}>Show scrapped</Text>
        </View>
        <View style={styles.toggle}>
          <Switch
            value={state.showArchived}
            onValueChange={(showArchived) => setState({ ...state, showArchived })}
          />
          <Text style={{ color: colors.foreground }}>Show archived</Text>
        </View>
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

  // Gated on `query` too, so clearing the box shows the full board at once instead of
  // the last search's matches until the unsearched read lands. A new query keeps the
  // previous one's matches on screen until its own arrive.
  const matches = query && board.matches ? new Set(board.matches) : null;
  const searching = matches !== null;
  const lanes = layout(board.beans, state.showScrapped, state.showArchived, matches);
  const progressOf = progress(board.beans);
  const isSaved = (lane: Lane) => state.collapsed[laneKey(lane)] ?? lane.collapsedByDefault;
  const isCollapsed = (lane: Lane) => !searching && isSaved(lane);
  // Feature ids and lane keys share the map: bean ids are unique, and "no-epic" is none.
  const isRowCollapsed = (row: Row) =>
    !searching && row.feature !== null && (state.collapsed[row.feature.id] ?? row.collapsedByDefault);

  return (
    <View style={[styles.fill, { backgroundColor: colors.surface0 }]}>
      {toolbar}
      {banner}
      <ScrollView contentContainerStyle={styles.lanes}>
        {lanes.length === 0 && (
          <Text style={[styles.empty, { color: colors.foregroundMuted }]}>
            {searching ? "No beans match" : "Nothing to show"}
          </Text>
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
              searching={searching}
              selected={selected}
              onOpenBean={(beanId) => onOpenBean(workspaceId, beanId)}
              colors={colors}
              progressOf={progressOf}
              isRowCollapsed={isRowCollapsed}
              onToggleRow={(row) => {
                if (!row.feature) return;
                setState({
                  ...state,
                  collapsed: { ...state.collapsed, [row.feature.id]: !isRowCollapsed(row) },
                });
              }}
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
  toggles: { flexDirection: "row", flexWrap: "wrap", flexShrink: 1, alignItems: "center", gap: 16 },
  toggle: { flexDirection: "row", alignItems: "center", gap: 8 },
  searchGroup: { gap: 4, flexShrink: 1 },
  search: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    minWidth: 220,
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderWidth: 1,
    borderRadius: 6,
  },
  searchInput: { flex: 1, paddingVertical: 2 },
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
  // A column, not the default row: the lane's rows stack, and stretch to its width.
  laneBody: { flexGrow: 1, flexDirection: "column", gap: 6, paddingHorizontal: 8, paddingBottom: 8 },
  // Columns share the row's width equally, down to a floor below which the lane scrolls.
  row: { flexDirection: "row", gap: 8 },
  rowBlock: { gap: 6, paddingTop: 6 },
  rowHeader: { flexDirection: "row", alignItems: "center", gap: 6 },
  rowTitle: { fontSize: 13, fontWeight: "500", flexShrink: 1 },
  rowStatus: { textTransform: "uppercase" },
  // A definite `width`, not `flex: 1`: each lane scrolls separately, and flex: 1 sizes
  // columns from their content, misaligning them between epics. Not `width: 0` with
  // `minWidth`: Yoga leaves the floor out of the content width, so a lane can't scroll.
  column: { width: 300, flexGrow: 1 },
  cell: { gap: 6 },
  columnTitle: { fontSize: 12, fontWeight: "600", textTransform: "uppercase" },
  laneGroup: { gap: 6 },
  groupTitle: { fontSize: 12, fontWeight: "600", textTransform: "uppercase", marginTop: 6 },
  card: { borderWidth: 1, borderRadius: 6, padding: 10, gap: 6 },
  context: { opacity: 0.5 },
  cardTitle: { fontWeight: "500" },
  cardRow: { flexDirection: "row", alignItems: "center", justifyContent: "space-between" },
  cardIcons: { flexDirection: "row", alignItems: "center", gap: 6 },
  cardId: { alignSelf: "flex-end", fontStyle: "italic" },
  small: { fontSize: 11 },
  inline: { flexDirection: "row", alignItems: "center", gap: 2 },
});
