export function profileInitials(name: string): string {
  return name.replace(/\([^)]*\)/g, '').trim().split(/\s+/).slice(0, 2).map(part => part[0]).join('') || '?'
}

export function shortWallet(address: string): string {
  return `${address.slice(0, 8)}…${address.slice(-6)}`
}
