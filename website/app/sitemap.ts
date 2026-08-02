import type { MetadataRoute } from "next";
import { siteConfig } from "@/lib/metadata";

const paths = [
  "",
  "/features",
  "/download",
  "/docs",
  "/docs/getting-started",
  "/docs/service-matrix",
  "/docs/strategy-lab",
  "/docs/updates",
  "/docs/security",
  "/docs/diagnostics",
  "/docs/architecture",
  "/docs/compatibility",
  "/security",
  "/faq",
  "/changelog",
];

export default function sitemap(): MetadataRoute.Sitemap {
  return paths.map((path) => ({
    url: `${siteConfig.url}${path}`,
    lastModified: new Date(),
    changeFrequency: path === "" || path === "/download" ? "daily" : "weekly",
    priority: path === "" ? 1 : path === "/download" ? 0.9 : 0.7,
  }));
}
