"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useMemo, useState, type ChangeEvent, type ReactNode } from "react";
import { Menu, Search, X } from "lucide-react";
import { docsNavigation } from "@/content/site";
import { cn } from "@/lib/utils";

function NavigationList({ query, onNavigate }: { query: string; onNavigate?: () => void }) {
  const pathname = usePathname();
  const filtered = useMemo(
    () => docsNavigation.filter((item) => item.label.toLowerCase().includes(query.toLowerCase())),
    [query],
  );
  return (
    <nav aria-label="Разделы документации" className="mt-4 space-y-1">
      {filtered.map((item) => {
        const active = pathname === item.href;
        const Icon = item.icon;
        return (
          <Link
            key={item.href}
            href={item.href}
            onClick={onNavigate}
            className={cn(
              "flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300",
              active ? "bg-cyan-300/[0.07] text-cyan-100" : "text-zinc-500 hover:bg-white/[0.035] hover:text-zinc-200",
            )}
          >
            <Icon className="size-4" />
            {item.label}
          </Link>
        );
      })}
      {filtered.length === 0 && <p className="px-3 py-4 text-sm text-zinc-600">Ничего не найдено.</p>}
    </nav>
  );
}

function SearchBox({ value, onChange }: { value: string; onChange: (value: string) => void }) {
  return (
    <label className="relative block">
      <span className="sr-only">Поиск по документации</span>
      <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-zinc-600" />
      <input
        value={value}
        onChange={(event: ChangeEvent<HTMLInputElement>) => onChange(event.target.value)}
        placeholder="Поиск раздела"
        className="h-10 w-full rounded-xl border border-white/8 bg-white/[0.025] pl-9 pr-3 text-sm text-white outline-none placeholder:text-zinc-700 focus:border-cyan-300/25 focus:ring-2 focus:ring-cyan-300/10"
      />
    </label>
  );
}

export function DocsShell({ children }: { children: ReactNode }) {
  const [query, setQuery] = useState("");
  const [open, setOpen] = useState(false);
  return (
    <div className="mx-auto grid max-w-[1440px] lg:grid-cols-[270px_minmax(0,1fr)]">
      <aside className="sticky top-17 hidden h-[calc(100vh-68px)] border-r border-white/8 px-5 py-8 lg:block">
        <SearchBox value={query} onChange={setQuery} />
        <NavigationList query={query} />
        <div className="mt-8 rounded-2xl border border-white/8 bg-white/[0.02] p-4">
          <p className="font-mono text-[10px] uppercase tracking-[.16em] text-cyan-300">Source of truth</p>
          <p className="mt-2 text-xs leading-5 text-zinc-600">Точные параметры и контракты находятся в папке docs и исходном коде репозитория.</p>
        </div>
      </aside>

      <div className="min-w-0">
        <div className="sticky top-17 z-30 flex items-center justify-between border-b border-white/8 bg-[#050709]/92 px-4 py-3 backdrop-blur-xl lg:hidden">
          <span className="text-sm font-medium text-white">Документация</span>
          <button
            type="button"
            aria-label="Открыть навигацию документации"
            aria-expanded={open}
            onClick={() => setOpen(true)}
            className="inline-flex size-9 items-center justify-center rounded-lg border border-white/10 text-white"
          >
            <Menu className="size-4" />
          </button>
        </div>
        {children}
      </div>

      {open && (
        <div className="fixed inset-0 z-[70] bg-[#050709]/98 p-4 backdrop-blur-xl lg:hidden">
          <div className="mx-auto max-w-lg">
            <div className="flex items-center justify-between py-3">
              <span className="font-semibold text-white">Разделы документации</span>
              <button
                type="button"
                onClick={() => setOpen(false)}
                aria-label="Закрыть навигацию документации"
                className="inline-flex size-10 items-center justify-center rounded-xl border border-white/10 text-white"
              >
                <X className="size-5" />
              </button>
            </div>
            <SearchBox value={query} onChange={setQuery} />
            <NavigationList query={query} onNavigate={() => setOpen(false)} />
          </div>
        </div>
      )}
    </div>
  );
}
