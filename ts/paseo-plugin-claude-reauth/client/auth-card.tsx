import { openExternalUrl, useRpc, type PluginTimelineItemProps } from "@getpaseo/plugin/client";
import { useEffect, useRef, useState } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { recoveryStatus, startRecovery, type RecoveryState } from "../shared/rpc";
import type { AuthExpiredData } from "../shared/timeline";

const POLL_MS = 2_000;

type Colors = PluginTimelineItemProps["theme"]["colors"];

function isRunning(state: RecoveryState): boolean {
  return state.phase === "logging-in" || state.phase === "reloading";
}

function describe(state: RecoveryState): string | null {
  switch (state.phase) {
    case "idle":
      return null;
    case "logging-in":
      return "Finish signing in in the browser on your host";
    case "reloading":
      return "Reloading the agent…";
    case "done":
      return "Reloaded — send your message again";
    case "failed":
      return `${state.step === "login" ? "Login" : "Reload"} failed: ${state.error}`;
  }
}

function Button({
  label,
  primary,
  disabled,
  colors,
  onPress,
}: {
  label: string;
  primary?: boolean;
  disabled: boolean;
  colors: Colors;
  onPress(): void;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      disabled={disabled}
      onPress={onPress}
      style={[
        styles.button,
        primary
          ? { backgroundColor: colors.accent, borderColor: colors.accent }
          : { borderColor: colors.border },
        disabled && styles.disabled,
      ]}
    >
      <Text style={{ color: primary ? colors.accentForeground : colors.foreground }}>{label}</Text>
    </Pressable>
  );
}

// Stateless by design: the daemon half owns recovery state, so the card asks for it
// on mount (a second device, or a reopened chat, picks up a job in flight) and polls
// only while a job runs.
export function AuthCard({ agentId, item, theme }: PluginTimelineItemProps<AuthExpiredData>) {
  const { colors } = theme;
  const start = useRpc(startRecovery);
  const status = useRpc(recoveryStatus);
  const [state, setState] = useState<RecoveryState>({ phase: "idle" });
  const [starting, setStarting] = useState(false);
  const [startError, setStartError] = useState<string | null>(null);
  // Only the latest request's answer may land, so a slow mount-time status can't
  // overwrite the state a button press already returned.
  const latest = useRef(0);
  const mounted = useRef(true);
  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);

  function request(call: () => Promise<RecoveryState>): Promise<void> {
    const seq = ++latest.current;
    return call().then((next) => {
      if (mounted.current && seq === latest.current) setState(next);
    });
  }

  function refresh() {
    // A failed poll (the daemon half restarting, say) keeps the last state; the next
    // tick retries.
    request(() => status({ agentId })).catch((error: unknown) =>
      console.warn("claude-reauth: could not read recovery status", error),
    );
  }

  useEffect(refresh, [agentId]);

  const running = isRunning(state);
  useEffect(() => {
    if (!running) return;
    const timer = setInterval(refresh, POLL_MS);
    return () => clearInterval(timer);
  }, [running, agentId]);

  function begin(login: boolean) {
    setStarting(true);
    setStartError(null);
    request(() => start({ agentId, login }))
      .catch((error: unknown) => {
        if (mounted.current) setStartError(error instanceof Error ? error.message : String(error));
      })
      .finally(() => {
        if (mounted.current) setStarting(false);
      });
  }

  const line = startError ? `Could not start: ${startError}` : describe(state);
  const url = state.phase === "logging-in" || state.phase === "failed" ? state.url : undefined;
  const disabled = running || starting;

  return (
    <View style={[styles.card, { backgroundColor: colors.surface1, borderColor: colors.border }]}>
      <Text style={[styles.title, { color: colors.statusWarning }]}>Claude login expired</Text>
      <Text style={{ color: colors.foregroundMuted }}>{item.data.message}</Text>
      <View style={styles.actions}>
        <Button label="Log in & reload" primary disabled={disabled} colors={colors} onPress={() => begin(true)} />
        <Button label="Reload only" disabled={disabled} colors={colors} onPress={() => begin(false)} />
      </View>
      {line && (
        <Text
          style={{
            color: state.phase === "failed" || startError ? colors.statusDanger : colors.foreground,
          }}
        >
          {line}
        </Text>
      )}
      {url && (
        <Text
          accessibilityRole="link"
          style={[styles.link, { color: colors.accent }]}
          onPress={() =>
            openExternalUrl(url).catch((error: unknown) =>
              console.warn("claude-reauth: could not open the login page", error),
            )
          }
        >
          Open login page
        </Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  card: { borderWidth: 1, borderRadius: 8, padding: 12, gap: 8 },
  title: { fontWeight: "600" },
  actions: { flexDirection: "row", flexWrap: "wrap", gap: 8 },
  button: { borderWidth: 1, borderRadius: 6, paddingVertical: 6, paddingHorizontal: 12 },
  disabled: { opacity: 0.5 },
  link: { textDecorationLine: "underline" },
});
