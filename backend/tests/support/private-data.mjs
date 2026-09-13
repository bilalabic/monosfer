import { ObjectId } from 'mongodb';
import { randomBytes } from 'node:crypto';
export const privateSecrets = ['PRIVATE_ADDRESS', 'PRIVATE_PHONE', 'PRIVATE_CODE', 'PRIVATE_EVIDENCE', 'PRIVATE_PUSH'];
export function privateFixtures() {
  const customer = `0x${randomBytes(20).toString('hex')}`;
  const courier = `0x${randomBytes(20).toString('hex')}`;
  const delivery = { _id: new ObjectId(), customer, acceptedCourier: courier, status: 'Accepted',
    pickup: { address: 'PRIVATE_ADDRESS', lat: 41, lng: 29, contactPhone: 'PRIVATE_PHONE' },
    dropoff: { address: 'PRIVATE_ADDRESS', lat: 40, lng: 28, deliveryCode: 'PRIVATE_CODE', recipientPhone: 'PRIVATE_PHONE', recipientWallet: customer },
    network: 'monad-testnet', onChainRequestId: 42, maxBudget: '1000000000000000000', packageType: 'small', urgency: 'standard', createdAt: new Date(), notes: 'PRIVATE_EVIDENCE' };
  const dispute = { _id: new ObjectId(), deliveryId: delivery._id, status: 'open', initiator: customer, respondent: courier,
    evidence: [{ type: 'gps_log', submitter: customer, content: 'PRIVATE_EVIDENCE', ipfsHash: 'PRIVATE_EVIDENCE' }], description: 'PRIVATE_EVIDENCE' };
  const user = { _id: new ObjectId(), walletAddress: courier, email: 'EXCLUDED_EMAIL', phone: 'EXCLUDED_PHONE',
    courierProfile: { location: { lat: 41, lng: 29, updatedAt: new Date() } }, pushToken: 'PRIVATE_PUSH' };
  return { customer, courier, delivery, dispute, user };
}
export async function* fixtureItems(fixtures) {
  yield { collection: 'deliveries', document: fixtures.delivery };
  yield { collection: 'disputes', document: fixtures.dispute, parent: fixtures.delivery };
  yield { collection: 'users', document: fixtures.user };
}
