import test from 'node:test'
import assert from 'node:assert/strict'
import User from '../src/models/User.js'
import CourierStats from '../src/models/CourierStats.js'
import Delivery from '../src/models/Delivery.js'
import Bid from '../src/models/Bid.js'
import { listCouriers } from '../src/services/courierService.js'

function queryMatchesRole(query, user) {
  const allowedRoles = query?.role?.$in
  return !allowedRoles || allowedRoles.includes(user.role)
}

test('listCouriers includes customer users because every user can be a courier', async () => {
  const originalUserFind = User.find
  const originalStatsFind = CourierStats.find
  const originalDeliveryFind = Delivery.find
  const originalBidFind = Bid.find

  const users = [
    {
      _id: { toString: () => 'customer-id' },
      walletAddress: '0x1111111111111111111111111111111111111111',
      name: 'Normal Kullanici',
      role: 'customer',
      createdAt: new Date('2026-01-01T00:00:00.000Z'),
    },
    {
      _id: { toString: () => 'courier-id' },
      walletAddress: '0x2222222222222222222222222222222222222222',
      name: 'Kayitli Kurye',
      role: 'courier',
      courierProfile: { specialties: ['Gida'] },
      createdAt: new Date('2026-01-02T00:00:00.000Z'),
    },
  ]

  User.find = query => ({
    select: () => ({
      lean: async () => users.filter(user => queryMatchesRole(query, user)),
    }),
  })
  CourierStats.find = () => ({
    lean: async () => [],
  })
  Delivery.find = () => ({
    select: () => ({
      lean: async () => [],
    }),
  })
  Bid.find = () => ({
    select: () => ({
      lean: async () => [],
    }),
  })

  try {
    const couriers = await listCouriers()

    assert.deepEqual(
      couriers.map(courier => courier.name),
      ['Normal Kullanici', 'Kayitli Kurye'],
    )
  } finally {
    User.find = originalUserFind
    CourierStats.find = originalStatsFind
    Delivery.find = originalDeliveryFind
    Bid.find = originalBidFind
  }
})

test('listCouriers derives delivery, percentage, and earnings stats from completed deliveries', async () => {
  const originals = {
    userFind: User.find,
    statsFind: CourierStats.find,
    deliveryFind: Delivery.find,
    bidFind: Bid.find,
  }
  const courierWallet = '0x2222222222222222222222222222222222222222'
  const selectedBidId = { toString: () => 'bid-id' }

  User.find = () => ({
    select: () => ({
      lean: async () => [
        {
          _id: { toString: () => 'courier-id' },
          walletAddress: courierWallet,
          name: 'Kayitli Kurye',
          role: 'courier',
          createdAt: new Date('2026-01-02T00:00:00.000Z'),
        },
      ],
    }),
  })
  CourierStats.find = () => ({
    lean: async () => [],
  })
  Delivery.find = () => ({
    select: () => ({
      lean: async () => [
        {
          selectedBidId,
          deliveredAt: new Date(),
          deadline: new Date(Date.now() + 60_000),
        },
      ],
    }),
  })
  Bid.find = () => ({
    select: () => ({
      lean: async () => [
        {
          _id: selectedBidId,
          courier: courierWallet,
          amount: '12.5',
        },
      ],
    }),
  })

  try {
    const [courier] = await listCouriers()

    assert.equal(courier.totalDeliveries, 1)
    assert.equal(courier.onTimeRate, 100)
    assert.equal(courier.weeklyDeliveries, 1)
    assert.equal(courier.weeklyEarnings, 12.5)
    assert.equal(courier.monthlyEarnings, 12.5)
  } finally {
    User.find = originals.userFind
    CourierStats.find = originals.statsFind
    Delivery.find = originals.deliveryFind
    Bid.find = originals.bidFind
  }
})
