import { useEffect, useState } from "react";
import { Linking, Pressable, StyleSheet, Text, TextInput, View } from "react-native";
import { clearChatGPTProblem, refreshChatGPTAccount, useChatGPTAccount } from "../../state/browseForMe/store";
import { choosePageSummaryChatGPT, choosePageSummaryProvider, claudeOffered, refreshClaudeAccount, refreshPageSummaryProvider, removeClaudeKey, saveClaudeKey, useClaudeAccount, usePageSummaryProvider } from "../../state/pageSummary/store";
import { PAGE_SUMMARY_COPY } from "../../state/pageSummary/copy";
import { refreshPageSummariesEnabled, setPageSummariesEnabled, usePageSummariesEnabled } from "../../state/pageSummary/enabled";
import { popSettings } from "../../state/settings/nav";
import { font, PrimaryButton, settingsLayout, settingsTint, space, Symbol, useTheme } from "../ui";
import { Divider, Group, IconTile, SettingsPage, ToggleRow } from "./SettingsKit";

export function PageSummaryPage() {
  const theme = useTheme();
  const account = useChatGPTAccount();
  const provider = usePageSummaryProvider();
  const enabled = usePageSummariesEnabled();
  const claude = useClaudeAccount();
  const offersClaude = claudeOffered();
  const [key, setKey] = useState("");
  const [wantsClaude, setWantsClaude] = useState(false);
  useEffect(() => {
    void refreshChatGPTAccount();
    void refreshClaudeAccount();
    void refreshPageSummaryProvider();
    void refreshPageSummariesEnabled();
    return () => void clearChatGPTProblem();
  }, []);
  const connected = account?.connected ?? false;
  const signingIn = account?.signingIn ?? false;
  const choosesChatGPT = provider === "chatgpt";
  const choosesClaude = provider === "claude";
  const claudeConnected = claude?.connected ?? false;
  const checking = claude?.checking ?? false;
  const footer = choosesClaude
    ? PAGE_SUMMARY_COPY.claudeFooter
    : choosesChatGPT
      ? PAGE_SUMMARY_COPY.chatGPTFooter
      : [PAGE_SUMMARY_COPY.onDeviceFooter, PAGE_SUMMARY_COPY.chatGPTFooter, offersClaude ? PAGE_SUMMARY_COPY.claudeFooter : null].filter(Boolean).join(" ");
  const asksForKey = offersClaude && !claudeConnected && (wantsClaude || choosesClaude);
  const chooseClaude = () => {
    if (claudeConnected) void choosePageSummaryProvider("claude");
    else setWantsClaude(true);
  };
  return (
    <SettingsPage title={PAGE_SUMMARY_COPY.title} onBack={popSettings}>
      <View testID="pageSummarySettings" accessible style={styles.hero}>
        <IconTile icon="sparkles" tint={settingsTint.nightShade} side={56} />
        <Text accessibilityRole="header" style={[font.title3, styles.bold, { color: theme.label }]}>
          {PAGE_SUMMARY_COPY.title}
        </Text>
        <Text style={[font.subheadline, styles.centered, { color: theme.secondaryLabel }]}>{PAGE_SUMMARY_COPY.subtitle}</Text>
      </View>
      <Group footer={enabled ? undefined : PAGE_SUMMARY_COPY.offFooter}>
        <ToggleRow title={PAGE_SUMMARY_COPY.title} value={enabled} onChange={(on) => void setPageSummariesEnabled(on)} />
      </Group>
      {enabled ? (
        <Group footer={asksForKey ? undefined : footer}>
          <Choice title={PAGE_SUMMARY_COPY.onDevice} detail={PAGE_SUMMARY_COPY.onDeviceDetail} selected={!choosesChatGPT && !choosesClaude} onPress={() => void choosePageSummaryProvider("on_device")} />
          <Divider />
          <Choice
            title={PAGE_SUMMARY_COPY.chatGPT}
            detail={signingIn ? "Waiting for ChatGPT…" : connected && account?.label ? account.label : PAGE_SUMMARY_COPY.chatGPTDetail}
            selected={choosesChatGPT}
            enabled={!signingIn}
            onPress={() => void choosePageSummaryChatGPT(connected)}
          />
          {offersClaude ? (
            <>
              <Divider />
              <Choice
                title={PAGE_SUMMARY_COPY.claude}
                detail={checking ? "Checking your key…" : claudeConnected && claude?.label ? claude.label : PAGE_SUMMARY_COPY.claudeDetail}
                selected={choosesClaude}
                enabled={!checking}
                onPress={chooseClaude}
              />
            </>
          ) : null}
        </Group>
      ) : null}
      {enabled && asksForKey ? (
        <View testID="claudeKeyEntry" style={styles.connect}>
          {claude?.problem ? (
            <Text testID="claudeKeyProblem" accessibilityLiveRegion="polite" style={[font.footnote, { color: theme.destructive }]}>
              {claude.problem}
            </Text>
          ) : null}
          <TextInput
            testID="claudeKeyField"
            autoFocus
            value={key}
            onChangeText={setKey}
            placeholder={PAGE_SUMMARY_COPY.claudeKeyPlaceholder}
            placeholderTextColor={theme.secondaryLabel}
            secureTextEntry
            autoCapitalize="none"
            autoCorrect={false}
            textContentType="password"
            accessibilityLabel="Anthropic API Key"
            style={[font.body, styles.field, { color: theme.label, borderColor: theme.secondaryLabel }]}
          />
          <PrimaryButton
            title={checking ? "Checking…" : "Save Key and Use Claude"}
            onPress={() => {
              if (checking || !key.trim()) return;
              void saveClaudeKey(key).then((saved) => {
                if (saved) {
                  setKey("");
                  setWantsClaude(false);
                }
              });
            }}
          />
          <Text style={[font.footnote, { color: theme.secondaryLabel }]}>{PAGE_SUMMARY_COPY.claudeKeyHelp}</Text>
          <Pressable accessibilityRole="link" onPress={() => void Linking.openURL("https://console.anthropic.com/settings/keys")}>
            <Text style={[font.footnote, { color: theme.formAccent }]}>Open console.anthropic.com</Text>
          </Pressable>
        </View>
      ) : null}
      {enabled && offersClaude && claudeConnected ? (
        <Pressable testID="claudeRemoveKey" accessibilityRole="button" onPress={() => void removeClaudeKey()} style={styles.remove}>
          <Text style={[font.body, { color: theme.destructive }]}>Remove Anthropic API Key</Text>
        </Pressable>
      ) : null}
      {enabled && choosesChatGPT && !connected ? (
        <View style={styles.connect}>
          <PrimaryButton title={signingIn ? "Waiting for ChatGPT…" : "Continue with ChatGPT"} onPress={() => void choosePageSummaryChatGPT(false)} />
          <Text style={[font.footnote, { color: theme.secondaryLabel }]}>{PAGE_SUMMARY_COPY.reconnect}</Text>
        </View>
      ) : null}
      {account?.problem ? <Text style={[font.footnote, styles.problem, { color: theme.destructive }]}>{account.problem}</Text> : null}
    </SettingsPage>
  );
}

