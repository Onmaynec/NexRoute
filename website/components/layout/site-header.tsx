"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { Download, Github, Menu, X } from "lucide-react";
import { navigation, projectLinks } from "@/content/site";
import { LogoMark } from "@/components/layout/logo";
import { cn } from "@/lib/utils";

export function SiteHeader() {
  const [open, setOpen] = useState(false);
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 12);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  useEffect(() => {
    document.body.style.overflow = open ? "hidden" : "";
    return () => {
      document.body.style.overflow = "";
    };
  }, [open]);

  return (
    <header
      className={cn(
        "sticky top-0 z-50 border-b transition-all duration-200",
        scrolled
          ? "border-white/8 bg-[#050709]/82 shadow-[0_12px_40px_rgba(0,0,0,.28)] backdrop-blur-xl"
          : "border-transparent bg-transparent",
      )}
    >
      <div className="mx-auto flex h-17 max-w-7xl items-center justify-between px-4 sm:px-6 lg:px-8">
        <Link href="/" className="group flex items-center gap-3 rounded-xl focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300">
          <LogoMark className="transition-transform duration-200 group-hover:rotate-3" />
          <span className="text-[15px] font-semibold tracking-[-0.02em] text-white">NexRoute</span>
        </Link>

        <nav aria-label="Основная навигация" className="hidden items-center gap-1 lg:flex">
          {navigation.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className="rounded-lg px-3.5 py-2 text-sm text-zinc-400 transition hover:bg-white/[0.035] hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300"
            >
              {item.label}
            </Link>
          ))}
        </nav>

        <div className="hidden items-center gap-2 lg:flex">
          <a
            href={projectLinks.github}
            target="_blank"
            rel="noreferrer"
            className="inline-flex h-10 items-center gap-2 rounded-xl border border-white/10 bg-white/[0.025] px-4 text-sm font-medium text-zinc-200 transition hover:border-white/16 hover:bg-white/[0.05] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300"
          >
            <Github className="size-4" aria-hidden="true" /> GitHub
          </a>
          <Link
            href="/download"
            className="inline-flex h-10 items-center gap-2 rounded-xl bg-cyan-300 px-4 text-sm font-semibold text-[#041013] shadow-[0_0_24px_rgba(34,211,238,.18)] transition hover:bg-cyan-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-100 focus-visible:ring-offset-2 focus-visible:ring-offset-[#050709]"
          >
            <Download className="size-4" aria-hidden="true" /> Скачать
          </Link>
        </div>

        <button
          type="button"
          aria-label={open ? "Закрыть меню" : "Открыть меню"}
          aria-expanded={open}
          onClick={() => setOpen((value: boolean) => !value)}
          className="inline-flex size-10 items-center justify-center rounded-xl border border-white/10 bg-white/[0.03] text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300 lg:hidden"
        >
          {open ? <X className="size-5" /> : <Menu className="size-5" />}
        </button>
      </div>

      {open && (
        <div className="fixed inset-x-0 bottom-0 top-17 z-40 overflow-y-auto border-t border-white/8 bg-[#050709]/98 px-4 py-6 backdrop-blur-xl lg:hidden">
          <nav aria-label="Мобильная навигация" className="mx-auto flex max-w-lg flex-col gap-2">
            {navigation.map((item) => (
              <Link
                key={item.href}
                href={item.href}
                onClick={() => setOpen(false)}
                className="rounded-2xl border border-white/8 bg-white/[0.025] px-5 py-4 text-lg font-medium text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300"
              >
                {item.label}
              </Link>
            ))}
            <a
              href={projectLinks.github}
              target="_blank"
              rel="noreferrer"
              className="mt-3 inline-flex items-center justify-center gap-2 rounded-2xl border border-white/10 px-5 py-4 font-medium text-white"
            >
              <Github className="size-5" /> GitHub
            </a>
            <Link
              href="/download"
              onClick={() => setOpen(false)}
              className="inline-flex items-center justify-center gap-2 rounded-2xl bg-cyan-300 px-5 py-4 font-semibold text-[#041013]"
            >
              <Download className="size-5" /> Скачать NexRoute
            </Link>
          </nav>
        </div>
      )}
    </header>
  );
}
