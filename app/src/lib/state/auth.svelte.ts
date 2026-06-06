/**
 * Shared auth / session state for the signed-in user.
 *
 * Single source of truth for "is the user signed in?" and the addresses
 * derived from their Turnkey sub-org. Read by the header (to swap the
 * Connect CTA for an account chip), by Trade (to swap the Connect button
 * for a Swap button), and by any future surface that gates on auth.
 *
 * Written by SignupModal on a successful OTP verification.
 *
 * Mirrors the `sidebar` / `signup` singleton pattern: private `_session`
 * `$state`, exported object with getters + mutator methods so call sites
 * can `auth.signIn(...)` instead of importing setter symbols.
 *
 * Currently in-memory only — sessions do not survive a page refresh. Once
 * the real Turnkey SDK is wired in, the @turnkey/sdk-browser session
 * storage (IndexedDB) becomes the source of truth and we rehydrate this
 * store from it on app mount.
 */

export type AuthSession = {
	email: string;
	ownerEoa: `0x${string}`;
	smartWallet: `0x${string}`;
};

let _session = $state<AuthSession | null>(null);

export const auth = {
	get session() {
		return _session;
	},
	get isSignedIn() {
		return _session !== null;
	},
	get email() {
		return _session?.email ?? null;
	},
	get ownerEoa() {
		return _session?.ownerEoa ?? null;
	},
	get smartWallet() {
		return _session?.smartWallet ?? null;
	},
	signIn(session: AuthSession) {
		_session = session;
	},
	signOut() {
		_session = null;
	}
};
