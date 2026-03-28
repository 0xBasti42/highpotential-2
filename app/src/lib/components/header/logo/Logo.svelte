<script lang="ts">
</script>

<div class="logo">
	<img src="/brand/icon.png" alt="Logo" />
</div>

<style>
	.logo {
		width: auto;
		height: 25px;
		display: flex;
		align-items: center;
		justify-content: flex-start;
		gap: 10px;
		box-shadow: 0 0 10px 0 rgba(0, 0, 0, 0.1);
		cursor: pointer;
	}

	.logo img {
		width: 25px;
		height: 25px;
		border-radius: 5px;
		border: 1px solid var(--color-border);
		transition: border var(--transition-base);
	}

	.logo:hover img {
		border: 1px solid var(--color-border-strong);
	}

	.logo:active {
		animation: logo-bounce-right 0.2s ease-out forwards;
	}

	@keyframes logo-bounce-right {
		0% {
			transform: translateX(0);
		}
		50% {
			transform: translateX(3px);
		}
		100% {
			transform: translateX(0);
		}
	}
</style>