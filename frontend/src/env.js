// Single source of truth for "is this a local dev build" checks (e.g. to hide
// the Dev Panel from the production build shipped to GitHub Pages). Vite
// replaces import.meta.env.DEV with a literal `false` in production builds,
// so anything gated behind IS_DEV never renders for real users.
export const IS_DEV = import.meta.env.DEV;
