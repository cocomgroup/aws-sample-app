import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
	plugins: [sveltekit()],
	
	build: {
		rollupOptions: {
			output: {
				// Let Vite handle chunking automatically
				manualChunks: undefined
			}
		}
	},
	
	server: {
		port: 5173,
		strictPort: false,
		host: true
	}
});