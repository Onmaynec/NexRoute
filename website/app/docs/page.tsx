import Link from "next/link";
import { ArrowRight, Search } from "lucide-react";
import { docsOverviewCards } from "@/content/docs";
import { createMetadata } from "@/lib/metadata";

export const metadata = createMetadata(
  "Документация NexRoute",
  "Руководства по установке, настройке сервисов, тестированию стратегий, обновлениям и проверке релизов.",
  "/docs",
);

export default function DocsIndexPage() {
  return (
    <div className="px-4 py-16 sm:px-8 lg:px-12 xl:px-16">
      <div className="max-w-4xl">
        <p className="font-mono text-xs uppercase tracking-[.18em] text-cyan-300">DOCUMENTATION</p>
        <h1 className="mt-5 text-balance text-[clamp(3rem,7vw,5rem)] font-semibold leading-[.98] tracking-[-0.055em] text-white">Документация NexRoute</h1>
        <p className="mt-6 max-w-3xl text-lg leading-8 text-zinc-400">Руководства по установке, настройке сервисов, тестированию стратегий, обновлениям и проверке релизов.</p>
        <div className="mt-8 flex max-w-md items-center gap-3 rounded-2xl border border-white/8 bg-white/[0.025] px-4 py-3 text-sm text-zinc-600">
          <Search className="size-4" /> Используйте поиск в боковой панели
        </div>
      </div>
      <div className="mt-14 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        {docsOverviewCards.map((card) => (
          <Link key={card.href} href={card.href} className="group rounded-3xl border border-white/8 bg-white/[0.02] p-6 transition hover:-translate-y-0.5 hover:border-cyan-300/18 hover:bg-white/[0.032]">
            <h2 className="text-lg font-semibold text-white">{card.title}</h2>
            <p className="mt-3 text-sm leading-6 text-zinc-500">{card.description}</p>
            <span className="mt-6 inline-flex items-center gap-2 text-sm text-cyan-200">Открыть <ArrowRight className="size-4 transition-transform group-hover:translate-x-1" /></span>
          </Link>
        ))}
      </div>
    </div>
  );
}
