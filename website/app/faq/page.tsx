import { faqItems } from "@/content/faq";
import { createMetadata } from "@/lib/metadata";
import { PageHero } from "@/components/ui/primitives";
import { FAQAccordion } from "@/components/ui/faq-accordion";

export const metadata = createMetadata(
  "FAQ NexRoute",
  "Ответы на частые вопросы об установке, стратегиях, Service Matrix, обновлениях и безопасности NexRoute.",
  "/faq",
);

export default function FAQPage() {
  const categories = [...new Set(faqItems.map((item) => item.category))];
  return (
    <>
      <PageHero
        eyebrow="FAQ"
        title="Частые вопросы"
        description="Ответы об установке, стратегиях, Service Matrix, обновлениях, безопасности и типичных проблемах."
      />
      <div className="mx-auto max-w-5xl px-4 py-20 sm:px-6 sm:py-28 lg:px-8">
        <div className="space-y-14">
          {categories.map((category) => (
            <section key={category}>
              <h2 className="mb-5 text-2xl font-semibold tracking-[-0.03em] text-white">{category}</h2>
              <FAQAccordion items={faqItems.filter((item) => item.category === category)} />
            </section>
          ))}
        </div>
      </div>
    </>
  );
}
