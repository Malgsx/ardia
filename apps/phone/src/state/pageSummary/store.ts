import { create } from "zustand";
import { pages, type ClaudeAccountState, type PageSummaryProvider } from "../../platform/pages";
import { connectChatGPT } from "../browseForMe/store";
import { settled } from "../pages/store";

export const usePageSummary = create<{ provider: PageSummaryProvider; claude: ClaudeAccountState | null }>()(() => ({ provider: "on_device", claude: null }));

export const useClaudeAccount = () => usePageSummary((state) => state.claude);

export function claudeOffered(): boolean {
  try {
    return pages.offersClaude();
  } catch {
    return false;
  }
}

export async function refreshClaudeAccount() {
  if (!claudeOffered()) return;
  const claude = await settled(() => pages.claudeAccount(), null);
  if (claude) usePageSummary.setState({ claude });
}

/** Checks the key with Anthropic, saves it to the Keychain and, when it's good, makes Claude the writer. */
export async function saveClaudeKey(key: string): Promise<boolean> {
  if (!claudeOffered()) return false;
  const current = usePageSummary.getState().claude;
  usePageSummary.setState({ claude: { connected: current?.connected ?? false, label: current?.label ?? null, checking: true, problem: null } });
  const claude = await settled(() => pages.saveClaudeKey(key), null);
  if (claude) usePageSummary.setState({ claude });
  if (!claude?.connected) return false;
  await saveProvider("claude", ++selection);
  return true;
}

export async function removeClaudeKey() {
  if (!claudeOffered()) return;
  const claude = await settled(() => pages.removeClaudeKey(), null);
  if (claude) usePageSummary.setState({ claude });
  await refreshPageSummaryProvider();
}

export const usePageSummaryProvider = () => usePageSummary((state) => state.provider);

export function pageSummaryChoiceOffered(): boolean {
  try {
    return pages.choosesSummaryProvider();
  } catch {
    return false;
  }
}

let selection = 0;

export async function refreshPageSummaryProvider() {
  if (!pageSummaryChoiceOffered()) return;
  const current = selection;
  const provider = await settled(() => pages.summaryProvider(), usePageSummary.getState().provider);
  if (current === selection) usePageSummary.setState({ provider });
}

async function saveProvider(provider: PageSummaryProvider, current: number): Promise<boolean> {
  const saved = await settled(() => pages.setSummaryProvider(provider), usePageSummary.getState().provider);
  if (current !== selection) return false;
  usePageSummary.setState({ provider: saved });
  return saved === provider;
}

export async function choosePageSummaryProvider(provider: PageSummaryProvider) {
  if (!pageSummaryChoiceOffered()) return;
  await saveProvider(provider, ++selection);
}

export async function choosePageSummaryChatGPT(connected: boolean): Promise<boolean> {
  if (!pageSummaryChoiceOffered()) return false;
  const current = ++selection;
  if (!connected && !(await connectChatGPT())) return false;
  return current === selection && saveProvider("chatgpt", current);
}
