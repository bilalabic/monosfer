/** Shared across the navbar and any section that wants to hide it during a full-screen moment (e.g. a pinned scrollytelling panel). */
export function useNavbarVisibility() {
  return useState<boolean>('navbar-hidden', () => false)
}
