"use client";

import { useState } from "react";
import { ChevronDown } from "lucide-react";
import type { FaqItem } from "@/content/faq";
import { cn } from "@/lib/utils";

export function FAQAccordion({ items }: { items: FaqItem[] }) {
  const [open, setOpen] = useState<number | null>(0);
  return (
    <div className="divide-y divide-white/8 overflow-hidden rounded-3xl border border-white/8 bg-white/[0.02]">
      {items.map((item, index) => {
        const expanded = open === index;
        return (
          <div key={item.question}>
            <button
              type="button"
              aria-expanded={expanded}
              onClick={() => setOpen(expanded ? null : index)}
              className="flex w-full items-center justify-between gap-6 px-5 py-5 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-cyan-300 sm:px-7"
            >
              <span className="font-medium text-white">{item.question}</span>
              <ChevronDown className={cn("size-5 shrink-0 text-zinc-500 transition-transform duration-200", expanded && "rotate-180 text-cyan-300")} />
            </button>
            <div className={cn("grid transition-[grid-template-rows] duration-200", expanded ? "grid-rows-[1fr]" : "grid-rows-[0fr]")}>
              <div className="overflow-hidden">
                <p className="px-5 pb-6 text-sm leading-7 text-zinc-400 sm:px-7">{item.answer}</p>
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}
