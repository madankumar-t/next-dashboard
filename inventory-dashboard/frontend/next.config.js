/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,

  // ✅ REQUIRED for static hosting (S3 / CloudFront)
  output: 'export',

  // ✅ Required for static export
  images: {
    unoptimized: true,
  },

  // ✅ false — prevents S3 from 302-redirecting /auth/callback?code=xxx to /auth/callback/ (which strips the code)
  trailingSlash: false,

  compiler: {
    removeConsole:
      process.env.NODE_ENV === 'production'
        ? { exclude: ['error', 'warn'] }
        : false,
  },

  // 🔴 MUST BE FALSE — otherwise Next.js tries to load "critters"
  experimental: {
    optimizeCss: false,
  },

  typescript: {
    ignoreBuildErrors: false,
  },
};

module.exports = nextConfig;
