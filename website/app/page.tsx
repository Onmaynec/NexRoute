import Link from "next/link";
import {
  ArrowRight,
  BookOpen,
  CheckCircle2,
  Download,
  ExternalLink,
  Github,
  HardDriveDownload,
  ShieldCheck,
  SlidersHorizontal,
  TerminalSquare,
} from "lucide-react";
import { faqItems } from "@/content/faq";
import { featureCards, projectLinks, summaryStats } from "@/content/site";
import { getLatestStableRelease } from "@/lib/github";
import { siteConfig } from "@/lib/metadata";
import { Badge, ButtonLink, FeatureCard, InlineLink, SectionHeading } from "@/components/ui/primitives";
import { Reveal } from "@/components/ui/reveal";
import { FAQAccordion } from "@/components/ui/faq-accordion";
import { GitHubStats } from "@/components/marketing/github-stats";
import {
  AnimatedRouteGraph,
  ReleaseVerificationDemo,
  RollbackDemo,
  ServiceMatrixDemo,
  StrategyLabDemo,
  TerminalWindow,
  UpdateFlow,
} from "@/components/product/demos";

export const revalidate = 900;

export default async function HomePage() {
  const release = await getLatestStableRelease();
  const downloadHref = release?.archive?.browser_download_url || `${projectLinks.releases}/latest`;
  const softwareJsonLd = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: "NexRoute",
    applicationCategory: "UtilitiesApplication",
    operatingSystem: "Windows 10 x64, Windows 11 x64",
    description: siteConfig.description,
    license: "https://opensource.org/license/mit",
    codeRepository: projectLinks.github,
    downloadUrl: downloadHref,
    softwareVersion: release?.version,
  };

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(softwareJsonLd).replace(/</g, "\\u003c") }}
      />

      <section className="noise relative overflow-hidden border-b border-white/8 pb-20 pt-16 sm:pb-28 sm:pt-24">
        <div className="network-grid absolute inset-0 opacity-45" />
        <div className="glow-orb glow-orb-one" />
        <div className="glow-orb glow-orb-two" />
        <div className="relative mx-auto grid max-w-7xl items-center gap-14 px-4 sm:px-6 lg:grid-cols-[.92fr_1.08fr] lg:px-8">
          <Reveal>
            <div>
              <Badge>NexRoute · Open Source · Windows 10/11</Badge>
              <h1 className="mt-7 text-balance text-[clamp(3rem,7vw,5.5rem)] font-semibold leading-[.96] tracking-[-0.058em] text-white">
                Управляйте сетевыми стратегиями. Без лишней сложности.
              </h1>
              <p className="mt-6 max-w-2xl text-pretty text-lg leading-8 text-zinc-400">
                NexRoute объединяет готовые стратегии, профили сервисов, диагностику и безопасные обновления в одном понятном консольном интерфейсе.
              </p>
              <div className="mt-8 flex flex-col gap-3 sm:flex-row">
                <ButtonLink href={downloadHref} external className="w-full sm:w-auto">
                  <Download className="size-4" /> Скачать последнюю версию
                </ButtonLink>
                <ButtonLink href={projectLinks.github} external variant="secondary" className="w-full sm:w-auto">
                  <Github className="size-4" /> Открыть на GitHub
                </ButtonLink>
              </div>
              <Link href="/docs" className="mt-5 inline-flex items-center gap-2 text-sm text-zinc-400 transition hover:text-cyan-200">
                Перейти к документации <ArrowRight className="size-4" />
              </Link>
              <p className="mt-6 text-xs text-zinc-600">Windows 10/11 x64 · Открытый исходный код · MIT License</p>
              <div className="mt-7"><GitHubStats /></div>
            </div>
          </Reveal>

          <Reveal delay={0.08} className="relative">
            <div className="absolute -inset-10 opacity-45"><AnimatedRouteGraph /></div>
            <div className="relative"><TerminalWindow /></div>
            <div className="absolute -bottom-5 -left-3 hidden rounded-2xl border border-white/10 bg-[#071015]/90 p-3 shadow-xl backdrop-blur-xl sm:block">
              <p className="font-mono text-[10px] uppercase tracking-[.16em] text-zinc-600">Integrity</p>
              <p className="mt-1 flex items-center gap-2 text-xs text-emerald-200"><CheckCircle2 className="size-3.5" /> verified</p>
            </div>
            <div className="absolute -right-3 top-12 hidden rounded-2xl border border-white/10 bg-[#071015]/90 p-3 shadow-xl backdrop-blur-xl sm:block">
              <p className="font-mono text-[10px] uppercase tracking-[.16em] text-zinc-600">Channel</p>
              <p className="mt-1 text-xs text-cyan-200">stable</p>
            </div>
          </Reveal>
        </div>
      </section>

      <section className="border-b border-white/8 bg-white/[0.015]">
        <div className="mx-auto grid max-w-7xl grid-cols-2 px-4 sm:px-6 lg:grid-cols-4 lg:px-8">
          {summaryStats.map((item) => (
            <div key={item.label} className="border-white/8 px-3 py-7 first:border-l-0 lg:border-l">
              <p className="text-xl font-semibold tracking-[-0.03em] text-white sm:text-2xl">{item.value}</p>
              <p className="mt-1 text-xs text-zinc-600">{item.label}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="py-24 sm:py-32">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <Reveal>
            <SectionHeading
              title="Всё необходимое для управления стратегиями"
              description="NexRoute объединяет настройку сервисов, тестирование, диагностику и обновления в единой системе."
            />
          </Reveal>
          <div className="mt-12 grid gap-4 lg:grid-cols-6">
            {featureCards.map((feature, index) => (
              <Reveal key={feature.title} delay={index * 0.05} className={index < 2 ? "lg:col-span-3" : "lg:col-span-2"}>
                <FeatureCard {...feature} className="h-full">
                  {index === 0 && <MiniMatrix />}
                  {index === 1 && <MiniLab />}
                  {index === 2 && <MiniUpdate />}
                  {index === 3 && <RollbackDemo />}
                  {index === 4 && <ReleaseVerificationDemo />}
                </FeatureCard>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      <section className="border-y border-white/8 bg-white/[0.012] py-24 sm:py-32">
        <div className="mx-auto grid max-w-7xl items-center gap-14 px-4 sm:px-6 lg:grid-cols-[.8fr_1.2fr] lg:px-8">
          <Reveal>
            <SectionHeading
              eyebrow="SERVICE MATRIX"
              title="Настройте сервисы один раз"
              description="Выберите нужные приложения и платформы. NexRoute подготовит отдельные доменные и IP-списки и подключит их к совместимым стратегиям."
            />
            <div className="mt-8 space-y-5">
              <FeatureLine title="Точные профили">Используются отдельные правила для каждого включённого сервиса.</FeatureLine>
              <FeatureLine title="Автоматическая синхронизация">Общие домены сохраняются, пока они нужны хотя бы одному активному профилю.</FeatureLine>
              <FeatureLine title="Состояние между запусками">Выбранная конфигурация сохраняется и безопасно восстанавливается.</FeatureLine>
            </div>
            <div className="mt-8"><InlineLink href="/docs/service-matrix">Документация Service Matrix</InlineLink></div>
          </Reveal>
          <Reveal delay={0.08}><ServiceMatrixDemo /></Reveal>
        </div>
      </section>

      <section className="py-24 sm:py-32">
        <div className="mx-auto grid max-w-7xl items-center gap-14 px-4 sm:px-6 lg:grid-cols-2 lg:px-8">
          <Reveal className="order-2 lg:order-1"><StrategyLabDemo /></Reveal>
          <Reveal delay={0.08} className="order-1 lg:order-2">
            <SectionHeading
              eyebrow="STRATEGY LAB"
              title="Не угадывайте. Проверяйте."
              description="Запустите последовательное тестирование стратегий и сравните результаты в одном интерфейсе."
            />
            <ul className="mt-8 grid gap-3 sm:grid-cols-2">
              {[
                "Последовательная проверка",
                "Понятные статусы",
                "Отображение результата",
                "Выбор подходящего варианта",
                "Повторная проверка при изменении сети",
              ].map((item) => (
                <li key={item} className="flex items-center gap-3 rounded-xl border border-white/7 bg-white/[0.02] px-3 py-3 text-sm text-zinc-400">
                  <span className="size-1.5 rounded-full bg-cyan-300" /> {item}
                </li>
              ))}
            </ul>
            <div className="mt-8"><InlineLink href="/docs/strategy-lab">Открыть руководство Strategy Lab</InlineLink></div>
          </Reveal>
        </div>
      </section>

      <section className="border-y border-white/8 bg-white/[0.012] py-24 sm:py-32">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <Reveal>
            <SectionHeading
              eyebrow="SAFE UPDATE FLOW"
              title="Каждое обновление проходит проверку"
              description="NexRoute проверяет версию, структуру архива и контрольную сумму до того, как изменит текущую установку."
              align="center"
            />
          </Reveal>
          <Reveal delay={0.08} className="mt-12"><UpdateFlow /></Reveal>
          <Reveal delay={0.14}>
            <div className="mx-auto mt-8 max-w-3xl rounded-2xl border border-cyan-300/12 bg-cyan-300/[0.04] p-5 text-center text-sm leading-6 text-zinc-300">
              При ошибке NexRoute автоматически восстанавливает предыдущую рабочую версию.
            </div>
          </Reveal>
          <div className="mt-8 text-center"><InlineLink href="/docs/updates">Подробнее об обновлениях</InlineLink></div>
        </div>
      </section>

      <section className="py-24 sm:py-32">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <Reveal>
            <SectionHeading
              eyebrow="VERIFIABLE BUILDS"
              title="Доверие, которое можно проверить"
              description="Официальные release assets сопровождаются контрольными суммами и build provenance attestations."
            />
          </Reveal>
          <div className="mt-12 grid gap-4 lg:grid-cols-3">
            <FeatureCard icon={ShieldCheck} title="SHA-256" description="Сравните цифровой отпечаток загруженного архива с опубликованным файлом .sha256." />
            <FeatureCard icon={Github} title="GitHub Attestations" description="Проверьте, что asset был создан workflow репозитория Onmaynec/NexRoute." />
            <FeatureCard icon={BookOpen} title="Open Source" description="Изучите исходный код, release workflow и процесс сборки непосредственно на GitHub." />
          </div>
          <div className="mt-8 grid items-stretch gap-4 lg:grid-cols-[1.2fr_.8fr]">
            <div className="rounded-3xl border border-white/8 bg-[#05090c] p-5 font-mono text-sm leading-7 text-zinc-300 sm:p-7">
              <p className="text-[10px] uppercase tracking-[.16em] text-cyan-300">PowerShell</p>
              <pre className="mt-4 overflow-x-auto"><code>gh attestation verify `{"\n"}  .\NexRoute-X.Y.Z-win-x64.zip `{"\n"}  --repo Onmaynec/NexRoute</code></pre>
            </div>
            <div className="rounded-3xl border border-white/8 bg-white/[0.025] p-6">
              <p className="text-lg font-semibold text-white">Source → Workflow → Asset</p>
              <p className="mt-3 text-sm leading-6 text-zinc-400">Attestation связывает digest файла с workflow и исходным commit. Она дополняет checksum, но не заменяет Windows Authenticode.</p>
              <div className="mt-6"><InlineLink href="/security">Открыть раздел безопасности</InlineLink></div>
            </div>
          </div>
        </div>
      </section>

      <section className="border-y border-white/8 bg-white/[0.012] py-24 sm:py-32">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <Reveal><SectionHeading eyebrow="QUICK START" title="От загрузки до запуска — несколько шагов" align="center" /></Reveal>
          <div className="mt-12 grid gap-4 md:grid-cols-2 lg:grid-cols-4">
            {[
              ["01", "Скачайте релиз", "Получите ZIP последней стабильной версии на странице Download или в GitHub Releases."],
              ["02", "Распакуйте архив", "Полностью извлеките файлы в отдельную папку. Не запускайте BAT или CMD прямо из ZIP."],
              ["03", "Запустите NexRoute", "Откройте NexRoute.lnk, nexroute.bat или service.bat от имени администратора."],
              ["04", "Выберите стратегию", "Запустите подходящую стратегию и при необходимости настройте Service Matrix."],
            ].map(([number, title, text]) => (
              <Reveal key={number} delay={Number(number) * 0.04}>
                <article className="h-full rounded-3xl border border-white/8 bg-white/[0.02] p-6">
                  <span className="font-mono text-xs text-cyan-300">{number}</span>
                  <h3 className="mt-5 text-xl font-semibold text-white">{title}</h3>
                  <p className="mt-3 text-sm leading-6 text-zinc-400">{text}</p>
                </article>
              </Reveal>
            ))}
          </div>
          <div className="mt-8 text-center"><ButtonLink href="/docs/getting-started" variant="secondary">Открыть руководство <ArrowRight className="size-4" /></ButtonLink></div>
        </div>
      </section>

      <section className="py-24 sm:py-32">
        <div className="mx-auto max-w-5xl px-4 sm:px-6 lg:px-8">
          <Reveal><SectionHeading title="Частые вопросы" description="Короткие ответы о запуске, стратегиях, обновлениях и проверке релиза." align="center" /></Reveal>
          <Reveal delay={0.08} className="mt-10"><FAQAccordion items={faqItems.slice(0, 6)} /></Reveal>
          <div className="mt-8 text-center"><InlineLink href="/faq">Все вопросы и ответы</InlineLink></div>
        </div>
      </section>

      <section className="pb-24 sm:pb-32">
        <div className="relative mx-auto max-w-7xl overflow-hidden rounded-[32px] border border-cyan-300/13 bg-[#071015] px-5 py-16 text-center sm:px-10 sm:py-20 lg:px-16">
          <div className="network-grid absolute inset-0 opacity-35" />
          <div className="absolute inset-x-1/4 -top-32 h-64 rounded-full bg-cyan-300/12 blur-3xl" />
          <div className="relative mx-auto max-w-3xl">
            <TerminalSquare className="mx-auto size-8 text-cyan-300" />
            <h2 className="mt-6 text-balance text-[clamp(2.3rem,5vw,4rem)] font-semibold leading-[1] tracking-[-0.05em] text-white">Готовы настроить NexRoute?</h2>
            <p className="mt-5 text-lg leading-8 text-zinc-400">Скачайте последнюю стабильную версию или изучите исходный код проекта на GitHub.</p>
            <div className="mt-8 flex flex-col justify-center gap-3 sm:flex-row">
              <ButtonLink href={downloadHref} external><Download className="size-4" /> Скачать NexRoute</ButtonLink>
              <ButtonLink href={projectLinks.github} external variant="secondary"><Github className="size-4" /> Открыть GitHub</ButtonLink>
            </div>
          </div>
        </div>
      </section>
    </>
  );
}

function FeatureLine({ title, children }: { title: string; children: string }) {
  return (
    <div className="flex gap-4">
      <div className="mt-1 flex size-8 shrink-0 items-center justify-center rounded-xl border border-cyan-300/13 bg-cyan-300/[0.045] text-cyan-200"><CheckCircle2 className="size-4" /></div>
      <div><h3 className="font-medium text-white">{title}</h3><p className="mt-1 text-sm leading-6 text-zinc-500">{children}</p></div>
    </div>
  );
}

function MiniMatrix() {
  return (
    <div className="grid grid-cols-3 gap-2">
      {["YouTube", "Discord", "ChatGPT", "Telegram", "Signal", "TikTok"].map((service, index) => (
        <div key={service} className={`rounded-lg border px-2 py-2 text-center text-[10px] ${index < 4 ? "border-cyan-300/12 bg-cyan-300/[0.04] text-cyan-100" : "border-white/6 bg-black/15 text-zinc-600"}`}>{service}</div>
      ))}
    </div>
  );
}

function MiniLab() {
  return (
    <div className="space-y-2 font-mono text-[10px]">
      {["General ALT", "Discord Filter", "TLS Split"].map((item, index) => (
        <div key={item} className="flex items-center justify-between rounded-lg border border-white/6 bg-black/15 px-3 py-2"><span className="text-zinc-400">{item}</span><span className={index === 2 ? "text-rose-300" : "text-emerald-300"}>{index === 2 ? "FAILED" : "PASSED"}</span></div>
      ))}
    </div>
  );
}

function MiniUpdate() {
  return (
    <div className="grid grid-cols-3 gap-2">
      {[
        [Download, "Download"],
        [ShieldCheck, "Verify"],
        [HardDriveDownload, "Backup"],
      ].map(([Icon, label]) => {
        const Component = Icon as typeof Download;
        return <div key={label as string} className="rounded-lg border border-white/6 bg-black/15 p-3 text-center"><Component className="mx-auto size-4 text-cyan-300" /><p className="mt-2 text-[10px] text-zinc-500">{label as string}</p></div>;
      })}
    </div>
  );
}
