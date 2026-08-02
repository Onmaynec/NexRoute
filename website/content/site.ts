import {
  Activity,
  Blocks,
  BookOpen,
  Download,
  FlaskConical,
  Github,
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
  { value: "Windows", label: "10 и 11 x64" },
  { value: "Open Source", label: "MIT License" },
];

export const featureCards = [
  {
    title: "Сервисы под вашим контролем",
    description:
      "Включайте только нужные профили. NexRoute собирает совместимые доменные и IP-фильтры для выбранных сервисов.",
    label: "15 готовых профилей",
    icon: SlidersHorizontal,
  },
  {
    title: "Найдите рабочую стратегию",
    description:
      "Strategy Lab последовательно проверяет варианты и помогает сравнить результаты в текущей сети.",
    label: "Тестирование и сравнение",
    icon: FlaskConical,
  },
  {
    title: "Обновления без риска",
    description:
      "Перед установкой NexRoute проверяет пакет, создаёт резервную копию и сохраняет пользовательские настройки.",
    label: "Backup before install",
    icon: RefreshCcw,
  },
  {
    title: "Вернитесь к рабочей версии",
    description:
      "Если установка завершается ошибкой, предыдущая версия автоматически восстанавливается из резервной копии.",
    label: "Automatic rollback",
    icon: History,
  },
  {
    title: "Проверяемое происхождение сборки",
    description:
      "SHA-256 и GitHub attestations позволяют проверить целостность файлов и связь релиза с исходным репозиторием.",
    label: "SHA-256 · Build provenance",
    icon: ShieldCheck,
  },
];

export const detailedFeatures = [
  {
    id: "service-matrix",
    eyebrow: "SERVICE MATRIX",
    title: "Профили сервисов вместо ручной настройки",
    description:
      "Выбирайте нужные платформы, а NexRoute подготовит отдельные доменные и IP-списки и подключит их к совместимым стратегиям.",
    bullets: ["15 готовых профилей", "Изолированные runtime-группы", "Сохранение состояния между запусками"],
    href: "/docs/service-matrix",
    icon: SlidersHorizontal,
  },
  {
    id: "strategy-lab",
    eyebrow: "STRATEGY LAB",
    title: "Проверка стратегий в одном интерфейсе",
    description:
      "Последовательное тестирование помогает сравнить доступные варианты без ручного запуска каждого файла.",
    bullets: ["21 реальная стратегия", "Понятные статусы", "Повторная проверка при изменении сети"],
    href: "/docs/strategy-lab",
    icon: FlaskConical,
  },
  {
    id: "strategy-management",
    eyebrow: "STRATEGY MANAGEMENT",
    title: "Переключение без редактирования множества файлов",
    description:
      "Переключайтесь между доступными конфигурациями через терминальное меню и устанавливайте выбранную стратегию как службу.",
    bullets: ["Единый Control Node", "Установка и перезапуск службы", "Совместимость с профилями сервисов"],
    href: "/docs/getting-started",
    icon: Route,
  },
  {
    id: "diagnostics",
    eyebrow: "DIAGNOSTICS",
    title: "Privacy-safe отчёт о состоянии",
    description:
      "Получайте данные о версии, активных профилях, runtime-файлах, источниках и состоянии службы без копирования пользовательских списков.",
    bullets: ["JSON-отчёт", "SHA-256 runtime-файлов", "Без имён пользователей и внешних путей"],
    href: "/docs/diagnostics",
    icon: Activity,
  },
  {
    id: "updates",
    eyebrow: "SAFE UPDATES",
    title: "Проверка пакета до изменения установки",
    description:
      "Updater принимает только стабильный релиз, сверяет SHA-256, структуру архива, версию и обязательные provenance-файлы.",
    bullets: ["Stable-only channel", "Полный backup", "Сохранение настроек"],
    href: "/docs/updates",
    icon: Download,
  },
  {
    id: "rollback",
    eyebrow: "ROLLBACK",
    title: "Автоматическое восстановление при ошибке",
    description:
      "Если установка не завершается успешно, NexRoute возвращает предыдущую рабочую версию из backup-набора.",
    bullets: ["Safety backup перед rollback", "До четырёх backup-наборов", "Ручной откат через Update Center"],
    href: "/docs/updates",
    icon: RefreshCcw,
  },
  {
    id: "verification",
    eyebrow: "RELEASE VERIFICATION",
    title: "SHA-256 и GitHub build provenance",
    description:
      "Официальные assets можно связать с release workflow, репозиторием и исходным commit через Sigstore-backed attestation.",
    bullets: ["ZIP и checksum asset", "Self-verification до публикации", "Upstream lock и patch report внутри архива"],
    href: "/docs/security",
    icon: ShieldCheck,
  },
  {
    id: "architecture",
    eyebrow: "OPEN SOURCE",
    title: "Открытая архитектура и процесс сборки",
    description:
      "Код проекта, документация, release workflows и контракты сборки доступны для изучения на GitHub.",
    bullets: ["MIT License", "Публичный changelog", "Воспроизводимая online/offline сборка"],
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

export const icons = { Github };
