import mongoose from 'mongoose'

const timelineStepSchema = new mongoose.Schema(
  {
    step: {
      type: String,
      enum: ['created', 'escrow', 'accepted', 'pickup', 'transit', 'notification', 'delivered', 'cancelled'],
    },
    label: { type: String },
    completed: { type: Boolean, default: false },
    txHash: { type: String },
    timestamp: { type: Date },
  },
  { _id: false },
)

const deliverySchema = new mongoose.Schema(
  {
    // Blockchain bağlantısı
    onChainRequestId: { type: Number, index: true, sparse: true },
    creationTxHash: { type: String },
    network: {
      type: String,
      enum: ['monad-testnet', 'monad-mainnet', 'localhost'],
      default: 'monad-testnet',
    },

    // Başlık (UI display)
    title: { type: String },

    // Taraflar (wallet address)
    customer: { type: String, required: true, lowercase: true, index: true },
    acceptedCourier: { type: String, lowercase: true, index: true, sparse: true },

    // Adres bilgileri — privacy gereği SADECE off-chain burada tutulur
    // Blockchain'de sadece hash'leri var
    pickup: {
      address: { type: String, required: true },
      lat: { type: Number, required: true },
      lng: { type: Number, required: true },
      contactPhone: { type: String },
    },
    dropoff: {
      address: { type: String, required: true },
      lat: { type: Number, required: true },
      lng: { type: Number, required: true },
      recipientType: {
        type: String,
        enum: ['person', 'business', 'office', 'other'],
        default: 'person',
      },
      recipientName: { type: String },
      businessName: { type: String },
      contactPerson: { type: String },
      orderRef: { type: String },
      department: { type: String },
      recipientNote: { type: String },
      recipientPhone: { type: String },
      recipientWallet: { type: String, lowercase: true },
      deliveryCode: { type: String },
      deliveryConfirmedBy: {
        type: String,
        enum: ['sender_wallet', 'recipient_code'],
      },
      deliveryConfirmedAt: { type: Date },
    },

    // Kargo detayları
    packageType: {
      type: String,
      enum: ['document', 'food', 'small', 'medium', 'large'],
      required: true,
    },
    urgency: {
      type: String,
      enum: ['standard', 'express', 'instant'],
      required: true,
    },
    weight: { type: String }, // örn: "2.5 kg"
    notes: { type: String, maxlength: 500 },

    // Ödeme (token miktarları bigint → string)
    maxBudget: { type: String, required: true },
    acceptedAmount: { type: String },
    escrowBalance: { type: String },

    // Durum
    status: {
      type: String,
      enum: ['OpenForBids', 'Accepted', 'InTransit', 'Delivered', 'Cancelled'],
      default: 'OpenForBids',
      index: true,
    },

    // Teklif referansı
    selectedBidId: { type: mongoose.Schema.Types.ObjectId, ref: 'Bid' },

    // Zaman damgaları
    deadline: { type: Date, index: true },
    acceptedAt: { type: Date },
    pickedUpAt: { type: Date },
    deliveredAt: { type: Date },
    cancelledAt: { type: Date },

    // Teslimat zaman çizelgesi (UI için hazır)
    timeline: [timelineStepSchema],

    // Puanlama
    rating: { type: Number, min: 1, max: 5 },
    ratingComment: { type: String },
    ratingCategories: {
      speed: { type: Number, min: 1, max: 5 },
      behavior: { type: Number, min: 1, max: 5 },
      packageCondition: { type: Number, min: 1, max: 5 },
      communication: { type: Number, min: 1, max: 5 },
    },
    isRated: { type: Boolean, default: false },
    ratedAt: { type: Date },

    // Anlaşmazlık
    hasDispute: { type: Boolean, default: false },
    disputeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Dispute' },

    // Mesafe (km)
    distanceKm: { type: Number },
  },
  {
    timestamps: true,
    versionKey: false,
  },
)

// Composite index — aktif teslimatları hız için
deliverySchema.index({ status: 1, createdAt: -1 })
deliverySchema.index({ customer: 1, status: 1 })
deliverySchema.index({ acceptedCourier: 1, status: 1 })
// Geo index — yakın teslimat arama için
deliverySchema.index({ 'pickup.lat': 1, 'pickup.lng': 1 })

export default mongoose.model('Delivery', deliverySchema)
