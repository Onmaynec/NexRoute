"use client";

import { useState } from "react";
import { Check, Copy } from "lucide-react";

export function CodeBlock({ language, title, value }: { language: string; title?: string; value: string }) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1600);
    } catch {
      setCopied(false);
    }
  }

  return (
    <div className="overflow-hidden rounded-2xl border border-white/9 bg-[#05090c] shadow-[inset_0_1px_rgba(255,255,255,.025)]">
      <div className="flex items-center justify-between border-b border-white/8 px-4 py-2.5">
        <div className="flex items-center gap-3">
          <span className="font-mono text-[10px] uppercase tracking-[0.16em] text-cyan-300">{language}</span>
          {title && <span className="text-xs text-zinc-600">{title}</span>}
        </div>
        <button
          type="button"
          onClick={copy}
          className="inline-flex items-center gap-1.5 rounded-lg px-2 py-1 text-xs text-zinc-500 transition hover:bg-white/[0.05] hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300"
          aria-label="Скопировать код"
        >
          {copied ? <Check className="size-3.5" /> : <Copy className="size-3.5" />}
          {copied ? "Скопировано" : "Копировать"}
        </button>
      </div>
      <pre className="overflow-x-auto p-4 text-[13px] leading-6 text-zinc-300">
        <code>{value}</code>
      </pre>
    </div>
  );
}
