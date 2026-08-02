export type DocSection = {
  id: string;
  title: string;
  paragraphs?: string[];
  bullets?: string[];
  code?: { language: string; title: string; value: string };
  note?: string;
};

export type DocPage = {
  slug: string;
  title: string;
  description: string;
  sourceUrl: string;
  sections: DocSection[];
  previous?: { label: string; href: string };
  next?: { label: string; href: string };
};

const repo = "https://github.com/Onmaynec/NexRoute/blob/main";

export const docsPages: Record<string, DocPage> = {
  "getting-started": {
    slug: "getting-started",
    title: "Быстрый старт",
    description: "Скачивание, распаковка и первый запуск NexRoute на Windows 10 или Windows 11 x64.",
    sourceUrl: `${repo}/README.md`,
    sections: [
      {
        id: "requirements",
        title: "Перед началом",
        paragraphs: [
          "NexRoute предназначен для Windows 10 x64 и Windows 11 x64. Для терминального интерфейса требуется Windows PowerShell 5.1 или более новая версия PowerShell.",
        ],
        bullets: [
          "Права администратора для установки и перезапуска службы.",
          "curl.exe для отдельных функций Strategy Lab.",
          "Доступ к GitHub Releases для онлайн-обновлений.",
          "GitHub CLI нужен только для дополнительной проверки build provenance.",
        ],
      },
      {
        id: "download",
        title: "1. Скачайте стабильный релиз",
        paragraphs: [
          "Используйте страницу Download или официальный GitHub Release. Основной релиз содержит ZIP-архив и соответствующий файл .sha256.",
        ],
      },
      {
        id: "extract",
        title: "2. Полностью распакуйте архив",
        paragraphs: [
          "Извлеките все файлы в новую отдельную папку. Не запускайте CMD- или BAT-файлы непосредственно из ZIP: такая схема не поддерживается.",
        ],
      },
      {
        id: "launch",
        title: "3. Запустите NexRoute",
        paragraphs: [
          "Откройте NexRoute.lnk, nexroute.bat или service.bat от имени администратора. Windows Terminal рекомендуется, но классический cmd.exe также поддерживается через PowerShell renderer.",
        ],
      },
      {
        id: "configure",
        title: "4. Выберите стратегию и профили",
        bullets: [
          "Выберите стратегию и установите её как службу.",
          "Откройте [14] SERVICE MATRIX, чтобы включить нужные сервисы.",
          "Используйте [12] STRATEGY LAB, если нужно сравнить доступные варианты.",
          "Откройте [6] CHECK UPDATES для настройки stable-updater.",
        ],
      },
      {
        id: "diagnostics-command",
        title: "Диагностический отчёт",
        paragraphs: [
          "Privacy-safe Diagnostics экспортирует версию, включённые ID сервисов, статусы источников, hashes runtime-файлов и состояние службы. Содержимое пользовательских списков не копируется.",
        ],
        code: {
          language: "powershell",
          title: "PowerShell",
          value:
            "powershell -NoProfile -ExecutionPolicy Bypass -File .service\\nexroute-services.ps1 `\n  -Mode Diagnostics `\n  -Root .",
        },
      },
    ],
    next: { label: "Service Matrix", href: "/docs/service-matrix" },
  },
  "service-matrix": {
    slug: "service-matrix",
    title: "Service Matrix",
    description: "Как NexRoute формирует отдельные доменные, IP- и транспортные группы для выбранных сервисов.",
    sourceUrl: `${repo}/docs/SERVICES.md`,
    sections: [
      {
        id: "overview",
        title: "Что делает матрица",
        paragraphs: [
          "Service Matrix — источник доменных, IP- и транспортных фильтров для 21 настоящей стратегии Flowseal. Матрица содержит 15 профилей и применяет только правила включённых сервисов.",
        ],
      },
      {
        id: "profiles",
        title: "Поля профиля",
        bullets: [
          "domains — домены сервиса.",
          "testTargets — реальные HTTP/TLS endpoints для Strategy Lab.",
          "tcpPorts и udpPorts — транспортные порты перехвата.",
          "resolveHosts — хосты для DNS-разрешения в IPv4 /32.",
          "ipCidrs и ipSources — статические и удалённые IPv4 CIDR.",
        ],
      },
      {
        id: "shared-domains",
        title: "Общие домены",
        paragraphs: [
          "Контроллер строит карту владения доменами. Общий домен остаётся включённым, пока активен хотя бы один использующий его профиль, и попадает в исключения только после отключения всех владельцев.",
        ],
      },
      {
        id: "runtime",
        title: "Изолированные runtime-группы",
        paragraphs: [
          "Для каждого включённого профиля создаются отдельные hostlist/IPSet-файлы и собственные TCP/UDP --new-группы. Это предотвращает применение широких портов одного приложения к адресам всех остальных сервисов.",
        ],
        code: {
          language: "text",
          title: "Создаваемые файлы",
          value:
            "lists/list-service-<id>.txt\nlists/ipset-service-<id>.txt\nlists/list-services-enabled.txt\nlists/ipset-services-user.txt\n.service/services-runtime.cmd",
        },
      },
      {
        id: "state",
        title: "Состояние и восстановление",
        paragraphs: [
          "services-state.json использует schema v2. Старое плоское состояние мигрируется с backup, а повреждённый файл сохраняется отдельно и заменяется валидными значениями по умолчанию.",
        ],
        code: {
          language: "json",
          title: "services-state.json",
          value:
            '{\n  "schemaVersion": 2,\n  "updatedAtUtc": "...",\n  "services": {\n    "youtube": true,\n    "discord": true\n  }\n}',
        },
      },
      {
        id: "cache",
        title: "Внешние IP-источники",
        paragraphs: [
          "Успешно проверенные данные сохраняются в .service/cache/ip-sources. Максимальный возраст last-known-good кэша — 14 дней. Статусы fresh, cache и failed записываются в .service/ip-source-status.json.",
        ],
      },
    ],
    previous: { label: "Быстрый старт", href: "/docs/getting-started" },
    next: { label: "Strategy Lab", href: "/docs/strategy-lab" },
  },
  "strategy-lab": {
    slug: "strategy-lab",
    title: "Strategy Lab",
    description: "Последовательная проверка доступных стратегий в текущей сети.",
    sourceUrl: `${repo}/README.md`,
    sections: [
      {
        id: "purpose",
        title: "Не угадывайте — проверяйте",
        paragraphs: [
          "Strategy Lab запускается через пункт [12] STRATEGY LAB и помогает последовательно сравнить реальные стратегии. Результат зависит от провайдера, региона, DNS, версии приложений и текущей конфигурации сети.",
        ],
      },
      {
        id: "targets",
        title: "Что проверяется",
        paragraphs: [
          "Профили Service Matrix содержат testTargets для web, API, CDN, media, gateway и update endpoints. Strategy Lab использует эти цели для практической проверки доступности.",
        ],
      },
      {
        id: "workflow",
        title: "Рекомендуемый порядок",
        bullets: [
          "Убедитесь, что архив полностью распакован и NexRoute запущен с правами администратора.",
          "Включите нужные профили через Service Matrix.",
          "Откройте Strategy Lab и дождитесь последовательного прохождения тестов.",
          "Сравните статусы и задержку, затем выберите подходящий вариант.",
          "Повторите проверку после смены провайдера, DNS или существенного изменения сети.",
        ],
      },
      {
        id: "limits",
        title: "Как читать результат",
        paragraphs: [
          "Успешный тест показывает, что конкретная цель ответила в момент проверки. Он не гарантирует одинаковый результат для всех приложений, медиареле или будущих сетевых условий.",
        ],
        note:
          "Не описывайте отдельную стратегию как универсальную. NexRoute намеренно предоставляет несколько вариантов и инструменты сравнения.",
      },
    ],
    previous: { label: "Service Matrix", href: "/docs/service-matrix" },
    next: { label: "Обновления и rollback", href: "/docs/updates" },
  },
  updates: {
    slug: "updates",
    title: "Обновления и rollback",
    description: "Stable-only обновления с проверкой SHA-256, полным backup и автоматическим восстановлением.",
    sourceUrl: `${repo}/docs/UPDATES.md`,
    sections: [
      {
        id: "flow",
        title: "Порядок безопасного обновления",
        bullets: [
          "Updater запрашивает только последний стабильный GitHub Release.",
          "Draft и prerelease-релизы отклоняются.",
          "Для версии X.Y.Z ожидаются ZIP и соответствующий .sha256.",
          "SHA-256 сравнивается с реально загруженным архивом.",
          "Проверяются версия, обязательные файлы, 21 стратегия и 23 patch records.",
          "Перед заменой файлов создаётся полная резервная копия.",
          "При ошибке предыдущая версия автоматически восстанавливается.",
        ],
      },
      {
        id: "automatic",
        title: "Автоматический режим",
        paragraphs: [
          "Автообновление включается через [6] CHECK UPDATES или nexroute-update.cmd. Повторная автоматическая проверка выполняется не чаще одного раза в 24 часа. Сетевой сбой не блокирует запуск текущей версии.",
        ],
        code: {
          language: "text",
          title: "Состояние updater",
          value: ".service/update-state.json",
        },
      },
      {
        id: "manual",
        title: "Ручной Update Center",
        code: { language: "text", title: "Launcher", value: "nexroute-update.cmd" },
        bullets: [
          "Включить или выключить автоматические обновления.",
          "Немедленно проверить и установить стабильный релиз.",
          "Откатиться к последней резервной копии.",
        ],
      },
      {
        id: "preserved",
        title: "Что сохраняется",
        bullets: [
          "Язык интерфейса и Service Matrix state.",
          "update-state.json и кеш IP-источников.",
          "Флаги Update Watch и Game Filter.",
          "Пользовательские domain/IPSet-файлы из lists.",
        ],
      },
      {
        id: "backups",
        title: "Резервные копии",
        paragraphs: [
          "Backup-наборы создаются в соседней директории NexRoute-backups. Хранятся последние четыре набора. Перед ручным rollback создаётся дополнительная safety-копия текущей установки.",
        ],
      },
    ],
    previous: { label: "Strategy Lab", href: "/docs/strategy-lab" },
    next: { label: "Проверка релиза", href: "/docs/security" },
  },
  security: {
    slug: "security",
    title: "Проверка релиза",
    description: "Проверка SHA-256 и GitHub build provenance для официальных release assets.",
    sourceUrl: `${repo}/docs/ATTESTATIONS.md`,
    sections: [
      {
        id: "assets",
        title: "Официальные assets",
        code: {
          language: "text",
          title: "Release files",
          value: "NexRoute-X.Y.Z-win-x64.zip\nNexRoute-X.Y.Z-win-x64.zip.sha256",
        },
        paragraphs: [
          "Официальный релиз содержит архив и checksum-файл. Оба assets получают GitHub artifact attestation до публикации Release.",
        ],
      },
      {
        id: "attestation",
        title: "Проверка build provenance",
        paragraphs: [
          "Успешная проверка подтверждает, что digest загруженного файла присутствует в подписанной attestation, созданной workflow репозитория Onmaynec/NexRoute.",
        ],
        code: {
          language: "powershell",
          title: "GitHub CLI",
          value:
            "gh attestation verify .\\NexRoute-X.Y.Z-win-x64.zip --repo Onmaynec/NexRoute\ngh attestation verify .\\NexRoute-X.Y.Z-win-x64.zip.sha256 --repo Onmaynec/NexRoute",
        },
      },
      {
        id: "checksum",
        title: "Проверка SHA-256",
        code: {
          language: "powershell",
          title: "PowerShell",
          value:
            "$expected = (Get-Content .\\NexRoute-X.Y.Z-win-x64.zip.sha256 -Raw).Split()[0].Trim().ToLowerInvariant()\n$actual = (Get-FileHash .\\NexRoute-X.Y.Z-win-x64.zip -Algorithm SHA256).Hash.ToLowerInvariant()\nif ($actual -ne $expected) { throw 'SHA-256 mismatch.' }",
        },
      },
      {
        id: "inside",
        title: "Provenance внутри архива",
        code: {
          language: "text",
          title: "Package provenance",
          value:
            ".service/upstream-manifest.json\n.service/upstream-lock.json\n.service/patch-report.json\nNEXROUTE_BUILD_INFO.txt",
        },
      },
      {
        id: "trust-boundary",
        title: "Граница доверия",
        paragraphs: [
          "Artifact attestation доказывает происхождение опубликованного архива и его digest, но не является Windows Authenticode-подписью отдельных EXE, DLL или драйвера.",
        ],
      },
    ],
    previous: { label: "Обновления и rollback", href: "/docs/updates" },
    next: { label: "Диагностика", href: "/docs/diagnostics" },
  },
  diagnostics: {
    slug: "diagnostics",
    title: "Диагностика",
    description: "Privacy-safe отчёт о runtime, профилях, источниках и состоянии службы.",
    sourceUrl: `${repo}/README.md`,
    sections: [
      {
        id: "command",
        title: "Создание отчёта",
        code: {
          language: "powershell",
          title: "PowerShell",
          value:
            "powershell -NoProfile -ExecutionPolicy Bypass -File .service\\nexroute-services.ps1 `\n  -Mode Diagnostics `\n  -Root .",
        },
      },
      {
        id: "included",
        title: "Что входит в отчёт",
        bullets: [
          "Версия NexRoute и включённые ID сервисов.",
          "Количество сгенерированных записей.",
          "Статусы IP-источников.",
          "SHA-256 runtime-файлов.",
          "Версия Windows/PowerShell и состояние службы.",
        ],
      },
      {
        id: "privacy",
        title: "Что не включается",
        bullets: [
          "Имена пользователей.",
          "Содержимое пользовательских доменных/IP-списков.",
          "Внешние локальные пути.",
        ],
      },
      {
        id: "issues",
        title: "Перед созданием Issue",
        paragraphs: [
          "Сначала проверьте Strategy Lab и состояние службы. Затем приложите диагностический отчёт и опишите Windows, провайдера, DNS и наблюдаемое поведение без публикации чувствительных данных.",
        ],
      },
    ],
    previous: { label: "Проверка релиза", href: "/docs/security" },
    next: { label: "Архитектура", href: "/docs/architecture" },
  },
  architecture: {
    slug: "architecture",
    title: "Архитектура и сборка",
    description: "Открытая структура проекта, locked upstream и воспроизводимая online/offline сборка.",
    sourceUrl: `${repo}/docs/ARCHITECTURE.md`,
    sections: [
      {
        id: "layers",
        title: "Основные слои",
        bullets: [
          "Overlay с launcher-файлами, PowerShell renderer и Service Matrix controller.",
          "Скрипты Build-NexRoute, Build-Release и Build-Package.",
          "Pester-контракты Service Matrix, updater, upstream и release attestations.",
          "Release workflow с SHA-256, online/offline rebuild и Sigstore-backed attestation.",
        ],
      },
      {
        id: "upstream",
        title: "Locked upstream",
        paragraphs: [
          "Декларативный .service/upstream-manifest.json закрепляет репозиторий, tag, asset, размер, SHA-256 и обязательную структуру Flowseal. Несовпадение останавливает сборку до упаковки NexRoute.",
        ],
      },
      {
        id: "build-online",
        title: "Online build",
        code: {
          language: "powershell",
          title: "Build-Release.ps1",
          value:
            "pwsh ./scripts/Build-Release.ps1 `\n  -Version X.Y.Z `\n  -OutputDirectory ./artifacts `\n  -UpstreamCachePath ./cache/zapret-discord-youtube-1.10.0.zip",
        },
      },
      {
        id: "build-offline",
        title: "Offline rebuild",
        code: {
          language: "powershell",
          title: "Build-Release.ps1",
          value:
            "pwsh ./scripts/Build-Release.ps1 `\n  -Version X.Y.Z `\n  -OutputDirectory ./artifacts-offline `\n  -UpstreamArchive ./cache/zapret-discord-youtube-1.10.0.zip",
        },
        note:
          "Локальный upstream-файл обязан совпасть с locked SHA-256 и обязательной структурой. Совпадения имени недостаточно.",
      },
    ],
    previous: { label: "Диагностика", href: "/docs/diagnostics" },
    next: { label: "Совместимость", href: "/docs/compatibility" },
  },
  compatibility: {
    slug: "compatibility",
    title: "Совместимость",
    description: "Поддерживаемые версии Windows, терминалы и известные категории конфликтов.",
    sourceUrl: `${repo}/docs/COMPATIBILITY.md`,
    sections: [
      {
        id: "systems",
        title: "Поддерживаемые системы",
        bullets: [
          "Windows 10 x64 — поддерживается.",
          "Windows 11 x64 — поддерживается.",
          "Windows x86 — не поддерживается.",
          "Windows ARM64 — не тестировалась.",
          "Linux и macOS — не поддерживаются этой сборкой.",
        ],
      },
      {
        id: "terminals",
        title: "Терминалы",
        bullets: [
          "Windows Terminal — рекомендуется.",
          "Классический cmd.exe — поддерживается через PowerShell renderer.",
          "PowerShell console host — поддерживается.",
          "Запуск BAT непосредственно из ZIP — не поддерживается.",
        ],
      },
      {
        id: "conflicts",
        title: "Возможные конфликты",
        bullets: [
          "Другие инструменты на WinDivert.",
          "AdGuard и системные фильтры.",
          "Killer, SmartByte и Intel Connectivity Network Service.",
          "VPN-клиенты и корпоративные endpoint-фильтры.",
          "Антивирусный карантин WinDivert.",
          "Нестандартные proxy/DNS-настройки.",
        ],
      },
      {
        id: "limits",
        title: "Сетевые ограничения",
        paragraphs: [
          "Текущий runtime ориентирован на IPv4. CDN и медиареле могут менять адреса, а IPv6-only и отдельные peer-to-peer endpoints требуют отдельного расширения.",
        ],
      },
    ],
    previous: { label: "Архитектура", href: "/docs/architecture" },
  },
};

export const docsOverviewCards = [
  { title: "Быстрый старт", description: "Скачивание, распаковка и первый запуск.", href: "/docs/getting-started" },
  { title: "Service Matrix", description: "Профили сервисов, состояние и runtime-группы.", href: "/docs/service-matrix" },
  { title: "Strategy Lab", description: "Последовательная проверка доступных стратегий.", href: "/docs/strategy-lab" },
  { title: "Обновления", description: "Stable updater, backup и автоматический rollback.", href: "/docs/updates" },
  { title: "Проверка релиза", description: "SHA-256 и GitHub build provenance.", href: "/docs/security" },
  { title: "Диагностика", description: "Privacy-safe отчёт о состоянии системы.", href: "/docs/diagnostics" },
  { title: "Архитектура", description: "Locked upstream и воспроизводимая сборка.", href: "/docs/architecture" },
  { title: "Совместимость", description: "Windows, терминалы и возможные конфликты.", href: "/docs/compatibility" },
];
