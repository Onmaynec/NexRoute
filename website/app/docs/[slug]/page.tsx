import { notFound } from "next/navigation";
import type { Metadata } from "next";
import { docsPages } from "@/content/docs";
import { createMetadata } from "@/lib/metadata";
import { DocArticle } from "@/components/docs/doc-article";

export function generateStaticParams() {
  return Object.keys(docsPages).map((slug) => ({ slug }));
}

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const { slug } = await params;
  const page = docsPages[slug];
  if (!page) return {};
  return createMetadata(`${page.title} — документация`, page.description, `/docs/${slug}`);
}

export default async function DocumentationPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const page = docsPages[slug];
  if (!page) notFound();
  return <DocArticle page={page} />;
}
