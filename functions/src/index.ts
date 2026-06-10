import { setGlobalOptions } from 'firebase-functions/v2';
import './admin';

setGlobalOptions({ region: 'us-central1' });

export { joinGroupByInviteCode } from './callables/joinGroupByInviteCode';
export { cleanupAnonUidArtifacts } from './callables/cleanupAnonUidArtifacts';
export { deleteAccount } from './callables/deleteAccount';
export { deleteGroup } from './callables/deleteGroup';
export { leaveGroup } from './callables/leaveGroup';
export { removeMember } from './callables/removeMember';
export {
  eventWriteRateMonitor,
  groupSettlementWriteRateMonitor,
  groupActivityWriteRateMonitor,
} from './triggers/writeRateMonitor';
export {
  eventSettlementNotifier,
  groupSettlementNotifier,
} from './triggers/settlementNotifier';
export { expenseAuditLogger } from './triggers/expenseAuditLogger';
export {
  eventModuleBalanceAggregator,
  groupSettlementBalanceAggregator,
  eventBalanceAggregator,
  memberBalanceAggregator,
} from './triggers/balanceAggregator';
export { deletionReaper } from './scheduled/deletionReaper';
