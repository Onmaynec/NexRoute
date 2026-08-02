import { ArrowRight } from "lucide-react";
import { detailedFeatures } from "@/content/site";
import { createMetadata } from "@/lib/metadata";
import { ButtonLink, PageHero } from "@/components/ui/primitives";
import { Reveal } from "@/components/ui/reveal";
import {
  ReleaseVerificationDemo,
  RollbackDemo,
  ServiceMatrixDemo,
  StrategyLabDemo,
  TerminalWindow,
  UpdateFlow,
} from "@/components/product/demos";

export const metadata = createMetadata(
  "Возможности NexRoute",
  "Подробный обзор Service Matrix, Strategy Lab, диагностики, безопасных обновлений и проверяемых релизов NexRoute.",
  "/features",
);

export default function FeaturesPage() {
  return (
    <>
      <PageHero
        eyebrow="FEATURES"
        title="Инструменты для точного управления"
        description="От выбора сервисов до безопасного обновления — NexRoute собирает ключевые операции в одном консольном интерфейсе."
      >
        <ButtonLink href="/download">Скачать NexRoute</ButtonLink>
        <ButtonLink href="/docs" variant="secondary">Открыть документацию</ButtonLink>
      </PageHero>

      <div className="mx-auto max-w-7xl px-4 py-24 sm:px-6 sm:py-32 lg:px-8">
        <div className="space-y-28">
          {detailedFeatures.map((feature, index) => {
            const Icon = feature.icon;
            return (
              <section id={feature.id} key={feature.id} className="scroll-mt-28">
                <div className={`grid items-center gap-12 lg:grid-cols-2 ${index % 2 ? "" : "lg:[&>*:first-child]:order-2"}`}>
                  <Reveal>
                    <div>
                      <div className="flex size-11 items-center justify-center rounded-2xl border border-cyan-300/14 bg-cyan-300/[0.045] text-cyan-200">
                        <Icon className="size-5" />
                      </div>
                      <p className="mt-6 font-mono text-xs uppercase tracking-[.18em] text-cyan-300">{feature.eyebrow}</p>
                      <h2 className="mt-4 text-balance text-[clamp(2.2rem,5vw,3.7rem)] font-semibold leading-[1.02] tracking-[-0.045em] text-white">{feature.title}</h2>
                      <p className="mt-5 text-lg leading-8 text-zinc-400">{feature.description}</p>
                      <ul className="mt-7 space-y-3">
                        {feature.bullets.map((item) => (
                          <li key={item} className="flex gap-3 text-sm text-zinc-400"><span className="mt-2 size-1.5 rounded-full bg-cyan-300" /> {item}</li>
                        ))}
                      </ul>
                      <div className="mt-8"><ButtonLink href={feature.href} variant="ghost">Документация <ArrowRight className="size-4" /></ButtonLink></div>
                    </div>
                  </Reveal>
                  <Reveal delay={0.08}>{renderMockup(feature.id)}</Reveal>
                </div>
              </section>
            );
          })}
        </div>
      </div>
    </>
  );
}

function renderMockup(id: string) {
  if (id === "service-matrix") return <ServiceMatrixDemo />;
  if (id === "strategy-lab") return <StrategyLabDemo />;
  if (id === "updates") return <div className="rounded-[26px] border border-white/9 bg-[#060b0f] p-5"><UpdateFlow /></div>;
  if (id === "rollback") return <RollbackDemo />;
  if (id === "verification") return <ReleaseVerificationDemo />;
  return <TerminalWindow compact />;
}
