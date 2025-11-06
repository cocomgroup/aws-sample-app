<script>
	import { onMount } from 'svelte';

	// API endpoint from environment variable
	const API_URL = import.meta.env.VITE_API_URL || '/api';

	let healthStatus = null;
	let loading = true;
	let error = null;

	onMount(async () => {
		try {
			const response = await fetch(`${API_URL}/health`);
			if (!response.ok) throw new Error('API request failed');
			healthStatus = await response.json();
		} catch (err) {
			error = err.message;
		} finally {
			loading = false;
		}
	});
</script>

<svelte:head>
	<title>Home - My Svelte + Go App</title>
	<meta name="description" content="Welcome to my Svelte + Go web application" />
</svelte:head>

<main>
	<div class="container">
		<header>
			<h1>🚀 Svelte + Go Web App</h1>
			<p class="subtitle">Deployed on AWS with CloudFront, S3, and EC2</p>
		</header>

		<section class="hero">
			<div class="hero-content">
				<h2>Welcome to Your Web Application</h2>
				<p>
					This is a full-stack application built with SvelteKit frontend and Go backend,
					deployed on AWS infrastructure.
				</p>
			</div>
		</section>

		<section class="status-card">
			<h3>🔌 Backend Status</h3>
			
			{#if loading}
				<div class="loading">
					<div class="spinner"></div>
					<p>Checking backend connection...</p>
				</div>
			{:else if error}
				<div class="error">
					<p>❌ Could not connect to backend</p>
					<small>{error}</small>
				</div>
			{:else if healthStatus}
				<div class="success">
					<p>✅ Backend is healthy!</p>
					<div class="health-details">
						<div class="detail">
							<strong>Status:</strong> {healthStatus.status}
						</div>
						{#if healthStatus.timestamp}
							<div class="detail">
								<strong>Timestamp:</strong> {new Date(healthStatus.timestamp).toLocaleString()}
							</div>
						{/if}
						{#if healthStatus.services}
							<div class="detail">
								<strong>Services:</strong>
								<ul>
									{#each Object.entries(healthStatus.services) as [service, status]}
										<li>{service}: {status}</li>
									{/each}
								</ul>
							</div>
						{/if}
					</div>
				</div>
			{/if}
		</section>

		<section class="features">
			<h3>📦 Stack Components</h3>
			<div class="feature-grid">
				<div class="feature">
					<div class="icon">⚡</div>
					<h4>SvelteKit Frontend</h4>
					<p>Fast, modern UI framework with static site generation</p>
				</div>
				<div class="feature">
					<div class="icon">🔧</div>
					<h4>Go Backend</h4>
					<p>High-performance API server with minimal footprint</p>
				</div>
				<div class="feature">
					<div class="icon">☁️</div>
					<h4>AWS Infrastructure</h4>
					<p>CloudFront CDN, S3 storage, EC2 compute</p>
				</div>
				<div class="feature">
					<div class="icon">🗄️</div>
					<h4>Data Layer</h4>
					<p>DynamoDB and Redis for fast, scalable storage</p>
				</div>
			</div>
		</section>

		<footer>
			<p>Built with ❤️ using SvelteKit and Go</p>
		</footer>
	</div>
</main>

<style>
	:global(body) {
		background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
		min-height: 100vh;
	}

	main {
		padding: 2rem;
		min-height: 100vh;
	}

	.container {
		max-width: 1200px;
		margin: 0 auto;
	}

	header {
		text-align: center;
		margin-bottom: 3rem;
		color: white;
	}

	h1 {
		font-size: 3rem;
		margin-bottom: 0.5rem;
		font-weight: 700;
	}

	.subtitle {
		font-size: 1.2rem;
		opacity: 0.9;
	}

	.hero {
		background: white;
		border-radius: 16px;
		padding: 3rem;
		margin-bottom: 2rem;
		box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
	}

	.hero-content h2 {
		color: #667eea;
		margin-bottom: 1rem;
		font-size: 2rem;
	}

	.hero-content p {
		color: #4a5568;
		font-size: 1.1rem;
		line-height: 1.6;
	}

	.status-card {
		background: white;
		border-radius: 16px;
		padding: 2rem;
		margin-bottom: 2rem;
		box-shadow: 0 10px 30px rgba(0, 0, 0, 0.2);
	}

	.status-card h3 {
		margin-bottom: 1.5rem;
		color: #2d3748;
	}

	.loading {
		text-align: center;
		padding: 2rem;
	}

	.spinner {
		width: 40px;
		height: 40px;
		border: 4px solid #f3f3f3;
		border-top: 4px solid #667eea;
		border-radius: 50%;
		animation: spin 1s linear infinite;
		margin: 0 auto 1rem;
	}

	@keyframes spin {
		0% { transform: rotate(0deg); }
		100% { transform: rotate(360deg); }
	}

	.success {
		padding: 1rem;
		background: #f0fff4;
		border: 2px solid #9ae6b4;
		border-radius: 8px;
		color: #22543d;
	}

	.error {
		padding: 1rem;
		background: #fff5f5;
		border: 2px solid #fc8181;
		border-radius: 8px;
		color: #742a2a;
	}

	.health-details {
		margin-top: 1rem;
		padding-top: 1rem;
		border-top: 1px solid #9ae6b4;
	}

	.detail {
		margin-bottom: 0.5rem;
	}

	.detail strong {
		color: #2d3748;
	}

	.detail ul {
		margin-left: 1.5rem;
		margin-top: 0.5rem;
	}

	.features {
		background: white;
		border-radius: 16px;
		padding: 2rem;
		margin-bottom: 2rem;
		box-shadow: 0 10px 30px rgba(0, 0, 0, 0.2);
	}

	.features h3 {
		margin-bottom: 2rem;
		color: #2d3748;
		text-align: center;
	}

	.feature-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
		gap: 1.5rem;
	}

	.feature {
		text-align: center;
		padding: 1.5rem;
		border-radius: 8px;
		background: #f7fafc;
		transition: transform 0.2s;
	}

	.feature:hover {
		transform: translateY(-4px);
		box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
	}

	.icon {
		font-size: 3rem;
		margin-bottom: 1rem;
	}

	.feature h4 {
		color: #667eea;
		margin-bottom: 0.5rem;
	}

	.feature p {
		color: #4a5568;
		font-size: 0.9rem;
	}

	footer {
		text-align: center;
		color: white;
		margin-top: 3rem;
		padding: 2rem;
		opacity: 0.9;
	}

	@media (max-width: 768px) {
		h1 {
			font-size: 2rem;
		}

		.hero {
			padding: 1.5rem;
		}

		.hero-content h2 {
			font-size: 1.5rem;
		}

		.feature-grid {
			grid-template-columns: 1fr;
		}
	}
</style>
