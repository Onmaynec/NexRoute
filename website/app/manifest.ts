import type { MetadataRoute } from "next";

export const dynamic = "force-static";

export default function manifest(): MetadataRoute.Manifest {
  const basePath = process.env.NEXT_PUBLIC_BASE_PATH?.replace(/\/$/, "") || "";

  return {
    name: "NexRoute",
    short_name: "NexRoute",
    description: "Управление сетевыми стратегиями для Windows 10 и Windows 11.",
    start_url: `${basePath}/`,
    display: "standalone",
    background_color: "#050709",
    theme_color: "#050709",
    lang: "ru",
    icons: [{ src: `${basePath}/icon.svg`, sizes: "any", type: "image/svg+xml" }],
  };
}
