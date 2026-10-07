const labels: Record<string, string> = {
  Bidding: 'Teklif bekliyor',
  AwaitingFunding: 'Ödeme bekliyor',
  ReadyForPickup: 'Teslim almaya hazır',
  InTransit: 'Yolda',
  DeliveredPending: 'Teslim onayı bekliyor',
  Completed: 'Tamamlandı',
  ReturnRequired: 'İade bekliyor',
  Returned: 'İade edildi',
  Cancelled: 'İptal edildi',
  Expired: 'Süresi doldu',
  Disputed: 'Uyuşmazlık',
  Resolved: 'Çözüldü',
}

export function deliveryStateLabel(state: string): string {
  return labels[state] || state
}
