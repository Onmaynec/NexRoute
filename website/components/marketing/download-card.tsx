import { CalendarDays, Download, ExternalLink, FileCheck2, FileDown } from "lucide-react";
import type { StableRelease } from "@/lib/github";
import { excerptMarkdown, formatBytes, formatDate } from "@/lib/utils";
import { ButtonLink, StatusBadge } from "@/components/ui/primitives";

export function DownloadCard({ release }: { release: StableRelease | null }) {
  const archiveUrl = release?.archive?.browser_download_url || "https://github.com/Onmaynec/NexRoute/releases/latest";
  return (
    <article className="relative overflow-hidden rounded-[28px] border border-cyan-300/14 bg-white/[0.025] p-6 shadow-[0_28px_100px_rgba(0,0,0,.38),inset_0_1px_rgba(255,255,255,.035)] sm:p-8">
      <div className="pointer-events-none absolute -right-24 -top-24 size-64 rounded-full bg-cyan-300/10 blur-3xl" />
      <div className="relative">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <StatusBadge status="success">Stable release</StatusBadge>
            <h2 className="mt-4 text-3xl font-semibold tracking-[-0.04em] text-white">
              {release ? `NexRoute ${release.version}` : "Последняя стабильная версия"}
            </h2>
            <p className="mt-3 max-w-2xl text-sm leading-6 text-zinc-400">
              {release?.body ? excerptMarkdown(release.body) : "GitHub API временно недоступен. Откройте официальный список Releases, чтобы увидеть актуальную стабильную версию."}
            </p>
          </div>
          <div className="rounded-2xl border border-white/8 bg-black/20 p-4 text-right">
            <p className="font-mono text-[10px] uppercase tracking-[.15em] text-zinc-600">Platform</p>
            <p className="mt-2 text-sm font-medium text-white">Windows 10/11 x64</p>
          </div>
        </div>

        <div className="mt-7 grid gap-3 sm:grid-cols-3">
          <div className="rounded-2xl border border-white/7 bg-black/15 p-4">
            <FileDown className="size-4 text-cyan-300" />
            <p className="mt-3 text-xs text-zinc-600">Архив</p>
            <p className="mt-1 break-all text-sm text-zinc-200">{release?.archive?.name || "NexRoute-X.Y.Z-win-x64.zip"}</p>
          </div>
          <div className="rounded-2xl border border-white/7 bg-black/15 p-4">
            <CalendarDays className="size-4 text-cyan-300" />
            <p className="mt-3 text-xs text-zinc-600">Публикация</p>
            <p className="mt-1 text-sm text-zinc-200">{formatDate(release?.publishedAt)}</p>
          </div>
          <div className="rounded-2xl border border-white/7 bg-black/15 p-4">
            <FileCheck2 className="size-4 text-cyan-300" />
            <p className="mt-3 text-xs text-zinc-600">Размер ZIP</p>
            <p className="mt-1 text-sm text-zinc-200">{formatBytes(release?.archive?.size)}</p>
          </div>
        </div>

        <div className="mt-7 flex flex-col gap-3 sm:flex-row">
          <ButtonLink href={archiveUrl} external className="sm:min-w-56">
            <Download className="size-4" /> Скачать для Windows
          </ButtonLink>
          <ButtonLink href={release?.htmlUrl || "https://github.com/Onmaynec/NexRoute/releases"} external variant="secondary">
            <ExternalLink className="size-4" /> Посмотреть релиз на GitHub
          </ButtonLink>
        </div>
        <div className="mt-5 flex flex-wrap items-center gap-x-5 gap-y-2 text-xs text-zinc-600">
          {release?.checksum && (
            <a className="transition hover:text-cyan-200" href={release.checksum.browser_download_url}>
              Скачать {release.checksum.name}
            </a>
          )}
          <span>ZIP archive</span>
          <span>Administrator rights required</span>
        </div>
      </div>
    </article>
  );
}
