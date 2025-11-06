import adapter from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/** @type {import('@sveltejs/kit').Config} */
const config = {
	// Consult https://kit.svelte.dev/docs/integrations#preprocessors
	preprocess: vitePreprocess(),

	kit: {
		// Use static adapter for S3/CloudFront deployment
		adapter: adapter({
			// Output directory
			pages: 'build',
			assets: 'build',
			// Fallback for SPA routing (important for CloudFront)
			fallback: 'index.html',
			precompress: false,
			strict: true
		}),
		prerender: {
      		handleHttpError: ({ path, referrer, message }) => {
        		// Ignore 404s for og-image.png
        		if (path === '/og-image.png') {
          			return;
        		}
        		// Throw for other errors
        		throw new Error(message);
      		}
    	}
	}
};

export default config;
