import mongoose from 'mongoose'

const badgeSchema = new mongoose.Schema(
  {
    tokenId: { type: Number, required: true, unique: true, index: true },
    owner: { type: String, required: true, lowercase: true, index: true },
    badgeType: {
      type: String,
      required: true,
      enum: [
        'FirstDelivery',
        'HundredClub',
        'ThousandClub',
        'WeeklyChampion',
        'MonthlyChampion',
        'SeasonChampion',
        'SpeedChampion',
        'PerfectRating',
        'StreakMaster',
        'FairJury',
        'RegionLord',
        // Gönderici rozetleri
        'FirstShipment',
        'LoyalCustomer',
        'GenerousRater',
        'VIP',
      ],
    },
    rarity: {
      type: String,
      enum: ['common', 'uncommon', 'rare', 'epic', 'legendary'],
      required: true,
    },

    // Metadata (IPFS veya statik)
    name: { type: String },
    description: { type: String },
    imageUri: { type: String },

    // Blockchain referans
    txHash: { type: String },
    network: {
      type: String,
      enum: ['monad-testnet', 'monad-mainnet', 'localhost'],
      default: 'monad-testnet',
    },

    mintedAt: { type: Date, required: true },

    // Hangi dönem için kazanıldı (haftalık/aylık şampiyonluk için)
    periodLabel: { type: String }, // örn: "2026-W17", "2026-04"
  },
  {
    timestamps: true,
    versionKey: false,
  },
)

badgeSchema.index({ owner: 1, badgeType: 1 })

export default mongoose.model('Badge', badgeSchema)
