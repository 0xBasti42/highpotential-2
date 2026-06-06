<script lang="ts">
	import { fade, fly } from 'svelte/transition';
	import { cubicOut } from 'svelte/easing';
	import { account } from '$lib/state/account.svelte';
	import { auth } from '$lib/state/auth.svelte';
	import { truncateAddress } from '$lib/utils/address';

	/* Tracks which row was just copied so the row's trailing icon can
	   flip to a check briefly. Single string is enough because the user
	   can only have one most-recent copy at a time. */
	let copiedKey = $state<string | null>(null);
	let copiedTimer: ReturnType<typeof setTimeout> | null = null;

	async function copy(value: string, key: string) {
		try {
			await navigator.clipboard.writeText(value);
			copiedKey = key;
			if (copiedTimer) clearTimeout(copiedTimer);
			copiedTimer = setTimeout(() => (copiedKey = null), 1500);
		} catch {
			/* Clipboard API can reject in insecure contexts or when the
			   page isn't focused. Silent fail keeps the UI usable;
			   we'll surface real errors if/when we add a toast layer. */
		}
	}

	function handleSignOut() {
		account.close();
		auth.signOut();
	}

	function onKeydown(event: KeyboardEvent) {
		if (event.key === 'Escape' && account.isOpen) {
			account.close();
		}
	}
</script>

<svelte:window onkeydown={onKeydown} />

{#if account.isOpen && auth.isSignedIn}
	<div
		class="account-overlay"
		role="presentation"
		onclick={() => account.close()}
		transition:fade={{ duration: 180, easing: cubicOut }}
	></div>

	<aside
		id="app-account-sidebar"
		class="account"
		aria-label="Account"
		transition:fly={{ x: 320, duration: 260, easing: cubicOut }}
	>
		<header class="account-header">
			<div class="header-icon">
				<i class="fa-solid fa-wallet" aria-hidden="true"></i>
			</div>
			<div class="header-text">
				<p class="header-email">{auth.email}</p>
				<p class="header-status">
					<span class="status-dot" aria-hidden="true"></span>
					Connected
				</p>
			</div>
		</header>

		<nav class="account-body">
			<section class="account-section">
				<h6 class="label-eyebrow section-title">Wallet</h6>
				<ul class="address-list">
					<li>
						<button
							type="button"
							class="address-row"
							onclick={() => copy(auth.smartWallet!, 'smart')}
						>
							<div class="address-text">
								<span class="label-eyebrow row-label">Smart Wallet</span>
								<code class="row-addr">{truncateAddress(auth.smartWallet!)}</code>
							</div>
							<i
								class="fa-solid row-icon {copiedKey === 'smart'
									? 'fa-check row-icon--copied'
									: 'fa-copy'}"
								aria-hidden="true"
							></i>
						</button>
					</li>
					<li>
						<button
							type="button"
							class="address-row"
							onclick={() => copy(auth.ownerEoa!, 'eoa')}
						>
							<div class="address-text">
								<span class="label-eyebrow row-label">Owner EOA</span>
								<code class="row-addr">{truncateAddress(auth.ownerEoa!)}</code>
							</div>
							<i
								class="fa-solid row-icon {copiedKey === 'eoa'
									? 'fa-check row-icon--copied'
									: 'fa-copy'}"
								aria-hidden="true"
							></i>
						</button>
					</li>
				</ul>
			</section>

			<section class="account-section">
				<h6 class="label-eyebrow section-title">Settings</h6>
				<p class="placeholder">Coming soon</p>
			</section>
		</nav>

		<footer class="account-footer">
			<button type="button" class="signOut" onclick={handleSignOut}>
				<i class="fa-solid fa-arrow-right-from-bracket" aria-hidden="true"></i>
				<span>Sign out</span>
			</button>
		</footer>
	</aside>
{/if}

