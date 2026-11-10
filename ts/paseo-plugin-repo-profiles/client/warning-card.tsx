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
  const { reason, detail, loaded } = item.data;
  const title = loaded
    ? `Repository skills: loaded ${loaded} only`
    : "Repository skills not loaded";
  return (
    <View style={[styles.card, { backgroundColor: colors.surface1, borderColor: colors.border }]}>
      <View style={styles.header}>
        <Icon name="TriangleAlert" size={14} color={colors.statusWarning} />
        <Text style={[styles.title, { color: colors.statusWarning }]}>{title}</Text>
      </View>
      <Text style={{ color: colors.foregroundMuted }}>{reason}</Text>
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
  );
}

const styles = StyleSheet.create({
  card: { borderWidth: 1, borderRadius: 8, paddingVertical: 8, paddingHorizontal: 12, gap: 6 },
  header: { flexDirection: "row", alignItems: "center", gap: 6 },
  title: { fontWeight: "600" },
  code: {
    alignSelf: "flex-start",
    borderWidth: 1,
    borderRadius: 4,
    paddingVertical: 2,
    paddingHorizontal: 6,
  },
  codeText: { fontFamily: MONO, fontSize: 12 },
});
