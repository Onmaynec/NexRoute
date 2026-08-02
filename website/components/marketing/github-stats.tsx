import { GitFork, Github, Star } from "lucide-react";
import { getRepositoryStats } from "@/lib/github";

export async function GitHubStats() {
  const stats = await getRepositoryStats();
  return (
    <a
      href={stats.htmlUrl}
      target="_blank"
      rel="noreferrer"
      className="inline-flex flex-wrap items-center gap-4 rounded-2xl border border-white/8 bg-white/[0.025] px-4 py-3 text-sm text-zinc-400 transition hover:border-cyan-300/16 hover:text-white"
    >
      <span className="inline-flex items-center gap-2"><Github className="size-4" /> Open source</span>
      {stats.stars !== null && <span className="inline-flex items-center gap-1.5"><Star className="size-3.5" /> {stats.stars}</span>}
      {stats.forks !== null && <span className="inline-flex items-center gap-1.5"><GitFork className="size-3.5" /> {stats.forks}</span>}
    </a>
  );
}
