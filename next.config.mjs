/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Standalone offline console: no remote fonts, no remote images.
  // DEVIATION (P2-SPEC §8 / Appendix C #9): no self-hosted Source Sans Pro woff2 — system font stack instead (documented in README "Deviations from spec").
  images: { unoptimized: true },
  // Wording sweep: the old /precincts route was renamed to /sectors — keep the
  // legacy path working with a temporary redirect.
  async redirects() {
    return [
      {
        source: "/precincts",
        destination: "/sectors",
        permanent: false,
      },
    ];
  },
};

export default nextConfig;
