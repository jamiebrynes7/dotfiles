import type { PluginTimelineItemProps } from "@getpaseo/plugin/client";
import { Icon } from "@getpaseo/plugin/client/ui";
import { Platform, StyleSheet, Text, View } from "react-native";
import type { WarningData } from "../shared/timeline.ts";

// The app's own monospace stack; the plugin theme carries colours but no fonts.
const MONO = Platform.select({
  ios: "ui-monospace",
  web: "SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace",
  default: "monospace",
});

// On web the app forces its interface font onto everything except subtrees tagged
// with this dataSet. React Native's types don't know the prop; react-native-web does.
const CODE_SURFACE = { dataSet: { pmono: "" } } as object;

export function WarningCard({ item, theme }: PluginTimelineItemProps<WarningData>) {
  const { colors } = theme;
  const { problems, key, loaded } = item.data;
  const title =
    loaded.length > 0
      ? `Repository profile: loaded ${loaded.join(" and ")}${key === undefined ? "" : ` for ${key}`}`
      : "Repository profile not loaded";
  return (
    <View style={[styles.card, { backgroundColor: colors.surface1, borderColor: colors.border }]}>
      <View style={styles.header}>
        <Icon name="TriangleAlert" size={14} color={colors.statusWarning} />
        <Text style={[styles.title, { color: colors.statusWarning }]}>{title}</Text>
      </View>
      {problems.map(({ field, reason, detail }, index) => (
        <View key={index} style={styles.problem}>
          <Text style={{ color: colors.foregroundMuted }}>
            {field === undefined ? reason : `${field[0]!.toUpperCase()}${field.slice(1)}: ${reason}`}
          </Text>
          {detail !== undefined && (
            <View
              {...CODE_SURFACE}
              style={[styles.code, { backgroundColor: colors.surface2, borderColor: colors.border }]}
            >
              <Text selectable style={[styles.codeText, { color: colors.foreground }]}>
                {detail}
              </Text>
            </View>
          )}
        </View>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  card: { borderWidth: 1, borderRadius: 8, paddingVertical: 8, paddingHorizontal: 12, gap: 6 },
  header: { flexDirection: "row", alignItems: "center", gap: 6 },
  title: { fontWeight: "600" },
  problem: { gap: 4 },
  code: {
    alignSelf: "flex-start",
    borderWidth: 1,
    borderRadius: 4,
    paddingVertical: 2,
    paddingHorizontal: 6,
  },
  codeText: { fontFamily: MONO, fontSize: 12 },
});
