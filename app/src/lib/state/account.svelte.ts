/**
 * Shared open/close state for the right-hand account sidebar.
 *
 * Mirrors the `sidebar` (main nav) and `signup` (auth modal) singleton
 * pattern. The trigger lives in PrimaryHeaderBar (the wallet pill in
 * the signed-in state); the panel itself is mounted at the layout root
 * alongside the other overlays.
 *
 * Independent from `auth` so the open/close state is a UI concern only —
 * AccountSidebar guards its own render on `auth.isSignedIn` so the
 * panel unmounts if the user signs out while it's open.
 */

let _isOpen = $state(false);

export const account = {
	get isOpen() {
		return _isOpen;
	},
	open() {
		_isOpen = true;
	},
	close() {
		_isOpen = false;
	},
	toggle() {
		_isOpen = !_isOpen;
	}
};