function Choice({ title, detail, selected, enabled = true, onPress }: { title: string; detail: string; selected: boolean; enabled?: boolean; onPress: () => void }) {
  const theme = useTheme();
  return (
    <Pressable
      testID={`pageSummaryChoice:${title}`}
      accessibilityRole="radio"
      accessibilityState={{ selected, disabled: !enabled }}
      disabled={!enabled}
      onPress={onPress}
      style={({ pressed }) => [styles.row, pressed ? { backgroundColor: theme.rowHighlight } : null]}
    >
      <View style={styles.fill}>
        <Text style={[font.body, { color: theme.label }]}>{title}</Text>
        <Text style={[font.footnote, { color: theme.secondaryLabel }]}>{detail}</Text>
      </View>
      {selected ? <Symbol name="checkmark" size={18} color={theme.formAccent} /> : null}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  hero: { alignItems: "center", gap: space.s, paddingHorizontal: space.xxl, paddingVertical: space.xl },
  bold: { fontWeight: "700" },
  centered: { textAlign: "center" },
  connect: { gap: space.s, paddingHorizontal: space.l },
  problem: { paddingHorizontal: space.l, paddingTop: space.s },
  field: { borderWidth: StyleSheet.hairlineWidth, borderRadius: 10, paddingHorizontal: 12, paddingVertical: 10 },
  remove: { paddingHorizontal: space.l, paddingVertical: space.m },
  row: { flexDirection: "row", alignItems: "center", gap: settingsLayout.labelGap, minHeight: settingsLayout.rowMinHeight, paddingHorizontal: settingsLayout.rowInset, paddingVertical: 8 },
  fill: { flex: 1 },
});
