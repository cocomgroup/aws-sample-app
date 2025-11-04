import adapter from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/** @type {import('@sveltejs/kit').Config} */
const config = {
	// Preprocess with Vite
	preprocess: vitePreprocess(),

	kit: {
		// Use static adapter for S3 deployment
		adapter: adapter({
			// Output directory
			pages: 'build',
			assets: 'build',
			fallback: 'index.html',
			precompress: false,
			strict: true
		}),

		// Prerendering configuration
		prerender: {
			handleHttpError: 'warn',
			handleMissingId: 'warn',
			entries: ['*']
		},

		// Path configuration
		paths: {
			base: '',
			assets: ''
		},

		// CSRF protection
		csrf: {
			checkOrigin: true
		},

		// Alias configuration
		alias: {
			$components: 'src/components',
			$stores: 'src/stores',
			$utils: 'src/utils',
			$types: 'src/types'
		}
	}
};

export default config;
