import mongoose from 'mongoose'

const userSchema = new mongoose.Schema(
  {
    walletAddress: {
      type: String,
      required: true,
      unique: true,
      lowercase: true,
      index: true,
    },
    role: {
      type: String,
      enum: ['customer', 'courier', 'both'],
      default: 'both',
    },
    name: { type: String, trim: true },
    phone: { type: String, trim: true },
    email: { type: String, lowercase: true, trim: true },
    avatar: { type: String },
    isVerified: { type: Boolean, default: false },
    isSuspended: { type: Boolean, default: false },

    // Kurye profil alanları — sadece role courier/both olduğunda dolu
    courierProfile: {
      isRegistered: { type: Boolean, default: false },
      stakeAmount: { type: String, default: '0' }, // bigint → string
      vehicleType: {
        type: String,
        enum: ['bicycle', 'motorcycle', 'car', 'on_foot'],
      },
      specialties: [{ type: String }], // ['Elektronik', 'Gıda', ...]
      bio: { type: String, maxlength: 500 },
      regions: [{ type: String }], // hizmet verdiği mahalleler
      isOnline: { type: Boolean, default: false },
      lastSeenAt: { type: Date },
      location: {
        lat: { type: Number },
        lng: { type: Number },
        updatedAt: { type: Date },
      },
    },

    // Bildirim tercihleri
    notificationPrefs: {
      push: { type: Boolean, default: true },
      email: { type: Boolean, default: false },
      sms: { type: Boolean, default: true },
    },

    // Push notification token (mobil için)
    pushToken: { type: String },

    nonce: { type: String }, // wallet imza nonce (auth için)
  },
  {
    timestamps: true,
    versionKey: false,
  },
)

userSchema.index({ 'courierProfile.isOnline': 1, 'courierProfile.regions': 1 })

export default mongoose.model('User', userSchema)
