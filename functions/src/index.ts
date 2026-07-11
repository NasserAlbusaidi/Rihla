import { setGlobalOptions } from 'firebase-functions/v2';
import './admin';

setGlobalOptions({ region: 'us-central1' });

export { joinGroupByInviteCode } from './callables/joinGroupByInviteCode';
export { deleteAccount } from './callables/deleteAccount';
export { deleteGroup } from './callables/deleteGroup';
export { leaveGroup } from './callables/leaveGroup';
export { removeMember } from './callables/removeMember';
export { addShadowMember } from './callables/addShadowMember';
export { requestClaimShadow } from './callables/requestClaimShadow';
export { decideClaimRequest } from './callables/decideClaimRequest';
export { listMyClaimRequests } from './callables/listMyClaimRequests';
export { listGroupClaimRequests } from './callables/listGroupClaimRequests';
export { listUnclaimedShadows } from './callables/listUnclaimedShadows';
export { correctSettlement } from './callables/correctSettlement';
export { correctLogicalSettleUp } from './callables/correctLogicalSettleUp';
export { recordSettlement } from './callables/recordSettlement';
export {
  eventWriteRateMonitor,
  groupActivityWriteRateMonitor,
} from './triggers/writeRateMonitor';
export {
  eventSettlementNotifier,
  groupSettlementNotifier,
} from './triggers/settlementNotifier';
export { expenseAuditLogger } from './triggers/expenseAuditLogger';
export { expenseNotifier } from './triggers/expenseNotifier';
export { eventNotifier } from './triggers/eventNotifier';
export { claimRequestNotifier } from './triggers/claimRequestNotifier';
export {
  eventModuleBalanceAggregator,
  groupSettlementBalanceAggregator,
  eventBalanceAggregator,
  memberBalanceAggregator,
} from './triggers/balanceAggregator';
export { deletionReaper } from './scheduled/deletionReaper';
export { balanceReconciler } from './scheduled/balanceReconciler';
export { deleteGroupLockReaper } from './scheduled/deleteGroupLockReaper';
export { claimShadowLockReaper } from './scheduled/claimShadowLockReaper';
export { departureLockReaper } from './scheduled/departureLockReaper';
