import {
  Activity,
  Blocks,
  BookOpen,
  Download,
  FlaskConical,
  History,
  RefreshCcw,
  Route,
  ShieldCheck,
  SlidersHorizontal,
  TerminalSquare,
  Wrench,
} from "lucide-react";

export const navigation = [
  { label: "Возможности", href: "/features" },
  { label: "Документация", href: "/docs" },
  { label: "Безопасность", href: "/security" },
  { label: "FAQ", href: "/faq" },
];

export const footerColumns = [
  {
    title: "Product",
    links: [
      { label: "Возможности", href: "/features" },
      { label: "Скачать", href: "/download" },
      { label: "Changelog", href: "/changelog" },
      { label: "FAQ", href: "/faq" },
    ],
  },
  {
    title: "Documentation",
    links: [
      { label: "Быстрый старт", href: "/docs/getting-started" },
      { label: "Service Matrix", href: "/docs/service-matrix" },
      { label: "Strategy Lab", href: "/docs/strategy-lab" },
      { label: "Обновления", href: "/docs/updates" },
      { label: "Безопасность", href: "/docs/security" },
    ],
  },
  {
    title: "Project",
    links: [
      { label: "GitHub", href: "https://github.com/Onmaynec/NexRoute" },
      { label: "Releases", href: "https://github.com/Onmaynec/NexRoute/releases" },
      { label: "Issues", href: "https://github.com/Onmaynec/NexRoute/issues" },
      { label: "MIT License", href: "https://github.com/Onmaynec/NexRoute/blob/main/LICENSE" },
    ],
  },
];

export const summaryStats = [
  { value: "21", label: "стратегия" },
  { value: "15", label: "сервисных профилей" },
  { value: "4", label: "attested release assets" },
  { value: "Windows", label: "10 и 11 x64" },
];

export const featureCards = [
  {
    title: "Изолированные сервисные workers",
    description:
      "Каждый включённый сервис получает собственные PID, лог, стратегию и filter scope. Сбой одного worker не завершает остальные.",
    label: "Per-service runtime",
    icon: SlidersHorizontal,
  },
  {
    title: "Измерения вместо догадок",
    description:
      "Strategy Lab измеряет переданные байты и Mbps, загружает HLS media segment и разделяет TCP/TLS и UDP readiness.",
    label: "Behavioral measurement",
    icon: FlaskConical,
  },
  {
    title: "Детерминированный failover",
    description:
      "Consecutive-failure, recovery, cooldown и maximum-switch thresholds предотвращают случайные переключения и циклы.",
    label: "Synthetic fault injection",
    icon: RefreshCcw,
  },
  {
    title: "Transactional updates",
    description:
      "Detached updater проверяет checksum и attestations, сохраняет пользовательские данные, запускает health check и откатывает ошибку.",
    label: "Backup · health · rollback",
    icon: History,
  },
  {
    title: "Проверяемый релиз",
    description:
      "ZIP, checksum и два validation report входят в одну GitHub attestation, а Viewer показывает каждый check и limitation.",
    label: "4 attested subjects",
    icon: ShieldCheck,
  },
];

export const detailedFeatures = [
  {
    id: "service-matrix",
    eyebrow: "SERVICE MATRIX",
    title: "Профили сервисов и отдельные capture scopes",
    description:
      "Выбирайте нужные платформы, а NexRoute подготовит отдельные доменные и IP-списки, TCP/UDP groups и non-overlapping worker scopes.",
    bullets: ["15 готовых профилей", "Изолированные workers", "Restart-safe state"],
    href: "/docs/service-matrix",
    icon: SlidersHorizontal,
  },
  {
    id: "strategy-lab",
    eyebrow: "STRATEGY LAB",
    title: "Проверка throughput, media и transport readiness",
    description:
      "Лаборатория передаёт многомегабайтный payload, проверяет HLS manifest и segment и не выдаёт HTTP latency за качество звонка.",
    bullets: ["21 реальная стратегия", "Bytes · elapsed · Mbps", "TCP/TLS и UDP отдельно"],
    href: "/docs/strategy-lab",
    icon: FlaskConical,
  },
  {
    id: "strategy-management",
    eyebrow: "WORKER SUPERVISOR",
    title: "Независимое управление сервисами",
    description:
      "Supervisor запускает, останавливает и переключает только затронутый worker, сохраняя здоровые процессы и их PID.",
    bullets: ["Unique PID и log", "Deterministic failover", "Synthetic health fixtures"],
    href: "/docs/getting-started",
    icon: Route,
  },
  {
    id: "diagnostics",
    eyebrow: "DIAGNOSTICS & REPAIR",
    title: "Evidence-backed findings и обратимые исправления",
    description:
      "Diagnostics отделяет факты от предположений, а repair transactions создают backup, проверяют результат и выполняют rollback.",
    bullets: ["Firewall · VPN · WinDivert", "Privacy-safe report", "Unknown security products remain unknown"],
    href: "/docs/diagnostics",
    icon: Activity,
  },
  {
    id: "updates",
    eyebrow: "SAFE UPDATES",
    title: "Четыре проверяемых release asset",
    description:
      "Updater принимает immutable ZIP, checksum и два validation report, проверяет каждый attested subject и только затем начинает transaction.",
    bullets: ["Stable-only channel", "Portable verifier", "Attestation receipt"],
    href: "/docs/updates",
    icon: Download,
  },
  {
    id: "rollback",
    eyebrow: "ROLLBACK",
    title: "Автоматическое восстановление после failed health check",
    description:
      "Ошибка verification, extraction, replacement, first launch или post-update health возвращает предыдущую установку.",
    bullets: ["Detached helper", "User data preservation", "0.4.1 и 0.5.0 migration fixtures"],
    href: "/docs/updates",
    icon: RefreshCcw,
  },
  {
    id: "verification",
    eyebrow: "RELEASE VERIFICATION",
    title: "Signed validation без ложных hardware claims",
    description:
      "Validation Viewer проверяет schema, product, version, check IDs, statuses и overall consistency. Experimental и unsupported остаются ограничениями.",
    bullets: ["Digest-matched receipt", "Required failures block release", "JSON и Markdown reports"],
    href: "/docs/security",
    icon: ShieldCheck,
  },
  {
    id: "architecture",
    eyebrow: "OPEN SOURCE",
    title: "Воспроизводимый online и offline build",
    description:
      "Код, workflows, immutable upstream identity, patch report и package self-tests доступны в репозитории.",
    bullets: ["MIT License", "23 tracked patch targets", "Native binaries compiled without NuGet"],
    href: "/docs/architecture",
    icon: Blocks,
  },
];

export const docsNavigation = [
  { label: "Обзор документации", href: "/docs", icon: BookOpen },
  { label: "Быстрый старт", href: "/docs/getting-started", icon: TerminalSquare },
  { label: "Service Matrix", href: "/docs/service-matrix", icon: SlidersHorizontal },
  { label: "Strategy Lab", href: "/docs/strategy-lab", icon: FlaskConical },
  { label: "Обновления и rollback", href: "/docs/updates", icon: RefreshCcw },
  { label: "Проверка релиза", href: "/docs/security", icon: ShieldCheck },
  { label: "Диагностика", href: "/docs/diagnostics", icon: Activity },
  { label: "Архитектура", href: "/docs/architecture", icon: Blocks },
  { label: "Совместимость", href: "/docs/compatibility", icon: Wrench },
];

export const projectLinks = {
  github: "https://github.com/Onmaynec/NexRoute",
  releases: "https://github.com/Onmaynec/NexRoute/releases",
  issues: "https://github.com/Onmaynec/NexRoute/issues",
};
