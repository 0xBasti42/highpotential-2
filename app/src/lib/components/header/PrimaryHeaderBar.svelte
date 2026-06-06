<script lang="ts">
	import Logo from './logo/Logo.svelte';
	import MainMenu from './main-menu/MainMenu.svelte';
	import NetworkSelector from './network-selector/NetworkSelector.svelte';
	import { signup } from '$lib/state/signup.svelte';
	import { auth } from '$lib/state/auth.svelte';
	import { account } from '$lib/state/account.svelte';
</script>

<div class="header">
    <div class="header-left">
        <Logo />
        <MainMenu />
    </div>
    <div class="header-right">
        <div class="header-right-item">
            <NetworkSelector />
        </div>
        <div class="header-right-item">
            {#if auth.smartWallet}
                <button
                    type="button"
                    class="accountButton"
                    aria-label="Open account menu"
                    aria-expanded={account.isOpen}
                    aria-controls="app-account-sidebar"
                    onclick={() => account.toggle()}
                >
                    <i class="fa-solid fa-wallet" aria-hidden="true"></i>
                </button>
            {:else}
                <button type="button" class="button" onclick={() => signup.open()}>Connect</button>
            {/if}
        </div>
    </div>
</div>

<style>
	.header {
        background-color: var(--color-surface-elevated);
		border-bottom: 1px solid var(--color-border);
        height: 50px;
        display: flex;
        align-items: center;
        justify-content: flex-start;
        padding: 0 20px;
        box-shadow: 0 0 10px 0 rgba(0, 0, 0, 0.1);
	}

    .header-left {
        flex: 1;
        display: flex;
        align-items: center;
        justify-content: flex-start;
        gap: 0;
    }

    .header-right {
        flex: 1;
        display: flex;
        align-items: center;
        justify-content: flex-end;
        gap: 10px;
    }

    .header-right-item {
        display: flex;
        flex-direction: row;
        align-items: center;
        justify-content: flex-end;
        gap: 25px;
        cursor: default;
    }

    .button {
        height: 25px;
        width: 142px;
        font-size: 11px;
        transition: all var(--transition-base);
    }

    .button:active {
        opacity: 1;
    }

    /* Signed-in account button. A single teal-gradient wallet-icon pill
       sized to line up with the other header controls (25px tall, same
       as the NetworkSelector trigger and the signed-out Connect button).
       Border radius matches the NetworkSelector pill for visual rhythm.

       Gradient, hover and active treatment are the same recipe as the
       global `button` rule (and Trade.svelte's `.swap-button`): brighten
       + primary-light glow on hover, dim + snap-fast on press. Keeps
       all three CTAs interaction-language consistent. */
    .accountButton {
        all: unset;
        box-sizing: border-box;
        width: 40px;
        height: 25px;
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
        font-size: 12px;
        cursor: pointer;
        transition: all var(--transition-base);
    }

    .accountButton:hover {
        filter: brightness(1.08);
        box-shadow: 0 0 16px -4px color-mix(in oklab, var(--color-primary-light) 40%, transparent);
    }

    .accountButton:active {
        filter: brightness(0.97);
        box-shadow: none;
        transition-duration: 80ms;
    }
</style>