import { CheckCircle2, ShieldCheck, TerminalSquare } from "lucide-react";
import { getLatestStableRelease } from "@/lib/github";
import { createMetadata } from "@/lib/metadata";
import { DownloadCard } from "@/components/marketing/download-card";
import { CodeBlock } from "@/components/ui/code-block";
import { FeatureCard, PageHero, SectionHeading } from "@/components/ui/primitives";

export const revalidate = 900;
export const metadata = createMetadata(
  "Скачать NexRoute для Windows",
  "Скачайте последнюю стабильную версию NexRoute для Windows 10 и Windows 11 x64.",
  "/download",
);

export default async function DownloadPage() {
  const release = await getLatestStableRelease();
  const archive = release?.archive?.name || "NexRoute-X.Y.Z-win-x64.zip";
  return (
    <>
      <PageHero
        eyebrow="DOWNLOAD"
        title="Скачать NexRoute"
        description="Последняя стабильная версия для Windows 10 и Windows 11 x64. Release-данные загружаются из публичного GitHub API."
      />
      <div className="mx-auto max-w-6xl px-4 py-20 sm:px-6 sm:py-28 lg:px-8">
        <DownloadCard release={release} />
        <p className="mt-5 text-center text-xs text-zinc-600">Windows 10/11 x64 · ZIP archive · Administrator rights required</p>

        <section className="mt-24">
          <SectionHeading title="Перед установкой" description="Несколько обязательных шагов помогут избежать проблем при первом запуске." />
          <div className="mt-10 grid gap-4 md:grid-cols-2">
            {[
              "Полностью распакуйте ZIP в отдельную папку.",
              "Не запускайте файлы непосредственно из архива.",
              "Для установки службы потребуются права администратора.",
              "При желании проверьте SHA-256 и GitHub attestation.",
            ].map((item, index) => (
              <div key={item} className="flex gap-4 rounded-2xl border border-white/8 bg-white/[0.02] p-5">
                <span className="font-mono text-xs text-cyan-300">0{index + 1}</span>
                <p className="text-sm leading-6 text-zinc-300">{item}</p>
              </div>
            ))}
          </div>
        </section>

        <section className="mt-24">
          <SectionHeading title="Системные требования" />
          <div className="mt-10 grid gap-4 md:grid-cols-3">
            <FeatureCard icon={TerminalSquare} title="Windows" description="Windows 10 x64 или Windows 11 x64. Windows x86, Linux и macOS этой сборкой не поддерживаются." />
            <FeatureCard icon={CheckCircle2} title="PowerShell и права" description="Windows PowerShell 5.1 или новее и права администратора для установки и перезапуска службы." />
            <FeatureCard icon={ShieldCheck} title="Дополнительные инструменты" description="curl.exe для отдельных функций Strategy Lab и доступ к GitHub Releases для онлайн-обновлений." />
          </div>
        </section>

        <section className="mt-24">
          <SectionHeading
            eyebrow="VERIFY"
            title="Проверка файла"
            description="SHA-256 помогает обнаружить повреждение или изменение архива. Attestation дополнительно связывает asset с workflow и исходным commit."
          />
          <div className="mt-10 grid gap-4 lg:grid-cols-2">
            <div>
              <h3 className="mb-3 text-sm font-medium text-white">1. Рассчитайте SHA-256</h3>
              <CodeBlock language="powershell" title="PowerShell" value={`Get-FileHash .\\${archive} -Algorithm SHA256`} />
              <p className="mt-3 text-sm leading-6 text-zinc-500">Сравните значение Hash с первой строкой опубликованного файла .sha256.</p>
            </div>
            <div>
              <h3 className="mb-3 text-sm font-medium text-white">2. Проверьте build provenance</h3>
              <CodeBlock language="powershell" title="GitHub CLI" value={`gh attestation verify \`\n  .\\${archive} \`\n  --repo Onmaynec/NexRoute`} />
              <p className="mt-3 text-sm leading-6 text-zinc-500">GitHub CLI нужен только для этой дополнительной онлайн-проверки.</p>
            </div>
          </div>
        </section>
      </div>
    </>
  );
}
