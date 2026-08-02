import Link from "next/link";
import { ArrowLeft, ArrowRight, ExternalLink } from "lucide-react";
import type { DocPage } from "@/content/docs";
import { CodeBlock } from "@/components/ui/code-block";

export function DocArticle({ page }: { page: DocPage }) {
  return (
    <div className="grid min-h-[70vh] xl:grid-cols-[minmax(0,820px)_220px] xl:gap-14">
      <article className="min-w-0 px-4 py-12 sm:px-8 lg:px-12 xl:px-16">
        <div className="flex items-center gap-2 text-xs text-zinc-600">
          <Link href="/docs" className="hover:text-zinc-300">Документация</Link>
          <span>/</span>
          <span className="text-zinc-400">{page.title}</span>
        </div>
        <h1 className="mt-5 text-balance text-[clamp(2.5rem,6vw,4.5rem)] font-semibold leading-[1] tracking-[-0.05em] text-white">{page.title}</h1>
        <p className="mt-5 max-w-3xl text-lg leading-8 text-zinc-400">{page.description}</p>
        <a href={page.sourceUrl} target="_blank" rel="noreferrer" className="mt-5 inline-flex items-center gap-1.5 text-sm text-cyan-200 hover:text-cyan-100">
          Открыть исходный документ <ExternalLink className="size-3.5" />
        </a>

        <div className="mt-12 space-y-14">
          {page.sections.map((section) => (
            <section id={section.id} key={section.id} className="scroll-mt-28">
              <h2 className="text-2xl font-semibold tracking-[-0.03em] text-white">{section.title}</h2>
              {section.paragraphs?.map((paragraph) => (
                <p key={paragraph} className="mt-4 text-base leading-8 text-zinc-400">{paragraph}</p>
              ))}
              {section.bullets && (
                <ul className="mt-5 space-y-3">
                  {section.bullets.map((bullet) => (
                    <li key={bullet} className="flex gap-3 text-sm leading-7 text-zinc-400">
                      <span className="mt-3 size-1.5 shrink-0 rounded-full bg-cyan-300/80" />
                      <span>{bullet}</span>
                    </li>
                  ))}
                </ul>
              )}
              {section.code && <div className="mt-6"><CodeBlock {...section.code} /></div>}
              {section.note && (
                <div className="mt-6 rounded-2xl border border-amber-300/13 bg-amber-300/[0.04] p-4 text-sm leading-6 text-amber-100/75">
                  {section.note}
                </div>
              )}
            </section>
          ))}
        </div>

        <nav aria-label="Предыдущая и следующая страница" className="mt-16 grid gap-3 border-t border-white/8 pt-8 sm:grid-cols-2">
          {page.previous ? (
            <Link href={page.previous.href} className="rounded-2xl border border-white/8 bg-white/[0.02] p-4 text-sm text-zinc-400 transition hover:border-cyan-300/16 hover:text-white">
              <span className="inline-flex items-center gap-2"><ArrowLeft className="size-4" /> Назад</span>
              <span className="mt-2 block font-medium text-white">{page.previous.label}</span>
            </Link>
          ) : <div />}
          {page.next && (
            <Link href={page.next.href} className="rounded-2xl border border-white/8 bg-white/[0.02] p-4 text-right text-sm text-zinc-400 transition hover:border-cyan-300/16 hover:text-white">
              <span className="inline-flex items-center gap-2">Далее <ArrowRight className="size-4" /></span>
              <span className="mt-2 block font-medium text-white">{page.next.label}</span>
            </Link>
          )}
        </nav>
      </article>

      <aside className="sticky top-24 hidden h-fit py-16 pr-8 xl:block">
        <p className="font-mono text-[10px] uppercase tracking-[.17em] text-zinc-600">На этой странице</p>
        <nav className="mt-4 space-y-2 border-l border-white/8 pl-4" aria-label="Оглавление страницы">
          {page.sections.map((section) => (
            <a key={section.id} href={`#${section.id}`} className="block text-xs leading-5 text-zinc-600 transition hover:text-cyan-200">
              {section.title}
            </a>
          ))}
        </nav>
      </aside>
    </div>
  );
}
