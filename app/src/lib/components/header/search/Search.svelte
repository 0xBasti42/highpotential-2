<script lang="ts">
    import Searchbox from './searchbox/Searchbox.svelte';
    import { settings, type Stablecoin } from '$lib/state/settings.svelte';
    import { currencyOf } from '$lib/utils/currency';

    /* Fiat-fiat row config keyed on the user's default stablecoin. We
       can't render `USD/USD` when the default is already USD, so each
       default carries its own foreign counterpart plus a flipped rate
       expressed in the default's units (the value is always prefixed
       with `currency.sign`, so the rate string must match that side).

       Driven off the `Stablecoin` union so adding a new fiat default
       in `settings.svelte.ts` produces a type error here until we
       pick its counterpart + rate.

       TODO: the rate strings are placeholders. Wire to the live FX
       feed once the rates store lands — the `$derived` shape below
       will pick the new values up without further restructuring. */
    const FX_BY_DEFAULT: Record<Stablecoin, { foreign: Stablecoin; rate: string }> = {
        TGBP: { foreign: 'USDC', rate: '0.7531' },
        USDC: { foreign: 'TGBP', rate: '1.3278' },
        EURC: { foreign: 'USDC', rate: '1.07122' }
    };

    /* `$derived` so flipping the default stablecoin in the account
       sidebar instantly relabels the strip and reprices it in the new
       currency sign — same pattern as TokenInfo.svelte. */
    const currency = $derived(currencyOf(settings.defaultStablecoin));
    const fx = $derived(FX_BY_DEFAULT[settings.defaultStablecoin]);
    const foreign = $derived(currencyOf(fx.foreign));

    const rates = $derived([
        { label: `${currency.code}/${foreign.code}`, value: `${currency.sign} ${fx.rate}` },
        { label: `SETH/${currency.code}`, value: `${currency.sign} 15.490` },
        { label: `ETH/${currency.code}`, value: `${currency.sign} 1549.39` }
        // { label: `HPI-TOTAL/${currency.code}`, value: `${currency.sign} 1150.19` }
    ]);
</script>

<div class="search">
    <Searchbox />
    <div class="prices">
        {#each rates as rate (rate.label)}
            <div class="exchange-rate">
                <p class="exchange-rate-label label-eyebrow">{rate.label}</p>
                <p class="exchange-rate-value">{rate.value}</p>
            </div>
        {/each}
    </div>
</div>

<style>
	.search {
        background-color: var(--color-surface-elevated);
		border-bottom: 1px solid var(--color-border);
        height: 60px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        box-shadow: 0 0 10px 0 rgba(0, 0, 0, 0.1);
	}

	.prices {
        flex: 0 0 var(--side-width);
		background-color: var(--color-surface-elevated);
		height: 100%;
        display: flex;
        align-items: center;
        gap: 25px;
        padding-left: 20px;
        border-left: 1px solid var(--color-border);
        overflow: hidden;
	}

    .exchange-rate {
        display: flex;
        flex-direction: column;
        align-items: flex-start;
        justify-content: center;
        gap: 4px;
        flex-shrink: 0;
        cursor: pointer;
        transition: opacity var(--transition-base);
        margin-bottom: 2px;
    }

    .prices:hover .exchange-rate {
        opacity: 0.4;
    }

    .prices:hover .exchange-rate:hover {
        opacity: 1;
    }

    .prices:hover .exchange-rate:active {
        opacity: 0.8;
    }

    .exchange-rate-label {
        margin-top: 2px;
        line-height: 1;
        font-size: 9px;
    }

    .exchange-rate-value {
        font-size: 10px;
        font-weight: 400;
        letter-spacing: 1px;
        color: var(--color-text);
        font-size: var(--text-sm);
        line-height: 1;
    }
</style>