import mongoose from 'mongoose'

const bidSchema = new mongoose.Schema(
  {
    // İlişkiler
    deliveryId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Delivery',
      required: true,
      index: true,
    },
    onChainRequestId: { type: Number, index: true },
    courier: { type: String, required: true, lowercase: true, index: true },

    // Teklif detayları
    amount: { type: String, required: true }, // token miktarı bigint → string
    estimatedMinutes: { type: Number, required: true, min: 1, max: 480 },

    // Durum
    isSelected: { type: Boolean, default: false, index: true },
    isRefunded: { type: Boolean, default: false }, // deposit iade edildi mi

    // Blockchain referansı
    txHash: { type: String },
    network: {
      type: String,
      enum: ['monad-testnet', 'monad-mainnet', 'localhost'],
      default: 'monad-testnet',
    },

    // Teklif depositi (stake'den bloke edilen)
    depositAmount: { type: String }, // BID_DEPOSIT
  },
  {
    timestamps: true,
    versionKey: false,
  },
)

bidSchema.index({ deliveryId: 1, courier: 1 }, { unique: true }) // bir kuryeden bir teslimat için tek teklif
bidSchema.index({ deliveryId: 1, isSelected: 1 })

export default mongoose.model('Bid', bidSchema)