<style>
	/* Backdrop + panel recipe mirrors the main Sidebar so the two
	   sliding surfaces feel like siblings: faint white tint at 0.04
	   alpha + 2px blur, no shadow on the panel itself. */
	.account-overlay {
		position: fixed;
		inset: 0;
		z-index: 90;
		background-color: rgba(255, 255, 255, 0.04);
		backdrop-filter: blur(2px);
		-webkit-backdrop-filter: blur(2px);
		cursor: pointer;
	}

	/* Anchored to the right edge — slides in from outside the viewport
	   so the entry direction matches its origin (the wallet pill at
	   header-right). Border on the LEFT edge (vs the main sidebar's
	   right edge) for the same reason. */
	.account {
		position: fixed;
		top: 0;
		right: 0;
		height: 100vh;
		width: 320px;
		z-index: 100;
		display: flex;
		flex-direction: column;
		background-color: var(--color-surface-elevated);
		border-left: 1px solid var(--color-border);
		overflow: hidden;
	}

	/* ---- Header (avatar + email + status) ---- */
	.account-header {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 22px 18px 18px;
		border-bottom: 1px solid var(--color-border);
	}

	/* Same teal-gradient pill as the header wallet trigger — keeps the
	   "this surface belongs to that trigger" lineage visible. */
	.header-icon {
		flex-shrink: 0;
		width: 36px;
		height: 36px;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		background: linear-gradient(
			to left,
			var(--color-primary-light) -20%,
			var(--color-primary) 100%
		);
		border-radius: var(--radius-pill);
		color: var(--color-text-inverse);
		font-size: 14px;
	}

	.header-text {
		min-width: 0;
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 2px;
	}

	.header-email {
		margin: 0;
		font-size: var(--text-sm);
		color: var(--color-text);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.header-status {
		margin: 0;
		font-size: 11px;
		color: var(--color-text-muted);
		display: inline-flex;
		align-items: center;
		gap: 6px;
	}

	.status-dot {
		width: 6px;
		height: 6px;
		border-radius: 50%;
		background-color: var(--color-primary-light);
		box-shadow: 0 0 6px var(--color-primary-light);
	}

	/* ---- Body sections ---- */
	.account-body {
		flex: 1 1 auto;
		min-height: 0;
		overflow-y: auto;
		padding: 18px 0;
		display: flex;
		flex-direction: column;
		gap: 22px;
	}

	.account-section {
		display: flex;
		flex-direction: column;
		gap: 10px;
		padding: 0 18px;
	}

	.section-title {
		color: var(--color-text-faded);
	}

	/* ---- Address rows ---- */
	.address-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 8px;
	}

	/* Same card-on-surface treatment used by the modal's wallet card,
	   but clickable. Border brightens on hover (mirrors the Trade
	   .asset-dropdown pattern). */
	.address-row {
		all: unset;
		box-sizing: border-box;
		width: 100%;
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 12px;
		padding: 10px 12px;
		background-color: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		cursor: pointer;
		transition: border-color var(--transition-base);
	}

	.address-row:hover {
		border-color: var(--color-border-strong);
	}

	.address-row:active {
		opacity: 0.85;
	}

	.address-text {
		min-width: 0;
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 4px;
	}

	.row-label {
		font-size: 10px;
	}

	.row-addr {
		font-family: ui-monospace, 'JetBrains Mono', 'SFMono-Regular', Menlo, monospace;
		font-size: 12px;
		color: var(--color-text);
	}

	.row-icon {
		flex-shrink: 0;
		font-size: 12px;
		color: var(--color-text-muted);
		transition: color var(--transition-base);
	}

	.address-row:hover .row-icon {
		color: var(--color-text);
	}

	/* Flipped to the success teal so the "copied" confirmation reads
	   as a positive state rather than a hover state. Reverts to the
	   normal icon colour when copiedKey resets. */
	.row-icon--copied,
	.address-row:hover .row-icon--copied {
		color: var(--color-primary-light);
	}

	.placeholder {
		margin: 0;
		padding: 10px 12px;
		font-size: 12px;
		color: var(--color-text-faded);
		font-style: italic;
	}

	/* ---- Footer (sign out) ---- */
	.account-footer {
		flex: 0 0 auto;
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 12px 18px;
		border-top: 1px solid var(--color-border);
	}

	/* Quiet destructive action: muted text by default, error-coloured
	   on hover so the user gets a clear "this is a removal" cue before
	   committing. Press dims for tactile feedback. */
	.signOut {
		all: unset;
		display: inline-flex;
		align-items: center;
		gap: 10px;
		padding: 8px 14px;
		font-size: var(--text-sm);
		color: var(--color-text-muted);
		border-radius: var(--radius-pill);
		cursor: pointer;
		transition: color var(--transition-base);
	}

	.signOut:hover {
		color: var(--color-error);
	}

	.signOut:active {
		opacity: 0.7;
	}
</style>
