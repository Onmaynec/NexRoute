import type { Metadata } from "next";

const fallbackUrl = "http://localhost:3000";

export const siteConfig = {
  name: "NexRoute",
  description:
    "NexRoute объединяет Service Matrix, Strategy Lab, диагностику и безопасные обновления в одном консольном интерфейсе для Windows 10 и Windows 11.",
  url: process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/$/, "") || fallbackUrl,
  repository: "https://github.com/Onmaynec/NexRoute",
  releases: "https://github.com/Onmaynec/NexRoute/releases",
  issues: "https://github.com/Onmaynec/NexRoute/issues",
};

export function createMetadata(
  title: string,
  description: string,
  path = "",
): Metadata {
  const canonical = `${siteConfig.url}${path}`;
  return {
    title,
    description,
    alternates: { canonical },
    openGraph: {
      title,
      description,
      url: canonical,
      siteName: siteConfig.name,
      locale: "ru_RU",
      type: "website",
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
    },
  };
}
