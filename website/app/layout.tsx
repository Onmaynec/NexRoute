import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import "./globals.css";
import { SiteHeader } from "@/components/layout/site-header";
import { SiteFooter } from "@/components/layout/site-footer";
import { siteConfig } from "@/lib/metadata";

export const metadata: Metadata = {
  metadataBase: new URL(siteConfig.url),
  title: {
    default: "NexRoute — управление сетевыми стратегиями для Windows",
    template: "%s · NexRoute",
  },
  description: siteConfig.description,
  applicationName: "NexRoute",
  authors: [{ name: "Onmaynec", url: "https://github.com/Onmaynec" }],
  creator: "Onmaynec",
  category: "technology",
  keywords: ["NexRoute", "Windows", "Service Matrix", "Strategy Lab", "DPI", "WinDivert", "open source"],
  robots: { index: true, follow: true },
};

export const viewport: Viewport = {
  themeColor: "#050709",
  colorScheme: "dark",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="ru">
      <body>
        <a
          href="#main-content"
          className="fixed left-4 top-3 z-[100] -translate-y-20 rounded-lg bg-cyan-300 px-4 py-2 text-sm font-semibold text-[#041013] transition focus:translate-y-0"
        >
          Перейти к содержимому
        </a>
        <SiteHeader />
        <main id="main-content">{children}</main>
        <SiteFooter />
      </body>
    </html>
  );
}
