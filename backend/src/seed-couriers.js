import mongoose from 'mongoose';
import dotenv from 'dotenv';
import User from './models/User.js';

dotenv.config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/monad';

const KAYSERI_COURIERS = [
  {
    name: 'Ahmet Yılmaz',
    walletAddress: '0x1111111111111111111111111111111111111111',
    role: 'courier',
    courierProfile: {
      isRegistered: true,
      vehicleType: 'motorcycle',
      isOnline: true,
      location: { lat: 38.7205, lng: 35.4826, updatedAt: new Date() }
    }
  },
  {
    name: 'Mehmet Demir',
    walletAddress: '0x2222222222222222222222222222222222222222',
    role: 'courier',
    courierProfile: {
      isRegistered: true,
      vehicleType: 'bicycle',
      isOnline: true,
      location: { lat: 38.7075, lng: 35.5200, updatedAt: new Date() }
    }
  },
  {
    name: 'Ayşe Kaya',
    walletAddress: '0x3333333333333333333333333333333333333333',
    role: 'courier',
    courierProfile: {
      isRegistered: true,
      vehicleType: 'car',
      isOnline: true,
      location: { lat: 38.7150, lng: 35.5050, updatedAt: new Date() }
    }
  },
  {
    name: 'Fatma Şahin',
    walletAddress: '0x4444444444444444444444444444444444444444',
    role: 'courier',
    courierProfile: {
      isRegistered: true,
      vehicleType: 'on_foot',
      isOnline: false,
      location: { lat: 38.6900, lng: 35.4950, updatedAt: new Date() }
    }
  },
  {
    name: 'Can Erkan',
    walletAddress: '0x5555555555555555555555555555555555555555',
    role: 'courier',
    courierProfile: {
      isRegistered: true,
      vehicleType: 'motorcycle',
      isOnline: true,
      location: { lat: 38.7400, lng: 35.4850, updatedAt: new Date() }
    }
  },
  {
    name: 'Selin Yıldız',
    walletAddress: '0x6666666666666666666666666666666666666666',
    role: 'courier',
    courierProfile: {
      isRegistered: true,
      vehicleType: 'bicycle',
      isOnline: true,
      location: { lat: 38.7320, lng: 35.4750, updatedAt: new Date() }
    }
  }
];

async function seed() {
  try {
    await mongoose.connect(MONGODB_URI);
    console.log('Connected to MongoDB');

    for (const courier of KAYSERI_COURIERS) {
      await User.findOneAndUpdate(
        { walletAddress: courier.walletAddress },
        courier,
        { upsert: true, new: true }
      );
      console.log(`Seeded courier: ${courier.name}`);
    }

    console.log('Seeding completed successfully');
    process.exit(0);
  } catch (error) {
    console.error('Seeding failed:', error);
    process.exit(1);
  }
}

seed();
