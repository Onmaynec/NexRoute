import { ExternalLink, GitCommitHorizontal } from "lucide-react";
import { getStableReleases } from "@/lib/github";
import { createMetadata } from "@/lib/metadata";
import { excerptMarkdown, formatDate } from "@/lib/utils";
import { PageHero, StatusBadge } from "@/components/ui/primitives";

export const revalidate = 900;
export const metadata = createMetadata(
  "Changelog NexRoute",
  "История стабильных релизов NexRoute на основе GitHub Releases.",
  "/changelog",
);

const fallback = [
  { version: "0.3.2", date: "2026-08-02", summary: "GitHub build provenance attestations для ZIP и checksum asset, self-verification до публикации Release." },
  { version: "0.3.1", date: "2026-08-01", summary: "Stable updater, полный backup, сохранение пользовательского state и автоматический rollback." },
  { version: "0.3.0", date: "2026-08-01", summary: "Locked upstream, patch report и воспроизводимая online/offline сборка." },
  { version: "0.2.3", date: "2026-08-01", summary: "Изолированные Service Matrix runtime-группы, schema v2 и privacy-safe Diagnostics." },
];

export default async function ChangelogPage() {
  const releases = await getStableReleases(12);
  return (
    <>
      <PageHero
        eyebrow="CHANGELOG"
        title="История версий"
        description="Стабильные релизы загружаются из GitHub. При недоступности API используется фактическая история из CHANGELOG.md."
      />
      <div className="mx-auto max-w-5xl px-4 py-20 sm:px-6 sm:py-28 lg:px-8">
        <div className="relative space-y-6 before:absolute before:bottom-0 before:left-[19px] before:top-0 before:w-px before:bg-white/8">
          {(releases.length ? releases : fallback).map((release) => {
            const isApi = "tagName" in release;
            const version = isApi ? release.version : release.version;
            const date = isApi ? release.publishedAt : release.date;
            const summary = isApi ? excerptMarkdown(release.body, 360) : release.summary;
            const href = isApi ? release.htmlUrl : `https://github.com/Onmaynec/NexRoute/releases/tag/v${version}`;
            return (
              <article key={version} className="relative pl-14">
                <div className="absolute left-0 top-6 flex size-10 items-center justify-center rounded-full border border-cyan-300/16 bg-[#071015] text-cyan-200">
                  <GitCommitHorizontal className="size-4" />
                </div>
                <div className="rounded-3xl border border-white/8 bg-white/[0.02] p-6 sm:p-7">
                  <div className="flex flex-wrap items-center justify-between gap-3">
                    <div className="flex items-center gap-3"><h2 className="text-2xl font-semibold text-white">v{version}</h2><StatusBadge status="success">stable</StatusBadge></div>
                    <time className="text-xs text-zinc-600">{formatDate(date)}</time>
                  </div>
                  <p className="mt-4 text-sm leading-7 text-zinc-400">{summary || "Описание изменений доступно в GitHub Release."}</p>
                  <a href={href} target="_blank" rel="noreferrer" className="mt-5 inline-flex items-center gap-2 text-sm text-cyan-200 hover:text-cyan-100">
                    GitHub Release <ExternalLink className="size-3.5" />
                  </a>
                </div>
              </article>
            );
          })}
        </div>
      </div>
    </>
  );
}
