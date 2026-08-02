# Официальный сайт NexRoute 🌐

Исходный код сайта находится в `website/` и использует Next.js App Router, TypeScript, Tailwind CSS, Motion и Lucide Icons.

## Локальный запуск

```bash
cd website
cp .env.example .env.local
npm install
npm run dev
```

Локальный адрес: `http://localhost:3000`.

## Production build

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

`NEXT_PUBLIC_SITE_URL` задаёт canonical URLs, sitemap и social metadata. `GITHUB_TOKEN` необязателен и используется только для повышения rate limit публичного GitHub API.

## Vercel

1. Импортируйте `Onmaynec/NexRoute`.
2. Укажите Root Directory `website`.
3. Выберите Next.js Framework Preset.
4. Добавьте `NEXT_PUBLIC_SITE_URL`.
5. Выполните Deploy.
6. После назначения production-домена обновите переменную и повторите deployment.

## GitHub integration

Сайт запрашивает публичные endpoints репозитория для:

- последнего стабильного release;
- release assets;
- даты публикации;
- release notes;
- stars и forks, когда API доступен.

Draft и prerelease не используются как основной стабильный релиз. При ошибке API сайт показывает ссылку на GitHub Releases и не подставляет выдуманные данные.

## Источники документации

Структурированный контент в `website/content/docs.ts` основан на `README.md`, `docs/SERVICES.md`, `docs/UPDATES.md`, `docs/ATTESTATIONS.md`, `docs/COMPATIBILITY.md`, `docs/ARCHITECTURE.md` и release-контрактах проекта.
