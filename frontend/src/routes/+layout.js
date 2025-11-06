// src/routes/+layout.js
// This file configures SvelteKit for static site generation (SSG)
// Required for deploying to S3/CloudFront

// Prerender all pages at build time
export const prerender = true;

// Disable server-side rendering (SSR) - use client-side only
export const ssr = false;
