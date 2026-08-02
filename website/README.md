# NexRoute Website

Официальный многостраничный сайт NexRoute на Next.js App Router, TypeScript, Tailwind CSS 4, Motion и Lucide Icons.

## Возможности сайта

- главная продуктовая страница с интерактивными HTML/CSS mockups;
- страницы Features, Download, Security, FAQ и Changelog;
- адаптивная документация с поиском, sidebar, оглавлением и Previous/Next;
- получение последнего стабильного GitHub Release без обязательного token;
- fallback-состояния без выдуманных версий и чисел;
- SHA-256 и GitHub attestation инструкции;
- Open Graph/Twitter image routes, sitemap, robots, manifest и JSON-LD;
- reduced-motion, keyboard navigation и заметные focus states.

## Локальный запуск

Требуется Node.js 22 или новее.

```bash
cd website
cp .env.example .env.local
npm install
npm run dev
```

Откройте `http://localhost:3000`.

## Проверка production-сборки

```bash
cd website
npm install
npm run typecheck
npm run build
npm run start
```

## Переменные окружения

```env
NEXT_PUBLIC_SITE_URL=https://your-domain.example
GITHUB_TOKEN=
```

`NEXT_PUBLIC_SITE_URL` обязателен для корректных canonical URL, sitemap и social metadata в production. `GITHUB_TOKEN` необязателен: публичный API работает без него, но token повышает rate limit.

## Деплой на Vercel

1. Импортируйте репозиторий `Onmaynec/NexRoute` в Vercel.
2. Укажите **Root Directory**: `website`.
3. Framework Preset: **Next.js**.
4. Добавьте `NEXT_PUBLIC_SITE_URL` с будущим production-доменом.
5. При необходимости добавьте server-only `GITHUB_TOKEN` с read-only доступом к публичному репозиторию.
6. Выполните Deploy.
7. После назначения домена обновите `NEXT_PUBLIC_SITE_URL` и повторите deployment.

## Источники контента

Тексты документации основаны на фактических файлах репозитория:

- `README.md`;
- `docs/SERVICES.md`;
- `docs/UPDATES.md`;
- `docs/ATTESTATIONS.md`;
- `docs/COMPATIBILITY.md`;
- `docs/ARCHITECTURE.md`;
- `CHANGELOG.md` и GitHub Releases.

Команды, отсутствующие в исходных документах, не выдаются за настоящие CLI-команды. Терминальные демонстрации помечены как conceptual product preview.

## Что проверить перед production-деплоем

- назначить реальный домен и `NEXT_PUBLIC_SITE_URL`;
- проверить доступность GitHub API из выбранного региона Vercel;
- при желании добавить реальные скриншоты NexRoute в отдельную галерею (текущий сайт использует лёгкие HTML/CSS mockups);
- проверить release notes новой версии после публикации;
- запустить Lighthouse для production URL;
- проверить social preview после назначения домена.
