"use client";

import { GitHubIcon } from "@/components/ui/github-icon";
import { useEffect, useMemo, useState } from "react";
import { motion, useReducedMotion } from "motion/react";
import {
  Check,
  CheckCircle2,
  Circle,
  Download,
  HardDriveDownload,
  RefreshCcw,
  RotateCcw,
  ShieldCheck,
} from "lucide-react";
import { StatusBadge } from "@/components/ui/primitives";
import { cn } from "@/lib/utils";

const terminalRows = [
  ["Runtime", "READY", "success"],
  ["Service Matrix", "LOADED", "success"],
  ["Update Channel", "STABLE", "info"],
  ["Integrity Check", "VERIFIED", "success"],
] as const;

export function TerminalWindow({ compact = false }: { compact?: boolean }) {
  const reduced = useReducedMotion();
  return (
    <div className="relative overflow-hidden rounded-[26px] border border-white/10 bg-[#04080b]/95 shadow-[0_28px_100px_rgba(0,0,0,.52),0_0_70px_rgba(34,211,238,.07)]">
      <div className="flex items-center justify-between border-b border-white/8 px-4 py-3">
        <div className="flex items-center gap-2" aria-hidden="true">
          <span className="size-2 rounded-full bg-zinc-700" />
          <span className="size-2 rounded-full bg-zinc-600" />
          <span className="size-2 rounded-full bg-cyan-300/70" />
        </div>
        <span className="font-mono text-[10px] uppercase tracking-[.18em] text-zinc-600">Conceptual product preview</span>
      </div>
      <div className={cn("overflow-x-auto font-mono", compact ? "p-4 text-[11px]" : "p-5 text-xs sm:p-7 sm:text-[13px]")}>
        <motion.div
          initial={reduced ? false : "hidden"}
          animate="show"
          variants={{ show: { transition: { staggerChildren: 0.075 } } }}
          className="min-w-[500px]"
        >
          <motion.p variants={{ hidden: { opacity: 0, y: 5 }, show: { opacity: 1, y: 0 } }} className="text-cyan-200">
            NEXROUTE CONTROL CENTER
          </motion.p>
          <motion.p variants={{ hidden: { opacity: 0 }, show: { opacity: 1 } }} className="mt-1 text-zinc-700">
            ──────────────────────────────────────────────
          </motion.p>
          <motion.p variants={{ hidden: { opacity: 0 }, show: { opacity: 1 } }} className="mt-5 text-[10px] uppercase tracking-[.2em] text-zinc-600">
            SYSTEM STATUS
          </motion.p>
          <div className="mt-3 space-y-2.5">
            {terminalRows.map(([label, value, status]) => (
              <motion.div key={label} variants={{ hidden: { opacity: 0, x: -8 }, show: { opacity: 1, x: 0 } }} className="grid grid-cols-[180px_1fr] items-center gap-4">
                <span className="text-zinc-400">● {label}</span>
                <span className={status === "info" ? "text-cyan-300" : "text-emerald-300"}>{value}</span>
              </motion.div>
            ))}
          </div>
          <motion.p variants={{ hidden: { opacity: 0 }, show: { opacity: 1 } }} className="mt-6 text-[10px] uppercase tracking-[.2em] text-zinc-600">
            ACTIVE PROFILES
          </motion.p>
          <motion.p variants={{ hidden: { opacity: 0 }, show: { opacity: 1 } }} className="mt-3 text-zinc-300">
            YouTube &nbsp; Discord &nbsp; ChatGPT &nbsp; Telegram &nbsp; Signal
          </motion.p>
          <motion.div variants={{ hidden: { opacity: 0, y: 6 }, show: { opacity: 1, y: 0 } }} className="mt-7 grid grid-cols-2 gap-x-6 gap-y-2 text-zinc-400">
            <span>[1] SELECT STRATEGY</span>
            <span>[6] CHECK UPDATES</span>
            <span>[12] STRATEGY LAB</span>
            <span>[14] SERVICE MATRIX</span>
          </motion.div>
          <motion.div variants={{ hidden: { opacity: 0 }, show: { opacity: 1 } }} className="mt-7 rounded-lg border border-cyan-300/10 bg-cyan-300/[0.035] p-3 text-zinc-400">
            <span className="text-cyan-300">STATUS</span> &nbsp; Strategy loaded · Service filters synchronized · Runtime ready
          </motion.div>
        </motion.div>
      </div>
    </div>
  );
}

