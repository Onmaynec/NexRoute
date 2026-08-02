const API = "https://api.github.com/repos/Onmaynec/NexRoute";
const repositoryUrl = "https://github.com/Onmaynec/NexRoute";

export type ReleaseAsset = {
  name: string;
  browser_download_url: string;
  size: number;
};

export type StableRelease = {
  tagName: string;
  version: string;
  name: string;
  publishedAt: string | null;
  htmlUrl: string;
  body: string;
  archive: ReleaseAsset | null;
  checksum: ReleaseAsset | null;
};

export type RepositoryStats = {
  stars: number | null;
  forks: number | null;
  htmlUrl: string;
};

type GitHubRelease = {
  tag_name: string;
  name: string | null;
  published_at: string | null;
  html_url: string;
  body: string | null;
  draft: boolean;
  prerelease: boolean;
  assets: ReleaseAsset[];
};

function headers(): HeadersInit {
  const value: Record<string, string> = {
    Accept: "application/vnd.github+json",
    "User-Agent": "NexRoute-Website",
    "X-GitHub-Api-Version": "2022-11-28",
  };
  if (process.env.GITHUB_TOKEN) {
    value.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  }
  return value;
}

function normalizeRelease(release: GitHubRelease): StableRelease {
  const archive =
    release.assets.find((asset) => /^NexRoute-\d+\.\d+\.\d+-win-x64\.zip$/.test(asset.name)) ?? null;
  const checksum = archive
    ? release.assets.find((asset) => asset.name === `${archive.name}.sha256`) ?? null
    : null;
  return {
    tagName: release.tag_name,
    version: release.tag_name.replace(/^v/, ""),
    name: release.name || release.tag_name,
    publishedAt: release.published_at,
    htmlUrl: release.html_url,
    body: release.body || "",
    archive,
    checksum,
  };
}

export async function getStableReleases(limit = 10): Promise<StableRelease[]> {
  try {
    const response = await fetch(`${API}/releases?per_page=${Math.max(limit, 10)}`, {
      headers: headers(),
      next: { revalidate: 900 },
    });
    if (!response.ok) return [];
    const data = (await response.json()) as GitHubRelease[];
    return data
      .filter((release) => !release.draft && !release.prerelease)
      .slice(0, limit)
      .map(normalizeRelease);
  } catch {
    return [];
  }
}

export async function getLatestStableRelease(): Promise<StableRelease | null> {
  const releases = await getStableReleases(1);
  return releases[0] ?? null;
}

export async function getRepositoryStats(): Promise<RepositoryStats> {
  try {
    const response = await fetch(API, {
      headers: headers(),
      next: { revalidate: 3600 },
    });
    if (!response.ok) throw new Error("GitHub API unavailable");
    const data = (await response.json()) as {
      stargazers_count?: number;
      forks_count?: number;
      html_url?: string;
    };
    return {
      stars: typeof data.stargazers_count === "number" ? data.stargazers_count : null,
      forks: typeof data.forks_count === "number" ? data.forks_count : null,
      htmlUrl: data.html_url || repositoryUrl,
    };
  } catch {
    return { stars: null, forks: null, htmlUrl: repositoryUrl };
  }
}
