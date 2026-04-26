import { setGlobalOptions } from 'firebase-functions/v2';
import './admin';

setGlobalOptions({ region: 'us-central1' });

export { getSignedUploadUrl } from './callables/getSignedUploadUrl';
export { deleteStorageObject } from './callables/deleteStorageObject';
