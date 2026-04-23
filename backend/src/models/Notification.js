import mongoose from 'mongoose'

const notificationSchema = new mongoose.Schema(
  {
    recipient: { type: String, required: true, lowercase: true, index: true },
    type: {
      type: String,
      required: true,
      enum: [
        'bid_received',       // müşteri: yeni teklif geldi
        'bid_accepted',       // kurye: teklifin kabul edildi
        'bid_rejected',       // kurye: teklifin seçilmedi
        'pickup_confirmed',   // müşteri: ürün alındı
        'delivery_confirmed', // kurye: teslimat onaylandı
        'payment_released',   // kurye: ödeme hesabına aktarıldı
        'rating_request',     // müşteri: lütfen puanla
        'rating_received',    // kurye: puan aldın
        'badge_earned',       // kullanıcı: rozet kazandın
        'reward_distributed', // kurye: leaderboard ödülün dağıtıldı
        'dispute_raised',     // ilgili taraf: anlaşmazlık açıldı
        'dispute_resolved',   // ilgili taraf: anlaşmazlık sonuçlandı
        'delivery_cancelled', // ilgili taraf: teslimat iptal edildi
        'system',             // genel sistem bildirimi
      ],
      index: true,
    },
    title: { type: String, required: true },
    body: { type: String, required: true },

    // İlgili varlık referansı
    data: {
      deliveryId: { type: mongoose.Schema.Types.ObjectId, ref: 'Delivery' },
      bidId: { type: mongoose.Schema.Types.ObjectId, ref: 'Bid' },
      disputeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Dispute' },
      badgeType: { type: String },
      amount: { type: String }, // ödeme miktarı
    },

    isRead: { type: Boolean, default: false, index: true },
    readAt: { type: Date },
  },
  {
    timestamps: true,
    versionKey: false,
  },
)

notificationSchema.index({ recipient: 1, isRead: 1, createdAt: -1 })

// 90 gün sonra otomatik sil (TTL index)
notificationSchema.index({ createdAt: 1 }, { expireAfterSeconds: 60 * 60 * 24 * 90 })

export default mongoose.model('Notification', notificationSchema)
