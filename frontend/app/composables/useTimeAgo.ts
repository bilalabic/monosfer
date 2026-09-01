export function timeAgo(dateStr: string | null, options?: { suffix?: string; unknownLabel?: string }): string {
  const suffix = options?.suffix ? ` ${options.suffix}` : ''
  if (!dateStr) return options?.unknownLabel ?? `Az önce${suffix}`

  const diffMinutes = Math.floor((Date.now() - new Date(dateStr).getTime()) / 60000)
  if (diffMinutes < 1) return `Az önce${suffix}`
  if (diffMinutes < 60) return `${diffMinutes} dk önce${suffix}`
  return `${Math.floor(diffMinutes / 60)} sa önce${suffix}`
}
