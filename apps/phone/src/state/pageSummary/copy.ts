import { Platform } from "react-native";
import type { PageSummaryProvider } from "../../platform/pages";

export const PAGE_SUMMARY_COPY = {
  title: "Pinch to Summarize",
  subtitle: "Pinch in on a page, or choose Summarize Page in the page menu, for a short summary over the page you’re reading.",
  onDevice: Platform.OS === "ios" ? "On This Device" : "On This Phone",
  onDeviceDetail: Platform.OS === "ios" ? "Apple Intelligence, or the page’s key lines without it" : "Gemini Nano, on phones that have it",
  chatGPT: "ChatGPT",
  chatGPTDetail: "Your ChatGPT Plus or Pro plan",
  onDeviceFooter: Platform.OS === "ios" ? "The page’s text stays on this device." : "The page’s text stays on this phone.",
  chatGPTFooter:
    "Choosing ChatGPT sends the text Ardia extracts from each page you summarize, Incognito pages included, straight from this phone to OpenAI on your plan, never through a server of ours. Usage counts toward your ChatGPT limits.",
  offFooter: "Off until you turn it on. Ardia reads a page only when you pinch in or choose Summarize Page.",
  iPhoneFooter: "Pinch to Summarize writes a short summary on this iPhone when you pinch in on a page or choose Summarize Page in the page menu.",
  reconnect: "ChatGPT isn’t connected, so summaries stay on this phone until you connect it again.",
  claude: "Claude",
  claudeDetail: "Your Anthropic API key and credits",
  claudeFooter:
    "Choosing Claude sends the text Ardia extracts from each page you summarize, Incognito pages included, straight from this device to Anthropic with your API key, never through a server of ours. Each summary uses your API credits.",
  claudeKeyPlaceholder: "sk-ant-…",
  claudeKeyHelp: "Create a key at console.anthropic.com › API Keys. It’s checked with Anthropic, then kept in this device’s Keychain.",
} as const;

export const pageSummaryRowValue = (enabled: boolean, provider: PageSummaryProvider, connected: boolean) =>
  !enabled ? "Off" : provider === "claude" ? PAGE_SUMMARY_COPY.claude : provider === "chatgpt" ? (connected ? PAGE_SUMMARY_COPY.chatGPT : "ChatGPT, Not Connected") : PAGE_SUMMARY_COPY.onDevice;
