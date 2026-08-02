import type { ReactNode } from "react";
import type { LucideIcon } from "lucide-react";
import { ButtonLink, FeatureCard } from "@/components/ui/primitives";
import { cn } from "@/lib/utils";

export const Button = ButtonLink;

export function BentoGrid({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={cn("grid gap-4 lg:grid-cols-6", className)}>{children}</div>;
}

export function SecurityCard({ icon, title, description }: { icon: LucideIcon; title: string; description: string }) {
  return <FeatureCard icon={icon} title={title} description={description} />;
}

export function GlowBackground({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div className={cn("relative overflow-hidden", className)}>
      <div className="pointer-events-none absolute inset-x-1/4 -top-40 h-72 rounded-full bg-cyan-300/10 blur-3xl" />
      <div className="network-grid pointer-events-none absolute inset-0 opacity-30" />
      <div className="relative">{children}</div>
    </div>
  );
}
