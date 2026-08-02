import { Compass, Home, Search } from "lucide-react";
import { ButtonLink } from "@/components/ui/primitives";
import { AnimatedRouteGraph } from "@/components/product/demos";

export default function NotFound() {
  return (
    <section className="relative min-h-[72vh] overflow-hidden px-4 py-24">
      <div className="network-grid absolute inset-0 opacity-35" />
      <div className="absolute inset-0 opacity-35"><AnimatedRouteGraph /></div>
      <div className="relative mx-auto max-w-2xl text-center">
        <Compass className="mx-auto size-10 text-cyan-300" />
        <p className="mt-6 font-mono text-sm text-cyan-300">ROUTE_NOT_FOUND · 404</p>
        <h1 className="mt-5 text-5xl font-semibold tracking-[-0.05em] text-white sm:text-7xl">Маршрут не найден</h1>
        <p className="mt-6 text-lg leading-8 text-zinc-400">Страница была перемещена, удалена или адрес введён неверно.</p>
        <div className="mt-8 flex flex-col justify-center gap-3 sm:flex-row">
          <ButtonLink href="/"><Home className="size-4" /> На главную</ButtonLink>
          <ButtonLink href="/docs" variant="secondary"><Search className="size-4" /> Документация</ButtonLink>
        </div>
      </div>
    </section>
  );
}
