import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
	plugins: [sveltekit()],
	
	// Environment variable prefix
	envPrefix: 'VITE_',
	
	build: {
		// Generate sourcemaps for debugging
		sourcemap: false,
		
		// Optimize chunks
		rollupOptions: {
			output: {
				manualChunks: {
					vendor: ['svelte', '@sveltejs/kit']
				}
			}
		},
		
		// Target modern browsers
		target: 'es2020',
		
		// Minify
		minify: 'terser',
		terserOptions: {
			compress: {
				drop_console: true,
				drop_debugger: true
			}
		}
	},
	
	server: {
		port: 5173,
		proxy: {
			// Proxy API calls during development
			'/api': {
				target: 'http://localhost:8080',
				changeOrigin: true
			}
		}
	}
});
