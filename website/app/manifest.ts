import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "NexRoute",
    short_name: "NexRoute",
    description: "Управление сетевыми стратегиями для Windows 10 и Windows 11.",
    start_url: "/",
    display: "standalone",
    background_color: "#050709",
    theme_color: "#050709",
    lang: "ru",
    icons: [{ src: "/icon.svg", sizes: "any", type: "image/svg+xml" }],
  };
}