const services = ["YouTube", "Discord", "ChatGPT", "Telegram", "WhatsApp", "Signal", "Instagram", "TikTok", "X", "LinkedIn"];

export function ServiceMatrixDemo() {
  const [active, setActive] = useState(() => new Set(["YouTube", "Discord", "ChatGPT", "Telegram", "Signal"]));
  function toggle(service: string) {
    setActive((current: Set<string>) => {
      const next = new Set(current);
      if (next.has(service)) next.delete(service);
      else next.add(service);
      return next;
    });
  }
  return (
    <div className="rounded-[26px] border border-white/9 bg-[#060b0f] p-4 shadow-[0_24px_90px_rgba(0,0,0,.38)] sm:p-6">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-white/8 pb-4">
        <div>
          <p className="font-mono text-[10px] uppercase tracking-[.18em] text-cyan-300">Service Matrix · Demo</p>
          <p className="mt-1 text-sm text-zinc-500">Локальная визуальная демонстрация</p>
        </div>
        <StatusBadge status="info">{active.size} active</StatusBadge>
      </div>
      <div className="mt-5 grid grid-cols-1 gap-2 sm:grid-cols-2">
        {services.map((service) => {
          const enabled = active.has(service);
          return (
            <button
              key={service}
              type="button"
              onClick={() => toggle(service)}
              aria-pressed={enabled}
              className={cn(
                "flex items-center justify-between rounded-xl border px-3.5 py-3 text-left transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300",
                enabled ? "border-cyan-300/17 bg-cyan-300/[0.055] text-white" : "border-white/7 bg-white/[0.018] text-zinc-500 hover:border-white/12",
              )}
            >
              <span className="text-sm font-medium">{service}</span>
              <span className={cn("relative h-5 w-9 rounded-full transition", enabled ? "bg-cyan-300" : "bg-zinc-800")}>
                <span className={cn("absolute top-0.5 size-4 rounded-full bg-[#071015] transition-transform", enabled ? "translate-x-[18px]" : "translate-x-0.5")} />
              </span>
            </button>
          );
        })}
      </div>
      <div className="mt-5 grid gap-2 sm:grid-cols-3">
        {["domain groups", "IPv4 sets", "runtime args"].map((item, index) => (
          <div key={item} className="rounded-xl border border-white/7 bg-black/20 p-3">
            <p className="font-mono text-[9px] uppercase tracking-[.16em] text-zinc-600">0{index + 1}</p>
            <p className="mt-2 text-xs text-zinc-400">{item}</p>
            <div className="mt-3 h-1.5 overflow-hidden rounded-full bg-white/5">
              <div className="h-full rounded-full bg-cyan-300/60" style={{ width: `${Math.min(35 + active.size * 6 + index * 4, 92)}%` }} />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

const labRows = [
  { name: "General ALT", ms: "142 ms" },
  { name: "Discord Filter", ms: "86 ms" },
  { name: "TLS Split", ms: "—" },
  { name: "Multi-Split", ms: "…" },
];

export function StrategyLabDemo() {
  const reduced = useReducedMotion();
  const [step, setStep] = useState(reduced ? 4 : 0);
  useEffect(() => {
    if (reduced) return;
    const timer = window.setInterval(() => setStep((value: number) => (value + 1) % 5), 1400);
    return () => window.clearInterval(timer);
  }, [reduced]);
  return (
    <div className="rounded-[26px] border border-white/9 bg-[#060b0f] p-5 font-mono shadow-[0_24px_90px_rgba(0,0,0,.38)] sm:p-7">
      <div className="flex items-center justify-between border-b border-white/8 pb-4">
        <div>
          <p className="text-sm text-cyan-200">STRATEGY LAB</p>
          <p className="mt-1 text-[10px] uppercase tracking-[.15em] text-zinc-600">Conceptual test sequence</p>
        </div>
        <StatusBadge status="info">14 / 21</StatusBadge>
      </div>
      <div className="mt-5 space-y-2">
        {labRows.map((row, index) => {
          const state = index < Math.max(step - 1, 0) ? (index === 2 ? "failed" : "passed") : index === Math.max(step - 1, 0) ? "testing" : "queued";
          return (
            <div key={row.name} className="grid grid-cols-[28px_1fr_80px_65px] items-center gap-2 rounded-xl border border-white/6 bg-white/[0.018] px-3 py-3 text-[11px] sm:text-xs">
              <span className="text-zinc-700">0{index + 1}</span>
              <span className="truncate text-zinc-300">{row.name}</span>
              <span className={cn(state === "passed" && "text-emerald-300", state === "failed" && "text-rose-300", state === "testing" && "text-cyan-300", state === "queued" && "text-zinc-700")}>
                {state.toUpperCase()}
              </span>
              <span className="text-right text-zinc-600">{state === "passed" ? row.ms : state === "failed" ? "—" : state === "testing" ? "…" : "—"}</span>
            </div>
          );
        })}
      </div>
      <div className="mt-5 flex items-center gap-3">
        <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-white/6">
          <motion.div className="h-full rounded-full bg-cyan-300" animate={{ width: `${Math.max(step, 1) * 20}%` }} transition={{ duration: reduced ? 0 : 0.4 }} />
        </div>
        <span className="text-[10px] text-zinc-600">testing</span>
      </div>
    </div>
  );
}

const updateSteps = [
  { label: "Проверка релиза", icon: GitHubIcon },
  { label: "Загрузка пакета", icon: Download },
  { label: "Проверка SHA-256", icon: ShieldCheck },
  { label: "Создание backup", icon: HardDriveDownload },
  { label: "Установка", icon: RefreshCcw },
  { label: "Проверка результата", icon: CheckCircle2 },
];

export function UpdateFlow() {
  return (
    <div className="grid grid-cols-[repeat(auto-fit,minmax(9.5rem,1fr))] gap-3">
      {updateSteps.map((step, index) => {
        const Icon = step.icon;
        return (
          <div key={step.label} className="flex min-h-[170px] min-w-0 flex-col rounded-2xl border border-white/8 bg-white/[0.022] p-4">
            <div className="flex size-9 shrink-0 items-center justify-center rounded-xl border border-cyan-300/13 bg-cyan-300/[0.045] text-cyan-200">
              <Icon className="size-4" />
            </div>
            <p className="mt-4 break-words text-sm font-medium leading-5 text-white">{step.label}</p>
            <p className="mt-auto pt-4 font-mono text-[10px] uppercase tracking-[.14em] text-zinc-600">step 0{index + 1}</p>
          </div>
        );
      })}
    </div>
  );
}

export function RollbackDemo() {
  return (
    <div className="rounded-2xl border border-white/8 bg-[#060b0f] p-4 sm:p-5">
      <div className="grid grid-cols-[repeat(auto-fit,minmax(10.5rem,1fr))] gap-3">
        <div className="flex min-h-[136px] min-w-0 flex-col rounded-xl border border-emerald-300/12 bg-emerald-300/[0.04] p-4">
          <div className="flex items-start justify-between gap-3">
            <p className="font-mono text-[10px] uppercase tracking-[.15em] text-emerald-300">VERSION A</p>
            <span className="font-mono text-[9px] text-zinc-700">01</span>
          </div>
          <p className="mt-auto break-words pt-5 text-sm leading-5 text-white">Рабочая установка</p>
        </div>
        <div className="flex min-h-[136px] min-w-0 flex-col rounded-xl border border-rose-300/12 bg-rose-300/[0.04] p-4">
          <div className="flex items-start justify-between gap-3">
            <p className="font-mono text-[10px] uppercase tracking-[.15em] text-rose-300">ОШИБКА ОБНОВЛЕНИЯ</p>
            <span className="font-mono text-[9px] text-zinc-700">02</span>
          </div>
          <p className="mt-auto break-words pt-5 text-sm leading-5 text-white">Установка остановлена</p>
        </div>
        <div className="flex min-h-[136px] min-w-0 flex-col rounded-xl border border-cyan-300/12 bg-cyan-300/[0.04] p-4">
          <div className="flex items-start justify-between gap-3">
            <p className="font-mono text-[10px] uppercase tracking-[.15em] text-cyan-300">ВОССТАНОВЛЕНО</p>
            <span className="flex items-center gap-2 font-mono text-[9px] text-zinc-600"><RotateCcw className="size-3.5 text-cyan-300" />03</span>
          </div>
          <p className="mt-auto break-words pt-5 text-sm leading-5 text-white">Версия A восстановлена из backup</p>
        </div>
      </div>
    </div>
  );
}

export function ReleaseVerificationDemo() {
  const stages = ["Исходный коммит", "GitHub Actions", "Аттестация", "Релизный файл"];
  return (
    <div className="rounded-2xl border border-white/8 bg-[#060b0f] p-4 sm:p-5">
      <div className="grid grid-cols-[repeat(auto-fit,minmax(8.5rem,1fr))] gap-3">
        {stages.map((label, index) => (
          <div key={label} className="flex min-h-[132px] min-w-0 flex-col items-center justify-center rounded-xl border border-white/7 bg-white/[0.02] px-3 py-4 text-center">
            <div className="flex size-9 shrink-0 items-center justify-center rounded-full border border-cyan-300/14 bg-cyan-300/[0.045] text-cyan-200">
              {index === stages.length - 1 ? <Check className="size-4" /> : <Circle className="size-3 fill-current" />}
            </div>
            <p className="mt-3 break-words text-xs leading-5 text-zinc-300">{label}</p>
            <p className="mt-2 font-mono text-[9px] uppercase tracking-[.14em] text-zinc-700">0{index + 1}</p>
          </div>
        ))}
      </div>
    </div>
  );
}

export function AnimatedRouteGraph({ className }: { className?: string }) {
  const paths = useMemo(
    () => [
      "M30 170 C130 40 190 210 300 88 S480 35 590 150",
      "M20 85 C140 180 220 30 340 145 S520 205 620 75",
      "M80 210 C180 120 250 230 380 110 S510 20 610 115",
    ],
    [],
  );
  return (
    <svg className={cn("h-full w-full", className)} viewBox="0 0 640 250" role="img" aria-label="Абстрактная схема сетевых маршрутов">
      <defs>
        <filter id="routeGlow"><feGaussianBlur stdDeviation="4" result="blur" /><feMerge><feMergeNode in="blur" /><feMergeNode in="SourceGraphic" /></feMerge></filter>
      </defs>
      {paths.map((path: string, index: number) => (
        <path key={path} id={`route-${index}`} d={path} fill="none" stroke={index === 0 ? "rgba(34,211,238,.65)" : "rgba(255,255,255,.10)"} strokeWidth={index === 0 ? 1.7 : 1.1} />
      ))}
      {[[30,170],[300,88],[590,150],[20,85],[340,145],[620,75],[80,210],[380,110],[610,115]].map(([x,y], index) => (
        <g key={`${x}-${y}`}>
          <circle cx={x} cy={y} r="5" fill="#071015" stroke={index % 3 === 0 ? "#22D3EE" : "rgba(255,255,255,.22)"} />
          <circle cx={x} cy={y} r="1.5" fill={index % 3 === 0 ? "#67E8F9" : "#748188"} />
        </g>
      ))}
      <circle r="3" fill="#67E8F9" filter="url(#routeGlow)" className="route-dot">
        <animateMotion dur="11s" repeatCount="indefinite" rotate="auto"><mpath href="#route-0" /></animateMotion>
      </circle>
      <circle r="2.5" fill="#38BDF8" className="route-dot route-dot-delay">
        <animateMotion dur="15s" repeatCount="indefinite" rotate="auto"><mpath href="#route-1" /></animateMotion>
      </circle>
    </svg>
  );
}
