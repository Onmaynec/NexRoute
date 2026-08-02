import Link from "next/link";
import type { ComponentType, ReactNode, SVGProps } from "react";
import { ArrowRight } from "lucide-react";
import { cn } from "@/lib/utils";

type Icon = ComponentType<SVGProps<SVGSVGElement>>;

export function Badge({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <span className={cn("inline-flex items-center rounded-full border border-cyan-300/18 bg-cyan-300/[0.055] px-3 py-1 text-[11px] font-medium uppercase tracking-[0.16em] text-cyan-200", className)}>
      {children}
    </span>
  );
}

export function ButtonLink({
  href,
  children,
  variant = "primary",
  className,
  external = false,
}: {
  href: string;
  children: ReactNode;
  variant?: "primary" | "secondary" | "ghost";
  className?: string;
  external?: boolean;
}) {
  const classes = cn(
    "inline-flex min-h-11 items-center justify-center gap-2 rounded-xl px-5 text-sm font-semibold transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300 focus-visible:ring-offset-2 focus-visible:ring-offset-[#050709]",
    variant === "primary" && "bg-cyan-300 text-[#041013] shadow-[0_0_28px_rgba(34,211,238,.16)] hover:bg-cyan-200",
    variant === "secondary" && "border border-white/10 bg-white/[0.035] text-white hover:border-white/16 hover:bg-white/[0.06]",
    variant === "ghost" && "text-zinc-300 hover:bg-white/[0.04] hover:text-white",
    className,
  );
  if (external) {
    return (
      <a className={classes} href={href} target="_blank" rel="noreferrer">
        {children}
      </a>
    );
  }
  return (
    <Link className={classes} href={href}>
      {children}
    </Link>
  );
}

export function SectionHeading({
  eyebrow,
  title,
  description,
  align = "left",
}: {
  eyebrow?: string;
  title: string;
  description?: string;
  align?: "left" | "center";
}) {
  return (
    <div className={cn("max-w-3xl", align === "center" && "mx-auto text-center")}>
      {eyebrow && <p className="font-mono text-xs uppercase tracking-[0.2em] text-cyan-300">{eyebrow}</p>}
      <h2 className="mt-4 text-balance text-[clamp(2.2rem,5vw,3.75rem)] font-semibold leading-[1.02] tracking-[-0.045em] text-white">
        {title}
      </h2>
      {description && <p className="mt-5 text-pretty text-base leading-7 text-zinc-400 sm:text-lg">{description}</p>}
    </div>
  );
}

export function FeatureCard({
  title,
  description,
  label,
  icon: Icon,
  children,
  className,
}: {
  title: string;
  description: string;
  label?: string;
  icon?: Icon;
  children?: ReactNode;
  className?: string;
}) {
  return (
    <article className={cn("group relative overflow-hidden rounded-[24px] border border-white/8 bg-white/[0.025] p-6 shadow-[inset_0_1px_rgba(255,255,255,.025)] transition duration-300 hover:-translate-y-0.5 hover:border-cyan-300/20 hover:bg-white/[0.035] sm:p-7", className)}>
      <div className="pointer-events-none absolute inset-x-12 -top-20 h-32 rounded-full bg-cyan-300/8 blur-3xl opacity-0 transition group-hover:opacity-100" />
      <div className="relative">
        {Icon && (
          <div className="mb-5 flex size-10 items-center justify-center rounded-xl border border-white/10 bg-[#081117] text-cyan-200">
            <Icon className="size-5" aria-hidden="true" />
          </div>
        )}
        <h3 className="text-xl font-semibold tracking-[-0.025em] text-white">{title}</h3>
        <p className="mt-3 text-sm leading-6 text-zinc-400">{description}</p>
        {label && <p className="mt-5 font-mono text-[11px] uppercase tracking-[0.15em] text-zinc-600">{label}</p>}
        {children && <div className="mt-6">{children}</div>}
      </div>
    </article>
  );
}

export function StatusBadge({ status, children }: { status: "success" | "info" | "warning" | "error"; children: ReactNode }) {
  const styles = {
    success: "border-emerald-300/16 bg-emerald-300/7 text-emerald-200",
    info: "border-cyan-300/16 bg-cyan-300/7 text-cyan-200",
    warning: "border-amber-300/16 bg-amber-300/7 text-amber-200",
    error: "border-rose-300/16 bg-rose-300/7 text-rose-200",
  };
  return <span className={cn("inline-flex rounded-full border px-2.5 py-1 font-mono text-[10px] uppercase tracking-[0.13em]", styles[status])}>{children}</span>;
}

export function InlineLink({ href, children }: { href: string; children: ReactNode }) {
  return (
    <Link className="inline-flex items-center gap-1.5 text-sm font-medium text-cyan-200 transition hover:text-cyan-100" href={href}>
      {children} <ArrowRight className="size-4" aria-hidden="true" />
    </Link>
  );
}

export function PageHero({ eyebrow, title, description, children }: { eyebrow?: string; title: string; description: string; children?: ReactNode }) {
  return (
    <section className="relative overflow-hidden border-b border-white/8 py-20 sm:py-28">
      <div className="glow-orb glow-orb-one" />
      <div className="network-grid absolute inset-0 opacity-30" />
      <div className="relative mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div className="max-w-4xl">
          {eyebrow && <Badge>{eyebrow}</Badge>}
          <h1 className="mt-6 text-balance text-[clamp(3rem,7vw,5.5rem)] font-semibold leading-[.98] tracking-[-0.055em] text-white">{title}</h1>
          <p className="mt-6 max-w-2xl text-pretty text-lg leading-8 text-zinc-400">{description}</p>
          {children && <div className="mt-8 flex flex-wrap gap-3">{children}</div>}
        </div>
      </div>
    </section>
  );
}
