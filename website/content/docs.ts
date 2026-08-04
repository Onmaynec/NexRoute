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
    description: "Проверка четырёх release assets, распаковка и первый запуск NexRoute 0.6.0.",
    sourceUrl: `${repo}/README.md`,
    sections: [
      {
        id: "requirements",
        title: "Перед началом",
        paragraphs: [
          "NexRoute 0.6.0 предназначен для Windows 10 x64 и Windows 11 x64. Терминальный интерфейс поддерживает Windows PowerShell 5.1, а нативные desktop-компоненты компилируются без NuGet-зависимостей.",
        ],
        bullets: [
          "Права администратора для установки службы и управления WinDivert.",
          "curl.exe для отдельных Strategy Lab probes.",
          "Доступ к GitHub Releases для online update и первоначальной проверки assets.",
          "GitHub CLI необязателен: package содержит pinned portable attestation verifier.",
        ],
      },
      {
        id: "download",
        title: "1. Скачайте полный релиз",
        paragraphs: [
          "Берите все четыре файла из одного стабильного GitHub Release. ZIP и checksum недостаточны для полного validation trust-flow.",
        ],
        code: {
          language: "text",
          title: "Release assets",
          value:
            "NexRoute-X.Y.Z-win-x64.zip\nNexRoute-X.Y.Z-win-x64.zip.sha256\nNexRoute-X.Y.Z-validation.json\nNexRoute-X.Y.Z-validation.md",
        },
      },
      {
        id: "verify",
        title: "2. Проверьте происхождение",
        paragraphs: [
          "Portable verifier проверяет immutable release URLs, SHA-256 архива и GitHub artifact attestation каждого из четырёх subjects. После успеха validation report и digest-matched receipt устанавливаются в .service атомарно.",
        ],
        note:
          "Импортированный validation JSON без matching local receipt остаётся attestation-not-verified и не считается доказательством релиза.",
      },
      {
        id: "extract",
        title: "3. Полностью распакуйте архив",
        paragraphs: [
          "Извлеките все файлы в новую отдельную папку. Не запускайте CMD- или BAT-файлы непосредственно из ZIP.",
        ],
      },
      {
        id: "launch",
        title: "4. Запустите NexRoute",
        paragraphs: [
          "Откройте NexRoute.lnk, nexroute.bat или service.bat от имени администратора. Tray launcher использует NexRoute.Tray.exe первым и сохраняет PowerShell fallback.",
        ],
      },
      {
        id: "configure",
        title: "5. Настройте runtime",
        bullets: [
          "Выберите стратегию и установите её как службу.",
          "Откройте [14] SERVICE MATRIX и включите только нужные сервисы.",
          "Используйте [12] STRATEGY LAB для измерения throughput, media и transport readiness.",
          "Через tray откройте Dashboard и Validation Viewer.",
          "Откройте [6] CHECK UPDATES для stable updater и rollback.",
        ],
      },
      {
        id: "diagnostics-command",
        title: "Privacy-safe Diagnostics",
        paragraphs: [
          "Отчёт экспортирует версию, ID включённых сервисов, source statuses, runtime hashes и service state без содержимого пользовательских списков.",
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
    description: "Сервисные профили, address families и изолированные worker scopes.",
    sourceUrl: `${repo}/docs/SERVICES.md`,
    sections: [
      {
        id: "overview",
        title: "Что делает матрица",
        paragraphs: [
          "Service Matrix содержит 15 профилей и формирует domain, IP и transport scope только для включённых сервисов. Эти scopes используются при создании отдельных per-service winws workers.",
        ],
      },
      {
        id: "profiles",
        title: "Поля профиля",
        bullets: [
          "domains — домены сервиса.",
          "testTargets — web, API, CDN, gateway, media и update endpoints.",
          "tcpPorts и udpPorts — транспортные порты перехвата.",
          "resolveHosts — имена для A/AAAA resolution.",
          "ipCidrs и ipSources — IPv4 и IPv6 literals/CIDR из статических и проверяемых внешних источников.",
        ],
      },
      {
        id: "shared-domains",
        title: "Общие домены",
        paragraphs: [
          "Контроллер строит карту владельцев. Общий домен остаётся включённым, пока активен хотя бы один профиль-владелец, и попадает в exclusions только после отключения всех владельцев.",
        ],
      },
      {
        id: "workers",
        title: "Изолированные workers",
        paragraphs: [
          "Supervisor создаёт отдельный worker plan для каждого service assignment. Worker получает собственные PID file, log, service identity, strategy и filter scope. Duplicate capture scopes отклоняются до запуска.",
        ],
        bullets: [
          "Сбой одного сервиса не завершает остальные процессы.",
          "IPv4-only, IPv6-only и dual-stack plans формируются отдельно.",
          "Failover заменяет только затронутый worker.",
        ],
      },
      {
        id: "runtime-files",
        title: "Runtime-файлы",
        code: {
          language: "text",
          title: "Generated state",
          value:
            "lists/list-service-<id>.txt\nlists/ipset-service-<id>.txt\n.service/services-runtime.cmd\n.service/service-workers.json\n.service/worker-state.json",
        },
      },
      {
        id: "state",
        title: "Состояние и восстановление",
        paragraphs: [
          "services-state.json использует schema v2. Старое плоское состояние мигрируется с backup, повреждённый JSON сохраняется отдельно, а worker/failover history восстанавливается после restart.",
        ],
      },
      {
        id: "cache",
        title: "Внешние IP-источники",
        paragraphs: [
          "Проверенные данные сохраняются в .service/cache/ip-sources. Last-known-good cache ограничен 14 днями, а fresh/cache/failed status записывается в .service/ip-source-status.json.",
        ],
      },
    ],
    previous: { label: "Быстрый старт", href: "/docs/getting-started" },
    next: { label: "Strategy Lab", href: "/docs/strategy-lab" },
  },

  "strategy-lab": {
    slug: "strategy-lab",
    title: "Strategy Lab",
    description: "Behavioral measurements, history, scoring и deterministic failover.",
    sourceUrl: `${repo}/README.md`,
    sections: [
      {
        id: "purpose",
        title: "Измерения вместо ложного успеха",
        paragraphs: [
          "Strategy Lab сравнивает стратегии в текущей сети и сохраняет measurement contract в history. Результаты описывают только реально выполненные probes.",
        ],
      },
      {
        id: "download",
        title: "Download throughput",
        paragraphs: [
          "Probe передаёт configurable multi-megabyte payload и записывает transferred bytes, elapsed time и measured Mbps. Размер HTTP metadata не используется как скорость загрузки.",
        ],
      },
      {
        id: "media",
        title: "YouTube media readiness",
        paragraphs: [
          "Проверка загружает HLS master manifest, variant playlist и media segment. Ответ generate_204 сам по себе не считается доказательством playback readiness.",
        ],
      },
      {
        id: "realtime",
        title: "Discord и Telegram",
        paragraphs: [
          "TCP/TLS reachability и UDP transport readiness показываются отдельно. HTTP latency не называется call MOS или voice quality без реальной authenticated call session.",
        ],
      },
      {
        id: "dashboard",
        title: "Native Dashboard",
        paragraphs: [
          "NexRoute.Dashboard.exe читает ту же .service/history/strategy-lab, что и терминальный интерфейс. Доступны metric/strategy filters, zoom, tooltips, themes и accent colors.",
        ],
      },
      {
        id: "failover",
        title: "Deterministic failover",
        bullets: [
          "Consecutive-failure threshold защищает от одиночного сбоя.",
          "Recovery threshold подтверждает возврат сервиса.",
          "Cooldown и maximum-switch limits предотвращают loop.",
          "Synthetic healthy, degraded и failed probes тестируют весь контракт offline.",
        ],
      },
      {
        id: "limits",
        title: "Как читать результат",
        paragraphs: [
          "Synthetic workers и measurement fixtures подтверждают логику, но не доказывают bypass у конкретного ISP. Live IPv4/IPv6 behavior остаётся environment-dependent.",
        ],
        note:
          "Не описывайте одну стратегию как универсальную: итог зависит от провайдера, региона, DNS, приложения и текущего DPI.",
      },
    ],
    previous: { label: "Service Matrix", href: "/docs/service-matrix" },
    next: { label: "Обновления и rollback", href: "/docs/updates" },
  },

  updates: {
    slug: "updates",
    title: "Обновления и rollback",
    description: "Stable-only transaction с checksum, attestations, health check и rollback.",
    sourceUrl: `${repo}/docs/UPDATES.md`,
    sections: [
      {
        id: "flow",
        title: "Порядок безопасного обновления",
        bullets: [
          "Updater принимает только последний stable GitHub Release; draft и prerelease отклоняются.",
          "Для X.Y.Z требуются ZIP, checksum, validation JSON и validation Markdown.",
          "Проверяются immutable official URLs, SHA-256 package и attestations всех четырёх subjects.",
          "Signed JSON проверяется по schema, product, version, status и unique check IDs.",
          "Перед replacement создаётся полная резервная копия.",
          "Detached helper останавливает процессы, заменяет locked files и запускает новую версию.",
          "Failure verification, extraction, replacement, first launch или health policy запускает rollback.",
        ],
      },
      {
        id: "verifier",
        title: "Portable verifier",
        paragraphs: [
          "Проверка artifact attestation не требует заранее установленного gh. Pinned GitHub CLI archive загружается или берётся из integrity-checked cache и запускается с repository/signer constraints.",
        ],
      },
      {
        id: "automatic",
        title: "Автоматический режим",
        paragraphs: [
          "Auto update check имеет 24-часовой cooldown и не блокирует запуск текущей версии при сетевой ошибке. Установка выполняется только после пользовательского подтверждения.",
        ],
        code: { language: "text", title: "Updater state", value: ".service/update-state.json" },
      },
      {
        id: "preserved",
        title: "Что сохраняется",
        bullets: [
          "Язык интерфейса, Service Matrix state и UI settings.",
          "update-state.json и verified caches.",
          "Пользовательские domain/IPSet-файлы.",
          "Strategy Lab history и diagnostics history.",
        ],
      },
      {
        id: "migration",
        title: "Migration и rollback fixtures",
        paragraphs: [
          "Automated acceptance tests покрывают переходы 0.4.1 -> 0.6.0 и 0.5.0 -> 0.6.0, включая восстановление точной предыдущей версии.",
        ],
      },
    ],
    previous: { label: "Strategy Lab", href: "/docs/strategy-lab" },
    next: { label: "Проверка релиза", href: "/docs/security" },
  },

  security: {
    slug: "security",
    title: "Проверка релиза",
    description: "Четыре attested assets, signed validation report и локальный trust receipt.",
    sourceUrl: `${repo}/docs/ATTESTATIONS.md`,
    sections: [
      {
        id: "assets",
        title: "Официальные assets",
        code: {
          language: "text",
          title: "Release files",
          value:
            "NexRoute-X.Y.Z-win-x64.zip\nNexRoute-X.Y.Z-win-x64.zip.sha256\nNexRoute-X.Y.Z-validation.json\nNexRoute-X.Y.Z-validation.md",
        },
        paragraphs: [
          "Все четыре subjects включены в одну GitHub artifact attestation до публикации Release.",
        ],
      },
      {
        id: "attestation",
        title: "Проверка build provenance",
        code: {
          language: "powershell",
          title: "GitHub CLI",
          value:
            "gh attestation verify .\\NexRoute-X.Y.Z-win-x64.zip --repo Onmaynec/NexRoute\ngh attestation verify .\\NexRoute-X.Y.Z-win-x64.zip.sha256 --repo Onmaynec/NexRoute\ngh attestation verify .\\NexRoute-X.Y.Z-validation.json --repo Onmaynec/NexRoute\ngh attestation verify .\\NexRoute-X.Y.Z-validation.md --repo Onmaynec/NexRoute",
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
        id: "viewer",
        title: "Validation Viewer",
        paragraphs: [
          "NexRoute.Validation.exe показывает каждый check, evidence и limitation. Wrong product/version, duplicate IDs, unknown statuses и inconsistent overallStatus отклоняются до display.",
          "Imported JSON остаётся informational до появления matching .attestation-receipt.json с тем же report SHA-256.",
        ],
      },
      {
        id: "statuses",
        title: "Статусы и release gate",
        bullets: [
          "passed — automated evidence подтверждено.",
          "experimental — automated contract есть, но требуется live machine/session evidence.",
          "unsupported — capability недоступна в проверенной среде.",
          "failed required check — publication блокируется.",
        ],
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
          "Artifact attestation связывает digest с repository workflow и source commit, но не заменяет Windows Authenticode для отдельных EXE, DLL и драйвера.",
        ],
      },
    ],
    previous: { label: "Обновления и rollback", href: "/docs/updates" },
    next: { label: "Диагностика", href: "/docs/diagnostics" },
  },

  diagnostics: {
    slug: "diagnostics",
    title: "Диагностика и repair",
    description: "Privacy-safe evidence и обратимые repair transactions.",
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
        title: "Что входит",
        bullets: [
          "Версия и включённые service IDs.",
          "Generated runtime counts и source statuses.",
          "SHA-256 runtime files.",
          "Windows/PowerShell environment и service state.",
          "Evidence отдельных firewall, VPN, WinDivert, route, DNS и adapter findings.",
        ],
      },
      {
        id: "repair",
        title: "Repair contract",
        paragraphs: [
          "Перед изменением создаётся точный snapshot. Transaction считается committed только после verification; failure восстанавливает firewall rules, metrics, DNS addresses, services или созданные exclusions.",
        ],
      },
      {
        id: "unknown",
        title: "Неизвестные security products",
        paragraphs: [
          "Нераспознанный продукт отображается как unknown. Отсутствие известного конфликта не превращается в утверждение о совместимости.",
        ],
      },
      {
        id: "privacy",
        title: "Что не включается",
        bullets: [
          "Имена пользователей.",
          "Содержимое пользовательских domain/IP lists.",
          "Внешние локальные пути и secrets.",
        ],
      },
    ],
    previous: { label: "Проверка релиза", href: "/docs/security" },
    next: { label: "Архитектура", href: "/docs/architecture" },
  },

  architecture: {
    slug: "architecture",
    title: "Архитектура и сборка",
    description: "Supervisor, native tools, locked upstream и signed release gate.",
    sourceUrl: `${repo}/docs/ARCHITECTURE.md`,
    sections: [
      {
        id: "layers",
        title: "Основные слои",
        bullets: [
          "Arrow-key Control Node и Service Matrix controller.",
          "Per-service worker plans, supervisor и product worker host.",
          "Strategy Lab probes, history и native Dashboard.",
          "Native tray, notifier и Validation Viewer.",
          "Transactional updater, portable verifier и attestation receipt.",
          "Build-Package, package self-tests и signed validation report.",
        ],
      },
      {
        id: "native",
        title: "Native Windows executables",
        paragraphs: [
          "Tray, Notifier, Dashboard и Validation Viewer компилируются напрямую из repository C# sources системным .NET Framework compiler. Build не использует NuGet или сетевой restore и не переписывает Dashboard fields перед compilation.",
        ],
      },
      {
        id: "upstream",
        title: "Locked upstream",
        paragraphs: [
          "Declarative upstream manifest закрепляет Flowseal repository, tag, asset, size, SHA-256 и required paths. Несовпадение останавливает build до применения 23 tracked patch targets.",
        ],
      },
      {
        id: "build-online",
        title: "Online build через verified cache",
        code: {
          language: "powershell",
          title: "Build-Release.ps1",
          value:
            "pwsh ./scripts/Build-Release.ps1 `\n  -Version 0.6.0 `\n  -OutputDirectory ./artifacts `\n  -UpstreamCachePath ./cache/zapret-discord-youtube-1.10.0.zip",
        },
      },
      {
        id: "build-offline",
        title: "Полностью offline rebuild",
        code: {
          language: "powershell",
          title: "Build-Release.ps1",
          value:
            "pwsh ./scripts/Build-Release.ps1 `\n  -Version 0.6.0 `\n  -OutputDirectory ./artifacts-offline `\n  -UpstreamArchive ./cache/zapret-discord-youtube-1.10.0.zip",
        },
        note:
          "Offline package повторяет desktop, notification, viewer и provenance self-tests и обязан использовать тот же upstream digest.",
      },
      {
        id: "release-gate",
        title: "Release gate",
        paragraphs: [
          "Workflow проверяет source/Pester contracts, website build, online/offline package, native self-tests, notification fallback, validation trust states и package identities. Затем создаёт JSON/Markdown report, attests четыре subjects, проверяет их и только после этого публикует Release.",
        ],
      },
    ],
    previous: { label: "Диагностика", href: "/docs/diagnostics" },
    next: { label: "Совместимость", href: "/docs/compatibility" },
  },

  compatibility: {
    slug: "compatibility",
    title: "Совместимость",
    description: "Поддерживаемые Windows environments и честные live limitations.",
    sourceUrl: `${repo}/docs/COMPATIBILITY.md`,
    sections: [
      {
        id: "systems",
        title: "Поддерживаемые системы",
        bullets: [
          "Windows 10 x64 — target platform.",
          "Windows 11 x64 — target platform.",
          "Windows x86 — не поддерживается.",
          "Windows ARM64 — не валидировалась.",
          "Linux и macOS — package runtime не поддерживается.",
        ],
      },
      {
        id: "terminals",
        title: "Терминалы и desktop session",
        bullets: [
          "Windows Terminal рекомендуется для Control Node.",
          "Classic cmd.exe поддерживается через PowerShell renderer.",
          "Interactive tray, toast и Dashboard требуют signed-in desktop session.",
          "Запуск launchers непосредственно из ZIP не поддерживается.",
        ],
      },
      {
        id: "families",
        title: "IPv4 и IPv6",
        paragraphs: [
          "NexRoute строит и запускает synthetic IPv4-only, IPv6-only и dual-stack workers, включая family-specific DNS/TCP probes. Это доказывает runtime contract, но не ISP-specific live bypass.",
        ],
      },
      {
        id: "conflicts",
        title: "Возможные конфликты",
        bullets: [
          "Параллельные WinDivert tools.",
          "VPN и corporate endpoint filters.",
          "AdGuard и системные traffic filters.",
          "Killer, SmartByte и Intel Connectivity services.",
          "Антивирусный quarantine WinDivert.",
          "Нестандартные proxy, route и DNS settings.",
        ],
      },
      {
        id: "limits",
        title: "Что остаётся experimental",
        bullets: [
          "ISP-specific IPv4 DPI bypass.",
          "Full live IPv6 bypass в сети пользователя.",
          "Live DoH routing на конкретном Windows build/adapter.",
          "Physical Ethernet/Wi-Fi arrival/removal transitions.",
          "Visible toast и interactive Dashboard rendering.",
        ],
      },
    ],
    previous: { label: "Архитектура", href: "/docs/architecture" },
  },
};

export const docsOverviewCards = [
  { title: "Быстрый старт", description: "Четыре assets, verification и первый запуск.", href: "/docs/getting-started" },
  { title: "Service Matrix", description: "Профили, address families и isolated workers.", href: "/docs/service-matrix" },
  { title: "Strategy Lab", description: "Throughput, HLS и transport measurements.", href: "/docs/strategy-lab" },
  { title: "Обновления", description: "Attestations, detached transaction и rollback.", href: "/docs/updates" },
  { title: "Проверка релиза", description: "Signed reports, Viewer и trust receipt.", href: "/docs/security" },
  { title: "Диагностика", description: "Evidence-backed findings и reversible repair.", href: "/docs/diagnostics" },
  { title: "Архитектура", description: "Supervisor, native tools и release gate.", href: "/docs/architecture" },
  { title: "Совместимость", description: "Windows targets и live limitations.", href: "/docs/compatibility" },
];
