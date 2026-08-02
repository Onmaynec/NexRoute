import { GitHubIcon } from "@/components/ui/github-icon";
import { ArrowRight, CheckCircle2, HardDriveDownload, LockKeyhole, ShieldCheck } from "lucide-react";
import { createMetadata } from "@/lib/metadata";
import { ButtonLink, FeatureCard, PageHero, SectionHeading } from "@/components/ui/primitives";
import { CodeBlock } from "@/components/ui/code-block";
import { ReleaseVerificationDemo } from "@/components/product/demos";

export const metadata = createMetadata(
  "Безопасность и проверка релизов NexRoute",
  "SHA-256, GitHub build provenance, locked upstream и backup-защита официальных релизов NexRoute.",
  "/security",
);

const sections = [
  {
    icon: LockKeyhole,
    title: "Release Assets",
    text: "Стабильный релиз содержит ZIP-архив NexRoute и соответствующий checksum-файл .sha256. Draft и prerelease не используются как основной канал обновления.",
  },
  {
    icon: ShieldCheck,
    title: "SHA-256",
    text: "Контрольная сумма — цифровой отпечаток файла. Если архив был изменён или повреждён, его SHA-256 не совпадёт с опубликованным значением.",
  },
  {
    icon: GitHubIcon,
    title: "Build Provenance",
    text: "GitHub attestation связывает опубликованный asset с workflow, репозиторием и исходным commit через Sigstore-backed сертификат.",
  },
  {
    icon: CheckCircle2,
    title: "Upstream Integrity",
    text: "При сборке NexRoute проверяет закреплённый upstream-архив, его структуру, размер и контрольную сумму до упаковки итогового релиза.",
  },
  {
    icon: HardDriveDownload,
    title: "Rollback Protection",
    text: "Перед обновлением создаётся полная резервная копия текущей установки. При ошибке предыдущая версия восстанавливается автоматически.",
  },
  {
    icon: GitHubIcon,
    title: "Open Source",
    text: "Исходный код, release workflow, Pester-контракты и документация доступны в открытом репозитории.",
  },
];

export default function SecurityPage() {
  return (
    <>
      <PageHero
        eyebrow="SECURITY"
        title="Безопасность и проверяемость"
        description="NexRoute использует несколько уровней проверки, чтобы пользователь мог убедиться в целостности официального релиза."
      >
        <ButtonLink href="/docs/security">Инструкция проверки <ArrowRight className="size-4" /></ButtonLink>
        <ButtonLink href="https://github.com/Onmaynec/NexRoute" external variant="secondary">Исходный код на GitHub</ButtonLink>
      </PageHero>
      <div className="mx-auto max-w-7xl px-4 py-24 sm:px-6 sm:py-32 lg:px-8">
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {sections.map((section) => <FeatureCard key={section.title} icon={section.icon} title={section.title} description={section.text} />)}
        </div>

        <section className="mt-24">
          <SectionHeading
            eyebrow="VERIFICATION CHAIN"
            title="От исходного commit до локальной проверки"
            description="Каждый слой отвечает на отдельный вопрос: кто собрал asset, совпадает ли его digest и соответствует ли архив закреплённому upstream-контракту."
          />
          <div className="mt-10"><ReleaseVerificationDemo /></div>
          <div className="mt-8 grid gap-4 lg:grid-cols-2">
            <CodeBlock
              language="powershell"
              title="GitHub CLI"
              value={"gh attestation verify `\n  .\\NexRoute-X.Y.Z-win-x64.zip `\n  --repo Onmaynec/NexRoute"}
            />
            <CodeBlock
              language="powershell"
              title="SHA-256"
              value={"Get-FileHash .\\NexRoute-X.Y.Z-win-x64.zip -Algorithm SHA256"}
            />
          </div>
          <div className="mt-8 rounded-2xl border border-amber-300/13 bg-amber-300/[0.04] p-5 text-sm leading-7 text-amber-100/75">
            Build provenance подтверждает происхождение release asset, но не является Windows Authenticode-подписью отдельных EXE, DLL или драйвера.
          </div>
        </section>
      </div>
    </>
  );
}
