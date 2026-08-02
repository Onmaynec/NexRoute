import Link from "next/link";
import { Github } from "lucide-react";
import { footerColumns, projectLinks } from "@/content/site";
import { LogoMark } from "@/components/layout/logo";

export function SiteFooter() {
  return (
    <footer className="border-t border-white/8 bg-[#050709]">
      <div className="mx-auto max-w-7xl px-4 py-16 sm:px-6 lg:px-8">
        <div className="grid gap-12 lg:grid-cols-[1.2fr_2fr]">
          <div>
            <Link href="/" className="inline-flex items-center gap-3 rounded-xl focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300">
              <LogoMark />
              <span className="font-semibold text-white">NexRoute</span>
            </Link>
            <p className="mt-5 max-w-sm text-sm leading-6 text-zinc-500">
              Консольная система управления сетевыми стратегиями, сервисными профилями, диагностикой и безопасными обновлениями для Windows 10/11 x64.
            </p>
            <a
              className="mt-6 inline-flex items-center gap-2 text-sm text-zinc-300 transition hover:text-cyan-200"
              href={projectLinks.github}
              target="_blank"
              rel="noreferrer"
            >
              <Github className="size-4" /> Onmaynec/NexRoute
            </a>
          </div>
          <div className="grid grid-cols-2 gap-8 sm:grid-cols-3">
            {footerColumns.map((column) => (
              <div key={column.title}>
                <h2 className="text-sm font-semibold text-white">{column.title}</h2>
                <ul className="mt-4 space-y-3">
                  {column.links.map((link) => (
                    <li key={link.href}>
                      {link.href.startsWith("http") ? (
                        <a className="text-sm text-zinc-500 transition hover:text-zinc-200" href={link.href} target="_blank" rel="noreferrer">
                          {link.label}
                        </a>
                      ) : (
                        <Link className="text-sm text-zinc-500 transition hover:text-zinc-200" href={link.href}>
                          {link.label}
                        </Link>
                      )}
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        </div>
        <div className="mt-14 flex flex-col gap-3 border-t border-white/8 pt-6 text-xs text-zinc-600 sm:flex-row sm:items-center sm:justify-between">
          <p>NexRoute · Open-source project by Onmaynec</p>
          <p>MIT License · Windows 10/11 x64</p>
        </div>
      </div>
    </footer>
  );
}
